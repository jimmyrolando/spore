import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Notifications
import "../common"
import "../services"

// A notification: icon (or the image the app sends), app and time, title,
// text and the buttons for its actions. Used by the popups
// (NotificationPopups.qml) and the history (CcNotifications.qml).
// Click on the card: the default action, if the app provided one.
Rectangle {
    id: root

    required property Theme theme
    required property NotificationService service
    required property var entry
    // In the popup: ✕ hides it. In the history: the trash can deletes it.
    property bool inHistory: false
    readonly property bool hovered: hover.hovered

    readonly property color muted: theme.muted
    readonly property bool critical: entry.urgency === NotificationUrgency.Critical
    readonly property var actions: entry.live ? entry.live.actions.filter(a => a.identifier !== "default") : []

    implicitHeight: content.implicitHeight + 24
    // The Control Center's card style (design v2).
    radius: 14
    color: theme.cardBg
    border.width: 1
    border.color: critical ? theme.error : theme.cardBorder

    HoverHandler {
        id: hover
    }

    function iconSource(): string {
        const img = entry.image
        if (img) return img.startsWith("/") ? "file://" + img : img
        const icon = entry.appIcon
        if (icon) return icon.startsWith("/") ? "file://" + icon : icon.startsWith("file:") ? icon : Quickshell.iconPath(icon, true)
        const desktop = DesktopEntries.heuristicLookup(entry.appName)
        return desktop && desktop.icon ? Quickshell.iconPath(desktop.icon, true) : ""
    }

    function ago(t: real): string {
        const s = Math.floor((Date.now() - t) / 1000)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + " min ago"
        if (s < 86400) return Math.floor(s / 3600) + " h ago"
        return Qt.formatDateTime(new Date(t), "MMM d, hh:mm")
    }

    // Click: default action (opens the app, the chat, etc.).
    MouseArea {
        anchors.fill: parent
        cursorShape: root.entry.live ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: root.service.invoke(root.entry.key, null)
    }

    ColumnLayout {
        id: content
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            ClippingRectangle {
                Layout.preferredWidth: 36
                Layout.preferredHeight: 36
                Layout.alignment: Qt.AlignTop
                radius: 8
                color: "transparent"

                Image {
                    id: icon
                    anchors.fill: parent
                    source: root.iconSource()
                    sourceSize: Qt.size(72, 72)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }

                Icon {
                    anchors.centerIn: parent
                    visible: icon.status !== Image.Ready
                    name: "bell"
                    size: 22
                    color: root.theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Text {
                    Layout.fillWidth: true
                    text: (root.entry.appName || "Notification") + "  ·  " + root.ago(root.entry.time)
                    color: root.muted
                    font.family: root.theme.uiFont
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.entry.summary
                    color: root.critical ? root.theme.error : root.theme.text
                    font.family: root.theme.uiFont
                    font.pixelSize: 13
                    font.weight: Font.Medium
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }

                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: root.entry.body
                    color: root.theme.text
                    opacity: 0.85
                    font.family: root.theme.uiFont
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                    maximumLineCount: root.inHistory ? 6 : 4
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                }
            }

            CcButton {
                Layout.alignment: Qt.AlignTop
                theme: root.theme
                flat: true
                danger: true
                icon: root.inHistory ? "trash" : "x"
                iconSize: root.inHistory ? 14 : 11
                onClicked: root.inHistory ? root.service.remove(root.entry.key) : root.service.hidePopup(root.entry.key)
            }
        }

        // The app's actions (e.g. "Reply", "Mark as read").
        RowLayout {
            Layout.fillWidth: true
            visible: root.actions.length > 0
            spacing: 6

            Repeater {
                model: root.actions

                CcButton {
                    required property var modelData
                    Layout.fillWidth: true
                    theme: root.theme
                    label: modelData.text || modelData.identifier
                    onClicked: root.service.invoke(root.entry.key, modelData)
                }
            }
        }
    }
}
