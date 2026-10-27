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

## Next candidates

1. The engine of Files' operations (`shell/files/FileOps.qml`): copies with
   exact progress, no-overwrite renames from the kernel (`renameat2`), no
   quoting or argument-length limits.
2. Anything else that today is a script watching a D-Bus monitor.

Talking to the shell, when a service needs it: JSON lines over a Unix
socket (Quickshell.Io's `Socket`), with a protocol version, since in dev
mode the QML comes from the checkout and spored from the package.

## Building

- Nix: `nix/spored.nix` (`buildGoModule`, which also runs the tests);
  spore-shell links it into its `bin`. After changing `go.mod`, update
  `vendorHash` there.
- Elsewhere: `install.sh` builds it if Go is installed. Without it, Spore
  works the same, minus these services.
- By hand: `CGO_ENABLED=0 go build -trimpath -ldflags="-s -w" .`, and
  `go test ./...`.

Its version is Spore's (`tools/test.sh` checks that they match).
