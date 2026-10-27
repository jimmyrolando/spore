package main

import (
	"reflect"
	"testing"
)

func TestItemTargets(t *testing.T) {
	got := itemTargets([]string{
		"file:///home/a/Downloads/one.pdf",
		"file:///home/a/Downloads/two%2Fslash.pdf",
		"file:///home/a/Music/song.mp3",
		"FILE:///home/a/Pictures/",
		"sftp://host/home/a/x",
	})
	want := []string{
		"file:///home/a/Downloads/one.pdf",
		"file:///home/a/Music/song.mp3",
		"FILE:///home/a/Pictures",
	}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("itemTargets = %q, want %q", got, want)
	}
}

func TestFolderTargets(t *testing.T) {
	got := folderTargets([]string{"file:///tmp", "file:///tmp", "smb://nas/share", "file:///home"})
	want := []string{"file:///tmp", "file:///home"}
	if !reflect.DeepEqual(got, want) {
		t.Errorf("folderTargets = %q, want %q", got, want)
	}
}

func TestShowOpensEachTarget(t *testing.T) {
	var opened []string
	fm := &fileManager{open: func(uri string) error {
		opened = append(opened, uri)
		return nil
	}}
	if err := fm.ShowItems([]string{"file:///a/b.txt", "file:///a/c.txt"}, ""); err != nil {
		t.Fatal(err)
	}
	if want := []string{"file:///a/b.txt"}; !reflect.DeepEqual(opened, want) {
		t.Errorf("opened %q, want %q", opened, want)
	}
}
