import QtQuick
import QtQuick.Shapes
import "brand.js" as Brand

// The Spore mark: three thin mushrooms growing from a single line of soil
// (the "Spore Shell brand" handoff). The design's geometry on a 64x64 grid,
// 3-wide strokes with round caps. Colors:
//  - color (default): the brand's fixed colors (brand.js), not the
//    palette's: the center mushroom in Spore, the side ones in Mycel and
//    the soil in Ink on a light background or Bone on a dark one.
//  - mono: everything in `color`, the sides at 45% (for the bar or over
//    photos).
Item {
    id: root

    required property Theme theme
    property real size: 64
    property bool mono: false
    property color color: theme.ink2

    readonly property real k: size / 64
    readonly property color center: mono ? color : Brand.colors.spore
    readonly property color side: mono ? color : Brand.colors.mycel
    readonly property color ground: mono ? color : (theme.isDark ? Brand.colors.bone : Brand.colors.ink)

    implicitWidth: size
    implicitHeight: size

    // Ellipse as a path (two arcs).
    function ellipse(cx: real, cy: real, rx: real, ry: real): string {
        return `M${cx - rx} ${cy}a${rx} ${ry} 0 1 0 ${2 * rx} 0a${rx} ${ry} 0 1 0 ${-2 * rx} 0z`
    }

    component Stroke: ShapePath {
        scale: Qt.size(root.k, root.k)
        strokeWidth: 3 * root.k
        fillColor: "transparent"
        capStyle: ShapePath.RoundCap
        joinStyle: ShapePath.RoundJoin
    }

    component Fill: ShapePath {
        scale: Qt.size(root.k, root.k)
        strokeColor: "transparent"
        strokeWidth: 0
    }

    // Sides: on their own layer, so in mono the 45% applies to the whole
    // (stem and cap don't get darker where they touch).
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        opacity: root.mono ? 0.45 : 1
        layer.enabled: root.mono
        layer.samples: 4

        Stroke {
            strokeColor: root.side
            PathSvg { path: "M20 22c1 12 5 22 10 32" }
        }
        Stroke {
            strokeColor: root.side
            PathSvg { path: "M44 22c-1 12-5 22-10 32" }
        }
        Fill {
            fillColor: root.side
            PathSvg { path: root.ellipse(19, 20, 6, 4.5) }
        }
        Fill {
            fillColor: root.side
            PathSvg { path: root.ellipse(45, 20, 6, 4.5) }
        }
    }

    // Center and soil.
    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        Stroke {
            strokeColor: root.center
            PathSvg { path: "M32 16v38" }
        }
        Fill {
            fillColor: root.center
            PathSvg { path: root.ellipse(32, 13, 7, 5.5) }
        }
        Stroke {
            strokeColor: root.ground
            PathSvg { path: "M24 54h16" }
        }
    }
}
