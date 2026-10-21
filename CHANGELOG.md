# What's new

Spore is my daily driver, and it grows with what I find I'm missing. This is
what has been added since [v0.1.0](https://github.com/jimmyrolando/spore/releases/tag/v0.1.0),
newest first. A line is added here each time something new reaches `main`.

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
