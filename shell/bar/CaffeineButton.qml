import QtQuick

// Idle inhibitor ("caffeine"; CaffeineButton and not IdleInhibitor, which is
// a Quickshell.Wayland type): while it's on, nothing suspends, and the
// screen only locks and turns off after a long while (Idle.qml). The state
// lives in shell.qml (shared with the Control Center's tile); this only
// shows it and requests the change.
BarButton {
    property bool inhibiting: false

    icon: "coffee"
    active: inhibiting
    tooltip: inhibiting ? "Caffeine on · no suspending" : "Caffeine off"
}
