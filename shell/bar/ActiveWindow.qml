import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../common"
import "../services"

// The focused window's app: icon and name, taken from the app's .desktop
// (DesktopEntries); if there's no .desktop, the app_id as is. Compositor.qml
// tracks the focused window (no polling).
Item {
    id: root

    required property Theme theme
    // Settings → Bar → Active window (the gear).
    property bool showIcon: true

    property Compositor compositor: null
    readonly property var focusedWindow: compositor ? compositor.focusedWindow : null
    readonly property string appId: focusedWindow ? focusedWindow.appId : ""
    // The window's title (tooltip: the bar only shows the app's name).
    readonly property string title: focusedWindow ? focusedWindow.title : ""
    readonly property bool hasWindow: appId !== ""
    // Looked up again when the .desktop list changes: at shell startup, the
    // first lookup can arrive before they're loaded.
    readonly property var entry: hasWindow && DesktopEntries.applications.values.length >= 0
        ? DesktopEntries.heuristicLookup(appId) : null
    readonly property string name: entry && entry.name ? entry.name : appId
    readonly property string iconSource: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""

    // Same height and padding as a BarButton with text.
    implicitWidth: row.implicitWidth + 16
    implicitHeight: 24

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 6

        IconImage {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.showIcon && root.iconSource !== ""
            source: root.iconSource
            implicitSize: 16
        }

        BarText {
            theme: root.theme
            text: root.name
            // Long names (e.g. an odd app_id) don't push the rest.
            width: Math.min(implicitWidth, 220)
            elide: Text.ElideRight
        }
    }

    HoverHandler {
        id: hover
    }

    // The window's full title.
    BarTooltip {
        theme: root.theme
        hovered: hover.hovered
        text: root.title
    }
}
