import QtQuick
import Quickshell
import "../common"
import "../services"

// This monitor's workspaces (niri gives each monitor its own; design 3a):
// pills 8 tall; the one it shows is 26 wide (fully colored if this monitor
// has the focus), the others 8, stronger if they have windows. Click any to
// go to it.
Row {
    id: root
    spacing: 5

    required property Theme theme
    property Compositor compositor: null
    // The monitor's output name ("DP-4"). Empty, or none of them on it (a name
    // that doesn't match): all of them.
    property string output: ""
    readonly property var shown: {
        const all = compositor ? compositor.workspaces : []
        const mine = all.filter(w => w.output === output)
        return mine.length ? mine : all
    }

    Repeater {
        model: root.shown

        Rectangle {
            id: ws
            required property var modelData
            readonly property bool focused: modelData.focused
            // The one this monitor shows (with all of them: the focused one).
            readonly property bool current: root.output && root.shown.every(w => w.output === root.output) ? modelData.active : focused
            readonly property bool occupied: modelData.occupied

            anchors.verticalCenter: parent.verticalCenter
            width: current ? 26 : 8
            height: 8
            radius: 4
            color: focused ? root.theme.ink2
                : current ? root.theme.alpha(root.theme.ink2, 0.6)
                : root.theme.alpha(root.theme.ink2, area.containsMouse ? 0.7 : occupied ? 0.45 : 0.2)

            Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

            BarTooltip {
                theme: root.theme
                hovered: area.containsMouse
                text: "Workspace " + ws.modelData.index + (ws.modelData.name ? " · " + ws.modelData.name : "")
            }

            MouseArea {
                id: area
                // Bigger than the pill: 8px is hard to hit.
                anchors.fill: parent
                anchors.margins: -4
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                // On press: with a panel open, Qt cancels the click on release (see
                // BarButton.qml).
                onPressed: root.compositor.focusWorkspace(ws.modelData)
            }
        }
    }
}
