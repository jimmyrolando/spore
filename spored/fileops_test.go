package main

import (
	"bufio"
	"context"
	"encoding/json"
	"io"
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
		runFiles(in, out)
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

	if !strings.Contains(lines[0], `"protocol":1`) {
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
