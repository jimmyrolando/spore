import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import "../common"
import "../services"
import "../wallpaper"
import "../common/brand.js" as Brand

// The settings window: a sidebar with the sections (Appearance, Bar, Lock
// screen, Idle, About) and the chosen section's content. It edits
// settings.json with Settings.save() right away; wallpaper, palette and mode
// are applied by shell.qml (signals). "Preview on desktop" hides it and
// opens the strip (WallpaperStrip) to choose while seeing the desktop.
//
// shell.qml loads it with a LazyLoader only while it's open.
PanelWindow {
    id: root

    required property Theme theme
    required property Settings settings
    required property WallpaperService wallpapers
    property string currentWallpaperSource: ""
    // The lockscreen's: to show the time zone's city.
    property Weather weather: null
    // "dark", "light" or "auto" (theme.mode is the one applied).
    property string modeSetting: "dark"
    property string autoModeHint: ""
    // Caffeine (the Idle counter says nothing is going to happen).
    property bool caffeine: false

    signal closeRequested()
    signal previewRequested()
    signal wallpaperChosen(path: string)
    signal paletteChosen(name: string)
    signal themeModeChosen(mode: string)
    // The folder button next to "Wallpaper folder" (FilePicker.qml).
    signal folderPickerRequested()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-settings"
    // OnDemand: niri gives it the keyboard on click (search, fields, Esc) and
    // gives it back to regular windows normally.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // width/height and not implicit*: with no anchors, implicit* leaves the
    // surface at 0x0 (the "deprecated" warning is cosmetic).
    width: 920
    // Height: the wallpaper grid is the only thing that stretches (Palette,
    // Mode and Options stay fixed below); at 620 there was hardly any room
    // left.
    height: 800
    color: "transparent"

    Component.onCompleted: wallpapers.refresh()

    // Version, name and window radius of the compositor (Compositor.qml).
    property Compositor compositor: null
    readonly property int cornerRadius: compositor ? compositor.cornerRadius : 0

    // --- Colors (all from the theme, so the window follows the palette) ---

    function tint(alpha: real): color {
        return Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, alpha))
    }
    readonly property color sidebarBg: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.5))
    readonly property color groupBg: tint(0.03)
    readonly property color subtle: tint(0.08)
    readonly property color inputBg: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.6))
    readonly property color inputBorder: tint(0.15)
    readonly property color button: tint(0.08)
    readonly property color buttonHover: tint(0.14)
    readonly property color track: tint(0.07)
    readonly property color navActive: Qt.tint(theme.base, Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.12))
    readonly property color soft: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.75)
    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.55)

    // --- Fonts ----------------------------------------------------------------

    // The open list: which row (its key) and where (below the field).
    property string fontMenuKey: ""
    property bool fontMenuAllowSame: false
    property real fontMenuX: 0
    property real fontMenuY: 0
    property real fontMenuWidth: 300
    // The installed fonts (read once per opened window).
    readonly property var installedFonts: Qt.fontFamilies()
    // The ones matching the search; "" = "Same as Monospace" (Bar).
    readonly property var fontChoices: {
        const q = fontSearch.text.trim().toLowerCase()
        const found = installedFonts.filter(f => f.toLowerCase().includes(q))
        return fontMenuAllowSame && (q === "" || "same as monospace".includes(q)) ? [""].concat(found) : found
    }

    function openFontMenu(row: var, field: Item): void {
        if (fontMenuKey === row.key) {
            fontMenuKey = ""
            return
        }
        const p = field.mapToItem(frame, 0, field.height + 4)
        fontMenuX = p.x
        fontMenuY = p.y
        fontMenuWidth = field.width
        fontMenuAllowSame = row.allowSame === true
        fontSearch.text = ""
        fontMenuKey = row.key
        fontSearch.forceActiveFocus()
    }

    function pickFont(family: string): void {
        set(fontMenuKey, family)
        fontMenuKey = ""
    }

    // --- Sections ---------------------------------------------------------

    readonly property var sections: [
        { id: "appearance", label: "Appearance", desc: "Wallpaper, palette and mode", custom: true, groups: [
            { title: "Options", rows: [
                { key: "folder", label: "Wallpaper folder", hint: "Images shown above", type: "text", browse: true },
                { key: "transition", label: "Transition", hint: "When the wallpaper changes", type: "segmented",
                  options: [{ value: "none", label: "None" }, { value: "fade", label: "Fade" }, { value: "wipe", label: "Wipe" },
                            { value: "disc", label: "Disc" }, { value: "nix", label: "Nix" }, { value: "nix-rnd", label: "Nix Rnd" }, { value: "spore", label: "Spore" }, { value: "random", label: "Random" }] },
                { key: "videos", label: "Video wallpapers", hint: "Play once when chosen, at startup and after unlocking. Off: they stay as a still image and use much less memory", type: "toggle" }
            ]}
        ]},
        // Separate from Appearance: there the wallpaper grid takes all the spare
        // height.
        { id: "fonts", label: "Fonts", desc: "Typefaces used across the shell", groups: [
            { title: "Typefaces", rows: [
                { key: "fontInterface", label: "Interface", hint: "Menus, panels and most text", type: "font" },
                { key: "fontMonospace", label: "Monospace", hint: "Numbers, times and values", type: "font" },
                { key: "fontBar", label: "Bar", hint: "The top bar", type: "font", allowSame: true }
            ]}
        ]},
        { id: "bar", label: "Bar", desc: "Layout and content of the top bar", groups: [
            { title: "Layout", rows: [
                { key: "style", label: "Style", type: "segmented",
                  options: [{ value: "full", label: "Full" }, { value: "floating", label: "Floating" }, { value: "pill", label: "Pill" }] },
                { key: "opacity", label: "Opacity", hint: "Bar background; at 0% only the capsules show", type: "percent" }
            ]},
            { title: "Content", rows: [
                { key: "clockFormat", label: "Clock format", hint: "Qt date format, e.g. ddd, MMM d  hh:mm", type: "text" },
                { key: "launcher", label: "Launcher command", hint: "Opened by the Launcher widget", type: "text" }
            ]},
            // Rows built from bar.layout (see widgetRows).
            // One block per bar zone and one for the hidden ones.
            { title: "Widgets · Left", widgets: "left" },
            { title: "Widgets · Center", widgets: "center" },
            { title: "Widgets · Right", widgets: "right" },
            { title: "Widgets · Hidden", widgets: "hidden" }
        ]},
        { id: "lock", label: "Lock screen", desc: "Shown while the session is locked", groups: [
            { title: "Weather", rows: [
                { key: "weatherOn", label: "Show weather", hint: "From Open-Meteo every 30 minutes, which sees your IP address. Off by default", type: "toggle" },
                // Auto mode uses it too (Appearance): editable even with the weather off.
                { key: "weatherLocation", label: "Location", type: "text", placeholder: "City, state or country" },
                { key: "weatherUnits", label: "Units", type: "segmented", offHint: "Enable weather to edit",
                  options: [{ value: "metric", label: "°C · km/h" }, { value: "imperial", label: "°F · mph" }] }
            ]}
        ]},
        { id: "idle", label: "Idle", desc: "What happens when you step away", groups: [
            { title: "Timers", idleCounter: true, rows: [
                { key: "lockAfter", label: "Lock screen", hint: "Minutes of inactivity before locking", type: "minutes", step: 1 },
                { key: "screenOffAfter", label: "Turn off screen", type: "minutes", step: 1 },
                { key: "suspendAfter", label: "Suspend", hint: "Always locks first", type: "minutes", step: 5 }
            ]}
        ]},
        // Its view is built separately (see "About" below).
        { id: "about", label: "About", desc: "Spore Shell", groups: [] }
    ]

    // About: Quickshell's and niri's versions, and where the shell runs from
    // (the checkout in dev mode, or the package).
    property string quickshellVersion: ""
    readonly property string runningFrom: Quickshell.shellDir
    readonly property bool devMode: !runningFrom.startsWith("/nix/store")

    Process {
        running: root.activeSection === "about"
        command: [Quickshell.env("SPORE_QUICKSHELL") || "quickshell", "--version"]
        stdout: StdioCollector {
            // "Quickshell 0.3.1 (revision …)": the second word.
            onStreamFinished: root.quickshellVersion = text.split("\n")[0].split(" ")[1] || ""
        }
    }

    // Section on open (shell.qml: spore-ipc settings open <id>).
    property string activeSection: "appearance"
    readonly property var current: sections.find(s => s.id === activeSection) || sections[0]

    // --- Values (read from and saved to settings.json) --------------------

    // lock.weather from settings.json (see Weather.qml): null, nothing chosen
    // yet, is off.
    readonly property var weatherCfg: settings.lockWeather || ({})
    readonly property bool weatherOn: settings.lockWeather !== null && weatherCfg.enabled !== false
    readonly property bool weatherHasPlace: weatherCfg.latitude !== undefined && weatherCfg.longitude !== undefined

    // Lookup of what's typed in "Location": "", "searching" or "notFound".
    property string locationStatus: ""
    property string locationQuery: ""

    Geocoder {
        id: geocoder
        onDone: (result) => {
            if (!result) {
                root.locationStatus = "notFound"
                return
            }
            root.locationStatus = ""
            root.settings.save({ lock: { weather: {
                enabled: root.weatherOn,
                location: root.locationQuery,
                name: result.name,
                region: result.region,
                latitude: result.latitude,
                longitude: result.longitude
            } } })
        }
    }

    function describePlace(p: var): string {
        return p.region ? p.name + ", " + p.region : p.name
    }

    // A row's help text; the "Location" one says which place is in use.
    function hintFor(row: var, disabled: bool): string {
        if (disabled && row.offHint) return row.offHint
        if (row.key !== "weatherLocation") return row.hint || ""
        if (locationStatus === "searching") return "Searching…"
        if (locationStatus === "notFound") return "Not found. Try adding the state or country, e.g. Springfield, IL"
        if (weatherHasPlace) return describePlace(weatherCfg)
        const tz = root.weather ? root.weather.timezonePlace : null
        return "Empty: uses your time zone" + (tz ? " (" + describePlace(tz) + ")" : "")
    }

    function value(key: string): var {
        if (key.startsWith("widgetOpt:")) {
            const [, id, opt] = key.split(":")
            return settings.widgetOption(id, opt)
        }
        switch (key) {
        case "lockAfter": return settings.lockAfter
        case "screenOffAfter": return settings.screenOffAfter
        case "suspendAfter": return settings.suspendAfter
        case "style": return settings.barStyle
        case "opacity": return settings.barOpacity
        case "clockFormat": return settings.clockFormat
        case "fontInterface": return settings.fontInterface
        case "fontMonospace": return settings.fontMonospace
        case "fontBar": return settings.fontBar
        case "launcher": return settings.launcher.join(" ")
        case "folder": return settings.wallpaperDirRaw
        case "transition": return settings.wallpaperTransition
        case "videos": return settings.videoWallpapers
        case "weatherOn": return weatherOn
        case "weatherUnits": return settings.lockUnits
        // Old configs have no `location`: the closest thing is the name.
        case "weatherLocation": return weatherCfg.location ?? (weatherHasPlace ? weatherCfg.name : "")
        }
        return ""
    }

    // − / + controls: minutes (0 = Never) or percentage (in 10% steps).
    function stepValue(row: var, v: real, dir: int): real {
        if (row.type === "percent") return Math.max(0, Math.min(1, Math.round(v * 10 + dir) / 10))
        return Math.max(0, Math.min(240 * 60, v + dir * row.step * 60))
    }

    function stepLabel(row: var, v: real): string {
        if (row.type === "percent") return Math.round(v * 100) + "%"
        return v === 0 ? "Never" : Math.round(v / 60) + " min"
    }

    function isDisabled(key: string): bool {
        switch (key) {
        case "weatherUnits": return !weatherOn
        }
        return false
    }

    function set(key: string, v: var): void {
        if (key.startsWith("widgetOpt:")) {
            const [, id, opt] = key.split(":")
            const all = JSON.parse(JSON.stringify(settings.widgetOptions))
            all[id] = Object.assign({}, all[id], { [opt]: v })
            settings.save({ bar: { widgetOptions: all } })
            return
        }
        switch (key) {
        case "lockAfter": case "screenOffAfter": case "suspendAfter":
            settings.save({ idle: { [key]: v } })
            break
        case "style": settings.save({ bar: { style: v } }); break
        case "opacity": settings.save({ bar: { opacity: v } }); break
        case "clockFormat": settings.save({ bar: { clockFormat: v } }); break
        case "fontInterface": settings.save({ fonts: { interface: v } }); break
        case "fontMonospace": settings.save({ fonts: { monospace: v } }); break
        case "fontBar": settings.save({ fonts: { bar: v } }); break
        case "launcher": settings.save({ bar: { launcher: v.trim().split(/\s+/).filter(a => a !== "") } }); break
        case "folder": settings.save({ picker: { wallpaperDir: v.trim() } }); break
        case "transition": settings.save({ wallpaper: { transition: v } }); break
        case "videos": settings.save({ wallpaper: { videos: v } }); break
        case "weatherUnits": settings.save({ lock: { units: v } }); break
        case "weatherOn":
            settings.save({ lock: { weather: Object.assign({}, weatherCfg, { enabled: v }) } })
            break
        case "weatherLocation": {
            const q = v.trim()
            if (q === "") {
                // Empty: go back to the time zone (no stored coordinates).
                locationStatus = ""
                settings.save({ lock: { weather: { enabled: weatherOn } } })
            } else {
                locationStatus = "searching"
                locationQuery = q
                geocoder.search(q, "")
            }
            break
        }
        }
    }

    // --- Bar widgets -----------------------------------------------------------

    // bar.layout is zones with groups (capsules). To edit it, each zone is
    // flattened into a list of { id, joined }: joined = it goes in the same
    // capsule as the previous one.
    readonly property var zones: ["left", "center", "right"]
    // Icons: where it sits on the bar (blocks against the edge) or hidden.
    readonly property var zoneOptions: [
        { value: "left", label: "Left", icon: "align-horizontal-justify-start" },
        { value: "center", label: "Center", icon: "align-horizontal-justify-center" },
        { value: "right", label: "Right", icon: "align-horizontal-justify-end" },
        { value: "hidden", label: "Hidden", icon: "eye-off" }
    ]
    readonly property var widgetLabels: ({
        launcher: "Launcher", about: "About (NixOS logo)", controlCenter: "Control Center", activeWindow: "Active window", apps: "Open apps",
        system: "System", cpu: "CPU", memory: "Memory", gpu: "GPU", workspaces: "Workspaces", clipboard: "Clipboard",
        audio: "Volume", bluetooth: "Bluetooth", network: "Network", idleInhibitor: "Idle inhibitor", screencast: "Screen sharing", notifications: "Notifications", drives: "Drives",
        clock: "Clock", power: "Power"
    })

    function flatLayout(): var {
        const out = {}
        for (const z of zones)
            out[z] = settings.barLayout[z].reduce((acc, g) => acc.concat(g.map((id, i) => ({ id: id, joined: i > 0 }))), [])
        return out
    }

    function saveFlat(flat: var): void {
        const out = {}
        for (const z of zones) {
            out[z] = []
            for (const e of flat[z]) {
                if (e.joined && out[z].length > 0) out[z][out[z].length - 1].push(e.id)
                else out[z].push([e.id])
            }
        }
        settings.save({ bar: { layout: out } })
    }

    // Removes the one at position i. If it started a capsule, the next one in
    // that capsule starts it now.
    function takeWidget(list: var, i: int): var {
        const e = list.splice(i, 1)[0]
        if (!e.joined && i < list.length && list[i].joined) list[i].joined = false
        return e
    }

    function setWidgetZone(id: string, zone: string): void {
        const flat = flatLayout()
        for (const z of zones) {
            const i = flat[z].findIndex(e => e.id === id)
            if (i >= 0) takeWidget(flat[z], i)
        }
        if (zone !== "hidden") flat[zone].push({ id: id, joined: false })
        saveFlat(flat)
    }

    // Inside its capsule, swaps places with its neighbor. At the capsule's
    // edge, it leaves it and moves, on its own, to the other side of the
    // neighboring capsule.
    function moveWidget(id: string, zone: string, dir: int): void {
        const flat = flatLayout()
        const list = flat[zone]
        const i = list.findIndex(e => e.id === id)
        const j = i + dir
        if (i < 0 || j < 0 || j >= list.length) return
        const sameCapsule = dir < 0 ? list[i].joined : list[j].joined
        if (sameCapsule) {
            [list[i].id, list[j].id] = [list[j].id, list[i].id]
        } else {
            takeWidget(list, i)
            let k = dir < 0 ? i - 1 : i
            if (dir < 0) {
                while (k > 0 && list[k].joined) k--
            } else {
                k++
                while (k < list.length && list[k].joined) k++
            }
            list.splice(k, 0, { id: id, joined: false })
        }
        saveFlat(flat)
    }

    function toggleJoin(id: string, zone: string): void {
        const flat = flatLayout()
        const i = flat[zone].findIndex(e => e.id === id)
        if (i <= 0) return
        flat[zone][i].joined = !flat[zone][i].joined
        saveFlat(flat)
    }

    // The widget whose options are expanded (the gear on its row), or "".
    property string expandedWidget: ""

    // Its option rows, below the widget's (indented). The key is
    // "widgetOpt:<id>:<option>" (see value and set).
    function optionRows(id: string): var {
        if (id !== expandedWidget) return []
        return (settings.widgetOptionDefs[id] || []).map(d => ({ key: "widgetOpt:" + id + ":" + d.key,
            type: d.type, label: d.label, hint: d.hint, sub: true }))
    }

    // Each block's rows (left, center, right and hidden), in the bar's order.
    // No help text: the ones in the same capsule read as one (no divider
    // between them) and every row has the same height.
    readonly property var widgetRows: {
        const flat = flatLayout()
        const out = { hidden: [] }
        for (const z of zones) {
            const list = flat[z]
            out[z] = list.reduce((acc, e, i) => acc.concat([{ key: "widget", type: "widget", id: e.id, label: widgetLabels[e.id], zone: z,
                joined: e.joined, canUp: i > 0, canDown: i < list.length - 1, canJoin: i > 0,
                hasOptions: settings.widgetOptionDefs[e.id] !== undefined }], optionRows(e.id)), [])
        }
        for (const id of settings.barWidgets) {
            if (!zones.some(z => flat[z].some(e => e.id === id)))
                out.hidden.push({ key: "widget", type: "widget", id: id, label: widgetLabels[id], zone: "hidden", joined: false,
                    hasOptions: settings.widgetOptionDefs[id] !== undefined }, ...optionRows(id))
        }
        // An empty block says so.
        for (const z in out)
            if (out[z].length === 0)
                out[z] = [{ key: "widget", type: "empty", label: z === "hidden" ? "Every widget is on the bar" : "No widgets here" }]
        return out
    }

    // A row's three zone buttons: the other two zones and hide, or (if it's
    // hidden) the three zones. Always three, so the rows stay even.
    function zoneTargets(zone: string): var {
        return zone === "hidden" ? zoneOptions.filter(o => o.value !== "hidden")
            : zoneOptions.filter(o => o.value !== zone)
    }

    // --- Controls ---------------------------------------------------------

    // Interface text in Noto Sans (theme.uiFont, the brand's). Numbers, values
    // and text fields use the monospace one (theme.fontFamily). Plain text,
    // never markup (see UiText.qml): a place's name comes from the weather's
    // server.
    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    component SmallButton: Rectangle {
        id: smallButton
        property string label: ""
        // A Lucide icon instead of the text.
        property string icon: ""
        property bool enabled: true
        // On (e.g. the shared capsule one).
        property bool active: false
        signal clicked()

        implicitWidth: 34
        implicitHeight: 34
        radius: 8
        color: active ? root.theme.accent : area.containsMouse && enabled ? root.buttonHover : root.button

        Label {
            anchors.centerIn: parent
            visible: smallButton.icon === ""
            text: smallButton.label
            color: smallButton.active ? root.theme.textOnAccent : root.theme.text
            font.pixelSize: 14
        }

        Icon {
            anchors.centerIn: parent
            visible: smallButton.icon !== ""
            name: smallButton.icon
            size: 15
            stroke: 1.4
            color: smallButton.active ? root.theme.textOnAccent : root.theme.text
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: smallButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (smallButton.enabled) smallButton.clicked()
        }
    }

    // Options in a row, one chosen.
    component Segmented: Rectangle {
        id: segmented
        property var options: []
        property var current
        signal picked(var value)

        implicitWidth: segments.implicitWidth + 6
        implicitHeight: 34
        radius: 9
        color: root.track

        Row {
            id: segments
            anchors.centerIn: parent
            spacing: 2

            Repeater {
                model: segmented.options

                Rectangle {
                    required property var modelData
                    readonly property bool active: modelData.value === segmented.current

                    // With `icon`, a square button with the Lucide icon instead of the text
                    // (the text stays for screen readers).
                    readonly property bool iconOnly: (modelData.icon ?? "") !== ""
                    width: iconOnly ? 34 : segmentLabel.implicitWidth + 28
                    height: 28
                    radius: 7
                    color: active ? root.theme.accent : segmentArea.containsMouse ? root.buttonHover : "transparent"
                    Accessible.name: modelData.label

                    Icon {
                        anchors.centerIn: parent
                        visible: parent.iconOnly
                        name: parent.modelData.icon ?? ""
                        size: 15
                        stroke: 1.5
                        color: parent.active ? root.theme.textOnAccent : root.theme.text
                    }

                    Label {
                        id: segmentLabel
                        anchors.centerIn: parent
                        visible: !parent.iconOnly
                        text: modelData.label
                        color: parent.active ? root.theme.textOnAccent : root.theme.text
                        font.pixelSize: 12
                        font.weight: parent.active ? Font.Medium : Font.Normal
                    }

                    MouseArea {
                        id: segmentArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: if (!parent.active) segmented.picked(parent.modelData.value)
                    }
                }
            }
        }
    }

    component SectionHeader: Label {
        color: root.theme.accent
        font.pixelSize: 11
        font.bold: true
        font.capitalization: Font.AllUppercase
        font.letterSpacing: 1
    }

    // Palette/mode preview: background, a "bar" strip and an accent dot with
    // the real colors.
    component Swatch: Item {
        id: swatch
        property var colors: null
        // Auto: the right half with these colors (the dark variant).
        property var splitColors: null
        property string label: ""
        property bool selected: false
        signal chosen()

        implicitWidth: 80
        implicitHeight: 50 + 6 + swatchLabel.implicitHeight

        Rectangle {
            id: swatchBox
            width: 80
            height: 50
            radius: 8
            color: swatch.colors ? swatch.colors.base : root.button

            // Right half: rounded outside, straight in the middle.
            Rectangle {
                visible: swatch.splitColors !== null
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: parent.width / 2
                radius: parent.radius
                color: swatch.splitColors ? swatch.splitColors.base : "transparent"

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                    width: parent.radius
                    color: parent.color
                }
            }

            Rectangle {
                visible: swatch.colors !== null && swatch.splitColors === null
                anchors { top: parent.top; left: parent.left; right: parent.right; margins: 5 }
                height: 5
                radius: 2.5
                color: swatch.colors ? swatch.colors.surface : "transparent"
            }

            Rectangle {
                visible: swatch.colors !== null
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 11
                width: 14
                height: 14
                radius: 7
                color: swatch.colors ? swatch.colors.accent : "transparent"
            }

            Label {
                visible: swatch.colors === null
                anchors.centerIn: parent
                text: "not generated"
                color: root.muted
                font.pixelSize: 10
            }

            // Border on top of everything (the right half would cover it).
            Rectangle {
                anchors.fill: parent
                radius: parent.radius
                color: "transparent"
                border.width: 2
                border.color: swatch.selected ? root.theme.accent : root.subtle
            }

            MouseArea {
                anchors.fill: parent
                enabled: swatch.colors !== null
                cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                onClicked: swatch.chosen()
            }
        }

        Label {
            id: swatchLabel
            anchors.top: swatchBox.bottom
            anchors.topMargin: 6
            anchors.horizontalCenter: swatchBox.horizontalCenter
            text: swatch.label
            color: swatch.selected ? root.theme.text : root.soft
            font.pixelSize: 12
        }
    }

    // A settings row: title and help on the left, control on the right.
    component SettingRow: Item {
        id: rowItem
        required property var row
        property bool first: false
        readonly property bool disabled: root.isDisabled(row.key)
        readonly property var val: root.value(row.key)

        // There are many widgets and they only have a name and buttons: shorter
        // rows.
        implicitHeight: row.type === "widget" || row.type === "empty" || row.sub === true ? Math.max(44, rowContent.implicitHeight + 10)
            : Math.max(60, rowContent.implicitHeight + 20)
        opacity: disabled ? 0.4 : 1

        // Divider between rows. Not between widgets of the same capsule (linked
        // to the one above): that way they read as a group.
        Rectangle {
            visible: !rowItem.first && !(rowItem.row.type === "widget" && rowItem.row.joined)
            anchors { top: parent.top; left: parent.left; right: parent.right }
            // A widget's options, indented: they read as part of it.
            anchors.leftMargin: rowItem.row.sub === true ? 40 : 0
            height: 1
            color: root.subtle
        }

        RowLayout {
            id: rowContent
            anchors.fill: parent
            anchors.leftMargin: rowItem.row.sub === true ? 40 : 16
            anchors.rightMargin: 16
            spacing: 24

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    Layout.fillWidth: true
                    text: rowItem.row.label
                    color: rowItem.row.type === "empty" ? root.muted : root.theme.text
                    font.pixelSize: 14
                }

                Label {
                    Layout.fillWidth: true
                    readonly property string hint: root.hintFor(rowItem.row, rowItem.disabled)
                    visible: hint !== ""
                    text: hint
                    color: root.muted
                    font.pixelSize: 12
                    wrapMode: Text.WordWrap
                }
            }

            // Stepper: minutes (0 = Never) or percentage.
            RowLayout {
                visible: ["minutes", "percent"].includes(rowItem.row.type)
                spacing: 4

                SmallButton {
                    icon: "minus"
                    enabled: !rowItem.disabled
                    onClicked: root.set(rowItem.row.key, root.stepValue(rowItem.row, rowItem.val, -1))
                }

                Label {
                    Layout.preferredWidth: 76
                    horizontalAlignment: Text.AlignHCenter
                    text: root.stepLabel(rowItem.row, rowItem.val)
                    color: rowItem.row.type === "minutes" && rowItem.val === 0 ? root.muted : root.theme.text
                    font.family: root.theme.fontFamily
                    font.pixelSize: 13
                }

                SmallButton {
                    icon: "plus"
                    enabled: !rowItem.disabled
                    onClicked: root.set(rowItem.row.key, root.stepValue(rowItem.row, rowItem.val, 1))
                }
            }

            // Toggle.
            Rectangle {
                visible: rowItem.row.type === "toggle"
                implicitWidth: 44
                implicitHeight: 24
                radius: 12
                color: rowItem.val === true ? root.theme.accent : root.inputBorder

                Rectangle {
                    width: 18
                    height: 18
                    radius: 9
                    anchors.verticalCenter: parent.verticalCenter
                    x: rowItem.val === true ? parent.width - width - 3 : 3
                    color: rowItem.val === true ? root.theme.textOnAccent : root.muted
                    Behavior on x { NumberAnimation { duration: 120 } }
                }

                MouseArea {
                    anchors.fill: parent
                    cursorShape: rowItem.disabled ? Qt.ArrowCursor : Qt.PointingHandCursor
                    onClicked: if (!rowItem.disabled) root.set(rowItem.row.key, rowItem.val !== true)
                }
            }

            Segmented {
                visible: rowItem.row.type === "segmented"
                options: rowItem.row.options || []
                current: rowItem.val
                onPicked: (v) => root.set(rowItem.row.key, v)
            }

            // Bar widget: zone, order and shared capsule.
            RowLayout {
                visible: rowItem.row.type === "widget"
                spacing: 4

                // Its options (if it has any): they expand below. For those without, the
                // spot stays empty, so the buttons stay aligned.
                SmallButton {
                    Layout.rightMargin: 8
                    icon: "settings"
                    opacity: rowItem.row.hasOptions === true ? 1 : 0
                    enabled: rowItem.row.hasOptions === true
                    active: root.expandedWidget === rowItem.row.id
                    onClicked: root.expandedWidget = root.expandedWidget === rowItem.row.id ? "" : rowItem.row.id
                }

                Repeater {
                    model: rowItem.row.type === "widget" ? root.zoneTargets(rowItem.row.zone) : []

                    SmallButton {
                        required property var modelData
                        required property int index
                        // Room between the zone buttons and the order ones.
                        Layout.rightMargin: index === 2 && rowItem.row.zone !== "hidden" ? 8 : 0
                        icon: modelData.icon
                        Accessible.name: "Move to " + modelData.label
                        onClicked: root.setWidgetZone(rowItem.row.id, modelData.value)
                    }
                }

                // Hidden: the arrows' and the link's spots stay empty, so their buttons
                // sit in the same column as the zone buttons of the other blocks.
                Item {
                    visible: rowItem.row.zone === "hidden"
                    implicitWidth: 8 + 3 * 34 + 2 * 4
                    implicitHeight: 1
                }

                SmallButton {
                    visible: rowItem.row.zone !== "hidden"
                    icon: "arrow-up"
                    enabled: rowItem.row.canUp === true
                    opacity: enabled ? 1 : 0.35
                    onClicked: root.moveWidget(rowItem.row.id, rowItem.row.zone, -1)
                }

                SmallButton {
                    visible: rowItem.row.zone !== "hidden"
                    icon: "arrow-down"
                    enabled: rowItem.row.canDown === true
                    opacity: enabled ? 1 : 0.35
                    onClicked: root.moveWidget(rowItem.row.id, rowItem.row.zone, 1)
                }

                // Same capsule as the one above.
                SmallButton {
                    visible: rowItem.row.zone !== "hidden"
                    icon: "link"
                    active: rowItem.row.joined === true
                    enabled: rowItem.row.canJoin === true
                    opacity: enabled ? 1 : 0.35
                    onClicked: root.toggleJoin(rowItem.row.id, rowItem.row.zone)
                }
            }

            // Read-only (About: versions).
            Label {
                visible: rowItem.row.type === "info"
                text: rowItem.row.value ?? ""
                color: root.soft
                font.family: root.theme.fontFamily
                font.pixelSize: 13
            }

            // Font: the name written in that font; opens the list (fontMenu).
            Rectangle {
                id: fontField
                readonly property string family: rowItem.row.type === "font" ? String(rowItem.val ?? "") : ""
                visible: rowItem.row.type === "font"
                Layout.preferredWidth: Math.min(300, rowItem.width / 2)
                implicitHeight: 36
                radius: 8
                color: fontFieldArea.containsMouse ? root.buttonHover : root.inputBg
                border.width: 1
                border.color: root.fontMenuKey === rowItem.row.key ? root.theme.accent : root.inputBorder

                Label {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 12
                    anchors.rightMargin: 32
                    anchors.verticalCenter: parent.verticalCenter
                    text: fontField.family === "" ? "Same as Monospace" : fontField.family
                    color: fontField.family === "" ? root.muted : root.theme.text
                    font.family: fontField.family === "" ? root.settings.fontMonospace : fontField.family
                    font.pixelSize: 13
                    elide: Text.ElideRight
                }
                Icon {
                    anchors.right: parent.right
                    anchors.rightMargin: 12
                    anchors.verticalCenter: parent.verticalCenter
                    name: "chevron-down"
                    size: 13
                    color: root.theme.ink2
                }
                MouseArea {
                    id: fontFieldArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.openFontMenu(rowItem.row, fontField)
                }
            }

            // Text: saves on Enter or when leaving the field.
            Rectangle {
                visible: rowItem.row.type === "text"
                Layout.preferredWidth: Math.min(300, rowItem.width / 2)
                implicitHeight: 36
                radius: 8
                color: root.inputBg
                border.width: 1
                border.color: input.activeFocus ? root.theme.accent : root.inputBorder

                TextInput {
                    id: input
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    enabled: !rowItem.disabled
                    text: String(rowItem.val)
                    color: root.theme.text
                    selectionColor: root.theme.accent
                    selectedTextColor: root.theme.textOnAccent
                    selectByMouse: true
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    onEditingFinished: if (text !== String(rowItem.val)) root.set(rowItem.row.key, text)

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: input.text === "" && !input.activeFocus
                        text: rowItem.row.placeholder || ""
                        font.family: root.theme.fontFamily
                        color: root.muted
                        font.pixelSize: 12
                    }
                }
            }

            // Choose with the picker (rows with `browse`).
            SmallButton {
                visible: rowItem.row.type === "text" && rowItem.row.browse === true
                icon: "folder"
                onClicked: root.folderPickerRequested()
            }
        }
    }

    // Idle → next to TIMERS: "Idle 1 s", "Idle 2 s"… while nothing is touched,
    // to see the count working. Two 1 s monitors while the section is open:
    // the one that ignores inhibitors says when idleness started; if the other
    // one doesn't see it, an app is preventing it.
    component IdleCounter: Label {
        id: counter

        property real since: 0
        property real now: Date.now()
        readonly property int seconds: since > 0 ? Math.floor((now - since) / 1000) : 0

        IdleMonitor {
            id: rawMonitor
            timeout: 1
            respectInhibitors: false
            onIsIdleChanged: {
                counter.since = isIdle ? Date.now() - 1000 : 0
                counter.now = Date.now()
            }
        }
        IdleMonitor {
            id: awareMonitor
            timeout: 1
            respectInhibitors: true
        }
        Timer {
            interval: 1000
            repeat: true
            running: rawMonitor.isIdle
            onTriggered: counter.now = Date.now()
        }

        text: root.caffeine ? "Caffeine on"
            : rawMonitor.isIdle && !awareMonitor.isIdle ? "Inhibited by an app"
            : "Idle " + (seconds < 60 ? seconds + " s" : Math.floor(seconds / 60) + " min " + seconds % 60 + " s")
        color: root.caffeine || (rawMonitor.isIdle && !awareMonitor.isIdle) ? root.theme.warn : root.muted
        font.family: root.theme.fontFamily
        font.pixelSize: 12
    }

    // Group: an uppercase title and a card with its rows.
    component GroupCard: ColumnLayout {
        id: groupCard
        required property var group
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            SectionHeader {
                Layout.fillWidth: true
                text: groupCard.group.title
            }
            // Only in Idle (with its monitors): in the other groups it isn't created.
            Loader {
                active: groupCard.group.idleCounter === true
                sourceComponent: IdleCounter {}
            }
        }

        Rectangle {
            Layout.fillWidth: true
            implicitHeight: groupRows.implicitHeight
            radius: 10
            color: root.groupBg
            border.width: 1
            border.color: root.subtle

            ColumnLayout {
                id: groupRows
                anchors.left: parent.left
                anchors.right: parent.right
                spacing: 0

                Repeater {
                    model: groupCard.group.widgets ? root.widgetRows[groupCard.group.widgets] : groupCard.group.rows

                    SettingRow {
                        required property var modelData
                        required property int index
                        Layout.fillWidth: true
                        row: modelData
                        first: index === 0
                    }
                }
            }
        }
    }

    // --- Window -------------------------------------------------------------

    Rectangle {
        id: frame
        anchors.fill: parent
        // Keys and not Shortcut: Shortcut only fires in Qt's "active" window, and a
        // layer-shell surface never is one.
        focus: true
        Keys.onEscapePressed: root.closeRequested()
        radius: root.cornerRadius
        color: root.theme.base
        // Like niri's border: accent with focus, gray without.
        border.width: 1
        border.color: Window.active ? root.theme.accent : root.theme.inactiveBorder
        clip: true

        // Click on the background: takes focus away from the text fields (and
        // saves them).
        MouseArea {
            anchors.fill: parent
            onClicked: frame.forceActiveFocus()
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // --- Sidebar ---
            Rectangle {
                Layout.fillHeight: true
                Layout.preferredWidth: 188
                color: root.sidebarBg
                // Left corners of the frame: the clip trims the radius.
                radius: root.cornerRadius

                // Covers the radius on the right side (only the outer corners are
                // rounded).
                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: parent.radius
                    color: root.sidebarBg
                }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                    width: 1
                    color: root.subtle
                }

                ColumnLayout {
                    anchors.fill: parent
                    anchors.topMargin: 20
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    anchors.bottomMargin: 16
                    spacing: 16

                    Label {
                        Layout.leftMargin: 8
                        text: "Settings"
                        font.pixelSize: 20
                        font.weight: Font.Medium
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2

                        Repeater {
                            model: root.sections

                            Rectangle {
                                required property var modelData
                                readonly property bool active: modelData.id === root.current.id

                                Layout.fillWidth: true
                                implicitHeight: 36
                                radius: 8
                                color: active ? root.navActive : navArea.containsMouse ? root.groupBg : "transparent"

                                Rectangle {
                                    visible: parent.active
                                    anchors.left: parent.left
                                    anchors.leftMargin: 10
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 3
                                    height: 16
                                    radius: 2
                                    color: root.theme.accent
                                }

                                Label {
                                    anchors.left: parent.left
                                    anchors.leftMargin: 23
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: modelData.label
                                    color: parent.active ? root.theme.accent : navArea.containsMouse ? root.theme.text : root.soft
                                    font.pixelSize: 13
                                    font.weight: parent.active ? Font.Medium : Font.Normal
                                }

                                MouseArea {
                                    id: navArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.activeSection = parent.modelData.id
                                }
                            }
                        }
                    }

                    Item { Layout.fillHeight: true }

                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 10
                        spacing: 8

                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            color: root.theme.current.ansi ? root.theme.current.ansi[2] : root.theme.accent
                        }

                        Label {
                            // The mono font is wider than the design's: if it doesn't fit, wrap
                            // instead of widening the sidebar.
                            Layout.fillWidth: true
                            wrapMode: Text.Wrap
                            text: "Saved to settings.json"
                            color: root.muted
                            font.pixelSize: 11
                        }
                    }
                }
            }

            // --- Content ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 0

                // Anchors and not RowLayout: inside a layout the ✕ stuck to the title.
                Item {
                    Layout.fillWidth: true
                    Layout.topMargin: 24
                    Layout.bottomMargin: 8
                    implicitHeight: Math.max(headerText.implicitHeight, 36)

                    ColumnLayout {
                        id: headerText
                        anchors.left: parent.left
                        anchors.leftMargin: 28
                        anchors.right: closeButton.left
                        anchors.rightMargin: 16
                        spacing: 4

                        Label {
                            text: root.current.label
                            font.pixelSize: 18
                            font.weight: Font.Medium
                        }

                        Label {
                            text: root.current.desc
                            color: root.muted
                            font.pixelSize: 12
                        }
                    }

                    SmallButton {
                        id: closeButton
                        anchors.right: parent.right
                        anchors.rightMargin: 28
                        anchors.top: parent.top
                        width: 36
                        height: 36
                        icon: "x"
                        onClicked: root.closeRequested()
                    }
                }

                // Appearance: the wallpaper grid is the only thing that scrolls; palette,
                // mode and folder always stay in view.
                ColumnLayout {
                    visible: root.current.custom === true
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.leftMargin: 28
                    Layout.rightMargin: 28
                    Layout.topMargin: 16
                    Layout.bottomMargin: 24
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true

                        SectionHeader {
                            Layout.fillWidth: true
                            text: "Wallpaper"
                        }

                        Rectangle {
                            implicitWidth: previewLabel.implicitWidth + 24
                            implicitHeight: 30
                            radius: 8
                            color: previewArea.containsMouse ? root.button : "transparent"
                            border.width: 1
                            border.color: previewArea.containsMouse ? root.theme.accent : root.inputBorder

                            Label {
                                id: previewLabel
                                anchors.centerIn: parent
                                text: "Preview on desktop"
                                font.pixelSize: 12
                            }

                            MouseArea {
                                id: previewArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.previewRequested()
                            }
                        }
                    }

                    // GridView and not Grid + Repeater: it only creates the visible thumbnails
                    // (with 100+ wallpapers, opening was slow). As many ~120px columns as fit;
                    // 16:10. Each cell carries the gap on its right and bottom: the view is
                    // `gap` wider than the column, so the last one lines up with the edge.
                    GridView {
                        id: wallGrid
                        readonly property int gap: 8
                        readonly property int cols: Math.max(1, Math.floor(width / (120 + gap)))
                        readonly property real thumbWidth: width / cols - gap

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.rightMargin: -gap
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds
                        cellWidth: width / cols
                        cellHeight: thumbWidth * 10 / 16 + gap
                        model: root.wallpapers.files

                        delegate: Item {
                            required property string modelData
                            width: wallGrid.cellWidth
                            height: wallGrid.cellHeight

                            WallpaperThumb {
                                width: wallGrid.thumbWidth
                                height: wallGrid.thumbWidth * 10 / 16
                                theme: root.theme
                                wallpapers: root.wallpapers
                                path: parent.modelData
                                selected: parent.modelData === root.currentWallpaperSource
                                onChosen: if (path !== root.currentWallpaperSource) root.wallpaperChosen(path)
                            }
                        }
                    }

                    // Palette on the left and Mode at the right edge: the spare room goes
                    // between them.
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.topMargin: 16
                        spacing: 0

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            spacing: 8

                            SectionHeader { text: "Palette" }

                            Row {
                                spacing: 10

                                Repeater {
                                    model: root.theme.paletteNames

                                    Swatch {
                                        required property string modelData
                                        colors: root.theme.colorsFor(modelData, root.theme.mode)
                                        label: root.theme.label(modelData)
                                        selected: modelData === root.theme.palette
                                        onChosen: root.paletteChosen(modelData)
                                    }
                                }
                            }
                        }

                        Item {
                            Layout.fillWidth: true
                            Layout.minimumWidth: 40
                        }

                        ColumnLayout {
                            Layout.alignment: Qt.AlignTop
                            // As wide as the swatches: with the title's row (which stretches) the
                            // column stretched too and Auto didn't line up with the grid.
                            Layout.fillWidth: false
                            spacing: 8

                            // With Auto: which mode is on now and until when, next to the title (on
                            // its own row it took height from the wallpaper grid).
                            // opacity and not visible: the title doesn't move when Auto is chosen.
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 12

                                SectionHeader {
                                    Layout.alignment: Qt.AlignBaseline
                                    text: "Mode"
                                }

                                Label {
                                    Layout.fillWidth: true
                                    // No width of its own: the swatches' row sizes the column, so Auto lines
                                    // up with the grid.
                                    Layout.preferredWidth: 0
                                    Layout.alignment: Qt.AlignBaseline
                                    horizontalAlignment: Text.AlignRight
                                    opacity: root.modeSetting === "auto" ? 1 : 0
                                    text: root.autoModeHint
                                    color: root.muted
                                    font.pixelSize: 12
                                    elide: Text.ElideRight
                                }
                            }

                            Row {
                                spacing: 10

                                Repeater {
                                    model: [{ mode: "light", label: "Light" }, { mode: "dark", label: "Dark" },
                                            { mode: "auto", label: "Auto" }]

                                    Swatch {
                                        required property var modelData
                                        function variant(m: string): var {
                                            return root.theme.colorsFor(root.theme.palette, m) || root.theme.palettes.catppuccin[m]
                                        }
                                        colors: variant(modelData.mode === "auto" ? "light" : modelData.mode)
                                        splitColors: modelData.mode === "auto" ? variant("dark") : null
                                        label: modelData.label
                                        selected: modelData.mode === root.modeSetting
                                        onChosen: root.themeModeChosen(modelData.mode)
                                    }
                                }
                            }
                        }
                    }

                    Repeater {
                        model: root.current.custom === true ? root.current.groups : []

                        GroupCard {
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.topMargin: 16
                            group: modelData
                        }
                    }
                }

                // About: the brand (the stacked lockup from Spore's handoff: mark, "spore"
                // and "SHELL"), the tagline and the versions.
                Flickable {
                    visible: root.current.id === "about"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: aboutColumn.implicitHeight + 64
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: aboutColumn
                        x: 28
                        y: 32
                        width: parent.width - 56
                        spacing: 0

                        SporeMark {
                            theme: root.theme
                            Layout.alignment: Qt.AlignHCenter
                            size: 148
                        }

                        // "spore" in Noto Sans 700 and "SHELL" right-aligned below it, ending
                        // under the "e".
                        Item {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 12
                            implicitWidth: wordmark.implicitWidth
                            implicitHeight: wordmark.implicitHeight + shellLabel.implicitHeight - 14

                            Text {
                                id: wordmark
                                text: Brand.wordmark
                                color: root.theme.isDark ? Brand.colors.bone : Brand.colors.ink
                                font.family: root.theme.uiFont
                                font.pixelSize: 72
                                font.weight: Font.Bold
                                font.letterSpacing: -1.44
                                // Exact curves: with the default mode (distance fields), at this size the
                                // edges came out thickened and the word looked bolder than in the brand.
                                renderType: Text.CurveRendering
                            }

                            Text {
                                id: shellLabel
                                anchors.right: parent.right
                                // Compensates for the spacing left after the last letter.
                                anchors.rightMargin: -font.letterSpacing
                                y: wordmark.implicitHeight - 14
                                text: "SHELL"
                                color: Brand.colors.spore
                                font.family: root.theme.fontFamily
                                font.pixelSize: 18
                                font.letterSpacing: 18 * 0.32
                                renderType: Text.CurveRendering
                            }
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 28
                            text: Brand.slogan
                            color: root.soft
                            font.family: root.theme.uiFont
                            font.pixelSize: 16
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 6
                            text: Brand.description
                            color: root.muted
                            font.family: root.theme.uiFont
                            font.pixelSize: 13
                        }

                        GroupCard {
                            Layout.fillWidth: true
                            Layout.maximumWidth: 520
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 36
                            group: ({ title: "Versions", info: true, rows: [
                                { key: "about", type: "info", label: Brand.name, hint: "The shell", value: Brand.version },
                                { key: "about", type: "info", label: "Quickshell", hint: "QML toolkit it runs on", value: root.quickshellVersion },
                                { key: "about", type: "info", label: root.compositor ? root.compositor.name : "Compositor", hint: "Wayland compositor", value: root.compositor ? root.compositor.version : "" },
                                { key: "about", type: "info", label: "Running from", hint: root.runningFrom, value: root.devMode ? "Dev checkout" : "Nix package" }
                            ] })
                        }
                    }
                }

                // The other sections: groups of rows, with scrolling if they don't fit.
                Flickable {
                    id: flick
                    visible: root.current.custom !== true && root.current.id !== "about"
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    contentHeight: content.implicitHeight + 44
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: content
                        x: 28
                        y: 16
                        width: flick.width - 56
                        spacing: 24

                        Repeater {
                            model: root.current.custom === true ? [] : root.current.groups

                            GroupCard {
                                required property var modelData
                                Layout.fillWidth: true
                                group: modelData
                            }
                        }
                    }
                }
            }
        }

        // --- The font list ("font" rows): on top of everything, below the field
        // that opened it. Search at the top and each name in its own font.
        MouseArea {
            anchors.fill: parent
            visible: root.fontMenuKey !== ""
            onClicked: root.fontMenuKey = ""
        }

        Rectangle {
            id: fontMenu
            visible: root.fontMenuKey !== ""
            x: root.fontMenuX
            y: Math.max(12, Math.min(root.fontMenuY, frame.height - height - 12))
            width: Math.max(280, root.fontMenuWidth)
            height: 320
            radius: 10
            color: root.theme.base
            border.width: 1
            border.color: root.inputBorder

            // Clicks inside don't reach the background (which closes it).
            MouseArea {
                anchors.fill: parent
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 8
                spacing: 6

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 32
                    radius: 7
                    color: root.inputBg
                    border.width: 1
                    border.color: fontSearch.activeFocus ? root.theme.accent : root.inputBorder

                    TextInput {
                        id: fontSearch
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        verticalAlignment: TextInput.AlignVCenter
                        clip: true
                        color: root.theme.text
                        selectionColor: root.theme.accent
                        selectedTextColor: root.theme.textOnAccent
                        font.family: root.theme.uiFont
                        font.pixelSize: 13
                        onTextChanged: fontList.positionViewAtBeginning()
                        Keys.onEscapePressed: (event) => {
                            root.fontMenuKey = ""
                            event.accepted = true
                        }
                        // Enter: the first match.
                        Keys.onReturnPressed: if (root.fontChoices.length > 0) root.pickFont(root.fontChoices[0])

                        Label {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: fontSearch.text === ""
                            text: "Search fonts"
                            color: root.muted
                            font.pixelSize: 13
                        }
                    }
                }

                ListView {
                    id: fontList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.fontChoices

                    delegate: Rectangle {
                        id: fontItem
                        required property string modelData
                        readonly property bool current: modelData === String(root.value(root.fontMenuKey) ?? "")
                        width: fontList.width
                        height: 30
                        radius: 6
                        color: fontItemArea.containsMouse ? root.buttonHover
                            : current ? Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.14) : "transparent"

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            anchors.verticalCenter: parent.verticalCenter
                            text: fontItem.modelData === "" ? "Same as Monospace" : fontItem.modelData
                            color: fontItem.modelData === "" ? root.muted : root.theme.text
                            font.family: fontItem.modelData === "" ? root.settings.fontMonospace : fontItem.modelData
                            font.pixelSize: 14
                            elide: Text.ElideRight
                            // A font's name comes from its file: as it is (see UiText.qml).
                            textFormat: Text.PlainText
                        }

                        MouseArea {
                            id: fontItemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.pickFont(fontItem.modelData)
                        }
                    }
                }
            }
        }
    }
}
