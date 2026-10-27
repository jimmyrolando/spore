package main

import (
	"context"
	"errors"
	"io/fs"
	"path/filepath"
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
