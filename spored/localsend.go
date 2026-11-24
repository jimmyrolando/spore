package main

// Receiving files with LocalSend's protocol (v2, https://github.com/localsend/protocol),
// so the LocalSend app on an iPhone, a Mac or Android sends straight to
// Spore. Only receiving: sending stays in the LocalSend app for now.
//
// It's a server on the local network, so nothing comes in without the user:
// every request waits for Accept in the shell's notification, one at a time.
// What comes in is written under the chosen folder only: names are cleaned
// of "..", slashes and control characters, a folder sent gets a new folder
// of its own, files are created and never replaced (O_EXCL, which doesn't
// follow a link either), and the sizes and checksums the sender announced
// are held to.
//
// The shell turns it on and off ({"op":"localsend"}, service.go) and gets
// its events:
//
//	→ {"event":"localsend","kind":"ready","alias":…,"port":…}
//	→ {"event":"localsend","kind":"error","message":…}      it couldn't start (the port is taken)
//	→ {"event":"localsend","kind":"request","session":…,"from":…,"device":…,"count":…,"size":…,"names":[…]}
//	← {"op":"localsend-answer","session":…,"accept":true}
//	→ {"event":"localsend","kind":"progress","session":…,"received":…,"size":…}
//	→ {"event":"localsend","kind":"done","session":…,"from":…,"count":…,"paths":[…]}
//	→ {"event":"localsend","kind":"failed","session":…,"from":…,"message":…}
//	← {"op":"localsend-cancel","session":…}
//	→ {"event":"localsend","kind":"text","from":…,"text":…}  a message, not a file
//
// The certificate is made once and kept (state folder, localsend/): the
// sender pins it by its fingerprint, the SHA-256 of its DER in upper-case
// hex, as the official app computes it.

import (
	"context"
	"crypto/rand"
	"crypto/rsa"
	"crypto/sha256"
	"crypto/subtle"
	"crypto/tls"
	"crypto/x509"
	"crypto/x509/pkix"
	"encoding/hex"
	"encoding/json"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"math/big"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
	"unicode"
	"unicode/utf8"
)

const (
	lsPort    = 53317
	lsGroup   = "224.0.0.167"
	lsVersion = "2.1"
	lsAPI     = "/api/localsend/v2/"
	// How long a request waits for Accept before it's declined.
	lsAnswerWait = 2 * time.Minute
	// At most this many files in one request (a sender's folder).
	lsMaxFiles = 10000
)

type lsConfig struct {
	Alias string `json:"alias"`
	// Where files go (an absolute path; made if missing).
	Folder string `json:"folder"`
	// Where the certificate is kept.
	StateDir string `json:"stateDir"`
	// 0: LocalSend's. A test uses another one with Local.
	Port int `json:"port"`
	// Only on 127.0.0.1 and without multicast (the nested test session).
	Local bool `json:"local"`
}

// What a device says about itself: in an announcement, /register and
// /info, and in prepare-upload's "info".
type lsInfo struct {
	Alias       string  `json:"alias"`
	Version     string  `json:"version"`
	DeviceModel *string `json:"deviceModel"`
	DeviceType  *string `json:"deviceType"`
	Fingerprint string  `json:"fingerprint"`
	Port        int     `json:"port,omitempty"`
	Protocol    string  `json:"protocol,omitempty"`
	Download    bool    `json:"download"`
	Announce    *bool   `json:"announce,omitempty"`
}

type lsFile struct {
	ID       string  `json:"id"`
	FileName string  `json:"fileName"`
	Size     int64   `json:"size"`
	FileType string  `json:"fileType"`
	SHA256   *string `json:"sha256"`
	Preview  *string `json:"preview"`
}

type lsIncoming struct {
	file    lsFile
	token   string
	started bool
	done    bool
}

type lsSession struct {
	id     string
	ip     string
	from   string
	files  map[string]*lsIncoming
	size   int64
	answer chan bool
	// After Accept.
	accepted bool
	received int64
	// The folders a sent folder became, by the name it was sent with (topMu:
	// two of its files coming in at once make it once).
	topMu sync.Mutex
	tops  map[string]string
	// What it wrote at the top of the folder, for "done".
	paths    []string
	ctx      context.Context
	cancel   context.CancelFunc
	reported time.Time
}

