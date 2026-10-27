# spored

Spore's services: what the shell needs and Quickshell can't do on its own,
in one small Go program with no runtime dependencies.

## Where it fits

- The shell (QML) draws everything and keeps doing what Quickshell does
  well: PipeWire, Bluetooth, MPRIS, the tray, notifications, and one-line
  commands (`niri msg`, `hyprctl`).
- spored does what needs a real program: owning a D-Bus name, and later,
  work that's fragile in `sh -c` scripts inside QML.
- `shell/services/Spored.qml` starts it with the session (not in a nested
  test session, which shares the real bus) and starts it again if it ends.
  It runs with the session's environment and ends with the shell.

## What it offers

- `org.freedesktop.FileManager1`: a browser's "Show in folder" (and any
  app's) opens Spore Files with the file selected. Thunar offers the same
  name and doesn't let it be taken: whoever asks first keeps it. spored asks
  at login, before anything starts Thunar; if Thunar already has it, spored
  waits in the queue.
- `spored files` (files.go, fileops.go): the engine of Files' operations.
  Files starts it as its child and they talk in JSON lines on its stdin and
  stdout (the protocol is at the top of files.go); it ends when Files does.
  It copies, moves, checks what a paste would collide with, renames, makes
  folders and deletes for good: progress by the bytes really copied (the
  kernel's `copy_file_range`), renames that never replace (`renameat2` with
  `RENAME_NOREPLACE`), a move to another disk with its progress, cancel
  as a message, and no quoting or argument-length limits. The queue and the
  questions stay in `shell/files/FileOps.qml`.
  It also counts what a folder holds for the quick view (Space on a
  folder): files, folders and their weight, growing as it walks, beside
  whatever job is under way; moving on cancels it.

  It says hello with a protocol number first. Without spored, or with
  another protocol (dev mode: the QML from the checkout, spored from the
  package), FileOps does everything with its old scripts. They go once
  releases ship spored built.

## Next candidates

1. The Trash (send, restore, purge, empty), following the freedesktop spec,
   other disks' Trash folders included. Today `gio trash` and scripts.
2. Anything else that today is a script watching a D-Bus monitor.

Compressing and extracting stay with bsdtar: Go reads neither 7z nor rar.

## Building

- Nix: `nix/spored.nix` (`buildGoModule`, which also runs the tests);
  spore-shell links it into its `bin`. After changing `go.mod`, update
  `vendorHash` there.
- Elsewhere: `install.sh` builds it if Go is installed. Without it, Spore
  works the same, minus these services.
- By hand: `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" .`, and
  `go test ./...`.

Its version is Spore's (`tools/test.sh` checks that they match).
