import QtQuick
import QtQml.Models
import Qt.labs.folderlistmodel
import "fileutil.js" as Util

// The open folder's entries, ready for the views. FolderListModel reads the
// folder and follows it (a file that appears or disappears shows up by
// itself) and a SortFilterProxyModel sorts it: folders first, "img2" before
// "img10". While filtering, the views show `matches` instead: the entries
// whose name contains the text, in the same order, remade when the text or
// the folder changes. (Not a FunctionFilter in the proxy: in Qt 6.11,
// destroying one crashed the process every time it ended or reloaded.)
//
// `model` is what the views show; entry() and rowOf() read it, whichever it
// is.
//
// The Recent place (`folder` is Util.recentPath) isn't a folder: its
// entries come from Recents.qml, newest first and not sorted again, each
// with a name of its own (pathOf() says where it is).
QtObject {
    id: root

    property string folder: ""
    property bool showHidden: false
    // Part of the name, case-insensitive ("" = everything).
    property string filterText: ""
    // "name" | "size" | "modified" | "kind"
    property string sortBy: "name"
    property bool descending: false

    // The Recent place's list (files.qml has the one for all windows).
    property Recents recents: null
    readonly property bool recent: folder === Util.recentPath

    readonly property var model: filterText ? matches : recent ? recentList : proxy
    // Entries shown (filtered) and in the folder.
    property int count: 0
    readonly property int totalCount: recent ? recentList.count : source.count
    readonly property bool ready: recent ? recents !== null && recents.loaded : source.status === FolderListModel.Ready
    // The names in the folder (name -> true), shown or not: the window keeps
    // its selection to the ones still there.
    property var present: ({})

    onFilterTextChanged: refilter()
    onModelChanged: countShown()

    // Before `source` on purpose: QML sets bindings in the order they're
    // written, and the proxy has to be given the folder model before its
    // folder is set. FolderListModel (Qt 6.11) starts a reset then and ends
    // it once the listing comes (or the next folder is set); a proxy given it
    // in between got only the end, and Qt warned "endResetModel called on
    // QQmlSortFilterProxyModel without calling beginResetModel first" every
    // time Files started (tools/test.sh looks for it in the log).
    property SortFilterProxyModel proxy: SortFilterProxyModel {
        model: root.source
        // In order of priority: folders first, then the chosen column, and the
        // name to break ties.
        sorters: [
            RoleSorter {
                roleName: "fileIsDir"
                sortOrder: Qt.DescendingOrder
            },
            RoleSorter {
                roleName: "fileSize"
                enabled: root.sortBy === "size"
                sortOrder: root.descending ? Qt.DescendingOrder : Qt.AscendingOrder
            },
            RoleSorter {
                roleName: "fileModified"
                enabled: root.sortBy === "modified"
                sortOrder: root.descending ? Qt.DescendingOrder : Qt.AscendingOrder
            },
            StringSorter {
                roleName: "fileSuffix"
                enabled: root.sortBy === "kind"
                caseSensitivity: Qt.CaseInsensitive
                sortOrder: root.descending ? Qt.DescendingOrder : Qt.AscendingOrder
            },
            StringSorter {
                roleName: "fileName"
                numericMode: true
                caseSensitivity: Qt.CaseInsensitive
                sortOrder: root.sortBy === "name" && root.descending ? Qt.DescendingOrder : Qt.AscendingOrder
            }
        ]
    }

    property FolderListModel source: FolderListModel {
        // The window gives `folder` only once it's complete, as folderUri
        // needs. Until then "/", a few entries that are always there: with
        // none, the model lists the process's working folder, which can be a
        // huge one (spore-files run from a terminal there).
        folder: root.folder && !root.recent ? Util.folderUri(root.folder) : "file:///"
        showDirsFirst: false
        showDotAndDotDot: false
        showHidden: root.showHidden
        // The proxy sorts.
        sortField: FolderListModel.Unsorted
    }

    property ListModel matches: ListModel {}

    property ListModel recentList: ListModel {}

    onRecentChanged: {
        if (recent && recents) {
            recents.active = true
            // What was there last time may have gone since.
            if (recents.loaded) recents.check()
        }
        fillRecent()
    }

    property Connections recentFeed: Connections {
        target: root.recents
        function onItemsChanged() { root.fillRecent() }
    }

    function fillRecent(): void {
        recentList.clear()
        if (recent && recents) {
            recentList.append(recents.items.map(i => ({
                fileName: i.name, filePath: i.path, fileIsDir: i.isDir, fileSize: i.size, fileModified: i.modified
            })))
        }
        changed()
    }

    // Where the entry called `name` is.
    function pathOf(name: string): string {
        if (recent) return recents ? recents.pathByName[name] || "" : ""
        return folder === "/" ? "/" + name : folder + "/" + name
    }

    // Every entry, shown or not: [{ path, isDir }] (the thumbnails).
    function all(): var {
        const out = []
        if (recent) {
            for (let i = 0; i < recentList.count; i++) {
                const e = recentList.get(i)
                out.push({ path: e.filePath, isDir: e.fileIsDir })
            }
        } else {
            for (let i = 0; i < source.count; i++) out.push({ path: source.get(i, "filePath"), isDir: source.get(i, "fileIsDir") })
        }
        return out
    }

    // The folder changes under a filter (a file appears, the order changes):
    // the matches are remade once it settles.
    property Timer refilterSoon: Timer {
        interval: 150
        onTriggered: root.refilter()
    }

    property Connections listing: Connections {
        target: root.proxy
        function onRowsInserted() { root.changed() }
        function onRowsRemoved() { root.changed() }
        function onLayoutChanged() { root.changed() }
        function onModelReset() { root.changed() }
    }

    function changed(): void {
        if (filterText) refilterSoon.restart()
        else countShown()
        const names = {}
        if (recent) {
            for (let i = 0; i < recentList.count; i++) names[recentList.get(i).fileName] = true
        } else {
            for (let i = 0; i < source.count; i++) names[source.get(i, "fileName")] = true
        }
        present = names
    }

    function countShown(): void {
        count = filterText ? matches.count : recent ? recentList.count : proxy.rowCount()
    }

    function refilter(): void {
        refilterSoon.stop()
        const found = []
        if (filterText && recent) {
            const needle = filterText.toLowerCase()
            for (let i = 0; i < recentList.count; i++) {
                const e = recentList.get(i)
                if (e.fileName.toLowerCase().includes(needle))
                    found.push({ fileName: e.fileName, filePath: e.filePath, fileIsDir: e.fileIsDir, fileSize: e.fileSize, fileModified: e.fileModified })
            }
        } else if (filterText) {
            const needle = filterText.toLowerCase()
            for (let row = 0; row < proxy.rowCount(); row++) {
                const i = proxy.mapToSource(proxy.index(row, 0)).row
                const name = source.get(i, "fileName")
                if (!name.toLowerCase().includes(needle)) continue
                found.push({
                    fileName: name,
                    filePath: source.get(i, "filePath"),
                    fileIsDir: source.get(i, "fileIsDir"),
                    fileSize: source.get(i, "fileSize"),
                    fileModified: source.get(i, "fileModified")
                })
            }
        }
        matches.clear()
        if (found.length) matches.append(found)
        countShown()
    }

    // The entry in row `row` of `model`, or null.
    function entry(row: int): var {
        if (row < 0 || row >= count) return null
        if (filterText) {
            const match = matches.get(row)
            return {
                name: match.fileName,
                path: match.filePath,
                isDir: match.fileIsDir,
                size: match.fileSize,
                modified: match.fileModified
            }
        }
        if (recent) {
            const e = recentList.get(row)
            return { name: e.fileName, path: e.filePath, isDir: e.fileIsDir, size: e.fileSize, modified: e.fileModified }
        }
        const i = proxy.mapToSource(proxy.index(row, 0)).row
        return {
            name: source.get(i, "fileName"),
            path: source.get(i, "filePath"),
            isDir: source.get(i, "fileIsDir"),
            size: source.get(i, "fileSize"),
            modified: source.get(i, "fileModified")
        }
    }

    // What the files among `names` (name -> true) weigh together (folders
    // don't count: their size would take reading them).
    function sizeOf(names: var): real {
        let bytes = 0
        if (recent) {
            for (let i = 0; i < recentList.count; i++) {
                const e = recentList.get(i)
                if (names[e.fileName] && !e.fileIsDir) bytes += e.fileSize
            }
            return bytes
        }
        for (let i = 0; i < source.count; i++) {
            if (names[source.get(i, "fileName")] && !source.get(i, "fileIsDir")) bytes += source.get(i, "fileSize")
        }
        return bytes
    }

    // The row of the entry called `name` in `model`, or -1 (not there, or
    // filtered out).
    function rowOf(name: string): int {
        if (filterText) {
            for (let row = 0; row < matches.count; row++) {
                if (matches.get(row).fileName === name) return row
            }
            return -1
        }
        if (recent) {
            for (let i = 0; i < recentList.count; i++) {
                if (recentList.get(i).fileName === name) return i
            }
            return -1
        }
        for (let i = 0; i < source.count; i++) {
            if (source.get(i, "fileName") === name)
                return proxy.mapFromSource(source.index(i, 0)).row
        }
        return -1
    }
}