type receiver struct {
	cfg         lsConfig
	emit        func(any)
	fingerprint string
	server      *http.Server
	udp         *net.UDPConn
	// Answering announcements: any certificate (only who it is is asked).
	client *http.Client

	mu      sync.Mutex
	session *lsSession
	closed  bool
}

// The receiver starts listening, or says why it can't.
func startReceiver(cfg lsConfig, emit func(any)) (*receiver, error) {
	if cfg.Port == 0 {
		cfg.Port = lsPort
	}
	if cfg.Alias == "" {
		cfg.Alias, _ = os.Hostname()
	}
	cert, err := lsCertificate(filepath.Join(cfg.StateDir, "localsend"))
	if err != nil {
		return nil, fmt.Errorf("the certificate: %w", err)
	}
	r := &receiver{
		cfg:         cfg,
		emit:        emit,
		fingerprint: lsFingerprint(cert.Certificate[0]),
		client: &http.Client{
			Timeout:   3 * time.Second,
			Transport: &http.Transport{TLSClientConfig: &tls.Config{InsecureSkipVerify: true}},
		},
	}
	host := ""
	if cfg.Local {
		host = "127.0.0.1"
	}
	ln, err := net.Listen("tcp", net.JoinHostPort(host, strconv.Itoa(cfg.Port)))
	if err != nil {
		return nil, err
	}
	mux := http.NewServeMux()
	mux.HandleFunc("POST "+lsAPI+"register", r.register)
	mux.HandleFunc("GET "+lsAPI+"info", r.register)
	mux.HandleFunc("POST "+lsAPI+"prepare-upload", r.prepare)
	mux.HandleFunc("POST "+lsAPI+"upload", r.upload)
	mux.HandleFunc("POST "+lsAPI+"cancel", r.cancelled)
	r.server = &http.Server{
		Handler:           mux,
		ReadHeaderTimeout: 10 * time.Second,
		// A request waits for Accept, and a file can be big: no write timeout.
		IdleTimeout: time.Minute,
		TLSConfig:   &tls.Config{Certificates: []tls.Certificate{cert}},
		ErrorLog:    log.New(io.Discard, "", 0),
	}
	go func() { _ = r.server.ServeTLS(ln, "", "") }()
	if !cfg.Local {
		if err := r.listenMulticast(); err != nil {
			log.Printf("localsend: no multicast, so only found by a scan: %v", err)
		} else {
			go r.announce()
		}
	}
	return r, nil
}

func (r *receiver) stop() {
	r.mu.Lock()
	r.closed = true
	if s := r.session; s != nil {
		s.cancel()
		r.session = nil
	}
	r.mu.Unlock()
	if r.udp != nil {
		r.udp.Close()
	}
	ctx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()
	_ = r.server.Shutdown(ctx)
	r.server.Close()
}

func (r *receiver) info() lsInfo {
	model, kind := "Spore", "desktop"
	return lsInfo{
		Alias: r.cfg.Alias, Version: lsVersion, DeviceModel: &model, DeviceType: &kind,
		Fingerprint: r.fingerprint, Port: r.cfg.Port, Protocol: "https",
	}
}

// --- Being found ---

func (r *receiver) listenMulticast() error {
	group := &net.UDPAddr{IP: net.ParseIP(lsGroup), Port: r.cfg.Port}
	conn, err := net.ListenMulticastUDP("udp4", nil, group)
	if err != nil {
		return err
	}
	r.udp = conn
	go func() {
		buf := make([]byte, 64*1024)
		for {
			n, from, err := conn.ReadFromUDP(buf)
			if err != nil {
				return
			}
			var peer lsInfo
			if json.Unmarshal(buf[:n], &peer) != nil || peer.Fingerprint == r.fingerprint {
				continue
			}
			if peer.Announce != nil && *peer.Announce {
				go r.answerAnnouncement(from.IP, peer)
			}
		}
	}()
	return nil
}

