import QtQuick
import Quickshell
import Quickshell.Io
import "common"
import "services"
import "bar"
import "controlcenter"
import "panels"
import "lock"
import "wallpaper"

ShellRoot {
    id: root

    // Wallpaper and palette state, with a single owner: they're passed
    // explicitly as properties to everything that needs them (see below).
    // They're not a Singleton because a Quickshell Singleton's
    // Component.onCompleted never actually fired here (confirmed with
    // console.log) -- plain properties passed by hand are more predictable.
    //
    // What's chosen in the picker persists per user in $XDG_STATE_HOME/spore
    // (default ~/.local/state/spore; it can be overridden with
    // $SPORE_STATE_DIR). The shell runs from the nix store (read-only), so
    // assets/ is only the factory default until something is chosen.
    readonly property string stateDir: Quickshell.env("SPORE_STATE_DIR")
        || (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/spore"
    // Copy of the wallpaper/mode/palette/colors for the greeter, which runs
    // before login as another user and can't read the home folder. The NixOS
    // module creates it (services.spore.users): owned by the user, group
    // greeter, 2750, so no other user can read it. If it doesn't exist,
    // nothing is published.
    readonly property string publishDir: "/var/lib/spore/" + Quickshell.env("USER")
    readonly property string stateWallpaper: stateDir + "/wallpaper.jpg"
    // Path of the original copied to wallpaper.jpg: the picker uses it to know
    // which one is set (the copy doesn't match any file in the folder).
    readonly property string stateWallpaperSource: stateDir + "/wallpaper-source"
    readonly property string stateThemeMode: stateDir + "/theme-mode"
    readonly property string statePalette: stateDir + "/palette"
    // matugen's output for the current wallpaper ("wallpaper" palette).
    readonly property string stateColors: stateDir + "/colors.json"
    // Wallpaper crop for the Control Center's header (see heroGen).
    readonly property string cacheHero: (Quickshell.env("XDG_CACHE_HOME") || Quickshell.env("HOME") + "/.cache") + "/spore/cc-hero.jpg"

    // Empty until we know which one it is (wallpaperLookup): if it started with
    // the factory one, entering the session showed that one for an instant and
    // then the user's.
    property string wallpaperPath: ""
    readonly property string factoryWallpaper: Quickshell.shellPath("../assets/wallpapers/spore-dome.jpg")
    property int wallpaperVersion: 0
    property string wallpaperSource: ""
    // Video wallpaper: the original's path (wallpaperPath is its last frame).
    // "" if it's an image.
    readonly property string wallpaperVideo: wallpaperService.isVideo(wallpaperSource) ? wallpaperSource : ""
    // Every time it goes up, the video plays once (at login, on unlock and when
    // chosen).
    property int videoPlayCount: 0
    // What's chosen: "dark", "light" or "auto" (by the sun, see Sun.qml).
    property string themeModeSetting: "dark"
    // The one applied.
    readonly property string themeMode: themeModeSetting === "auto" ? (sun.isDay ? "light" : "dark") : themeModeSetting
    property string palette: "catppuccin"
    // State reads (mode, palette) still pending at startup.
    property int pendingStateReads: 2

    // settings.json (see Settings.qml), a single one for the whole session.
    Settings {
        id: shellSettings
    }

    // The writers below write to stateDir: it has to exist.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", root.stateDir])

    // Publishes the state for the greeter (see publishDir) whenever something
    // the greeter shows changes. Debounced: at startup several arrive together.
    onWallpaperVersionChanged: publishTimer.restart()
    onThemeModeChanged: {
        publishTimer.restart()
        appliedThemeTimer.restart()
    }
    onPaletteChanged: {
        publishTimer.restart()
        appliedThemeTimer.restart()
    }
    onPendingStateReadsChanged: appliedThemeTimer.restart()

    // The theme as applied, for Spore's windows that run in a process of their
    // own (Files, files.qml), which follow it live: the mode already resolved
    // ("auto" is dark or light by now) and the palette. Only once the state has
    // been read: until then they're the defaults, not the user's.
    Timer {
        id: appliedThemeTimer
        interval: 100
        onTriggered: {
            if (root.pendingStateReads === 0)
                appliedThemeFile.setText(JSON.stringify({ mode: root.themeMode, palette: root.palette }) + "\n")
        }
    }

    // Direct, without tmp + rename: the file keeps its inode and the other
    // processes' watchChanges keep seeing it (see Settings.qml).
    FileView {
        id: appliedThemeFile
        path: root.stateDir + "/theme.json"
        preload: false
        atomicWrites: false
        onSaveFailed: console.warn("Could not save the applied theme to " + path)
    }
    // The interface and numbers fonts are used by the greeter too.
    Connections {
        target: shellSettings
        function onFontInterfaceChanged() { publishTimer.restart() }
        function onFontMonospaceChanged() { publishTimer.restart() }
    }

    Timer {
        id: publishTimer
        interval: 1000
        // If it's still publishing the previous one, try again in a moment
        // (otherwise this change wasn't published). Nothing is published in a
        // nested test niri: the folder is the real greeter's, and the test left
        // its wallpaper and colors there.
        onTriggered: {
            if (sessionCompositor.nested) return
            if (publisher.running) restart()
            else publisher.running = true
        }
    }

    // 640 and tmp + mv: the greeter group comes from the folder's setgid, and
    // the greeter never reads a half-copied file. theme-mode goes with the
    // effective mode: the greeter can't resolve "auto".
    Process {
        id: publisher
        command: ["sh", "-c", `
            [ -d "$2" ] && [ -w "$2" ] || exit 0
            for f in wallpaper.jpg palette colors.json; do
                [ -f "$1/$f" ] || continue
                install -m 640 "$1/$f" "$2/.$f.tmp" && mv "$2/.$f.tmp" "$2/$f"
            done
            printf '%s' "$3" > "$2/.theme-mode.tmp" && chmod 640 "$2/.theme-mode.tmp" && mv "$2/.theme-mode.tmp" "$2/theme-mode"
            printf '%s' "$4" > "$2/.fonts.json.tmp" && chmod 640 "$2/.fonts.json.tmp" && mv "$2/.fonts.json.tmp" "$2/fonts.json"`,
            "_", root.stateDir, root.publishDir, root.themeMode,
            JSON.stringify({ interface: shellSettings.fontInterface, monospace: shellSettings.fontMonospace })]
        onExited: (exitCode) => {
            if (exitCode !== 0)
                console.warn("Could not publish the theme for the greeter to " + root.publishDir)
        }
    }

    // The session's only Theme, passed to everything that paints (see
    // Theme.qml).
    Theme {
        id: sessionTheme
        mode: root.themeMode
        palette: root.palette
        uiFont: shellSettings.fontInterface
        fontFamily: shellSettings.fontMonospace
        barFont: shellSettings.fontBar || shellSettings.fontMonospace
    }

    // Read once at startup: the state first, otherwise assets/.
    Process {
        id: wallpaperLookup
        running: true
        command: ["sh", "-c", "test -f \"$1\" && echo \"$1\"", "_", root.stateWallpaper]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpaperPath = text.trim() || root.factoryWallpaper
                root.wallpaperVersion = root.wallpaperVersion + 1
                root.regenPalette()
                root.regenHero()
            }
        }
    }

    Process {
        running: true
        command: ["cat", root.stateWallpaperSource]
        stdout: StdioCollector {
            onStreamFinished: {
                root.wallpaperSource = text.trim()
                // Video wallpaper: it plays when the session starts.
                if (root.wallpaperVideo) root.videoPlayCount++
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || cat \"$2\"", "_",
            root.stateThemeMode, Quickshell.shellPath("../assets/defaults/theme-mode")]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim()
                if (m === "dark" || m === "light" || m === "auto") root.themeModeSetting = m
                root.pendingStateReads--
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", "cat \"$1\" 2>/dev/null || cat \"$2\"", "_",
            root.statePalette, Quickshell.shellPath("../assets/defaults/palette")]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim()
                if (sessionTheme.paletteNames.includes(p)) root.palette = p
                root.pendingStateReads--
            }
        }
    }

    // Copies the chosen wallpaper into the state (so it survives even if the
    // original is deleted or moved) and saves the original's path (see
    // stateWallpaperSource). The greeter reads the published copy, not this
    // one.
    Process {
        id: wallpaperCopy
        property string src: ""
        // Chosen while another one was being copied: it goes next (see
        // chooseWallpaper).
        property string queued: ""
        // Video: it was already set playing when chosen (see chooseWallpaper).
        property bool startedVideo: false
        // For a video, its last frame is kept: the desktop's image when it ends,
        // and the one for the palette, the lockscreen and the greeter. If it's
        // already cached ($5, see WallpaperService.stillFor) it's copied;
        // otherwise it's extracted with ffmpeg (-update 1 keeps the last frame)
        // and stored there.
        command: ["sh", "-c", `
            if [ "$4" = video ] && [ -s "$5" ] && [ "$5" -nt "$1" ]; then
                install -m 644 "$5" "$2"
            elif [ "$4" = video ]; then
                ffmpeg -v error -y -sseof -0.3 -i "$1" -update 1 -q:v 2 "$2.tmp.jpg" </dev/null &&
                    { mkdir -p "$(dirname "$5")"; cp "$2.tmp.jpg" "$5" || true; } &&
                    mv "$2.tmp.jpg" "$2"
            else
                install -m 644 "$1" "$2"
            fi && printf '%s' "$1" > "$3"`, "_",
            src, root.stateWallpaper, root.stateWallpaperSource, wallpaperService.isVideo(src) ? "video" : "image",
            wallpaperService.stillFor(src)]
        onExited: (exitCode) => {
            if (exitCode !== 0) {
                console.warn("Could not save wallpaper to " + root.stateWallpaper)
            } else {
                root.wallpaperSource = src
                root.wallpaperPath = root.stateWallpaper
                root.wallpaperVersion = root.wallpaperVersion + 1
                root.regenPalette()
                root.regenHero()
                if (root.wallpaperVideo && !startedVideo) root.videoPlayCount++
            }
            if (queued) {
                const next = queued
                queued = ""
                root.chooseWallpaper(next)
            }
        }
    }

    // Chosen mode and palette. FileView and not a process: two changes in a
    // row are both written (with the process still running, the second was
    // lost). No preload: they only write (they're read at startup, above).
    FileView {
        id: themeModeFile
        path: root.stateThemeMode
        preload: false
        onSaveFailed: console.warn("Could not save mode to " + root.stateThemeMode)
    }

    FileView {
        id: paletteFile
        path: root.statePalette
        preload: false
        onSaveFailed: console.warn("Could not save palette to " + root.statePalette)
    }

    // "wallpaper" palette: matugen extracts a Material 3 palette from the
    // wallpaper with the dark and light variants together. It's regenerated
    // only if the wallpaper is newer than colors.json (install gives the copy a
    // new mtime), so running it at startup is free. --source-color-index
    // because otherwise, with several candidate colors, matugen asks on the
    // terminal and fails ("not a terminal"). It's written to .tmp + mv so
    // nobody reads a half-written JSON.
    //
    // wallpaper.jpg has that name whatever the original's format, and matugen
    // decides how to decode by the extension ("Illegal start bytes:8950" with
    // a PNG): the real format is detected from the magic bytes and it's given
    // a symlink with the right extension.
    // Requested while running (another wallpaper): it runs again when done.
    function regenPalette(): void {
        if (paletteGen.running) paletteGen.again = true
        else paletteGen.running = true
    }

    Process {
        id: paletteGen
        property bool again: false
        // That second run ignores the timestamps: the new wallpaper was copied
        // while matugen was already reading the previous one, and colors.json,
        // written afterward, ended up newer than it (the run was skipped and the
        // previous wallpaper's palette stayed).
        property bool force: false
        command: ["sh", "-c", `
            [ -z "$3" ] && [ "$2" -nt "$1" ] && exit 0
            case "$(od -An -tx1 -N4 "$1" | tr -d ' \\n')" in
                89504e47) ext=png ;;
                52494646) ext=webp ;;
                *) ext=jpg ;;
            esac
            ln -sf "$1" "$2.src.$ext"
            matugen image "$2.src.$ext" --source-color-index 0 --dry-run -q -j hex > "$2.tmp" && mv "$2.tmp" "$2"
            r=$?
            rm -f "$2.src.$ext" "$2.tmp"
            exit $r`,
            "_", root.wallpaperPath, root.stateColors, force ? "force" : ""]
        onExited: (exitCode) => {
            // There's another wallpaper already: this palette is stale and isn't
            // loaded (it would show for an instant, in GTK and kitty too).
            if (again) {
                again = false
                force = true
                running = true
                return
            }
            force = false
            if (exitCode !== 0)
                console.warn("Could not generate the wallpaper palette (see matugen)")
            colorsFile.reload()
        }
    }

    FileView {
        id: colorsFile
        path: root.stateColors
        onLoaded: {
            try {
                sessionTheme.matugen = JSON.parse(text()).colors
                // New colors.json (another wallpaper): it goes to the greeter too.
                publishTimer.restart()
            } catch (e) {
                console.warn("Invalid colors.json:", e)
            }
        }
    }

    // Header of the Control Center's Home (CcHome.qml): the middle band of the
    // wallpaper, already cropped at twice its size (578x104, so it looks sharp
    // on HiDPI screens). The whole wallpaper (a 4K PNG) took about 150 ms to
    // load every time the panel opened, and the gap showed; the crop loads in
    // 2 ms. It's remade like the palette: only if the wallpaper is newer, and
    // forced if requested while running.
    //
    // wallpaperHero is its URL, "" until it exists.
    property string wallpaperHero: ""

    function regenHero(): void {
        if (heroGen.running) heroGen.again = true
        else heroGen.running = true
    }

    Process {
        id: heroGen
        property bool again: false
        property bool force: false
        property int version: 0
        command: ["sh", "-c", `
            [ -z "$3" ] && [ "$2" -nt "$1" ] && exit 0
            mkdir -p "$(dirname "$2")" &&
                ffmpeg -v error -y -i "$1" -frames:v 1 -q:v 2 \\
                    -vf "scale=1156:208:force_original_aspect_ratio=increase:flags=lanczos,crop=1156:208" \\
                    "$2.tmp.jpg" </dev/null &&
                mv "$2.tmp.jpg" "$2"
            r=$?
            rm -f "$2.tmp.jpg"
            exit $r`,
            "_", root.wallpaperPath, root.cacheHero, force ? "force" : ""]
        onExited: (exitCode) => {
            if (again) {
                again = false
                force = true
                running = true
                return
            }
            force = false
            if (exitCode !== 0) {
                console.warn("Could not make the Control Center header image (see ffmpeg)")
                return
            }
            // A new URL every time: with the same one, Qt could return the previous
            // crop from its image cache.
            version++
            root.wallpaperHero = Qt.resolvedUrl(root.cacheHero) + "?" + version
        }
    }

    // Carries the palette and mode to GTK, kitty, Kate and dconf (see
    // SystemTheme.qml). Also applied at startup: home-manager overwrites
    // gtk-theme on every rebuild, so the system ends up matching the shell
    // again.
    SystemTheme {
        theme: sessionTheme
        ready: root.pendingStateReads === 0
        enabled: !sessionCompositor.nested
    }

    // qs ipc call wallpaper reload
    IpcHandler {
        target: "wallpaper"
        // Looks for the state file again: it might not have existed before (the
        // first change made from bin/pick-wallpaper.sh).
        function reload(): void {
            wallpaperLookup.running = true
        }
    }

    // --- Settings and the wallpaper strip ------------------------------
    // Only one thing open at a time: "closed", "window" (SettingsWindow) or
    // "strip" (WallpaperStrip). Both are loaded with a LazyLoader only while
    // open, which is why the IpcHandlers live here.
    property string ui: "closed"
    // The strip was opened with "Preview on desktop": closing it goes back to
    // Settings.
    property bool stripFromWindow: false
    // The section Settings opens on (see the "settings" IpcHandler).
    property string settingsSection: "appearance"

    function toggleSettings(): void {
        root.stripFromWindow = false
        root.ui = root.ui === "window" ? "closed" : "window"
    }

    function closeStrip(): void {
        root.ui = root.stripFromWindow ? "window" : "closed"
        root.stripFromWindow = false
        // Goes back to the workspace the preview came from (see
        // previewWorkspace).
        if (root.previewReturn) {
            sessionCompositor.focusWorkspace(root.previewReturn)
            root.previewReturn = null
        }
    }

    // The strip (from "Preview on desktop" or with Mod+Alt+A): jumps to an
    // empty workspace to see the wallpaper (Compositor.emptyWorkspace) and,
    // when the strip closes, goes back to the previous one (by index). If it
    // was already on an empty one, it doesn't move.
    property var previewReturn: null

    // In shell.qml and not in SettingsWindow's handler: when ui switches to
    // "strip" the LazyLoader destroys the window and the rest of the handler
    // no longer runs.
    function openPreview(): void {
        openStrip(true)
    }

    // fromSettings: closing the strip goes back to Settings (otherwise
    // everything closes).
    function openStrip(fromSettings: bool): void {
        const move = sessionCompositor.emptyWorkspace()
        if (move) {
            root.previewReturn = move.from
            console.info("Preview: workspace " + move.from.index + " -> " + move.to.index)
            sessionCompositor.focusWorkspace(move.to)
        }
        root.stripFromWindow = fromSettings
        root.ui = "strip"
    }

    function chooseWallpaper(path: string): void {
        // Another one is being copied: this one goes next. Otherwise the running
        // process finished with `src` already changed, and one was marked while
        // another was set.
        if (wallpaperCopy.running) {
            wallpaperCopy.queued = path
            return
        }
        // Already set: don't copy it again or regenerate the palette (if it's a
        // video, it plays again).
        if (path === root.wallpaperSource) {
            if (root.wallpaperVideo) root.videoPlayCount++
            return
        }
        wallpaperCopy.src = path
        // A video starts right away, with the fade to black (Wallpaper.qml):
        // extracting its last frame with ffmpeg takes 1-3 s, and waiting felt
        // like the click hadn't done anything. The frame goes underneath once
        // it's ready.
        wallpaperCopy.startedVideo = wallpaperService.isVideo(path) && shellSettings.videoWallpapers
        if (wallpaperCopy.startedVideo) {
            root.wallpaperSource = path
            root.videoPlayCount++
        } else {
            // An image (or a video with videos turned off): if one is playing, it's
            // stopped so the transition shows right away.
            videoPlayer.stop()
        }
        wallpaperCopy.running = true
    }

    function chooseThemeMode(mode: string): void {
        root.themeModeSetting = mode
        themeModeFile.setText(mode)
    }

    function choosePalette(name: string): void {
        root.palette = name
        paletteFile.setText(name)
    }

    // "auto" mode: day or night at the weather's location (the one chosen in
    // Settings, or the time zone's city).
    Sun {
        id: sun
        latitude: lockScreen.weather.place ? lockScreen.weather.place.latitude : NaN
        longitude: lockScreen.weather.place ? lockScreen.weather.place.longitude : NaN
    }

    // "Light until 19:12", below Auto.
    readonly property string autoModeHint: (sun.isDay ? "Light" : "Dark") + " until "
        + Qt.formatTime(sun.nextChange, "hh:mm") + (sun.hasLocation ? "" : " (no location yet)")

    // Clipboard history: the service always runs (it saves what's copied);
    // the panel only while it's open.
    ClipboardService {
        id: clipboardService
        stateDir: root.stateDir
        maxItems: shellSettings.clipboardMaxItems
    }

    // --- Power menu (PowerMenu.qml) ---
    property bool powerMenuOpen: false

    function runPowerAction(action: string): void {
        powerMenuOpen = false
        switch (action) {
        case "lock": lockScreen.lock(); break
        case "logout": sessionCompositor.quit(); break
        // Lock first: never wake up without a lock (one second for it to draw).
        case "suspend": lockScreen.lock(); suspendAfterLock.restart(); break
        case "reboot": Quickshell.execDetached(["systemctl", "reboot"]); break
        case "poweroff": Quickshell.execDetached(["systemctl", "poweroff"]); break
        }
    }

    Timer {
        id: suspendAfterLock
        interval: 1000
        onTriggered: Quickshell.execDetached(["systemctl", "suspend"])
    }

    // qs ipc call power toggle
    IpcHandler {
        target: "power"
        function toggle(): void {
            root.powerMenuOpen = !root.powerMenuOpen
        }
    }

    LazyLoader {
        active: root.powerMenuOpen

        PowerMenu {
            theme: sessionTheme
            monitor: systemMonitor
            topOffset: 36 + (shellSettings.barStyle === "floating" ? 6 : 0)
            onCloseRequested: root.powerMenuOpen = false
            onActionChosen: (action) => root.runPowerAction(action)
        }
    }

    // About: system data, fastfetch style (the bar's NixOS logo).
    property bool aboutOpen: false
    // When it opens, the data is refreshed in the background (the panel
    // already shows what it had).
    onAboutOpenChanged: if (aboutOpen) systemInfo.refresh()

    // The compositor (niri): the only thing that talks to it. Workspaces,
    // windows, focus, turning off monitors and quitting (see Compositor.qml).
    Compositor {
        id: sessionCompositor
    }

    SystemInfo {
        id: systemInfo
        compositor: sessionCompositor
    }

    // Name, user@host and photo (the Control Center's Home), read at startup.
    UserInfo {
        id: userInfo
    }

    // qs ipc call about toggle
    IpcHandler {
        target: "about"
        function toggle(): void {
            root.aboutOpen = !root.aboutOpen
        }
    }

    LazyLoader {
        active: root.aboutOpen

        AboutPanel {
            theme: sessionTheme
            monitor: systemMonitor
            system: systemInfo
            onCloseRequested: root.aboutOpen = false
        }
    }

    // CPU, memory, GPU and network: a single measurement for the bar and the
    // panel.
    SystemMonitor {
        id: systemMonitor
    }

    // Video wallpapers: they play in a separate process that exits when done
    // (see VideoPlayer.qml). Every time videoPlayCount goes up (when chosen, at
    // startup and on unlock) it plays once.
    VideoPlayer {
        id: videoPlayer
    }
    onVideoPlayCountChanged: if (wallpaperVideo && shellSettings.videoWallpapers) videoPlayer.play(wallpaperVideo)
    // Turning videos off in Settings stops the one playing.
    Connections {
        target: shellSettings
        function onVideoWallpapersChanged() {
            if (!shellSettings.videoWallpapers) videoPlayer.stop()
        }
    }

    // External drives: the bar widget and the Drives page.
    DrivesService {
        id: drivesService
    }

    // The screens' brightness (Control Center → Home).
    BrightnessService {
        id: brightnessService
    }

    // qs ipc call brightness refresh | list | set <name> <percent>
    IpcHandler {
        target: "brightness"
        // Reads it again (the Control Center does when it opens).
        function refresh(): void {
            brightnessService.refresh()
        }
        // JSON: [{ "name": "HP 524pf", "percent": 64 }, …], left to right.
        function list(): string {
            return JSON.stringify(brightnessService.displays.map(d => ({ name: d.label, percent: Math.round(d.value * 100) })))
        }
        // A screen's brightness, by the name list() gives.
        function set(name: string, percent: int): void {
            const d = brightnessService.displays.find(d => d.label === name)
            if (d) brightnessService.set(d.id, percent / 100)
        }
    }

    // Bluetooth pairing with an agent (the Control Center's Bluetooth page).
    BluetoothAgent {
        id: bluetoothPairing
    }

    // Notifications: server, history and popups (see NotificationService.qml).
    NotificationService {
        compositor: sessionCompositor
        id: notificationService
        stateDir: root.stateDir
    }

    NotificationPopups {
        theme: sessionTheme
        service: notificationService
        topOffset: 36 + (shellSettings.barStyle === "floating" ? 6 : 0)
    }

    // --- Control Center (ControlCenter.qml) ---
    // A bar capsule opens its tab; the same one again closes it.
    property bool controlCenterOpen: false
    property string controlCenterTab: "home"
    // Which side it comes out on ("left", "center" or "right"): the zone of the
    // widget that opened it. From IPC, the last one is kept.
    property string controlCenterSide: "right"
    // Caffeine: no locking, turning off or suspending on idle (Idle.qml). In
    // PersistentProperties so it survives hot reload (when editing the shell's
    // code): before, every reload turned it off silently and the machine ended
    // up suspending. Restarting the shell turns it off again.
    PersistentProperties {
        id: persisted
        reloadableId: "shellState"
        property bool caffeine: false
    }
    property alias caffeine: persisted.caffeine

    // qs ipc call caffeine toggle | enable | disable | isEnabled
    IpcHandler {
        target: "caffeine"
        function toggle(): void {
            root.caffeine = !root.caffeine
        }
        function enable(): void {
            root.caffeine = true
        }
        function disable(): void {
            root.caffeine = false
        }
        function isEnabled(): bool {
            return root.caffeine
        }
    }

    function openControlCenter(tab: string, side: string): void {
        if (side) {
            // Requested from another zone: it moves there instead of closing.
            const moved = side !== controlCenterSide
            controlCenterSide = side
            if (moved && controlCenterOpen) {
                controlCenterTab = tab
                return
            }
        }
        if (controlCenterOpen && controlCenterTab === tab) {
            controlCenterOpen = false
            return
        }
        controlCenterTab = tab
        controlCenterOpen = true
    }

    // qs ipc call controlcenter toggle | open <home|audio|network|bluetooth>
    IpcHandler {
        target: "controlcenter"
        function toggle(): void {
            if (root.controlCenterOpen) root.controlCenterOpen = false
            else root.openControlCenter("home", "")
        }
        function open(tab: string): void {
            root.controlCenterTab = tab
            root.controlCenterOpen = true
        }
    }

    LazyLoader {
        active: root.controlCenterOpen

        ControlCenter {
            theme: sessionTheme
            compositor: sessionCompositor
            side: root.controlCenterSide
            tab: root.controlCenterTab
            // The bar's height (Bar.qml: 36, +6 of margin if it floats).
            topOffset: 36 + (shellSettings.barStyle === "floating" ? 6 : 0)
            heroSource: root.wallpaperHero
            weather: lockScreen.weather
            notifications: notificationService
            monitor: systemMonitor
            drives: drivesService
            brightness: brightnessService
            bluetoothAgent: bluetoothPairing
            user: userInfo
            caffeine: root.caffeine

            onCloseRequested: root.controlCenterOpen = false
            onTabRequested: (tab) => root.controlCenterTab = tab
            onCaffeineToggled: root.caffeine = !root.caffeine
            onSettingsRequested: {
                root.controlCenterOpen = false
                root.toggleSettings()
            }
            onAvatarPickerRequested: root.openPicker({ purpose: "avatar", mode: "file",
                title: "Choose a profile picture", folder: Quickshell.env("HOME") + "/Pictures",
                filters: ["*.png", "*.jpg", "*.jpeg", "*.webp"] })
            onWallpaperPickerRequested: {
                root.controlCenterOpen = false
                root.settingsSection = "appearance"
                root.stripFromWindow = false
                root.ui = "window"
            }
        }
    }

    property bool clipboardOpen: false

    // qs ipc call clipboard toggle
    IpcHandler {
        target: "clipboard"
        function toggle(): void {
            root.clipboardOpen = !root.clipboardOpen
        }
    }

    LazyLoader {
        active: root.clipboardOpen

        ClipboardPanel {
            compositor: sessionCompositor
            theme: sessionTheme
            clipboard: clipboardService
            onCloseRequested: root.clipboardOpen = false
        }
    }

    // Wallpapers in the folder and their thumbnails, shared by both.
    WallpaperService {
        id: wallpaperService
        folder: shellSettings.wallpaperDir
        videosEnabled: shellSettings.videoWallpapers
    }

    // qs ipc call settings toggle
    IpcHandler {
        target: "settings"
        // spore-ipc settings open bar (idle, bar, appearance, lock)
        function open(section: string): void {
            root.stripFromWindow = false
            root.settingsSection = section
            root.ui = "window"
        }

        function toggle(): void {
            root.toggleSettings()
        }
    }

    // qs ipc call appearance toggle
    IpcHandler {
        target: "appearance"
        function toggle(): void {
            if (root.ui === "strip") {
                root.closeStrip()
                return
            }
            root.openStrip(false)
        }
    }

    LazyLoader {
        active: root.ui === "window"

        SettingsWindow {
            theme: sessionTheme
            compositor: sessionCompositor
            settings: shellSettings
            wallpapers: wallpaperService
            activeSection: root.settingsSection
            weather: lockScreen.weather
            currentWallpaperSource: root.wallpaperSource
            modeSetting: root.themeModeSetting
            autoModeHint: root.autoModeHint
            caffeine: root.caffeine

            onCloseRequested: root.ui = "closed"
            onPreviewRequested: root.openPreview()
            onWallpaperChosen: (path) => root.chooseWallpaper(path)
            onThemeModeChosen: (mode) => root.chooseThemeMode(mode)
            onPaletteChosen: (name) => root.choosePalette(name)
            onFolderPickerRequested: root.openPicker({ purpose: "wallpaperDir", mode: "folder",
                title: "Choose the wallpaper folder", folder: shellSettings.wallpaperDir })
        }
    }

    // --- File picker (FilePicker.qml) ---
    // One request at a time: { purpose, mode, title, folder, filters }.
    // `purpose` says what to do with the chosen path (see pickerAccepted).
    property var picker: null

    function openPicker(request: var): void {
        root.picker = request
    }

    function pickerAccepted(path: string): void {
        const purpose = root.picker ? root.picker.purpose : ""
        root.picker = null
        if (purpose === "avatar") {
            userInfo.setAvatar(path)
        } else if (purpose === "wallpaperDir") {
            const home = Quickshell.env("HOME")
            const raw = path === home ? "~" : path.startsWith(home + "/") ? "~" + path.slice(home.length) : path
            shellSettings.save({ picker: { wallpaperDir: raw } })
        }
    }

    LazyLoader {
        active: root.picker !== null

        FilePicker {
            theme: sessionTheme
            mode: root.picker ? root.picker.mode : "file"
            title: root.picker ? root.picker.title : ""
            startFolder: root.picker ? root.picker.folder : Quickshell.env("HOME")
            nameFilters: root.picker ? (root.picker.filters ?? []) : []
            extraPlaces: [{ label: "Wallpapers", path: shellSettings.wallpaperDir, icon: "image" }]
            onAccepted: (path) => root.pickerAccepted(path)
            onCanceled: root.picker = null
        }
    }

    LazyLoader {
        active: root.ui === "strip"

        WallpaperStrip {
            theme: sessionTheme
            wallpapers: wallpaperService
            currentWallpaperSource: root.wallpaperSource
            modeSetting: root.themeModeSetting
            autoModeHint: root.autoModeHint

            onCloseRequested: root.closeStrip()
            onWallpaperChosen: (path) => root.chooseWallpaper(path)
            onThemeModeChosen: (mode) => root.chooseThemeMode(mode)
            onPaletteChosen: (name) => root.choosePalette(name)
        }
    }

    // Background, one per monitor.
    Variants {
        model: Quickshell.screens

        Wallpaper {
            required property var modelData
            screen: modelData
            path: root.wallpaperPath
            version: root.wallpaperVersion
            theme: sessionTheme
            videoPath: root.wallpaperVideo
            transition: shellSettings.wallpaperTransition
            videoPlayCount: root.videoPlayCount
            videosEnabled: shellSettings.videoWallpapers
            player: videoPlayer
        }
    }

    // A bar per monitor.
    Variants {
        model: Quickshell.screens

        Bar {
            required property var modelData
            screen: modelData
            theme: sessionTheme
            settings: shellSettings
            monitor: systemMonitor
            compositor: sessionCompositor
            caffeine: root.caffeine
            notifications: notificationService
            drives: drivesService
            onCaffeineToggled: root.caffeine = !root.caffeine
            onAboutRequested: root.aboutOpen = !root.aboutOpen
            onClipboardRequested: root.clipboardOpen = !root.clipboardOpen
            onControlCenterRequested: (tab, side) => root.openControlCenter(tab, side)
            onPowerRequested: root.powerMenuOpen = !root.powerMenuOpen
        }
    }

    // Lockscreen (WlSessionLock, see Lock.qml). A single Lock for the whole
    // session -- WlSessionLock already creates a WlSessionLockSurface per
    // monitor internally, no Variants needed here.
    Lock {
        id: lockScreen
        wallpaperPath: root.wallpaperPath
        wallpaperVersion: root.wallpaperVersion
        theme: sessionTheme
        settings: shellSettings
    }

    // On unlock, the video wallpaper plays again (like on macOS).
    Connections {
        target: lockScreen
        function onLockedChanged(): void {
            if (!lockScreen.locked && root.wallpaperVideo) root.videoPlayCount++
        }
    }

    // Locking, turning off the monitors and suspending on idle; the times are
    // in settings.json (see Idle.qml).
    Idle {
        lock: lockScreen
        settings: shellSettings
        compositor: sessionCompositor
        inhibited: root.caffeine
    }
}
