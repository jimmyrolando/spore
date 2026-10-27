package main

import (
	"context"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"os"
	"os/exec"
	"path/filepath"
	"strconv"
	"strings"
	"sync/atomic"
	"syscall"

	"golang.org/x/sys/unix"
)

// Files' operations, with the rules shell/files/FileOps.qml has always had,
// so nothing is ever lost:
//   - Nothing is overwritten. A name that's taken keeps both (the new one
//     becomes "name (2)"), is skipped, or, if the user says replace, the old
//     one goes to the Trash first.
//   - A copy is written under a hidden temporary name in the destination and
//     renamed when it's complete, with RENAME_NOREPLACE: one that fails or is
//     canceled never leaves a half file with the real name, and a name taken
//     meanwhile by another program is an error, never overwritten.

// The base name, as the user sees it.
func quoted(path string) string {
	return "“" + filepath.Base(path) + "”"
}

// The system's reason, briefly and in lower case ("permission denied").
func reasonOf(err error) string {
	var errno syscall.Errno
	if errors.As(err, &errno) {
		return errno.Error()
	}
	var pathErr *fs.PathError
	if errors.As(err, &pathErr) {
		return pathErr.Err.Error()
	}
	return err.Error()
}

func failure(message string, err error) result {
	if err == nil {
		return result{err: message}
	}
	reason := reasonOf(err)
	return result{err: message + ": " + reason, reason: reason}
}

// exists: something is there (a broken link counts).
func exists(path string) bool {
	_, err := os.Lstat(path)
	return err == nil
}

// "name (2).ext", "name (3).ext"…, the first that's free next to `target`
// (a folder keeps its dots: "v1.2" becomes "v1.2 (2)").
func freeName(target string, isDir bool) string {
	dir, name := filepath.Split(target)
	base, ext := name, ""
	if !isDir {
		if i := strings.LastIndex(name, "."); i > 0 {
			base, ext = name[:i], name[i:]
		}
	}
	for k := 2; ; k++ {
		candidate := filepath.Join(dir, base+" ("+strconv.Itoa(k)+")"+ext)
		if !exists(candidate) {
			return candidate
		}
	}
}

// Renames without ever replacing: the kernel refuses if `newPath` exists.
// A filesystem without RENAME_NOREPLACE (some FUSE, old NFS) gets a check
// and a plain rename, as mv --update=none-fail does.
func renameNoReplace(oldPath, newPath string) error {
	err := unix.Renameat2(unix.AT_FDCWD, oldPath, unix.AT_FDCWD, newPath, unix.RENAME_NOREPLACE)
	if errors.Is(err, unix.EINVAL) || errors.Is(err, unix.ENOSYS) {
		if exists(newPath) {
			return &os.LinkError{Op: "rename", Old: oldPath, New: newPath, Err: unix.EEXIST}
		}
		return os.Rename(oldPath, newPath)
	}
	if err != nil {
		return &os.LinkError{Op: "rename", Old: oldPath, New: newPath, Err: err}
	}
	return nil
}

// The names in `sources` already in `dest` (another file, not the source
// itself): what a paste asks about.
func check(sources []string, dest string) result {
	var names []string
	for _, src := range sources {
		target := filepath.Join(dest, filepath.Base(src))
		if exists(target) && !sameFile(src, target) {
			names = append(names, filepath.Base(src))
		}
	}
	return result{names: names}
}

// Like the shell's -ef: the same file, following links.
func sameFile(a, b string) bool {
	ia, errA := os.Stat(a)
	ib, errB := os.Stat(b)
	return errA == nil && errB == nil && os.SameFile(ia, ib)
}

// What's in `paths`, counted without following links: the regular files'
// bytes, and every item.
func measure(ctx context.Context, paths []string) (bytes, items int64, err error) {
	for _, root := range paths {
		err = filepath.WalkDir(root, func(path string, d fs.DirEntry, err error) error {
			if ctx.Err() != nil {
				return ctx.Err()
			}
			if err != nil {
				return nil
			}
			items++
			if d.Type().IsRegular() {
				if info, err := d.Info(); err == nil {
					bytes += info.Size()
				}
			}
			return nil
		})
		if err != nil {
			return
		}
	}
	return
}

var tmpCount atomic.Int64

// A hidden name in `dir` for a copy in progress. Not named after the file:
// one of 235 bytes or more left no room in the 255 a name can have.
func tmpName(dir string) string {
	return filepath.Join(dir, fmt.Sprintf(".spore-copy-%d-%d", os.Getpid(), tmpCount.Add(1)))
}

