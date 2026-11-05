package main

import (
	"bytes"
	"strings"
	"testing"
)

func TestServiceMessages(t *testing.T) {
	var out bytes.Buffer
	s := newService(&out)
	s.hello(nil)
	s.event("drives")
	want := `{"hello":"spored","protocol":1,"services":[]}` + "\n" + `{"event":"drives"}` + "\n"
	if out.String() != want {
		t.Errorf("got %q, want %q", out.String(), want)
	}

	locked := 0
	s.onLocked = func() { locked++ }
	s.read(strings.NewReader("{\"op\":\"locked\"}\nnot json\n{\"op\":\"other\"}\n{\"op\":\"locked\"}\n"))
	if locked != 2 {
		t.Errorf("locked %d times, want 2", locked)
	}
}
