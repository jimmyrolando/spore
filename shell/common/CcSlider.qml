import QtQuick

// 0..1 slider (design v2): a 6 track, accent fill and a white 14 knob with
// an accent border. value comes from outside; dragging or clicking emits
// moved(v). The mouse wheel moves it in 5% steps.
Item {
    id: root

    required property Theme theme
    property real value: 0
    property bool dimmed: false
    signal moved(real value)

    implicitHeight: 20
    implicitWidth: 160

    readonly property real shown: Math.max(0, Math.min(1, value))
    readonly property color fill: dimmed ? theme.muted2 : theme.accent

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: root.theme.track

        Rectangle {
            width: parent.width * root.shown
            height: parent.height
            radius: 3
            color: root.fill
        }
    }

    Rectangle {
        width: 14
        height: 14
        radius: 7
        anchors.verticalCenter: parent.verticalCenter
        x: parent.width * root.shown - width / 2
        color: "white"
        border.width: 2
        border.color: root.fill
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        function update(x: real): void {
            root.moved(Math.max(0, Math.min(1, x / width)))
        }
        onPressed: (mouse) => update(mouse.x)
        onPositionChanged: (mouse) => { if (pressed) update(mouse.x) }
        onWheel: (wheel) => root.moved(Math.max(0, Math.min(1, root.value + (wheel.angleDelta.y > 0 ? 0.05 : -0.05))))
    }
}
