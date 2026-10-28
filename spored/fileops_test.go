package main

import (
	"bufio"
	"context"
	"encoding/json"
	"errors"
	"io"
	"io/fs"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"
)

// A progress that reports nowhere.
func quiet() *progress {
	return &progress{rep: &reporter{enc: json.NewEncoder(io.Discard)}}
}

func write(t *testing.T, path, content string) {
	t.Helper()
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(path, []byte(content), 0o644); err != nil {
		t.Fatal(err)
	}
}

func read(t *testing.T, path string) string {
	t.Helper()
	b, err := os.ReadFile(path)
	if err != nil {
		t.Fatal(err)
	}
	return string(b)
}

func names(t *testing.T, dir string) []string {
	t.Helper()
	entries, err := os.ReadDir(dir)
	if err != nil {
		t.Fatal(err)
	}
	var out []string
	for _, e := range entries {
		out = append(out, e.Name())
	}
	sort.Strings(out)
	return out
}

func noTotal(int64, int64) {}

func TestCopyTreeKeepsLinksModesAndTimes(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	folder := filepath.Join(src, "Odd \n name #?%41")
	write(t, filepath.Join(folder, "a.txt"), "hello")
	write(t, filepath.Join(folder, "sub", "b.sh"), "#!/bin/sh")
	os.Chmod(filepath.Join(folder, "sub", "b.sh"), 0o755)
	write(t, filepath.Join(folder, "suid"), "x")
	os.Chmod(filepath.Join(folder, "suid"), 0o755|fs.ModeSetuid)
	os.Symlink("a.txt", filepath.Join(folder, "link"))
	os.Symlink("/nowhere", filepath.Join(folder, "broken"))
	old := time.Date(2020, 1, 2, 3, 4, 5, 0, time.UTC)
	os.Chtimes(filepath.Join(folder, "a.txt"), old, old)
	// A folder without write permission is still copied, and keeps its mode.
	os.Chmod(filepath.Join(folder, "sub"), 0o555)
	t.Cleanup(func() { os.Chmod(filepath.Join(folder, "sub"), 0o755) })

	res := transfer(context.Background(), "copy", []string{folder}, dest, "keep", noTotal, quiet())
	if res.err != "" {
		t.Fatal(res.err)
	}
	got := filepath.Join(dest, filepath.Base(folder))
	if !reflect.DeepEqual(res.names, []string{filepath.Base(folder)}) {
		t.Errorf("placed %q", res.names)
	}
	if read(t, filepath.Join(got, "a.txt")) != "hello" {
		t.Error("a.txt's contents")
	}
	if info, _ := os.Stat(filepath.Join(got, "sub", "b.sh")); info.Mode().Perm() != 0o755 {
		t.Errorf("b.sh's mode: %v", info.Mode())
	}
	// The chown that keeps the owner cleared it.
	if info, _ := os.Stat(filepath.Join(got, "suid")); info.Mode()&fs.ModeSetuid == 0 {
		t.Errorf("suid's mode: %v", info.Mode())
	}
	if info, _ := os.Stat(filepath.Join(got, "sub")); info.Mode().Perm() != 0o555 {
		t.Errorf("sub's mode: %v", info.Mode())
	}
	os.Chmod(filepath.Join(got, "sub"), 0o755)
	if link, _ := os.Readlink(filepath.Join(got, "link")); link != "a.txt" {
		t.Errorf("link -> %q", link)
	}
	if link, _ := os.Readlink(filepath.Join(got, "broken")); link != "/nowhere" {
		t.Errorf("broken -> %q", link)
	}
	if info, _ := os.Stat(filepath.Join(got, "a.txt")); !info.ModTime().Equal(old) {
		t.Errorf("a.txt's time: %v", info.ModTime())
	}
	// No temporary left behind.
	if n := names(t, dest); len(n) != 1 {
		t.Errorf("dest has %q", n)
	}
}

