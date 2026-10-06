import QtQuick
import "../common"

// Bar button (design 3a, enlarged): 24 tall, radius 12, soft accent
// background on hover. A line icon (Icon.qml) and, optionally, a text next
// to it; without text it's square. `danger` tints the hover red (power off)
// and `active` keeps it highlighted (e.g. an open popover).
Rectangle {
    id: root

    required property Theme theme
    property string icon: ""
    property real iconSize: 15
    // Every bar icon with the same size and stroke.
    property real iconStroke: 1.2
    property string label: ""
    property string tooltip: ""
    property var tooltipRows: []
    property bool danger: false
    property bool active: false
    // Dimmed (e.g. muted volume, bluetooth off).
    property bool dim: false
    // Custom content instead of icon + text (clock, meters).
    default property alias content: custom.data
    property int hPadding: 7
    signal clicked()
    signal wheel(int delta)

    readonly property bool hovered: area.containsMouse
    readonly property color fg: danger && hovered ? theme.danger : dim ? theme.muted2 : theme.ink2
    readonly property bool square: label === "" && custom.children.length === 0

    implicitHeight: 24
    implicitWidth: square ? 24 : row.implicitWidth + hPadding * 2
    radius: 12
    color: active ? theme.alpha(theme.accent, 0.16)
        : hovered ? (danger ? theme.dangerHover : theme.accentHover)
        : "transparent"

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 5

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.icon !== ""
            name: root.icon
            size: root.iconSize
            stroke: root.iconStroke
            color: root.fg
        }

        BarText {
            theme: root.theme
            visible: root.label !== ""
            text: root.label
            color: root.dim ? root.theme.muted2 : root.theme.text
        }

        Row {
            id: custom
            anchors.verticalCenter: parent.verticalCenter
            visible: children.length > 0
            spacing: 8
        }
    }

    BarTooltip {
        theme: root.theme
        hovered: root.hovered
        text: root.tooltip
        rows: root.tooltipRows
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        // On press and not on release: with a panel open, the click moves focus from
        // the panel to the bar and Qt cancels the click in progress (pressed ->
        // canceled, with no released), so it took a second click.
        onPressed: root.clicked()
        onWheel: (event) => root.wheel(event.angleDelta.y)
    }
}
