# What's new

Spore is my daily driver, and it grows with what I find I'm missing. This is
what has been added since [v0.1.0](https://github.com/jimmyrolando/spore/releases/tag/v0.1.0),
newest first. A line is added here each time something new reaches `main`.

## Unreleased

### November 6

- **Hyprland 0.57 works again.** Its config is Lua now (`hyprland.lua`), so
  the lines from `examples/hyprland.conf` were ignored and Spore didn't start
  with the session. `examples/hyprland.lua` has them for 0.57 and newer. The
  bar's workspaces, turning the screens off, logging out, Settings → Displays
  and the window borders in the palette speak Lua to it too. Older versions
  go on as before, with `hyprland.conf`.
- The manual install lists Go, which builds spored, among what it needs.
- Music has its icon again in Files' sidebar (Lucide renamed it).

### November 5

- **spored watches logind and the drives.** The lock before the system
  sleeps and the drives' events (plugged in, mounted, unplugged) now come
  from spored, listening to D-Bus, instead of scripts reading `gdbus
  monitor` and `udisksctl monitor`: six fewer processes in the session.
  Without spored (installed with no Go), the scripts still do it.

## v0.3.0, November 4, 2026

### October 29

- **"Show in folder" opens Files.** A browser's download list (and any other
  app's) now opens Spore Files with the file selected. It's the job of
  spored, a small new program in Go that comes with Spore and starts with the
  session. If Thunar is installed and its daemon starts first, Thunar keeps
  "Show in folder" for itself.
- **Files' copies, moves, renames and deletes are done by spored**: progress
  by the bytes really copied, renames that never replace a file, and no limit
  on how many files go at once.
- **The quick view counts what a folder holds.** Space on a folder shows its
  files, folders and weight, growing as it counts; one counted before shows
  its numbers at once.
- **Caffeine has its own lock time.** Settings → Idle → Caffeine shows the
  same rows as Timers: Lock screen and Turn off screen (an hour each by
  default), and Suspend, fixed at Never. Before, the screen only locked when
  it turned off, so locking sooner meant turning the screen off too.

### October 28

- **A round of fixes from a review of the whole code.**
  - A Wi-Fi password no longer gets wiped while you type it: every change in
    a network's signal rebuilt the list.
  - On niri, a monitor plugged in gets back the mode, scale and rotation kept
    for it in Settings > Displays (before, only after opening About or
    Displays).
  - A notification that an app updates (a download's progress, a volume
    script) shows the new text and pops up again, instead of the first one.
  - Each change in Settings rebuilt the whole bar, twice, and fetched the
    weather again: now only what changed moves.
  - After a click in Settings' sidebar, `spore-ipc settings open` and the
    Control Center still change the section.
  - Changing the clipboard's `maxItems` reaches cliphist at once, and the
    history is no longer listed again on every copy once the panel was opened.
  - Files: after a rename, the selection follows the new name (F2 again,
    Open With and the quick view used the old one); sending thousands of files
    to the Trash no longer freezes the window for seconds, and the folder
    shows empty after them, with nothing left selected; two "already exists"
    questions at once (two windows) are asked one after the other, instead of
    the second silently replacing the first.

### October 27

- **Files' questions show on the quick view.** It's above every window, so a
  question (deleting for good, a name that's taken when pasting) opened under
  it, unseen. Now it shows on the view's card, over the file, and Enter and
  Esc answer it as always. Open With and the menu, which can't, make the view
  step aside while they're open.
- **Deleting keeps your place.** After sending files to the Trash (or deleting
  them for good), the selection goes to the next one, or the one before if it
  was the last. With the quick view open, it goes on showing that one: going
  through wallpapers deleting the ones you don't want no longer closes it.

### October 26

- **Files shows its progress in a card.** A copy, a move, a zip or emptying
  the Trash that takes more than a moment gets a card in the window's corner:
  the bar, how much is done, about how long is left, what's waiting behind it
  and Cancel; then, for a few seconds, that it's done or why it stopped. One
  that ends while Files isn't in front sends a notification. Pasting the same
  thing again while it's still being copied now says so, instead of quietly
  waiting and then asking whether to keep both.

### October 22

- **The AppImages widget has its own icon** (a package): it looked just like
  the Control Center's on the bar.
- **No empty capsules on the bar.** Volume, Bluetooth or Notifications alone in
  a capsule didn't take it with them when they hid (no Bluetooth adapter, no
  sound output); an empty pill stayed.
- **Files: Shift+Delete deletes for good**, without going through the Trash
  (also in the right-click menu). It always asks first.

## v0.2.2, October 22, 2026

### October 21

- **Caffeine keeps the machine awake, not the screen.** Nothing suspends while
  it's on, but after an hour without input the screen locks and turns off
  anyway (Settings → Idle → Caffeine; `0` keeps it on).
- **Windows survive a monitor that disconnects when it turns off.** Settings,
  the Control Center and the rest come back with the monitor (Settings on the
  same section); before, they vanished and the first click only "closed" them.

## v0.2.1, October 21, 2026

### October 21

- **About This Machine shows the right version.** v0.2.0 still said 0.1.0 there;
  `tools/test.sh` now fails if the version numbers don't match.

## v0.2.0, October 18, 2026

### October 17–18

- **AppImages widget** (Settings → Bar, hidden by default). A button that lists
  a folder (`~/Applications`) and shows only the newest version of each app:
  type to search, Enter to run, a dot on the ones already running. On NixOS it
  uses `appimage-run`, so files that aren't executable work too.
- **A nicer printer test page.** The sheet is drawn by the shell (Spore's mark,
  the machine's details, color, gray, text and line patterns) and printed as an
  image.
- **Hyprland's first start is clean.** `install.sh` leaves an empty colors file
  where Hyprland expects it, so there's no config error before the shell has run.
- **niri no longer reloads its config for nothing.** Spore doesn't rewrite a
  theme file that already says the same (it used to reload niri 77 times in a
  row).

### October 15–16

- **Settings → Printers.** The printers CUPS knows: pause or resume, the
  default one, its queue (cancel one job or all), a test page and removing it.
  "Search" finds printers that announce themselves on the network and "Add" sets
  one up without a driver (IPP Everywhere); a slow printer gets three tries and
  an "Adding…" note.
- **Displays are remembered.** What you keep in Settings → Displays is saved per
  monitor (make, model, serial: not the port) and put back when the shell starts
  or the monitor is plugged in.

### October 12–14

- **Hyprland.** Spore runs on Hyprland as well as niri: the compositor is
  detected and one backend per compositor does the rest (workspaces, windows,
  outputs, borders in the theme's colors).
- **Settings → Displays.** Resolution, refresh rate, scale, rotation and turning
  a monitor off. After a change it asks "Keep this change?" and goes back by
  itself after 15 seconds, in case the screen goes black.
- **Installing outside NixOS.** `install.sh` and `uninstall.sh` (no root, into
  `~/.local`), a package list in [docs/install.md](docs/install.md), the
  official wallpapers and Rofi's theme if you have none. Tried on Arch, with niri
  and with Hyprland.
- **Each distro gets its own logo** in About and the bar (Tux when it doesn't
  know it), and the package count works with pacman, rpm, dpkg and apk.
- Fixed a Files crash on Qt 6.12, and the GTK theme is found outside NixOS'
  user profile.

### October 6 (after v0.1.0)

- **Brightness of each screen** in the Control Center's Home; the sliders stay
  where you leave them.
- About finds Quickshell's version when it isn't in `PATH`.
