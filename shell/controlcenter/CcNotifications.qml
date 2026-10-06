import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import "../common"
import "../services"

// Control Center → Notifications (design v2): the history grouped by app and
// filtered by All, Today, Yesterday or Older; Do Not Disturb, and clear
// (what the filter shows). Clicking one runs its default action if the app
// is still alive. Only the list scrolls.
ColumnLayout {
    id: root

    required property Theme theme
    required property NotificationService service

    readonly property string subtitle: service.history.length + " total"

    spacing: 12

    property string filter: "all"

    // With the page open everything counts as seen, including what arrives
    // meanwhile.
    Component.onCompleted: service.markSeen()
    Connections {
        target: root.service
        // callLater: marking it inside `unread`'s change notification changes
        // `unread` again mid-update (binding loop) and Qt drops the change.
        function onUnreadChanged(): void {
            Qt.callLater(root.service.markSeen)
        }
    }

    // Today's and yesterday's boundaries (local midnight).
    readonly property real todayStart: { const d = new Date(); d.setHours(0, 0, 0, 0); return d.getTime() }
    readonly property real yesterdayStart: todayStart - 86400000

    function matches(e: var, f: string): bool {
        return f === "today" ? e.time >= todayStart
            : f === "yesterday" ? e.time >= yesterdayStart && e.time < todayStart
            : f === "older" ? e.time < yesterdayStart
            : true
    }

    readonly property var visibleEntries: service.history.filter(e => matches(e, filter))

    // Groups by app, in the order of each one's most recent.
    readonly property var groups: {
        const byApp = {}
        const order = []
        for (const e of visibleEntries) {
            const app = e.appName || "Notification"
            if (!byApp[app]) {
                byApp[app] = []
                order.push(app)
            }
            byApp[app].push(e)
        }
        return order.map(app => ({ app: app, items: byApp[app] }))
    }

    // Short time: "now", "4m", "1h", "19:42" (yesterday), "Mon" (older).
    function when(t: real): string {
        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (t >= todayStart) return Math.floor(s / 3600) + "h"
        if (t >= yesterdayStart) return Qt.formatTime(new Date(t), "hh:mm")
        return Qt.formatDate(new Date(t), "ddd")
    }

    // A fixed color per app for the initial (from the palette's colors).
    function appColor(name: string): color {
        const ansi = theme.current.ansi
        let h = 0
        for (const ch of name) h = (h * 31 + ch.charCodeAt(0)) >>> 0
        return ansi[1 + h % 6]
    }

    function imageOf(e: var): string {
        return e.image ? (e.image.startsWith("/") ? "file://" + e.image : e.image) : ""
    }

    // All at once (see NotificationService.removeMany).
    function clearEntries(list: var): void {
        service.removeMany(list.map(e => e.key))
    }

    // --- Bar: filters, Do Not Disturb and clear ---
    RowLayout {
        Layout.fillWidth: true
        spacing: 8

        CcSegmented {
            theme: root.theme
            Layout.fillWidth: true
            fill: true
            current: root.filter
            options: [["all", "All"], ["today", "Today"], ["yesterday", "Yesterday"], ["older", "Older"]].map(([v, l]) => {
                const n = root.service.history.filter(e => root.matches(e, v)).length
                return { value: v, label: v === "all" || n === 0 ? l : l + " · " + n }
            })
            onPicked: (v) => root.filter = v
        }

        // "DND" when off, "Silenced" when on (shared with Home).
        Rectangle {
            implicitWidth: dndRow.implicitWidth + 24
            implicitHeight: 34
            radius: 10
            color: root.service.dnd ? root.theme.accent : dndArea.containsMouse ? root.theme.accentHoverStrong : root.theme.accentSoft

            Row {
                id: dndRow
                anchors.centerIn: parent
                spacing: 6
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "moon"
                    size: 14
                    color: root.service.dnd ? root.theme.textOnAccent : root.theme.ink2
                }
                UiText {
                    theme: root.theme
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.service.dnd ? "Silenced" : "DND"
                    color: root.service.dnd ? root.theme.textOnAccent : root.theme.ink2
                    font.pixelSize: 12
                }
            }

            MouseArea {
                id: dndArea
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.service.toggleDnd()
            }
        }

        CcButton {
            theme: root.theme
            size: 34
            label: "Clear all"
            danger: true
            enabled: root.visibleEntries.length > 0
            onClicked: root.clearEntries(root.visibleEntries)
        }
    }

    // Empty: a card with the bell in a circle and a text depending on the filter
    // (and the Do Not Disturb notice, if it's on).
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.visibleEntries.length === 0

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 320)
            spacing: 0

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: root.theme.alpha(root.theme.accent, 0.1)

                Icon {
                    anchors.centerIn: parent
                    name: root.service.dnd ? "moon" : "bell"
                    size: 26
                    stroke: 1.4
                    color: root.theme.accent
                }
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.filter === "all" ? "You're all caught up"
                    : root.filter === "today" ? "Nothing from today"
                    : root.filter === "yesterday" ? "Nothing from yesterday"
                    : "Nothing older"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.filter === "all" || root.service.history.length === 0
                    ? "New notifications will show up here"
                    : root.service.history.length + (root.service.history.length === 1 ? " notification" : " notifications") + " in All"
                color: root.theme.muted
                font.pixelSize: 12
            }

            // Do Not Disturb on: popups don't appear.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 16
                visible: root.service.dnd
                implicitWidth: dndNote.implicitWidth + 24
                implicitHeight: 28
                radius: 14
                color: root.theme.accentSoft

                UiText {
                    id: dndNote
                    theme: root.theme
                    anchors.centerIn: parent
                    text: "Do Not Disturb is on · popups are hidden"
                    color: root.theme.ink2
                    font.pixelSize: 12
                }
            }
        }
    }

    // --- List ---
    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.visibleEntries.length > 0
        contentHeight: groupList.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: groupList
            width: parent.width
            spacing: 12

            Repeater {
                model: root.groups

                Column {
                    id: group
                    required property var modelData
                    width: groupList.width
                    spacing: 6

                    RowLayout {
                        width: parent.width
                        spacing: 8

                        UiText {
                            theme: root.theme
                            Layout.leftMargin: 4
                            text: group.modelData.app
                            font.pixelSize: 13
                            font.weight: Font.DemiBold
                        }
                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: group.modelData.items.length
                            color: root.theme.muted
                            font.pixelSize: 11
                        }
                        UiText {
                            theme: root.theme
                            Layout.rightMargin: 4
                            text: "Clear"
                            color: clearArea.containsMouse ? root.theme.danger : root.theme.muted
                            font.pixelSize: 12
                            MouseArea {
                                id: clearArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.clearEntries(group.modelData.items)
                            }
                        }
                    }

                    ClippingRectangle {
                        width: parent.width
                        height: items.implicitHeight
                        radius: 14
                        color: root.theme.cardBg
                        border.width: 1
                        border.color: root.theme.cardBorder

                        Column {
                            id: items
                            width: parent.width

                            Repeater {
                                model: group.modelData.items

                                Rectangle {
                                    id: row
                                    required property var modelData
                                    required property int index
                                    readonly property string image: root.imageOf(modelData)

                                    width: items.width
                                    height: 60
                                    color: rowArea.containsMouse ? root.theme.alpha(root.theme.accent, 0.04) : "transparent"

                                    // Divider between rows.
                                    Rectangle {
                                        visible: row.index > 0
                                        width: parent.width
                                        height: 1
                                        color: root.theme.alpha(root.theme.accent, 0.1)
                                    }

                                    // Click: the default action (opens the app, the chat...).
                                    MouseArea {
                                        id: rowArea
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: row.modelData.live ? Qt.PointingHandCursor : Qt.ArrowCursor
                                        onClicked: root.service.invoke(row.modelData.key, null)
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        // The notification's image or the app's initial.
                                        ClippingRectangle {
                                            implicitWidth: 40
                                            implicitHeight: 40
                                            radius: 9
                                            color: row.image ? root.theme.track : root.appColor(group.modelData.app)

                                            Image {
                                                anchors.fill: parent
                                                visible: row.image !== ""
                                                source: row.image
                                                sourceSize: Qt.size(80, 80)
                                                fillMode: Image.PreserveAspectCrop
                                                asynchronous: true
                                            }
                                            UiText {
                                                theme: root.theme
                                                anchors.centerIn: parent
                                                visible: row.image === ""
                                                text: group.modelData.app.charAt(0).toUpperCase()
                                                color: root.theme.onColor
                                                font.pixelSize: 15
                                                font.weight: Font.DemiBold
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: 2
                                            UiText {
                                                theme: root.theme
                                                Layout.fillWidth: true
                                                text: row.modelData.summary
                                                font.weight: Font.Medium
                                            }
                                            UiText {
                                                theme: root.theme
                                                Layout.fillWidth: true
                                                visible: text !== ""
                                                // One line: no line breaks or tags.
                                                text: (row.modelData.body || "").replace(/<[^>]*>/g, "").replace(/\s+/g, " ")
                                                textFormat: Text.PlainText
                                                color: root.theme.muted
                                                font.pixelSize: 12
                                            }
                                        }

                                        MonoText {
                                            theme: root.theme
                                            text: root.when(row.modelData.time)
                                            color: root.theme.muted2
                                            font.pixelSize: 11
                                        }

                                        CcButton {
                                            theme: root.theme
                                            size: 26
                                            flat: true
                                            danger: true
                                            icon: "x"
                                            iconSize: 11
                                            onClicked: root.service.remove(row.modelData.key)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
