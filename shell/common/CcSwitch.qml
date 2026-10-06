import QtQuick

// On/off switch (design v2): 38x22, white 16 knob. Emits toggled; the user
// of it changes the real value (checked comes from outside).
Rectangle {
    id: root

    required property Theme theme
    property bool checked: false
    signal toggled()

    implicitWidth: 38
    implicitHeight: 22
    radius: 11
    color: checked ? theme.accent : theme.switchOff
    Behavior on color { ColorAnimation { duration: 120 } }

    Rectangle {
        width: 16
        height: 16
        radius: 8
        anchors.verticalCenter: parent.verticalCenter
        x: root.checked ? parent.width - width - 3 : 3
        color: "white"
        Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.toggled()
    }
}
