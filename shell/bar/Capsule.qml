import QtQuick
import "../common"

// Bar group (design 3a "Capsules"): a pill 28 tall, lighter than the bar.
// What's declared inside goes in a row; the buttons (BarButton.qml) are 24
// and get 2 of padding.
Rectangle {
    id: root

    required property Theme theme
    default property alias content: row.data
    property int padding: 2
    property alias spacing: row.spacing

    implicitWidth: row.implicitWidth + padding * 2
    implicitHeight: 28
    radius: height / 2
    color: theme.capsule

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 2
    }
}
