import QtQuick
import "../common"
import "fileutil.js" as Util

// The open folder as a list with columns: name, size, kind and modified.
// A click on a column's title sorts by it (again: the other way around).
// Clicks and drags work like the grid's (EntryArea.qml); a folder takes what's
// dropped on it.
ListView {
    id: root

    required property Theme theme
    required property FolderModel folderModel
    required property Thumbnails thumbnails
    property bool windowActive: true
    // The bar clock's hours: "hh:mm" or "h:mm AP".
    property string timeFormat: "hh:mm"
    // What's selected (name -> true), the cut ones (path -> true, dimmed) and
    // the one being renamed.
    property var selection: ({})
    property var cutPaths: ({})
    property string renaming: ""
    signal activated(int row)
    signal sortRequested(string column)
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

    readonly property real sizeWidth: 88
    readonly property real kindWidth: 130
    readonly property real dateWidth: 150
    readonly property real nameWidth: width - sizeWidth - kindWidth - dateWidth - 24

    model: folderModel.model
    currentIndex: -1
    clip: true
    focus: true
    keyNavigationEnabled: false
    boundsBehavior: Flickable.StopAtBounds
    highlightFollowsCurrentItem: false
    headerPositioning: ListView.OverlayHeader

    component ColumnTitle: Rectangle {
        id: title
        property string label: ""
        property string column: ""
        property bool alignRight: false
        // Recent is newest first, always.
        readonly property bool active: !root.folderModel.recent && root.folderModel.sortBy === column

        height: 30
        color: titleArea.containsMouse ? root.theme.alpha(root.theme.accent, 0.08) : "transparent"
        radius: 6

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: title.alignRight ? undefined : parent.left
            anchors.right: title.alignRight ? parent.right : undefined
            anchors.leftMargin: 8
            anchors.rightMargin: 8
            layoutDirection: title.alignRight ? Qt.RightToLeft : Qt.LeftToRight
            spacing: 4

            UiText {
                theme: root.theme
                text: title.label
                color: title.active ? root.theme.text : root.theme.muted
                font.pixelSize: 12
                font.weight: title.active ? Font.DemiBold : Font.Normal
            }
            Icon {
                anchors.verticalCenter: parent.verticalCenter
                visible: title.active
                name: root.folderModel.descending ? "chevron-down" : "chevron-up"
                size: 12
                color: root.theme.muted
            }
        }

        MouseArea {
            id: titleArea
            anchors.fill: parent
            enabled: !root.folderModel.recent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.sortRequested(title.column)
        }
    }

    header: Rectangle {
        width: root.width
        height: 34
        z: 2
        color: root.theme.base

        Row {
            anchors.left: parent.left
            anchors.leftMargin: 8
            anchors.verticalCenter: parent.verticalCenter

            ColumnTitle {
                width: root.nameWidth
                label: "Name"
                column: "name"
            }
            ColumnTitle {
                width: root.sizeWidth
                label: "Size"
                column: "size"
                alignRight: true
            }
            ColumnTitle {
                width: root.kindWidth
                label: "Kind"
                column: "kind"
            }
            ColumnTitle {
                width: root.dateWidth
                label: "Modified"
                column: "modified"
            }
        }

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: 1
            color: root.theme.alpha(root.theme.accent, 0.1)
        }
    }

    delegate: Rectangle {
        id: row

        required property int index
        required property string fileName
        required property string filePath
        required property bool fileIsDir
        required property real fileSize
        required property date fileModified
        readonly property bool selected: root.selection[fileName] === true

        // The list puts its rows at x 0 (an x here is ignored): the whole width.
        width: root.width
        height: 30
        radius: 7
        opacity: root.cutPaths[filePath] ? 0.45 : 1
        color: dropHere.containsDrag ? root.theme.alpha(root.theme.accent, 0.2)
            : selected ? (root.windowActive ? root.theme.accentSoft : root.theme.alpha(root.theme.text, 0.06))
            : area.containsMouse ? root.theme.alpha(root.theme.accent, 0.05) : "transparent"
        border.width: dropHere.containsDrag ? 2 : selected && root.windowActive ? 1 : 0
        border.color: root.theme.accent

        Row {
            anchors.fill: parent
            anchors.leftMargin: 4

            Item {
                width: root.nameWidth
                height: parent.height

                FileIcon {
                    id: icon
                    theme: root.theme
                    anchors.left: parent.left
                    anchors.leftMargin: 6
                    anchors.verticalCenter: parent.verticalCenter
                    width: 20
                    height: 20
                    path: row.filePath
                    isDir: row.fileIsDir
                    fileSize: row.fileSize
                    thumbnail: root.thumbnails.found[row.filePath] || ""
                    iconSize: 16
                }
                UiText {
                    theme: root.theme
                    anchors.left: icon.right
                    anchors.leftMargin: 10
                    anchors.right: parent.right
                    anchors.rightMargin: 8
                    anchors.verticalCenter: parent.verticalCenter
                    visible: root.renaming !== row.fileName
                    text: row.fileName
                    elide: Text.ElideMiddle
                }
            }
            MonoText {
                theme: root.theme
                width: root.sizeWidth
                anchors.verticalCenter: parent.verticalCenter
                rightPadding: 8
                horizontalAlignment: Text.AlignRight
                text: row.fileIsDir ? "—" : Util.humanSize(row.fileSize)
                color: root.theme.muted
            }
            UiText {
                theme: root.theme
                width: root.kindWidth
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
                text: Util.kindLabel(Util.baseName(row.filePath), row.fileIsDir)
                color: root.theme.muted
                font.pixelSize: 12
            }
            MonoText {
                theme: root.theme
                width: root.dateWidth
                anchors.verticalCenter: parent.verticalCenter
                leftPadding: 8
                text: Util.shortDate(row.fileModified, root.timeFormat)
                color: root.theme.muted
            }
        }

        EntryArea {
            id: area
            anchors.fill: parent
            view: root
            rowIndex: row.index
        }
        DropTarget {
            id: dropHere
            anchors.fill: parent
            enabled: row.fileIsDir
            path: row.filePath
            label: row.fileName
        }

        // Above the MouseArea: clicks in the field go to the field.
        Loader {
            x: 4 + 6 + 20 + 6
            width: root.nameWidth - x - 4
            anchors.verticalCenter: parent.verticalCenter
            active: root.renaming === row.fileName

            sourceComponent: RenameField {
                theme: root.theme
                name: row.fileName
                isDir: row.fileIsDir
                onAccepted: (name) => root.renamed(name)
                onCanceled: root.renameCanceled()
            }
        }
    }

    // The empty part, under the entries: a click there selects nothing; the
    // right button, the folder's menu.
    MouseArea {
        z: -1
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
        y: Math.min(34 + root.visibleArea.yPosition * (root.height - 34), root.height - height)
        width: 4
        height: Math.max(24, root.visibleArea.heightRatio * (root.height - 34))
        radius: 2
        color: root.theme.alpha(root.theme.text, root.moving ? 0.35 : 0.18)
    }
}
