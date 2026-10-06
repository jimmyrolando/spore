#!/bin/sh
# Compiles the transition shaders (*.frag -> *.frag.qsb) with qsb, from
# qtshadertools. The .qsb files are committed: that way neither the package
# nor dev mode needs qsb. Run it after editing a .frag.
set -e
cd "$(dirname "$0")"
for f in *.frag; do
    # The same Qt as Quickshell: the .qsb format has to be compatible.
    nix shell nixpkgs#qt6.qtshadertools -c qsb --glsl "100 es,120,150" --hlsl 50 --msl 12 -o "$f.qsb" "$f"
    echo "compiled $f"
done
