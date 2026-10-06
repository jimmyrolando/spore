import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import "../common"

// The open apps ("apps" widget): one icon per app, even with several
// windows. Tooltip with the name; click takes you to that app, or if it has
// several windows, opens a list to pick one. Collapsed, it shows only the
// focused one and a button to expand.
//
// The windows come from ToplevelManager (the wlr-foreign-toplevel protocol,
// which niri supports): it only reports each change, with no processes or
// queries.
Item {
    id: root

    required property Theme theme
    // All or only the focused one (the ‹ › button toggles it).
    property bool expanded: true

    readonly property var windows: ToplevelManager.toplevels.values
    // One entry per app, in the order they were opened:
    // { appId, windows: [Toplevel], active }.
    readonly property var apps: {
        const out = []
        for (const w of windows) {
            const id = w.appId || w.title || "?"
            let app = out.find(a => a.appId === id)
            if (!app) {
                app = { appId: id, windows: [], active: false }
                out.push(app)
            }
            app.windows.push(w)
            if (w.activated) app.active = true
        }
        return out
    }
    // Collapsed: the focused one (or the first, if none is).
    readonly property var shownApps: expanded || apps.length === 0 ? apps : [apps.find(a => a.active) ?? apps[0]]

    readonly property bool shown: apps.length > 0

    implicitWidth: row.implicitWidth
    implicitHeight: 24

    // The open window list: which app (appId, so it updates if windows open or
    // close) and under which icon.
    property string menuAppId: ""
    property Item menuAnchor: null
    readonly property var menuApp: apps.find(a => a.appId === menuAppId) ?? null

    // Click: a single window, go to it; several, the list (another click closes
    // it).
    function appClicked(app: var, item: Item): void {
        if (app.windows.length === 1) {
            app.windows[0].activate()
            return
        }
        // The click that closed the list (outside, on this icon) doesn't open it
        // again.
        if (Date.now() - menu.closedAt < 250 && menu.lastAppId === app.appId) return
        menuAnchor = item
        menuAppId = menuAppId === app.appId ? "" : app.appId
    }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        spacing: 2

        Repeater {
            model: root.shownApps

            Rectangle {
                id: appButton
                required property var modelData
                // Looked up again when the .desktop list changes: when the shell starts
                // with windows open, the first lookup arrives before they're loaded.
                readonly property var entry: DesktopEntries.applications.values.length >= 0
                    ? DesktopEntries.heuristicLookup(modelData.appId) : null
                readonly property string name: entry && entry.name ? entry.name : modelData.appId
                readonly property string iconSource: entry && entry.icon ? Quickshell.iconPath(entry.icon, true) : ""

                width: 24
                height: 24
                radius: 12
                readonly property bool menuOpen: root.menuAppId === modelData.appId
                color: modelData.active || menuOpen ? root.theme.alpha(root.theme.accent, 0.16)
                    : appArea.containsMouse ? root.theme.accentHover : "transparent"

                IconImage {
                    anchors.centerIn: parent
                    visible: appButton.iconSource !== ""
                    source: appButton.iconSource
                    implicitSize: 16
                }
                // No theme icon: a generic one.
                Icon {
                    anchors.centerIn: parent
                    visible: appButton.iconSource === ""
                    name: "app-window"
                    size: 15
                    stroke: 1.2
                    color: root.theme.ink2
                }

                MouseArea {
                    id: appArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onPressed: root.appClicked(appButton.modelData, appButton)
                }

                BarTooltip {
                    theme: root.theme
                    hovered: appArea.containsMouse && !appButton.menuOpen
                    text: appButton.name + (appButton.modelData.windows.length > 1 ? "  ·  " + appButton.modelData.windows.length + " windows" : "")
                }
            }
        }

        // Collapse / expand (only with more than one app).
        BarButton {
            theme: root.theme
            visible: root.apps.length > 1
            icon: root.expanded ? "chevron-left" : "chevron-right"
            iconSize: 13
            tooltip: root.expanded ? "Show only the focused app" : "Show all " + root.apps.length + " apps"
            onClicked: root.expanded = !root.expanded
        }
    }

    // --- An app's window list ---
    PopupWindow {
        id: menu
        property real closedAt: 0
        property string lastAppId: ""

        visible: root.menuApp !== null && root.menuAnchor !== null
        onVisibleChanged: if (!visible) {
            closedAt = Date.now()
            lastAppId = root.menuAppId
            root.menuAppId = ""
        }
        // A click outside closes it.
        grabFocus: true

        anchor.item: root.menuAnchor
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        // Below the bar's edge, not the icon's (see BarTooltip.qml).
        anchor.margins.bottom: -(visible && root.menuAnchor && root.menuAnchor.Window.window
            ? Math.max(0, root.menuAnchor.Window.height - root.menuAnchor.mapToItem(null, 0, root.menuAnchor.height).y) + 6
            : 6)
        implicitWidth: 300
        implicitHeight: list.implicitHeight + 16
        color: "transparent"

        Rectangle {
            anchors.fill: parent
            radius: 12
            color: root.theme.base
            border.width: 1
            border.color: root.theme.alpha(root.theme.accent, 0.18)

            Column {
                id: list
                anchors.fill: parent
                anchors.margins: 8
                spacing: 2

                Repeater {
                    model: root.menuApp ? root.menuApp.windows : []

                    Rectangle {
                        id: windowRow
                        required property var modelData
                        width: list.width
                        height: 32
                        radius: 8
                        color: rowArea.containsMouse ? root.theme.accentHover
                            : modelData.activated ? root.theme.alpha(root.theme.accent, 0.12) : "transparent"

                        // The focused one: an accent dot.
                        Rectangle {
                            anchors.left: parent.left
                            anchors.leftMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            width: 6
                            height: 6
                            radius: 3
                            color: root.theme.accent
                            visible: windowRow.modelData.activated
                        }

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 24
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: windowRow.modelData.title || root.menuAppId
                            color: root.theme.text
                            font.family: root.theme.uiFont
                            font.pixelSize: 13
                            elide: Text.ElideRight
                            // A web page's title, as it is (see UiText.qml).
                            textFormat: Text.PlainText
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                windowRow.modelData.activate()
                                root.menuAppId = ""
                            }
                        }
                    }
                }
            }
        }
    }
}
