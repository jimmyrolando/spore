#!/usr/bin/env bash
# Spore's test: checks the syntax of the shell scripts embedded in the QML,
# then runs this checkout's shell in a nested niri, isolated (config, state
# and cache in a temporary folder), opens every screen, tests the IPC, tries
# Files on a sample folder, locks the nested session and closes the shell. It
# fails if a script is broken, if a log has errors, if something crashes or if
# orphan processes are left. Run it before every commit.
#
# It doesn't touch the real session: IPC always goes by the test shell's pid
# (never by path, which is the same as the real shell's), and in a nested
# compositor the shell doesn't write system themes, handle idle or publish to
# the greeter. While it runs (~40 s) the nested niri's window is visible.
#
# Usage: tools/test.sh [--keep]   (--keep keeps the log and state even if it passes)
# Requires a niri session, and nix to build the packages.
set -u

repo=$(cd "$(dirname "$0")/.." && pwd)
keep=0
[ "${1:-}" = --keep ] && keep=1
tmp=$(mktemp -d "${TMPDIR:-/tmp}/spore-test.XXXXXX")
log=$tmp/shell.log
fail=0
niri_pid=
shell_pid=

bad() {
    echo "  FAIL: $*"
    fail=1
}

cleanup() {
    [ -n "${files_pid:-}" ] && kill "$files_pid" 2>/dev/null
    [ -n "$shell_pid" ] && kill "$shell_pid" 2>/dev/null
    [ -n "$niri_pid" ] && kill "$niri_pid" 2>/dev/null
    if [ "$fail" = 0 ] && [ "$keep" = 0 ]; then
        rm -rf "${tmp:?}"
    else
        echo "Test log and state: $tmp"
    fi
}
trap cleanup EXIT

# QML and JavaScript errors in the log (warnings don't count), only in the
# lines added since the previous check.
checked=0
check_errors() {
    local found
    found=$(tail -n +$((checked + 1)) "$log" | grep -E 'ERROR|ReferenceError|TypeError|SyntaxError|RangeError|is not a type|is not defined|Unable to assign|Cannot assign|Binding loop|Failed to load' | sort -u)
    checked=$(wc -l < "$log")
    [ -z "$found" ] && return 0
    bad "errors in the log $1:"
    echo "$found" | sed 's/^/    /' | head -20
}

[ -n "${WAYLAND_DISPLAY:-}" ] && command -v niri >/dev/null || {
    echo "It has to run inside a niri session."
    exit 1
}

# Before anything else, and without a session: a broken script fails silently
# (see tools/check-scripts.mjs).
echo "1. Embedded shell scripts"
if command -v node >/dev/null; then
    scripts=$(node "$repo/tools/check-scripts.mjs") || bad "shell scripts with syntax errors:"
    echo "$scripts" | sed 's/^/    /'
else
    echo "    skipped: node isn't installed"
fi

# This checkout's package: its wrapper puts the dependencies in PATH, and with
# dev-path (below) it runs the checkout's code, not the copy in the store.
echo "Building the packages…"
pkg=$(nix build --no-link --print-out-paths "path:$repo#spore-shell") || {
    bad "couldn't build the package"
    exit 1
}
# The greeter isn't run here (see docs/greeter.md to try it): only built.
greeter=$(nix build --no-link --print-out-paths "path:$repo#spore-greeter") &&
    [ -x "$greeter/bin/spore-greeter" ] && [ -f "$greeter/share/spore/greeter/Theme.qml" ] ||
    bad "couldn't build the greeter's package"
qs=$(sed -n 's/^export SPORE_QUICKSHELL="\(.*\)"$/\1/p' "$pkg/bin/spore")
[ -x "$qs" ] || qs=quickshell

mkdir -p "$tmp/config/spore" "$tmp/state" "$tmp/cache" "$tmp/xdg-state"
printf '%s' "$repo" > "$tmp/config/spore/dev-path"
cp "$repo/settings.example.json" "$tmp/config/spore/settings.json"
cat > "$tmp/niri.kdl" <<'EOF'
hotkey-overlay {
    skip-at-startup
}
EOF

echo "Starting a nested niri and the shell…"
niri -c "$tmp/niri.kdl" > "$tmp/niri.log" 2>&1 &
niri_pid=$!
sock=
for _ in $(seq 50); do
    sock=$(ls "${XDG_RUNTIME_DIR:?}"/niri.wayland-*."$niri_pid".sock 2>/dev/null | head -1)
    [ -n "$sock" ] && break
    sleep 0.2
done
[ -n "$sock" ] || { bad "the nested niri didn't start (see $tmp/niri.log)"; exit 1; }
disp=$(basename "$sock" | sed 's/^niri\.\(wayland-[0-9]*\)\..*/\1/')

