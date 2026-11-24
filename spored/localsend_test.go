package main

import (
	"bytes"
	"crypto/sha256"
	"crypto/tls"
	"crypto/x509"
	"encoding/hex"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"reflect"
	"sort"
	"strings"
	"testing"
	"time"
)

func TestLsPathParts(t *testing.T) {
	for name, want := range map[string][]string{
		"photo.jpg":              {"photo.jpg"},
		"Photos/2024/a.jpg":      {"Photos", "2024", "a.jpg"},
		"../../etc/passwd":       {"etc", "passwd"},
		"..\\..\\x.txt":          {"x.txt"},
		"/abs/./file":            {"abs", "file"},
		"":                       {"file"},
		"..":                     {"file"},
		" bad\x00na\nme.txt ":    {"badname.txt"},
		"a//b":                   {"a", "b"},
		strings.Repeat("é", 300): {strings.Repeat("é", 100)},
	} {
		if got := lsPathParts(name); !reflect.DeepEqual(got, want) {
			t.Errorf("lsPathParts(%q) = %q, want %q", name, got, want)
		}
	}
	deep := strings.Repeat("d/", 100) + "f"
	if got := lsPathParts(deep); len(got) != 32 || got[31] != "f" {
		t.Errorf("a deep path has %d parts (last %q), want 32 ending in f", len(got), got[len(got)-1])
	}
}

func TestLsCreate(t *testing.T) {
	dir := t.TempDir()
	touch := func(p string) error {
		f, err := os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
		if err == nil {
			f.Close()
		}
		return err
	}
	for _, want := range []string{"a.txt", "a (1).txt", "a (2).txt"} {
		got, err := lsCreate(dir, "a.txt", touch)
		if err != nil || filepath.Base(got) != want {
			t.Fatalf("lsCreate = %q, %v; want %q", got, err, want)
		}
	}
	// A link already there isn't followed: the next name is used.
	outside := filepath.Join(t.TempDir(), "target")
	os.Symlink(outside, filepath.Join(dir, "b"))
	got, err := lsCreate(dir, "b", touch)
	if err != nil || filepath.Base(got) != "b (1)" {
		t.Fatalf("lsCreate next to a link = %q, %v; want b (1)", got, err)
	}
	if _, err := os.Stat(outside); err == nil {
		t.Fatal("the link was followed")
	}
}

// The certificate is kept, and its fingerprint is the official app's.
func TestLsCertificate(t *testing.T) {
	dir := t.TempDir()
	a, err := lsCertificate(dir)
	if err != nil {
		t.Fatal(err)
	}
	b, err := lsCertificate(dir)
	if err != nil {
		t.Fatal(err)
	}
	if !bytes.Equal(a.Certificate[0], b.Certificate[0]) {
		t.Fatal("a second start made another certificate")
	}
	sum := sha256.Sum256(a.Certificate[0])
	fp := lsFingerprint(a.Certificate[0])
	if fp != strings.ToUpper(hex.EncodeToString(sum[:])) || len(fp) != 64 {
		t.Fatalf("fingerprint %q", fp)
	}
	if info, _ := os.Stat(filepath.Join(dir, "key.pem")); info.Mode().Perm() != 0o600 {
		t.Fatalf("the key is %v, want 0600", info.Mode().Perm())
	}
}

// --- A receiver and a sender, on 127.0.0.1 ---

type lsHarness struct {
	t      *testing.T
	r      *receiver
	folder string
	base   string
	client *http.Client
	events chan map[string]any
}

func newLsHarness(t *testing.T) *lsHarness {
	t.Helper()
	ln, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	h := &lsHarness{t: t, folder: filepath.Join(t.TempDir(), "Downloads"), events: make(chan map[string]any, 1000)}
	emit := func(v any) {
		b, _ := json.Marshal(v)
		var m map[string]any
		json.Unmarshal(b, &m)
		h.events <- m
	}
	h.r, err = startReceiver(lsConfig{Alias: "test", Folder: h.folder, StateDir: t.TempDir(), Port: port, Local: true}, emit)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(h.r.stop)
	h.base = fmt.Sprintf("https://127.0.0.1:%d%s", port, lsAPI)
	// As the official app does: the certificate has to be the fingerprint's.
	want := h.r.fingerprint
	h.client = &http.Client{Timeout: 10 * time.Second, Transport: &http.Transport{TLSClientConfig: &tls.Config{
		InsecureSkipVerify: true,
		VerifyPeerCertificate: func(raw [][]byte, _ [][]*x509.Certificate) error {
			if lsFingerprint(raw[0]) != want {
				return fmt.Errorf("fingerprint mismatch")
			}
			return nil
		},
	}}}
	return h
}

func (h *lsHarness) post(path string, body []byte) (*http.Response, []byte) {
	h.t.Helper()
	resp, err := h.client.Post(h.base+path, "application/octet-stream", bytes.NewReader(body))
	if err != nil {
		h.t.Fatal(err)
	}
	defer resp.Body.Close()
	b, _ := io.ReadAll(resp.Body)
	return resp, b
}