func TestPolicies(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	write(t, filepath.Join(src, "doc.txt"), "new")
	write(t, filepath.Join(dest, "doc.txt"), "old")

	res := transfer(context.Background(), "copy", []string{filepath.Join(src, "doc.txt")}, dest, "skip", noTotal, quiet())
	if res.err != "" || len(res.names) != 0 || read(t, filepath.Join(dest, "doc.txt")) != "old" {
		t.Errorf("skip: %+v", res)
	}
	res = transfer(context.Background(), "copy", []string{filepath.Join(src, "doc.txt")}, dest, "keep", noTotal, quiet())
	if !reflect.DeepEqual(res.names, []string{"doc (2).txt"}) || read(t, filepath.Join(dest, "doc (2).txt")) != "new" {
		t.Errorf("keep: %+v", res)
	}
	if read(t, filepath.Join(dest, "doc.txt")) != "old" {
		t.Error("keep overwrote the old one")
	}
}

func TestCopyIntoItsOwnFolderKeepsBoth(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "v1.2", "x"), "x")
	res := transfer(context.Background(), "copy", []string{filepath.Join(dir, "v1.2")}, dir, "skip", noTotal, quiet())
	if !reflect.DeepEqual(res.names, []string{"v1.2 (2)"}) {
		t.Errorf("placed %q, error %q", res.names, res.err)
	}
}

func TestMoveWithinADisk(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	write(t, filepath.Join(src, "a", "b"), "b")
	var totals int
	res := transfer(context.Background(), "move", []string{filepath.Join(src, "a")}, dest, "keep",
		func(int64, int64) { totals++ }, quiet())
	if res.err != "" || !reflect.DeepEqual(res.names, []string{"a"}) {
		t.Fatalf("%+v", res)
	}
	if exists(filepath.Join(src, "a")) || read(t, filepath.Join(dest, "a", "b")) != "b" {
		t.Error("not moved")
	}
	if totals != 0 {
		t.Error("a rename has nothing to count")
	}
	// Into its own folder: nothing happens.
	res = transfer(context.Background(), "move", []string{filepath.Join(dest, "a")}, dest, "keep", noTotal, quiet())
	if res.err != "" || len(res.names) != 0 || !exists(filepath.Join(dest, "a", "b")) {
		t.Errorf("%+v", res)
	}
}

func TestCanceledCopyLeavesNothing(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	write(t, filepath.Join(src, "big", "f"), strings.Repeat("x", 1<<20))
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	res := transfer(ctx, "copy", []string{filepath.Join(src, "big")}, dest, "keep", noTotal, quiet())
	if !res.canceled {
		t.Errorf("%+v", res)
	}
	if n := names(t, dest); len(n) != 0 {
		t.Errorf("left %q", n)
	}
}

func TestRenameNeverReplaces(t *testing.T) {
	dir := t.TempDir()
	write(t, filepath.Join(dir, "a"), "a")
	write(t, filepath.Join(dir, "b"), "b")
	if res := rename(filepath.Join(dir, "a"), "b"); res.code != "exists" {
		t.Errorf("%+v", res)
	}
	if read(t, filepath.Join(dir, "b")) != "b" {
		t.Error("b was replaced")
	}
	if res := rename(filepath.Join(dir, "a"), "../x"); res.err == "" {
		t.Error("a name with / was taken")
	}
	if res := rename(filepath.Join(dir, "a"), "c"); res.err != "" || read(t, filepath.Join(dir, "c")) != "a" {
		t.Errorf("%+v", res)
	}
}

func TestNewFolderAndRemove(t *testing.T) {
	dir := t.TempDir()
	if res := newFolder(dir); !reflect.DeepEqual(res.names, []string{"New folder"}) {
		t.Errorf("%+v", res)
	}
	if res := newFolder(dir); !reflect.DeepEqual(res.names, []string{"New folder 2"}) {
		t.Errorf("%+v", res)
	}
	locked := filepath.Join(dir, "New folder", "locked")
	write(t, filepath.Join(locked, "f"), "f")
	os.Chmod(locked, 0o500)
	res := remove(context.Background(), []string{filepath.Join(dir, "New folder"), "relative", "/"})
	if res.err != "" || exists(filepath.Join(dir, "New folder")) {
		t.Errorf("%+v", res)
	}
	if !reflect.DeepEqual(res.names, []string{filepath.Join(dir, "New folder")}) {
		t.Errorf("removed %q", res.names)
	}
}

