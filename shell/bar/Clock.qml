import QtQuick

// Date and time (design 3a): the date muted and the time in weight 500.
// bar.clockFormat is split at the first double space ("ddd MMM dd  hh:mm"
// -> date, time); without a double space, it all goes as the time.
BarButton {
    id: root

    // Qt.formatDateTime format (settings.json: bar.clockFormat).
    property string format: "ddd MMM dd  hh:mm"
    readonly property int split: format.indexOf("  ")
    readonly property string dateFormat: split >= 0 ? format.slice(0, split) : ""
    readonly property string timeFormat: split >= 0 ? format.slice(split).trim() : format

    property date now: new Date()
    hPadding: 8

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    BarText {
        theme: root.theme
        visible: root.dateFormat !== ""
        text: Qt.formatDateTime(root.now, root.dateFormat)
        color: root.theme.soft
    }

    BarText {
        theme: root.theme
        text: Qt.formatDateTime(root.now, root.timeFormat)
        font.weight: Font.Medium
    }

    // The full date.
    tooltip: hovered ? Qt.formatDate(now, "dddd, MMMM d, yyyy") : ""
}
