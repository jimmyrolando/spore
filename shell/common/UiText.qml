import QtQuick

// Interface text (Noto Sans) in the Control Center.
//
// Always plain text, never markup. What it shows often comes from outside
// (file names, window titles, networks, devices, notifications), and Qt's
// default format (AutoText) reads a "<img src=…>" in it as an image to
// fetch from the network: a web page's title made the shell send a request.
// Spore's other texts (MonoText, BarText, CcButton…) do the same.
Text {
    required property Theme theme
    color: theme.text
    font.family: theme.uiFont
    font.pixelSize: 13
    elide: Text.ElideRight
    textFormat: Text.PlainText
}
