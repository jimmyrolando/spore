import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Notifications
import "../common"
import "../services"

// Notification popups: top right, below the bar, newest on top. Each one
// goes away by itself (5 s or what the app asks for; critical ones stay
// until closed); while hovered, the timer pauses.
PanelWindow {
    id: root

    required property Theme theme
    required property NotificationService service
    property int topOffset: 36

    anchors { top: true; right: true }
    margins { top: topOffset + 8; right: 16 }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: 400
    implicitHeight: Math.max(1, column.implicitHeight)
    color: "transparent"
    visible: service.popups.length > 0

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-notifications"
    // No keyboard: a notification doesn't steal focus from what you're using.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    // Column and not ColumnLayout: with the layout, the window's height ended up
    // ~0 (only the card's border showed).
    Column {
        id: column
        width: parent.width
        spacing: 8

        Repeater {
            // ScriptModel and not the array directly: when one arrives or leaves, the
            // other cards are kept (with the array they were all recreated and each
            // one's timer restarted, so they stayed too long).
            model: ScriptModel {
                values: root.service.popups
            }

            NotificationCard {
                id: card
                required property string modelData
                readonly property var found: root.service.find(modelData)

                width: column.width
                visible: found !== null
                theme: root.theme
                service: root.service
                entry: found ?? { key: "", appName: "", appIcon: "", image: "", summary: "", body: "", urgency: 1, time: 0, live: null }
                // Popup: solid background (the history's is more transparent).
                color: root.theme.base

                // How long it stays: what the app asks for (ms), otherwise 5 s. Critical:
                // until closed.
                readonly property int timeout: {
                    if (entry.urgency === NotificationUrgency.Critical) return 0
                    const t = entry.live ? entry.live.expireTimeout : -1
                    return t > 0 ? (t < 100 ? t * 1000 : t) : 5000
                }

                Timer {
                    interval: card.timeout
                    running: card.timeout > 0 && !card.hovered
                    onTriggered: root.service.hidePopup(card.modelData)
                }
            }
        }
    }
}
