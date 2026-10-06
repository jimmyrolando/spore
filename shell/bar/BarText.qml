import QtQuick
import "../common"

// Bar text centered by eye: a Text's box includes the font's air above and
// below (ascent/descent), so centering the box leaves numbers higher than
// the icons. Here the real height of a digit (tightBoundingRect of "0") is
// centered in the parent's height. It goes in a Row: it uses `y`, not
// anchors. Plain text, never markup (see UiText.qml).
Text {
    id: root

    required property Theme theme

    color: theme.text
    font.family: theme.barFont
    font.pixelSize: 13
    textFormat: Text.PlainText

    FontMetrics {
        id: metrics
        font: root.font
    }
    // Relative to the baseline: negative y (upward) and height.
    readonly property rect digit: metrics.tightBoundingRect("0")

    y: parent ? Math.round(parent.height / 2 - baselineOffset - digit.y - digit.height / 2) : 0
}