// Copies or moves (mode) `sources` into `dest`; `policy` is what to do with a
// name that's taken (replace, keep or skip). Pasting into its own folder, a
// copy keeps both and a move does nothing. total gets what there is to copy
// (for a move, only what crosses to another disk).
func transfer(ctx context.Context, mode string, sources []string, dest, policy string, total func(bytes, items int64), p *progress) result {
	var placed []string
	stop := func(r result) result {
		r.names = placed
		return r
	}

	// What will be copied: everything for a copy; for a move, what's on
	// another disk (within one it's a rename, instant).
	toCopy := sources
	if mode == "move" {
		toCopy = nil
		if destInfo, err := os.Stat(dest); err == nil {
			for _, src := range sources {
				if info, err := os.Lstat(src); err == nil && deviceOf(info) != deviceOf(destInfo) {
					toCopy = append(toCopy, src)
				}
			}
		}
	}
	if len(toCopy) > 0 {
		bytes, items, err := measure(ctx, toCopy)
		if ctx.Err() != nil {
			return stop(result{canceled: true})
		}
		if err == nil {
			total(bytes, items)
		}
	}

	verb := "copy"
	if mode == "move" {
		verb = "move"
	}
	for _, src := range sources {
		if ctx.Err() != nil {
			return stop(result{canceled: true})
		}
		name := filepath.Base(src)
		target := filepath.Join(dest, name)
		info, err := os.Lstat(src)
		if err != nil {
			return stop(failure("Couldn't "+verb+" "+quoted(src), err))
		}
		if exists(target) {
			what := policy
			if sameFile(src, target) {
				if mode == "move" {
					continue
				}
				what = "keep"
			}
			switch what {
			case "skip":
				continue
			case "replace":
				// What's pasted is inside the one it replaces (a/b/b pasted
				// into a): it would go to the Trash along with it.
				if strings.HasPrefix(src+"/", target+"/") {
					return stop(result{err: "Can't replace " + quoted(target) + " with something inside it"})
				}
				if err := exec.Command("gio", "trash", "--", target).Run(); err != nil {
					return stop(result{err: "Couldn't move the old " + quoted(target) + " to the Trash"})
				}
			default:
				target = freeName(target, info.IsDir())
			}
		}

		if mode == "move" {
			err := renameNoReplace(src, target)
			if err == nil {
				placed = append(placed, filepath.Base(target))
				p.add(0, 1, name)
				continue
			}
			if !errors.Is(err, unix.EXDEV) {
				return stop(failure("Couldn't move "+quoted(src), err))
			}
			// Another disk: copied, then the original deleted.
		}
		if r := copyInto(ctx, src, target, p); r.err != "" || r.canceled {
			return stop(r)
		}
		placed = append(placed, filepath.Base(target))
		if mode == "move" {
			if err := removeAll(src); err != nil {
				return stop(failure("Moved "+quoted(src)+", but couldn't delete the original", err))
			}
		}
	}
	return stop(result{})
}

func deviceOf(info os.FileInfo) uint64 {
	if st, ok := info.Sys().(*syscall.Stat_t); ok {
		return uint64(st.Dev)
	}
	return 0
}

// `src` to `target`, through a temporary next to it.
func copyInto(ctx context.Context, src, target string, p *progress) result {
	tmp := tmpName(filepath.Dir(target))
	err := copyTree(ctx, src, tmp, p)
	if err == nil {
		err = renameNoReplace(tmp, target)
	}
	if err != nil {
		_ = removeAll(tmp)
		if ctx.Err() != nil {
			return result{canceled: true}
		}
		return failure("Couldn't copy "+quoted(src), err)
	}
	return result{}
}

// Like cp -a, without following links: folders, files, links and pipes,
// with their permissions, times and (when allowed) owners. A folder is made
// writable while it's filled, and gets its own mode at the end.
func copyTree(ctx context.Context, src, dst string, p *progress) error {
	if err := ctx.Err(); err != nil {
		return err
	}
	info, err := os.Lstat(src)
	if err != nil {
		return err
	}
	mode := info.Mode()
	switch {
	case mode&fs.ModeSymlink != 0:
		link, err := os.Readlink(src)
		if err != nil {
			return err
		}
		if err := os.Symlink(link, dst); err != nil {
			return err
		}
	case mode.IsDir():
		if err := os.Mkdir(dst, 0o700); err != nil {
			return err
		}
		entries, err := os.ReadDir(src)
		if err != nil {
			return err
		}
		for _, entry := range entries {
			if err := copyTree(ctx, filepath.Join(src, entry.Name()), filepath.Join(dst, entry.Name()), p); err != nil {
				return err
			}
		}
		if err := os.Chmod(dst, mode.Perm()|mode&(fs.ModeSetgid|fs.ModeSticky)); err != nil {
			return err
		}
	case mode.IsRegular():
		if err := copyFile(ctx, src, dst, info, p); err != nil {
			return err
		}
	case mode&fs.ModeNamedPipe != 0:
		if err := unix.Mkfifo(dst, uint32(mode.Perm())); err != nil {
			return err
		}
	default:
		return fmt.Errorf("%s: %w", filepath.Base(src), errors.New("a device or socket can't be copied"))
	}
	keepOwnerAndTimes(dst, info)
	if !mode.IsDir() {
		p.add(0, 1, filepath.Base(src))
	} else {
		p.add(0, 1, "")
	}
	return nil
}

