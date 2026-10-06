import QtQuick
import Quickshell

// Somewhere dragged files can go: a folder in the view, a place on the left,
// a piece of the path, the open folder itself. What's dragged in Files (its
// window's ghost) reads these from the one it's over and says whether it
// takes it there: a folder never goes into itself, and nothing goes inside
// the Trash but through its place.
//
// A drag that left the window and came back is the system's by then: it
// comes with its own format (application/x-spore-files) and lands in
// onDropped. So do files dragged from another app (Thunar, a browser…): a
// list of local files (text/uri-list), which the window (QsWindow.window,
// the FilesWindow) checks and drops.
DropArea {
    // The folder it's for, its name for "Move to …", or the Trash.
    property string path: ""
    property string label: ""
    property bool trash: false

    readonly property var files: QsWindow.window

    keys: ["spore-files", "application/x-spore-files", "text/uri-list"]
    onEntered: (drag) => {
        if (drag.source !== null && drag.source.accepts !== undefined) {
            drag.accepted = drag.source.accepts(path, trash)
            return
        }
        const paths = files && drag.hasUrls ? files.localPaths(drag.urls) : []
        drag.accepted = paths.length > 0 && files.dropAllowed(paths, path, trash, false)
    }
    onDropped: (drop) => {
        if (drop.source !== null && drop.source.droppedOn !== undefined) {
            drop.source.droppedOn(path, trash)
        } else {
            const paths = files && drop.hasUrls ? files.localPaths(drop.urls) : []
            if (!paths.length) return
            files.dropOn(paths, path, trash, 0, false)
        }
        drop.accept(Qt.CopyAction)
    }
}
