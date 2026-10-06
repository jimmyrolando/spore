import QtQuick
import Quickshell

// The compositor, for the rest of the shell: the only thing that knows which
// one is running. It picks the implementation from the environment and
// always exposes the same shape, so the bar, notifications, idle, the
// lockscreen, Settings and About depend on none of them.
//
// Today there's one: NiriCompositor.qml. To add another (e.g. Hyprland):
//   1. HyprlandCompositor.qml with the same properties and functions as
//      NiriCompositor.qml, in the shape below (Quickshell ships the
//      Quickshell.Hyprland module: workspaces, active window, dispatch()).
//   2. Detect it in `kind` and load it with another LazyLoader like niri's.
//
// The shape:
//   workspaces   [{ id, index, name, output, focused, active, occupied }]
//                (index: position on its monitor, from 1; active: the one
//                shown on its monitor; occupied: has windows)
//   windows      [{ id, appId, title, workspaceId, focused, urgent,
//                   lastFocused }] (lastFocused: seconds, 0 = never)
//   focusedWindow  one of windows, or null
//   outputs      [{ name, width, height, refresh, scale }] (the ones on)
//   casts        [{ id, active, output, windowId, pwNodeId }]: ongoing
//                screen captures (an app records or shares the screen or a
//                window; pwNodeId is the PipeWire node of the stream)
//   name, version     for About and Settings ("niri", "26.04")
//   cornerRadius, innerRadius  window corner radius (0 = square), so the
//                shell's floating panels look like one more window
//   quitCommand  command to end the session
//   nested       running inside another session, for testing: there the
//                shell doesn't suspend on idle or change the system theme
//   focusWorkspace(ws), focusWindow(w), powerOffMonitors(), quit(),
//   refreshOutputs(), emptyWorkspace() -> { from, to } (workspaces) or null
Scope {
    id: root

    // Which one: the variables each compositor sets in the session.
    readonly property string kind: Quickshell.env("NIRI_SOCKET") ? "niri"
        : Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") ? "hyprland"
        : "unknown"
    // No version for this compositor: niri's (the only one for now).
    readonly property var backend: niriBackend.item

    LazyLoader {
        id: niriBackend
        active: true
        NiriCompositor {}
    }

    Component.onCompleted: if (kind !== "niri")
        console.warn("Compositor: " + kind + " is not supported yet, using niri")

    readonly property string name: backend ? backend.name : ""
    readonly property string version: backend ? backend.version : ""
    readonly property var workspaces: backend ? backend.workspaces : []
    readonly property var windows: backend ? backend.windows : []
    readonly property var focusedWindow: backend ? backend.focusedWindow : null
    readonly property var outputs: backend ? backend.outputs : []
    readonly property var casts: backend ? backend.casts : []
    readonly property int cornerRadius: backend ? backend.cornerRadius : 0
    readonly property int innerRadius: backend ? backend.innerRadius : 0
    readonly property var quitCommand: backend ? backend.quitCommand : []
    readonly property bool nested: backend ? backend.nested : false

    function focusWorkspace(ws: var): void { if (backend) backend.focusWorkspace(ws) }
    function focusWindow(w: var): void { if (backend) backend.focusWindow(w) }
    function powerOffMonitors(): void { if (backend) backend.powerOffMonitors() }
    function quit(): void { if (backend) backend.quit() }
    function refreshOutputs(): void { if (backend) backend.refreshOutputs() }
    function emptyWorkspace(): var { return backend ? backend.emptyWorkspace() : null }
}
