import QtQuick

// Control Center card (design v2): radius 16, card background (almost white
// in light mode) and a very soft accent border.
Rectangle {
    required property Theme theme

    radius: 16
    color: theme.cardBg
    border.width: 1
    border.color: theme.cardBorder
}
