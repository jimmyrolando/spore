import QtQuick
import Quickshell
import Quickshell.Io

// Reads $XDG_CONFIG_HOME/spore/settings.json (default ~/.config/spore/; one
// per user, separate from the code) and exposes each option as a property.
// It's re-read when saved, without restarting the shell. A missing key (or
// the whole file), or one of another type, uses the default from `defaults`.
//
// shell.qml creates a single one and passes it as `settings` to whoever uses
// it, like the Theme (see docs/architecture.md: why there's no Singleton).
Scope {
    id: root

    readonly property string home: Quickshell.env("HOME")

    readonly property var defaults: ({
        idle: {
            lockAfter: 300,
            screenOffAfter: 600,
            suspendAfter: 1800
        },
        bar: {
            launcher: ["rofi", "-show", "drun"],
            clockFormat: "ddd MMM dd  hh:mm",
            opacity: 1.0,
            style: "full",
            // Widgets per zone. Each inner group is a capsule; what isn't listed isn't
            // shown. In "center", the group with the workspaces sits at the exact
            // center (if there's none, the middle one).
            layout: {
                left: [["launcher", "about"]],
                center: [["workspaces"]],
                right: [["screencast"], ["clipboard", "audio", "bluetooth", "idleInhibitor", "system"], ["clock", "power"]]
            },
            // Each widget's options: { "activeWindow": { "showIcon": false } }. Missing
            // ones use the default from widgetOptionDefs.
            widgetOptions: {}
        },
        picker: {
            wallpaperDir: "~/Pictures/Wallpapers"
        },
        wallpaper: {
            // When the wallpaper changes: "none", "fade", "wipe", "disc", "nix",
            // "nix-rnd", "spore" or "random".
            transition: "fade",
            // Video wallpapers (they play once when chosen, at startup and on unlock).
            // false: they stay as a still image (their last frame) and QtMultimedia
            // isn't loaded.
            videos: true
        },
        lock: {
            // { "name": "City", "latitude": 0, "longitude": 0, "enabled": true } or
            // null (no weather). enabled: false hides it without losing the location.
            weather: null,
            // "metric" (°C, km/h) or "imperial" (°F, mph).
            units: "metric"
        },
        clipboard: {
            // History entries (cliphist). The oldest are deleted automatically.
            maxItems: 500
        },
        fonts: {
            // Interface text, numbers/times/values, and the bar ("" = the monospace
            // one). There used to be just one: bar.font (the monospace one).
            interface: "Noto Sans",
            monospace: "JetBrainsMono Nerd Font Mono",
            bar: ""
        }
    })

    // Idle timeouts, in seconds (0 = off). See Idle.qml.
    property int lockAfter: defaults.idle.lockAfter
    property int screenOffAfter: defaults.idle.screenOffAfter
    property int suspendAfter: defaults.idle.suspendAfter
    // The NixOS button's command (a list: program and arguments).
    property var launcher: defaults.bar.launcher
    // Qt.formatDateTime format.
    property string clockFormat: defaults.bar.clockFormat
    // Fonts (Settings → Appearance → Fonts). fontBar "" = the monospace one.
    property string fontInterface: defaults.fonts.interface
    property string fontMonospace: defaults.fonts.monospace
    property string fontBar: defaults.fonts.bar
    // The bar's background opacity: 0.0 = no background (only the capsules
    // over the wallpaper), 1.0 = solid.
    property real barOpacity: defaults.bar.opacity
    // Shape: "full" | "floating" | "pill" (see Bar.qml).
    property string barStyle: defaults.bar.style
    // The bar's widgets per zone (see defaults.bar.layout and Bar.qml).
    readonly property var barWidgets: ["launcher", "about", "controlCenter", "activeWindow", "apps", "system", "cpu", "memory", "gpu", "workspaces",
        "clipboard", "audio", "bluetooth", "network", "idleInhibitor", "screencast", "notifications", "drives", "clock", "power"]
    property var barLayout: defaults.bar.layout
    property var widgetOptions: defaults.bar.widgetOptions

    // The options each widget has (Settings → Bar shows them with the gear on
    // its row). A new widget with options is added here and reads its own with
    // widgetOption().
    readonly property var widgetOptionDefs: ({
        activeWindow: [
            { key: "showIcon", label: "Show icon", hint: "The app icon next to its name", type: "toggle", fallback: true }
        ]
    })

    function widgetOption(id: string, key: string): var {
        const v = (widgetOptions[id] || {})[key]
        if (v !== undefined) return v
        const def = (widgetOptionDefs[id] || []).find(d => d.key === key)
        return def ? def.fallback : undefined
    }

    // Only known ids, each once, with no empty groups. If nothing valid is
    // left (a broken file), the factory one.
    // "settings" (the button that opened Settings) became "about".
    function cleanLayout(layout: var): var {
        if (!layout || typeof layout !== "object") return defaults.bar.layout
        const seen = {}
        const out = {}
        for (const zone of ["left", "center", "right"]) {
            out[zone] = (Array.isArray(layout[zone]) ? layout[zone] : [])
                .map(g => (Array.isArray(g) ? g : [g]).map(id => id === "settings" ? "about" : id).filter(id => barWidgets.includes(id) && !seen[id] && (seen[id] = true)))
                .filter(g => g.length > 0)
        }
        return out
    }
    // As it is in the file (with "~/"): that's what gets saved.
    property string wallpaperDirRaw: defaults.picker.wallpaperDir
    readonly property string wallpaperDir: expandHome(wallpaperDirRaw)
    // Transition when the wallpaper changes (see Wallpaper.qml).
    readonly property var wallpaperTransitions: ["none", "fade", "wipe", "disc", "nix", "nix-rnd", "spore", "random"]
    property string wallpaperTransition: defaults.wallpaper.transition
    property bool videoWallpapers: defaults.wallpaper.videos
    // The lockscreen's weather (see Weather.qml): null = time zone; otherwise
    // { enabled, location, name, region, latitude, longitude } (Settings builds
    // it).
    property var lockWeather: defaults.lock.weather
    // Weather units: "metric" or "imperial".
    property string lockUnits: defaults.lock.units
    // Clipboard history (see ClipboardService.qml).
    property int clipboardMaxItems: defaults.clipboard.maxItems

    readonly property string path: (Quickshell.env("XDG_CONFIG_HOME") || home + "/.config") + "/spore/settings.json"

    function expandHome(path: string): string {
        return path.startsWith("~/") ? home + path.slice(1) : path
    }

    FileView {
        path: root.path
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.apply(text())
        onLoadFailed: root.apply("{}")
    }

    // Saves the current values with `changes` on top, e.g.
    // save({ idle: { lockAfter: 600 } }). Used by SettingsWindow.qml. The
    // FileView above sees the change and applies it, just as if the file were
    // edited by hand.
    function save(changes: var): void {
        const s = {
            idle: { lockAfter: lockAfter, screenOffAfter: screenOffAfter, suspendAfter: suspendAfter },
            bar: { launcher: launcher, clockFormat: clockFormat, opacity: barOpacity, style: barStyle, layout: barLayout, widgetOptions: widgetOptions },
            picker: { wallpaperDir: wallpaperDirRaw },
            wallpaper: { transition: wallpaperTransition, videos: videoWallpapers },
            lock: { weather: lockWeather, units: lockUnits },
            clipboard: { maxItems: clipboardMaxItems },
            fonts: { interface: fontInterface, monospace: fontMonospace, bar: fontBar }
        }
        for (const section in changes)
            Object.assign(s[section], changes[section])
        const json = JSON.stringify(s, null, 4) + "\n"
        // Applied right away, without waiting to re-read the file: otherwise a
        // second change in a row (two clicks on ↑) started from the old values.
        apply(json)
        writer.setText(json)
    }

    // Written with FileView and not a process: two changes in a row are both
    // saved (with the process still running, the second was lost and, when the
    // file was re-read, the interface went back). Direct, without tmp +
    // rename: that way the file keeps its inode (the watchChanges above still
    // sees it) and, if it's a link (programs.spore.settingsFile to the
    // dotfiles), the target is written instead of replacing the link. No
    // preload: it only writes.
    FileView {
        id: writer
        path: root.path
        preload: false
        atomicWrites: false
        onSaveFailed: console.warn("Could not save settings.json")
    }

    // The folder has to exist to write (a user without a settings.json yet).
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", path.slice(0, path.lastIndexOf("/"))])

    function apply(json: string): void {
        let s
        try {
            s = JSON.parse(json)
        } catch (e) {
            console.warn("Invalid settings.json, keeping previous values:", e)
            return
        }
        if (!s || typeof s !== "object" || Array.isArray(s)) {
            console.warn("Invalid settings.json (not an object), keeping previous values")
            return
        }
        // A value of another type than its default (edited by hand: "five" for
        // a number, {} for a name) gets the default, with a warning. Assigning
        // it threw, and every key after it was left as it was.
        const get = (section, key) => {
            const fallback = defaults[section][key]
            const value = (s[section] && typeof s[section] === "object" ? s[section] : {})[key] ?? fallback
            if (fallback === null || (typeof value === typeof fallback && Array.isArray(value) === Array.isArray(fallback)))
                return value
            console.warn("settings.json:", section + "." + key, "should be",
                Array.isArray(fallback) ? "a list" : typeof fallback === "object" ? "an object" : "a " + typeof fallback, "- using the default")
            return fallback
        }
        lockAfter = get("idle", "lockAfter")
        screenOffAfter = get("idle", "screenOffAfter")
        suspendAfter = get("idle", "suspendAfter")
        launcher = get("bar", "launcher")
        clockFormat = get("bar", "clockFormat")
        barOpacity = Math.max(0, Math.min(1, get("bar", "opacity")))
        barStyle = ["full", "floating", "pill"].includes(get("bar", "style")) ? get("bar", "style") : defaults.bar.style
        barLayout = cleanLayout(get("bar", "layout"))
        const opts = get("bar", "widgetOptions")
        widgetOptions = opts && typeof opts === "object" && !Array.isArray(opts) ? opts : {}
        wallpaperDirRaw = get("picker", "wallpaperDir")
        // "hex" was nix-rnd's first name.
        const transition = get("wallpaper", "transition") === "hex" ? "nix-rnd" : get("wallpaper", "transition")
        wallpaperTransition = wallpaperTransitions.includes(transition) ? transition : "fade"
        videoWallpapers = get("wallpaper", "videos") !== false
        const weather = get("lock", "weather")
        lockWeather = weather && typeof weather === "object" && !Array.isArray(weather) ? weather : null
        lockUnits = get("lock", "units") === "imperial" ? "imperial" : "metric"
        clipboardMaxItems = Math.max(1, get("clipboard", "maxItems"))
        fontInterface = get("fonts", "interface") || defaults.fonts.interface
        // Without the fonts section, the old bar.font was the monospace one.
        const oldFont = (s.bar || {}).font
        fontMonospace = (s.fonts ? get("fonts", "monospace") : typeof oldFont === "string" ? oldFont : "") || defaults.fonts.monospace
        fontBar = get("fonts", "bar") || ""
        console.info("Settings: loaded (idle: lock", lockAfter + "s, screen off", screenOffAfter
            + "s, suspend", suspendAfter + "s)")
    }
}
