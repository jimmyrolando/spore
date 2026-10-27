package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"os"
	"sync"
	"time"
)

// `spored files`: the engine of Files' operations (shell/files/FileOps.qml
// starts it as its child). JSON lines both ways, on stdin and stdout:
//
//	→ {"hello":"spored","protocol":1}
//	← {"id":7,"op":"copy","sources":[…],"dest":"/x","policy":"keep"}
//	→ {"id":7,"event":"total","bytes":…,"items":…}
//	→ {"id":7,"event":"progress","bytes":…,"items":…,"current":"name"}
//	→ {"id":7,"event":"done","names":[…],"error":"","code":"","reason":"","canceled":false}
//	← {"op":"cancel","id":7}
//	← {"id":8,"op":"count","path":"/x"}
//	→ {"id":8,"event":"count","count":{"files":…,"folders":…,"bytes":…}}
//	→ {"id":8,"event":"done","count":{…},"error":"","canceled":false}
//
// One job at a time, in the order they come (the queue, and the questions,
// are FileOps'). A count (the quick view's, of a folder) isn't a job: it
// starts at once, beside the job under way, and goes until it's done or
// canceled. It ends when stdin closes (Files went), canceling the job
// under way. Change `protocol` with any change to the messages: in dev mode
// the QML comes from the checkout and spored from the package, and FileOps
// goes back to its scripts when they don't match.
const filesProtocol = 2

type request struct {
	ID      int      `json:"id"`
	Op      string   `json:"op"`
	Sources []string `json:"sources,omitempty"`
	Dest    string   `json:"dest,omitempty"`
	Policy  string   `json:"policy,omitempty"`
	Path    string   `json:"path,omitempty"`
	Name    string   `json:"name,omitempty"`
	Paths   []string `json:"paths,omitempty"`
}

type event struct {
	ID      int    `json:"id"`
	Event   string `json:"event"`
	Bytes   int64  `json:"bytes,omitempty"`
	Items   int64  `json:"items,omitempty"`
	Current string `json:"current,omitempty"`
	// done: what it left (the names it placed, made or found), and, if it
	// stopped, why: a message for the user, a code the QML acts on
	// ("exists"), the system's reason ("permission denied").
	Names    []string `json:"names,omitempty"`
	Error    string   `json:"error,omitempty"`
	Code     string   `json:"code,omitempty"`
	Reason   string   `json:"reason,omitempty"`
	Canceled bool     `json:"canceled,omitempty"`
	// count, and its done: what the folder holds so far.
	Count *count `json:"count,omitempty"`
}

// What a job reports on the way: the encoder is shared with the reader's
// hello, so writes are one at a time.
type reporter struct {
	mu  sync.Mutex
	enc *json.Encoder
}

func (r *reporter) send(v any) {
	r.mu.Lock()
	defer r.mu.Unlock()
	_ = r.enc.Encode(v)
}

func runFiles(in io.Reader, out io.Writer) {
	rep := &reporter{enc: json.NewEncoder(out)}
	rep.enc.SetEscapeHTML(false)
	rep.send(map[string]any{"hello": "spored", "protocol": filesProtocol})

	jobs := make(chan request, 64)
	var mu sync.Mutex
	running := map[int]context.CancelFunc{}
	queued := map[int]bool{}

	var wg sync.WaitGroup
	wg.Add(1)
	go func() {
		defer wg.Done()
		for req := range jobs {
			ctx, cancel := context.WithCancel(context.Background())
			mu.Lock()
			canceled := !queued[req.ID]
			delete(queued, req.ID)
			running[req.ID] = cancel
			mu.Unlock()
			if canceled {
				cancel()
			}
			rep.send(runJob(ctx, req, rep))
			mu.Lock()
			delete(running, req.ID)
			mu.Unlock()
			cancel()
		}
	}()

	scanner := bufio.NewScanner(in)
	// Tens of thousands of paths in one request.
	scanner.Buffer(make([]byte, 1<<20), 256<<20)
	for scanner.Scan() {
		var req request
		if json.Unmarshal(scanner.Bytes(), &req) != nil {
			continue
		}
		if req.Op == "cancel" {
			mu.Lock()
			if cancel, ok := running[req.ID]; ok {
				cancel()
			}
			delete(queued, req.ID)
			mu.Unlock()
			continue
		}
		if req.Op == "count" {
			ctx, cancel := context.WithCancel(context.Background())
			mu.Lock()
			running[req.ID] = cancel
			mu.Unlock()
			wg.Add(1)
			go func() {
				defer wg.Done()
				rep.send(runCount(ctx, req, rep))
				mu.Lock()
				delete(running, req.ID)
				mu.Unlock()
				cancel()
			}()
			continue
		}
		mu.Lock()
		queued[req.ID] = true
		mu.Unlock()
		jobs <- req
	}

	// Files went: what's under way stops (and cleans up after itself).
	mu.Lock()
	for _, cancel := range running {
		cancel()
	}
	for id := range queued {
		delete(queued, id)
	}
	mu.Unlock()
	close(jobs)
	wg.Wait()
}

// The progress of a job, sent at most every 200 ms (and always the last).
type progress struct {
	rep     *reporter
	id      int
	bytes   int64
	items   int64
	current string
	last    time.Time
}

func (p *progress) add(bytes, items int64, current string) {
	p.bytes += bytes
	p.items += items
	if current != "" {
		p.current = current
	}
	if now := time.Now(); now.Sub(p.last) >= 200*time.Millisecond {
		p.last = now
		p.flush()
	}
}

func (p *progress) flush() {
	p.rep.send(event{ID: p.id, Event: "progress", Bytes: p.bytes, Items: p.items, Current: p.current})
}

func runJob(ctx context.Context, req request, rep *reporter) event {
	done := event{ID: req.ID, Event: "done"}
	var res result
	switch req.Op {
	case "check":
		res = check(req.Sources, req.Dest)
	case "copy", "move":
		p := &progress{rep: rep, id: req.ID}
		res = transfer(ctx, req.Op, req.Sources, req.Dest, req.Policy, func(bytes, items int64) {
			rep.send(event{ID: req.ID, Event: "total", Bytes: bytes, Items: items})
		}, p)
		p.flush()
	case "rename":
		res = rename(req.Path, req.Name)
	case "mkdir":
		res = newFolder(req.Dest)
	case "remove":
		res = remove(ctx, req.Paths)
	default:
		res = result{err: "Unknown operation " + req.Op}
	}
	done.Names = res.names
	done.Error = res.err
	done.Code = res.code
	done.Reason = res.reason
	done.Canceled = res.canceled
	return done
}

func runCount(ctx context.Context, req request, rep *reporter) event {
	c, err := countFolder(ctx, req.Path, func(c count) {
		rep.send(event{ID: req.ID, Event: "count", Count: &c})
	})
	done := event{ID: req.ID, Event: "done", Count: &c}
	if errors.Is(err, errVirtual) {
		// No numbers: the quick view says only that it's a folder.
		done.Count = nil
	} else if ctx.Err() != nil {
		done.Canceled = true
	} else if err != nil {
		done.Reason = reasonOf(err)
		done.Error = "Couldn't read " + quoted(req.Path) + ": " + done.Reason
	}
	return done
}

// A job's end: see event.
type result struct {
	names    []string
	err      string
	code     string
	reason   string
	canceled bool
}

func filesMain() {
	runFiles(os.Stdin, os.Stdout)
}
