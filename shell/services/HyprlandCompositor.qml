import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Hyprland for Compositor.qml: talks to Hyprland and translates it into the
// neutral shape the rest of the shell uses (see Compositor.qml).
//
// Quickshell's Hyprland module reports every event of Hyprland's socket
// (rawEvent); the ones that change something we show re-read, after a short
// pause, the state with `hyprctl -j` (workspaces, windows, monitors). Nothing
// polls: with no events, nothing runs.
//
// Differences with niri, hidden here: Hyprland's workspaces are global (one
// list, each on a monitor), so `index` is made up (the position among its
// monitor's, by id), and it has no screen-capture list (`casts` stays empty).
Scope {
    id: root

    // A nested test Hyprland (inside another session): its screens are "WL-1"…
    readonly property bool nested: Quickshell.screens.some(s => s.name.startsWith("WL-"))

    readonly property string name: "Hyprland"
    property string version: ""

    property var workspaces: []
    property var windows: []
    readonly property var focusedWindow: windows.find(w => w.focused) ?? null
    property var outputs: []
    // Every monitor, on or off, with its modes (see Compositor.qml).
    property var displays: []
    readonly property var casts: []

    // From decoration:rounding, so the shell's panels look like one more window.
    property int cornerRadius: 0
    readonly property int innerRadius: cornerRadius > 0 ? Math.max(4, Math.round(cornerRadius / 2)) : 0

    readonly property var quitCommand: ["hyprctl", "dispatch", "exit"]

    // Hyprland's dispatchers take a workspace by its id (it creates it if
    // missing) and a window by its address.
    function focusWorkspace(ws: var): void {
        if (ws) Hyprland.dispatch("workspace " + ws.id)
    }

    function focusWindow(w: var): void {
        if (w) Hyprland.dispatch("focuswindow address:" + w.id)
    }

    // They come back on with a key or the mouse if the user's config has
    // misc:key_press_enables_dpms and mouse_move_enables_dpms (examples/hyprland.conf).
    function powerOffMonitors(): void {
        Hyprland.dispatch("dpms off")
    }

    function quit(): void {
        Hyprland.dispatch("exit")
    }

    // "Preview on desktop": Hyprland creates a workspace when it's asked for,
    // so the empty one is the first id not in use.
    function emptyWorkspace(): var {
        const focused = workspaces.find(w => w.focused)
        if (!focused || !focused.occupied) return null
        const used = new Set(workspaces.map(w => w.id))
        let id = 1
        while (used.has(id)) id++
        return { from: focused, to: { id: id, index: 0, name: "", output: focused.output, focused: false, active: false, occupied: false } }
    }

    function refreshOutputs(): void {
        monitorsReader.rerun()
    }

    // Hyprland's `monitor` rule sets everything at once, so what isn't changing
    // is taken from the monitor as it is now. `hyprctl keyword` lasts until
    // the config is reloaded.
    function configureDisplay(name: string, change: var): void {
        const d = displays.find(x => x.name === name)
        if (!d) return
        if (change.on === false) {
            Quickshell.execDetached(["hyprctl", "keyword", "monitor", name + ",disable"])
        } else {
            const m = change.mode ?? (d.mode >= 0 ? d.modes[d.mode] : null)
            const res = m ? m.width + "x" + m.height + "@" + m.refresh.toFixed(3) : "preferred"
            const scale = change.scale ?? d.scale
            const transform = change.transform ?? d.transform
            Quickshell.execDetached(["hyprctl", "keyword", "monitor",
                [name, res, d.x + "x" + d.y, scale, "transform", transforms.indexOf(transform)].join(",")])
        }
        displaysRefresh.restart()
        displaysLater.restart()
    }

    // Hyprland's numbers for the transform, by position.
    readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

    // The command runs on its own: ask again a moment later, and once more
    // in case it hadn't finished.
    Timer {
        id: displaysRefresh
        interval: 400
        onTriggered: monitorsReader.rerun()
    }

    Timer {
        id: displaysLater
        interval: 1500
        onTriggered: monitorsReader.rerun()
    }

    // --- Queries ---

    // A hyprctl command that returns JSON. If it's requested again while
    // running, it runs again when it finishes (so a change isn't lost).
    component Reader: Process {
        id: reader
        property bool again: false
        signal parsed(var data)
        function rerun(): void {
            if (running) again = true
            else running = true
        }
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    reader.parsed(JSON.parse(text))
                } catch (e) {
                    console.warn("Compositor: could not parse `" + reader.command.join(" ") + "`:", e)
                }
            }
        }
        onExited: if (again) {
            again = false
            running = true
        }
    }

    // The monitors' active workspace (id by monitor name), from monitorsReader.
    property var activeByMonitor: ({})
    // The windows that asked for attention (address -> true) until focused.
    property var urgentAddresses: ({})
    // The focused window's address, "" if none (activewindowv2).
    property string activeAddress: ""

    Reader {
        id: workspacesReader
        running: true
        command: ["hyprctl", "-j", "workspaces"]
        onParsed: (data) => root.publishWorkspaces(data)
    }

    Reader {
        id: windowsReader
        running: true
        command: ["hyprctl", "-j", "clients"]
        onParsed: (data) => root.publishWindows(data)
    }

    Reader {
        id: monitorsReader
        running: true
        command: ["hyprctl", "-j", "monitors", "all"]
        onParsed: (data) => {
            // `monitors all` also lists the ones that are off.
            const on = data.filter(m => !m.disabled)
            const active = {}
            for (const m of on) active[m.name] = m.activeWorkspace ? m.activeWorkspace.id : null
            root.activeByMonitor = active
            root.focusedMonitor = (on.find(m => m.focused) || {}).name || ""
            root.outputs = on.map(m => ({ name: m.name, width: m.width, height: m.height,
                refresh: m.refreshRate, scale: m.scale }))
            root.displays = data.map(m => {
                // "3840x2160@60.00Hz"
                const modes = (m.availableModes || []).map(t => {
                    const p = /^(\d+)x(\d+)@([\d.]+)Hz$/.exec(t)
                    return p ? { width: +p[1], height: +p[2], refresh: +p[3] } : null
                }).filter(x => x)
                const mode = modes.findIndex(x => x.width === m.width && x.height === m.height
                    && Math.abs(x.refresh - m.refreshRate) < 0.05)
                return {
                    name: m.name,
                    label: ((m.make || "") + " " + (m.model || "")).trim() || m.name,
                    on: !m.disabled, modes: modes, mode: m.disabled ? -1 : mode,
                    scale: m.scale, transform: root.transforms[m.transform] || "normal",
                    x: m.x, y: m.y
                }
            })
            // Which one is active and focused depends on this.
            workspacesReader.rerun()
        }
    }

    property string focusedMonitor: ""
    property var rawWorkspaces: []
    property var rawWindows: []

    function publishWorkspaces(list: var): void {
        rawWorkspaces = list
        // Special workspaces (scratchpads) have negative ids: not shown.
        const real = list.filter(w => w.id > 0).sort((a, b) => a.id - b.id)
        const perMonitor = {}
        workspaces = real.map(w => {
            const n = (perMonitor[w.monitor] = (perMonitor[w.monitor] || 0) + 1)
            const active = root.activeByMonitor[w.monitor] === w.id
            return {
                id: w.id, index: n, name: w.name === String(w.id) ? "" : w.name, output: w.monitor,
                focused: active && w.monitor === root.focusedMonitor, active: active,
                occupied: w.windows > 0
            }
        }).sort((a, b) => a.output.localeCompare(b.output) || a.index - b.index)
    }

    function publishWindows(list: var): void {
        rawWindows = list
        windows = list.filter(c => c.mapped).map(c => ({
            id: c.address, appId: c.class || "", title: c.title || "", workspaceId: c.workspace.id,
            focused: c.address === root.activeAddress,
            urgent: root.urgentAddresses[c.address] === true,
            // focusHistoryID: 0 is the latest, -1 never: made into "more is later".
            lastFocused: c.focusHistoryID >= 0 ? 1000 - c.focusHistoryID : 0
        }))
    }

    // Only the events that change what's shown (e.g. not a window moving).
    readonly property var relevant: new Set([
        "workspace", "workspacev2", "createworkspace", "createworkspacev2", "destroyworkspace",
        "destroyworkspacev2", "moveworkspace", "moveworkspacev2", "renameworkspace", "focusedmon",
        "focusedmonv2", "openwindow", "closewindow", "movewindow", "movewindowv2", "windowtitle",
        "windowtitlev2", "monitoradded", "monitorremoved", "monitoraddedv2", "monitorremovedv2",
        "configreloaded"
    ])

    Connections {
        target: Hyprland
        function onRawEvent(event: var): void {
            const name = event.name
            if (name === "activewindowv2") {
                // The address comes without 0x.
                root.activeAddress = event.data ? "0x" + event.data : ""
                delete root.urgentAddresses[root.activeAddress]
                root.publishWindows(root.rawWindows)
                return
            }
            if (name === "urgent") {
                root.urgentAddresses["0x" + event.data] = true
                root.publishWindows(root.rawWindows)
                return
            }
            if (name === "configreloaded") radiusReader.running = true
            if (root.relevant.has(name)) refreshSoon.restart()
        }
    }

    // A burst of events (opening a window sends several) is one read.
    Timer {
        id: refreshSoon
        interval: 60
        onTriggered: {
            monitorsReader.rerun()
            windowsReader.rerun()
        }
    }

    Process {
        running: true
        command: ["hyprctl", "-j", "version"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.version = (JSON.parse(text).tag || "").replace(/^v/, "")
                } catch (e) {}
            }
        }
    }

    Process {
        running: true
        command: ["hyprctl", "-j", "activewindow"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.activeAddress = JSON.parse(text).address || ""
                    root.publishWindows(root.rawWindows)
                } catch (e) {}
            }
        }
    }

    Process {
        id: radiusReader
        running: true
        command: ["hyprctl", "-j", "getoption", "decoration:rounding"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.cornerRadius = JSON.parse(text).int || 0
                } catch (e) {}
            }
        }
    }
}
