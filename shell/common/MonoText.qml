import QtQuick

// Numbers, times and IPs (JetBrains Mono) in the Control Center. Plain
// text, never markup (see UiText.qml).
Text {
    required property Theme theme
    color: theme.text
    font.family: theme.fontFamily
    font.pixelSize: 12
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
