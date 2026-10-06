import QtQuick
import QtQuick.Layouts
import "../common"
import "ccutil.js" as CcUtil

// Control Center → Calendar (design v2): the month with today highlighted,
// arrows and "Today", and at the bottom the chosen day (day of the year,
// ISO week and how long until or since). There are no events: the shell
// isn't connected to any calendar.
ColumnLayout {
    id: root

    required property Theme theme

    readonly property string subtitle: "Week " + CcUtil.isoWeek(today)

    spacing: 12

    property date today: new Date()
    // Month shown (day 1) and chosen day.
    property date month: new Date(today.getFullYear(), today.getMonth(), 1)
    property date selected: today

    // Day change at midnight.
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: root.today = new Date()
    }

    // First day of the week from the system's locale (0 = Sunday).
    readonly property int firstDay: Qt.locale().firstDayOfWeek % 7

    function sameDay(a: date, b: date): bool {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate()
    }

    // 42 days (6 weeks) from the start of the week of day 1.
    readonly property var days: {
        const first = new Date(month.getFullYear(), month.getMonth(), 1)
        const offset = (first.getDay() - firstDay + 7) % 7
        const list = []
        for (let i = 0; i < 42; i++)
            list.push(new Date(month.getFullYear(), month.getMonth(), 1 - offset + i))
        return list
    }

    function shiftMonth(delta: int): void {
        month = new Date(month.getFullYear(), month.getMonth() + delta, 1)
    }

    function dayOfYear(d: date): int {
        return Math.round((new Date(d.getFullYear(), d.getMonth(), d.getDate()) - new Date(d.getFullYear(), 0, 1)) / 86400000) + 1
    }

    // "Today", "Tomorrow", "In 3 days", "2 days ago"...
    function relative(d: date): string {
        const a = new Date(today.getFullYear(), today.getMonth(), today.getDate())
        const b = new Date(d.getFullYear(), d.getMonth(), d.getDate())
        const n = Math.round((b - a) / 86400000)
        if (n === 0) return "Today"
        if (n === 1) return "Tomorrow"
        if (n === -1) return "Yesterday"
        return n > 0 ? "In " + n + " days" : -n + " days ago"
    }

    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 4

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.month, "MMMM yyyy")
                    font.pixelSize: 15
                    font.weight: Font.DemiBold
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    icon: "chevron-left"
                    iconSize: 13
                    onClicked: root.shiftMonth(-1)
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    label: "Today"
                    onClicked: {
                        root.month = new Date(root.today.getFullYear(), root.today.getMonth(), 1)
                        root.selected = root.today
                    }
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    icon: "chevron-right"
                    iconSize: 13
                    onClicked: root.shiftMonth(1)
                }
            }

            GridLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                columns: 7
                rowSpacing: 4
                columnSpacing: 4

                // SUN ... SAT (from the locale's first day of the week).
                Repeater {
                    model: 7
                    UiText {
                        required property int index
                        theme: root.theme
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        Layout.preferredHeight: 26
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                        text: Qt.locale("en_US").dayName((root.firstDay + index) % 7, Locale.ShortFormat).toUpperCase()
                        color: root.theme.accent
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        font.letterSpacing: 0.66
                    }
                }

                Repeater {
                    model: root.days

                    Rectangle {
                        id: cell
                        required property var modelData
                        readonly property bool isToday: root.sameDay(modelData, root.today)
                        readonly property bool isSelected: root.sameDay(modelData, root.selected)
                        readonly property bool inMonth: modelData.getMonth() === root.month.getMonth()

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: 12
                        color: isToday ? root.theme.accent : isSelected ? root.theme.accentSoft : "transparent"
                        border.width: isSelected && !isToday ? 1.5 : cellArea.containsMouse ? 1 : 0
                        border.color: root.theme.accent

                        MonoText {
                            theme: root.theme
                            anchors.centerIn: parent
                            text: cell.modelData.getDate()
                            color: cell.isToday ? root.theme.textOnAccent : cell.inMonth ? root.theme.text : root.theme.muted2
                            font.pixelSize: 14
                            font.weight: cell.isToday ? Font.DemiBold : Font.Normal
                        }

                        MouseArea {
                            id: cellArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.selected = cell.modelData
                                if (!cell.inMonth) root.month = new Date(cell.modelData.getFullYear(), cell.modelData.getMonth(), 1)
                            }
                        }
                    }
                }
            }

            // --- Chosen day: a band at the bottom of the month ---
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 1
                color: root.theme.cardBorder
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                UiText {
                    theme: root.theme
                    text: Qt.locale("en_US").dayName(root.selected.getDay())
                    color: root.theme.accent
                    font.weight: Font.DemiBold
                }
                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: Qt.formatDate(root.selected, "MMMM d, yyyy")
                    font.weight: Font.DemiBold
                }
                MonoText {
                    theme: root.theme
                    text: "Day " + root.dayOfYear(root.selected) + " · Week " + CcUtil.isoWeek(root.selected) + " · " + root.relative(root.selected)
                    color: root.theme.muted
                }
            }
        }
    }
}
