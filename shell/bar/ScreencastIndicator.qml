import QtQuick
import Quickshell
import Quickshell.Services.Pipewire
import "../common"
import "../services"

// Screen sharing ("screencast" widget), like macOS's dot: it shows only
// while an app records or shares the screen (OBS, a call in the browser…).
// Just the dot, on the bar: no capsule (Bar.bareWidgets), no background and
// no click; on hover, the tooltip says which app and which screen or window.
//
// The compositor reports the captures (Compositor.casts). The app isn't in
// that report: PipeWire is searched for the node the capture's stream goes
// to.
Item {
    id: root

    required property Theme theme
    property Compositor compositor: null

    readonly property var casts: compositor ? compositor.casts.filter(c => c.active) : []
    readonly property bool shown: casts.length > 0

    // The app receiving the capture: the target of the link leaving the
    // compositor's node. On NixOS wrapped programs are called ".obs-wrapped":
    // the name is cleaned up and its .desktop is looked up, first by the
    // command it runs (OBS's runs "obs" but its id is com.obsproject.Studio)
    // and otherwise by name.
    function appName(cast: var): string {
        const link = Pipewire.linkGroups.values.find(l => l.source && l.target && l.source.id === cast.pwNodeId)
        if (!link) return ""
        const raw = link.target.name.replace(/^\./, "").replace(/-wrapped$/, "")
        const entry = DesktopEntries.applications.values.find(d => d.command && d.command.length > 0
                && d.command[0].split("/").pop() === raw)
            ?? DesktopEntries.heuristicLookup(raw)
        return entry && entry.name ? entry.name : raw
    }

    // A fixed red and not the palette's (theme.danger): in dark palettes that
    // one is deliberately light (for text), and a recording indicator must
    // always look equally strong, like on macOS. Apple's system red.
    readonly property color dotColor: "#ff3b30"

    // Just enough for the dot, plus a little room to hit it with the mouse.
    implicitWidth: 14
    implicitHeight: 24

    Rectangle {
        anchors.centerIn: parent
        width: 8
        height: 8
        radius: 4
        color: root.dotColor
    }

    HoverHandler {
        id: hover
    }

    BarTooltip {
        theme: root.theme
        hovered: hover.hovered
        rows: root.casts.map(c => ({
            label: root.appName(c) || "Screen",
            value: c.output ? "Sharing " + c.output : "Sharing a window"
        }))
    }
}