func TestCheck(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	write(t, filepath.Join(src, "a"), "")
	write(t, filepath.Join(src, "b"), "")
	write(t, filepath.Join(dest, "b"), "")
	res := check([]string{filepath.Join(src, "a"), filepath.Join(src, "b"), filepath.Join(dest, "b")}, dest)
	if !reflect.DeepEqual(res.names, []string{"b"}) {
		t.Errorf("%q", res.names)
	}
}

// The protocol end to end: hello, a copy with its total and progress, done.
func TestProtocol(t *testing.T) {
	src, dest := t.TempDir(), t.TempDir()
	write(t, filepath.Join(src, "f"), "12345")
	req, _ := json.Marshal(request{ID: 3, Op: "copy", Sources: []string{filepath.Join(src, "f")}, Dest: dest, Policy: "keep"})
	// stdin stays open until the job is done, as Files keeps it (closing it
	// cancels what's pending).
	in, toSpored := io.Pipe()
	fromSpored, out := io.Pipe()
	go func() {
		runFiles(context.Background(), in, out)
		out.Close()
	}()
	go toSpored.Write(append(req, '\n'))
	var lines []string
	scanner := bufio.NewScanner(fromSpored)
	for scanner.Scan() {
		lines = append(lines, scanner.Text())
		if strings.Contains(scanner.Text(), `"done"`) {
			toSpored.Close()
		}
	}

	if !strings.Contains(lines[0], `"protocol":2`) {
		t.Errorf("hello: %s", lines[0])
	}
	var last event
	json.Unmarshal([]byte(lines[len(lines)-1]), &last)
	if last.ID != 3 || last.Event != "done" || !reflect.DeepEqual(last.Names, []string{"f"}) {
		t.Errorf("done: %s", lines[len(lines)-1])
	}
	var total event
	json.Unmarshal([]byte(lines[1]), &total)
	if total.Event != "total" || total.Bytes != 5 {
		t.Errorf("total: %s", lines[1])
	}
}

// To another disk: copied with its total, then the original deleted.
func TestMoveAcrossDisks(t *testing.T) {
	src := t.TempDir()
	runtime := os.Getenv("XDG_RUNTIME_DIR")
	srcInfo, _ := os.Stat(src)
	runInfo, err := os.Stat(runtime)
	if runtime == "" || err != nil || deviceOf(srcInfo) == deviceOf(runInfo) {
		t.Skip("no second filesystem to move to")
	}
	dest, err := os.MkdirTemp(runtime, "spored-test-")
	if err != nil {
		t.Skip(err)
	}
	t.Cleanup(func() { os.RemoveAll(dest) })
	write(t, filepath.Join(src, "a", "f"), "12345")
	var bytes int64
	res := transfer(context.Background(), "move", []string{filepath.Join(src, "a")}, dest, "keep",
		func(b, _ int64) { bytes = b }, quiet())
	if res.err != "" || !reflect.DeepEqual(res.names, []string{"a"}) {
		t.Fatalf("%+v", res)
	}
	if bytes != 5 {
		t.Errorf("total %d", bytes)
	}
	if exists(filepath.Join(src, "a")) || read(t, filepath.Join(dest, "a", "f")) != "12345" {
		t.Error("not moved")
	}
}

// Everything inside, all the way down: a hard link weighs once, a link to a
// folder isn't followed, an unreadable folder is noted.
func TestCountFolder(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "a"), "12345")
	write(t, filepath.Join(root, "sub", "b"), "123")
	write(t, filepath.Join(root, "sub", "deeper", "c"), "1")
	os.Link(filepath.Join(root, "a"), filepath.Join(root, "sub", "a-again"))
	os.Symlink(filepath.Join(root, "sub"), filepath.Join(root, "link"))
	os.Mkdir(filepath.Join(root, "locked"), 0o755)
	write(t, filepath.Join(root, "locked", "hidden"), "123456789")
	os.Chmod(filepath.Join(root, "locked"), 0)
	defer os.Chmod(filepath.Join(root, "locked"), 0o755)

	c, err := countFolder(context.Background(), root, func(count) {})
	if err != nil {
		t.Fatal(err)
	}
	want := count{Files: 5, Folders: 3, Bytes: 9, Unreadable: 1}
	if os.Getuid() == 0 {
		want = count{Files: 6, Folders: 3, Bytes: 18}
	}
	if c != want {
		t.Errorf("got %+v, want %+v", c, want)
	}

	if _, err := countFolder(context.Background(), filepath.Join(root, "missing"), func(count) {}); err == nil {
		t.Error("a missing folder counted")
	}
	if _, err := countFolder(context.Background(), "/proc", func(count) {}); !errors.Is(err, errVirtual) {
		t.Errorf("/proc counted: %v", err)
	}
	ctx, cancel := context.WithCancel(context.Background())
	cancel()
	if _, err := countFolder(ctx, root, func(count) {}); err == nil {
		t.Error("a canceled count went on")
	}
}

