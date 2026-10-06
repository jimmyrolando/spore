import QtQuick
import QtQuick.Shapes
import "lucide.js" as Lucide

// A Lucide icon (lucide.js, 24x24 grid, generated with tools/lucide.mjs)
// drawn with a rounded stroke, scaled to `size`. `filled` fills it
// (play/pause); lucide.js's brand logos (Simple Icons) are always filled.
//
// Optical centering: it's the drawing (its boundingRect) that's centered,
// not the grid, so an asymmetric icon (the cup with its handle on one side)
// doesn't look off-center inside a round button.
Item {
    id: root

    property string name: ""
    property real size: 16
    property color color: "black"
    property real stroke: 1.5
    property bool filled: false

    readonly property string path: Lucide.paths[name] ?? ""
    // Brand logos (Simple Icons, in lucide.js): filled and with no stroke.
    readonly property bool brand: Lucide.filled[name] === true

    implicitWidth: size
    implicitHeight: size

    Shape {
        id: shape
        width: root.size
        height: root.size
        // Shifts the drawing so its center sits at the icon's center.
        readonly property rect bounds: boundingRect
        x: bounds.width > 0 ? root.size / 2 - (bounds.x + bounds.width / 2) : 0
        y: bounds.height > 0 ? root.size / 2 - (bounds.y + bounds.height / 2) : 0
        // CurveRenderer: smooth curves without multisampling.
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            // scale scales the path, not the stroke width.
            scale: Qt.size(root.size / 24, root.size / 24)
            strokeColor: root.brand ? "transparent" : root.color
            strokeWidth: root.brand ? 0 : root.stroke
            fillColor: root.filled || root.brand ? root.color : "transparent"
            // As in SVG: with the even-odd rule (Qt's default), overlapping pieces in a
            // logo cancel out and leave gaps.
            fillRule: ShapePath.WindingFill
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin

            PathSvg { path: root.path }
        }
    }
}
