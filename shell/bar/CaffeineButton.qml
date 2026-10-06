import QtQuick

// Idle inhibitor ("caffeine"; CaffeineButton and not IdleInhibitor, which is
// a Quickshell.Wayland type): while it's on, the screen doesn't turn off or
// lock by itself. The state lives in shell.qml (shared with the Control
// Center's tile); this only shows it and requests the change.
BarButton {
    property bool inhibiting: false

    icon: "coffee"
    active: inhibiting
    tooltip: inhibiting ? "Caffeine on · screen stays on" : "Caffeine off"
}
