import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"
import "../services"
import "../common/brand.js" as Brand

// About (the bar's NixOS logo): machine and system data, fastfetch style, in
// a card in the center with the screen dimmed. "Copy" copies them as text
// (to paste when asking for help). Esc or a click outside closes it.
// shell.qml loads it with a LazyLoader only while it's open; the data is
// already read (SystemInfo.qml) and it appears with a short fade.
PanelWindow {
    id: root

    required property Theme theme
    required property SystemMonitor monitor

    signal closeRequested()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-about"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    // The data (read beforehand, see SystemInfo.qml).
    required property SystemInfo system
    property bool copied: false
    // A small secret: a click on one of the palette's colors paints the logo
    // with it, and a second click on it gives the accent back. Nothing hints
    // at it (not even the cursor), and nothing is saved: closing resets it.
    // -1: the accent.
    property int logoColor: -1

    readonly property var info: system.info

    function gib(bytes: real): string {
        return (bytes / 1073741824).toFixed(1)
    }

    readonly property var rows: [
        ["OS", info.os],
        ["Nixpkgs", system.nixpkgs],
        // Only if the flake records it (system.configurationRevision).
        ["Flake", (info.nix_configurationRevision || "").slice(0, 7)],
        ["Kernel", info.kernel],
        ["Uptime", monitor.formatUptime()],
        ["Packages", info.pkgs_system ? Number(info.pkgs_system).toLocaleString(Qt.locale("en_US"), "f", 0) + " (system) · "
            + Number(info.pkgs_user || 0).toLocaleString(Qt.locale("en_US"), "f", 0) + " (user)" : ""],
        // The desktop environment: the shell itself (brand.js).
        ["DE", Brand.name + " " + Brand.version],
        ["WM", system.wm],
        ["Shell", [info.shell, info.terminal].filter(s => s).join(" · ")],
        ["Display", system.display],
        ["CPU", system.cpuName + (monitor.cores ? " · " + monitor.cores + "C/" + monitor.threads + "T" : "")],
        ["GPU", system.gpuName],
        ["Memory", gib(monitor.memUsed) + " / " + gib(monitor.memTotal) + " GiB"],
        ["Disk (/)", info.disk ? info.disk.split("\t").map(Number).map(b => gib(b)).join(" / ") + " GiB" : ""],
        ["Theme", theme.label(theme.palette) + " · " + (theme.isDark ? "Dark" : "Light")]
    ].filter(r => r[1])

    // Fade in (0 -> 1): background and card, without popping in.
    property real shown: 0
    NumberAnimation on shown {
        from: 0
        to: 1
        duration: 150
        easing.type: Easing.OutCubic
    }

    function asText(): string {
        const user = info.user || ""
        return [user, "-".repeat(user.length)].concat(rows.map(r => r[0] + ": " + r[1])).join("\n")
    }

    // Dimmed background: a click closes it.
    Rectangle {
        anchors.fill: parent
        opacity: root.shown
        color: Qt.rgba(20 / 255, 22 / 255, 60 / 255, 0.3)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    RectangularShadow {
        anchors.fill: card
        opacity: root.shown
        offset.y: 24
        blur: 64
        radius: card.radius
        color: Qt.rgba(30 / 255, 32 / 255, 80 / 255, 0.35)
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        opacity: root.shown
        scale: 0.97 + 0.03 * root.shown
        width: 960
        height: content.implicitHeight + 72
        radius: 20
        color: root.theme.panelBg
        border.width: 1
        border.color: root.theme.panelBorder

        // So a click on the card doesn't close it.
        MouseArea {
            anchors.fill: parent
        }

        focus: true
        Keys.onEscapePressed: root.closeRequested()

        CcButton {
            theme: root.theme
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 14
            size: 32
            icon: "x"
            iconSize: 13
            onClicked: root.closeRequested()
        }

        ColumnLayout {
            id: content
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 36
            spacing: 28

            RowLayout {
                Layout.fillWidth: true
                spacing: 40

                // Logo and user.
                ColumnLayout {
                    Layout.alignment: Qt.AlignTop
                    Layout.preferredWidth: 320
                    Layout.topMargin: 4
                    spacing: 20

                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "nixos"
                        size: 300
                        color: root.logoColor >= 0 ? root.theme.current.ansi[root.logoColor] : root.theme.accent
                        Behavior on color { ColorAnimation { duration: 250 } }
                    }

                    ColumnLayout {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 2

                        MonoText {
                            theme: root.theme
                            Layout.alignment: Qt.AlignHCenter
                            text: root.info.user || ""
                            font.pixelSize: 17
                            font.weight: Font.Medium
                        }
                        UiText {
                            theme: root.theme
                            Layout.alignment: Qt.AlignHCenter
                            text: root.info.os || ""
                            color: root.theme.muted
                            font.pixelSize: 13
                        }
                    }
                }

                // Details.
                GridLayout {
                    Layout.fillWidth: true
                    columns: 2
                    columnSpacing: 20
                    rowSpacing: 9

                    Repeater {
                        model: root.rows

                        UiText {
                            required property var modelData
                            required property int index
                            theme: root.theme
                            Layout.row: index
                            Layout.column: 0
                            text: modelData[0]
                            color: root.theme.accent
                            font.weight: Font.DemiBold
                            font.pixelSize: 14
                        }
                    }

                    Repeater {
                        model: root.rows

                        MonoText {
                            required property var modelData
                            required property int index
                            theme: root.theme
                            Layout.row: index
                            Layout.column: 1
                            Layout.fillWidth: true
                            text: modelData[1]
                            font.pixelSize: 14
                        }
                    }
                }
            }

            // The palette's 16 colors (like fastfetch's blocks) and copy.
            RowLayout {
                Layout.fillWidth: true
                spacing: 16

                // The same width as the logo's column: the colors sit centered under the
                // logo and the user.
                Item {
                    Layout.preferredWidth: 320
                    implicitHeight: colors.height

                    Grid {
                        id: colors
                        anchors.horizontalCenter: parent.horizontalCenter
                        columns: 8
                        spacing: 4

                        Repeater {
                            model: 16

                            Rectangle {
                                id: swatch
                                required property int index
                                width: 24
                                height: 14
                                radius: 4
                                color: root.theme.current.ansi[index]

                                // The secret (logoColor): no hover, no cursor.
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: root.logoColor = root.logoColor === swatch.index ? -1 : swatch.index
                                }
                            }
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                CcButton {
                    theme: root.theme
                    size: 32
                    icon: "copy"
                    label: root.copied ? "Copied" : "Copy"
                    onClicked: {
                        Quickshell.execDetached(["wl-copy", root.asText()])
                        root.copied = true
                        copiedReset.restart()
                    }
                }
            }
        }
    }

    Timer {
        id: copiedReset
        interval: 2000
        onTriggered: root.copied = false
    }
}