// The next event of this kind (others before it are skipped).
func (h *lsHarness) wait(kind string) map[string]any {
	h.t.Helper()
	timeout := time.After(5 * time.Second)
	for {
		select {
		case e := <-h.events:
			if e["kind"] == kind {
				return e
			}
		case <-timeout:
			h.t.Fatalf("no %q event", kind)
		}
	}
}

func prepareBody(files map[string][]byte, names map[string]string, sha bool) []byte {
	list := map[string]any{}
	for id, data := range files {
		f := map[string]any{"id": id, "fileName": names[id], "size": len(data), "fileType": "application/octet-stream"}
		if sha {
			sum := sha256.Sum256(data)
			f["sha256"] = hex.EncodeToString(sum[:])
		}
		list[id] = f
	}
	b, _ := json.Marshal(map[string]any{
		"info":  map[string]any{"alias": "iPhone", "version": "2.1", "deviceModel": "iPhone", "deviceType": "mobile", "fingerprint": "x", "port": 53317, "protocol": "https", "download": false},
		"files": list,
	})
	return b
}

// Asks, and the shell answers.
func (h *lsHarness) prepare(body []byte, accept bool) (*http.Response, map[string]any) {
	h.t.Helper()
	go func() {
		e := h.wait("request")
		h.r.answer(e["session"].(string), accept)
	}()
	resp, b := h.post("prepare-upload", body)
	var out map[string]any
	json.Unmarshal(b, &out)
	return resp, out
}

func TestLsReceive(t *testing.T) {
	h := newLsHarness(t)
	// Already there: the new ones get other names.
	os.MkdirAll(filepath.Join(h.folder, "Photos"), 0o755)
	os.WriteFile(filepath.Join(h.folder, "notes.txt"), []byte("old"), 0o644)

	files := map[string][]byte{"1": []byte("hello"), "2": bytes.Repeat([]byte("x"), 300000), "3": []byte("y"), "4": {}}
	names := map[string]string{"1": "notes.txt", "2": "Photos/a.jpg", "3": "Photos/sub/../../b.jpg", "4": "../../escape"}

	resp, b := h.post("info", nil)
	if resp.StatusCode != 405 && resp.StatusCode != 200 {
		t.Fatalf("info: %d %s", resp.StatusCode, b)
	}
	resp, b = h.post("register", nil)
	var info lsInfo
	if json.Unmarshal(b, &info) != nil || info.Alias != "test" || info.Fingerprint != h.r.fingerprint || info.Protocol != "https" {
		t.Fatalf("register: %d %s", resp.StatusCode, b)
	}

	resp, out := h.prepare(prepareBody(files, names, true), true)
	if resp.StatusCode != 200 {
		t.Fatalf("prepare-upload: %d", resp.StatusCode)
	}
	session := out["sessionId"].(string)
	tokens := out["files"].(map[string]any)

	// Another one meanwhile: busy.
	if resp, _ := h.post("prepare-upload", prepareBody(map[string][]byte{"9": []byte("z")}, map[string]string{"9": "z"}, false)); resp.StatusCode != 409 {
		t.Fatalf("a second request got %d, want 409", resp.StatusCode)
	}
	// A wrong token.
	if resp, _ := h.post(fmt.Sprintf("upload?sessionId=%s&fileId=1&token=nope", session), files["1"]); resp.StatusCode != 403 {
		t.Fatalf("a wrong token got %d, want 403", resp.StatusCode)
	}
	for id, data := range files {
		if resp, b := h.post(fmt.Sprintf("upload?sessionId=%s&fileId=%s&token=%s", session, id, tokens[id]), data); resp.StatusCode != 200 {
			t.Fatalf("upload %s: %d %s", id, resp.StatusCode, b)
		}
	}
	// The same file twice: no.
	if resp, _ := h.post(fmt.Sprintf("upload?sessionId=%s&fileId=1&token=%s", session, tokens["1"]), files["1"]); resp.StatusCode != 403 {
		t.Fatalf("a second upload of a file got %d, want 403", resp.StatusCode)
	}

	done := h.wait("done")
	var paths []string
	for _, p := range done["paths"].([]any) {
		paths = append(paths, filepath.Base(p.(string)))
	}
	sort.Strings(paths)
	if want := []string{"Photos (1)", "escape", "notes (1).txt"}; !reflect.DeepEqual(paths, want) {
		t.Fatalf("done paths %q, want %q", paths, want)
	}
	for path, want := range map[string]string{
		"notes.txt":            "old",
		"notes (1).txt":        "hello",
		"Photos (1)/a.jpg":     string(files["2"]),
		"Photos (1)/sub/b.jpg": "y",
		"escape":               "",
	} {
		got, err := os.ReadFile(filepath.Join(h.folder, path))
		if err != nil || string(got) != want {
			t.Errorf("%s: %v (%d bytes)", path, err, len(got))
		}
	}
	// Nothing outside the folder.
	if _, err := os.Stat(filepath.Join(filepath.Dir(h.folder), "escape")); err == nil {
		t.Error("a file landed outside the folder")
	}
}

