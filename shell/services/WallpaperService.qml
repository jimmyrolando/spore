import QtQuick
import Quickshell
import Quickshell.Io

// List of wallpapers in the folder (settings.json: picker.wallpaperDir) and
// their thumbnails on disk. Used by SettingsWindow's grid and the strip
// (WallpaperStrip), which get it as `wallpapers`.
//
// Re-reads the folder and generates the missing thumbnails every time
// `refresh()` is called (when either of those two windows opens).
Scope {
    id: root

    property string folder: ""

    // Absolute paths, sorted. Images and videos mixed.
    property var files: []

    // Accepted extensions (lowercase). Videos play once at login and on unlock
    // (see VideoPlayer.qml and video/shell.qml).
    readonly property var imageExtensions: ["jpg", "jpeg", "png", "webp"]
    readonly property var videoExtensions: ["mp4", "mov", "webm"]

    function extension(path: string): string {
        return path.split(".").pop().toLowerCase()
    }
    function isVideo(path: string): bool {
        return videoExtensions.includes(extension(path))
    }

    // Wallpapers are 4K+ PNG/JPG (and a PNG can't be decoded at a lower
    // resolution: Qt reads all of it even when shown small), so each one is
    // scaled down just once, to 400px, in thumbDir.
    readonly property string thumbDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/spore/thumbs"
    // Goes up when new thumbnails are generated: the Images re-read them.
    property int thumbsVersion: 0
    // false while thumbGen runs: until it finishes, a missing thumbnail doesn't
    // mean it can't be generated.
    property bool thumbsReady: false

    // For each video, its last frame at full size (the background left when it
    // ends): generated along with the thumbnail, just once, and copied when the
    // video is chosen instead of extracting it again with ffmpeg (1-3 s).
    readonly property string stillDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/spore/stills"
    function stillFor(path: string): string {
        return stillDir + "/" + path.split("/").pop() + ".jpg"
    }

    // Settings (wallpaper.videos): when off, videos behave like images (the
    // thumbnails don't get the ▶).
    property bool videosEnabled: true

    function thumbFor(path: string): string {
        return Qt.resolvedUrl(thumbDir + "/" + path.split("/").pop() + ".jpg") + "?" + thumbsVersion
    }

    function refresh(): void {
        if (!folder) return
        thumbsReady = false
        lister.running = true
        thumbGen.running = true
    }

    onFolderChanged: files = []

    // find ... \( -iname '*.jpg' -o -iname '*.mp4' ... \)
    readonly property var findPattern: {
        const names = imageExtensions.concat(videoExtensions).map(e => ["-iname", "*." + e])
        return ["("].concat(...names.map((n, i) => i === 0 ? n : ["-o"].concat(n)), [")"])
    }

    Process {
        id: lister
        command: ["find", root.folder, "-maxdepth", "1", "-type", "f"].concat(root.findPattern)
        stdout: StdioCollector {
            onStreamFinished: {
                const list = text.trim().split("\n").filter(l => l.length > 0).sort()
                // Same list: don't reassign, so the views aren't rebuilt.
                if (JSON.stringify(list) !== JSON.stringify(root.files)) root.files = list
            }
        }
    }

    // In parallel and in the background: the views show the existing ones right
    // away, and reload when it finishes if there were new ones. It only starts
    // processes for wallpapers newer than their thumbnail (the filter runs in a
    // single shell: it used to be 100+ processes on every open).
    //
    // With ffmpeg: from a video, its last frame (how the desktop looks after the
    // animation), with the thumbnail and the full-size frame (stillDir) in the
    // same pass. If it fails, a "<name>.jpg.failed" marker stays so it isn't
    // retried every time (the view uses the original); if the wallpaper
    // changes, it's retried. Without ffmpeg in PATH (old package) it does
    // nothing: it doesn't mark as failed the ones that could be generated.
    Process {
        id: thumbGen
        command: ["sh", "-c", `
            command -v ffmpeg >/dev/null || exit 0
            mkdir -p "$1" "$STILLS"
            shift
            dir="$1"
            shift
            find "$dir" -maxdepth 1 -type f "$@" -print0 |
                while IFS= read -r -d '' f; do
                    t="$THUMBS/$(basename "$f").jpg"
                    s="$STILLS/$(basename "$f").jpg"
                    [ "$t.failed" -nt "$f" ] && continue
                    # Videos also need their full-size frame.
                    case "$(printf %s "$f" | tr A-Z a-z)" in
                        ${root.videoExtensions.map(e => "*." + e).join("|")}) [ "$t" -nt "$f" ] && [ "$s" -nt "$f" ] && continue ;;
                        *) [ "$t" -nt "$f" ] && continue ;;
                    esac
                    printf '%s\\0' "$f"
                done |
                xargs -0 -r -P "$(nproc)" -I{} sh -c '
                    t="$THUMBS/$(basename "$1").jpg"
                    s="$STILLS/$(basename "$1").jpg"
                    case "$(printf %s "$1" | tr A-Z a-z)" in
                        ${root.videoExtensions.map(e => "*." + e).join("|")}) video=1 ;;
                        *) video="" ;;
                    esac
                    # .tmp + mv: if it is interrupted, no half-made thumbnail is left
                    # "newer" than the original. Always exit 0: with a 255, xargs
                    # aborts all the rest.
                    # Video: the last 0.3 s, -update 1 keeps the last frame; a single
                    # decode for both outputs.
                    if [ -n "$video" ]; then
                        ffmpeg -v error -y -sseof -0.3 -i "$1" -map 0:v -update 1 -q:v 2 "$s.tmp.jpg" -map 0:v -vf scale=400:-2 -update 1 -q:v 4 "$t.tmp.jpg" </dev/null && mv "$s.tmp.jpg" "$s" && mv "$t.tmp.jpg" "$t"
                    else
                        ffmpeg -v error -y -i "$1" -vf scale=400:-2 -frames:v 1 -update 1 -q:v 4 "$t.tmp.jpg" </dev/null && mv "$t.tmp.jpg" "$t"
                    fi
                    if [ $? -eq 0 ]; then
                        echo new
                    else
                        touch "$t.failed"
                    fi
                    rm -f "$t.tmp.jpg" "$s.tmp.jpg"
                    exit 0
                ' _ {}`, "_", root.thumbDir, root.folder].concat(root.findPattern)
        environment: ({ THUMBS: root.thumbDir, STILLS: root.stillDir })
        stdout: StdioCollector {
            onStreamFinished: {
                if (text.includes("new")) root.thumbsVersion = root.thumbsVersion + 1
                root.thumbsReady = true
            }
        }
    }
}
