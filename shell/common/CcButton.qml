import QtQuick

// Control Center button (design v2). Secondary by default: 28 tall, radius
// 8, soft accent background and ink-2 text at 12. With `icon` (from
// lucide.js) and no `label` it's square. `primary`: solid accent (e.g.
// play); `danger`: the hover turns red (delete, forget); `flat`: no
// background until hover; `mono`: the text in the monospace font.
Rectangle {
    id: root

    required property Theme theme
    property string icon: ""
    property real iconSize: 14
    property bool iconFilled: false
    property string label: ""
    property bool primary: false
    property bool danger: false
    property bool flat: false
    property bool mono: false
    // Accent text with no background (e.g. "Connect" in a list).
    property bool link: false
    property bool enabled: true
    property int size: 28
    // Long text (e.g. a device name): truncated with "…".
    property real maxLabelWidth: 1000
    signal clicked()

    readonly property bool hovered: area.containsMouse
    readonly property color fg: primary ? theme.textOnAccent
        : link ? theme.accent
        : danger && hovered ? theme.danger
        : theme.ink2

    implicitWidth: label ? content.implicitWidth + 22 : size
    implicitHeight: size
    radius: size >= 32 ? 9 : 8
    opacity: enabled ? 1 : 0.4
    color: primary ? theme.accent
        : danger && hovered ? theme.dangerHover
        : hovered && enabled ? theme.accentHoverStrong
        : flat || link ? "transparent" : theme.accentSoft

    Row {
        id: content
        anchors.centerIn: parent
        spacing: 6

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            size: root.iconSize
            filled: root.iconFilled
            color: root.fg
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.label !== ""
            text: root.label
            width: Math.min(implicitWidth, root.maxLabelWidth)
            elide: Text.ElideRight
            color: root.fg
            font.family: root.mono ? root.theme.fontFamily : root.theme.uiFont
            font.pixelSize: 12
            // A device's name, a notification's action: as it is (see UiText.qml).
            textFormat: Text.PlainText
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.enabled) root.clicked()
    }
}
