import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Networking
import "../common"

// Control Center → Network (design v2): ethernet (with a switch) and wifi:
// turn it on or off, available networks, connect (with a password if
// needed), disconnect and forget. Only the network list scrolls.
ColumnLayout {
    id: root

    required property Theme theme

    spacing: 12

    readonly property var devices: Networking.devices.values
    readonly property var wifiDevice: devices.find(d => d.type === DeviceType.Wifi) ?? null
    readonly property var wiredDevices: devices.filter(d => d.type === DeviceType.Wired)
    readonly property var wiredActive: wiredDevices.find(d => d.connected) ?? null
    readonly property var wifiCurrent: wifiDevice ? (wifiDevice.networks.values.find(n => n.connected) ?? null) : null
    // Networks: the connected one first, then the known ones, then by signal.
    readonly property var networks: wifiDevice
        ? wifiDevice.networks.values.filter(n => n.name).slice().sort((a, b) =>
            (b.connected - a.connected) || (b.known - a.known) || (b.signalStrength - a.signalStrength))
        : []

    readonly property string subtitle: [
        wiredActive ? wiredActive.name + " " + (addresses[wiredActive.name] ?? "") : "",
        wifiCurrent ? wifiCurrent.name : ""
    ].filter(s => s.trim()).join(" · ") || "Offline"

    // With the page open, the wifi scans for networks.
    Component.onCompleted: if (wifiDevice) wifiDevice.scannerEnabled = true
    Component.onDestruction: if (wifiDevice) wifiDevice.scannerEnabled = false

    function strengthOf(network: var): real {
        const s = network.signalStrength
        return s > 1 ? s / 100 : s
    }

    // IP and speed of each interface (Quickshell doesn't provide them).
    property var addresses: ({})
    property var speeds: ({})
    Process {
        id: ipReader
        running: true
        command: ["sh", "-c", `
            ip -4 -o addr show scope global | awk '{ split($4, a, "/"); print "ip", $2, a[1] }'
            for i in /sys/class/net/*; do
                s=$(cat "$i/speed" 2>/dev/null) && [ "$s" -gt 0 ] 2>/dev/null && echo "speed \${i##*/} $s"
            done`]
        stdout: StdioCollector {
            onStreamFinished: {
                const ips = {}, speeds = {}
                for (const line of text.trim().split("\n")) {
                    const [kind, dev, value] = line.split(" ")
                    if (kind === "ip" && value) ips[dev] = value
                    if (kind === "speed" && value) speeds[dev] = Number(value)
                }
                root.addresses = ips
                root.speeds = speeds
            }
        }
    }
    Timer {
        interval: 5000
        running: true
        repeat: true
        onTriggered: ipReader.running = true
    }
    // After turning ethernet on or off: the IP takes a moment to show up.
    Timer {
        id: ipRefresh
        interval: 2500
        onTriggered: ipReader.running = true
    }

    function speedText(mbps: real): string {
        return mbps >= 1000 ? (mbps / 1000) + " Gb/s" : mbps + " Mb/s"
    }

    // Network asking for a password, and the last connection error.
    property string askingFor: ""
    property string failure: ""

    // --- Ethernet ---
    // Always visible (also when off or unplugged), with a switch. It's turned
    // on and off with nmcli: Quickshell can only disconnect, and a card turned
    // off by hand doesn't come back on its own until it's connected.
    Repeater {
        model: root.wiredDevices

        CcCard {
            id: wired
            required property var modelData
            theme: root.theme
            Layout.fillWidth: true
            implicitHeight: 62

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 12

                Rectangle {
                    implicitWidth: 34
                    implicitHeight: 34
                    radius: 10
                    color: root.theme.alpha(root.theme.accent, 0.1)
                    Icon {
                        anchors.centerIn: parent
                        name: "ethernet-port"
                        size: 16
                        stroke: 1.4
                        color: root.theme.accent
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1
                    UiText {
                        theme: root.theme
                        text: "Ethernet"
                        font.pixelSize: 14
                        font.weight: Font.Medium
                    }
                    MonoText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: wired.modelData.connected
                            ? [wired.modelData.name, root.addresses[wired.modelData.name] ?? "", root.speeds[wired.modelData.name] ? root.speedText(root.speeds[wired.modelData.name]) : ""].filter(s => s).join(" · ")
                            : !wired.modelData.hasLink ? wired.modelData.name + " · Cable unplugged"
                            : wired.modelData.name + " · Disabled"
                        color: root.theme.muted
                    }
                }

                CcSwitch {
                    theme: root.theme
                    checked: wired.modelData.connected
                    onToggled: {
                        Quickshell.execDetached(["nmcli", "device", wired.modelData.connected ? "disconnect" : "connect", wired.modelData.name])
                        ipRefresh.restart()
                    }
                }
            }
        }
    }

    // --- Wi-Fi ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.wifiDevice !== null

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 6

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: "Wi-Fi"
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }

                CcSwitch {
                    theme: root.theme
                    checked: Networking.wifiEnabled
                    onToggled: Networking.wifiEnabled = !Networking.wifiEnabled
                }
            }

            UiText {
                theme: root.theme
                visible: !Networking.wifiEnabled
                Layout.topMargin: 4
                text: "Wi-Fi is off"
                color: root.theme.muted
                font.pixelSize: 12
            }

            UiText {
                theme: root.theme
                visible: root.failure !== ""
                text: root.failure
                color: root.theme.danger
                font.pixelSize: 12
            }

            UiText {
                theme: root.theme
                visible: Networking.wifiEnabled && root.networks.length === 0
                text: "Searching…"
                color: root.theme.muted
                font.pixelSize: 12
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                // The rows' hover reaches the edge: the list reaches 6 into the card's
                // padding.
                Layout.leftMargin: -6
                Layout.rightMargin: -6
                visible: Networking.wifiEnabled
                clip: true
                contentHeight: list.implicitHeight
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: list
                    width: parent.width
                    spacing: 6

                    Repeater {
                        model: root.networks

                        Rectangle {
                            id: net
                            required property var modelData
                            readonly property bool current: modelData.connected
                            readonly property bool secured: modelData.security !== WifiSecurityType.Open
                            readonly property bool asking: root.askingFor === modelData.name
                            readonly property real strength: root.strengthOf(modelData)

                            Connections {
                                target: net.modelData
                                function onConnectionFailed(reason: int): void {
                                    root.failure = net.modelData.name + ": "
                                        + (reason === ConnectionFailReason.NoSecrets ? "wrong password" : "could not connect")
                                }
                            }

                            width: list.width
                            implicitHeight: netColumn.implicitHeight + 12
                            radius: 10
                            color: current ? root.theme.accentSoft
                                : rowHover.hovered ? root.theme.alpha(root.theme.accent, 0.07)
                                : "transparent"

                            HoverHandler {
                                id: rowHover
                            }

                            ColumnLayout {
                                id: netColumn
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 8

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.minimumHeight: 32
                                    spacing: 12

                                    // Signal: 4 bars (thresholds 1/30/55/80%).
                                    Row {
                                        Layout.preferredWidth: 18
                                        Layout.preferredHeight: 13
                                        spacing: 2
                                        Repeater {
                                            model: [0.01, 0.30, 0.55, 0.80]
                                            Rectangle {
                                                required property real modelData
                                                required property int index
                                                anchors.bottom: parent.bottom
                                                width: 3
                                                height: 4 + index * 3
                                                radius: 1
                                                color: net.strength >= modelData
                                                    ? (net.current ? root.theme.accent : root.theme.ink2)
                                                    : root.theme.alpha(root.theme.ink2, 0.2)
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        UiText {
                                            theme: root.theme
                                            Layout.fillWidth: true
                                            text: net.modelData.name
                                            font.weight: net.current ? Font.DemiBold : Font.Normal
                                        }
                                        MonoText {
                                            theme: root.theme
                                            visible: net.current
                                            text: [root.wifiDevice ? (root.addresses[root.wifiDevice.name] ?? "") : "", "Connected"].filter(s => s).join(" · ")
                                            color: root.theme.accent
                                            font.pixelSize: 11
                                        }
                                    }

                                    MonoText {
                                        theme: root.theme
                                        text: Math.round(net.strength * 100) + "%"
                                        color: root.theme.muted
                                    }

                                    Icon {
                                        visible: net.secured
                                        name: "lock"
                                        size: 12
                                        color: root.theme.muted2
                                    }

                                    CcButton {
                                        theme: root.theme
                                        visible: net.current
                                        label: "Disconnect"
                                        onClicked: net.modelData.disconnect()
                                    }

                                    CcButton {
                                        theme: root.theme
                                        visible: !net.current
                                        link: true
                                        label: net.modelData.stateChanging ? "…" : "Connect"
                                        onClicked: {
                                            root.failure = ""
                                            if (net.secured && !net.modelData.known) root.askingFor = net.modelData.name
                                            else net.modelData.connect()
                                        }
                                    }

                                    // Forget (only the current one, as in the design).
                                    CcButton {
                                        theme: root.theme
                                        visible: net.current && net.modelData.known
                                        flat: true
                                        danger: true
                                        icon: "trash"
                                        onClicked: net.modelData.forget()
                                    }
                                }

                                // Password (unknown secured networks).
                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.bottomMargin: 4
                                    visible: net.asking
                                    spacing: 8

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 32
                                        radius: 8
                                        color: root.theme.insetBg
                                        border.width: 1
                                        border.color: psk.activeFocus ? root.theme.accent : root.theme.cardBorder

                                        TextInput {
                                            id: psk
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            verticalAlignment: TextInput.AlignVCenter
                                            echoMode: TextInput.Password
                                            passwordCharacter: "•"
                                            color: root.theme.text
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 13
                                            clip: true
                                            onVisibleChanged: if (visible) forceActiveFocus()
                                            onAccepted: joinButton.clicked()
                                            Keys.onEscapePressed: root.askingFor = ""

                                            UiText {
                                                theme: root.theme
                                                anchors.verticalCenter: parent.verticalCenter
                                                visible: psk.text === ""
                                                text: "Password"
                                                color: root.theme.muted
                                            }
                                        }
                                    }

                                    CcButton {
                                        id: joinButton
                                        theme: root.theme
                                        label: "Join"
                                        primary: true
                                        onClicked: {
                                            net.modelData.connectWithPsk(psk.text)
                                            psk.text = ""
                                            root.askingFor = ""
                                        }
                                    }

                                    CcButton {
                                        theme: root.theme
                                        label: "Cancel"
                                        onClicked: root.askingFor = ""
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // No wifi: keep the ethernet from floating at the top.
    Item {
        Layout.fillHeight: true
        visible: root.wifiDevice === null
    }
}
