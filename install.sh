#!/bin/sh
# Installs Spore for the current user, without root: the shell in
# ~/.local/share/spore, its commands in ~/.local/bin and Files in the app
# launchers. Meant for distros other than NixOS (there, use the flake).
#
# Usage: ./install.sh [--prefix DIR]   (DIR defaults to ~/.local)
# Remove it with ./uninstall.sh. It never asks for root: what needs it (the
# lockscreen's PAM service, external monitors' brightness) is only printed.
set -eu

repo=$(cd "$(dirname "$0")" && pwd)
prefix=${XDG_DATA_HOME:+${XDG_DATA_HOME%/share}}
prefix=${prefix:-$HOME/.local}
[ "${1:-}" = --prefix ] && prefix=${2:?--prefix needs a folder}

share=$prefix/share/spore
bin=$prefix/bin
apps=$prefix/share/applications

die() { echo "install.sh: $*" >&2; exit 1; }

qs=$(command -v quickshell) || die "Quickshell isn't installed (see docs/install.md)"
qs_prefix=$(dirname "$(dirname "$(readlink -f "$qs")")")
[ -x "$qs_prefix/bin/quickshell" ] || qs_prefix=$(dirname "$(dirname "$qs")")

pci_ids=
for f in /usr/share/hwdata/pci.ids /usr/share/misc/pci.ids /usr/share/pci.ids; do
  [ -r "$f" ] && { pci_ids=$f; break; }
done

rm -rf "$share"
mkdir -p "$share" "$bin" "$apps"
cp -r "$repo/shell" "$repo/video" "$repo/assets" "$repo/settings.example.json" "$share/"
mkdir -p "$share/licenses"
cp "$repo/LICENSE" "$repo/THIRD-PARTY-NOTICES.md" "$share/licenses/"

# The Nix wrappers, minus the lines that only exist for Nix.
for script in spore spore-ipc spore-files; do
  sed -e '/# nix-only: begin/,/# nix-only: end/d' \
      -e "s|@share@|$share|g" \
      -e "s|@quickshell@|$qs_prefix|g" \
      -e "s|@pciIds@|$pci_ids|g" \
      "$repo/nix/bin/$script" > "$bin/$script"
  chmod +x "$bin/$script"
done
sed "s|@bin@|$bin|" "$repo/nix/spore-files.desktop" > "$apps/spore-files.desktop"

# The official wallpapers for the grid in Settings, only if the user has no
# wallpaper folder yet (never into one that exists).
walls=${XDG_PICTURES_DIR:-$HOME/Pictures}/Wallpapers
if [ ! -e "$walls" ]; then
  mkdir -p "$walls" && cp "$repo"/assets/wallpapers/* "$walls/" && echo "The official wallpapers are in $walls."
fi

# Rofi in Spore's colors, only if the user has no rofi config yet.
rofi=${XDG_CONFIG_HOME:-$HOME/.config}/rofi
if [ ! -e "$rofi/config.rasi" ]; then
  mkdir -p "$rofi" && cp "$repo/examples/rofi/config.rasi" "$repo/examples/rofi/spore.rasi" "$rofi/" && echo "Rofi's theme is in $rofi."
fi

# Hyprland errors on a `source` that matches no file, and the shell only writes
# its colors once it runs (after Hyprland has read the config): an empty one
# keeps the first start clean. The shell fills it in.
hypr=${XDG_STATE_HOME:-$HOME/.local/state}/spore/hypr
if [ ! -e "$hypr/colors.conf" ]; then
  mkdir -p "$hypr" && : > "$hypr/colors.conf"
fi

echo "Spore installed in $share (commands in $bin)."
case ":$PATH:" in *":$bin:"*) ;; *) echo "Note: $bin isn't in your PATH." ;; esac

# What it needs from the system.
missing=
for c in niri matugen ffmpeg ffprobe gio bsdtar pdftoppm cliphist wl-copy ddcutil dconf \
         udisksctl nmcli bluetoothctl systemctl loginctl curl gawk rofi; do
  command -v "$c" >/dev/null 2>&1 || missing="$missing $c"
done
[ -n "$missing" ] && echo "Missing commands (some features need them):$missing"

cat <<MSG

Needs root, once (this script doesn't do it):
  - Lockscreen: a PAM service named "swaylock". Installing the swaylock
    package creates it; otherwise, in /etc/pam.d/swaylock: "auth include login"
    (or system-auth, depending on the distro).
  - External monitors' brightness: load i2c-dev (/etc/modules-load.d/i2c.conf)
    and add your user to the i2c group.
Then start "spore" with the session: spawn-at-startup in niri (examples/niri.kdl)
or exec-once in Hyprland (examples/hyprland.conf); both have the shortcuts.
The greeter isn't installed by this script.
MSG
