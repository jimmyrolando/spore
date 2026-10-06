import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "../services"
import "fileutil.js" as Util

// The places on the left: Recent (Recents.qml), Home and the user's folders
// (Desktop, Documents, Downloads…), the ones that exist, with their real
// names (they're translated on a system in another language), and the
// Trash. Then the Favorites, folders added with the right button (GTK's
// bookmarks, Bookmarks.qml), and Devices: the USB drives (DrivesService, the
// same as the shell's), mounted or not, each with its eject button. Files
// dragged from the views can be dropped on any of them but Recent (a volume
// once it's mounted).
//
// The keyboard comes here with Tab or F6 from the files (enter()): the
// arrows go through the places, a letter jumps to the next one starting with
// it, Enter opens it and Esc or Tab go back (done()).
Rectangle {
    id: root

    required property Theme theme
    required property DrivesService drives
    required property Bookmarks bookmarks
    // The open folder: its place is highlighted.
    property string folder: ""
    // The Trash's files/ (FileOps.trashFiles).
    property string trashPath: ""
    signal placeClicked(string path)
    // A drive's volume: open it (mounting it first if it isn't).
    signal volumeClicked(var device)
    signal ejectClicked(string disk)
    // The right button (or the Menu key) on a favorite: where, in the window.
    signal favoriteMenuRequested(string path, real x, real y)
    // The keyboard goes back to the files (a place opened, Esc or Tab).
    signal done()

    readonly property string home: Quickshell.env("HOME")
    // Recent isn't a folder: nothing drops there (dropPath, below).
    property var places: [{ label: "Recent", path: Util.recentPath, icon: "clock" }, { label: "Home", path: home, icon: "house" }]

    // Always on the left, so never a favorite too.
    function isPlace(path: string): bool {
        return path === trashPath || places.some(p => p.path === path)
    }

    // The favorite folders (GTK's bookmarks), without the places already shown
    // (other apps bookmark Documents or Downloads, for example).
    readonly property var favorites: bookmarks.folders.filter(b => !isPlace(b.path))

    // One row per volume: { disk, volume, label, mountpoint, target, icon,
    // internal, system }. The machine's own disks first ("/" is File System;
    // the others take their label, or the name of the folder they mount on),
    // then the USB drives.
    readonly property var devices: {
        const rows = []
        for (const volume of drives.internal) {
            const folder = Util.baseName(volume.mountpoint || volume.target || "")
            const named = volume.label || (folder && folder !== "/" ? folder.charAt(0).toUpperCase() + folder.slice(1)
                : Util.humanSize(volume.size) + " volume")
            rows.push({
                disk: volume.disk,
                volume: volume.path,
                label: volume.system ? "File System" : named,
                mountpoint: volume.mountpoint,
                target: volume.target,
                icon: "hard-drive",
                internal: true,
                system: volume.system
            })
        }
        for (const drive of drives.drives) {
            for (const volume of drive.volumes) {
                const unnamed = drive.volumes.length > 1 ? drive.name + " (" + Util.humanSize(volume.size) + ")" : drive.name
                rows.push({
                    disk: drive.path,
                    volume: volume.path,
                    label: volume.label || unnamed,
                    mountpoint: volume.mountpoint,
                    target: "",
                    icon: drive.transport === "USB" ? "usb" : "hard-drive",
                    internal: false,
                    system: false
                })
            }
        }
        return rows
    }

    // Every row in order, for the keyboard: { label, path } for a place or
    // the Trash, { label, device } for a volume.
    readonly property var rows: places.map(p => ({ label: p.label, path: p.path }))
        .concat([{ label: "Trash", path: trashPath }])
        .concat(favorites.map(b => ({ label: b.label, path: b.path })))
        .concat(devices.map(d => ({ label: d.label, device: d })))
    // The row the keyboard is on (its ring shows while the focus is here).
    property int keyIndex: 0
    onRowsChanged: keyIndex = Math.min(keyIndex, rows.length - 1)

    // The open folder is in it: its row is highlighted.
    function isHere(row: var): bool {
        if (!row.device) return folder === row.path
        const mount = row.device.mountpoint || row.device.target
        // "/" holds everything: highlighted only in "/" itself.
        return row.device.system ? folder === "/" : mount !== "" && (folder === mount || folder.startsWith(mount + "/"))
    }

    // The keyboard comes in, on the open folder's place (or the first one).
    function enter(): void {
        const here = rows.findIndex(row => isHere(row))
        keyIndex = here >= 0 ? here : 0
        forceActiveFocus()
    }

    function open(index: int): void {
        const row = rows[index]
        if (!row) return
        done()
        if (row.device) volumeClicked(row.device)
        else placeClicked(row.path)
    }

    // The Menu key on a favorite: its menu, just under it.
    function favoriteMenu(index: int): void {
        const i = index - places.length - 1
        const item = favoriteRepeater.itemAt(i)
        if (!item) return
        const point = item.mapToItem(null, 24, item.height)
        favoriteMenuRequested(favorites[i].path, point.x, point.y)
    }

    // The next row (after the keyboard's) whose name starts with `letter`.
    function jump(letter: string): void {
        const wanted = letter.toLowerCase()
        for (let step = 1; step <= rows.length; step++) {
            const index = (keyIndex + step) % rows.length
            if (rows[index].label.toLowerCase().startsWith(wanted)) {
                keyIndex = index
                return
            }
        }
    }

    Keys.onPressed: (event) => {
        const key = event.key
        const plain = !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier | Qt.MetaModifier))
        if (key === Qt.Key_Up) keyIndex = Math.max(0, keyIndex - 1)
        else if (key === Qt.Key_Down) keyIndex = Math.min(rows.length - 1, keyIndex + 1)
        else if (key === Qt.Key_Home) keyIndex = 0
        else if (key === Qt.Key_End) keyIndex = rows.length - 1
        else if (key === Qt.Key_Return || key === Qt.Key_Enter || key === Qt.Key_Space) open(keyIndex)
        else if (key === Qt.Key_Escape || key === Qt.Key_Tab || key === Qt.Key_Backtab || key === Qt.Key_F6) done()
        else if (key === Qt.Key_Menu || (event.modifiers & Qt.ShiftModifier) && key === Qt.Key_F10) favoriteMenu(keyIndex)
        else if (plain && event.text.length === 1 && event.text > " ") jump(event.text)
        else return
        event.accepted = true
    }

    color: theme.railBg
    implicitWidth: 196

    // The folders xdg-user-dirs set up (user-dirs.dirs, or the English names if
    // there isn't one). One that points to home is a disabled one.
    Process {
        running: true
        command: ["sh", "-c", `
            dirs="\${XDG_CONFIG_HOME:-$HOME/.config}/user-dirs.dirs"
            [ -f "$dirs" ] && . "$dirs"
            for place in "monitor:\${XDG_DESKTOP_DIR:-$HOME/Desktop}" "file-text:\${XDG_DOCUMENTS_DIR:-$HOME/Documents}" \\
                "download:\${XDG_DOWNLOAD_DIR:-$HOME/Downloads}" "music:\${XDG_MUSIC_DIR:-$HOME/Music}" \\
                "image:\${XDG_PICTURES_DIR:-$HOME/Pictures}" "film:\${XDG_VIDEOS_DIR:-$HOME/Videos}"; do
                dir=\${place#*:}
                [ -d "$dir" ] && [ "$dir" != "$HOME" ] && printf '%s\\n' "$place"
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const found = text.trim().split("\n").filter(l => l).map(l => {
                    const i = l.indexOf(":")
                    const path = l.slice(i + 1)
                    return { label: Util.baseName(path), path: path, icon: l.slice(0, i) }
                })
                root.places = root.places.slice(0, 2).concat(found)
            }
        }
    }

    // A place or a volume: its icon and name, highlighted when it's the open
    // folder, and optionally an eject button (busy: an ellipsis instead).
    component PlaceRow: Rectangle {
        id: row
        property string icon: ""
        property string label: ""
        property bool here: false
        // The keyboard is on it.
        property bool keyed: false
        property bool ejectable: false
        property bool busy: false
        // Files dropped on it go into this folder ("": none), or to the Trash.
        property string dropPath: ""
        property bool dropTrash: false
        signal clicked()
        signal ejected()
        // The right button, where it was in the window.
        signal menuRequested(real x, real y)

        Layout.fillWidth: true
        implicitHeight: 34
        radius: 9
        // Its ring goes over the rows next to it.
        z: keyed ? 1 : 0
        color: here ? root.theme.accent
            : rowDrop.containsDrag ? root.theme.alpha(root.theme.accent, 0.22)
            : rowArea.containsMouse || keyed && root.activeFocus ? root.theme.alpha(root.theme.accent, 0.12) : "transparent"
        border.width: rowDrop.containsDrag ? 1.5 : 0
        border.color: root.theme.accent

        DropTarget {
            id: rowDrop
            anchors.fill: parent
            enabled: row.dropPath !== "" || row.dropTrash
            path: row.dropPath
            label: row.label
            trash: row.dropTrash
        }

        // The keyboard's ring, with a gap so it shows around the highlighted
        // one too.
        Rectangle {
            anchors.fill: parent
            anchors.margins: -3
            radius: parent.radius + 3
            visible: row.keyed && root.activeFocus
            color: "transparent"
            border.width: 2
            border.color: root.theme.accent
        }

        MouseArea {
            id: rowArea
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor
            onClicked: (mouse) => {
                if (mouse.button === Qt.RightButton) {
                    const point = mapToItem(null, mouse.x, mouse.y)
                    row.menuRequested(point.x, point.y)
                } else {
                    row.clicked()
                }
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 4
            spacing: 10

            Icon {
                name: row.icon
                size: 15
                stroke: 1.5
                color: row.here ? root.theme.textOnAccent : root.theme.ink2
            }
            UiText {
                theme: root.theme
                Layout.fillWidth: true
                text: row.label
                color: row.here ? root.theme.textOnAccent : root.theme.text
            }
            UiText {
                theme: root.theme
                visible: row.busy
                Layout.rightMargin: 8
                text: "…"
                color: row.here ? root.theme.textOnAccent : root.theme.muted
            }
            CcButton {
                theme: root.theme
                visible: row.ejectable && !row.busy
                size: 26
                flat: true
                icon: "eject"
                iconSize: 13
                onClicked: row.ejected()
            }
        }
    }

    component Caption: UiText {
        theme: root.theme
        Layout.leftMargin: 10
        Layout.bottomMargin: 4
        color: root.theme.muted
        font.pixelSize: 11
        font.weight: Font.Medium
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        anchors.topMargin: 12
        spacing: 2

        Caption {
            text: "Places"
        }

        Repeater {
            model: root.places

            PlaceRow {
                required property var modelData
                required property int index
                icon: modelData.icon
                label: modelData.label
                here: root.folder === modelData.path
                dropPath: modelData.path === Util.recentPath ? "" : modelData.path
                keyed: root.keyIndex === index
                onClicked: root.open(index)
            }
        }

        PlaceRow {
            icon: "trash"
            label: "Trash"
            here: root.folder === root.trashPath
            dropTrash: true
            keyed: root.keyIndex === root.places.length
            onClicked: root.open(root.places.length)
        }

        Caption {
            visible: root.favorites.length > 0
            Layout.topMargin: 14
            text: "Favorites"
        }

        Repeater {
            id: favoriteRepeater
            model: root.favorites

            PlaceRow {
                required property var modelData
                required property int index
                icon: "folder"
                label: modelData.label
                here: root.folder === modelData.path
                dropPath: modelData.path
                keyed: root.keyIndex === root.places.length + 1 + index
                onClicked: root.open(root.places.length + 1 + index)
                onMenuRequested: (x, y) => root.favoriteMenuRequested(modelData.path, x, y)
            }
        }

        Caption {
            visible: root.devices.length > 0
            Layout.topMargin: 14
            text: "Devices"
        }

        Repeater {
            model: root.devices

            PlaceRow {
                required property var modelData
                required property int index
                icon: modelData.icon
                label: modelData.label
                here: root.isHere({ device: modelData })
                // Mounted (or in fstab): files can be dropped on it.
                dropPath: modelData.mountpoint || modelData.target
                keyed: root.keyIndex === root.places.length + 1 + root.favorites.length + index
                // The machine's own disks aren't ejected.
                ejectable: !modelData.internal
                busy: root.drives.working === modelData.disk
                onClicked: root.open(root.places.length + 1 + root.favorites.length + index)
                onEjected: root.ejectClicked(modelData.disk)
            }
        }

        Item { Layout.fillHeight: true }
    }
}
