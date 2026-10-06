import QtQuick
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// Top bar. Three shapes (settings.json: bar.style), all with the elements
// grouped in capsules (Capsule.qml):
//  - "full": edge to edge, attached to the top.
//  - "floating": detached from the edges, with rounded corners.
//  - "pill": a single pill (fully rounded ends).
// And the background, from transparent (only the capsules) to solid:
// bar.opacity.
PanelWindow {
    id: bar

    required property Theme theme
    required property Settings settings
    // Shared measurements (SystemMonitor.qml), for the System widget.
    required property SystemMonitor monitor
    // The compositor (Compositor.qml): workspaces and the focused window.
    property Compositor compositor: null
    // History and Do Not Disturb, for the notifications widget.
    property NotificationService notifications: null
    // External drives, for the drives widget.
    property DrivesService drives: null
    // Idle inhibitor (shell.qml's "caffeine").
    property bool caffeine: false
    signal caffeineToggled()
    // Click on the NixOS logo: shell.qml opens/closes About (AboutPanel.qml).
    signal aboutRequested()
    signal clipboardRequested()
    // The Control Center tab to open ("audio", "bluetooth", "network") and the
    // zone of the widget that asked for it ("left", "center" or "right"): the
    // panel comes out on that side.
    signal controlCenterRequested(string tab, string side)

    // The bar zone a widget is in (bar.layout); "right" if it isn't there.
    function zoneOf(id: string): string {
        for (const z of ["left", "center", "right"])
            if ((layout[z] ?? []).some(g => g.includes(id))) return z
        return "right"
    }
    // Power menu (the button to the right of the clock).
    signal powerRequested()

    readonly property string style: settings.barStyle
    readonly property bool floating: style === "floating"

    // Distance from the capsules at the ends to the background's edge: in
    // "pill" they're concentric with the rounded ends.
    readonly property int contentInset: style === "pill" ? 4 : 5

    // The Wayland layer-shell layer: "Top" sits above normal windows
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-bar"

    anchors {
        top: true
        left: true
        right: true
    }

    // "full" goes edge to edge; "floating" moves a little away from every edge;
    // "pill" stays attached to the top, narrower than the screen.
    margins {
        top: bar.floating ? 6 : 0
        left: bar.style === "full" ? 0 : bar.floating ? 8 : 16
        right: bar.style === "full" ? 0 : bar.floating ? 8 : 16
    }

    // Design 3a enlarged: 36 tall, 28 capsules (the design: 32 and 24).
    implicitHeight: 36
    // The background is painted by `background`, so it can be shaped.
    color: "transparent"

    // settings.json: bar.opacity, only the background (capsules and text stay
    // opaque). At 0 it isn't drawn: only the capsules over the wallpaper.
    readonly property color backgroundColor: theme.alpha(theme.barBg, settings.barOpacity)

    Rectangle {
        id: background
        anchors.fill: parent
        visible: bar.settings.barOpacity > 0
        radius: bar.style === "pill" ? height / 2 : bar.floating ? 12 : 0
        color: bar.backgroundColor
    }

    // --- Widgets -------------------------------------------------------------
    // Built from settings.json (bar.layout, see Settings.qml): three zones with
    // groups in each; each group is a capsule. Anchors and not a RowLayout
    // with spacers: that way the center sits at the exact center of the
    // screen, whatever the sides measure.

    readonly property var layout: settings.barLayout

    // Each widget by id (BarButton.qml and friends).

    Component {
        id: launcherWidget
        Launcher {
            theme: bar.theme
            command: bar.settings.launcher
        }
    }

    Component {
        id: aboutWidget
        BarButton {
            theme: bar.theme
            icon: "nixos"
            tooltip: "About this system"
            onClicked: bar.aboutRequested()
        }
    }

    // The Control Center's Home.
    Component {
        id: controlCenterWidget
        BarButton {
            theme: bar.theme
            icon: "layout-dashboard"
            tooltip: "Control Center"
            onClicked: bar.controlCenterRequested("home", bar.zoneOf("controlCenter"))
        }
    }

    Component {
        id: activeWindowWidget
        ActiveWindow {
            theme: bar.theme
            compositor: bar.compositor
            showIcon: bar.settings.widgetOption("activeWindow", "showIcon")
            // With no focused window, its capsule hides (see Group).
            property bool shown: hasWindow
            visible: shown
        }
    }

    Component {
        id: drivesWidget
        DrivesButton {
            theme: bar.theme
            service: bar.drives
            onClicked: bar.controlCenterRequested("drives", bar.zoneOf("drives"))
        }
    }

    Component {
        id: notificationsWidget
        NotificationsButton {
            theme: bar.theme
            service: bar.notifications
            onClicked: bar.controlCenterRequested("notifications", bar.zoneOf("notifications"))
        }
    }

    Component {
        id: systemWidget
        SystemButton {
            theme: bar.theme
            monitor: bar.monitor
            onClicked: bar.controlCenterRequested("system", bar.zoneOf("system"))
        }
    }

    // CPU, memory and GPU: the icon and usage and temperature bars.
    Component {
        id: cpuWidget
        ResourceMeter {
            theme: bar.theme
            icon: "cpu"
            name: "CPU"
            usage: bar.monitor.cpu
            temp: bar.monitor.cpuTemp
            onClicked: bar.controlCenterRequested("system", bar.zoneOf("cpu"))
        }
    }

    Component {
        id: memoryWidget
        ResourceMeter {
            theme: bar.theme
            icon: "memory-stick"
            name: "Memory"
            usage: bar.monitor.mem
            detail: bar.monitor.memTotal > 0 ? (bar.monitor.memUsed / 1073741824).toFixed(1) + " / " + (bar.monitor.memTotal / 1073741824).toFixed(1) + " GiB" : ""
            onClicked: bar.controlCenterRequested("system", bar.zoneOf("memory"))
        }
    }

    Component {
        id: gpuWidget
        ResourceMeter {
            theme: bar.theme
            icon: "gpu"
            name: "GPU"
            usage: bar.monitor.gpu
            temp: bar.monitor.gpuTemp
            onClicked: bar.controlCenterRequested("system", bar.zoneOf("gpu"))
        }
    }

    // A red dot while the screen is being recorded or shared.
    Component {
        id: screencastWidget
        ScreencastIndicator {
            theme: bar.theme
            compositor: bar.compositor
        }
    }

    Component {
        id: appsWidget
        OpenApps {
            theme: bar.theme
        }
    }

    Component {
        id: workspacesWidget
        Workspaces {
            theme: bar.theme
            compositor: bar.compositor
            output: bar.screen ? bar.screen.name : ""
        }
    }

    Component {
        id: clipboardWidget
        BarButton {
            theme: bar.theme
            icon: "clipboard-list"
            tooltip: "Clipboard history  ·  Mod+Alt+V"
            onClicked: bar.clipboardRequested()
        }
    }

    Component {
        id: audioWidget
        Audio {
            theme: bar.theme
            onClicked: bar.controlCenterRequested("audio", bar.zoneOf("audio"))
        }
    }

    Component {
        id: bluetoothWidget
        BluetoothStatus {
            theme: bar.theme
            onClicked: bar.controlCenterRequested("bluetooth", bar.zoneOf("bluetooth"))
        }
    }

    Component {
        id: networkWidget
        NetworkStatus {
            theme: bar.theme
            monitor: bar.monitor
            onClicked: bar.controlCenterRequested("network", bar.zoneOf("network"))
        }
    }

    Component {
        id: clockWidget
        Clock {
            theme: bar.theme
            format: bar.settings.clockFormat
            onClicked: bar.controlCenterRequested("calendar", bar.zoneOf("clock"))
        }
    }

    Component {
        id: powerWidget
        BarButton {
            theme: bar.theme
            icon: "power"
            danger: true
            tooltip: "Power  ·  Mod+Alt+P"
            onClicked: bar.powerRequested()
        }
    }

    Component {
        id: idleInhibitorWidget
        CaffeineButton {
            theme: bar.theme
            inhibiting: bar.caffeine
            onClicked: bar.caffeineToggled()
        }
    }

    // The ones that go without a capsule when they're alone in their group.
    readonly property var bareWidgets: ["screencast"]

    readonly property var widgetComponents: ({
        launcher: launcherWidget, about: aboutWidget, controlCenter: controlCenterWidget, activeWindow: activeWindowWidget, apps: appsWidget, screencast: screencastWidget,
        system: systemWidget, cpu: cpuWidget, memory: memoryWidget, gpu: gpuWidget, workspaces: workspacesWidget, clipboard: clipboardWidget,
        audio: audioWidget, bluetooth: bluetoothWidget, network: networkWidget,
        clock: clockWidget, power: powerWidget, idleInhibitor: idleInhibitorWidget, notifications: notificationsWidget, drives: drivesWidget
    })

    // A capsule with a group's widgets. It hides if none of them is shown
    // (e.g. the active window with no focused window).
    component Group: Capsule {
        id: group
        required property var ids
        // Only capsule-less widgets (e.g. the screen sharing dot): no background,
        // on the bar.
        readonly property bool bare: ids.every(id => bar.bareWidgets.includes(id))

        theme: bar.theme
        color: bare ? "transparent" : theme.capsule
        // itemAt() isn't reactive: count triggers re-evaluation when the Loaders
        // are created. With `shown` and not `visible`: visible depends on the
        // parent, and a hidden capsule would never show again.
        visible: loaders.count > 0 && ids.some((id, i) => i < loaders.count && loaders.itemAt(i) && loaders.itemAt(i).shown)
        // Workspaces with more room (they're loose pills, not buttons).
        padding: ids.includes("workspaces") ? 10 : 2
        spacing: ids.includes("workspaces") ? 5 : 6

        Repeater {
            id: loaders
            model: group.ids

            Loader {
                required property string modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                sourceComponent: bar.widgetComponents[modelData] ?? null
                // A widget can hide itself with its own `shown`.
                readonly property bool shown: item !== null && (item.shown ?? true)
                visible: shown
            }
        }
    }

    // A zone's row of groups.
    component Zone: Row {
        id: zone
        required property var groups
        spacing: 6

        Repeater {
            model: zone.groups

            Group {
                required property var modelData
                anchors.verticalCenter: parent ? parent.verticalCenter : undefined
                ids: modelData
            }
        }
    }

    Zone {
        anchors.left: parent.left
        anchors.leftMargin: bar.contentInset
        anchors.verticalCenter: parent.verticalCenter
        groups: bar.layout.left
    }

    // Center: the group with the workspaces (if there's none, the middle one)
    // at the exact center; the ones before it to its left and the ones after
    // to its right.
    readonly property int centerIndex: {
        const groups = layout.center
        const i = groups.findIndex(g => g.includes("workspaces"))
        return i >= 0 ? i : Math.floor((groups.length - 1) / 2)
    }

    Zone {
        anchors.right: centerGroup.left
        anchors.rightMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        groups: bar.layout.center.slice(0, Math.max(0, bar.centerIndex))
    }

    Zone {
        id: centerGroup
        anchors.centerIn: parent
        groups: bar.centerIndex >= 0 && bar.layout.center.length > 0 ? [bar.layout.center[bar.centerIndex]] : []
    }

    Zone {
        anchors.left: centerGroup.right
        anchors.leftMargin: 6
        anchors.verticalCenter: parent.verticalCenter
        groups: bar.layout.center.slice(bar.centerIndex + 1)
    }

    Zone {
        anchors.right: parent.right
        anchors.rightMargin: bar.contentInset
        anchors.verticalCenter: parent.verticalCenter
        groups: bar.layout.right
    }
}
