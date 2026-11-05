package main

import (
	"errors"
	"fmt"
	"io"
	"log"
	"os"
	"sync"
	"syscall"
	"time"

	"github.com/godbus/dbus/v5"
)

// The screen locks before the system sleeps, whatever puts it to sleep (the
// lid, the power key, `systemctl suspend`, another app), and `loginctl
// lock-session` locks it too.
//
// spored holds a delay inhibitor (`systemd-inhibit --list` shows it as
// Spore), so logind waits before sleeping. When logind says
// PrepareForSleep(true), the shell hears "sleep" and locks; its "locked"
// (or 2 s) lets the inhibitor go, and the system sleeps. On waking,
// PrepareForSleep(false), it's taken again. Session.Lock on this session
// is "lock".
const (
	loginName    = "org.freedesktop.login1"
	loginPath    = dbus.ObjectPath("/org/freedesktop/login1")
	loginManager = "org.freedesktop.login1.Manager"
	// How long a sleep waits for the lock. logind waits up to its
	// InhibitDelayMaxSec (5 s by default).
	lockWait = 2 * time.Second
)

type logindWatch struct {
	// Takes the delay inhibitor; closing what it returns lets it go.
	inhibit func() (io.Closer, error)
	emit    func(event string)
	// This session's object ("" if unknown: no "lock").
	session dbus.ObjectPath
	wait    time.Duration

	mu   sync.Mutex
	held io.Closer
	// The shell's "locked", for the sleep under way.
	lockedCh chan struct{}
}

func newLogindWatch(inhibit func() (io.Closer, error), emit func(string), session dbus.ObjectPath) *logindWatch {
	return &logindWatch{inhibit: inhibit, emit: emit, session: session, wait: lockWait, lockedCh: make(chan struct{}, 1)}
}

func watchLogind(conn *dbus.Conn, emit func(string)) (*logindWatch, error) {
	if !conn.SupportsUnixFDs() {
		return nil, errors.New("the system bus can't pass file descriptors (needed for the inhibitor)")
	}
	manager := conn.Object(loginName, loginPath)
	session, err := sessionPath(conn, manager)
	if err != nil {
		log.Printf("logind: this session isn't known, so `loginctl lock-session` won't lock: %v", err)
	}
	inhibit := func() (io.Closer, error) {
		var fd dbus.UnixFD
		err := manager.Call(loginManager+".Inhibit", 0, "sleep", "Spore", "Locks the screen before sleeping", "delay").Store(&fd)
		if err != nil {
			return nil, err
		}
		return fdCloser(fd), nil
	}
	w := newLogindWatch(inhibit, emit, session)
	if err := w.hold(); err != nil {
		return nil, fmt.Errorf("taking the inhibitor: %w", err)
	}
	if err := conn.AddMatchSignal(dbus.WithMatchSender(loginName), dbus.WithMatchObjectPath(loginPath),
		dbus.WithMatchInterface(loginManager), dbus.WithMatchMember("PrepareForSleep")); err != nil {
		w.release()
		return nil, err
	}
	if session != "" {
		if err := conn.AddMatchSignal(dbus.WithMatchSender(loginName), dbus.WithMatchObjectPath(session),
			dbus.WithMatchInterface(loginName+".Session"), dbus.WithMatchMember("Lock")); err != nil {
			log.Printf("logind: no Session.Lock: %v", err)
		}
	}
	return w, nil
}

// XDG_SESSION_ID's session, else the user's graphical one (its Display).
func sessionPath(conn *dbus.Conn, manager dbus.BusObject) (dbus.ObjectPath, error) {
	var path dbus.ObjectPath
	if id := os.Getenv("XDG_SESSION_ID"); id != "" {
		err := manager.Call(loginManager+".GetSession", 0, id).Store(&path)
		return path, err
	}
	var user dbus.ObjectPath
	if err := manager.Call(loginManager+".GetUser", 0, uint32(os.Getuid())).Store(&user); err != nil {
		return "", err
	}
	display, err := conn.Object(loginName, user).GetProperty(loginName + ".User.Display")
	if err != nil {
		return "", err
	}
	// (so): the session's id and object.
	if fields, ok := display.Value().([]any); ok && len(fields) == 2 {
		if p, ok := fields[1].(dbus.ObjectPath); ok && p != "/" {
			return p, nil
		}
	}
	return "", errors.New("the user has no graphical session")
}

type fdCloser int

func (f fdCloser) Close() error { return syscall.Close(int(f)) }

func (w *logindWatch) hold() error {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.held != nil {
		return nil
	}
	held, err := w.inhibit()
	if err != nil {
		return err
	}
	w.held = held
	return nil
}

func (w *logindWatch) release() {
	w.mu.Lock()
	defer w.mu.Unlock()
	if w.held != nil {
		w.held.Close()
		w.held = nil
	}
}

func (w *logindWatch) signal(s *dbus.Signal) {
	switch {
	case s.Path == loginPath && s.Name == loginManager+".PrepareForSleep":
		if len(s.Body) == 1 {
			if start, ok := s.Body[0].(bool); ok {
				w.prepareForSleep(start)
			}
		}
	case w.session != "" && s.Path == w.session && s.Name == loginName+".Session.Lock":
		w.emit("lock")
	}
}

func (w *logindWatch) prepareForSleep(start bool) {
	if !start {
		if err := w.hold(); err != nil {
			log.Printf("logind: taking the inhibitor again: %v", err)
		}
		return
	}
	// A "locked" left over from before doesn't count.
	select {
	case <-w.lockedCh:
	default:
	}
	w.emit("sleep")
	select {
	case <-w.lockedCh:
	case <-time.After(w.wait):
		log.Print("logind: the lock didn't come in time, sleeping anyway")
	}
	w.release()
}

// The shell's "locked".
func (w *logindWatch) locked() {
	select {
	case w.lockedCh <- struct{}{}:
	default:
	}
}
