import QtQuick

// Section title (design v2): 11/600 in the accent, uppercase, spaced out.
// Plain text, never markup (see UiText.qml).
Text {
    required property Theme theme
    color: theme.accent
    font.family: theme.uiFont
    font.pixelSize: 11
    font.weight: Font.DemiBold
    font.capitalization: Font.AllUppercase
    font.letterSpacing: 0.9
    textFormat: Text.PlainText
}
