import QtQuick
import Quickshell
import Quickshell.Io
import "fileutil.js" as Util

// The favorite folders on the left: GTK's bookmarks file, the one Thunar,
// Nautilus and the open and save dialogs of GTK apps use too (one URI per
// line, maybe followed by a name). Only local folders show; the other lines
// (sftp://, smb://…) are kept as they are. files.qml has one for every
// window, and a change made by another app shows at once.
QtObject {
    id: root

    readonly property string file: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/gtk-3.0/bookmarks"

    // [{ path, label, uri }] in the file's order; uri is the line's own, to
    // take it away even if another app spelled it differently.
    property var folders: []

    function has(path: string): bool {
        return folders.some(b => b.path === path)
    }

    function add(path: string): void {
        if (!has(path)) edit("add", Util.fileUri(path))
    }

    function remove(path: string): void {
        const bookmark = folders.find(b => b.path === path)
        if (bookmark) edit("remove", bookmark.uri)
    }

    function parse(text: string): var {
        const out = []
        for (const line of text.split("\n")) {
            const trimmed = line.trim()
            if (!trimmed.startsWith("file:///")) continue
            const space = trimmed.indexOf(" ")
            const uri = space < 0 ? trimmed : trimmed.slice(0, space)
            let path
            try {
                path = decodeURIComponent(uri.slice(7))
            } catch (e) {
                continue
            }
            if (path.length > 1 && path.endsWith("/")) path = path.slice(0, -1)
            const name = space < 0 ? "" : trimmed.slice(space + 1).trim()
            if (!out.some(b => b.path === path)) out.push({ path: path, label: name || Util.baseName(path), uri: uri })
        }
        return out
    }

    property FileView view: FileView {
        path: root.file
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.folders = root.parse(text())
        // No file yet: no favorites.
        onLoadFailed: root.folders = []
    }

    // $1 add or remove, $2 the file, $3 the folder's URI. The file is written
    // again without that URI (and with it at the end, for add), all at once,
    // so another app never reads half of it.
    readonly property string editScript: `
        mkdir -p -- "$(dirname -- "$2")" || exit 1
        tmp=$2.spore-$$
        if [ -f "$2" ]; then
            URI=$3 awk '$1 != ENVIRON["URI"]' "$2" > "$tmp" || { rm -f -- "$tmp"; exit 1; }
        else
            : > "$tmp"
        fi
        if [ "$1" = add ]; then printf '%s\\n' "$3" >> "$tmp"; fi
        # A link (to the dotfiles, say) is written through, not replaced by a
        # file of its own.
        if [ -L "$2" ]; then
            cat -- "$tmp" > "$2"
            written=$?
            rm -f -- "$tmp"
            exit $written
        fi
        mv -f -- "$tmp" "$2"`

    // One edit at a time, in order.
    property var pending: []

    function edit(action: string, uri: string): void {
        pending = pending.concat([[action, uri]])
        if (!editor.running) next()
    }

    function next(): void {
        if (!pending.length) return
        const [action, uri] = pending[0]
        pending = pending.slice(1)
        editor.command = ["sh", "-c", editScript, "_", action, file, uri]
        editor.running = true
    }

    property Process editor: Process {
        onExited: {
            // A file that didn't exist isn't being watched yet: read it now.
            root.view.reload()
            root.next()
        }
    }
}
