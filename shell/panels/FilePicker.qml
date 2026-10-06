import QtQuick
import QtQuick.Layouts
import Qt.labs.folderlistmodel
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"
import "../files/fileutil.js" as FileUtil

// Our own file and folder picker: a layer above everything (like the Control
// Center and Settings), not a window niri would put in the tiling where it
// could end up below a panel. shell.qml opens it with a request (mode,
// starting folder, filters) and it reports the chosen path.
//
// - mode "folder": you choose the open folder (or the selected one); files
//   are shown dimmed, to recognize the folder by its content.
// - mode "file": only the files in `nameFilters` (and folders, to
//   navigate); double click or Choose.
//
// Keyboard: arrows to move, Enter to enter or choose, Backspace goes up a
// folder, Esc cancels.
PanelWindow {
    id: root

    required property Theme theme
    property string mode: "file"
    property string title: mode === "folder" ? "Choose a folder" : "Choose a file"
    // Folder it opens in (a path, not a URL). If it doesn't exist, home.
    property string startFolder: home
    property var nameFilters: []
    // Places on the left besides Home, Pictures, Downloads and Documents (e.g.
    // the wallpaper folder): [{ label, path, icon }].
    property var extraPlaces: []

    signal accepted(string path)
    signal canceled()

    readonly property string home: Quickshell.env("HOME")
    property string folder: startFolder
    // The one selected in the grid (file or folder), or "".
    property string selected: ""
    property bool selectedIsDir: false

    // Path shown: with ~ instead of home.
    function pretty(path: string): string {
        return path === home ? "~" : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path
    }

    function open(path: string): void {
        folder = path
        selected = ""
    }

    function up(): void {
        if (folder === "/") return
        open(folder.slice(0, folder.lastIndexOf("/")) || "/")
    }

    // What Choose returns: the selected file, or in folder mode the selected or
    // the open folder.
    readonly property string choice: mode === "folder" ? (selected !== "" && selectedIsDir ? selected : folder)
        : (selected !== "" && !selectedIsDir ? selected : "")

    function activate(path: string, dir: bool): void {
        if (dir) open(path)
        else if (mode === "file") root.accepted(path)
    }

    // The breadcrumbs: ~ › Pictures › Wallpapers (or / › …, outside home).
    readonly property var crumbs: {
        const inHome = folder === home || folder.startsWith(home + "/")
        const base = inHome ? home : ""
        const rest = folder.slice(base.length).split("/").filter(s => s)
        const out = [{ label: inHome ? "~" : "/", path: inHome ? home : "/" }]
        let acc = base
        for (const part of rest) {
            acc += "/" + part
            out.push({ label: part, path: acc })
        }
        return out
    }

    // The fixed places that exist, plus the extra ones.
    property var places: []
    Process {
        running: true
        command: ["sh", "-c", 'for d in "$HOME/Pictures" "$HOME/Downloads" "$HOME/Documents"; do [ -d "$d" ] && echo "$d"; done']
        stdout: StdioCollector {
            onStreamFinished: {
                const icons = { Pictures: "image", Downloads: "download", Documents: "file-text" }
                const found = text.trim().split("\n").filter(s => s).map(p => {
                    const name = p.split("/").pop()
                    return { label: name, path: p, icon: icons[name] || "folder" }
                })
                root.places = [{ label: "Home", path: root.home, icon: "house" }].concat(found, root.extraPlaces)
            }
        }
    }

    FolderListModel {
        id: folders
        folder: FileUtil.folderUri(root.folder)
        // The start folder comes at creation: an odd one ("#", "?" or "%41" in
        // its path) too early for folderUri, so the model gets it again now.
        // (Not any other: one that doesn't exist falls back to the working
        // folder, which is home.)
        Component.onCompleted: if (FileUtil.oddFolder(root.folder)) folder = Qt.binding(() => FileUtil.folderUri(root.folder))
        showDirsFirst: true
        showDotAndDotDot: false
        showHidden: false
        caseSensitive: false
        nameFilters: root.mode === "file" ? root.nameFilters : []
        sortCaseSensitive: false
        // New folder loaded: nothing selected (the grid would select the first, and
        // in folder mode that one would be chosen instead of the open one).
        onStatusChanged: if (status === FolderListModel.Ready) {
            grid.currentIndex = -1
            root.selected = ""
        }
    }

    // The whole screen, dimmed: a click outside the card = cancel.
    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "spore-file-picker"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(0, 0, 0, 0.35)

        MouseArea {
            anchors.fill: parent
            onClicked: root.canceled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: 780
        height: 520
        radius: 20
        color: root.theme.panelBg
        border.width: 1
        border.color: root.theme.panelBorder
        clip: true

        // So clicks on the card don't reach the background (cancel).
        MouseArea {
            anchors.fill: parent
        }

        focus: true
        Keys.onEscapePressed: root.canceled()
        Keys.onPressed: (event) => {
            if (event.key === Qt.Key_Backspace) {
                root.up()
                event.accepted = true
            }
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // --- Title and close ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 12
                Layout.topMargin: 12
                Layout.bottomMargin: 10
                spacing: 12

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.title
                    font.pixelSize: 17
                    font.weight: Font.DemiBold
                }
                CcButton {
                    theme: root.theme
                    size: 32
                    flat: true
                    icon: "x"
                    iconSize: 13
                    onClicked: root.canceled()
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

                // --- Places ---
                Rectangle {
                    Layout.fillHeight: true
                    implicitWidth: 170
                    color: root.theme.railBg

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 2

                        Repeater {
                            model: root.places

                            Rectangle {
                                id: place
                                required property var modelData
                                readonly property bool here: root.folder === modelData.path
                                Layout.fillWidth: true
                                implicitHeight: 34
                                radius: 9
                                color: here ? root.theme.accent
                                    : placeArea.containsMouse ? root.theme.alpha(root.theme.accent, 0.12) : "transparent"

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 10
                                    Icon {
                                        name: place.modelData.icon
                                        size: 15
                                        stroke: 1.5
                                        color: place.here ? root.theme.textOnAccent : root.theme.ink2
                                    }
                                    UiText {
                                        theme: root.theme
                                        Layout.fillWidth: true
                                        text: place.modelData.label
                                        color: place.here ? root.theme.textOnAccent : root.theme.text
                                    }
                                }

                                MouseArea {
                                    id: placeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.open(place.modelData.path)
                                }
                            }
                        }

                        Item { Layout.fillHeight: true }
                    }
                }

                // --- Open folder ---
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 0

                    // Up, and the breadcrumbs.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 14
                        Layout.rightMargin: 14
                        Layout.topMargin: 10
                        Layout.bottomMargin: 6
                        spacing: 4

                        CcButton {
                            theme: root.theme
                            size: 28
                            icon: "arrow-up"
                            iconSize: 13
                            enabled: root.folder !== "/"
                            onClicked: root.up()
                        }

                        Flickable {
                            Layout.fillWidth: true
                            Layout.leftMargin: 6
                            implicitHeight: 28
                            contentWidth: crumbRow.implicitWidth
                            clip: true
                            // The end of the path shows (the closest part).
                            contentX: Math.max(0, contentWidth - width)
                            interactive: contentWidth > width

                            Row {
                                id: crumbRow
                                height: parent.height
                                spacing: 2

                                Repeater {
                                    model: root.crumbs

                                    Row {
                                        id: crumb
                                        required property var modelData
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 2

                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            visible: crumb.index > 0
                                            name: "chevron-right"
                                            size: 12
                                            color: root.theme.muted2
                                        }
                                        Rectangle {
                                            readonly property bool last: crumb.index === root.crumbs.length - 1
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: crumbText.implicitWidth + 12
                                            height: 24
                                            radius: 6
                                            color: crumbArea.containsMouse && !last ? root.theme.alpha(root.theme.accent, 0.12) : "transparent"

                                            UiText {
                                                id: crumbText
                                                theme: root.theme
                                                anchors.centerIn: parent
                                                text: crumb.modelData.label
                                                color: parent.last ? root.theme.text : root.theme.muted
                                                font.weight: parent.last ? Font.DemiBold : Font.Normal
                                            }
                                            MouseArea {
                                                id: crumbArea
                                                anchors.fill: parent
                                                hoverEnabled: true
                                                cursorShape: parent.last ? Qt.ArrowCursor : Qt.PointingHandCursor
                                                onClicked: if (!parent.last) root.open(crumb.modelData.path)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // The grid: folders first, images with their thumbnail.
                    GridView {
                        id: grid
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.leftMargin: 10
                        Layout.rightMargin: 10
                        clip: true
                        focus: true
                        model: folders
                        currentIndex: -1
                        cellWidth: Math.floor(width / Math.max(1, Math.floor(width / 112)))
                        cellHeight: 112
                        boundsBehavior: Flickable.StopAtBounds
                        keyNavigationWraps: false
                        onCurrentIndexChanged: {
                            if (currentIndex < 0) return
                            root.selected = folders.get(currentIndex, "filePath")
                            root.selectedIsDir = folders.get(currentIndex, "fileIsDir")
                        }
                        function activateCurrent(): void {
                            if (currentIndex >= 0) root.activate(folders.get(currentIndex, "filePath"), folders.get(currentIndex, "fileIsDir"))
                        }
                        Keys.onReturnPressed: activateCurrent()
                        Keys.onEnterPressed: activateCurrent()

                        delegate: Item {
                            id: entry
                            required property string fileName
                            required property string filePath
                            required property bool fileIsDir
                            required property int index
                            readonly property bool image: /\.(png|jpe?g|webp|gif|bmp)$/i.test(fileName)
                            // In folder mode files are only shown.
                            readonly property bool pickable: fileIsDir || root.mode === "file"
                            readonly property bool current: GridView.isCurrentItem

                            width: grid.cellWidth
                            height: grid.cellHeight
                            opacity: pickable ? 1 : 0.45

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: 4
                                radius: 12
                                color: entry.current ? root.theme.accentSoft
                                    : entryArea.containsMouse && entry.pickable ? root.theme.alpha(root.theme.accent, 0.08) : "transparent"
                                border.width: entry.current ? 1.5 : 0
                                border.color: root.theme.accent
                            }

                            Item {
                                id: preview
                                anchors.top: parent.top
                                anchors.topMargin: 12
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 72
                                height: 56

                                Icon {
                                    anchors.centerIn: parent
                                    visible: !entry.image || thumb.status !== Image.Ready
                                    name: entry.fileIsDir ? "folder" : entry.image ? "image" : "file"
                                    size: 34
                                    stroke: 1.2
                                    color: entry.fileIsDir ? root.theme.accent : root.theme.muted2
                                }

                                Image {
                                    id: thumb
                                    anchors.fill: parent
                                    visible: status === Image.Ready
                                    source: entry.image ? FileUtil.fileUri(entry.filePath) : ""
                                    sourceSize: Qt.size(144, 112)
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    cache: false
                                }
                            }

                            UiText {
                                theme: root.theme
                                anchors.top: preview.bottom
                                anchors.topMargin: 8
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.leftMargin: 8
                                anchors.rightMargin: 8
                                horizontalAlignment: Text.AlignHCenter
                                text: entry.fileName
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: entryArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: entry.pickable ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: if (entry.pickable) grid.currentIndex = entry.index
                                onDoubleClicked: if (entry.pickable) root.activate(entry.filePath, entry.fileIsDir)
                            }
                        }

                        // Empty folder (or no usable files).
                        UiText {
                            theme: root.theme
                            anchors.centerIn: parent
                            visible: grid.count === 0 && folders.status === FolderListModel.Ready
                            text: root.mode === "file" ? "No matching files here" : "Empty folder"
                            color: root.theme.muted
                        }
                    }

                    // --- The choice and the buttons ---
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 1
                        color: root.theme.alpha(root.theme.accent, 0.1)
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.margins: 12
                        Layout.leftMargin: 16
                        spacing: 8

                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.choice !== "" ? root.pretty(root.choice) : "Select a file"
                            color: root.choice !== "" ? root.theme.text : root.theme.muted
                            elide: Text.ElideMiddle
                        }
                        CcButton {
                            theme: root.theme
                            size: 32
                            label: "Cancel"
                            onClicked: root.canceled()
                        }
                        CcButton {
                            theme: root.theme
                            size: 32
                            primary: true
                            label: "Choose"
                            enabled: root.choice !== ""
                            onClicked: root.accepted(root.choice)
                        }
                    }
                }
            }
        }
    }
}
