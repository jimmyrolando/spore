import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "../services"
import "fileutil.js" as Util
import "../common/session.js" as Session

// A Files window: the places on the left; on top back, forward and up, the
// path, the filter and the view; the open folder; and a status line with
// what's selected and the free space. A regular window: niri tiles it like
// any app's. files.qml creates it and keeps what every window shares (the
// view, the hidden files and the order).
//
// Keyboard: arrows move (with Shift they select along), Enter opens, Space
// shows it big (the quick view), Backspace or Alt+Up goes up a folder,
// Alt+Left / Alt+Right go back and forward, typing filters the folder (Esc
// clears it), Ctrl+A selects everything, Ctrl+C / Ctrl+X / Ctrl+V copy, cut
// and paste, F2 renames, Delete moves to the Trash, Ctrl+Shift+N makes a
// folder, Ctrl+L types a path, Ctrl+H shows the hidden files, Ctrl+1 /
// Ctrl+2 switch between grid and list, Ctrl+N opens another window and
// Ctrl+W closes this one.
FloatingWindow {
    id: root

    required property Theme theme
    // Copy, paste, rename, the Trash (FileOps.qml, one for every window).
    required property FileOps ops
    // The USB drives (the shell's DrivesService, one for every window).
    required property DrivesService drives
    // The favorite folders on the left (Bookmarks.qml, one for every window).
    required property Bookmarks bookmarks
    // The Recent place's list, the same for every window.
    required property Recents recents
    // Shared by every window (files.qml remembers them).
    property string view: "grid"
    property bool showHidden: false
    property string sortBy: "name"
    property bool descending: false
    // The bar clock's hours: "hh:mm" or "h:mm AP".
    property string timeFormat: "hh:mm"
    // What it opens on: a folder, or a file (its folder, with it selected).
    property string startPath: ""

    signal viewPicked(string view)
    signal hiddenToggled()
    signal sortPicked(string column)
    signal newWindowRequested(string folder)
    signal closeRequested()
    // It got the focus: the IPC acts on the last one that did.
    signal focused()

    readonly property string home: Quickshell.env("HOME")
    property string folder: ""
    property var backStack: []
    property var forwardStack: []
    // Free space on the open folder's disk (-1 = unknown).
    property real freeBytes: -1
    // An error, for a few seconds, in the status line.
    property string message: ""

    // --- Selection ---

    // What's selected (name -> true) and the current entry: where the keyboard
    // is, what the quick view shows. Shift selects from the anchor (where the
    // last plain click or arrow left it) to here. All by name, not by row, so
    // they stay on the same files when others appear or go, when the order or
    // the filter change, when the hidden ones show. A folder opens with the
    // file it was asked for selected, or the folder you come up from.
    property var selection: ({})
    property string selectedName: ""
    property string anchorName: ""
    readonly property int selectedCount: Object.keys(selection).length
    // The current entry's row in the view (-1 = none, or filtered out). Only
    // the window moves the selection (clicks, arrows, a folder that loads) and
    // the views show it: left to themselves, they select the first entry of
    // every folder that loads, so their own changes are undone unless the
    // window is steering.
    property int currentRow: -1
    property bool steering: false
    readonly property var current: {
        folders.count
        return currentRow >= 0 ? folders.entry(currentRow) : null
    }

    function nameAt(row: int): string {
        const entry = folders.entry(row)
        return entry ? entry.name : ""
    }

    function pathOf(name: string): string {
        return folders.pathOf(name)
    }

    // Only the entry in `row` (-1: nothing): a click, the arrows.
    function select(row: int): void {
        selectNames(row >= 0 ? [nameAt(row)].filter(n => n) : [])
    }

    // These (the first is the current one): what a paste left, for example.
    function selectNames(names: var): void {
        const next = {}
        for (const name of names) next[name] = true
        selection = next
        selectedName = names.length ? names[0] : ""
        anchorName = selectedName
        syncRow()
    }

    // Ctrl+click: adds it or takes it away.
    function toggle(row: int): void {
        const name = nameAt(row)
        if (!name) return
        const next = Object.assign({}, selection)
        if (next[name]) delete next[name]
        else next[name] = true
        selection = next
        selectedName = name
        anchorName = name
        syncRow()
    }

    // Shift: from the anchor to `row`.
    function extend(row: int): void {
        const name = nameAt(row)
        const from = anchorName ? folders.rowOf(anchorName) : -1
        if (!name || from < 0) {
            select(row)
            return
        }
        const next = {}
        for (let r = Math.min(from, row); r <= Math.max(from, row); r++) next[nameAt(r)] = true
        selection = next
        selectedName = name
        syncRow()
    }

    function selectAll(): void {
        const next = {}
        for (let r = 0; r < folders.count; r++) next[nameAt(r)] = true
        selection = next
        if (!selectedName) selectedName = nameAt(0)
        syncRow()
    }

    // Clicks in the views, with their Ctrl or Shift.
    function picked(row: int, modifiers: int): void {
        if (modifiers & Qt.ControlModifier) toggle(row)
        else if (modifiers & Qt.ShiftModifier) extend(row)
        else select(row)
    }

    function selectedPaths(): var {
        return Object.keys(selection).map(pathOf)
    }

    function syncRow(): void {
        currentRow = selectedName ? folders.rowOf(selectedName) : -1
        renameIfListed()
    }

    onSelectedNameChanged: syncRow()

    // Files that left the folder (moved, in the Trash) leave the selection.
    Connections {
        target: folders
        function onPresentChanged() {
            const next = {}
            let gone = false
            for (const name in root.selection) {
                if (folders.present[name]) next[name] = true
                else gone = true
            }
            if (gone) root.selection = next
            root.selectIfListed()
        }
    }

    // What an operation made (a paste, a zip, an extracted folder), selected
    // once the listing shows it: selected before, the listing's next change
    // would take it away as gone.
    property var selectWhenListed: []

    function selectIfListed(): void {
        const listed = selectWhenListed.filter(name => folders.present[name])
        if (!listed.length) return
        selectWhenListed = []
        selectNames(listed)
    }

    Connections {
        target: folders.model
        function onRowsInserted() { root.syncRow() }
        function onRowsRemoved() { root.syncRow() }
        function onLayoutChanged() { root.syncRow() }
        function onModelReset() { root.syncRow() }
    }

    // The selection stays if it still shows; otherwise, while filtering, the
    // first match (Enter opens it).
    function filterChanged(text: string): void {
        folders.filterText = text
        if (selectedName && folders.rowOf(selectedName) >= 0) syncRow()
        else select(text && folders.count > 0 ? 0 : -1)
    }

    // For the IPC (files.qml): the entries shown (filtered) and in the
    // folder, the files with a thumbnail, the filter, and the first `max`
    // names shown, in order.
    readonly property int itemCount: folders.count
    readonly property int totalCount: folders.totalCount
    readonly property int thumbnailCount: Object.keys(thumbs.found).length

    function setFilter(text: string): void {
        filterField.text = text
    }

    function selectName(name: string): void {
        selectNames(name ? [name] : [])
    }

    function toggleName(name: string): void {
        toggle(folders.rowOf(name))
    }

    function toggleQuickView(): void {
        quickView = !quickView && current !== null
    }

    function names(max: int): var {
        const out = []
        for (let row = 0; row < Math.min(max, folders.count); row++) out.push(folders.entry(row).name)
        return out
    }

    title: (folder === home ? "Home" : folder === ops.trashFiles ? "Trash" : inRecent ? "Recent" : folder ? Util.baseName(folder) : "Files") + " — Files"

    // --- The Trash ---

    // In it (or in a folder inside it): what's here can be restored or deleted
    // for good, not renamed, cut or pasted into. Only what's at its top can be
    // restored (it has its record of where it came from).
    readonly property bool inTrash: folder === ops.trashFiles || folder.startsWith(ops.trashFiles + "/")
    // The Recent place: not a folder, so nothing is pasted, made, extracted,
    // zipped, renamed or dropped into it (what's in it can still be opened,
    // copied, cut, dragged out or sent to the Trash, from where it really is).
    readonly property bool inRecent: folder === Util.recentPath
    readonly property bool writable: !inTrash && !inRecent
    readonly property bool trashTop: folder === ops.trashFiles

    // Where the selected thing came from and when (its .trashinfo).
    FileView {
        id: trashInfo
        path: root.trashTop && root.current ? root.ops.trashDir + "/info/" + root.current.name + ".trashinfo" : ""
        blockLoading: true
        printErrors: false
    }
    readonly property string trashOrigin: {
        if (!trashTop || !current || !trashInfo.loaded) return ""
        const text = trashInfo.text()
        const path = (text.match(/^Path=(.*)$/m) || [])[1]
        const date = (text.match(/^DeletionDate=(.*)$/m) || [])[1]
        if (!path) return ""
        let where = Util.parentOf(path)
        try {
            where = decodeURIComponent(where)
        } catch (e) {
            // A badly encoded record: shown as it is.
        }
        if (where === home || where.startsWith(home + "/")) where = "~" + where.slice(home.length)
        return "From " + where + (date ? ", deleted " + Util.shortDate(new Date(date), timeFormat) : "")
    }

    // A question that deletes for good (the window's own, not a paste's):
    // { text, detail, action, names }.
    property var confirmation: null

    function askToPurge(): void {
        const names = Object.keys(selection)
        if (!names.length || !trashTop) return
        confirmation = {
            text: "Delete " + (names.length === 1 ? "“" + names[0] + "”" : items(names.length)) + " for good?",
            detail: "It can't be undone.",
            action: "purge",
            names: names
        }
    }

    function askToEmpty(): void {
        if (!trashTop || folders.totalCount === 0) return
        confirmation = {
            text: "Empty the Trash?",
            detail: "The " + items(folders.totalCount) + " in it will be deleted for good. It can't be undone.",
            action: "empty",
            names: []
        }
    }

    function confirmed(value: string): void {
        const asked = confirmation
        confirmation = null
        focusView()
        if (!asked || value !== "delete") return
        if (asked.action === "purge") ops.purge(root, asked.names)
        else if (asked.action === "empty") ops.emptyTrash(root)
    }

    function restoreSelection(): void {
        if (trashTop) ops.restore(root, Object.keys(selection))
    }

    // --- USB drives ---

    // A volume asked to mount: it opens when it gets its mountpoint.
    property string pendingVolume: ""
    // The disk whose mount or eject the status line reports.
    property string driveAsked: ""
    // The drive the open folder is on (its mountpoint), to leave it if it goes.
    property string onDrive: ""

    function mountOf(path: string): string {
        for (const drive of drives.drives) {
            for (const volume of drive.volumes) {
                const mount = volume.mountpoint
                if (mount && (path === mount || path.startsWith(mount + "/"))) return mount
            }
        }
        return ""
    }

    // Mounted: in. In fstab: into its folder (an automount mounts it then).
    // Otherwise udisks mounts it, and it opens once it has its mountpoint.
    function openVolume(device: var): void {
        if (device.mountpoint || device.target) {
            navigate(device.mountpoint || device.target, "go")
            return
        }
        pendingVolume = device.volume
        driveAsked = device.disk
        drives.mount(device.disk, device.volume)
    }

    // Out of it first: a folder open on it keeps it busy.
    function eject(disk: string): void {
        const drive = drives.drives.find(d => d.path === disk)
        const mounts = drive ? drive.volumes.map(v => v.mountpoint).filter(m => m) : []
        if (mounts.some(m => folder === m || folder.startsWith(m + "/"))) navigate(home, "go")
        driveAsked = disk
        drives.eject(disk)
    }

    Connections {
        target: root.drives
        function onDrivesChanged() {
            if (root.pendingVolume) {
                const volumes = root.drives.internal.concat(...root.drives.drives.map(d => d.volumes))
                const volume = volumes.find(v => v.path === root.pendingVolume)
                if (volume && volume.mountpoint) {
                    root.pendingVolume = ""
                    root.navigate(volume.mountpoint, "go")
                }
            }
            // The drive under the open folder went away (unplugged, ejected
            // elsewhere): home.
            if (root.onDrive && !root.mountOf(root.folder)) {
                root.onDrive = ""
                root.navigate(root.home, "go")
                root.flash("The drive isn't there anymore")
            }
        }
        function onMessagesChanged() {
            const text = root.drives.messages[root.driveAsked] || ""
            if (!text) return
            if (text === "Safe to remove") {
                root.flash("You can unplug " + (root.drives.lastEjected ? "“" + root.drives.lastEjected + "”" : "it") + " now", false)
            } else {
                root.pendingVolume = ""
                root.flash(text)
            }
            root.driveAsked = ""
        }
    }
    color: theme.base
    implicitWidth: 1020
    implicitHeight: 660
    minimumSize: Qt.size(560, 360)

    // Not "folderModel" or "thumbnails": inside the views, those names are
    // their own properties.
    FolderModel {
        id: folders
        folder: root.folder
        recents: root.recents
        showHidden: root.showHidden
        sortBy: root.sortBy
        descending: root.descending
    }

    Thumbnails {
        id: thumbs
        folderModel: folders
    }

    // --- Quick view (Space) ---

    // The selected file, big, in a panel above everything (QuickView.qml). The
    // keyboard stays here: the arrows keep moving the selection and the view
    // follows it. It closes with nothing selected and when this window loses
    // the focus (another app, the file opened with its app).
    property bool quickView: false
    readonly property string previewKind: quickViewLoader.item ? quickViewLoader.item.kind : ""
    readonly property bool previewPlaying: quickViewLoader.item ? quickViewLoader.item.mediaReady : false
    // A PDF's page in the quick view: "3/12" ("" for anything else).
    readonly property string previewPage: quickViewLoader.item && quickViewLoader.item.kind === "pdf"
        ? quickViewLoader.item.pdfPage + "/" + quickViewLoader.item.pdfPages : ""
    // An archive's in the quick view: what it holds ("" for anything else).
    readonly property string previewListing: quickViewLoader.item && quickViewLoader.item.kind === "archive"
        ? quickViewLoader.item.archiveSummary : ""

    function turnPage(delta: int): void {
        if (quickViewLoader.item) quickViewLoader.item.turn(delta)
    }

    // What the quick view shows: the current entry, kept while the listing is
    // remade (a file that appears empties the folder's rows for a moment,
    // which would close the view, or start its file over).
    property var previewEntry: current
    onCurrentChanged: {
        if (current) previewEntry = current
        else Qt.callLater(letGoOfPreview)
    }

    function letGoOfPreview(): void {
        if (current) return
        previewEntry = null
        quickView = false
    }

    LazyLoader {
        id: quickViewLoader
        active: root.quickView

        QuickView {
            id: preview
            theme: root.theme
            screen: root.screen
            entry: root.previewEntry
            // Of what it shows (the selection, once its file is ready).
            thumbnail: thumbs.thumbnailFor(preview.shownPath)
            timeFormat: root.timeFormat
            onOpenRequested: root.activate(root.currentRow)
            onCloseRequested: root.quickView = false
        }
    }

    Component.onCompleted: navigate(startPath || home, "go")

    // --- Navigation ---

    // Goes to `target` (relative to the open folder, if it isn't absolute)
    // once it's checked it exists and can be read. how: "go", "up", "back" or
    // "forward" (they move through the history differently). Asked for while
    // another check runs, it goes next (only the last one).
    function navigate(target: string, how: string): void {
        const request = { target: target, how: how }
        if (checker.busy) {
            checker.next = request
            return
        }
        // Not a folder: nothing to check.
        if (target === Util.recentPath) {
            arrived(["recent", target], how)
            return
        }
        checker.busy = true
        checker.request = request
        checker.command = ["sh", "-c", checkScript, "_", folder && !inRecent ? folder : home, target]
        checker.running = true
    }

    function back(): void {
        if (backStack.length) navigate(backStack[backStack.length - 1], "back")
    }
    function forward(): void {
        if (forwardStack.length) navigate(forwardStack[forwardStack.length - 1], "forward")
    }
    function up(): void {
        if (folder && folder !== "/" && !inRecent) navigate(Util.parentOf(folder), "up")
    }

    // Arguments: the open folder and the target. Prints "dir" and the folder,
    // "file", its folder and its name, or "denied"/"missing"; then the free
    // bytes on that disk. $PWD keeps the path as written (a link stays a link).
    readonly property string checkScript: `
        cd -- "$1" 2>/dev/null || cd
        if [ -d "$2" ]; then
            if cd -- "$2" 2>/dev/null && [ -r . ]; then
                printf 'dir\\n%s\\n' "$PWD"
            else
                printf 'denied\\n%s\\n' "$2"
            fi
        elif [ -e "$2" ]; then
            name=$(basename -- "$2")
            if cd -- "$(dirname -- "$2")" 2>/dev/null && [ -r . ]; then
                printf 'file\\n%s\\n%s\\n' "$PWD" "$name"
            else
                printf 'denied\\n%s\\n' "$2"
            fi
        else
            printf 'missing\\n%s\\n' "$2"
        fi
        df -P -B1 . 2>/dev/null | awk 'NR == 2 { print $4 }'`

    Process {
        id: checker
        // Busy from the start until its answer is read (not only while the
        // process runs: its output can arrive after it exits).
        property bool busy: false
        property var request: null
        property var next: null
        stdout: StdioCollector {
            onStreamFinished: {
                checker.busy = false
                root.arrived(text.split("\n"), checker.request.how)
                if (!checker.next) return
                const next = checker.next
                checker.next = null
                root.navigate(next.target, next.how)
            }
        }
    }

    function arrived(lines: var, how: string): void {
        const status = lines[0]
        if (status !== "dir" && status !== "file" && status !== "recent") {
            // A folder in the history that's gone: it leaves the history too.
            if (how === "back") backStack = backStack.slice(0, -1)
            if (how === "forward") forwardStack = forwardStack.slice(0, -1)
            flash(status === "denied" ? "You don't have permission to open “" + lines[1] + "”"
                : "“" + lines[1] + "” doesn't exist")
            if (!folder) navigate(home, "go")
            return
        }
        const path = lines[1]
        const previous = folder
        if (how === "back") {
            backStack = backStack.slice(0, -1)
            forwardStack = forwardStack.concat([previous])
        } else if (how === "forward") {
            forwardStack = forwardStack.slice(0, -1)
            backStack = backStack.concat([previous])
        } else if (previous && path !== previous) {
            backStack = backStack.concat([previous])
            forwardStack = []
        }
        freeBytes = status === "recent" ? -1 : Number(lines[status === "file" ? 3 : 2]) || -1
        message = ""
        renaming = ""
        selectWhenListed = []
        folder = path
        onDrive = status === "recent" ? "" : mountOf(path)
        filterField.text = ""
        // Found once the listing loads (or right away: a file in the open folder).
        const name = status === "file" ? lines[2] : how === "up" ? Util.baseName(previous) : ""
        selectNames(name ? [name] : [])
    }

    // Arrows: the view moves its current entry (in a grid, by rows and
    // columns) and the window takes it as the selection (with Shift, it
    // selects from the anchor to it). The first press selects the first entry.
    function move(key: int, along: bool): void {
        const view = viewLoader.item
        if (!view || folders.count === 0) return
        if (currentRow < 0) {
            select(0)
            return
        }
        steering = true
        view.currentIndex = currentRow
        if (root.view === "grid") {
            if (key === Qt.Key_Left) view.moveCurrentIndexLeft()
            else if (key === Qt.Key_Right) view.moveCurrentIndexRight()
            else if (key === Qt.Key_Up) view.moveCurrentIndexUp()
            else view.moveCurrentIndexDown()
        } else if (key === Qt.Key_Up) {
            view.decrementCurrentIndex()
        } else if (key === Qt.Key_Down) {
            view.incrementCurrentIndex()
        }
        steering = false
        if (along) extend(view.currentIndex)
        else select(view.currentIndex)
    }

    // --- Opening ---

    function activate(row: int): void {
        const entry = folders.entry(row)
        if (!entry) return
        quickView = false
        if (entry.isDir) navigate(entry.path, "go")
        else open(entry)
    }

    // With the app the system has for its kind (the same as a double click in
    // any file manager), which gets the session's environment, not this
    // process's (see session.js).
    function openCommand(path: string): var {
        return Session.command(["gio", "open", path])
    }

    function open(entry: var): void {
        // To the recent files (not one in the Trash).
        if (!inTrash) recents.record(entry.path)
        // Another one is still opening: this one goes on its own (without the
        // error message if it fails).
        if (opener.running) {
            Quickshell.execDetached(openCommand(entry.path))
            return
        }
        opener.name = entry.name
        opener.command = openCommand(entry.path)
        opener.running = true
    }

    Process {
        id: opener
        property string name: ""
        stderr: StdioCollector {
            id: openerErrors
        }
        onExited: (exitCode) => {
            if (exitCode === 0) return
            const noApp = /default application|No application/i.test(openerErrors.text)
            root.flash("Couldn't open “" + name + "”" + (noApp ? ": there's no app for this kind of file" : ""))
        }
    }

    // --- Copy, paste, rename, the Trash (the work is FileOps') ---

    // The entry being renamed in place ("" = none), and a new folder waiting
    // to show up to be renamed.
    property string renaming: ""
    property string renameWhenListed: ""

    function items(n: int): string {
        return n === 1 ? "1 item" : n + " items"
    }

    function copySelection(): void {
        const paths = selectedPaths()
        if (!paths.length) return
        ops.copy(paths)
        flash(items(paths.length) + " copied: Ctrl+V pastes " + (paths.length === 1 ? "it" : "them"), false)
    }

    function cutSelection(): void {
        const paths = selectedPaths()
        if (!paths.length || inTrash) return
        ops.cut(paths)
        flash(items(paths.length) + " cut: Ctrl+V moves " + (paths.length === 1 ? "it" : "them") + " where you paste", false)
    }

    // Not into the Trash (nor a folder inside it): only what gio trash puts there
    // has its record.
    function paste(): void {
        if (ops.clipboard && writable) ops.paste(root, folder)
    }

    function newFolder(): void {
        if (writable) ops.newFolder(root, folder)
    }

    function trashSelection(): void {
        if (!inTrash) ops.trash(root, selectedPaths())
    }

    // The archives selected, each into a folder here (FileOps.extract).
    function extractSelection(): void {
        if (writable) ops.extract(root, selectedPaths())
    }

    // The selection into a zip here, named after it (a file without its
    // extension), or Archive.zip for several.
    // Several items, or one that isn't compressed already: a zip alone zipped
    // again gains nothing, and its "x (2).zip" looks like a copy of it.
    function canCompress(names: var): bool {
        if (names.length !== 1) return names.length > 1
        const entry = folders.entry(folders.rowOf(names[0]))
        return entry !== null && (entry.isDir || !Util.compressed(entry.name))
    }

    function compressSelection(): void {
        const names = Object.keys(selection)
        if (!canCompress(names) || !writable) return
        const only = names.length === 1 ? folders.entry(folders.rowOf(names[0])) : null
        const name = only ? (only.isDir ? only.name : Util.stem(only.name)) : "Archive"
        ops.compress(root, folder, names, name + ".zip")
    }

    function startRename(): void {
        if (current && writable) renaming = current.name
    }

    // From the field (Enter or a click elsewhere): an empty or unchanged name
    // changes nothing.
    function renameTo(name: string): void {
        const old = renaming
        renaming = ""
        focusView()
        name = name.trim()
        if (!old || !name || name === old) return
        if (name === "." || name === ".." || name.includes("/")) {
            flash("A name can't be “.” or “..” or have a “/”")
            return
        }
        ops.rename(root, pathOf(old), name)
    }

    function renameCanceled(): void {
        renaming = ""
        focusView()
    }

    Connections {
        target: root.ops
        function onFinished(origin, kind, folder, names) {
            if (origin !== root) return
            if (kind === "trash") {
                root.flash("Moved " + root.items(names.length) + " to the Trash", false)
                return
            }
            if (kind === "restore") {
                const where = names.length === 1 ? Util.parentOf(names[0]) : ""
                root.flash("Restored " + root.items(names.length) + (where ? " to “" + Util.baseName(where) + "”" : ""), false)
                return
            }
            if (kind === "purge" || kind === "empty") {
                root.flash(kind === "empty" ? "The Trash is empty" : "Deleted " + root.items(names.length) + " for good", false)
                return
            }
            // Dropped in another folder: they're not in sight, so it says where.
            if (folder !== root.folder) {
                if (kind === "copy" || kind === "move")
                    root.flash((kind === "move" ? "Moved " : "Copied ") + root.items(names.length) + " to “"
                        + (folder === "/" ? "/" : Util.baseName(folder)) + "”", false)
                return
            }
            root.selectWhenListed = names
            root.selectIfListed()
            // A new folder: its name is edited as soon as it shows.
            if (kind === "mkdir") {
                root.renameWhenListed = names[0]
                root.renameIfListed()
            }
        }
        function onFailed(origin, message) {
            if (origin === root) root.flash(message)
        }
    }

    function renameIfListed(): void {
        if (renameWhenListed && folders.rowOf(renameWhenListed) >= 0) {
            renaming = renameWhenListed
            renameWhenListed = ""
        }
    }

    // A question left open when the window closes: nothing is pasted.
    Component.onDestruction: if (ops.question && ops.question.origin === root) ops.answer("cancel")

    // --- Dragging files ---

    // Where every filesystem is mounted (/proc/self/mountinfo), read when a
    // drag starts or lands. A network share, a Flatpak app's files (FUSE) or
    // /tmp (tmpfs) are filesystems of their own, and lsblk only knows disks:
    // taken for "/", files dropped from them were moved (copied, then deleted
    // there) instead of copied.
    property var mountPoints: ["/"]

    FileView {
        id: mountInfo
        path: "/proc/self/mountinfo"
        blockLoading: true
        printErrors: false
    }

    function readMounts(): void {
        mountInfo.reload()
        // The fifth field, with a space and the like written as \040.
        mountPoints = mountInfo.text().split("\n").map(line => line.split(" ")[4]).filter(m => m)
            .map(m => m.replace(/\\([0-7]{3})/g, (_, octal) => String.fromCharCode(parseInt(octal, 8))))
    }

    // The filesystem a path is on: the longest mount point it's under.
    function volumeOf(path: string): string {
        let best = "/"
        for (const mount of mountPoints) {
            if (mount.length > best.length && (path === mount || path.startsWith(mount + "/"))) best = mount
        }
        return best
    }

    // Like Finder and Explorer: a drop moves within a disk and copies to
    // another one; Ctrl always copies, Shift always moves.
    function dropMode(paths: var, target: string, modifiers: int): string {
        if (modifiers & Qt.ControlModifier) return "copy"
        if (modifiers & Qt.ShiftModifier) return "move"
        return paths.length && volumeOf(target) === volumeOf(paths[0]) ? "move" : "copy"
    }

    // Where `paths` can go: not where they already are, not into themselves,
    // and nothing inside the Trash except through its place (trash).
    // fromHere: dragged from this window, where nothing leaves the Trash this
    // way either.
    function dropAllowed(paths: var, target: string, trash: bool, fromHere: bool): bool {
        if (!paths.length || fromHere && inTrash) return false
        if (trash) return true
        if (!target || target === Util.recentPath || paths.every(p => Util.parentOf(p) === target)) return false
        if (target === ops.trashFiles || target.startsWith(ops.trashFiles + "/")) return false
        return !paths.some(p => target === p || target.startsWith(p + "/"))
    }

    // Lets go of `paths` on a folder, or on the Trash. From another app,
    // Ctrl and Shift aren't known (the keyboard is that app's while dragging).
    function dropOn(paths: var, target: string, trash: bool, modifiers: int, fromHere: bool): void {
        if (!dropAllowed(paths, target, trash, fromHere)) return
        if (trash) {
            ops.trash(root, paths)
            return
        }
        readMounts()
        ops.transfer(root, dropMode(paths, target, modifiers), paths, target, false)
    }

    // Files dragged from another app (Thunar, a browser…): their paths, or
    // none if any of them isn't a local file (a web link, say).
    function localPaths(urls: var): var {
        const paths = []
        for (const url of urls) {
            const text = String(url)
            if (!text.startsWith("file:///")) return []
            try {
                paths.push(decodeURIComponent(text.slice(7)))
            } catch (e) {
                return []
            }
        }
        return paths
    }

    // From the views (EntryArea): a drag starts on an entry, taking the
    // selection if the entry is in it (otherwise only the entry), follows the
    // pointer, and lets go on the DropTarget under it.
    function dragStart(row: int, at: point, modifiers: int): void {
        const name = nameAt(row)
        if (!name || inTrash || renaming) return
        if (!selection[name]) select(row)
        // What the ghost says (move or copy) comes from where things are mounted.
        readMounts()
        ghost.modifiers = modifiers
        ghost.handedOver = false
        ghost.place(at)
        ghost.paths = selectedPaths()
        // For another app, if it leaves the window: the files' list, and the
        // ghost as it looks now (over nothing yet) to go with the pointer.
        ghost.Drag.mimeData = {
            "text/uri-list": ghost.paths.map(p => Util.fileUri(p)).join("\r\n") + "\r\n",
            // So the targets here know it when it comes back.
            "application/x-spore-files": "1"
        }
        ghost.grabToImage(result => ghost.Drag.imageSource = result.url)
    }

    function dragMove(at: point, modifiers: int): void {
        if (!ghost.Drag.active || ghost.handedOver) return
        ghost.modifiers = modifiers
        if (at.x < 0 || at.y < 0 || at.x >= width || at.y >= height) handOver()
        else ghost.place(at)
    }

    // Out of the window, the system's drag takes over, carrying the files'
    // list: another app (Firefox, a chat, Thunar) takes them as a copy, and
    // the files here stay as they are. Back over Files, it drops as usual.
    function handOver(): void {
        ghost.handedOver = true
        // Off every target here, so none stays lit.
        ghost.place(Qt.point(-10000, -10000))
        // Not from inside the pointer's event: startDrag runs until the drop.
        Qt.callLater(() => {
            if (ghost.Drag.active) ghost.Drag.startDrag(Qt.CopyAction)
            ghost.paths = []
            ghost.handedOver = false
        })
    }

    // Qt tells the DropTargets about the ghost's last move on the next turn of
    // the event loop: the drop waits for it, or a quick release would land on
    // the target before.
    function dragEnd(modifiers: int): void {
        if (!ghost.Drag.active || ghost.handedOver) return
        ghost.modifiers = modifiers
        Qt.callLater(dragDrop)
    }

    function dragDrop(): void {
        if (!ghost.Drag.active || ghost.handedOver) return
        const over = ghost.over
        const paths = ghost.paths
        ghost.paths = []
        if (over) dropOn(paths, over.path, over.trash, ghost.modifiers, true)
    }

    // (Handed over, the system's drag ends it.)
    function dragCancel(): void {
        if (!ghost.handedOver) ghost.paths = []
    }

    // Esc lets go of a drag without dropping it anywhere.
    Shortcut {
        sequence: "Escape"
        enabled: ghost.Drag.active
        onActivated: root.dragCancel()
    }

    // --- The right button's menu ---

    // The folder the menu's "Add to sidebar" or "Remove from sidebar" is for.
    property string menuFolder: ""

    // "Add to sidebar" or "Remove from sidebar" for `path` (not for the
    // places that are always there).
    function favoriteItem(path: string): var {
        if (!path || sidebar.isPlace(path)) return null
        menuFolder = path
        return bookmarks.has(path) ? { action: "unfavorite", label: "Remove from sidebar" }
            : { action: "favorite", label: "Add to sidebar" }
    }

    // The right button on a favorite on the left.
    function openFavoriteMenu(path: string, x: real, y: real): void {
        menuFolder = path
        contextMenu.open(x, y, [
            { action: "openfavorite", label: "Open" },
            { action: "unfavorite", label: "Remove from sidebar" }
        ])
    }

    function openMenu(row: int, x: real, y: real): void {
        // On something that isn't selected: that one is selected first.
        if (row >= 0 && !selection[nameAt(row)]) select(row)
        const pasteItem = { action: "paste", label: "Paste", keys: "Ctrl+V", enabled: ops.clipboard !== null }
        const one = selectedCount === 1
        const folderSelected = one && current !== null && current.isDir
        if (row >= 0 && inTrash) {
            contextMenu.open(x, y, [
                { action: "quickview", label: "Quick view", keys: "Space" },
                { action: "copy", label: "Copy", keys: "Ctrl+C" },
                "-",
                { action: "restore", label: "Restore", enabled: trashTop },
                { action: "purge", label: "Delete for good", keys: "Delete", enabled: trashTop }
            ])
        } else if (row >= 0 && inRecent) {
            contextMenu.open(x, y, [
                { action: "open", label: "Open", keys: "Enter" },
                { action: "openwith", label: "Open with…", enabled: one && !folderSelected },
                { action: "quickview", label: "Quick view", keys: "Space" },
                { action: "reveal", label: "Show in its folder", enabled: one },
                "-",
                { action: "cut", label: "Cut", keys: "Ctrl+X" },
                { action: "copy", label: "Copy", keys: "Ctrl+C" },
                { action: "copypath", label: selectedCount > 1 ? "Copy paths" : "Copy path", keys: "Ctrl+Shift+C" },
                "-",
                { action: "trash", label: "Move to Trash", keys: "Delete" }
            ])
        } else if (inRecent) {
            select(-1)
        } else if (row >= 0) {
            const favorite = folderSelected ? favoriteItem(current.path) : null
            const archives = Object.keys(selection).some(name => Util.extractable(name))
            contextMenu.open(x, y, [
                { action: "open", label: "Open", keys: "Enter" },
                { action: "openwith", label: "Open with…", enabled: one && !folderSelected },
                { action: "quickview", label: "Quick view", keys: "Space" },
                "-",
                { action: "cut", label: "Cut", keys: "Ctrl+X" },
                { action: "copy", label: "Copy", keys: "Ctrl+C" },
                pasteItem,
                { action: "copypath", label: selectedCount > 1 ? "Copy paths" : "Copy path", keys: "Ctrl+Shift+C" },
                "-",
                { action: "rename", label: "Rename", keys: "F2", enabled: one },
                { action: "trash", label: "Move to Trash", keys: "Delete" },
                "-"
            ].concat(archives ? [{ action: "extract", label: "Extract here" }] : [],
                canCompress(Object.keys(selection))
                    ? [{ action: "compress", label: one ? "Compress “" + Object.keys(selection)[0] + "”" : "Compress " + selectedCount + " items" }] : [], [
                "-",
                { action: "terminal", label: "Open terminal here", enabled: folderSelected }
            ], favorite ? [favorite] : []))
        } else if (inTrash) {
            select(-1)
            contextMenu.open(x, y, [
                { action: "empty", label: "Empty Trash", enabled: trashTop && folders.totalCount > 0 }
            ])
        } else {
            select(-1)
            // The open folder's own.
            const favorite = favoriteItem(folder)
            contextMenu.open(x, y, [
                { action: "newfolder", label: "New folder", keys: "Ctrl+Shift+N" },
                pasteItem,
                "-",
                { action: "terminal", label: "Open terminal here" },
                { action: "copypath", label: "Copy path", keys: "Ctrl+Shift+C" }
            ].concat(favorite ? [favorite] : [], [
                "-",
                { action: "hidden", label: showHidden ? "Hide hidden files" : "Show hidden files", keys: "Ctrl+H" }
            ]))
        }
    }

    function menuAction(action: string): void {
        focusView()
        if (action === "open") activate(currentRow)
        else if (action === "openwith") openWithEntry = current
        else if (action === "quickview") quickView = current !== null
        else if (action === "reveal") reveal()
        else if (action === "cut") cutSelection()
        else if (action === "copy") copySelection()
        else if (action === "paste") paste()
        else if (action === "copypath") copyPaths()
        else if (action === "rename") startRename()
        else if (action === "trash") trashSelection()
        else if (action === "newfolder") newFolder()
        else if (action === "terminal") openTerminal(current && current.isDir && selectedCount === 1 ? current.path : folder)
        else if (action === "hidden") hiddenToggled()
        else if (action === "restore") restoreSelection()
        else if (action === "purge") askToPurge()
        else if (action === "empty") askToEmpty()
        else if (action === "extract") extractSelection()
        else if (action === "compress") compressSelection()
        else if (action === "favorite") bookmarks.add(menuFolder)
        else if (action === "unfavorite") bookmarks.remove(menuFolder)
        else if (action === "openfavorite") navigate(menuFolder, "go")
    }

    // --- Open with…, a terminal, the path ---

    // The file "Open with…" is choosing an app for (null: closed).
    property var openWithEntry: null

    // $1 the app's desktop id, $2 the file, $3 "always" to make it the
    // default for $4 (the file's type) first. The app's desktop file is looked
    // for where launchers look (XDG_DATA_HOME, XDG_DATA_DIRS). After
    // session.js's appScript, for `app`.
    readonly property string openWithScript: `
        if [ "$3" = always ]; then
            gio mime "$4" "$1" >/dev/null || echo "NODEFAULT"
        fi
        IFS=:
        for dir in \${XDG_DATA_HOME:-$HOME/.local/share} \${XDG_DATA_DIRS:-/usr/local/share:/usr/share}; do
            if [ -f "$dir/applications/$1" ]; then
                app gio launch "$dir/applications/$1" "$2"
                exit
            fi
        done
        exit 3`

    // A recent file's folder, with it selected.
    function reveal(): void {
        if (current) navigate(current.path, "go")
    }

    function openWith(desktopId: string, always: bool, mimeType: string): void {
        const entry = openWithEntry
        openWithEntry = null
        focusView()
        if (!entry) return
        if (!inTrash) recents.record(entry.path)
        launcher.what = "“" + entry.name + "”"
        launcher.command = ["sh", "-c", Session.appScript + openWithScript, "_", desktopId, entry.path, always ? "always" : "", mimeType]
        launcher.running = true
    }

    // $1 the folder: the first terminal there is ($TERMINAL, or a known one),
    // started in it and on its own (it outlives Files). After session.js's
    // appScript, for `app`.
    readonly property string terminalScript: `
        cd -- "$1" || exit 1
        for t in \${TERMINAL:-} kitty foot alacritty wezterm ghostty konsole gnome-terminal kgx xfce4-terminal xterm; do
            if command -v "$t" >/dev/null 2>&1; then
                app setsid -f "$t" >/dev/null 2>&1
                exit
            fi
        done
        exit 3`

    function openTerminal(dir: string): void {
        if (dir === Util.recentPath) return
        launcher.what = "a terminal"
        launcher.command = ["sh", "-c", Session.appScript + terminalScript, "_", dir]
        launcher.running = true
    }

    Process {
        id: launcher
        property string what: ""
        stdout: StdioCollector {
            id: launcherOutput
        }
        onExited: (exitCode) => {
            if (launcherOutput.text.includes("NODEFAULT")) root.flash("Couldn't make it the default app")
            if (exitCode === 3) root.flash(what === "a terminal" ? "No terminal found (set TERMINAL, or install kitty or foot)" : "Couldn't find that app")
            else if (exitCode !== 0) root.flash("Couldn't open " + what)
        }
    }

    // The selected paths (or the folder's), one per line, to the clipboard.
    function copyPaths(): void {
        const paths = selectedCount ? selectedPaths() : inRecent ? [] : [folder]
        if (!paths.length) return
        Quickshell.execDetached(["wl-copy", "--", paths.join("\n")])
        flash(paths.length === 1 ? "Path copied" : paths.length + " paths copied", false)
    }

    // An error (red) or a note, for a few seconds, in the status line.
    property bool messageIsError: true

    function flash(text: string, error: var): void {
        message = text
        messageIsError = error !== false
        messageTimer.restart()
    }

    Timer {
        id: messageTimer
        interval: 5000
        onTriggered: root.message = ""
    }

    // --- Keyboard ---

    function focusView(): void {
        if (viewLoader.item) viewLoader.item.forceActiveFocus()
    }

    // The views' keys (they don't move by themselves: the window does).
    function viewKey(event: var): void {
        const key = event.key
        const ctrl = (event.modifiers & Qt.ControlModifier) !== 0
        const shift = (event.modifiers & Qt.ShiftModifier) !== 0
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        const arrow = key === Qt.Key_Left || key === Qt.Key_Right || key === Qt.Key_Up || key === Qt.Key_Down
        if (key === Qt.Key_Return || key === Qt.Key_Enter) {
            activate(currentRow)
        } else if (previewPage && (key === Qt.Key_PageDown || key === Qt.Key_PageUp || ctrl && arrow)) {
            // A PDF in the quick view: Page Down or Ctrl+Down/Right turn to
            // its next page, Page Up or Ctrl+Up/Left to the one before
            // (Ctrl and the arrows for keyboards without the page keys).
            turnPage(key === Qt.Key_PageDown || key === Qt.Key_Down || key === Qt.Key_Right ? 1 : -1)
        } else if (arrow) {
            move(key, shift)
        } else if (ctrl && key === Qt.Key_A) {
            selectAll()
        } else if (ctrl && shift && key === Qt.Key_C) {
            copyPaths()
        } else if (ctrl && key === Qt.Key_C) {
            copySelection()
        } else if (ctrl && key === Qt.Key_X) {
            if (!inTrash) cutSelection()
        } else if (ctrl && key === Qt.Key_V) {
            if (!inTrash) paste()
        } else if (ctrl && shift && key === Qt.Key_N) {
            if (!inTrash) newFolder()
        } else if (key === Qt.Key_Menu || (shift && key === Qt.Key_F10)) {
            // The menu from the keyboard: at the current entry (or the folder's).
            const view = viewLoader.item
            const item = currentRow >= 0 && view ? view.itemAtIndex(currentRow) : null
            const point = item ? item.mapToItem(null, item.width / 2, item.height / 2) : Qt.point(width / 2, height / 3)
            openMenu(item ? currentRow : -1, point.x, point.y)
        } else if (key === Qt.Key_F2) {
            if (!inTrash) startRename()
        } else if (key === Qt.Key_Delete) {
            // In the Trash, Delete deletes for good (it asks first).
            if (inTrash) askToPurge()
            else trashSelection()
        } else if (key === Qt.Key_Backspace && plain) {
            up()
        } else if (key === Qt.Key_Home) {
            select(0)
        } else if (key === Qt.Key_End) {
            select(folders.count - 1)
        } else if (key === Qt.Key_Escape) {
            if (quickView) quickView = false
            else if (filterField.text) filterField.text = ""
            else select(-1)
        } else if (key === Qt.Key_Space) {
            quickView = !quickView && current !== null
        } else if (key === Qt.Key_Tab || key === Qt.Key_Backtab || key === Qt.Key_F6) {
            // To the places on the left (Esc or Tab there come back).
            sidebar.enter()
        } else if (plain && event.text.length === 1 && event.text > " ") {
            // Typing filters: the letter goes to the filter field.
            filterField.text += event.text
            filterField.forceActiveFocus()
        } else {
            return
        }
        event.accepted = true
    }

    Shortcut {
        sequence: "Ctrl+L"
        onActivated: pathBar.edit()
    }
    Shortcut {
        sequence: "Ctrl+F"
        onActivated: filterField.forceActiveFocus()
    }
    Shortcut {
        sequence: "Ctrl+H"
        onActivated: root.hiddenToggled()
    }
    Shortcut {
        sequence: "Ctrl+1"
        onActivated: root.viewPicked("grid")
    }
    Shortcut {
        sequence: "Ctrl+2"
        onActivated: root.viewPicked("list")
    }
    Shortcut {
        sequence: "Ctrl+N"
        onActivated: root.newWindowRequested(root.folder)
    }
    Shortcut {
        sequence: "Ctrl+W"
        onActivated: root.closeRequested()
    }
    Shortcut {
        sequences: ["Alt+Left", "Back"]
        onActivated: root.back()
    }
    Shortcut {
        sequences: ["Alt+Right", "Forward"]
        onActivated: root.forward()
    }
    Shortcut {
        sequence: "Alt+Up"
        onActivated: root.up()
    }
    // To the Trash (like Finder's ⌘⇧ for its places), from anywhere in the window.
    Shortcut {
        sequence: "Ctrl+Shift+T"
        onActivated: {
            root.navigate(root.ops.trashFiles, "go")
            root.focusView()
        }
    }

    // --- Window ---

    readonly property color inputBg: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.6))
    readonly property color inputBorder: Qt.tint(theme.base, theme.alpha(theme.text, 0.15))

    FocusScope {
        id: content
        anchors.fill: parent
        focus: true

        readonly property bool windowActive: Window.active
        onWindowActiveChanged: {
            if (windowActive) root.focused()
            else root.quickView = false
        }

        // The mouse's back and forward buttons, anywhere in the window.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.BackButton | Qt.ForwardButton
            onClicked: (mouse) => mouse.button === Qt.BackButton ? root.back() : root.forward()
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 0

            // --- Toolbar ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 12
                Layout.rightMargin: 10
                Layout.topMargin: 9
                Layout.bottomMargin: 9
                spacing: 4

                CcButton {
                    theme: root.theme
                    size: 32
                    flat: true
                    icon: "arrow-left"
                    iconSize: 15
                    enabled: root.backStack.length > 0
                    onClicked: root.back()
                }
                CcButton {
                    theme: root.theme
                    size: 32
                    flat: true
                    icon: "arrow-right"
                    iconSize: 15
                    enabled: root.forwardStack.length > 0
                    onClicked: root.forward()
                }
                CcButton {
                    theme: root.theme
                    size: 32
                    flat: true
                    icon: "arrow-up"
                    iconSize: 15
                    enabled: root.folder !== "/" && !root.inRecent
                    onClicked: root.up()
                }

                PathBar {
                    id: pathBar
                    theme: root.theme
                    trashPath: root.ops.trashFiles
                    Layout.fillWidth: true
                    Layout.leftMargin: 6
                    Layout.rightMargin: 6
                    folder: root.folder
                    onNavigate: (path) => root.navigate(path, "go")
                    onDone: root.focusView()
                }

                // The filter: part of the name, as you type.
                Rectangle {
                    Layout.preferredWidth: 190
                    implicitHeight: 34
                    radius: 9
                    color: root.inputBg
                    border.width: 1
                    border.color: filterField.activeFocus ? root.theme.accent : root.inputBorder

                    Icon {
                        id: searchIcon
                        anchors.left: parent.left
                        anchors.leftMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        name: "search"
                        size: 14
                        color: root.theme.muted
                    }
                    TextInput {
                        id: filterField
                        anchors.left: searchIcon.right
                        anchors.right: clearFilter.left
                        anchors.leftMargin: 8
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        clip: true
                        color: root.theme.text
                        selectionColor: root.theme.accent
                        selectedTextColor: root.theme.textOnAccent
                        font.family: root.theme.uiFont
                        font.pixelSize: 13
                        onTextChanged: root.filterChanged(text)
                        Keys.onEscapePressed: {
                            text = ""
                            root.focusView()
                        }
                        Keys.onDownPressed: {
                            if (root.currentRow < 0) root.select(0)
                            root.focusView()
                        }
                        onAccepted: {
                            if (root.currentRow < 0) root.select(0)
                            root.focusView()
                        }

                        UiText {
                            theme: root.theme
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !filterField.text
                            text: "Filter"
                            color: root.theme.muted2
                        }
                    }
                    CcButton {
                        id: clearFilter
                        theme: root.theme
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        visible: filterField.text !== ""
                        width: visible ? 26 : 0
                        size: 26
                        flat: true
                        icon: "x"
                        iconSize: 12
                        onClicked: {
                            filterField.text = ""
                            root.focusView()
                        }
                    }
                }

                // Grid or list.
                Rectangle {
                    Layout.leftMargin: 6
                    implicitWidth: viewRow.implicitWidth + 6
                    implicitHeight: 34
                    radius: 10
                    color: root.theme.alpha(root.theme.accent, root.theme.isDark ? 0.14 : 0.09)

                    Row {
                        id: viewRow
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: [{ value: "grid", icon: "layout-grid" }, { value: "list", icon: "list" }]

                            Rectangle {
                                required property var modelData
                                readonly property bool selected: root.view === modelData.value
                                width: 34
                                height: 28
                                radius: 8
                                color: selected ? root.theme.cardBg : "transparent"

                                Icon {
                                    anchors.centerIn: parent
                                    name: parent.modelData.icon
                                    size: 15
                                    color: parent.selected ? root.theme.text : root.theme.muted
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.viewPicked(parent.modelData.value)
                                }
                            }
                        }
                    }
                }

                // Hidden files: highlighted while they show.
                CcButton {
                    theme: root.theme
                    size: 32
                    flat: !root.showHidden
                    icon: root.showHidden ? "eye" : "eye-off"
                    iconSize: 15
                    onClicked: root.hiddenToggled()
                }

                CcButton {
                    theme: root.theme
                    size: 32
                    flat: true
                    icon: "x"
                    iconSize: 15
                    onClicked: root.closeRequested()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.theme.alpha(root.theme.accent, 0.1)
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                Sidebar {
                    id: sidebar
                    theme: root.theme
                    drives: root.drives
                    bookmarks: root.bookmarks
                    Layout.fillHeight: true
                    folder: root.folder
                    trashPath: root.ops.trashFiles
                    onPlaceClicked: (path) => root.navigate(path, "go")
                    onVolumeClicked: (device) => root.openVolume(device)
                    onEjectClicked: (disk) => root.eject(disk)
                    onFavoriteMenuRequested: (path, x, y) => root.openFavoriteMenu(path, x, y)
                    onDone: root.focusView()
                }

                // --- The open folder ---
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    // A click on the empty part: nothing selected.
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            root.select(-1)
                            root.focusView()
                        }
                    }

                    // The open folder itself, under its entries: files brought
                    // from another app land here (its own files are here
                    // already, so a drag from this window never does).
                    DropTarget {
                        id: folderDrop
                        anchors.fill: parent
                        path: root.folder
                        label: root.folder === "/" ? "/" : Util.baseName(root.folder)

                        Rectangle {
                            anchors.fill: parent
                            anchors.margins: 4
                            // Where the entries start: under the list's column
                            // titles, not over them.
                            anchors.topMargin: viewLoader.y + (viewLoader.item && viewLoader.item.headerItem ? viewLoader.item.headerItem.height : 0)
                            radius: 12
                            visible: folderDrop.containsDrag
                            color: root.theme.alpha(root.theme.accent, 0.05)
                            border.width: 2
                            border.color: root.theme.accent
                        }
                    }

                    // In the Trash: what it is, and what can be done with it.
                    Rectangle {
                        id: trashBar
                        visible: root.inTrash
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 10
                        height: visible ? 52 : 0
                        radius: 12
                        color: root.theme.cardBg
                        border.width: 1
                        border.color: root.theme.cardBorder

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 10
                            spacing: 10

                            Icon {
                                name: "trash"
                                size: 18
                                color: root.theme.ink2
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1

                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: "Trash"
                                    font.weight: Font.DemiBold
                                }
                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: root.trashTop ? "Restore puts things back where they were."
                                        : "Inside something deleted: restore it from the Trash's top."
                                    color: root.theme.muted
                                    font.pixelSize: 11
                                }
                            }
                            CcButton {
                                theme: root.theme
                                size: 30
                                icon: "archive-restore"
                                label: "Restore"
                                enabled: root.trashTop && root.selectedCount > 0
                                onClicked: root.restoreSelection()
                            }
                            CcButton {
                                theme: root.theme
                                size: 30
                                danger: true
                                label: "Empty Trash"
                                enabled: root.trashTop && folders.totalCount > 0
                                onClicked: root.askToEmpty()
                            }
                        }
                    }

                    Loader {
                        id: viewLoader
                        anchors.fill: parent
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        anchors.topMargin: (root.view === "grid" ? 8 : 4) + (root.inTrash ? trashBar.height + 10 : 0)
                        focus: true
                        sourceComponent: root.view === "list" ? listComponent : gridComponent
                        onLoaded: {
                            item.currentIndex = root.currentRow
                            if (root.currentRow >= 0) item.positionViewAtIndex(root.currentRow, GridView.Contain)
                        }
                    }

                    Component {
                        id: gridComponent
                        FileGrid {
                            theme: root.theme
                            folderModel: folders
                            thumbnails: thumbs
                            windowActive: content.windowActive
                            selection: root.selection
                            cutPaths: root.ops.cutPaths
                            renaming: root.renaming
                            onActivated: (row) => root.activate(row)
                            onPicked: (row, modifiers) => root.picked(row, modifiers)
                            onMenuRequested: (row, x, y) => root.openMenu(row, x, y)
                            onRenamed: (name) => root.renameTo(name)
                            onRenameCanceled: root.renameCanceled()
                            onEntryDragStarted: (row, at, modifiers) => root.dragStart(row, at, modifiers)
                            onEntryDragMoved: (at, modifiers) => root.dragMove(at, modifiers)
                            onEntryDragEnded: (modifiers) => root.dragEnd(modifiers)
                            onEntryDragCanceled: root.dragCancel()
                            onCurrentIndexChanged: if (!root.steering && currentIndex !== root.currentRow) currentIndex = root.currentRow
                            Keys.onPressed: (event) => root.viewKey(event)
                        }
                    }

                    Component {
                        id: listComponent
                        FileList {
                            theme: root.theme
                            folderModel: folders
                            thumbnails: thumbs
                            windowActive: content.windowActive
                            timeFormat: root.timeFormat
                            onActivated: (row) => root.activate(row)
                            selection: root.selection
                            cutPaths: root.ops.cutPaths
                            renaming: root.renaming
                            onSortRequested: (column) => root.sortPicked(column)
                            onPicked: (row, modifiers) => root.picked(row, modifiers)
                            onMenuRequested: (row, x, y) => root.openMenu(row, x, y)
                            onRenamed: (name) => root.renameTo(name)
                            onRenameCanceled: root.renameCanceled()
                            onEntryDragStarted: (row, at, modifiers) => root.dragStart(row, at, modifiers)
                            onEntryDragMoved: (at, modifiers) => root.dragMove(at, modifiers)
                            onEntryDragEnded: (modifiers) => root.dragEnd(modifiers)
                            onEntryDragCanceled: root.dragCancel()
                            onCurrentIndexChanged: if (!root.steering && currentIndex !== root.currentRow) currentIndex = root.currentRow
                            Keys.onPressed: (event) => root.viewKey(event)
                        }
                    }

                    UiText {
                        theme: root.theme
                        anchors.centerIn: parent
                        visible: folders.ready && folders.count === 0
                        text: folders.filterText ? "Nothing here matches “" + folders.filterText + "”"
                            : root.inRecent ? "No recent files" : "This folder is empty"
                        color: root.theme.muted
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.theme.alpha(root.theme.accent, 0.1)
            }

            // --- Status line ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 16
                Layout.rightMargin: 12
                implicitHeight: 30
                spacing: 12

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.ops.status ? root.ops.status + (root.ops.progress >= 0 ? " — " + Math.round(root.ops.progress * 100) + " %" : "…")
                        : root.message || root.statusText
                    color: root.message && !root.ops.status && root.messageIsError ? root.theme.danger
                        : root.message && !root.ops.status ? root.theme.text : root.theme.muted
                    font.pixelSize: 12
                }
                // A copy or a move under way: how far it is, and a way to stop it.
                Rectangle {
                    visible: root.ops.progress >= 0
                    Layout.preferredWidth: 120
                    implicitHeight: 4
                    radius: 2
                    color: root.theme.track

                    Rectangle {
                        width: parent.width * Math.max(0, root.ops.progress)
                        height: parent.height
                        radius: 2
                        color: root.theme.accent
                    }
                }
                CcButton {
                    theme: root.theme
                    visible: root.ops.busy && root.ops.current && ["transfer", "extract", "compress"].includes(root.ops.current.kind)
                    size: 22
                    flat: true
                    label: "Cancel"
                    onClicked: root.ops.cancel()
                }
                MonoText {
                    theme: root.theme
                    visible: root.freeBytes >= 0 && !root.ops.status
                    text: Util.humanSize(root.freeBytes) + " free"
                    color: root.theme.muted2
                    font.pixelSize: 11
                }
            }
        }

        ContextMenu {
            id: contextMenu
            theme: root.theme
            anchors.fill: parent
            onPicked: (action) => root.menuAction(action)
            onClosed: root.focusView()
        }

        // A paste that finds names already there asks what to do (FileOps).
        AskDialog {
            theme: root.theme
            anchors.fill: parent
            visible: root.ops.question !== null && root.ops.question.origin === root
            text: visible ? root.ops.question.text : ""
            detail: "Keep both adds a number to the new ones; Replace moves the old ones to the Trash."
            buttons: [
                { value: "keep", label: "Keep both", primary: true },
                { value: "replace", label: "Replace", danger: true },
                { value: "skip", label: "Skip" },
                { value: "cancel", label: "Cancel" }
            ]
            onAnswered: (value) => {
                root.ops.answer(value)
                root.focusView()
            }
        }

        // Deleting for good (the Trash): Enter deletes, Esc cancels.
        AskDialog {
            theme: root.theme
            anchors.fill: parent
            visible: root.confirmation !== null
            text: visible ? root.confirmation.text : ""
            detail: visible ? root.confirmation.detail : ""
            buttons: [
                { value: "delete", label: root.confirmation && root.confirmation.action === "empty" ? "Empty Trash" : "Delete for good", danger: true },
                { value: "cancel", label: "Cancel" }
            ]
            acceptValue: "delete"
            cancelValue: "cancel"
            onAnswered: (value) => root.confirmed(value)
        }

        OpenWithDialog {
            theme: root.theme
            anchors.fill: parent
            entry: root.openWithEntry
            onChosen: (desktopId, always, mimeType) => root.openWith(desktopId, always, mimeType)
            onCanceled: {
                root.openWithEntry = null
                root.focusView()
            }
        }

        // What's being dragged, next to the pointer: how many, and what letting
        // go there does. The DropTarget under the pointer (a folder, a place on
        // the left, a piece of the path) says where, if it takes it (accepts).
        Rectangle {
            id: ghost
            // What's dragged (empty: no drag) and the Ctrl or Shift held.
            property var paths: []
            property int modifiers: 0
            // Out of the window, the system's drag has it (see handOver): it
            // hides, and the targets here take it through DropTarget.onDropped.
            property bool handedOver: false
            readonly property var over: Drag.target
            readonly property string what: paths.length === 1 ? "“" + Util.baseName(paths[0]) + "”" : paths.length + " items"
            readonly property string mode: over && !over.trash ? root.dropMode(paths, over.path, modifiers) : "move"

            function accepts(path: string, trash: bool): bool {
                return root.dropAllowed(paths, path, trash, true)
            }
            // Let go on a target here after leaving the window (the system's drag,
            // see DropTarget): the same as a drop that never left.
            function droppedOn(path: string, trash: bool): void {
                root.dropOn(paths, path, trash, modifiers, true)
            }
            // The hot spot (where it looks for a DropTarget) is the pointer's
            // tip; the ghost goes just below and to the right of it.
            function place(at: point): void {
                x = at.x - Drag.hotSpot.x
                y = at.y - Drag.hotSpot.y
            }

            visible: Drag.active && !handedOver
            Drag.active: paths.length > 0
            Drag.source: ghost
            Drag.keys: ["spore-files"]
            Drag.hotSpot.x: -14
            Drag.hotSpot.y: -18
            // From the label's own width, which follows its text at once (a Row
            // only measures itself before the next frame): grabbed at the start
            // of a drag, the ghost already has its width.
            width: 12 + 15 + 8 + ghostLabel.width + 12
            height: 34
            radius: 10
            color: root.theme.cardBg
            border.width: 1
            border.color: root.theme.accent

            Row {
                anchors.left: parent.left
                anchors.leftMargin: 12
                anchors.verticalCenter: parent.verticalCenter
                spacing: 8

                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: !ghost.over ? "file" : ghost.over.trash ? "trash" : ghost.mode === "copy" ? "copy" : "arrow-right"
                    size: 15
                    color: root.theme.accent
                }
                UiText {
                    theme: root.theme
                    id: ghostLabel
                    width: Math.min(implicitWidth, 312)
                    anchors.verticalCenter: parent.verticalCenter
                    elide: Text.ElideMiddle
                    text: !ghost.over ? ghost.what
                        : ghost.over.trash ? "Move " + ghost.what + " to the Trash"
                        : (ghost.mode === "copy" ? "Copy " : "Move ") + ghost.what + " to “" + ghost.over.label + "”"
                }
            }
        }
    }

    // The status line: what's selected, or how many there are.
    readonly property string statusText: {
        const entry = current
        if (selectedCount > 1) {
            const size = folders.sizeOf(selection)
            return selectedCount + " items selected" + (size > 0 ? " (" + Util.humanSize(size) + ")" : "")
        }
        if (entry && trashOrigin) return "“" + entry.name + "” — " + trashOrigin
        if (entry && entry.isDir) return "“" + entry.name + "” — Folder"
        if (entry) return "“" + entry.name + "” — " + Util.kindLabel(Util.baseName(entry.path), false) + ", " + Util.humanSize(entry.size)
        const n = folders.count
        if (folders.filterText) return n + " of " + folders.totalCount + " items match “" + folders.filterText + "”"
        return n === 1 ? "1 item" : n + " items"
    }

    // The view shows the selection, scrolled into sight.
    onCurrentRowChanged: {
        const view = viewLoader.item
        if (!view) return
        if (view.currentIndex !== currentRow) view.currentIndex = currentRow
        if (currentRow >= 0) view.positionViewAtIndex(currentRow, GridView.Contain)
    }
}
