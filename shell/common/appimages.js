.pragma library

// What AppImagesService.qml does with the file names in the folder: a name
// and a version out of "OpenCADStudio-v2026.37-linux-x86_64.AppImage", and
// the newest of each app when there are several versions of it. In its own
// file (no QML in it) so it can be tried with node.

// What follows the version in a file name (the platform), taken off from the
// end, however many there are: "-linux-x86_64".
var platform = /[-_.](x86[-_]64|amd64|aarch64|arm64|armhf|armv7l?|i[3-6]86|linux64|linux|gnu)$/i

// The name, then a separator and a version: digits with at least one dot
// ("0.7.5", "2026.37"), maybe with a "v" and a tail ("-beta1"). The name is
// the shortest start that leaves one, so "app-2d-viewer-1.0" is "app 2d
// viewer" and "1.0".
var versioned = /^(.+?)[-_ ]v?(\d+(?:\.\d+)+(?:[-+~.]?[A-Za-z0-9.]+)*)$/

// "artcraft-launcher" -> "Artcraft Launcher": separators become spaces and a
// word written all in lowercase gets its capital; "IngeCAD" is left as it is.
function pretty(name) {
    return name.replace(/[-_]+/g, " ").trim().split(" ")
        .map(w => w === w.toLowerCase() ? w.charAt(0).toUpperCase() + w.slice(1) : w).join(" ")
}

// { name: shown, version: "" if none, key: what groups the versions of one app }
function parse(file) {
    let base = file.replace(/\.appimage$/i, "")
    for (;;) {
        const shorter = base.replace(platform, "")
        if (shorter === base) break
        base = shorter
    }
    const m = versioned.exec(base)
    const name = m ? m[1] : base
    return {
        name: pretty(name),
        version: m ? m[2] : "",
        key: name.toLowerCase().replace(/[^a-z0-9]/g, "")
    }
}

// <0, 0 or >0, like a sort function; "2026.9" is older than "2026.37".
function compareVersions(a, b) {
    const x = a.split(/[^0-9]+/).filter(s => s !== "").map(Number)
    const y = b.split(/[^0-9]+/).filter(s => s !== "").map(Number)
    for (let i = 0; i < Math.max(x.length, y.length); i++) {
        const d = (x[i] ?? -1) - (y[i] ?? -1)
        if (d !== 0) return d
    }
    return 0
}

// entries: [{ file, path, mtime }] -> one per app, the newest version (the
// later one if the versions are the same or there are none), with `older`:
// how many others there are. Sorted by name.
function newest(entries) {
    const groups = {}
    for (const e of entries) {
        const p = parse(e.file)
        const app = { name: p.name, version: p.version, key: p.key, file: e.file, path: e.path, mtime: e.mtime, older: 0 }
        const best = groups[p.key]
        if (!best) {
            groups[p.key] = app
            continue
        }
        const newer = compareVersions(app.version, best.version) || app.mtime - best.mtime
        const winner = newer > 0 ? app : best
        winner.older = best.older + 1
        groups[p.key] = winner
    }
    return Object.values(groups).sort((a, b) => a.name.localeCompare(b.name, undefined, { sensitivity: "base" }))
}
