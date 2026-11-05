package main

import (
	"strings"
	"sync"
	"time"

	"github.com/godbus/dbus/v5"
)

// Drives: UDisks2 says when a drive is plugged in or out (InterfacesAdded,
// InterfacesRemoved) and when a volume is mounted or unmounted
// (PropertiesChanged), and the shell reads them again (lsblk, in
// shell/services/DrivesService.qml). One event comes in a burst of
// signals, so they're gathered into one "drives".
const (
	udisksName = "org.freedesktop.UDisks2"
	udisksPath = dbus.ObjectPath("/org/freedesktop/UDisks2")
	drivesWait = 300 * time.Millisecond
)

type drivesWatch struct {
	emit func(event string)
	wait time.Duration

	mu    sync.Mutex
	timer *time.Timer
}

func newDrivesWatch(emit func(string)) *drivesWatch {
	return &drivesWatch{emit: emit, wait: drivesWait}
}

// Matched by name: the bus follows UDisks2 if it restarts. If it isn't
// installed, nothing comes, and nothing breaks.
func watchDrives(conn *dbus.Conn, emit func(string)) (*drivesWatch, error) {
	if err := conn.AddMatchSignal(dbus.WithMatchSender(udisksName), dbus.WithMatchPathNamespace(udisksPath)); err != nil {
		return nil, err
	}
	return newDrivesWatch(emit), nil
}

func (d *drivesWatch) signal(s *dbus.Signal) {
	if !strings.HasPrefix(string(s.Path), string(udisksPath)) {
		return
	}
	switch s.Name {
	case "org.freedesktop.DBus.ObjectManager.InterfacesAdded",
		"org.freedesktop.DBus.ObjectManager.InterfacesRemoved",
		"org.freedesktop.DBus.Properties.PropertiesChanged":
	default:
		return
	}
	d.mu.Lock()
	defer d.mu.Unlock()
	if d.timer == nil {
		d.timer = time.AfterFunc(d.wait, func() {
			d.mu.Lock()
			d.timer = nil
			d.mu.Unlock()
			d.emit("drives")
		})
	}
}