// A count goes beside a job, and ends with its numbers.
func TestCountOverTheProtocol(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "x", "f"), "12")
	req, _ := json.Marshal(request{ID: 4, Op: "count", Path: root})
	in, toSpored := io.Pipe()
	fromSpored, out := io.Pipe()
	go func() {
		runFiles(context.Background(), in, out)
		out.Close()
	}()
	go toSpored.Write(append(req, '\n'))
	var last event
	scanner := bufio.NewScanner(fromSpored)
	for scanner.Scan() {
		if strings.Contains(scanner.Text(), `"done"`) {
			json.Unmarshal(scanner.Bytes(), &last)
			toSpored.Close()
		}
	}
	if last.ID != 4 || last.Count == nil || *last.Count != (count{Files: 1, Folders: 1, Bytes: 2}) {
		t.Errorf("done: %+v", last)
	}
}

// The second count of a folder starts with the first one's numbers.
func TestCountAgain(t *testing.T) {
	root := t.TempDir()
	write(t, filepath.Join(root, "f"), "12")
	in, toSpored := io.Pipe()
	fromSpored, out := io.Pipe()
	go func() {
		runFiles(context.Background(), in, out)
		out.Close()
	}()
	ask := func(id int) {
		req, _ := json.Marshal(request{ID: id, Op: "count", Path: root})
		toSpored.Write(append(req, '\n'))
	}
	go ask(1)
	var events []event
	scanner := bufio.NewScanner(fromSpored)
	for scanner.Scan() {
		var e event
		json.Unmarshal(scanner.Bytes(), &e)
		events = append(events, e)
		if e.Event == "done" && e.ID == 1 {
			write(t, filepath.Join(root, "g"), "1")
			go ask(2)
		}
		if e.Event == "done" && e.ID == 2 {
			toSpored.Close()
		}
	}
	var again, last event
	for _, e := range events {
		if e.ID == 2 && e.Event == "count" {
			again = e
		}
		if e.ID == 2 && e.Event == "done" {
			last = e
		}
	}
	if !again.Again || again.Count == nil || again.Count.Files != 1 {
		t.Errorf("again: %+v", again)
	}
	if last.Count == nil || last.Count.Files != 2 || last.Count.Bytes != 3 {
		t.Errorf("done: %+v", last)
	}
}

// What a job changes is forgotten: its count, what's inside, and every
// folder above it.
func TestForgetCounts(t *testing.T) {
	known := newFolderCounts()
	for _, p := range []string{"/a", "/a/b", "/a/b/c", "/a/x", "/d"} {
		known.put(p, count{Files: 1})
	}
	known.forget("/a/b")
	left := []string{}
	for p := range known.m {
		left = append(left, p)
	}
	sort.Strings(left)
	if !reflect.DeepEqual(left, []string{"/a/x", "/d"}) {
		t.Errorf("left: %v", left)
	}
}

// A signal (Files killed, the session ending) ends it as stdin closing does,
// though stdin stays open.
func TestSignalEndsIt(t *testing.T) {
	in, toSpored := io.Pipe()
	defer toSpored.Close()
	ctx, cancel := context.WithCancel(context.Background())
	ended := make(chan struct{})
	go func() {
		runFiles(ctx, in, io.Discard)
		close(ended)
	}()
	cancel()
	select {
	case <-ended:
	case <-time.After(5 * time.Second):
		t.Fatal("still running")
	}
}
