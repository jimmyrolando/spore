package main

import (
	"testing"
	"time"

	"github.com/godbus/dbus/v5"
)

// A burst of UDisks2 signals is one "drives"; other signals, none.
func TestDrivesBurst(t *testing.T) {
	ev := &events{}
	d := newDrivesWatch(ev.emit)
	d.wait = 50 * time.Millisecond

	d.signal(&dbus.Signal{Path: loginPath, Name: "org.freedesktop.DBus.Properties.PropertiesChanged"})
	d.signal(&dbus.Signal{Path: udisksPath + "/jobs/1", Name: "org.freedesktop.UDisks2.Job.Completed"})
	time.Sleep(100 * time.Millisecond)
	if got := ev.all(); len(got) != 0 {
		t.Fatalf("events %v from other signals, want none", got)
	}

	for _, name := range []string{
		"org.freedesktop.DBus.ObjectManager.InterfacesAdded",
		"org.freedesktop.DBus.Properties.PropertiesChanged",
		"org.freedesktop.DBus.Properties.PropertiesChanged",
	} {
		d.signal(&dbus.Signal{Path: udisksPath + "/block_devices/sdb1", Name: name})
	}
	time.Sleep(100 * time.Millisecond)
	if got := ev.all(); len(got) != 1 || got[0] != "drives" {
		t.Fatalf("events %v, want [drives]", got)
	}

	d.signal(&dbus.Signal{Path: udisksPath, Name: "org.freedesktop.DBus.ObjectManager.InterfacesRemoved"})
	time.Sleep(100 * time.Millisecond)
	if got := ev.all(); len(got) != 2 {
		t.Fatalf("events %v, want a second drives", got)
	}
}
