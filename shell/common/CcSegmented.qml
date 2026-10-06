import QtQuick

// Segmented control (design v2): a container with padding 3 and radius 10;
// items 28 tall, the active one in white (card) with strong text.
// options: [{ value, label }]; emits picked(value).
Rectangle {
    id: root

    required property Theme theme
    property var options: []
    property var current
    // All the same width, sharing the control's width.
    property bool fill: false
    signal picked(var value)

    implicitHeight: 34
    implicitWidth: row.implicitWidth + 6
    radius: 10
    color: root.theme.alpha(root.theme.accent, root.theme.isDark ? 0.14 : 0.09)

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2

        Repeater {
            model: root.options

            Rectangle {
                required property var modelData
                readonly property bool selected: modelData.value === root.current

                width: root.fill ? (root.width - 6 - 2 * (root.options.length - 1)) / root.options.length : label.implicitWidth + 24
                height: 28
                radius: 8
                color: selected ? root.theme.cardBg : "transparent"

                Text {
                    id: label
                    anchors.centerIn: parent
                    text: parent.modelData.label
                    color: parent.selected ? root.theme.text : root.theme.muted
                    font.family: root.theme.uiFont
                    font.pixelSize: 12
                    font.weight: parent.selected ? Font.Medium : Font.Normal
                    textFormat: Text.PlainText
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.picked(parent.modelData.value)
                }
            }
        }
    }
}
