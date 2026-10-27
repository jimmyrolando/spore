package main

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
	"strings"
	"sync"
	"syscall"
	"time"

	"golang.org/x/sys/unix"
)

// What a folder holds, for the quick view (Space on a folder): its files and
// folders, all the way down, and what they weigh. Counted as it walks, so a
// big one (the home folder) shows its numbers growing; moving on cancels it.
type count struct {
	Files   int64 `json:"files"`
	Folders int64 `json:"folders"`
	Bytes   int64 `json:"bytes"`
	// Folders it couldn't read (the numbers are then "at least").
	Unreadable int64 `json:"unreadable,omitempty"`
}

// The kernel's own filesystems: their files aren't data (/proc's would count
// the memory of every process, and some never end). Not entered when they're
// mounted inside the folder counted.
var virtualFS = map[int64]bool{
	unix.PROC_SUPER_MAGIC:    true,
	unix.SYSFS_MAGIC:         true,
	unix.CGROUP_SUPER_MAGIC:  true,
	unix.CGROUP2_SUPER_MAGIC: true,
	unix.DEBUGFS_MAGIC:       true,
	unix.TRACEFS_MAGIC:       true,
	unix.SECURITYFS_MAGIC:    true,
	unix.PSTOREFS_MAGIC:      true,
	unix.BPF_FS_MAGIC:        true,
	unix.DEVPTS_SUPER_MAGIC:  true,
	unix.BINFMTFS_MAGIC:      true,
	unix.EFIVARFS_MAGIC:      true,
	unix.HUGETLBFS_MAGIC:     true,
	0x19800202:               true, // mqueue (these three have no name in x/sys)
	unix.AUTOFS_SUPER_MAGIC:  true,
	0x65735543:               true, // fusectl
	0x62656570:               true, // configfs
	unix.SELINUX_MAGIC:       true,
	unix.SMACK_MAGIC:         true,
	unix.NSFS_MAGIC:          true,
}

// A folder of the kernel's (/proc, /sys): nothing to count.
var errVirtual = errors.New("a virtual filesystem")

// The counts already made, for as long as Files is open: Space on a folder
// counted before shows its numbers at once while it's counted again. What
// Files changes is forgotten (see forget). Only the folders asked for: a
// subfolder's numbers from its parent's walk can be far off (a hard link
// weighs in whichever folder is walked first, and builds and git leave
// thousands).
type folderCounts struct {
	mu sync.Mutex
	m  map[string]count
}

// Past this many it starts over.
const maxCounts = 10000

func newFolderCounts() *folderCounts {
	return &folderCounts{m: map[string]count{}}
}

func (k *folderCounts) get(path string) (count, bool) {
	if k == nil {
		return count{}, false
	}
	k.mu.Lock()
	defer k.mu.Unlock()
	c, ok := k.m[path]
	return c, ok
}

func (k *folderCounts) put(path string, c count) {
	if k == nil {
		return
	}
	k.mu.Lock()
	defer k.mu.Unlock()
	if len(k.m) >= maxCounts {
		k.m = map[string]count{}
	}
	k.m[path] = c
}

// Forgets the counts that something changed at `paths` makes wrong: theirs,
// what's inside them, and every folder above them.
func (k *folderCounts) forget(paths ...string) {
	if k == nil {
		return
	}
	k.mu.Lock()
	defer k.mu.Unlock()
	for _, path := range paths {
		if path == "" {
			continue
		}
		path = filepath.Clean(path)
		for p := range k.m {
			if strings.HasPrefix(p, path+"/") {
				delete(k.m, p)
			}
		}
		for p := path; ; p = filepath.Dir(p) {
			delete(k.m, p)
			if p == "/" || p == "." {
				break
			}
		}
	}
}

// Counts what's in `root` (not root itself), calling `seen` at most every
// 200 ms on the way. A file with several hard links weighs once, as du
// counts it.
func countFolder(ctx context.Context, root string, seen func(count)) (c count, err error) {
	if virtual(root) {
		return c, errVirtual
	}
	var rootDev uint64
	if st, ok := lstat(root); ok {
		rootDev = uint64(st.Dev)
	}
	type inode struct{ dev, ino uint64 }
	linked := map[inode]bool{}
	last := time.Now()
	err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
		if ctx.Err() != nil {
			return ctx.Err()
		}
		if err != nil {
			// The folder itself, unreadable: the error is the answer.
			if path == root {
				return err
			}
			if d != nil && d.IsDir() {
				c.Unreadable++
			}
			return nil
		}
		if path == root {
			return nil
		}
		if d.IsDir() {
			c.Folders++
			if st, ok := lstat(path); ok && uint64(st.Dev) != rootDev && virtual(path) {
				return fs.SkipDir
			}
		} else {
			c.Files++
			if d.Type().IsRegular() {
				if st, ok := lstat(path); ok {
					if st.Nlink > 1 {
						key := inode{uint64(st.Dev), st.Ino}
						if linked[key] {
							return nil
						}
						linked[key] = true
					}
					c.Bytes += st.Size
				}
			}
		}
		if now := time.Now(); now.Sub(last) >= 200*time.Millisecond {
			last = now
			seen(c)
		}
		return nil
	})
	return
}

func lstat(path string) (*syscall.Stat_t, bool) {
	var st syscall.Stat_t
	if syscall.Lstat(path, &st) != nil {
		return nil, false
	}
	return &st, true
}

func virtual(path string) bool {
	var st unix.Statfs_t
	return unix.Statfs(path, &st) == nil && virtualFS[int64(st.Type)]
}