func TestLsDeclineAndText(t *testing.T) {
	h := newLsHarness(t)
	resp, _ := h.prepare(prepareBody(map[string][]byte{"1": []byte("a")}, map[string]string{"1": "a"}, false), false)
	if resp.StatusCode != 403 {
		t.Fatalf("declined: %d, want 403", resp.StatusCode)
	}
	h.wait("declined")

	text := "https://example.com"
	b, _ := json.Marshal(map[string]any{
		"info":  map[string]any{"alias": "iPhone", "version": "2.1"},
		"files": map[string]any{"m": map[string]any{"id": "m", "fileName": "m.txt", "size": len(text), "fileType": "text/plain", "preview": text}},
	})
	if resp, _ := h.post("prepare-upload", b); resp.StatusCode != 204 {
		t.Fatalf("a message got %d, want 204", resp.StatusCode)
	}
	if e := h.wait("text"); e["text"] != text || e["from"] != "iPhone" {
		t.Fatalf("text event %v", e)
	}
	entries, _ := os.ReadDir(h.folder)
	if len(entries) != 0 {
		t.Fatalf("a message left files: %v", entries)
	}
}

// A file that isn't what was announced is deleted, and the session ends.
func TestLsBadUploads(t *testing.T) {
	for _, tc := range []struct {
		name   string
		sent   []byte
		status int
	}{
		{"too short", []byte("hell"), 500},
		{"too long", []byte("hello world"), 500},
		{"wrong checksum", []byte("HELLO"), 422},
	} {
		t.Run(tc.name, func(t *testing.T) {
			h := newLsHarness(t)
			resp, out := h.prepare(prepareBody(map[string][]byte{"1": []byte("hello")}, map[string]string{"1": "f.txt"}, true), true)
			if resp.StatusCode != 200 {
				t.Fatalf("prepare-upload: %d", resp.StatusCode)
			}
			url := fmt.Sprintf("upload?sessionId=%s&fileId=1&token=%s", out["sessionId"], out["files"].(map[string]any)["1"])
			if resp, b := h.post(url, tc.sent); resp.StatusCode != tc.status {
				t.Fatalf("got %d %s, want %d", resp.StatusCode, b, tc.status)
			}
			h.wait("failed")
			if _, err := os.Stat(filepath.Join(h.folder, "f.txt")); err == nil {
				t.Fatal("the bad file was kept")
			}
			// The next request is welcome.
			if resp, _ := h.prepare(prepareBody(map[string][]byte{"1": []byte("a")}, map[string]string{"1": "a"}, false), true); resp.StatusCode != 200 {
				t.Fatalf("after a failure, a request got %d", resp.StatusCode)
			}
		})
	}
}

func TestLsSenderCancels(t *testing.T) {
	h := newLsHarness(t)
	resp, out := h.prepare(prepareBody(map[string][]byte{"1": []byte("a"), "2": []byte("b")}, map[string]string{"1": "a", "2": "b"}, false), true)
	if resp.StatusCode != 200 {
		t.Fatalf("prepare-upload: %d", resp.StatusCode)
	}
	h.post(fmt.Sprintf("cancel?sessionId=%s", out["sessionId"]), nil)
	if e := h.wait("failed"); !strings.Contains(e["message"].(string), "cancelled") {
		t.Fatalf("failed event %v", e)
	}
	url := fmt.Sprintf("upload?sessionId=%s&fileId=1&token=%s", out["sessionId"], out["files"].(map[string]any)["1"])
	if resp, _ := h.post(url, []byte("a")); resp.StatusCode != 403 {
		t.Fatalf("an upload after cancel got %d, want 403", resp.StatusCode)
	}
}

// The shell's ops turn it on, and a second one on the same port says why
// it can't.
func TestLsSwitch(t *testing.T) {
	var events []map[string]any
	emit := func(v any) { events = append(events, v.(map[string]any)) }
	ln, _ := net.Listen("tcp", "127.0.0.1:0")
	port := ln.Addr().(*net.TCPAddr).Port
	ln.Close()
	cfg := fmt.Sprintf(`{"op":"localsend","enabled":true,"alias":"a","folder":%q,"stateDir":%q,"port":%d,"local":true}`, t.TempDir(), t.TempDir(), port)

	nested := &localsend{emit: emit, nested: true}
	nested.op("localsend", []byte(strings.Replace(cfg, `"local":true`, `"local":false`, 1)))
	if nested.r != nil {
		t.Fatal("a nested session got a receiver on the real network")
	}
	l := &localsend{emit: emit}
	l.op("localsend", []byte(cfg))
	if l.r == nil || events[len(events)-1]["kind"] != "ready" {
		t.Fatalf("not on: %v", events)
	}
	other := &localsend{emit: emit}
	other.op("localsend", []byte(cfg))
	if e := events[len(events)-1]; e["kind"] != "error" || !strings.Contains(e["message"].(string), "taken") {
		t.Fatalf("a taken port: %v", e)
	}
	l.op("localsend", []byte(`{"op":"localsend","enabled":false}`))
	if l.r != nil {
		t.Fatal("still on")
	}
}
