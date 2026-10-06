import QtQuick
import Quickshell
import Quickshell.Io
import "fileutil.js" as Util

// The thumbnails the freedesktop cache already has for the open folder's
// files (~/.cache/thumbnails, which Thunar, tumbler and GTK fill). A single
// process checks which exist, instead of every Image trying to load one
// (each miss was a warning in the log). A thumbnail older than its file is
// stale and doesn't count.
QtObject {
    id: root

    required property FolderModel folderModel

    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/thumbnails"
    // path -> thumbnail path, for the files that have one.
    property var found: ({})

    function thumbnailFor(path: string): string {
        return found[path] || ""
    }

    // The listing changes while it loads and whenever a file appears: it's
    // checked again once it settles.
    property Timer settle: Timer {
        interval: 150
        onTriggered: root.scan()
    }
    property Connections listing: Connections {
        target: root.folderModel
        function onTotalCountChanged() { root.settle.restart() }
        function onFolderChanged() {
            root.found = {}
            root.settle.restart()
        }
    }

    // The Recent place changes without its count changing (a file opened
    // goes first; with 100, a new one takes the last one's place).
    property Connections recent: Connections {
        target: root.folderModel.recents
        function onItemsChanged() { if (root.folderModel.recent) root.settle.restart() }
    }

    // $1 the cache folder. Reads "<md5> <path>" lines, one per file, up to an
    // empty one, and prints "<md5> <size>" for the ones with a fresh
    // thumbnail (the biggest that's worth it: large is 256 px; normal, 128).
    // The files come on stdin, not as arguments: a folder with tens of
    // thousands of them went over the system's limit for arguments, and the
    // process didn't even start.
    readonly property string script: `
        cache=$1
        while IFS= read -r line && [ -n "$line" ]; do
            hash=\${line%% *}
            file=\${line#* }
            for size in large x-large normal; do
                t="$cache/$size/$hash.png"
                if [ -f "$t" ] && ! [ "$file" -nt "$t" ]; then
                    echo "$hash $size"
                    break
                fi
            done
        done`

    // md5 -> path of the last scan.
    property var pending: ({})

    function scan(): void {
        if (checker.running) {
            settle.restart()
            return
        }
        const lines = []
        const byHash = {}
        for (const entry of folderModel.all()) {
            if (entry.isDir) continue
            const path = entry.path
            // A line each: a name with a newline in it gets no thumbnail.
            if (path.includes("\n")) continue
            const hash = Qt.md5(Util.fileUri(path))
            byHash[hash] = path
            lines.push(hash + " " + path)
        }
        if (lines.length === 0) {
            found = {}
            return
        }
        pending = byHash
        checker.list = lines.join("\n") + "\n\n"
        checker.running = true
    }

    property Process checker: Process {
        // What scan() wrote down, for the script's stdin.
        property string list: ""
        command: ["sh", "-c", root.script, "_", root.cacheDir]
        stdinEnabled: true
        onStarted: {
            write(list)
            list = ""
        }
        stdout: StdioCollector {
            onStreamFinished: {
                const map = {}
                for (const line of text.split("\n")) {
                    const [hash, size] = line.split(" ")
                    const path = root.pending[hash]
                    if (path) map[path] = root.cacheDir + "/" + size + "/" + hash + ".png"
                }
                root.found = map
            }
        }
    }
}
