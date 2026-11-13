import QtQuick

// A battery drawn with its charge, as on macOS: the outline, the terminal and
// a fill as long as the charge. Lucide's battery icons only have four levels.
// The bar uses it at 22x11; the Control Center's Battery page, larger.
Item {
    id: root

    // 0..1.
    property real level: 0
    property color color: "black"
    property color fillColor: color
    property real bodyWidth: 22
    property real bodyHeight: 11
    readonly property real line: Math.max(1, bodyHeight / 9)
    // Between the outline and the fill.
    readonly property real gap: line * 1.4

    implicitWidth: bodyWidth + line * 2.2
    implicitHeight: bodyHeight

    Rectangle {
        width: root.bodyWidth
        height: root.bodyHeight
        radius: root.bodyHeight * 0.28
        color: "transparent"
        border.width: root.line
        border.color: root.color
    }

    Rectangle {
        x: root.line + root.gap
        y: root.line + root.gap
        // A sliver even near 0, so an empty battery still reads as one.
        width: Math.max(root.line, (root.bodyWidth - (root.line + root.gap) * 2) * Math.max(0, Math.min(1, root.level)))
        height: root.bodyHeight - (root.line + root.gap) * 2
        radius: Math.max(1, root.bodyHeight * 0.12)
        color: root.fillColor
    }

    // The terminal.
    Rectangle {
        x: root.bodyWidth + root.line * 0.6
        anchors.verticalCenter: parent.verticalCenter
        width: root.line * 1.6
        height: root.bodyHeight * 0.38
        radius: width / 2
        color: root.color
    }
}
