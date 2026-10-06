import QtQuick
import Quickshell
import "../common/session.js" as Session

// Launcher button: Lucide's rocket. Click: bar.launcher from settings.json
// (rofi by default).
BarButton {
    id: root

    // Program and arguments (settings.json: bar.launcher).
    property var command: ["rofi", "-show", "drun"]

    icon: "rocket"
    tooltip: "Applications"
    // execDetached and not a Process: rofi must not die if the shell reloads
    // while it's open. As an app (session.js): what it starts gets the
    // session's environment.
    onClicked: Quickshell.execDetached(Session.command(root.command))
}