# The screens' brightness (services/BrightnessService.qml) with stand-ins: a
# monitor that answers on the nested niri's output (winit), one that doesn't,
# and a laptop's backlight. The real ddcutil never runs: it would reach the
# real monitors.
mkdir -p "$tmp/backlight/test_bl"
echo 500 > "$tmp/backlight/test_bl/brightness"
echo 1000 > "$tmp/backlight/test_bl/max_brightness"
echo 40 > "$tmp/ddc.value"
cat > "$tmp/ddcutil" <<EOF
#!/bin/sh
case "\$1" in
detect) printf 'Display 1\n   I2C bus:          /dev/i2c-7\n   DRM connector:    card0-winit\n   Monitor:          TST:Test Monitor:1\n\nInvalid display\n   I2C bus:          /dev/i2c-8\n' ;;
getvcp) printf 'VCP 10 C %s 100\n' "\$(cat "$tmp/ddc.value")" ;;
setvcp) echo "\$3" > "$tmp/ddc.value" ;;
esac
EOF
chmod +x "$tmp/ddcutil"

env XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/xdg-state" XDG_CACHE_HOME="$tmp/cache" \
    SPORE_STATE_DIR="$tmp/state" WAYLAND_DISPLAY="$disp" NIRI_SOCKET="$sock" \
    SPORE_DDCUTIL="$tmp/ddcutil" SPORE_BACKLIGHT_DIR="$tmp/backlight" \
    "$pkg/bin/spore" --no-color > "$log" 2>&1 &
shell_pid=$!

# IPC, always to the test shell by its pid.
ipc() {
    WAYLAND_DISPLAY=$disp "$qs" ipc --pid "$shell_pid" call "$@"
}

for _ in $(seq 60); do
    grep -q 'Configuration Loaded' "$log" && break
    kill -0 "$shell_pid" 2>/dev/null || break
    sleep 0.5
done
grep -q 'Configuration Loaded' "$log" || {
    bad "the shell didn't load:"
    tail -15 "$log" | sed 's/^/    /'
    exit 1
}
# Make sure it really is the test shell (the lock below must never reach another).
tr '\0' '\n' < "/proc/$shell_pid/environ" | grep -qx "SPORE_STATE_DIR=$tmp/state" || {
    bad "pid $shell_pid isn't the test shell"
    exit 1
}
sleep 3
echo "2. Startup"
check_errors "at startup"
# Apps it starts get the session's environment back (shell/common/session.js):
# the wrapper kept the session's PATH.
tr '\0' '\n' < "/proc/$shell_pid/environ" | grep -qxF "SPORE_SESSION=PATH=$PATH" ||
    bad "the shell's wrapper didn't keep the session's PATH (SPORE_SESSION)"

echo "3. IPC"
targets=$(WAYLAND_DISPLAY=$disp "$qs" ipc --pid "$shell_pid" show | sed -n 's/^target //p')
for t in lock clipboard controlcenter appearance power wallpaper settings about caffeine brightness; do
    grep -qx "$t" <<< "$targets" || bad "missing IPC target \"$t\""
done
ipc caffeine enable
[ "$(ipc caffeine isEnabled)" = true ] || bad "caffeine enable didn't turn it on"
ipc caffeine disable
[ "$(ipc caffeine isEnabled)" = false ] || bad "caffeine disable didn't turn it off"

echo "4. Control Center (every page)"
for page in home media audio system network bluetooth drives weather calendar notifications; do
    ipc controlcenter open "$page"
    sleep 0.8
done
ipc controlcenter toggle
sleep 0.5
check_errors "in the Control Center"
# The brightness: found and read when the shell started, the built-in screen
# first; what's set reaches the monitor and the backlight.
want='[{"name":"Built-in display","percent":50},{"name":"Test Monitor","percent":40}]'
got=$(ipc brightness list)
[ "$got" = "$want" ] || bad "brightness: the screens are $got, expected $want"
ipc brightness set "Test Monitor" 72
ipc brightness set "Built-in display" 30
for _ in $(seq 10); do
    [ "$(cat "$tmp/ddc.value")" = 72 ] && [ "$(cat "$tmp/backlight/test_bl/brightness")" = 300 ] && break
    sleep 0.2
done
[ "$(cat "$tmp/ddc.value")" = 72 ] || bad "brightness: the monitor got $(cat "$tmp/ddc.value"), not 72"
[ "$(cat "$tmp/backlight/test_bl/brightness")" = 300 ] ||
    bad "brightness: the backlight is at $(cat "$tmp/backlight/test_bl/brightness"), not 300 (30 % of 1000)"
# And it says so: a Control Center page made again shows where they were left.
want='[{"name":"Built-in display","percent":30},{"name":"Test Monitor","percent":72}]'
got=$(ipc brightness list)
[ "$got" = "$want" ] || bad "brightness: after setting it, the screens are $got, expected $want"

echo "5. Settings (every section)"
for section in appearance fonts bar lock idle about; do
    ipc settings open "$section"
    sleep 0.8
done
ipc settings toggle
sleep 0.5
check_errors "in Settings"
# settings.json edited by hand with a value of the wrong type: it gets the
# default, and the keys after it still load (Settings.qml).
settings=$tmp/config/spore/settings.json
cp "$settings" "$tmp/settings.json.good"
printf '{ "idle": { "lockAfter": "five", "screenOffAfter": 777 } }\n' > "$settings"
sleep 1
grep -qF "Settings: loaded (idle: lock 300s, screen off 777s" "$log" ||
    bad "a value of the wrong type in settings.json kept the rest from loading"
