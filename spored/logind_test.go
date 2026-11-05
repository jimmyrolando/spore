package main

import (
	"io"
	"sync"
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// A fake inhibitor: counts what's held.
type fakeInhibitor struct {
	mu    sync.Mutex
	held  int
	taken int
}

func (f *fakeInhibitor) inhibit() (io.Closer, error) {
	f.mu.Lock()
	defer f.mu.Unlock()
	f.held++
	f.taken++
	return closerFunc(func() error {
		f.mu.Lock()
		defer f.mu.Unlock()
		f.held--
		return nil
	}), nil
}

func (f *fakeInhibitor) state() (held, taken int) {
	f.mu.Lock()
	defer f.mu.Unlock()
	return f.held, f.taken
}

type closerFunc func() error

func (c closerFunc) Close() error { return c() }

type events struct {
	mu   sync.Mutex
	list []string
	// Called with each event, outside the lock (as the shell would answer).
	on func(string)
}

func (e *events) emit(name string) {
	e.mu.Lock()
	e.list = append(e.list, name)
	e.mu.Unlock()
	if e.on != nil {
		e.on(name)
	}
}

func (e *events) all() []string {
	e.mu.Lock()
	defer e.mu.Unlock()
	return append([]string(nil), e.list...)
}

const testSession = dbus.ObjectPath("/org/freedesktop/login1/session/_32")

func sleepSignal(start bool) *dbus.Signal {
	return &dbus.Signal{Path: loginPath, Name: loginManager + ".PrepareForSleep", Body: []any{start}}
}

func newTestWatch(t *testing.T, ev *events) (*logindWatch, *fakeInhibitor) {
	t.Helper()
	inh := &fakeInhibitor{}
	w := newLogindWatch(inh.inhibit, ev.emit, testSession)
	w.wait = 200 * time.Millisecond
	if err := w.hold(); err != nil {
		t.Fatal(err)
	}
	return w, inh
}

// The shell answers "locked": the inhibitor goes at once, and comes back on
// waking.
func TestSleepWaitsForTheLock(t *testing.T) {
	ev := &events{}
	w, inh := newTestWatch(t, ev)
	ev.on = func(name string) {
		if name == "sleep" {
			go func() {
				time.Sleep(20 * time.Millisecond)
				if held, _ := inh.state(); held != 1 {
					t.Errorf("the inhibitor went before the lock (held %d)", held)
				}
				w.locked()
			}()
		}
	}
	start := time.Now()
	w.signal(sleepSignal(true))
	if took := time.Since(start); took >= w.wait {
		t.Errorf("waited %v: the lock's answer wasn't heard", took)
	}
	if held, _ := inh.state(); held != 0 {
		t.Errorf("held %d after the lock, want 0", held)
	}
	w.signal(sleepSignal(false))
	if held, taken := inh.state(); held != 1 || taken != 2 {
		t.Errorf("after waking: held %d taken %d, want 1 and 2", held, taken)
	}
	if got := ev.all(); len(got) != 1 || got[0] != "sleep" {
		t.Errorf("events %v, want [sleep]", got)
	}
}

// No answer: it sleeps anyway after the wait.
func TestSleepWithoutAnswer(t *testing.T) {
	ev := &events{}
	w, inh := newTestWatch(t, ev)
	start := time.Now()
	w.signal(sleepSignal(true))
	if took := time.Since(start); took < w.wait {
		t.Errorf("let go after %v, before the wait", took)
	}
	if held, _ := inh.state(); held != 0 {
		t.Errorf("held %d, want 0", held)
	}
}

// A "locked" from before (a lock with no sleep) doesn't let a later sleep
// go at once.
func TestStaleLockedIgnored(t *testing.T) {
	ev := &events{}
	w, _ := newTestWatch(t, ev)
	w.locked()
	start := time.Now()
	w.signal(sleepSignal(true))
	if took := time.Since(start); took < w.wait {
		t.Errorf("let go after %v: an old \"locked\" counted", took)
	}
}

// Waking twice, or without having slept, takes it once.
func TestWakeHoldsOnce(t *testing.T) {
	ev := &events{}
	w, inh := newTestWatch(t, ev)
	w.signal(sleepSignal(false))
	w.signal(sleepSignal(false))
	if held, taken := inh.state(); held != 1 || taken != 1 {
		t.Errorf("held %d taken %d, want 1 and 1", held, taken)
	}
}

// Session.Lock: only this session's.
func TestSessionLock(t *testing.T) {
	ev := &events{}
	w, _ := newTestWatch(t, ev)
	w.signal(&dbus.Signal{Path: "/org/freedesktop/login1/session/_33", Name: loginName + ".Session.Lock"})
	w.signal(&dbus.Signal{Path: testSession, Name: loginName + ".Session.Unlock"})
	w.signal(&dbus.Signal{Path: testSession, Name: loginName + ".Session.Lock"})
	if got := ev.all(); len(got) != 1 || got[0] != "lock" {
		t.Errorf("events %v, want [lock]", got)
	}
	// An unknown session never locks.
	ev2 := &events{}
	w2 := newLogindWatch((&fakeInhibitor{}).inhibit, ev2.emit, "")
	w2.signal(&dbus.Signal{Path: "", Name: loginName + ".Session.Lock"})
	if got := ev2.all(); len(got) != 0 {
		t.Errorf("events %v with no session, want none", got)
	}
}
