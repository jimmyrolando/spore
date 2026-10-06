import QtQuick
import "../common"

// A system resource in the bar (cpu, memory and gpu widgets): the icon and
// thin vertical bars, one for usage and one for temperature (if there's a
// sensor). The data comes from SystemMonitor.qml, which already measures
// once per second for the whole shell: here it's only drawn. Tooltip with
// the numbers; click: the Control Center's System page (Bar.qml wires it).
BarButton {
    id: root

    // For the tooltip ("CPU", "Memory", "GPU").
    property string name: ""
    // 0..1; -1 = not available (the widget isn't shown).
    property real usage: -1
    // °C; -1 = no sensor (no second bar).
    property real temp: -1
    // Extra tooltip text (e.g. "13.1 / 31.1 GiB").
    property string detail: ""

    // Temperature on the bar: 30 °C empty, 100 °C full. From 80 °C in the
    // warning color, from 90 °C in red.
    readonly property real tempLevel: temp < 0 ? 0 : Math.max(0, Math.min(1, (temp - 30) / 70))
    readonly property color tempColor: temp >= 90 ? theme.danger : temp >= 80 ? theme.warn : theme.ink2

    readonly property bool shown: usage >= 0

    tooltipRows: [{
        label: name,
        value: Math.round(Math.max(0, usage) * 100) + "%"
            + (temp >= 0 ? "  ·  " + Math.round(temp) + "°" : "")
            + (detail !== "" ? "  ·  " + detail : "")
    }]

    component Level: Rectangle {
        property real value: 0
        property color fill: root.theme.ink2

        anchors.verticalCenter: parent.verticalCenter
        width: 4
        height: 14
        radius: 2
        color: root.theme.alpha(root.theme.ink2, 0.18)

        Rectangle {
            anchors.bottom: parent.bottom
            width: parent.width
            height: Math.max(width, parent.height * parent.value)
            radius: 2
            color: parent.fill
        }
    }

    Row {
        spacing: 2

        Level {
            value: Math.max(0, root.usage)
        }
        Level {
            visible: root.temp >= 0
            value: root.tempLevel
            fill: root.tempColor
        }
    }
}
