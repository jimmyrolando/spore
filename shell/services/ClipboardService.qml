import QtQuick
import Quickshell
import Quickshell.Io

// Clipboard history with cliphist (+ wl-clipboard). Always running (in
// shell.qml), so it saves everything that's copied; ClipboardPanel.qml shows
// it.
//
// On top of what cliphist provides:
//   - the time of each entry (cliphist doesn't store it): the watcher records
//     it when saving, in clipboard/times.json;
//   - pins: cliphist drops old entries past maxItems, so a pinned one is
//     copied to clipboard/pins/ and lives separately (pins.json).
// What password managers mark as sensitive isn't saved (wl-paste passes
// CLIPBOARD_STATE=sensitive and cliphist ignores it).
Scope {
    id: root

    property string stateDir: ""
    property int maxItems: 500

    readonly property string dataDir: stateDir + "/clipboard"
    readonly property string cacheDir: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/spore/clipboard"

    // [{ key, id, pinned, kind, preview, time, image: { size, format, width, height } | null, line, file }]
    // id: cliphist's (null for pins); line: the line from `cliphist list` (used
    // by delete); file: a pin's file.
    property var entries: []

    property var times: ({})
    property var pins: []

    // --- Watchers --------------------------------------------------------------

    // One for text and one for images (as cliphist recommends). After saving
    // they print "<id> <epoch>" to record the time. Without cliphist in PATH
    // (old package) they do nothing.
    //
    // setpriv --pdeathsig: wl-paste dies with the shell. Otherwise, after a
    // restart (kill) it stayed alive and each copy was saved once more per
    // restart.
    component Watcher: Process {
        id: watcher
        property string type: "text"
        running: root.stateDir !== ""
        command: ["sh", "-c", `
            command -v cliphist >/dev/null && command -v wl-paste >/dev/null || exit 0
            exec setpriv --pdeathsig TERM wl-paste --type "$1" --watch sh -c '
                cliphist -max-items "$0" store && [ "\${CLIPBOARD_STATE:-data}" = data ] &&
                    printf "%s %s\\n" "$(cliphist list | head -n1 | cut -f1)" "$(date +%s)"
            ' "$2"`, "_", type, String(root.maxItems)]
        // The time goes only with a real copy (CLIPBOARD_STATE=data, from
        // wl-paste): cliphist skips a sensitive one, and the clipboard emptying
        // stores nothing, so the time used to land on the previous entry.
        stdout: SplitParser {
            onRead: (line) => root.stored(line)
        }
        // If wl-paste goes down (e.g. the compositor restarted), start it again.
        onExited: (code) => { if (code !== 0) restartTimer.restart() }
        property Timer restartTimer: Timer {
            interval: 3000
            onTriggered: watcher.running = true
        }
    }

    Watcher { type: "text" }
    Watcher { type: "image" }

    function stored(line: string): void {
        const [id, epoch] = line.trim().split(" ")
        if (!id || !epoch) return
        const t = Object.assign({}, times)
        t[id] = Number(epoch)
        // The ones cliphist already dropped (past maxItems) are cleaned up when
        // listing, but nothing is listed until the panel opens: keep the newest here.
        const ids = Object.keys(t)
        if (ids.length > root.maxItems) {
            ids.sort((a, b) => t[b] - t[a])
            for (const old of ids.slice(root.maxItems)) delete t[old]
        }
        times = t
        saveTimes.restart()
        if (listed) refresh()
    }

    // --- List --------------------------------------------------------------------

    // true from the first refresh (panel opened): until then, there's no need
    // to relist on every copy.
    property bool listed: false

    function refresh(): void {
        listed = true
        lister.running = true
    }

    Process {
        id: lister
        command: ["sh", "-c", "command -v cliphist >/dev/null && cliphist list"]
        stdout: StdioCollector {
            onStreamFinished: root.build(text)
        }
    }

    // [[ binary data 701 KiB jpeg 2048x995 ]]
    function parseImage(preview: string): var {
        const m = preview.match(/^\[\[ binary data (.+?) (\w+) (\d+)x(\d+) \]\]$/)
        return m ? { size: m[1], format: m[2], width: Number(m[3]), height: Number(m[4]) } : null
    }

    function classify(text: string): string {
        const t = text.trim()
        if (/^(https?|ftp|file):\/\/\S+$/i.test(t)) return "url"
        // Without "#" it needs some digit: "decade" or "facade" aren't colors.
        if (/^#([0-9a-f]{3}|[0-9a-f]{6}|[0-9a-f]{8})$/i.test(t) || /^(?=.*\d)([0-9a-f]{6}|[0-9a-f]{8})$/i.test(t)) return "hex"
        // Code: cliphist's preview comes on one line, so look at the shape: a block
        // or call at the start ("Name {", "foo("), braces or a semicolon at the end,
        // arrows, typical words, or lots of symbols.
        if (/^[\w.$-]+\s*\{|^[\w.$]+\(|[{};]\s*$|=>|^\s*(import|export|function|const|let|def|class|fn|pub|#include|<\/?\w+>)/m.test(t)
            || (t.match(/[{}()\[\];=:<>]/g) || []).length >= 6)
            return "code"
        return "txt"
    }

    function build(text: string): void {
        const list = []
        const alive = {}
        for (const line of text.split("\n")) {
            const tab = line.indexOf("\t")
            if (tab < 0) continue
            const id = line.slice(0, tab)
            const preview = line.slice(tab + 1)
            const image = parseImage(preview)
            alive[id] = true
            list.push({
                key: "c" + id,
                id: id,
                pinned: false,
                kind: image ? "img" : classify(preview),
                preview: preview,
                time: times[id] ?? 0,
                image: image,
                line: line,
                file: ""
            })
        }
        // Pins on top; the same content isn't repeated in the history.
        const pinnedPreviews = new Set(pins.map(p => p.preview))
        entries = pins.map(p => Object.assign({ key: p.key, id: null, pinned: true, line: "" }, p))
            .concat(list.filter(e => !pinnedPreviews.has(e.preview)))

        // Times of entries that no longer exist: out.
        const t = {}
        for (const id in times) if (alive[id]) t[id] = times[id]
        if (Object.keys(t).length !== Object.keys(times).length) {
            times = t
            saveTimes.restart()
        }

        // And their decoded images for the preview (loadDetail).
        cacheCleaner.keep = Object.keys(alive)
        cacheCleaner.running = true
    }

    // Deletes the cached images of entries that no longer exist: otherwise the
    // folder grew forever. The files are <id>.<format>.
    Process {
        id: cacheCleaner
        property var keep: []
        command: ["sh", "-c", `
            cd "$1" 2>/dev/null || exit 0
            shift
            keep=" $* "
            for f in *; do
                [ -f "$f" ] || continue
                case "$keep" in *" \${f%%.*} "*) ;; *) rm -f -- "$f" ;; esac
            done`, "_", root.cacheDir].concat(keep)
    }

    // --- Actions -----------------------------------------------------------------

    function mimeOf(entry: var): string {
        return entry.image ? "image/" + entry.image.format : "text/plain;charset=utf-8"
    }

    // Copies to the clipboard (the watcher saves it again at the top).
    function copy(entry: var): void {
        if (entry.pinned)
            Quickshell.execDetached(["sh", "-c", 'wl-copy --type "$2" < "$1"', "_", entry.file, mimeOf(entry)])
        else
            Quickshell.execDetached(["sh", "-c", 'cliphist decode "$1" | wl-copy --type "$2"', "_", entry.id, mimeOf(entry)])
    }

    function remove(entry: var): void {
        if (entry.pinned) {
            unpin(entry)
            return
        }
        remover.stdinText = entry.line
        remover.running = true
    }

    Process {
        id: remover
        property string stdinText: ""
        command: ["sh", "-c", 'printf "%s\\n" "$1" | cliphist delete', "_", stdinText]
        onExited: root.refresh()
    }

    function wipe(): void {
        wiper.running = true
    }

    Process {
        id: wiper
        command: ["cliphist", "wipe"]
        onExited: root.refresh()
    }

    function togglePin(entry: var): void {
        if (entry.pinned) unpin(entry)
        else pin(entry)
    }

    // Copies the content to pins/<key>.<ext>: it stays even if cliphist drops
    // the entry.
    function pin(entry: var): void {
        const key = "p" + Date.now()
        const ext = entry.image ? entry.image.format : "txt"
        pinner.meta = {
            key: key,
            kind: entry.kind,
            preview: entry.preview,
            time: entry.time || Math.floor(Date.now() / 1000),
            image: entry.image,
            file: dataDir + "/pins/" + key + "." + ext
        }
        pinner.cliphistId = entry.id
        pinner.running = true
    }

    Process {
        id: pinner
        property var meta: null
        property string cliphistId: ""
        command: ["sh", "-c", 'mkdir -p "$(dirname "$2")" && cliphist decode "$1" > "$2"', "_", cliphistId, meta ? meta.file : ""]
        onExited: (code) => {
            if (code !== 0) {
                console.warn("Clipboard: could not pin the entry")
                return
            }
            root.pins = [meta].concat(root.pins)
            savePins.restart()
            root.refresh()
        }
    }

    function unpin(entry: var): void {
        Quickshell.execDetached(["rm", "-f", entry.file])
        pins = pins.filter(p => p.key !== entry.key)
        savePins.restart()
        refresh()
    }

    // --- Preview of the selected entry ---------------------------------------------

    // Full text (cliphist's preview comes truncated and on one line) or the
    // image file to show.
    property string detailKey: ""
    property string detailText: ""
    property string detailImage: ""

    function loadDetail(entry: var): void {
        detailKey = entry ? entry.key : ""
        detailText = ""
        detailImage = ""
        if (!entry) return
        if (entry.image) {
            if (entry.pinned) {
                detailImage = entry.file
                return
            }
            const file = cacheDir + "/" + entry.id + "." + entry.image.format
            imageDecoder.key = entry.key
            imageDecoder.file = file
            imageDecoder.cliphistId = entry.id
            imageDecoder.running = true
            return
        }
        textDecoder.key = entry.key
        textDecoder.command = ["sh", "-c", textScript, "_", entry.pinned ? "file" : "id", entry.pinned ? entry.file : entry.id]
        textDecoder.running = true
    }

    // Arguments: "file" and a pin's file, or "id" and cliphist's id. The first
    // 200 KB is plenty to see what it is ("…" at the end says there's more): a
    // copy of hundreds of MB went whole into the shell's memory and the
    // preview. (Copy still copies all of it.)
    readonly property string textScript: `
        if [ "$1" = file ]; then cat -- "$2"; else cliphist decode "$2"; fi |
            { head -c 200000; if [ "$(head -c 1 | wc -c)" -gt 0 ]; then printf '\\n…'; fi; }`

    // A request while one runs goes after it (Quickshell runs it then): each
    // run notes whose it is, and an answer for an entry no longer selected is
    // ignored. (Before, the earlier run's text showed for the new entry, and an
    // image could stay blank.)
    Process {
        id: textDecoder
        property string key: ""
        property string runFor: ""
        onStarted: runFor = key
        stdout: StdioCollector {
            onStreamFinished: if (textDecoder.runFor === root.detailKey) root.detailText = text
        }
    }

    Process {
        id: imageDecoder
        property string key: ""
        property string file: ""
        property string cliphistId: ""
        property string runFor: ""
        property string runFile: ""
        onStarted: {
            runFor = key
            runFile = file
        }
        command: ["sh", "-c", '[ -s "$2" ] || { mkdir -p "$(dirname "$2")" && cliphist decode "$1" > "$2.tmp" && mv "$2.tmp" "$2"; }', "_", cliphistId, file]
        onExited: (code) => { if (code === 0 && runFor === root.detailKey) root.detailImage = runFile }
    }

    // --- State on disk -----------------------------------------------------------

    Timer {
        id: saveTimes
        interval: 500
        onTriggered: timesWriter.setText(JSON.stringify(root.times))
    }

    Timer {
        id: savePins
        interval: 200
        onTriggered: pinsWriter.setText(JSON.stringify(root.pins))
    }

    // FileView (tmp + rename) rather than a process: a write requested while the
    // previous one was running isn't lost. No preload: they only write (the ones
    // below read, once at startup).
    FileView {
        id: timesWriter
        path: root.stateDir ? root.dataDir + "/times.json" : ""
        preload: false
    }

    FileView {
        id: pinsWriter
        path: root.stateDir ? root.dataDir + "/pins.json" : ""
        preload: false
    }

    // The folder has to exist to write.
    Component.onCompleted: if (stateDir) Quickshell.execDetached(["mkdir", "-p", dataDir])

    FileView {
        path: root.stateDir ? root.dataDir + "/times.json" : ""
        onLoaded: {
            try { root.times = JSON.parse(text()) } catch (e) {}
        }
    }

    FileView {
        path: root.stateDir ? root.dataDir + "/pins.json" : ""
        onLoaded: {
            try { root.pins = JSON.parse(text()) } catch (e) {}
        }
    }
}
