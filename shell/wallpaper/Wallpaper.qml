import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"

// Background layer (WlrLayer.Background, below everything). One instance per
// monitor, like Bar. shell.qml passes path/version (see there) -- this isn't
// a Singleton because Component.onCompleted of a Quickshell Singleton never
// actually fired in practice (confirmed with console.log), leaving the path
// always empty.
PanelWindow {
    id: root

    property string path: ""
    property int version: 0
    required property Theme theme
    // Video wallpaper (path of the original) or "". `path` is its last frame.
    property string videoPath: ""
    // Every time it goes up, the video plays once (see shell.qml).
    property int videoPlayCount: 0
    // Settings (wallpaper.videos): when off, a video stays as a still image (its
    // last frame) and doesn't play.
    property bool videosEnabled: true
    // The player (a separate process, see VideoPlayer.qml): shell.qml starts it;
    // here we listen for when the video is on screen.
    property VideoPlayer player: null

    WlrLayershell.layer: WlrLayer.Background
    WlrLayershell.namespace: "quickshell-wallpaper"

    // Ignore = exclusiveZone -1: covers the whole screen, ignoring the zone the
    // bar reserves. Otherwise the wallpaper sits 32px lower than on the
    // lockscreen (which is always full screen) and it visibly jumps when locking.
    exclusionMode: ExclusionMode.Ignore

    anchors { top: true; bottom: true; left: true; right: true }
    color: theme.crust

    // Transition when the wallpaper changes (settings.json: wallpaper.transition):
    // "none", "fade", "wipe", "disc", "nix", "nix-rnd", "spore" or "random".
    property string transition: "fade"

    // Each effect with the duration that suits it best, in ms (not configurable):
    // the simple ones, about a second; the hexagon and spore ones, longer so
    // their phases can be seen (at 0.9 s they went by unnoticed).
    readonly property var durations: ({ fade: 900, wipe: 1000, disc: 1000, nix: 1500, "nix-rnd": 1500, spore: 1600 })

    // The "?version" forces Qt to re-read the file when version changes --
    // without it, Image doesn't notice the content changed because the URL would
    // be the same.
    readonly property string wantedSource: path && sized ? (Qt.resolvedUrl(path) + "?" + version) : ""

    // Images are decoded at the screen's size, not the file's: an 8000 px photo
    // took about 150 MB of memory even when shown in 4K. Qt multiplies by the
    // monitor's scale, so it looks just as sharp. With no size yet (a window
    // just created), nothing is loaded. LockSurface.qml uses the same size and
    // URL: they share the image.
    readonly property bool sized: width > 0 && height > 0
    readonly property size imageSize: Qt.size(width, height)

    // `current` is the one on screen. On a change, the new one loads in `next`
    // and, once ready, a shader goes from one to the other (shaders/*.frag). At
    // the end, `current` takes the new one and `next` is emptied.
    property bool transitioning: false
    property string effect: "fade"
    // Another one was chosen mid-transition: it goes when the transition ends
    // (see finishTransition).
    property bool queued: false

    onWantedSourceChanged: {
        // Mid-transition, wait. Putting it straight into `current` didn't work: when
        // it finished, the animation overwrote it with the incoming one, so the
        // previous wallpaper stayed on screen while Settings marked the chosen one.
        if (transitioning) {
            queued = true
            return
        }
        showWanted()
    }
    Component.onCompleted: current.source = wantedSource

    function showWanted(): void {
        // First image or no transition: straight in.
        if (!current.source.toString() || transition === "none") {
            current.source = wantedSource
            return
        }
        // Video: no transition (the video brings its own). Its last frame stays as
        // the background: if the video was already shown, it goes straight in (the
        // video covers it); otherwise it waits until it's shown (see videoReady).
        if (videoPath !== "" && videosEnabled) {
            if (videoShown) {
                current.source = wantedSource
            } else {
                pendingSource = wantedSource
                videoWait.restart()
            }
            return
        }
        next.source = wantedSource
    }

    // Video: when asked to play, fade to black until it has its first frame on
    // screen (videoStarting). The image underneath (its last frame) only changes
    // once the video covers it (pendingSource). If the video fails or doesn't
    // start within 3 s, it carries on anyway.
    property bool videoStarting: false
    // The current video has already been on screen (since the last play).
    property bool videoShown: false
    property string pendingSource: ""

    function playVideo(): void {
        if (videoPath === "" || !videosEnabled) return
        videoStarting = true
        videoShown = false
        videoWait.restart()
    }

    function videoReady(): void {
        videoStarting = false
        videoWait.stop()
        if (!pendingSource) return
        current.source = pendingSource
        pendingSource = ""
    }

    Timer {
        id: videoWait
        interval: 3000
        onTriggered: root.videoReady()
    }

    Connections {
        target: root.player
        function onShowingChanged(): void {
            if (!root.player.showing) return
            root.videoShown = true
            root.videoReady()
        }
        function onFailed(): void {
            root.videoReady()
        }
    }

    // The animation finished and `current` already shows the new one: the shader
    // goes away. If another one was chosen meanwhile, that one goes now.
    function finishTransition(): void {
        if (!transitioning || progressAnim.running) return
        if (current.status !== Image.Ready || current.source.toString() !== next.source.toString()) return
        transitioning = false
        next.source = ""
        if (queued) {
            queued = false
            showWanted()
        }
    }

    function startTransition(): void {
        const effects = ["fade", "wipe", "disc", "nix", "nix-rnd", "spore"]
        effect = transition === "random" ? effects[Math.floor(Math.random() * effects.length)] : transition
        transitioning = true
        progressAnim.restart()
    }

    Image {
        id: current
        anchors.fill: parent
        sourceSize: root.imageSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: root.finishTransition()
    }

    // Visible only during the transition, and even then the shader covers it
    // (hideSource): it's only drawn into the texture.
    Image {
        id: next
        anchors.fill: parent
        visible: root.transitioning
        sourceSize: root.imageSize
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        onStatusChanged: {
            if (status === Image.Ready && source.toString() && !root.transitioning) root.startTransition()
            // Doesn't load: the transition is skipped.
            if (status === Image.Error) current.source = source
        }
    }

    // The Images go through ShaderEffectSource instead of directly: that way the
    // shader gets how they look (cropped to the screen), not the whole image.
    ShaderEffectSource {
        id: fromTexture
        sourceItem: root.transitioning ? current : null
        live: true
    }

    ShaderEffectSource {
        id: toTexture
        sourceItem: root.transitioning ? next : null
        hideSource: true
        live: true
    }

    ShaderEffect {
        anchors.fill: parent
        visible: root.transitioning
        property variant source1: fromTexture
        property variant source2: toTexture
        property real progress: 0
        property real aspect: width / Math.max(1, height)
        property real smoothness: root.effect === "disc" ? 0.12 : root.effect === "nix" ? 0.012 : root.effect === "nix-rnd" ? 0.04 : root.effect === "spore" ? 0.004 : 0.08
        // Outlines for "nix" and the growth front for "spore" (the other shaders
        // don't use it).
        property color lineColor: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.9)
        fragmentShader: Qt.resolvedUrl("shaders/" + root.effect + ".frag.qsb")

        NumberAnimation on progress {
            id: progressAnim
            running: false
            from: 0
            to: 1
            duration: root.durations[root.effect] ?? 1000
            // Hexagons and spores, linear: each cell already eases on its own, and with
            // a curve their random starts all fell in the fast middle stretch (they
            // looked synchronized).
            easing.type: root.effect.startsWith("nix") || root.effect === "spore" ? Easing.Linear : Easing.InOutCubic
            // `current` switches to the new one; the shader stays visible until it loads.
            onFinished: {
                current.source = next.source
                // If it was already cached, current doesn't change state.
                Qt.callLater(root.finishTransition)
            }
        }
    }

    // Fade to black while a new video loads: the click gets an immediate
    // response, and the video (on the layer above, see VideoPlayer.qml) appears
    // over the black with its first frame. When the video ends (the black
    // already gone underneath), its last frame stays.
    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: root.videoStarting || root.pendingSource !== "" ? 1 : 0
        visible: opacity > 0
        Behavior on opacity {
            NumberAnimation { duration: 400; easing.type: Easing.InOutQuad }
        }
    }

    onVideoPlayCountChanged: playVideo()
}
