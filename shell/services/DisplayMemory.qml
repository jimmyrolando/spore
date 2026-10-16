import QtQuick
import Quickshell
import Quickshell.Io

// Remembers what was kept in Settings > Displays and puts it back. The
// compositor's changes (`niri msg output`) are lost when it restarts, and a
// line in its config wouldn't win over the user's own `output` (niri uses the
// first one it finds), so the shell does it: when a monitor shows up in the
// list (at startup or plugged in) its remembered mode, scale, rotation and
// on/off are applied.
//
// $state/displays.json: { "<make model serial>": { mode: { width, height,
// refresh }, scale, transform, on } }, by that name and not the connector's
// (DP-4 can change with the cable).
Scope {
    id: root

    required property Compositor compositor
    required property string stateDir

    readonly property string path: stateDir + "/displays.json"
    property var saved: ({})
    property bool loaded: false
    // The monitors already handled this session ("id@connector"): what's
    // changed afterwards by hand isn't undone.
    property var handled: ({})

    function has(id: string): bool {
        return saved[id] !== undefined
    }

    // Remembers how the monitor is now (called when a change is kept).
    function remember(name: string): void {
        const d = compositor.displays.find(x => x.name === name)
        if (!d) return
        const next = Object.assign({}, saved)
        next[d.id] = { on: d.on, scale: d.scale, transform: d.transform }
        if (d.on && d.mode >= 0) next[d.id].mode = d.modes[d.mode]
        else if (saved[d.id] && saved[d.id].mode) next[d.id].mode = saved[d.id].mode
        write(next)
    }

    function forget(id: string): void {
        const next = Object.assign({}, saved)
        delete next[id]
        write(next)
    }

    function write(next: var): void {
        saved = next
        writer.setText(JSON.stringify(next, null, 2) + "\n")
    }

    // What a compositor takes as a rotation; anything else in the file (edited
    // by hand) is skipped.
    readonly property var transforms: ["normal", "90", "180", "270", "flipped", "flipped-90", "flipped-180", "flipped-270"]

    // The same refresh rate, give or take what the compositor rounds.
    function findMode(d: var, m: var): int {
        return d.modes.findIndex(x => x.width === m.width && x.height === m.height
            && Math.abs(x.refresh - m.refresh) < 0.05)
    }

    // What's different between a monitor and its remembered state, or null.
    function changeFor(d: var, entry: var): var {
        const change = {}
        const mode = entry.mode ? findMode(d, entry.mode) : -1
        // A mode this monitor no longer has (another one, same port) is skipped.
        if (entry.on !== false && mode >= 0 && mode !== d.mode) change.mode = d.modes[mode]
        if (entry.on !== false && typeof entry.scale === "number" && Math.abs(entry.scale - d.scale) > 0.001) change.scale = entry.scale
        if (entry.on !== false && transforms.includes(entry.transform) && entry.transform !== d.transform) change.transform = entry.transform
        // Never the last one on: the screen would go black with nothing to undo it.
        if (entry.on === false && d.on && compositor.displays.filter(x => x.on).length > 1) change.on = false
        if (entry.on !== false && !d.on) change.on = true
        return Object.keys(change).length > 0 ? change : null
    }

    function applySaved(): void {
        if (!loaded) return
        for (const d of compositor.displays) {
            const key = d.id + "@" + d.name
            if (handled[key]) continue
            handled[key] = true
            const entry = saved[d.id]
            if (!entry) continue
            const change = changeFor(d, entry)
            if (change) {
                console.info("Displays: restoring " + d.name + " " + JSON.stringify(change))
                compositor.configureDisplay(d.name, change)
            }
        }
    }

    Connections {
        target: root.compositor
        function onDisplaysChanged(): void { root.applySaved() }
    }

    FileView {
        path: root.path
        onLoaded: {
            try {
                const s = JSON.parse(text())
                root.saved = s && typeof s === "object" && !Array.isArray(s) ? s : {}
            } catch (e) {
                console.warn("Invalid displays.json, ignoring it:", e)
                root.saved = {}
            }
            root.loaded = true
            root.applySaved()
        }
        onLoadFailed: {
            root.loaded = true
            root.applySaved()
        }
    }

    FileView {
        id: writer
        path: root.path
        preload: false
        atomicWrites: false
        onSaveFailed: console.warn("Could not save displays.json")
    }

    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", stateDir])
}