// Says it's here when it starts: a LocalSend app already open hears it.
func (r *receiver) announce() {
	for _, wait := range []time.Duration{100 * time.Millisecond, 500 * time.Millisecond, 2 * time.Second} {
		time.Sleep(wait)
		if !r.multicast(true) {
			return
		}
	}
}

func (r *receiver) multicast(announce bool) bool {
	r.mu.Lock()
	closed := r.closed
	r.mu.Unlock()
	if closed {
		return false
	}
	msg := r.info()
	msg.Announce = &announce
	body, _ := json.Marshal(msg)
	conn, err := net.DialUDP("udp4", nil, &net.UDPAddr{IP: net.ParseIP(lsGroup), Port: r.cfg.Port})
	if err != nil {
		return true
	}
	defer conn.Close()
	_, _ = conn.Write(body)
	return true
}

// A device that just opened LocalSend asks who's there: the answer goes to
// it over HTTP (its /register), or else by multicast.
func (r *receiver) answerAnnouncement(ip net.IP, peer lsInfo) {
	scheme := "https"
	if peer.Protocol == "http" {
		scheme = "http"
	}
	port := peer.Port
	if port <= 0 || port > 65535 {
		port = lsPort
	}
	body, _ := json.Marshal(r.info())
	url := fmt.Sprintf("%s://%s%s", scheme, net.JoinHostPort(ip.String(), strconv.Itoa(port)), lsAPI+"register")
	resp, err := r.client.Post(url, "application/json", strings.NewReader(string(body)))
	if err == nil {
		io.Copy(io.Discard, io.LimitReader(resp.Body, 64*1024))
		resp.Body.Close()
		return
	}
	r.multicast(false)
}

// /register (another device found this one) and /info: who this is.
func (r *receiver) register(w http.ResponseWriter, req *http.Request) {
	writeJSON(w, r.info())
}

// --- Receiving ---

func (r *receiver) prepare(w http.ResponseWriter, req *http.Request) {
	var body struct {
		Info  lsInfo            `json:"info"`
		Files map[string]lsFile `json:"files"`
	}
	if json.NewDecoder(io.LimitReader(req.Body, 4<<20)).Decode(&body) != nil || len(body.Files) == 0 || len(body.Files) > lsMaxFiles {
		http.Error(w, "invalid body", http.StatusBadRequest)
		return
	}
	from := lsClean(body.Info.Alias, 64)
	if from == "" {
		from = "Unknown device"
	}
	device := ""
	if body.Info.DeviceModel != nil {
		device = lsClean(*body.Info.DeviceModel, 64)
	}

	// A message: one text "file" with its text in the preview. Shown, and
	// nothing to transfer.
	if len(body.Files) == 1 {
		for _, f := range body.Files {
			if f.Preview != nil && (f.FileType == "text" || strings.HasPrefix(f.FileType, "text/")) {
				r.mu.Lock()
				busy := r.session != nil
				r.mu.Unlock()
				if busy {
					http.Error(w, "blocked by another session", http.StatusConflict)
					return
				}
				text := *f.Preview
				if len(text) > 16*1024 {
					text = text[:16*1024]
				}
				r.emit(map[string]any{"event": "localsend", "kind": "text", "from": from, "text": strings.ToValidUTF8(text, "")})
				w.WriteHeader(http.StatusNoContent)
				return
			}
		}
	}

	var size int64
	names := []string{}
	files := map[string]*lsIncoming{}
	for id, f := range body.Files {
		if f.Size < 0 || id == "" {
			http.Error(w, "invalid body", http.StatusBadRequest)
			return
		}
		f.ID = id
		size += f.Size
		if len(names) < 5 {
			names = append(names, lsDisplayName(f.FileName))
		}
		files[id] = &lsIncoming{file: f, token: lsRandom(16)}
	}

	ip := remoteIP(req)
	ctx, cancel := context.WithCancel(context.Background())
	s := &lsSession{
		id: lsRandom(16), ip: ip, from: from, files: files, size: size,
		answer: make(chan bool, 1), tops: map[string]string{}, ctx: ctx, cancel: cancel,
	}
	r.mu.Lock()
	if r.session != nil || r.closed {
		r.mu.Unlock()
		cancel()
		http.Error(w, "blocked by another session", http.StatusConflict)
		return
	}
	r.session = s
	r.mu.Unlock()

	if free, ok := freeSpace(r.cfg.Folder); ok && uint64(size) > free {
		r.finish(s)
		r.emit(map[string]any{"event": "localsend", "kind": "failed", "session": s.id, "from": from,
			"message": fmt.Sprintf("%s wanted to send %d %s, but there isn't room for them", from, len(files), plural(len(files), "file", "files"))})
		http.Error(w, "not enough space", http.StatusForbidden)
		return
	}

	r.emit(map[string]any{"event": "localsend", "kind": "request", "session": s.id, "from": from, "device": device,
		"count": len(files), "size": size, "names": names})

	timer := time.NewTimer(lsAnswerWait)
	defer timer.Stop()
	accepted := false
	select {
	case accepted = <-s.answer:
	case <-timer.C:
	case <-req.Context().Done():
	case <-ctx.Done():
	}
	r.mu.Lock()
	if accepted && r.session == s && req.Context().Err() == nil {
		s.accepted = true
		r.mu.Unlock()
		tokens := map[string]string{}
		for id, f := range files {
			tokens[id] = f.token
		}
		writeJSON(w, map[string]any{"sessionId": s.id, "files": tokens})
		return
	}
	r.mu.Unlock()
	r.finish(s)
	if req.Context().Err() != nil {
		r.emit(map[string]any{"event": "localsend", "kind": "failed", "session": s.id, "from": from, "message": from + " cancelled"})
		return
	}
	// Declined, or no answer: the shell takes its question away.
	r.emit(map[string]any{"event": "localsend", "kind": "declined", "session": s.id})
	http.Error(w, "rejected", http.StatusForbidden)
}

