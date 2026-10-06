import QtQuick
import Quickshell
import "../common"
import "fileutil.js" as Util

// Where you are: the path in pieces (Home › Pictures › Wallpapers), each
// one clickable and somewhere to drop files. Ctrl+L or a click on the empty
// part turns it into a text field to type a path (~ is home, trash:/// the
// Trash and recent:/// Recent, as in GNOME; a relative one starts from the
// open folder).
Rectangle {
    id: root

    required property Theme theme
    property string folder: ""
    // The text field is showing (until it loses the focus).
    property bool editing: false
    signal navigate(string path)
    // Esc or Enter in the field: the window gives the focus back to the view.
    signal done()

    readonly property string home: Quickshell.env("HOME")

    function edit(): void {
        editing = true
        input.text = folder
        input.forceActiveFocus()
        input.selectAll()
    }

    // The Trash's files/ (FileOps.trashFiles): it shows as "Trash".
    property string trashPath: ""

    // Home › Pictures › Wallpapers, / › nix › store outside home, Trash or
    // Recent.
    readonly property var crumbs: {
        if (folder === Util.recentPath) return [{ label: "Recent", path: folder }]
        const inTrash = trashPath !== "" && (folder === trashPath || folder.startsWith(trashPath + "/"))
        const inHome = !inTrash && (folder === home || folder.startsWith(home + "/"))
        const base = inTrash ? trashPath : inHome ? home : ""
        const parts = folder.slice(base.length).split("/").filter(s => s)
        const out = [{ label: inTrash ? "Trash" : inHome ? "Home" : "/", path: base || "/" }]
        let path = base
        for (const part of parts) {
            path += "/" + part
            out.push({ label: part, path: path })
        }
        return out
    }

    implicitHeight: 34
    radius: 9
    color: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.6))
    border.width: 1
    border.color: editing ? theme.accent : Qt.tint(theme.base, theme.alpha(theme.text, 0.15))

    // The empty part (after the last piece): edit the path.
    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.IBeamCursor
        onClicked: root.edit()
    }

    Flickable {
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        visible: !root.editing
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
                    readonly property bool last: index === root.crumbs.length - 1
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
                        anchors.verticalCenter: parent.verticalCenter
                        width: crumbText.implicitWidth + 14
                        height: 26
                        radius: 7
                        color: crumbDrop.containsDrag ? root.theme.alpha(root.theme.accent, 0.22)
                            : crumbArea.containsMouse && !crumb.last ? root.theme.alpha(root.theme.accent, 0.12) : "transparent"
                        border.width: crumbDrop.containsDrag ? 1.5 : 0
                        border.color: root.theme.accent

                        UiText {
                            id: crumbText
                            theme: root.theme
                            anchors.centerIn: parent
                            text: crumb.modelData.label
                            color: crumb.last ? root.theme.text : root.theme.muted
                            font.weight: crumb.last ? Font.DemiBold : Font.Normal
                        }
                        MouseArea {
                            id: crumbArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: crumb.last ? Qt.IBeamCursor : Qt.PointingHandCursor
                            onClicked: crumb.last ? root.edit() : root.navigate(crumb.modelData.path)
                        }
                        // Files dragged here go up into this folder.
                        DropTarget {
                            id: crumbDrop
                            anchors.fill: parent
                            enabled: !crumb.last
                            path: crumb.modelData.path
                            label: crumb.modelData.label
                        }
                    }
                }
            }
        }
    }

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 12
        visible: root.editing
        verticalAlignment: TextInput.AlignVCenter
        clip: true
        color: root.theme.text
        selectionColor: root.theme.accent
        selectedTextColor: root.theme.textOnAccent
        font.family: root.theme.fontFamily
        font.pixelSize: 13
        onActiveFocusChanged: if (!activeFocus) root.editing = false
        onAccepted: {
            const typed = text.trim()
            root.done()
            if (/^trash:\/*$/.test(typed)) root.navigate(root.trashPath)
            else if (/^recent:\/*$/.test(typed)) root.navigate(Util.recentPath)
            else if (typed) root.navigate(typed === "~" ? root.home : typed.startsWith("~/") ? root.home + typed.slice(1) : typed)
        }
        Keys.onEscapePressed: root.done()
    }
}
