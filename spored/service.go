package main

import (
	"bufio"
	"encoding/json"
	"io"
	"sync"
)

// The shell and spored (the session's one, not `spored files`) talk in JSON
// lines, spored on its stdout and the shell on spored's stdin:
//
//	→ {"hello":"spored","protocol":1,"services":["filemanager","logind","drives"]}
//	→ {"event":"sleep"}    the system is about to sleep: lock now
//	← {"op":"locked"}      the lock is up (spored lets the sleep go on)
//	→ {"event":"lock"}     logind asked to lock (`loginctl lock-session`)
//	→ {"event":"drives"}   a drive came, went or was mounted: read them again
//
// `services` lists what's working; for what's missing, the shell keeps
// its scripts. Change `protocol` with any change to the messages: in dev
// mode the QML comes from the checkout and spored from the package, and
// the shell goes back to its scripts when they don't match.
const serviceProtocol = 1

type service struct {
	mu  sync.Mutex
	enc *json.Encoder
	// {"op":"locked"} from the shell.
	onLocked func()
}

func newService(out io.Writer) *service {
	enc := json.NewEncoder(out)
	enc.SetEscapeHTML(false)
	return &service{enc: enc}
}

func (s *service) send(v any) {
	s.mu.Lock()
	defer s.mu.Unlock()
	_ = s.enc.Encode(v)
}

func (s *service) hello(services []string) {
	if services == nil {
		services = []string{}
	}
	s.send(map[string]any{"hello": "spored", "protocol": serviceProtocol, "services": services})
}

func (s *service) event(name string) {
	s.send(map[string]string{"event": name})
}

// Until stdin closes. Then spored goes on: FileManager1 doesn't need the
// shell's answers, and the shell (setpriv) stops spored when it ends.
func (s *service) read(in io.Reader) {
	scanner := bufio.NewScanner(in)
	for scanner.Scan() {
		var msg struct {
			Op string `json:"op"`
		}
		if json.Unmarshal(scanner.Bytes(), &msg) != nil {
			continue
		}
		if msg.Op == "locked" && s.onLocked != nil {
			s.onLocked()
		}
	}
}