// The shell's answer to a request.
func (r *receiver) answer(session string, accept bool) {
	r.mu.Lock()
	defer r.mu.Unlock()
	if s := r.session; s != nil && s.id == session && !s.accepted {
		select {
		case s.answer <- accept:
		default:
		}
	}
}

// The shell cancels a transfer under way (or a request).
func (r *receiver) cancel(session string) {
	r.mu.Lock()
	s := r.session
	r.mu.Unlock()
	if s == nil || s.id != session {
		return
	}
	if !s.accepted {
		r.answer(session, false)
		return
	}
	r.finish(s)
	r.emit(map[string]any{"event": "localsend", "kind": "failed", "session": s.id, "from": s.from, "message": "Cancelled"})
}

// The sender cancels.
func (r *receiver) cancelled(w http.ResponseWriter, req *http.Request) {
	r.mu.Lock()
	s := r.session
	r.mu.Unlock()
	if s != nil && s.id == req.URL.Query().Get("sessionId") && s.ip == remoteIP(req) {
		r.finish(s)
		r.emit(map[string]any{"event": "localsend", "kind": "failed", "session": s.id, "from": s.from, "message": s.from + " cancelled"})
	}
	w.WriteHeader(http.StatusOK)
}

// The session ends: what's still coming in stops (and is deleted).
func (r *receiver) finish(s *lsSession) {
	s.cancel()
	r.mu.Lock()
	if r.session == s {
		r.session = nil
	}
	r.mu.Unlock()
}

