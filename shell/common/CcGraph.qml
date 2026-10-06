import QtQuick

// Filled line graph (the Control Center's System tab): `values` is the
// history (0..1, newest on the right); `values2`, an optional second line
// with no fill (e.g. network upload and download).
Canvas {
    id: root

    property var values: []
    property var values2: []
    property color color: "white"
    property color color2: "white"
    property real lineWidth: 1.6
    // Flat fill under the first line (design: accent at 12-14%).
    property real fillAlpha: 0.12
    // Number of samples that fit across the width.
    property int samples: 60

    onValuesChanged: requestPaint()
    onValues2Changed: requestPaint()
    onColorChanged: requestPaint()
    onColor2Changed: requestPaint()
    onWidthChanged: requestPaint()
    onHeightChanged: requestPaint()

    function drawLine(ctx: var, list: var, c: color, fill: bool): void {
        list = list.slice(-samples)
        if (list.length < 2) return
        const step = width / (samples - 1)
        const x0 = width - (list.length - 1) * step
        const y = v => height - 2 - Math.max(0, Math.min(1, v)) * (height - 4)
        ctx.beginPath()
        ctx.moveTo(x0, y(list[0]))
        for (let i = 1; i < list.length; i++)
            ctx.lineTo(x0 + i * step, y(list[i]))
        ctx.strokeStyle = c
        ctx.lineWidth = lineWidth
        ctx.lineJoin = "round"
        ctx.stroke()
        if (!fill) return
        ctx.lineTo(width, height)
        ctx.lineTo(x0, height)
        ctx.closePath()
        ctx.fillStyle = Qt.rgba(c.r, c.g, c.b, fillAlpha)
        ctx.fill()
    }

    onPaint: {
        const ctx = getContext("2d")
        ctx.reset()
        drawLine(ctx, values, color, true)
        // The second one without fill: otherwise it covers the first.
        drawLine(ctx, values2, color2, false)
    }
}
