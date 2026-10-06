import QtQuick
import Quickshell
import Quickshell.Io

// niri for Compositor.qml: talks to niri and translates it into the neutral
// shape the rest of the shell uses (see Compositor.qml). Another compositor
// would be another file like this one, with the same properties and
// functions.
//
// No polling and no process per change: `niri msg event-stream` sends the
// full state on connect and then every change with its data, and the state
// is built here from that. If an event doesn't add up (an unknown id),
// everything is re-read with `niri msg workspaces/windows`.
Scope {
    id: root

    // A nested test niri (inside another session): its screen is called "winit".
    // There the shell doesn't touch anything on the system (see
    // Compositor.nested).
    readonly property bool nested: Quickshell.screens.some(s => s.name === "winit")

    // For About and Settings ("niri 26.04").
    readonly property string name: "niri"
    property string version: ""

    property var workspaces: []
    property var windows: []
    readonly property var focusedWindow: windows.find(w => w.focused) ?? null
    property var outputs: []
    property var casts: []

    // Window corner radius, so the shell's floating panels (Settings, clipboard)
    // look like one more window (0 = square). innerRadius: the one for things
    // inside (buttons, thumbnails).
    property int cornerRadius: 0
    readonly property int innerRadius: cornerRadius > 0 ? Math.max(4, Math.round(cornerRadius / 2)) : 0

    // End the session (power menu and lockscreen).
    readonly property var quitCommand: ["niri", "msg", "action", "quit", "--skip-confirmation"]

    // niri focuses a workspace by its position (idx).
    // Its index counts on its monitor, and niri takes it on the focused one:
    // that monitor first (a click on the other monitor's bar).
    function focusWorkspace(ws: var): void {
        if (!ws) return
        if (ws.output) Quickshell.execDetached(["sh", "-c", 'niri msg action focus-monitor "$1" && niri msg action focus-workspace "$2"',
            "_", ws.output, String(ws.index)])
        else Quickshell.execDetached(["niri", "msg", "action", "focus-workspace", String(ws.index)])
    }

    function focusWindow(w: var): void {
        if (w) Quickshell.execDetached(["niri", "msg", "action", "focus-window", "--id", String(w.id)])
    }

    // niri turns them back on with any key or mouse movement.
    function powerOffMonitors(): void {
        Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"])
    }

    function quit(): void {
        Quickshell.execDetached(quitCommand)
    }

    // "Preview on desktop": niri has no "show desktop", but it always leaves an
    // empty workspace at the end of each monitor.
    function emptyWorkspace(): var {
        const focused = workspaces.find(w => w.focused)
        if (!focused || !focused.occupied) return null
        const empty = workspaces
            .filter(w => w.output === focused.output && !w.occupied)
            .sort((a, b) => b.index - a.index)[0]
        return empty ? { from: focused, to: empty } : null
    }

    function refreshOutputs(): void {
        outputsReader.rerun()
    }

    // --- Queries ---

    // A niri command that returns JSON. If it's requested again while running,
    // it runs again when it finishes (so a change isn't lost).
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

    // --- State: niri's data as is, by id; events modify it and publish*()
    // turns it into the neutral shape ---

    property var niriWorkspaces: ({})
    property var niriWindows: ({})
    property var niriCasts: ({})

    function setWorkspaces(list: var): void {
        const map = {}
        for (const w of list) map[w.id] = w
        niriWorkspaces = map
        publishWorkspaces()
    }

    function setWindows(list: var): void {
        const map = {}
        for (const w of list) map[w.id] = w
        niriWindows = map
        publishWindows()
    }

    // By monitor and then by idx (the position on screen).
    function publishWorkspaces(): void {
        workspaces = Object.values(niriWorkspaces)
            .sort((a, b) => (a.output || "").localeCompare(b.output || "") || a.idx - b.idx)
            .map(w => ({
                id: w.id, index: w.idx, name: w.name || "", output: w.output || "",
                focused: w.is_focused === true, active: w.is_active === true,
                occupied: w.active_window_id !== null && w.active_window_id !== undefined
            }))
    }

    function publishWindows(): void {
        windows = Object.values(niriWindows).map(w => ({
            id: w.id, appId: w.app_id || "", title: w.title || "", workspaceId: w.workspace_id,
            focused: w.is_focused === true, urgent: w.is_urgent === true,
            lastFocused: w.focus_timestamp ? w.focus_timestamp.secs + w.focus_timestamp.nanos / 1e9 : 0
        }))
    }

    // Ongoing screen captures (the portal: OBS, sharing in a call).
    function publishCasts(): void {
        casts = Object.values(niriCasts).map(c => ({
            id: c.stream_id, active: c.is_active === true,
            output: c.target && c.target.Output ? c.target.Output.name : "",
            windowId: c.target && c.target.Window ? c.target.Window.id : null,
            pwNodeId: c.pw_node_id ?? null
        }))
    }

    // An event naming something unknown: the state got out of sync.
    function resync(): void {
        workspacesReader.rerun()
        windowsReader.rerun()
    }

    // The events that matter (the rest, e.g. WindowLayoutsChanged when moving
    // or resizing windows, is ignored). The semantics are niri-ipc's.
    function handle(line: string): void {
        let ev
        try {
            ev = JSON.parse(line)
        } catch (e) {
            return
        }
        const kind = Object.keys(ev)[0]
        const e = ev[kind]
        switch (kind) {
        case "WorkspacesChanged":
            setWorkspaces(e.workspaces)
            break
        case "WindowsChanged":
            setWindows(e.windows)
            break
        // Becomes the active one on its monitor (the others on that monitor stop
        // being active) and, if `focused`, the only focused one.
        case "WorkspaceActivated": {
            const ws = niriWorkspaces[e.id]
            if (!ws) return resync()
            for (const id in niriWorkspaces) {
                const w = niriWorkspaces[id]
                if (w.output === ws.output) w.is_active = w.id === e.id
                if (e.focused) w.is_focused = w.id === e.id
            }
            publishWorkspaces()
            break
        }
        case "WorkspaceActiveWindowChanged": {
            const ws = niriWorkspaces[e.workspace_id]
            if (!ws) return resync()
            ws.active_window_id = e.active_window_id
            publishWorkspaces()
            break
        }
        // A new or changed window (title, workspace…). If it's focused, the others
        // no longer are.
        case "WindowOpenedOrChanged":
            if (e.window.is_focused)
                for (const id in niriWindows) niriWindows[id].is_focused = false
            niriWindows[e.window.id] = e.window
            publishWindows()
            break
        case "WindowClosed":
            delete niriWindows[e.id]
            publishWindows()
            break
        case "WindowFocusChanged":
            for (const id in niriWindows) niriWindows[id].is_focused = niriWindows[id].id === e.id
            publishWindows()
            break
        case "WindowUrgencyChanged":
            if (!niriWindows[e.id]) return resync()
            niriWindows[e.id].is_urgent = e.urgent
            publishWindows()
            break
        // Only used by notifications on click: no need to publish it right away (it
        // goes out with the next change).
        case "WindowFocusTimestampChanged":
            if (niriWindows[e.id]) niriWindows[e.id].focus_timestamp = e.focus_timestamp
            break
        case "ConfigLoaded":
            radiusReader.running = true
            break
        case "CastsChanged": {
            const map = {}
            for (const c of e.casts) map[c.stream_id] = c
            niriCasts = map
            publishCasts()
            break
        }
        case "CastStartedOrChanged":
            niriCasts[e.cast.stream_id] = e.cast
            publishCasts()
            break
        case "CastStopped":
            delete niriCasts[e.stream_id]
            publishCasts()
            break
        }
    }

    // Full read, only if the state got out of sync (see resync).
    Reader {
        id: workspacesReader
        command: ["niri", "msg", "-j", "workspaces"]
        onParsed: (data) => root.setWorkspaces(data)
    }

    Reader {
        id: windowsReader
        command: ["niri", "msg", "-j", "windows"]
        onParsed: (data) => root.setWindows(data)
    }

    Reader {
        id: outputsReader
        running: true
        command: ["niri", "msg", "-j", "outputs"]
        // Only the ones that are on (with a current mode).
        onParsed: (data) => root.outputs = Object.keys(data).map(name => {
            const o = data[name]
            const m = o.modes && o.current_mode !== null ? o.modes[o.current_mode] : null
            return m ? { name: name, width: m.width, height: m.height, refresh: m.refresh_rate / 1000,
                scale: o.logical ? o.logical.scale : 1 } : null
        }).filter(o => o)
    }

    Process {
        running: true
        command: ["niri", "--version"]
        stdout: StdioCollector {
            // "niri 26.04 (…)" -> "26.04".
            onStreamFinished: root.version = text.trim().split(" ")[1] || ""
        }
    }

    // niri's window-rules don't apply to layer-shell, so the radius is read from
    // its config: the geometry-corner-radius of the last global window-rule
    // (without `match`), the one that would win for any window. It's re-read
    // when niri reloads its config.
    Process {
        id: radiusReader
        running: true
        command: ["awk", `
            /^[[:space:]]*\\/\\// { next }
            /^[[:space:]]*window-rule[[:space:]]*\\{/ { inRule = 1; hasMatch = 0; r = ""; next }
            inRule && /^[[:space:]]*match[[:space:]]/ { hasMatch = 1 }
            inRule && /^[[:space:]]*geometry-corner-radius[[:space:]]/ { r = $2 }
            inRule && /^}/ { if (!hasMatch && r != "") radius = r; inRule = 0 }
            END { print radius + 0 }`,
            (Quickshell.env("NIRI_CONFIG") || Quickshell.env("HOME") + "/.config/niri/config.kdl")]
        stdout: StdioCollector {
            onStreamFinished: root.cornerRadius = parseInt(text) || 0
        }
    }

    // Each line is an event: {"WorkspaceActivated":{…}}. On connect the full
    // state arrives (WorkspacesChanged, WindowsChanged…).
    Process {
        id: events
        running: true
        command: ["niri", "msg", "-j", "event-stream"]
        stdout: SplitParser {
            onRead: (line) => root.handle(line)
        }
        // If niri restarts, the stream stops: open it again.
        onExited: restartEvents.restart()
    }

    Timer {
        id: restartEvents
        interval: 2000
        onTriggered: events.running = true
    }
}