// A file's contents in pieces (the kernel's copy_file_range under io.Copy),
// for the progress and to stop in time.
func copyFile(ctx context.Context, src, dst string, info os.FileInfo, p *progress) error {
	in, err := os.Open(src)
	if err != nil {
		return err
	}
	defer in.Close()
	out, err := os.OpenFile(dst, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0o600)
	if err != nil {
		return err
	}
	name := filepath.Base(src)
	for {
		if err := ctx.Err(); err != nil {
			out.Close()
			return err
		}
		n, err := io.CopyN(out, in, 8<<20)
		p.add(n, 0, name)
		if err == io.EOF {
			break
		}
		if err != nil {
			out.Close()
			return err
		}
	}
	if err := out.Chmod(info.Mode().Perm() | info.Mode()&(fs.ModeSetuid|fs.ModeSetgid|fs.ModeSticky)); err != nil {
		out.Close()
		return err
	}
	return out.Close()
}

// The owner (only root can give a file away: otherwise it stays the user's,
// as with cp -a) and the times, without following links.
func keepOwnerAndTimes(dst string, info os.FileInfo) {
	st, ok := info.Sys().(*syscall.Stat_t)
	if !ok {
		return
	}
	_ = os.Lchown(dst, int(st.Uid), int(st.Gid))
	times := []unix.Timespec{unix.NsecToTimespec(syscall.TimespecToNsec(st.Atim)), unix.NsecToTimespec(syscall.TimespecToNsec(st.Mtim))}
	_ = unix.UtimesNanoAt(unix.AT_FDCWD, dst, times, unix.AT_SYMLINK_NOFOLLOW)
}

// Deleted for good. Folders without write permission (a Go module cache,
// files from a read-only disk) get it first, or what's inside them couldn't
// go; links are never followed.
func removeAll(path string) error {
	_ = filepath.WalkDir(path, func(p string, d fs.DirEntry, err error) error {
		if err == nil && d.IsDir() {
			if info, err := d.Info(); err == nil && info.Mode().Perm()&0o700 != 0o700 {
				_ = os.Chmod(p, info.Mode().Perm()|0o700)
			}
		}
		return nil
	})
	return os.RemoveAll(path)
}

// Shift+Delete: full paths, gone for good. Never / or a relative path.
func remove(ctx context.Context, paths []string) result {
	var gone []string
	for _, path := range paths {
		if ctx.Err() != nil {
			return result{names: gone, canceled: true}
		}
		if !filepath.IsAbs(path) || filepath.Clean(path) == "/" {
			continue
		}
		if err := removeAll(path); err != nil {
			r := failure("Couldn't delete "+quoted(path), err)
			r.names = gone
			return r
		}
		gone = append(gone, path)
	}
	return result{names: gone}
}

// `path` to `name`, in its folder. code "exists" if the name is taken.
func rename(path, name string) result {
	if name == "" || name == "." || name == ".." || strings.Contains(name, "/") {
		return result{err: "A name can't be “.” or “..” or have a “/”"}
	}
	target := filepath.Join(filepath.Dir(path), name)
	if err := renameNoReplace(path, target); err != nil {
		if errors.Is(err, unix.EEXIST) || errors.Is(err, unix.ENOTEMPTY) {
			return result{err: "There's already something called “" + name + "” here", code: "exists"}
		}
		return failure("Couldn't rename "+quoted(path), err)
	}
	return result{names: []string{name}}
}

// "New folder" (or "New folder 2"…) in `folder`.
func newFolder(folder string) result {
	name := "New folder"
	for k := 2; ; k++ {
		err := os.Mkdir(filepath.Join(folder, name), 0o777)
		if err == nil {
			return result{names: []string{name}}
		}
		if !errors.Is(err, fs.ErrExist) {
			return failure("Couldn't make a folder here", err)
		}
		name = "New folder " + strconv.Itoa(k)
	}
}