cp "$tmp/settings.json.good" "$settings"
sleep 1
check_errors "with a value of the wrong type in settings.json"

echo "6. Panels"
for panel in clipboard power about appearance; do
    ipc "$panel" toggle
    sleep 0.8
    ipc "$panel" toggle
    sleep 0.5
done
check_errors "in the panels"

pss=$(awk '/^Pss:/ { printf "%.0f", $2 / 1024 }' "/proc/$shell_pid/smaps_rollup")

# Files: another process (shell/files.qml), with the same isolated folders,
# on a sample folder. Its IPC goes by its pid too.
echo "7. Files"
sample=$tmp/sample
mkdir -p "$sample/Photos"
cp "$repo/assets/wallpapers/spore-dome.jpg" "$sample/img2.jpg"
cp "$repo/assets/wallpapers/spore-dome.jpg" "$sample/img10.jpg"
printf 'notes\n' > "$sample/notes.txt"
# A short video for the quick view, made with the package's ffmpeg.
runtime=$(sed -n 's/^export PATH="\(.*\):\$PATH"$/\1/p' "$pkg/bin/spore")
ffmpeg=$(IFS=:; for d in $runtime; do [ -x "$d/ffmpeg" ] && echo "$d/ffmpeg" && break; done)
bsdtar=$(IFS=:; for d in $runtime; do [ -x "$d/bsdtar" ] && echo "$d/bsdtar" && break; done)
"${ffmpeg:-ffmpeg}" -v error -f lavfi -i testsrc=size=320x240:rate=10 -t 2 -pix_fmt yuv420p "$sample/clip.mp4" </dev/null ||
    bad "couldn't make the sample video"
: > "$sample/.hidden"
# The "terminal" Files opens ($TERMINAL comes first): it writes down the
# environment and the folder it gets.
cat > "$tmp/terminal" <<EOF
#!/bin/sh
{ env; echo "cwd=\$(pwd)"; } > "$tmp/terminal.part" && mv "$tmp/terminal.part" "$tmp/terminal.env"
EOF
chmod +x "$tmp/terminal"
files_log=$tmp/files.log
# XDG_DATA_HOME: the Trash is the test's too (gio trash would use the real one).
env XDG_CONFIG_HOME="$tmp/config" XDG_STATE_HOME="$tmp/xdg-state" XDG_CACHE_HOME="$tmp/cache" \
    XDG_DATA_HOME="$tmp/data" SPORE_STATE_DIR="$tmp/state" WAYLAND_DISPLAY="$disp" NIRI_SOCKET="$sock" \
    TERMINAL="$tmp/terminal" "$pkg/bin/spore-files" "$sample" > "$files_log" 2>&1 &
files_pid=
for _ in $(seq 40); do
    for p in $(pgrep -x .quickshell-wra); do
        tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "SPORE_STATE_DIR=$tmp/state" &&
            tr '\0' ' ' < "/proc/$p/cmdline" | grep -q 'files\.qml' && files_pid=$p
    done
    [ -n "$files_pid" ] && grep -q 'Configuration Loaded' "$files_log" && break
    sleep 0.25
done
files_ipc() {
    WAYLAND_DISPLAY=$disp "$qs" ipc --pid "$files_pid" call files "$@"
}
# One field of the state (JSON) of the window that last had the focus.
files_state() {
    files_ipc state | sed -n "s/.*\"$1\":\(\[[^]]*\]\|\"[^\"]*\"\|[0-9a-z][0-9a-z]*\).*/\1/p"
}
# Waits (up to $4 seconds, 4 by default) for a field of the state to be $2:
# Files answers when it can (a folder loads, a video starts).
expect() {
    local got tries
    for tries in $(seq $(( ${4:-4} * 4 ))); do
        got=$(files_state "$1")
        [ "$got" = "$2" ] && return 0
        sleep 0.25
    done
    bad "Files, $3: $1 is $got, expected $2"
}
# The quick view's video players (video/preview.qml) this test started.
players() {
    for p in $(pgrep -f 'video/preview\.qml'); do
        tr '\0' '\n' < "/proc/$p/environ" 2>/dev/null | grep -qx "SPORE_STATE_DIR=$tmp/state" && echo "$p"
    done
}
if [ -z "$files_pid" ]; then
    bad "Files didn't start:"
    tail -15 "$files_log" | sed 's/^/    /'
