# Development

## Dev mode

With `programs.spore.devPath = "/path/to/checkout"`, home-manager writes that
path to `~/.config/spore/dev-path`, and `spore`, `spore-ipc` and
`spore-files` run from the checkout instead of the store. Quickshell
hot-reloads the shell (and Files, if it's open) every time a file in
`shell/` is saved.

The greeter always uses its package (`spore-greeter`). For the packages
to pick up the changes: `nix flake update spore` and rebuild the system.

Some things don't hot-reload and need a shell restart
(`pkill -x .quickshell-wra; niri msg action spawn -- spore`, or logging out;
on NixOS the process has that name because of the wrapper, and
`pkill -x quickshell` finds nothing and leaves two shells):

- `.js` files with `.pragma library` (`lucide.js`, `brand.js`, `ccutil.js`):
  Quickshell caches them.
- Moving or renaming many files: the reload sees the tree half-moved and
  fails ("X is not a type"). The shell keeps the previous version, but it
  has to be restarted to pick up the new one.
- Shaders (`.frag.qsb`): a change in a `.qml` triggers the reload, and
  changing only a shader doesn't.

**While the session is locked, the shell doesn't hot-reload.** Quickshell
0.3.1 doesn't carry a lock across a reload: it released it (the session
unlocked), or, with the lock kept, niri ended the shell for locking an
output twice. So `Lock.qml` stops watching the files while locked, and
what's saved meanwhile loads with the next save after unlocking (or a
restart). `spore-ipc lock isLocked` tells you whether it's locked.

## The automated test

`tools/test.sh` runs this checkout's shell in a nested niri, with config,
state and cache in a temporary folder, and in about 40 s:

1. checks the syntax of every shell script embedded in the QML
   (`tools/check-scripts.mjs`, `sh -n` without running them): a quote that
   closes too early, like an apostrophe in a comment inside a single-quoted
   script, breaks the whole script with no error in the log;
2. checks that the shell starts without QML or JavaScript errors in the log;
3. tests the IPC: that every target is there and that `caffeine` turns on
   and off;
4. opens every Control Center page, every Settings section and every panel
   (they only load when opened: their errors don't show up at startup);
5. opens Files on a sample folder and goes through it over IPC (folders
   first and in natural order, going in, back and up, a file with its folder,
   the filter, the hidden files, the quick view of an image, a text and a
   video, whose player has to end when the view moves on, a new folder
   renamed in place, a copy, a paste that asks, the Trash, a move,
   restoring from the Trash, deleting for good and emptying it (both asked
   first), a second window), checks each operation on disk (the Trash is the test's:
   `XDG_DATA_HOME`), then closes its last window: the process has to exit
   without crashing or leaving children;
6. locks the nested session, to see that the lockscreen loads;
7. closes the shell and checks that no orphan processes are left.

It ends with `OK` or `FAILED` (and exit code 1), the memory the shell and
Files used and how many warnings the shell left in its log. If it fails, it
keeps the folder with the logs and the state; `--keep` always keeps it.

Run it before every commit. It doesn't touch your session: IPC always goes
by the test shell's pid (never by path, which is the same as your shell's)
and in the nested niri the shell doesn't apply the theme to the system or
publish to the greeter. Warnings don't count as failures: with a clean state
some are expected (state files that don't exist yet, thumbnails not
generated yet, the notification server your shell already owns).

## Testing without touching your session

The safe way to test is a nested niri, a window inside your session, with
its own shell and its own state:

```bash
niri -c test.kdl &        # opens a window with another niri inside
# with that niri's WAYLAND_DISPLAY and NIRI_SOCKET:
env XDG_CONFIG_HOME=/tmp/spore-test/cfg \
    SPORE_STATE_DIR=/tmp/spore-test/state \
    XDG_CACHE_HOME=/tmp/spore-test/cache \
    WAYLAND_DISPLAY=wayland-2 NIRI_SOCKET=/run/user/1000/niri.wayland-2.….sock \
    spore
```

- `SPORE_STATE_DIR` separates the wallpaper, the palette and the mode; if
  it's empty, the shell starts with the defaults.
- `/tmp/spore-test/cfg/spore/dev-path` can hold the path of another checkout
  (a `git worktree`, for example) to test a branch without touching the
  real shell.
- `spore-ipc` or `quickshell ipc --pid <pid> call …` open every window and
  every page without clicking.
- For screenshots, `grim` with the nested niri's `WAYLAND_DISPLAY` (not
  `niri msg action screenshot`, which sends a notification to your session).
- Keys typed into the nested niri (`wtype`) aren't reliable: once its window
  is out of sight, the releases come late and Qt repeats the key (one Tab
  became six), and `wtype` can hang. That's why `tools/test.sh` drives
  everything over IPC; try the keyboard by hand, in a nested niri you're
  looking at.
- In the nested niri the shell doesn't suspend on idle (it would suspend the
  whole machine), apply the theme to the system or publish to the greeter:
  dconf, the GTK themes, kitty, Kate and the files in `~/.local/state/spore`
  are your real session's, and the test used to overwrite them with its
  colors. `Compositor.nested` detects it.

## Icons

The icons come from [Lucide](https://lucide.dev/icons) (and the logos from
[Simple Icons](https://simpleicons.org), as `simple:<name>`). To add one:

1. Add its name to `tools/lucide-icons.txt`.
2. `node tools/lucide.mjs`: downloads the SVGs and regenerates
   `shell/common/lucide.js`, with everything turned into a single path per
   icon.
3. Restart the shell (it's a `.js` with `.pragma library`).
4. Use it with `Icon { name: "name" }`.

## Transition shaders

`shell/wallpaper/shaders/*.frag`. After editing one,
`shell/wallpaper/shaders/build.sh` compiles them to `.frag.qsb` (with the
`qsb` from `qt6.qtshadertools`, the same Qt as Quickshell). The `.qsb` files
are committed. For a new transition: the `.frag`, its name and duration in
`durations` in `wallpaper/Wallpaper.qml`, and its name in the list in
`services/Settings.qml`.

## Conventions

- **Everything in English:** the interface, the comments, the documentation
  and the commit messages.
- **No loose colors:** everything comes from `Theme.qml` (or `brand.js` for
  the brand).
- **Text:** `UiText` for the interface (Noto Sans) and `MonoText` for
  numbers, times and values (JetBrains Mono). A plain `Text` that shows
  something from outside (a name, a title, a message) gets
  `textFormat: Text.PlainText`, as those two have: Qt's default reads a
  `<img src=…>` in it as an image to fetch from the network.
- **State:** it lives in `shell.qml` or in a service `shell.qml` creates;
  components receive it as a property and report with signals. There's no
  `Singleton` ([why](architecture.md)).
- **Light:** a window is created only while it's open (`LazyLoader`), a piece
  of data is measured once for everyone (`SystemMonitor`), and anything
  heavy goes in a separate process that exits when done.
- **Apps:** whatever starts an app for the user goes through `session.js`
  (`Session.command()`, or `app` in a script), so the app gets the
  session's environment: Spore's PATH and Qt variables are only for Spore.
