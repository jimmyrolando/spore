import QtQuick
import "../services"

// Notifications in the bar: the bell (Lucide), with a dot if there are
// pending ones (arrived since the Notifications page was last opened) and
// dimmed with Do Not Disturb. Click: that Control Center page, which marks
// them as seen.
BarButton {
    id: root

    property NotificationService service: null

    readonly property int count: service ? service.history.length : 0
    readonly property int unread: service ? service.unread : 0
    readonly property bool dnd: service !== null && service.dnd

    visible: service !== null
    icon: unread > 0 ? "bell-dot" : "bell"
    dim: dnd
    tooltip: (unread > 0 ? unread + " new" + (count > unread ? " · " + count + " total" : "")
            : count === 0 ? "No notifications" : "No new notifications · " + count + " total")
        + (dnd ? "  ·  Do Not Disturb" : "")
}
