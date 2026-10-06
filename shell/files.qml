import QtQuick
import Quickshell
import Quickshell.Io
import "common"
import "services"
import "files"

// Spore Files, the file manager: another Quickshell process, apart from the
// shell (`spore-files [folder]` starts it with `quickshell -p
// shell/files.qml`). Its windows are regular windows niri tiles like any
// app's, it exists only while one is open, and if it ever hangs it doesn't
// take the bar or the lockscreen with it. It lives in shell/ and not in a
// folder of its own because Quickshell doesn't import from outside the entry
// point's folder, and it uses the shell's theme and controls.
//
// A window per `spore-files` (when Files is already running, the command
// asks it over IPC); the process exits when the last one closes.
ShellRoot {
    id: root

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: Quickshell.env("SPORE_STATE_DIR")
        || (Quickshell.env("XDG_STATE_HOME") || home + "/.local/state") + "/spore"

    // --- The theme: the shell's, followed live ---

    // For the fonts and the clock's format.
    Settings {
        id: settings
    }

    // Not "theme": inside the windows that name is their own property.
    Theme {
        id: filesTheme
        uiFont: settings.fontInterface
        fontFamily: settings.fontMonospace
    }

    // The shell writes the theme it applies here (the mode already resolved:
    // "auto" is dark or light by then). Read before the first window is drawn,
    // so it doesn't flash the default colors.
    FileView {
        path: root.stateDir + "/theme.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                const applied = JSON.parse(text())
                if (applied.mode === "dark" || applied.mode === "light") filesTheme.mode = applied.mode
                if (filesTheme.paletteNames.includes(applied.palette)) filesTheme.palette = applied.palette
            } catch (e) {
                // Half written: the next change brings it whole.
            }
        }
        // No shell has written it yet: the factory mode and palette.
        onLoadFailed: {
            filesTheme.mode = "light"
            filesTheme.palette = "spore"
        }
    }

    // The "wallpaper" palette's colors (matugen, see shell.qml).
    FileView {
        path: root.stateDir + "/colors.json"
        blockLoading: true
        printErrors: false
        watchChanges: true
        onFileChanged: reload()
        onLoaded: {
            try {
                filesTheme.matugen = JSON.parse(text()).colors
            } catch (e) {
            }
        }
    }

    // --- What the windows share, remembered in files.json ---

    property string view: "grid"
    property bool showHidden: false
    property string sortBy: "name"
    property bool descending: false

    FileView {
        id: prefs
        path: root.stateDir + "/files.json"
        blockLoading: true
        printErrors: false
        atomicWrites: false
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                if (saved.view === "grid" || saved.view === "list") root.view = saved.view
                root.showHidden = saved.showHidden === true
                if (["name", "size", "modified", "kind"].includes(saved.sortBy)) root.sortBy = saved.sortBy
                root.descending = saved.descending === true
            } catch (e) {
            }
        }
    }

    function savePrefs(): void {
        prefs.setText(JSON.stringify({ view: view, showHidden: showHidden, sortBy: sortBy, descending: descending }) + "\n")
    }

    // The same column again: the other way around. A new one starts with what
    // you usually want first: A to Z, the biggest and the newest.
    function sortOn(column: string): void {
        if (sortBy === column) {
            descending = !descending
        } else {
            sortBy = column
            descending = column === "size" || column === "modified"
        }
        savePrefs()
    }

    // --- Windows ---

    // Copy, paste, rename and the Trash, for every window (one clipboard).
    FileOps {
        id: fileOps
        // A copy that outlived its window: now that it's done, Files goes.
        onBusyChanged: root.quitIfIdle()
    }

    // The USB drives for the sidebars (the same service as the shell's).
    DrivesService {
        id: fileDrives
    }

    // The favorite folders on the left (GTK's bookmarks), for every window.
    Bookmarks {
        id: fileBookmarks
    }

    // The Recent place (recently-used.xbel), for every window. Checked again
    // after an operation: a file moved or sent to the Trash leaves it.
    Recents {
        id: fileRecents
    }

    Connections {
        target: fileOps
        function onFinished() { if (fileRecents.loaded) fileRecents.check() }
        function onFailed() { if (fileRecents.loaded) fileRecents.check() }
    }

    property var windows: []
    // The one that last had the focus: the IPC acts on it.
    property var lastWindow: null

    // The clock's hours, in 24 h or 12 h like the bar's (bar.clockFormat).
    readonly property string timeFormat: /ap/i.test(settings.clockFormat) ? "h:mm AP" : "hh:mm"

    Component {
        id: windowComponent

        FilesWindow {
            id: window
            theme: filesTheme
            ops: fileOps
            drives: fileDrives
            bookmarks: fileBookmarks
            recents: fileRecents
            view: root.view
            showHidden: root.showHidden
            sortBy: root.sortBy
            descending: root.descending
            timeFormat: root.timeFormat
            onViewPicked: (view) => {
                root.view = view
                root.savePrefs()
            }
            onHiddenToggled: {
                root.showHidden = !root.showHidden
                root.savePrefs()
            }
            onSortPicked: (column) => root.sortOn(column)
            onNewWindowRequested: (folder) => root.openWindow(folder)
            onCloseRequested: root.closeWindow(window)
            // Closed from niri (Mod+Q, the overview).
            onClosed: root.closeWindow(window)
            onFocused: root.lastWindow = window
        }
    }

    function openWindow(path: string): void {
        const window = windowComponent.createObject(root, { startPath: path || home })
        windows = windows.concat([window])
        lastWindow = window
    }

    function closeWindow(window: var): void {
        if (!windows.includes(window)) return
        windows = windows.filter(w => w !== window)
        if (lastWindow === window) lastWindow = windows.length ? windows[windows.length - 1] : null
        window.destroy()
        quitIfIdle()
    }

    // With no windows the process goes away, and its memory with it: not
    // while a copy is still running (it finishes first), nor in a hot reload
    // (dev mode), which also closes them all.
    function quitIfIdle(): void {
        if (windows.length === 0 && !fileOps.busy && !reloading) Qt.quit()
    }

    property bool reloading: false
    Component.onDestruction: reloading = true

    // spore-files passes the folder (or file) it was asked for.
    Component.onCompleted: openWindow(Quickshell.env("SPORE_FILES_OPEN") || "")

    // spore-files <folder>, with Files already open: another window.
    // The rest is for the automated test (tools/test.sh) and scripts: it acts
    // on the window that last had the focus.
    IpcHandler {
        target: "files"

        function open(path: string): void {
            root.openWindow(path)
        }
        function go(path: string): void {
            if (root.lastWindow) root.lastWindow.navigate(path, "go")
        }
        function back(): void {
            if (root.lastWindow) root.lastWindow.back()
        }
        function forward(): void {
            if (root.lastWindow) root.lastWindow.forward()
        }
        function up(): void {
            if (root.lastWindow) root.lastWindow.up()
        }
        function setView(view: string): void {
            if (view === "grid" || view === "list") {
                root.view = view
                root.savePrefs()
            }
        }
        function toggleHidden(): void {
            root.showHidden = !root.showHidden
            root.savePrefs()
        }
        function filter(text: string): void {
            if (root.lastWindow) root.lastWindow.setFilter(text)
        }
        function close(): void {
            if (root.lastWindow) root.closeWindow(root.lastWindow)
        }
        // Space: the quick view of the selected file (select the file first).
        function select(name: string): void {
            if (root.lastWindow) root.lastWindow.selectName(name)
        }
        // Enter: the selected file opens with its app (a folder, right here).
        function activate(): void {
            if (root.lastWindow) root.lastWindow.activate(root.lastWindow.currentRow)
        }
        // A PDF in the quick view: the page after (1) or before (-1).
        function turnPage(delta: int): void {
            if (root.lastWindow) root.lastWindow.turnPage(delta)
        }
        function quickView(): void {
            if (root.lastWindow) root.lastWindow.toggleQuickView()
        }
        // What the keys do: Ctrl+click, Ctrl+A, Ctrl+C, Ctrl+X, Ctrl+V, F2
        // (with the new name), Ctrl+Shift+N, Delete, and the answer to a paste
        // that asks (keep, replace, skip or cancel).
        function toggle(name: string): void {
            if (root.lastWindow) root.lastWindow.toggleName(name)
        }
        function selectAll(): void {
            if (root.lastWindow) root.lastWindow.selectAll()
        }
        function copy(): void {
            if (root.lastWindow) root.lastWindow.copySelection()
        }
        function cut(): void {
            if (root.lastWindow) root.lastWindow.cutSelection()
        }
        function paste(): void {
            if (root.lastWindow) root.lastWindow.paste()
        }
        function rename(name: string): void {
            const w = root.lastWindow
            if (!w || !w.current) return
            w.renaming = w.current.name
            w.renameTo(name)
        }
        function newFolder(): void {
            if (root.lastWindow) root.lastWindow.newFolder()
        }
        function trash(): void {
            if (root.lastWindow) root.lastWindow.trashSelection()
        }
        // The archives selected, each into a folder; the selection into a zip.
        function extract(): void {
            if (root.lastWindow) root.lastWindow.extractSelection()
        }
        function compress(): void {
            if (root.lastWindow) root.lastWindow.compressSelection()
        }
        // The selection dropped on a folder (or "trash"), as a drag would: mode
        // auto (moves within a disk, copies to another), copy or move.
        // A folder added to the favorites on the left, or taken away.
        function addFavorite(path: string): void {
            fileBookmarks.add(path)
        }
        function removeFavorite(path: string): void {
            fileBookmarks.remove(path)
        }
        function drop(target: string, mode: string): void {
            const w = root.lastWindow
            if (!w) return
            const modifiers = mode === "copy" ? Qt.ControlModifier : mode === "move" ? Qt.ShiftModifier : 0
            w.dropOn(w.selectedPaths(), target === "trash" ? "" : target, target === "trash", modifiers, true)
        }
        // A question the window asks (deleting for good: delete or cancel), or
        // else a paste's.
        function answer(choice: string): void {
            if (root.lastWindow && root.lastWindow.confirmation) root.lastWindow.confirmed(choice)
            else fileOps.answer(choice)
        }
        // The Trash: restore what's selected, delete it for good or empty it
        // (these two ask first), and the paths to the clipboard.
        function restore(): void {
            if (root.lastWindow) root.lastWindow.restoreSelection()
        }
        function purge(): void {
            if (root.lastWindow) root.lastWindow.askToPurge()
        }
        function emptyTrash(): void {
            if (root.lastWindow) root.lastWindow.askToEmpty()
        }
        function copyPath(): void {
            if (root.lastWindow) root.lastWindow.copyPaths()
        }
        // A terminal in the open folder.
        function terminal(): void {
            if (root.lastWindow) root.lastWindow.openTerminal(root.lastWindow.folder)
        }
        // Stops a copy or a move under way.
        function cancel(): void {
            fileOps.cancel()
        }
        // { windows, folder, count, total, thumbnails, view, showHidden,
        // selected, names, preview, playing, selectedCount, renaming, busy,
        // progress, question, message, inTrash, clipboard }. thumbnails: how
        // many files have one; names: the first 50 shown, in order; preview:
        // what the quick view shows, "" if it's closed; playing: its video or
        // song plays; progress: a copy's percent (-100: unknown); question:
        // what the window or a paste asks; message: the error or note in the
        // status line; clipboard: "copy 2", "move 1" or "".
        function state(): string {
            const w = root.lastWindow
            return JSON.stringify({
                windows: root.windows.length,
                folder: w ? w.folder : "",
                count: w ? w.itemCount : 0,
                total: w ? w.totalCount : 0,
                thumbnails: w ? w.thumbnailCount : 0,
                view: root.view,
                showHidden: root.showHidden,
                selected: w && w.current ? w.current.name : "",
                names: w ? w.names(50) : [],
                preview: w && w.quickView ? w.previewKind || "loading" : "",
                playing: w ? w.previewPlaying : false,
                page: w ? w.previewPage : "",
                listing: w ? w.previewListing : "",
                selectedCount: w ? w.selectedCount : 0,
                renaming: w ? w.renaming : "",
                busy: fileOps.busy,
                progress: Math.round(fileOps.progress * 100),
                question: w && w.confirmation ? w.confirmation.text : fileOps.question ? fileOps.question.text : "",
                message: w ? w.message : "",
                inTrash: w ? w.inTrash : false,
                favorites: fileBookmarks.folders.map(b => b.path),
                clipboard: fileOps.clipboard ? fileOps.clipboard.mode + " " + fileOps.clipboard.paths.length : ""
            })
        }
    }
}