func (r *receiver) upload(w http.ResponseWriter, req *http.Request) {
	q := req.URL.Query()
	sessionID, fileID, token := q.Get("sessionId"), q.Get("fileId"), q.Get("token")
	if sessionID == "" || fileID == "" || token == "" {
		http.Error(w, "missing parameters", http.StatusBadRequest)
		return
	}
	r.mu.Lock()
	s := r.session
	var in *lsIncoming
	if s != nil && s.accepted && s.id == sessionID && s.ip == remoteIP(req) {
		in = s.files[fileID]
	}
	if in == nil || in.started || subtle.ConstantTimeCompare([]byte(in.token), []byte(token)) != 1 {
		r.mu.Unlock()
		http.Error(w, "invalid token or IP address", http.StatusForbidden)
		return
	}
	in.started = true
	r.mu.Unlock()

	path, err := r.write(s, in.file, req.Body)
	if err != nil {
		status := http.StatusInternalServerError
		if errors.Is(err, errChecksum) {
			status = http.StatusUnprocessableEntity
		}
		// Canceled by either side: already said.
		if s.ctx.Err() == nil {
			r.finish(s)
			r.emit(map[string]any{"event": "localsend", "kind": "failed", "session": s.id, "from": s.from,
				"message": "The transfer from " + s.from + " failed: " + err.Error()})
		}
		http.Error(w, err.Error(), status)
		return
	}

	r.mu.Lock()
	in.done = true
	if !containsString(s.paths, path) {
		s.paths = append(s.paths, path)
	}
	all := true
	for _, f := range s.files {
		all = all && f.done
	}
	r.mu.Unlock()
	w.WriteHeader(http.StatusOK)
	if all {
		r.finish(s)
		r.emit(map[string]any{"event": "localsend", "kind": "done", "session": s.id, "from": s.from,
			"count": len(s.files), "paths": s.paths})
	}
}

var errChecksum = errors.New("the file doesn't match its checksum")

// Writes a file as it comes in. Returns what it made at the top of the
// folder (the file, or the folder it went in).
func (r *receiver) write(s *lsSession, f lsFile, body io.Reader) (string, error) {
	if err := os.MkdirAll(r.cfg.Folder, 0o755); err != nil {
		return "", err
	}
	parts := lsPathParts(f.FileName)
	dir, top := r.cfg.Folder, ""
	if len(parts) > 1 {
		s.topMu.Lock()
		made, ok := s.tops[parts[0]]
		if !ok {
			var err error
			made, err = lsCreate(r.cfg.Folder, parts[0], func(p string) error { return os.Mkdir(p, 0o755) })
			if err != nil {
				s.topMu.Unlock()
				return "", err
			}
			s.tops[parts[0]] = made
		}
		s.topMu.Unlock()
		top = made
		dir = filepath.Join(made, filepath.Join(parts[1:len(parts)-1]...))
		if err := os.MkdirAll(dir, 0o755); err != nil {
			return "", err
		}
	}
	var out *os.File
	path, err := lsCreate(dir, parts[len(parts)-1], func(p string) error {
		var err error
		out, err = os.OpenFile(p, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o644)
		return err
	})
	if err != nil {
		return "", err
	}
	if top == "" {
		top = path
	}
	hash := sha256.New()
	n, err := io.Copy(io.MultiWriter(out, hash, &lsProgress{r: r, s: s}), &ctxReader{ctx: s.ctx, r: io.LimitReader(body, f.Size+1)})
	if cerr := out.Close(); err == nil {
		err = cerr
	}
	if err == nil && n != f.Size {
		err = fmt.Errorf("%d bytes came, not %d", n, f.Size)
	}
	if err == nil && f.SHA256 != nil && *f.SHA256 != "" && !strings.EqualFold(*f.SHA256, hex.EncodeToString(hash.Sum(nil))) {
		err = errChecksum
	}
	if err != nil {
		os.Remove(path)
		return "", err
	}
	return top, nil
}

// Counts what comes in, and tells the shell four times a second at most.
type lsProgress struct {
	r *receiver
	s *lsSession
}

func (p *lsProgress) Write(b []byte) (int, error) {
	p.r.mu.Lock()
	p.s.received += int64(len(b))
	report := time.Since(p.s.reported) > 250*time.Millisecond
	if report {
		p.s.reported = time.Now()
	}
	received := p.s.received
	p.r.mu.Unlock()
	if report {
		p.r.emit(map[string]any{"event": "localsend", "kind": "progress", "session": p.s.id, "received": received, "size": p.s.size})
	}
	return len(b), nil
}

type ctxReader struct {
	ctx context.Context
	r   io.Reader
}

