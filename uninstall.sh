#!/bin/sh
# Removes what install.sh put in place. Your settings (~/.config/spore), state
# and cache are left alone.
set -eu
prefix=${XDG_DATA_HOME:+${XDG_DATA_HOME%/share}}
prefix=${prefix:-$HOME/.local}
[ "${1:-}" = --prefix ] && prefix=${2:?--prefix needs a folder}
rm -rf "$prefix/share/spore"
rm -f "$prefix/bin/spore" "$prefix/bin/spore-ipc" "$prefix/bin/spore-files" \
      "$prefix/share/applications/spore-files.desktop"
echo "Spore removed from $prefix."
