import QtQuick
import "../common"

// The open folder as a grid: the thumbnail or icon, and the name in two
// lines at most. Clicks and drags: EntryArea.qml (a double click or Enter
// opens); a folder takes what's dropped on it.
GridView {
    id: root

    required property Theme theme
    required property FolderModel folderModel
    required property Thumbnails thumbnails
    // Without the focus the selection turns gray, like any app's.
    property bool windowActive: true
    // What's selected (name -> true), the cut ones (path -> true, dimmed) and
    // the one being renamed.
    property var selection: ({})
    property var cutPaths: ({})
    property string renaming: ""
    signal activated(int row)
    // A click on an entry (or on the empty part: -1) and its Ctrl/Shift. The
    // window owns the selection: it also moves it with the arrows.
    signal picked(int row, int modifiers)
    // The right button, where it was in the window (-1: the empty part).
    signal menuRequested(int row, real x, real y)
    signal renamed(string name)
    signal renameCanceled()
    // Dragging entries (EntryArea): where the pointer is, in the window.
    signal entryDragStarted(int row, point at, int modifiers)
    signal entryDragMoved(point at, int modifiers)
    signal entryDragEnded(int modifiers)
    signal entryDragCanceled()

    model: folderModel.model
    currentIndex: -1
    // As many columns as fit; the pixels left over go half to each side, so
    // the first and the last column are as far from the edges.
    readonly property int columns: Math.max(1, Math.floor(width / 116))
    cellWidth: Math.floor(width / columns)
    leftMargin: Math.floor((width - cellWidth * columns) / 2)
    cellHeight: 128
    clip: true
    focus: true
    keyNavigationEnabled: false
    boundsBehavior: Flickable.StopAtBounds
    // The selection is drawn by each item.
    highlightFollowsCurrentItem: false

    delegate: Item {
        id: entry

        required property int index
        required property string fileName
        required property string filePath
        required property bool fileIsDir
        required property real fileSize
        readonly property bool selected: root.selection[fileName] === true

        width: root.cellWidth
        height: root.cellHeight
        opacity: root.cutPaths[filePath] ? 0.45 : 1

        Rectangle {
            anchors.fill: parent
            anchors.margins: 4
            radius: 12
            color: dropHere.containsDrag ? root.theme.alpha(root.theme.accent, 0.2)
                : entry.selected ? (root.windowActive ? root.theme.accentSoft : root.theme.alpha(root.theme.text, 0.06))
                : area.containsMouse ? root.theme.alpha(root.theme.accent, 0.06) : "transparent"
            border.width: dropHere.containsDrag ? 2 : entry.selected && root.windowActive ? 1.5 : 0
            border.color: root.theme.accent
        }

        FileIcon {
            id: icon
            theme: root.theme
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            width: 84
            height: 62
            path: entry.filePath
            isDir: entry.fileIsDir
            fileSize: entry.fileSize
            thumbnail: root.thumbnails.found[entry.filePath] || ""
            iconSize: 44
        }

        UiText {
            theme: root.theme
            anchors.top: icon.bottom
            anchors.topMargin: 8
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            visible: root.renaming !== entry.fileName
            horizontalAlignment: Text.AlignHCenter
            text: entry.fileName
            font.pixelSize: 12
            wrapMode: Text.WrapAtWordBoundaryOrAnywhere
            maximumLineCount: 2
        }

        EntryArea {
            id: area
            anchors.fill: parent
            view: root
            rowIndex: entry.index
        }
        DropTarget {
            id: dropHere
            anchors.fill: parent
            enabled: entry.fileIsDir
            path: entry.filePath
            label: entry.fileName
        }

        // Above the MouseArea: clicks in the field go to the field.
        Loader {
            anchors.top: icon.bottom
            anchors.topMargin: 6
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            active: root.renaming === entry.fileName

            sourceComponent: RenameField {
                theme: root.theme
                name: entry.fileName
                isDir: entry.fileIsDir
                centered: true
                onAccepted: (name) => root.renamed(name)
                onCanceled: root.renameCanceled()
            }
        }
    }

    // The empty part, under the entries: a click there selects nothing; the
    // right button, the folder's menu.
    MouseArea {
        z: -1
        // The view's left edge (the content starts leftMargin in).
        x: -root.leftMargin
        width: root.width
        height: Math.max(root.contentHeight, root.height)
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: (mouse) => {
            // First: the menu that opens takes the keyboard after (EntryArea).
            root.forceActiveFocus()
            if (mouse.button === Qt.RightButton) {
                const point = mapToItem(null, mouse.x, mouse.y)
                root.menuRequested(-1, point.x, point.y)
            } else {
                root.picked(-1, mouse.modifiers)
            }
        }
    }

    // Where the scroll is, while there's more than fits.
    Rectangle {
        parent: root
        visible: root.contentHeight > root.height
        x: root.width - width - 2
        y: Math.min(root.visibleArea.yPosition * root.height, root.height - height)
        width: 4
        height: Math.max(24, root.visibleArea.heightRatio * root.height)
        radius: 2
        color: root.theme.alpha(root.theme.text, root.moving ? 0.35 : 0.18)
    }
}
