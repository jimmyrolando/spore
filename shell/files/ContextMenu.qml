import QtQuick
import "../common"

// The right button's menu, inside the window: the actions for what's
// selected, or for the folder. open() shows it at the pointer with a list of
// { action, label, keys, enabled } ("-" draws a line); a choice emits picked().
// Arrows and Enter choose too; Esc, or a click anywhere else, closes it.
Item {
    id: root

    required property Theme theme
    property var items: []
    // The item under the pointer or the arrows (-1: none).
    property int hovered: -1
    signal picked(string action)
    signal closed()

    visible: false

    // The pointer takes the highlight only once it really moves: Qt sends hover
    // events again when the menu appears under a still pointer, and that used
    // to steal what the arrows had chosen (Enter then chose the row under the
    // mouse). Where it first was, and whether it has left it since; after
    // that, every move counts. (Measured from the first point, not from the
    // last event: a slow move comes in steps under a pixel, more so on a
    // scaled screen, and never "moved".)
    property point pointer: Qt.point(-1, -1)
    property bool pointerMoved: false

    function pointerAt(index: int, point: point): void {
        if (!pointerMoved) {
            if (pointer.x < 0) {
                pointer = point
                return
            }
            if (Math.abs(point.x - pointer.x) < 3 && Math.abs(point.y - pointer.y) < 3) return
            pointerMoved = true
        }
        hovered = index
    }

    function open(x: real, y: real, list: var): void {
        items = list
        hovered = -1
        pointer = Qt.point(-1, -1)
        pointerMoved = false
        visible = true
        // Inside the window, even at its edges.
        menu.x = Math.max(4, Math.min(x, width - menu.width - 4))
        menu.y = Math.max(4, Math.min(y, height - menu.height - 4))
        menu.forceActiveFocus()
    }

    function close(): void {
        if (!visible) return
        visible = false
        closed()
    }

    function choose(index: int): void {
        const item = items[index]
        if (!item || item === "-" || item.enabled === false) return
        close()
        picked(item.action)
    }

    function step(delta: int): void {
        for (let i = 0, at = hovered; i < items.length; i++) {
            at = (at + delta + items.length) % items.length
            if (items[at] !== "-" && items[at].enabled !== false) {
                hovered = at
                return
            }
        }
    }

    // Anywhere else: close.
    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.AllButtons
        onPressed: root.close()
    }

    // While it's open, the files behind don't light up under the pointer (a
    // MouseArea lets hover through to what's under it).
    HoverHandler {
        blocking: true
    }

    Rectangle {
        id: menu
        width: 232
        height: column.implicitHeight + 12
        radius: 10
        color: root.theme.base
        border.width: 1
        border.color: root.theme.panelBorder

        Keys.onEscapePressed: root.close()
        Keys.onUpPressed: root.step(-1)
        Keys.onDownPressed: root.step(1)
        Keys.onReturnPressed: root.choose(root.hovered)
        Keys.onEnterPressed: root.choose(root.hovered)

        Column {
            id: column
            x: 6
            y: 6
            width: parent.width - 12

            Repeater {
                model: root.items

                Item {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool line: modelData === "-"
                    readonly property bool usable: !line && modelData.enabled !== false

                    width: column.width
                    height: line ? 9 : 30

                    Rectangle {
                        visible: row.line
                        anchors.centerIn: parent
                        width: parent.width - 12
                        height: 1
                        color: root.theme.alpha(root.theme.accent, 0.12)
                    }

                    Rectangle {
                        visible: !row.line
                        anchors.fill: parent
                        radius: 7
                        color: root.hovered === row.index && row.usable ? root.theme.accentHover : "transparent"

                        UiText {
                            theme: root.theme
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.right: keys.left
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.line ? "" : row.modelData.label
                            color: row.usable ? root.theme.text : root.theme.muted2
                        }
                        MonoText {
                            id: keys
                            theme: root.theme
                            anchors.right: parent.right
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: row.line ? "" : row.modelData.keys || ""
                            color: root.theme.muted2
                            font.pixelSize: 11
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onPositionChanged: (mouse) => root.pointerAt(row.index, mapToItem(root, mouse.x, mouse.y))
                            onClicked: root.choose(row.index)
                        }
                    }
                }
            }
        }
    }
}