else
    for _ in $(seq 20); do
        NIRI_SOCKET=$sock niri msg windows | grep -q 'App ID: "spore-files"' && break
        sleep 0.25
    done
    NIRI_SOCKET=$sock niri msg windows | grep -q 'App ID: "spore-files"' || bad "no Files window in niri"
    [ -f "$tmp/state/theme.json" ] || bad "the shell didn't write theme.json (Files follows it)"
    expect count 5 "on opening"
    expect names '["Photos","clip.mp4","img2.jpg","img10.jpg","notes.txt"]' "folders first and in natural order"
    files_ipc go Photos
    sleep 0.6
    expect folder "\"$sample/Photos\"" "going into a folder"
    files_ipc back
    sleep 0.6
    expect folder "\"$sample\"" "going back"
    expect selected '""' "going back"
    files_ipc go Photos
    sleep 0.6
    files_ipc up
    sleep 0.6
    expect selected '"Photos"' "going up (the folder it comes from)"
    files_ipc go "$sample/notes.txt"
    sleep 0.6
    expect selected '"notes.txt"' "opening a file (its folder, with it selected)"
    # Odd characters in a folder's path: Qt's FolderListModel read "C# a?b
    # %41" as "C" and listed that folder instead (see folderUri in
    # shell/files/fileutil.js).
    mkdir -p "$tmp/odd/C" "$tmp/odd/C# a?b %41"
    : > "$tmp/odd/C/not this.txt"
    : > "$tmp/odd/C# a?b %41/this.txt"
    files_ipc go "$tmp/odd/C# a?b %41"
    expect names '["this.txt"]' "in a folder with “#”, “?” and “%41” in its name"
    # A terminal there: it gets the session's environment (this test's), not
    # Files' (shell/common/session.js).
    files_ipc terminal
    for _ in $(seq 20); do
        [ -f "$tmp/terminal.env" ] && break
        sleep 0.2
    done
    if [ -f "$tmp/terminal.env" ]; then
        for v in PATH QT_PLUGIN_PATH NIXPKGS_QT6_QML_IMPORT_PATH XDG_DATA_DIRS QT_WAYLAND_DISABLE_WINDOWDECORATION; do
            [ "$(sed -n "s/^$v=//p" "$tmp/terminal.env")" = "$(printenv "$v")" ] ||
                bad "Files: the terminal's $v isn't the session's"
        done
        grep -qE '^(SPORE_SESSION|SPORE_QUICKSHELL|SPORE_FILES_OPEN|QS_APP_ID)=' "$tmp/terminal.env" &&
            bad "Files: the terminal got Spore's own variables"
        grep -qxF "cwd=$tmp/odd/C# a?b %41" "$tmp/terminal.env" || bad "Files: the terminal didn't open in the folder"
    else
        bad "Files: Open terminal here didn't start \$TERMINAL"
    fi
    # Thumbnails in a folder with 20000 files: as arguments, the list of
    # them (3.4 MB with these names) was over the system's limit (2 MB with
    # the usual 8 MB stack) and none showed (Thumbnails.qml).
    photo=a-photo-of-the-whole-family-on-the-beach-in-the-summer-holidays-of-that-year-number
    mkdir -p "$tmp/many" "$tmp/cache/thumbnails/normal"
    # Text files: empty .jpg ones only made Files try to decode them. And real
    # PNGs as their thumbnails, for the same reason.
    (cd "$tmp/many" && seq -w 20000 | sed "s/.*/$photo-&.txt/" | xargs touch)
    "${ffmpeg:-ffmpeg}" -v error -f lavfi -i color=c=gray:s=8x8 -frames:v 1 "$tmp/thumbnail.png" </dev/null
    for n in 00001 20000; do
        cp "$tmp/thumbnail.png" "$tmp/cache/thumbnails/normal/$(printf '%s' "file://$tmp/many/$photo-$n.txt" | md5sum | cut -c1-32).png"
    done
    files_ipc go "$tmp/many"
    expect thumbnails 2 "in a folder with 20000 files" 15
    # All 20000 to the Trash at once: as arguments, that many paths can't
    # even start. It has to fail and let the queue go on (FileOps.qml), not
    # keep Files busy for good.
    if [ "$(getconf ARG_MAX)" -le 2097152 ]; then
        files_ipc selectAll
        files_ipc trash
        expect busy false "after sending 20000 files to the Trash at once"
        expect message '"Too many items at once (20000): try with fewer"' "after sending 20000 files to the Trash at once"
        [ -e "$tmp/many/$photo-00001.txt" ] || bad "Files: the 20000 files went to the Trash"
    fi
    files_ipc go "$sample/notes.txt"
    sleep 0.6
    files_ipc filter img
    sleep 0.4
    expect count 2 "filtering"
    files_ipc filter ""
    files_ipc toggleHidden
    sleep 0.8
    expect count 6 "showing the hidden files"
    files_ipc toggleHidden
    files_ipc setView list
    sleep 0.5
    files_ipc setView grid
    # The quick view: an image, a text, a video (its player is another
    # process, which has to end when the view moves on).
    files_ipc select img2.jpg
    files_ipc quickView
    sleep 1
    expect preview '"image"' "the quick view of an image"
    files_ipc select notes.txt
    sleep 0.8
    expect preview '"text"' "the quick view of a text file"
    # A PDF (two blank pages, written by hand; poppler finds its objects),
    # there only for this.
    printf '%%PDF-1.4\n1 0 obj << /Type /Catalog /Pages 2 0 R >> endobj\n2 0 obj << /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 >> endobj\n3 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >> endobj\n4 0 obj << /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] >> endobj\ntrailer << /Root 1 0 R >>\n%%%%EOF\n' > "$sample/doc.pdf"
    expect count 6 "a new file listed (doc.pdf)"
    files_ipc select doc.pdf
    expect preview '"pdf"' "the quick view of a PDF"
    expect page '"1/2"' "the quick view of a PDF (its first page)"
    files_ipc turnPage 1
    expect page '"2/2"' "turning a PDF's page"
    files_ipc select clip.mp4
    expect preview '"video"' "the quick view of a video"
    expect playing true "the quick view of a video (the player)" 10
    [ -n "$(players)" ] || bad "the quick view didn't start the video player"
    files_ipc select notes.txt
    sleep 1.5
    [ -n "$(players)" ] && bad "the video player didn't end when the quick view moved on"
    files_ipc quickView
    sleep 0.5
    expect preview '""' "closing the quick view"
    ls "${XDG_RUNTIME_DIR:?}"/spore-files-page-*.ppm >/dev/null 2>&1 &&
        bad "Files: the quick view left a PDF's page behind (spore-files-page-*.ppm)"
    rm "$sample/doc.pdf"
    expect count 5 "a file gone (doc.pdf)"
    # More quick views, in a folder of their own: a font (the system's sans,
    # from fontconfig) shown in itself, and one that isn't a font; an ODF
    # document's thumbnail; an EPUB 3's cover (in a folder, with a space,
    # %-encoded) and an EPUB 2's (up a folder from its package file); an EPUB
    # with none. Covers and the rest take turns, so each "cover" is a new one.
    docs=$tmp/docs
    mkdir -p "$docs/odt/Thumbnails" "$docs/e3/META-INF" "$docs/e3/OEBPS/images" "$docs/e2/META-INF" \
        "$docs/e2/OPS" "$docs/e2/Images" "$docs/e0/META-INF"
    font=$(fc-match -f '%{file}' sans)
    cp "$font" "$docs/sans.${font##*.}"
    head -c 2000 /dev/urandom > "$docs/broken.ttf"
    "${ffmpeg:-ffmpeg}" -v error -f lavfi -i color=c=orange:s=60x90 -frames:v 1 "$tmp/cover.png" </dev/null
    printf 'application/vnd.oasis.opendocument.text' > "$docs/odt/mimetype"
    cp "$tmp/cover.png" "$docs/odt/Thumbnails/thumbnail.png"
    "${bsdtar:-bsdtar}" --format zip -cf "$docs/letter.odt" -C "$docs/odt" .
    container() {
        printf '<?xml version="1.0"?>\n<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">\n'
        printf '<rootfiles><rootfile full-path="%s"\n media-type="application/oebps-package+xml"/></rootfiles></container>\n' "$1"
    }
    container OEBPS/content.opf > "$docs/e3/META-INF/container.xml"
    printf '<package version="3.0"><manifest>\n<item id="c" href="images/cover%%20art.png"\n media-type="image/png" properties="cover-image"/>\n</manifest></package>\n' \
        > "$docs/e3/OEBPS/content.opf"
    cp "$tmp/cover.png" "$docs/e3/OEBPS/images/cover art.png"
    "${bsdtar:-bsdtar}" --format zip -cf "$docs/book3.epub" -C "$docs/e3" .
    container OPS/package.opf > "$docs/e2/META-INF/container.xml"
    printf '<package version="2.0"><metadata><meta content="art" name="cover"/></metadata>\n<manifest><item href="../Images/c.png" id="art" media-type="image/png"/></manifest></package>\n' \
        > "$docs/e2/OPS/package.opf"
    cp "$tmp/cover.png" "$docs/e2/Images/c.png"
    "${bsdtar:-bsdtar}" --format zip -cf "$docs/book2.epub" -C "$docs/e2" .
    container content.opf > "$docs/e0/META-INF/container.xml"
    printf '<package version="3.0"><manifest/></package>\n' > "$docs/e0/content.opf"
    "${bsdtar:-bsdtar}" --format zip -cf "$docs/plain.epub" -C "$docs/e0" .
    files_ipc go "$docs/sans.${font##*.}"
    sleep 0.6
    files_ipc quickView
    expect preview '"font"' "the quick view of a font"
    files_ipc select broken.ttf
    expect preview '"info"' "the quick view of a file that isn't a font"
    files_ipc select letter.odt
    expect preview '"cover"' "the quick view of an ODF document (its thumbnail)"
    files_ipc select plain.epub
    expect preview '"info"' "the quick view of an EPUB without a cover"
    files_ipc select book3.epub
    expect preview '"cover"' "the quick view of an EPUB 3 (its cover)"
    files_ipc select broken.ttf
    expect preview '"info"' "the quick view of a file that isn't a font, again"
    files_ipc select book2.epub
    expect preview '"cover"' "the quick view of an EPUB 2 (its cover)"
    files_ipc quickView
    expect preview '""' "closing the quick view"
    ls "${XDG_RUNTIME_DIR:?}"/spore-files-cover-* >/dev/null 2>&1 &&
        bad "Files: the quick view left a cover behind (spore-files-cover-*)"
    files_ipc go "$sample/notes.txt"
    sleep 0.6
    # Files on disk: a new folder renamed in place, a copy, a paste that asks,
    # the Trash, a move.
    files_ipc newFolder
    sleep 1
    expect renaming '"New folder"' "a new folder (it's renamed right away)"
    files_ipc rename Work
    sleep 0.8
    [ -d "$sample/Work" ] || bad "Files: the new folder wasn't renamed to Work"
    files_ipc select notes.txt
    files_ipc copy
    files_ipc go Work
    sleep 0.6
    files_ipc paste
    sleep 1
    { [ -f "$sample/Work/notes.txt" ] && [ -f "$sample/notes.txt" ]; } || bad "Files: copying notes.txt into Work"
    files_ipc paste
    sleep 0.8
    expect question '"“notes.txt” already exists in “Work”."' "pasting it again (it asks)"
    files_ipc answer keep
    sleep 1
    [ -f "$sample/Work/notes (2).txt" ] || bad "Files: Keep both didn't make “notes (2).txt”"
    files_ipc select "notes (2).txt"
    files_ipc trash
    sleep 1
    [ -e "$sample/Work/notes (2).txt" ] && bad "Files: the Trash didn't take “notes (2).txt”"
    [ -f "$tmp/data/Trash/files/notes (2).txt" ] || bad "Files: “notes (2).txt” isn't in the (test's) Trash"
    files_ipc back
    sleep 0.6
    files_ipc select img10.jpg
    files_ipc cut
    files_ipc go Work
    sleep 0.6
    files_ipc paste
    sleep 1
    { [ -f "$sample/Work/img10.jpg" ] && ! [ -e "$sample/img10.jpg" ]; } || bad "Files: moving img10.jpg into Work"
    files_ipc back
    sleep 0.6
    # The Trash (the test's): restore, delete for good (it asks), empty (it asks).
    trash_files=$tmp/data/Trash/files
    files_ipc go "$trash_files"
    sleep 0.8
    expect inTrash true "going into the Trash"
    expect count 1 "the Trash (“notes (2).txt”)"
    files_ipc select "notes (2).txt"
    files_ipc restore
    sleep 1
    [ -f "$sample/Work/notes (2).txt" ] || bad "Files: restoring “notes (2).txt” to Work"
    [ -e "$trash_files/notes (2).txt" ] && bad "Files: “notes (2).txt” stayed in the Trash after restoring it"
    files_ipc go "$sample/Work"
    sleep 0.6
    files_ipc select "notes (2).txt"
    files_ipc trash
    sleep 1
    files_ipc select notes.txt
    files_ipc trash
    sleep 1
    files_ipc go "$trash_files"
    sleep 0.8
    files_ipc select notes.txt
    files_ipc purge
    sleep 0.4
    expect question '"Delete “notes.txt” for good?"' "deleting for good (it asks)"
    files_ipc answer delete
    sleep 1
    [ -e "$trash_files/notes.txt" ] && bad "Files: “notes.txt” wasn't deleted for good"
    [ -e "$tmp/data/Trash/info/notes.txt.trashinfo" ] && bad "Files: the record of “notes.txt” stayed"
    files_ipc emptyTrash
    sleep 0.4
    files_ipc answer delete
    sleep 1
    [ -z "$(ls -A "$trash_files")" ] || bad "Files: the Trash isn't empty after emptying it"
    files_ipc go "$sample"
    sleep 0.6
    # Drag and drop (what a drop does, over IPC): within the disk it moves,
    # copy copies, a folder doesn't go into itself, the Trash takes it.
    files_ipc select notes.txt
    files_ipc drop "$sample/Photos" auto
    sleep 1
    { [ -f "$sample/Photos/notes.txt" ] && ! [ -e "$sample/notes.txt" ]; } || bad "Files: dropping notes.txt on Photos (a move)"
    files_ipc select img2.jpg
    files_ipc drop "$sample/Photos" copy
    sleep 1
    { [ -f "$sample/Photos/img2.jpg" ] && [ -f "$sample/img2.jpg" ]; } || bad "Files: dropping img2.jpg on Photos with Ctrl (a copy)"
    mkdir -p "$sample/Work/Inside"
    files_ipc select Work
    files_ipc drop "$sample/Work/Inside" auto
    sleep 0.8
    { [ -d "$sample/Work" ] && ! [ -e "$sample/Work/Inside/Work" ]; } || bad "Files: a folder dropped into itself moved"
    files_ipc select img2.jpg
    files_ipc drop trash auto
    sleep 1
    { [ -f "$trash_files/img2.jpg" ] && ! [ -e "$sample/img2.jpg" ]; } || bad "Files: dropping img2.jpg on the Trash"
    # Favorites: GTK's bookmarks file (the test's), shared with other apps.
    bookmarks=$tmp/config/gtk-3.0/bookmarks
    files_ipc addFavorite "$sample/Photos"
    expect favorites "[\"$sample/Photos\"]" "adding Photos to the favorites"
    grep -qx "file://$sample/Photos" "$bookmarks" 2>/dev/null || bad "Files: Photos isn't in GTK's bookmarks file"
    # Another app adds one (GTK writes the whole file at once) and a line
    # that isn't a local folder, which has to stay.
    { cat "$bookmarks"; printf 'file://%s Work things\nsftp://example.org/home\n' "$sample/Work"; } > "$bookmarks.new"
    mv "$bookmarks.new" "$bookmarks"
    expect favorites "[\"$sample/Photos\",\"$sample/Work\"]" "a favorite another app added"
    files_ipc removeFavorite "$sample/Photos"
    expect favorites "[\"$sample/Work\"]" "taking Photos away from the favorites"
    grep -q '^sftp://example.org/home$' "$bookmarks" || bad "Files: taking a favorite away lost another app's line"
    # Compress and extract (bsdtar). A folder gives Work.zip, and extracted
    # next to Work its one folder comes out as "Work (2)", not nested; two
    # items give Archive.zip, extracted into a folder called Archive. What's
    # made ends up selected, and no temporary is left behind.
    files_ipc select Work
    files_ipc compress
    expect selected '"Work.zip"' "compressing Work (Work.zip, selected)" 8
    # Its quick view lists what it holds (Work itself is a folder in it).
    files_ipc quickView
    expect preview '"archive"' "the quick view of an archive"
    n=$(find "$sample/Work" -type f | wc -l)
    d=$(find "$sample/Work" -type d | wc -l)
    holds="$([ "$n" -eq 1 ] && echo "1 file" || echo "$n files") in $([ "$d" -eq 1 ] && echo "1 folder" || echo "$d folders")"
    case "$(files_state listing)" in
        "\"$holds · "*) ;;
        *) bad "Files, the quick view of Work.zip: listing is $(files_state listing), expected $holds" ;;
    esac
    files_ipc quickView
    expect preview '""' "closing the quick view of an archive"
    files_ipc extract
    expect selected '"Work (2)"' "extracting Work.zip (its folder, as “Work (2)”)" 8
    { [ -f "$sample/Work (2)/img10.jpg" ] && [ -d "$sample/Work (2)/Inside" ]; } || bad "Files: “Work (2)” doesn't have Work's files"
    files_ipc select Photos
    files_ipc toggle clip.mp4
    files_ipc compress
    expect selected '"Archive.zip"' "compressing two items (Archive.zip)" 8
    files_ipc extract
    expect selected '"Archive"' "extracting Archive.zip (into “Archive”)" 8
    { [ -d "$sample/Archive/Photos" ] && [ -f "$sample/Archive/clip.mp4" ]; } || bad "Files: “Archive” doesn't have both items"
    [ -z "$(find "$sample" -name '*.spore-*')" ] || bad "Files: compressing or extracting left a temporary behind"
    # A name that starts with "@" is zipped as itself: bsdtar read
    # "@secret.tar" as what secret.tar holds. And a name of 80 Japanese
    # characters (240 bytes) copies: its temporary, named after it, went over
    # the 255 a name can have (FileOps.qml).
    mkdir -p "$tmp/names/in" "$tmp/names/to"
    echo private > "$tmp/names/in/secret.txt"
    "${bsdtar:-bsdtar}" -cf "$tmp/names/secret.tar" -C "$tmp/names/in" secret.txt
    echo mine > "$tmp/names/@secret.tar"
    long=$(printf '写%.0s' $(seq 80)).txt
    echo long > "$tmp/names/$long"
    files_ipc go "$tmp/names/@secret.tar"
    sleep 0.6
    files_ipc compress
    expect selected '"@secret.zip"' "compressing “@secret.tar”" 8
    [ "$("${bsdtar:-bsdtar}" -tf "$tmp/names/@secret.zip")" = "@secret.tar" ] ||
        bad "Files: “@secret.zip” doesn't hold “@secret.tar” but $("${bsdtar:-bsdtar}" -tf "$tmp/names/@secret.zip" | tr '\n' ' ')"
    files_ipc select "$long"
    files_ipc copy
    files_ipc go "$tmp/names/to"
    sleep 0.6
    files_ipc paste
    for _ in $(seq 20); do
        [ -f "$tmp/names/to/$long" ] && break
        sleep 0.2
    done
    [ -f "$tmp/names/to/$long" ] || bad "Files: a file with a 244-byte name wasn't copied"
    # Recent: the files in recently-used.xbel (the test's), newest first and only
    # those still there; two with the same name get their folders. Opening one
    # (with a stand-in app for JPEGs) puts it first, with Files among the apps
    # that used it; sending one to the Trash takes that one, and it leaves.
    mkdir -p "$tmp/recent/a" "$tmp/recent/b" "$tmp/data/applications"
    echo a > "$tmp/recent/a/notes.txt"
    echo b > "$tmp/recent/b/notes.txt"
    cp "$repo/assets/wallpapers/spore-dome.jpg" "$tmp/recent/photo.jpg"
    bookmark() {
        printf '  <bookmark href="file://%s" added="%s" modified="%s" visited="%s">\n    <info>\n' "$1" "$2" "$2" "$2"
        printf '      <metadata owner="http://freedesktop.org">\n        <mime:mime-type type="text/plain"/>\n'
        printf '        <bookmark:applications>\n          <bookmark:application name="Test" exec="&apos;test %%u&apos;" modified="%s" count="1"/>\n' "$2"
        printf '        </bookmark:applications>\n      </metadata>\n    </info>\n  </bookmark>\n'
    }
    {
        printf '<?xml version="1.0" encoding="UTF-8"?>\n<xbel version="1.0"\n'
        printf '      xmlns:bookmark="http://www.freedesktop.org/standards/desktop-bookmarks"\n'
        printf '      xmlns:mime="http://www.freedesktop.org/standards/shared-mime-info"\n>\n'
        bookmark "$tmp/recent/a/notes.txt" 2026-01-01T10:00:00.000000Z
        bookmark "$tmp/recent/photo.jpg" 2026-01-02T10:00:00.000000Z
        bookmark "$tmp/recent/gone.txt" 2026-01-03T10:00:00.000000Z
        bookmark "$tmp/recent/b/notes.txt" 2026-01-04T10:00:00.000000Z
        printf '</xbel>\n'
    } > "$tmp/data/recently-used.xbel"
    cat > "$tmp/viewer" <<EOF
