import QtQuick

// Thin progress bar (design v2: 4 tall, accent track and fill).
Rectangle {
    required property Theme theme
    property real value: 0

    implicitHeight: 4
    radius: height / 2
    color: theme.track
    clip: true

    Rectangle {
        width: parent.width * Math.max(0, Math.min(1, parent.value))
        height: parent.height
        radius: parent.radius
        color: parent.theme.accent
    }
}
