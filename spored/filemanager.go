package main

import (
	"fmt"
	"log"
	"os"
	"os/exec"
	"strings"

	"github.com/godbus/dbus/v5"
	"github.com/godbus/dbus/v5/introspect"
)

// org.freedesktop.FileManager1: what browsers (Firefox, Chromium), editors
// and others call to show a file in the file manager ("Show in folder").
// Thunar offers it too; whoever asks for the name first gets it, so the
// shell starts spored with the session. If Thunar already has it (started
// earlier), spored waits in the queue and takes it when Thunar goes.
const (
	fmName = "org.freedesktop.FileManager1"
	fmPath = "/org/freedesktop/FileManager1"
)

// The interface, as the spec has it
// (https://www.freedesktop.org/wiki/Specifications/file-manager-interface/).
const fmIntrospection = `
<node>
  <interface name="org.freedesktop.FileManager1">
    <method name="ShowFolders">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItems">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
    <method name="ShowItemProperties">
      <arg type="as" name="URIs" direction="in"/>
      <arg type="s" name="StartupId" direction="in"/>
    </method>
  </interface>` + introspect.IntrospectDataString + `</node>`

type fileManager struct {
	// Opens a Files window on a file:// URI: a folder, or a file's folder
	// with the file selected.
	open func(uri string) error
}

func (f *fileManager) ShowFolders(uris []string, startupID string) *dbus.Error {
	return f.show(folderTargets(uris))
}

func (f *fileManager) ShowItems(uris []string, startupID string) *dbus.Error {
	return f.show(itemTargets(uris))
}

// Files has no properties window: the item, selected, is the closest.
func (f *fileManager) ShowItemProperties(uris []string, startupID string) *dbus.Error {
	return f.show(itemTargets(uris))
}

func (f *fileManager) show(targets []string) *dbus.Error {
	for _, uri := range targets {
		if err := f.open(uri); err != nil {
			log.Printf("couldn't open %s: %v", uri, err)
			return dbus.MakeFailedError(err)
		}
	}
	return nil
}

// Local files only (file://): Files doesn't browse sftp:// or smb://.
func isFile(uri string) bool {
	return len(uri) >= 7 && strings.EqualFold(uri[:7], "file://")
}

// Each folder once.
func folderTargets(uris []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, uri := range uris {
		if !isFile(uri) || seen[uri] {
			continue
		}
		seen[uri] = true
		out = append(out, uri)
	}
	return out
}

// A window per folder, with its first item selected: ten files from one
// folder ("Show in folder" on several downloads) are one window, not ten.
// A name's "/" is %2F in a URI, so the last "/" is always the folder's.
func itemTargets(uris []string) []string {
	var out []string
	seen := map[string]bool{}
	for _, uri := range uris {
		if !isFile(uri) {
			continue
		}
		trimmed := strings.TrimRight(uri, "/")
		folder := trimmed[:strings.LastIndex(trimmed, "/")+1]
		if seen[folder] {
			continue
		}
		seen[folder] = true
		out = append(out, trimmed)
	}
	return out
}

// The command that opens Files: -files (the shell passes the spore-files
// next to spored's link), else spore-files from PATH. It decodes the URI
// itself.
func filesCommand(program string) func(uri string) error {
	if program == "" {
		program = "spore-files"
	}
	return func(uri string) error {
		cmd := exec.Command(program, uri)
		cmd.Stdout = os.Stderr
		cmd.Stderr = os.Stderr
		if err := cmd.Start(); err != nil {
			return err
		}
		// Files stays open: only its exit is collected.
		go cmd.Wait()
		return nil
	}
}

// The object first, then the name: a call can come as soon as it's ours.
func serveFileManager(conn *dbus.Conn, open func(uri string) error) error {
	fm := &fileManager{open: open}
	if err := conn.Export(fm, fmPath, fmName); err != nil {
		return err
	}
	if err := conn.Export(introspect.Introspectable(fmIntrospection), fmPath, "org.freedesktop.DBus.Introspectable"); err != nil {
		return err
	}
	// Taken from whoever has it, if they allow it; queued otherwise.
	reply, err := conn.RequestName(fmName, dbus.NameFlagReplaceExisting)
	if err != nil {
		return fmt.Errorf("asking for %s: %w", fmName, err)
	}
	if reply == dbus.RequestNameReplyInQueue {
		log.Printf("%s is taken (Thunar?): waiting for it", fmName)
	}
	return nil
}