#!/bin/sh
printf '%s\\n' "\$1" > "$tmp/viewer.part" && mv "$tmp/viewer.part" "$tmp/viewer.txt"
EOF
    chmod +x "$tmp/viewer"
    printf '[Desktop Entry]\nType=Application\nName=Test viewer\nExec=%s %%f\nMimeType=image/jpeg;\n' "$tmp/viewer" \
        > "$tmp/data/applications/spore-test-viewer.desktop"
    printf '[Default Applications]\nimage/jpeg=spore-test-viewer.desktop\n' > "$tmp/config/mimeapps.list"
    files_ipc go "recent:///"
    expect names "[\"notes.txt ($tmp/recent/b)\",\"photo.jpg\",\"notes.txt ($tmp/recent/a)\"]" "the Recent place (newest first, without the gone one)"
    files_ipc select photo.jpg
    files_ipc activate
    expect names "[\"photo.jpg\",\"notes.txt ($tmp/recent/b)\",\"notes.txt ($tmp/recent/a)\"]" "Recent, once photo.jpg is opened"
    [ "$(cat "$tmp/viewer.txt" 2>/dev/null)" = "$tmp/recent/photo.jpg" ] ||
        bad "Files: opening photo.jpg from Recent didn't open it with its app"
    sed -n "\\|<bookmark href=\"file://$tmp/recent/photo.jpg\"|,\\|</bookmark>|p" "$tmp/data/recently-used.xbel" |
        grep -q '<bookmark:application name="Files" exec="&apos;spore-files %u&apos;" modified="[^"]*" count="1"/>' ||
        bad "Files: opening photo.jpg didn't add Files to its bookmark"
    files_ipc select "notes.txt ($tmp/recent/a)"
    files_ipc trash
    expect names '["photo.jpg","notes.txt"]' "Recent, once one of its files is in the Trash"
    { ! [ -e "$tmp/recent/a/notes.txt" ] && [ -e "$tmp/recent/b/notes.txt" ]; } ||
        bad "Files: Move to Trash in Recent didn't take the right notes.txt"
    files_ipc open "$sample"
    sleep 1
    expect windows 2 "opening another window"
    files_pss=$(awk '/^Pss:/ { printf "%.0f", $2 / 1024 }' "/proc/$files_pid/smaps_rollup")
    files_children=$(pgrep -P "$files_pid" | tr '\n' ' ')
    files_ipc close
    sleep 0.5
    expect windows 1 "closing a window"
    # The last one: the process exits (and doesn't crash on the way out).
    files_ipc close
    sleep 2
    [ -d "/proc/$files_pid" ] && bad "Files didn't exit when its last window closed"
    grep -qE 'crashed|pure virtual' "$files_log" && bad "Files crashed:" && grep -E 'crashed|pure virtual' "$files_log" | sed 's/^/    /'
    for c in $files_children; do
        [ -d "/proc/$c" ] && bad "still alive after Files exited: $c $(tr '\0' ' ' < "/proc/$c/cmdline" | cut -c1-60)"
    done
    files_found=$(grep -E 'ERROR|ReferenceError|TypeError|SyntaxError|RangeError|is not a type|is not defined|Unable to assign|Cannot assign|Binding loop|Failed to load|ResetModel called' "$files_log" | sort -u)
    [ -n "$files_found" ] && bad "errors in Files' log:" && echo "$files_found" | sed 's/^/    /' | head -20
fi

echo "8. Lock (the nested session)"
ipc lock lock
sleep 2
[ "$(ipc lock isLocked)" = true ] || bad "lock didn't lock"
check_errors "when locking"

echo "9. Exit with no orphans"
children=$(pgrep -P "$shell_pid" | tr '\n' ' ')
kill "$shell_pid"
sleep 2
for c in $children; do
    [ -d "/proc/$c" ] || continue
    cmd=$(tr '\0' ' ' < "/proc/$c/cmdline")
    # niri's event reader exits by itself with the next event.
    case "$cmd" in *"niri msg"*event-stream*) continue ;; esac
    bad "still alive after the shell exited: $c ${cmd:0:60}"
    kill "$c" 2>/dev/null
done
shell_pid=
check_errors "at the end"

warnings=$(grep -c 'WARN' "$log")
echo
echo "Shell memory after opening and closing everything: ${pss:-?} MB (PSS). Warnings in the log: $warnings."
echo "Files memory with two windows open: ${files_pss:-?} MB (PSS)."
if [ "$fail" = 0 ]; then
    echo "OK"
else
    echo "FAILED"
fi
exit "$fail"
