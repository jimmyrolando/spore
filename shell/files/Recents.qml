import QtQuick
import Quickshell
import Quickshell.Io
import "fileutil.js" as Util

// The files used lately, for the Recent place: the freedesktop list that GTK
// apps, LibreOffice, the browsers and Thunar keep up to date
// (~/.local/share/recently-used.xbel), newest first, only the ones still
// there, up to 100. Files adds to it what it opens, as Thunar did, so the
// list keeps the files opened from here too.
//
// The views select by name, and two recent files can share one: those get
// their folder after it, "notes.txt (~/Work)".
QtObject {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string file: (Quickshell.env("XDG_DATA_HOME") || home + "/.local/share") + "/recently-used.xbel"
    // Read once a window shows Recent (and kept up to date from then on).
    property bool active: false
    // [{ name, path, isDir, size, modified }], newest first.
    property var items: []
    // name -> path.
    property var pathByName: ({})
    // Read at least once.
    property bool loaded: false

    // The list, read again whenever it changes (GTK apps rewrite it whole).
    property FileView reader: FileView {
        path: root.active ? root.file : ""
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: root.parse(text())
        onLoadFailed: root.parse("")
    }

    function fromXml(s: string): string {
        return s.replace(/&#x([0-9a-fA-F]+);/g, (m, h) => String.fromCharCode(parseInt(h, 16)))
            .replace(/&#(\d+);/g, (m, d) => String.fromCharCode(Number(d)))
            .replace(/&quot;/g, "\"").replace(/&apos;/g, "'").replace(/&lt;/g, "<").replace(/&gt;/g, ">").replace(/&amp;/g, "&")
    }

    // As GLib writes an attribute (an apostrophe too: a URI keeps it).
    function toXml(s: string): string {
        return s.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;").replace(/"/g, "&quot;").replace(/'/g, "&apos;")
    }

    // A tag's attributes: { name: value } (still escaped).
    function attributes(tag: string): var {
        const out = {}
        const pairs = /([\w:-]+)="([^"]*)"/g
        let m
        while ((m = pairs.exec(tag)) !== null) out[m[1]] = m[2]
        return out
    }

    // "2026-09-03T22:14:16.516000Z": GLib writes microseconds, and Date.parse()
    // takes that for no date at all.
    function time(s: string): real {
        return Date.parse((s || "").replace(/(\.\d{3})\d+/, "$1")) || 0
    }

    // file:///home/x (or file://localhost/home/x) -> /home/x; "" if it isn't
    // a local file or can't be decoded.
    function pathOf(uri: string): string {
        const rest = uri.replace(/^file:\/\/(localhost)?/, "")
        if (rest === uri || !rest.startsWith("/")) return ""
        try {
            return decodeURIComponent(rest)
        } catch (e) {
            return ""
        }
    }

    function pretty(path: string): string {
        return path === home ? "~" : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path
    }

    // The newest 200, for the checker to say which are still there.
    property var candidates: []

    function parse(xml: string): void {
        const used = {}
        const tags = /<bookmark\s([^>]*)>/g
        let m
        while ((m = tags.exec(xml)) !== null) {
            const attrs = attributes(m[1])
            const path = pathOf(fromXml(attrs.href || ""))
            // A line each for the checker.
            if (!path || path.includes("\n")) continue
            const when = Math.max(time(attrs.visited), time(attrs.modified), time(attrs.added))
            if (!(path in used) || used[path] < when) used[path] = when
        }
        candidates = Object.keys(used).map(path => ({ path: path, used: used[path] }))
            .sort((a, b) => b.used - a.used).slice(0, 200)
        check()
    }

    // Which candidates are still there (a file moved or sent to the Trash
    // leaves the list: files.qml asks again after each operation).
    function check(): void {
        if (checker.busy) {
            checker.again = true
            return
        }
        if (!candidates.length) {
            publish([], {})
            return
        }
        checker.busy = true
        checker.list = candidates
        checker.command = ["sh", "-c", checkScript, "_"].concat(candidates.map(c => c.path))
        checker.running = true
    }

    // Arguments: the paths. Prints "<size>\t<mtime>\t<kind>\t<path>" for the
    // ones still there (a link followed); stat says nothing for the rest.
    readonly property string checkScript: `
        stat -L --printf '%s\\t%Y\\t%F\\t%n\\n' -- "$@" 2>/dev/null
        exit 0`

    property Process checker: Process {
        // The candidates this run is for; busy until its answer is read (it
        // can come after the process exits); and whether they changed since.
        property var list: []
        property bool busy: false
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                const there = {}
                for (const line of text.split("\n")) {
                    const parts = line.split("\t")
                    // Files and folders: not a fifo or a device.
                    if (parts.length < 4 || !/^(directory|regular (empty )?file)$/.test(parts[2])) continue
                    there[parts.slice(3).join("\t")] = {
                        size: Number(parts[0]),
                        modified: new Date(Number(parts[1]) * 1000),
                        isDir: parts[2] === "directory"
                    }
                }
                root.checker.busy = false
                root.publish(root.checker.list, there)
                if (!root.checker.again) return
                root.checker.again = false
                root.check()
            }
        }
    }

    function publish(list: var, there: var): void {
        const kept = list.filter(c => there[c.path]).slice(0, 100)
        const bases = kept.map(c => Util.baseName(c.path) || c.path)
        const count = {}
        for (const base of bases) count[base] = (count[base] || 0) + 1
        const names = kept.map((c, i) => count[bases[i]] > 1 ? bases[i] + " (" + pretty(Util.parentOf(c.path)) + ")" : bases[i])
        // The views (and Move to Trash) go by name, so each has to be one of a
        // kind: one that's still repeated ("a (~)" can be a file's own name)
        // is its path, which no name can be.
        const uses = {}
        for (const name of names) uses[name] = (uses[name] || 0) + 1
        const byName = {}
        items = kept.map((c, i) => {
            const name = uses[names[i]] > 1 ? c.path : names[i]
            byName[name] = c.path
            const info = there[c.path]
            return { name: name, path: c.path, isDir: info.isDir, size: info.size, modified: info.modified }
        })
        pathByName = byName
        loaded = true
    }

    // --- Adding to it ---

    // A file Files opened (with its app, or another one): first in the list,
    // as GTK apps do it. Its bookmark gets the time and Files among the apps
    // that used it, or a new one is added, with its type (GTK's file choosers
    // show and filter by it), from gio.
    function record(path: string): void {
        typer.queue = typer.queue.concat([path])
        typer.next()
    }

    property Process typer: Process {
        property var queue: []
        property string path: ""
        // From the start until its answer is read, as the checker.
        property bool busy: false

        function next(): void {
            if (busy || !queue.length) return
            busy = true
            path = queue[0]
            queue = queue.slice(1)
            command = ["gio", "info", "-a", "standard::content-type", "--", path]
            running = true
        }

        stdout: StdioCollector {
            onStreamFinished: {
                const type = (text.match(/standard::content-type: (\S+)/) || [])[1] || "application/octet-stream"
                root.typer.busy = false
                root.write(root.typer.path, type)
                root.typer.next()
            }
        }
    }

    readonly property string header: "<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n<xbel version=\"1.0\"\n"
        + "      xmlns:bookmark=\"http://www.freedesktop.org/standards/desktop-bookmarks\"\n"
        + "      xmlns:mime=\"http://www.freedesktop.org/standards/shared-mime-info\"\n>\n"

    // Read right before writing, so what another app wrote just before stays,
    // and written whole to a new file renamed over it, as GLib does. Given its
    // path the first time it's needed.
    property FileView editor: FileView {
        blockWrites: true
        printErrors: false
        onSaveFailed: console.warn("Recents: couldn't write " + root.file)
    }

    // Anything that isn't as GLib writes the list leaves it untouched: a
    // second bookmark for the same file would make GLib refuse the whole
    // list, and GTK apps start a new one over it.
    function write(path: string, type: string): void {
        if (editor.path === file) editor.reload()
        else editor.path = file
        editor.waitForJob()
        let xml = editor.loaded ? editor.text() : ""
        // None yet (or emptied): a new list.
        if (!xml.trim()) xml = header + "</xbel>\n"
        if (!/<\/xbel>\s*$/.test(xml)) return

        // GLib's way: microseconds, in UTC.
        const now = new Date().toISOString().replace(/Z$/, "000Z")
        const uri = Util.fileUri(path)
        const app = (count) => "<bookmark:application name=\"Files\" exec=\"&apos;spore-files %u&apos;\" modified=\"" + now + "\" count=\"" + count + "\"/>"

        // Its bookmark, if it has one.
        const tags = /<bookmark\s([^>]*)>/g
        let m
        while ((m = tags.exec(xml)) !== null) {
            if (fromXml(attributes(m[1]).href || "") === uri) break
        }
        if (m !== null) {
            const start = m.index
            const tagEnd = start + m[0].length
            const end = xml.indexOf("</bookmark>", tagEnd)
            tags.lastIndex = tagEnd
            const following = tags.exec(xml)
            if (m[1].endsWith("/") || end < 0 || following !== null && following.index < end) return
            const tag = m[0].replace(/(\smodified=")[^"]*"/, "$1" + now + "\"").replace(/(\svisited=")[^"]*"/, "$1" + now + "\"")
            let body = xml.slice(tagEnd, end)
            const ours = body.match(/<bookmark:application\s[^>]*\bname="Files"[^>]*\/>/)
            if (ours) {
                body = body.replace(ours[0], app(Number(attributes(ours[0]).count || 0) + 1))
            } else if (body.includes("</bookmark:applications>")) {
                body = body.replace("</bookmark:applications>", "  " + app(1) + "\n        </bookmark:applications>")
            } else {
                return
            }
            xml = xml.slice(0, start) + tag + body + xml.slice(end)
        } else {
            const bookmark = "  <bookmark href=\"" + toXml(uri) + "\" added=\"" + now + "\" modified=\"" + now + "\" visited=\"" + now + "\">\n"
                + "    <info>\n"
                + "      <metadata owner=\"http://freedesktop.org\">\n"
                + "        <mime:mime-type type=\"" + toXml(type) + "\"/>\n"
                + "        <bookmark:applications>\n"
                + "          " + app(1) + "\n"
                + "        </bookmark:applications>\n"
                + "      </metadata>\n"
                + "    </info>\n"
                + "  </bookmark>\n"
            const close = xml.lastIndexOf("</xbel>")
            xml = xml.slice(0, close) + bookmark + xml.slice(close)
        }
        editor.setText(xml)
    }
}
