# Manual install (other distros)

Spore's reference platform is NixOS with niri. Tried so far on Arch (Quickshell 0.3.2, Qt 6.12, niri 26.04); this is the
path to follow elsewhere. It needs systemd.

```sh
git clone https://github.com/jimmyrolando/spore && cd spore
./install.sh        # for your user only; ./uninstall.sh removes it
```

It copies the shell to `~/.local/share/spore`, the commands (`spore`,
`spore-ipc`, `spore-files`) to `~/.local/bin` and Files to the app launchers.
Your settings and state are never touched. Then add `spawn-at-startup "spore"`
and the shortcuts from [`examples/niri.kdl`](../examples/niri.kdl) to niri's
config (the `binds` lines go inside the `binds { }` block you already have: niri allows only one).

## What it needs

| What | Used for |
|---|---|
| `quickshell` 0.3.1 or newer, with Qt's `qtmultimedia` and image plugins (`qtimageformats`, `kimageformats`) | the shell; video wallpapers; HEIC/AVIF/JXL |
| `niri` | the compositor |
| `matugen` | the palette from the wallpaper |
| `ffmpeg` (with `ffprobe`) | video wallpapers and thumbnails |
| `glib2` (`gio`), `libarchive` (`bsdtar`), `poppler` (`pdftoppm`) | Files |
| `cliphist`, `wl-clipboard` | the clipboard |
| `bluez-utils` on Arch (`bluetoothctl`) | the Bluetooth page |
| `adw-gtk-theme` (adw-gtk3) | GTK apps in Spore's colors |
| `dconf`, `curl`, `gawk`, `rofi`, `kitty` | themes, weather, the launcher |
| `ddcutil` | external monitors' brightness |
| PipeWire, NetworkManager, BlueZ, UPower, udisks2 | the Control Center's pages |
| Noto Sans, JetBrainsMono Nerd Font | the fonts |

On Arch: `quickshell niri matugen ffmpeg glib2 libarchive poppler cliphist
wl-clipboard bluez-utils adw-gtk-theme dconf curl gawk rofi kitty ddcutil swaylock noto-fonts
ttf-jetbrains-mono-nerd qt6-multimedia qt6-imageformats kimageformats`
(some are in the AUR). Package names may need adjusting.

## What needs root (once)

- **Lockscreen:** a PAM service named `swaylock` (the `swaylock` package
  creates it).
- **External monitors' brightness:** load `i2c-dev` and add your user to the
  `i2c` group.

The greeter isn't part of the manual install.