func (c *ctxReader) Read(b []byte) (int, error) {
	if err := c.ctx.Err(); err != nil {
		return 0, errors.New("cancelled")
	}
	return c.r.Read(b)
}

// --- Names ---

// A name as sent ("Photos/2024/IMG_1.jpg", maybe with "\" or "..") made
// into safe parts: no empty, "." or ".." parts, no control characters, none
// too long. Never empty.
func lsPathParts(name string) []string {
	var parts []string
	for _, p := range strings.Split(strings.ReplaceAll(name, "\\", "/"), "/") {
		p = lsClean(p, 200)
		if p == "" || p == "." || p == ".." {
			continue
		}
		parts = append(parts, p)
	}
	if len(parts) == 0 {
		return []string{"file"}
	}
	// No deeper than this: a sender can't make the folders go on forever.
	if len(parts) > 32 {
		parts = append(parts[:31], parts[len(parts)-1])
	}
	return parts
}

// Without control characters and trimmed, at most max bytes (whole runes).
func lsClean(s string, max int) string {
	s = strings.Map(func(r rune) rune {
		if unicode.IsControl(r) || r == '/' {
			return -1
		}
		return r
	}, strings.ToValidUTF8(s, ""))
	s = strings.TrimSpace(s)
	for len(s) > max {
		_, size := utf8.DecodeLastRuneInString(s)
		s = s[:len(s)-size]
	}
	return s
}

func lsDisplayName(name string) string {
	parts := lsPathParts(name)
	if len(parts) > 1 {
		return parts[0] + "/…/" + parts[len(parts)-1]
	}
	return parts[0]
}

// Makes `name` in `dir` with create, or "name (1).ext", "name (2).ext"… if
// it's taken. Returns the path made.
func lsCreate(dir, name string, create func(string) error) (string, error) {
	ext := filepath.Ext(name)
	if ext == name {
		ext = ""
	}
	base := strings.TrimSuffix(name, ext)
	for i := 0; i < 1000; i++ {
		candidate := name
		if i > 0 {
			candidate = fmt.Sprintf("%s (%d)%s", base, i, ext)
		}
		path := filepath.Join(dir, candidate)
		err := create(path)
		if err == nil {
			return path, nil
		}
		if !errors.Is(err, os.ErrExist) {
			return "", err
		}
	}
	return "", fmt.Errorf("too many files called %s", name)
}

// --- The certificate ---

// Made once (RSA, like the official app's) and kept, so devices that know
// this one keep knowing it.
func lsCertificate(dir string) (tls.Certificate, error) {
	certPath, keyPath := filepath.Join(dir, "cert.pem"), filepath.Join(dir, "key.pem")
	if cert, err := tls.LoadX509KeyPair(certPath, keyPath); err == nil {
		return cert, nil
	}
	if err := os.MkdirAll(dir, 0o700); err != nil {
		return tls.Certificate{}, err
	}
	key, err := rsa.GenerateKey(rand.Reader, 2048)
	if err != nil {
		return tls.Certificate{}, err
	}
	serial, _ := rand.Int(rand.Reader, new(big.Int).Lsh(big.NewInt(1), 62))
	template := &x509.Certificate{
		SerialNumber: serial,
		Subject:      pkix.Name{CommonName: "Spore"},
		NotBefore:    time.Now().Add(-24 * time.Hour),
		NotAfter:     time.Now().AddDate(20, 0, 0),
		KeyUsage:     x509.KeyUsageDigitalSignature | x509.KeyUsageKeyEncipherment,
		ExtKeyUsage:  []x509.ExtKeyUsage{x509.ExtKeyUsageServerAuth, x509.ExtKeyUsageClientAuth},
	}
	der, err := x509.CreateCertificate(rand.Reader, template, template, &key.PublicKey, key)
	if err != nil {
		return tls.Certificate{}, err
	}
	certPEM := pem.EncodeToMemory(&pem.Block{Type: "CERTIFICATE", Bytes: der})
	keyPEM := pem.EncodeToMemory(&pem.Block{Type: "RSA PRIVATE KEY", Bytes: x509.MarshalPKCS1PrivateKey(key)})
	if err := os.WriteFile(keyPath, keyPEM, 0o600); err != nil {
		return tls.Certificate{}, err
	}
	if err := os.WriteFile(certPath, certPEM, 0o644); err != nil {
		return tls.Certificate{}, err
	}
	return tls.X509KeyPair(certPEM, keyPEM)
}

