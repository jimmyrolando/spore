import QtQuick
import "../common"

// Renaming in place (F2): the name, editable, with the part before the
// extension selected (like macOS and Windows). Enter renames, Esc gives up,
// and clicking elsewhere keeps what's written.
Rectangle {
    id: root

    required property Theme theme
    property string name: ""
    property bool isDir: false
    // Centered (the grid) or from the left (the list).
    property bool centered: false
    // The view's row it's in (see onActiveFocusChanged).
    property Item rowItem: null
    signal accepted(string name)
    signal canceled()

    property bool finished: false

    function finish(keep: bool): void {
        if (finished) return
        finished = true
        if (keep) accepted(input.text)
        else canceled()
    }

    implicitHeight: 24
    radius: 6
    color: theme.base
    border.width: 1
    border.color: theme.accent

    TextInput {
        id: input
        anchors.fill: parent
        anchors.leftMargin: 6
        anchors.rightMargin: 6
        verticalAlignment: TextInput.AlignVCenter
        horizontalAlignment: root.centered ? TextInput.AlignHCenter : TextInput.AlignLeft
        text: root.name
        clip: true
        color: root.theme.text
        selectionColor: root.theme.accent
        selectedTextColor: root.theme.textOnAccent
        font.family: root.theme.uiFont
        font.pixelSize: 12

        Component.onCompleted: {
            forceActiveFocus()
            const dot = root.name.lastIndexOf(".")
            select(0, dot > 0 && !root.isDir ? dot : text.length)
        }
        Keys.onReturnPressed: root.finish(true)
        Keys.onEnterPressed: root.finish(true)
        Keys.onEscapePressed: root.finish(false)
        onActiveFocusChanged: {
            if (activeFocus) return
            // The row it's in took the keyboard: the view gives it to its
            // current row when the selection lands there, which can come
            // just after the field showed up (spored makes a new folder
            // before the listing has it). That's not a click elsewhere.
            if (root.rowItem && Window.activeFocusItem === root.rowItem) forceActiveFocus()
            else root.finish(true)
        }
    }
}
