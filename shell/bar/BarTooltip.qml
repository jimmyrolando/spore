import QtQuick
import QtQuick.Layouts
import Quickshell
import "../common"

// Bar tooltip: after a moment of hovering, a small panel below the element
// with its details. It goes inside the element (target, the parent by
// default) and the element passes it `hovered` (from a HoverHandler). It's
// invisible and has no size: that way it takes no space in a Row.
//
//   rows: [{ label: "Volume", value: "50%" }, ...]  -> two-column table
//   text: "Settings"                                -> a single line
Item {
    id: root

    required property Theme theme
    property bool hovered: false
    property var rows: []
    property string text: ""

    property Item target: parent
    visible: false

    property bool shown: false

    Timer {
        id: delay
        interval: 400
        onTriggered: root.shown = true
    }

    onHoveredChanged: {
        if (hovered) {
            delay.restart()
        } else {
            delay.stop()
            shown = false
        }
    }

    PopupWindow {
        anchor.item: root.target
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        // Below the bar's edge (not the icon's): the distance to the bottom of the
        // window plus 8. Margins shrink the anchoring rectangle, so a negative one
        // at the bottom extends it downward.
        anchor.margins.bottom: -(root.shown && root.target && root.target.Window.window
            ? Math.max(0, root.target.Window.height - root.target.mapToItem(null, 0, root.target.height).y) + 8
            : 8)
        visible: root.shown && (root.rows.length > 0 || root.text !== "")
        implicitWidth: box.implicitWidth
        implicitHeight: box.implicitHeight
        color: "transparent"

        Rectangle {
            id: box
            implicitWidth: Math.max(content.implicitWidth, single.implicitWidth) + 24
            implicitHeight: (root.rows.length > 0 ? content.implicitHeight : single.implicitHeight) + 16
            radius: 8
            color: root.theme.base
            border.width: 1
            border.color: Qt.tint(root.theme.base, Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.15))

            // Both as they are, never markup (see UiText.qml): a window's title
            // is the web page's, a drive's label is the drive's. Laid out even
            // while the tooltip is hidden, so markup in them acted right away.
            Text {
                id: single
                anchors.centerIn: parent
                visible: root.rows.length === 0
                text: root.text
                color: root.theme.text
                font.family: root.theme.uiFont
                font.pixelSize: 13
                textFormat: Text.PlainText
            }

            GridLayout {
                id: content
                anchors.centerIn: parent
                visible: root.rows.length > 0
                columns: 2
                columnSpacing: 24
                rowSpacing: 4

                Repeater {
                    // Flattened: label, value, label, value...
                    model: Array.from(root.rows).reduce((acc, r) => acc.concat([{ text: r.label, label: true }, { text: String(r.value), label: false }]), [])

                    Text {
                        required property var modelData
                        Layout.alignment: modelData.label ? Qt.AlignLeft : Qt.AlignRight
                        Layout.maximumWidth: 280
                        text: modelData.text
                        color: modelData.label ? root.theme.accent : root.theme.text
                        font.family: modelData.label ? root.theme.uiFont : root.theme.fontFamily
                        font.pixelSize: 13
                        elide: Text.ElideRight
                        textFormat: Text.PlainText
                    }
                }
            }
        }
    }
}