// The official app's: SHA-256 of the certificate's DER, upper-case hex.
func lsFingerprint(der []byte) string {
	sum := sha256.Sum256(der)
	return strings.ToUpper(hex.EncodeToString(sum[:]))
}

// --- Small things ---

func lsRandom(n int) string {
	b := make([]byte, n)
	_, _ = rand.Read(b)
	return hex.EncodeToString(b)
}

func remoteIP(req *http.Request) string {
	host, _, err := net.SplitHostPort(req.RemoteAddr)
	if err != nil {
		return req.RemoteAddr
	}
	return host
}

func writeJSON(w http.ResponseWriter, v any) {
	w.Header().Set("Content-Type", "application/json")
	_ = json.NewEncoder(w).Encode(v)
}

func freeSpace(dir string) (uint64, bool) {
	for d := dir; ; d = filepath.Dir(d) {
		var st syscall.Statfs_t
		if syscall.Statfs(d, &st) == nil {
			return st.Bavail * uint64(st.Bsize), true
		}
		if d == filepath.Dir(d) {
			return 0, false
		}
	}
}

func plural(n int, one, many string) string {
	if n == 1 {
		return one
	}
	return many
}

func containsString(list []string, s string) bool {
	for _, x := range list {
		if x == s {
			return true
		}
	}
	return false
}

// --- The shell's switch ---

// Turns the receiver on, off or over again with the shell's ops. In a
// nested test session, only a local one (on 127.0.0.1, without multicast):
// the real network is the real session's.
type localsend struct {
	emit   func(any)
	nested bool

	mu  sync.Mutex
	r   *receiver
	cfg lsConfig
}

func (l *localsend) op(op string, line []byte) {
	var msg struct {
		lsConfig
		Enabled bool   `json:"enabled"`
		Session string `json:"session"`
		Accept  bool   `json:"accept"`
	}
	if json.Unmarshal(line, &msg) != nil {
		return
	}
	l.mu.Lock()
	r := l.r
	l.mu.Unlock()
	switch op {
	case "localsend":
		l.configure(msg.Enabled, msg.lsConfig)
	case "localsend-answer":
		if r != nil {
			r.answer(msg.Session, msg.Accept)
		}
	case "localsend-cancel":
		if r != nil {
			r.cancel(msg.Session)
		}
	}
}

func (l *localsend) configure(enabled bool, cfg lsConfig) {
	l.mu.Lock()
	defer l.mu.Unlock()
	if enabled && l.nested && !cfg.Local {
		enabled = false
	}
	if l.r != nil && enabled && cfg == l.cfg {
		return
	}
	if l.r != nil {
		l.r.stop()
		l.r = nil
	}
	l.cfg = cfg
	if !enabled {
		return
	}
	if cfg.Folder == "" || !filepath.IsAbs(cfg.Folder) || cfg.StateDir == "" {
		l.emit(map[string]any{"event": "localsend", "kind": "error", "message": "no folder to save to"})
		return
	}
	r, err := startReceiver(cfg, l.emit)
	if err != nil {
		msg := err.Error()
		if errors.Is(err, syscall.EADDRINUSE) {
			msg = fmt.Sprintf("port %d is taken (is the LocalSend app open?)", lsPortOr(cfg.Port))
		}
		log.Printf("localsend: %s", msg)
		l.emit(map[string]any{"event": "localsend", "kind": "error", "message": msg})
		return
	}
	l.r = r
	l.emit(map[string]any{"event": "localsend", "kind": "ready", "alias": r.cfg.Alias, "port": r.cfg.Port})
}

func lsPortOr(port int) int {
	if port == 0 {
		return lsPort
	}
	return port
}
