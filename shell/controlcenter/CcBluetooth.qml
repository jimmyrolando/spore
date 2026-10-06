import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import "../common"
import "../services"

// Control Center → Bluetooth (design v2): on/off, discoverable, and the
// devices in three groups: connected, paired and found (with the button to
// scan). Only the list scrolls.
ColumnLayout {
    id: root

    required property Theme theme
    // Pairs, and shows what a pairing asks (BluetoothAgent, in shell.qml: it
    // goes on if this page closes).
    property BluetoothAgent agent: null

    spacing: 12

    readonly property var adapter: Bluetooth.defaultAdapter
    readonly property bool on: adapter !== null && adapter.enabled
    readonly property var devices: Bluetooth.devices.values
    readonly property var connectedDevices: devices.filter(d => d.connected)
    readonly property var pairedDevices: devices.filter(d => d.paired && !d.connected)
    // Found while scanning: unpaired and with a name.
    readonly property var foundDevices: devices.filter(d => !d.paired && !d.connected && d.name && d.name !== d.address)

    readonly property string subtitle: !adapter ? "No adapter" : !on ? "Off" : connectedDevices.length + " connected"

    // Scanning stops when the page closes.
    Component.onDestruction: if (adapter && adapter.discovering) adapter.discovering = false

    // Icon by type (BlueZ gives it as a freedesktop icon name).
    function iconFor(device: var): string {
        const i = device.icon || ""
        if (i.includes("headset") || i.includes("headphone") || i.includes("audio")) return "headphones"
        if (i.includes("keyboard")) return "keyboard"
        if (i.includes("gaming") || i.includes("joystick")) return "gamepad-2"
        return "smartphone"
    }

    // --- Switches ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        implicitHeight: switches.implicitHeight + 28

        component SwitchRow: RowLayout {
            id: switchRow
            property string label: ""
            property string sub: ""
            property bool checked: false
            property bool available: true
            signal toggled()

            Layout.fillWidth: true
            spacing: 12
            opacity: available ? 1 : 0.4

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 1
                UiText {
                    theme: root.theme
                    text: switchRow.label
                    font.pixelSize: 14
                    font.weight: Font.Medium
                }
                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: switchRow.sub
                    color: root.theme.muted
                    font.pixelSize: 12
                }
            }

            CcSwitch {
                theme: root.theme
                checked: switchRow.checked
                enabled: switchRow.available
                onToggled: if (switchRow.available) switchRow.toggled()
            }
        }

        ColumnLayout {
            id: switches
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 12

            SwitchRow {
                label: "Bluetooth"
                sub: root.adapter === null ? "No adapter found" : root.on ? "On" : "Off"
                checked: root.on
                available: root.adapter !== null
                onToggled: root.adapter.enabled = !root.adapter.enabled
            }

            SwitchRow {
                label: "Discoverable"
                sub: "Visible to nearby devices as \"" + (root.adapter ? root.adapter.name : "") + "\""
                checked: root.adapter !== null && root.adapter.discoverable
                available: root.on
                onToggled: root.adapter.discoverable = !root.adapter.discoverable
            }
        }
    }

    // --- What a pairing asks (BluetoothAgent) ---
    CcCard {
        id: ask
        theme: root.theme
        Layout.fillWidth: true
        readonly property string request: root.agent && root.agent.device ? root.agent.request : ""
        readonly property string name: request ? (root.agent.device.name || root.agent.device.address) : ""
        visible: request !== ""
        implicitHeight: askColumn.implicitHeight + 28

        ColumnLayout {
            id: askColumn
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 10

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                text: ask.request === "type" ? "Type this code on “" + ask.name + "”, then press Enter"
                    : ask.request === "confirm" ? "Does “" + ask.name + "” show this code?"
                    : "Pair with “" + ask.name + "”?"
                font.pixelSize: 14
                font.weight: Font.Medium
            }

            MonoText {
                theme: root.theme
                visible: text !== ""
                // 123456 -> 123 456: easier to read off and type.
                text: ask.request && root.agent.code ? root.agent.code.replace(/^(\d{3})(\d{3})$/, "$1 $2") : ""
                font.pixelSize: 30
                font.letterSpacing: 2
            }

            RowLayout {
                spacing: 8
                CcButton {
                    theme: root.theme
                    visible: ask.request !== "type"
                    primary: true
                    label: ask.request === "confirm" ? "Yes" : "Pair"
                    onClicked: root.agent.answer(true)
                }
                CcButton {
                    theme: root.theme
                    label: ask.request === "confirm" ? "No" : "Cancel"
                    onClicked: {
                        if (ask.request === "type") root.agent.cancel()
                        else root.agent.answer(false)
                    }
                }
            }
        }
    }

    // --- Devices ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.on

        Flickable {
            anchors.fill: parent
            anchors.leftMargin: 10
            anchors.rightMargin: 10
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            contentHeight: groups.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: groups
                width: parent.width
                spacing: 6

                Repeater {
                    model: [
                        { title: "Connected", kind: "connected", devices: root.connectedDevices, empty: "No devices connected" },
                        { title: "Paired", kind: "paired", devices: root.pairedDevices, empty: "No other paired devices" },
                        { title: "Available", kind: "found", devices: root.foundDevices,
                          empty: root.adapter && root.adapter.discovering ? "Searching for nearby devices…" : "Press Scan to look for new devices" }
                    ]

                    Column {
                        id: group
                        required property var modelData
                        width: groups.width
                        spacing: 4
                        bottomPadding: 6

                        RowLayout {
                            width: parent.width
                            height: 28

                            CcSection {
                                theme: root.theme
                                Layout.leftMargin: 6
                                Layout.fillWidth: true
                                text: group.modelData.title
                            }

                            CcButton {
                                theme: root.theme
                                visible: group.modelData.kind === "found"
                                size: 26
                                label: root.adapter && root.adapter.discovering ? "Scanning…" : "Scan"
                                onClicked: root.adapter.discovering = !root.adapter.discovering
                            }
                        }

                        UiText {
                            theme: root.theme
                            visible: group.modelData.devices.length === 0
                            leftPadding: 6
                            topPadding: 4
                            bottomPadding: 4
                            text: group.modelData.empty
                            color: root.theme.muted
                            font.pixelSize: 12
                        }

                        Repeater {
                            model: group.modelData.devices

                            Rectangle {
                                id: row
                                required property var modelData
                                readonly property string kind: group.modelData.kind
                                readonly property bool connected: kind === "connected"

                                width: group.width
                                height: 46
                                radius: 10
                                color: rowHover.hovered ? root.theme.alpha(root.theme.accent, 0.07) : "transparent"

                                HoverHandler {
                                    id: rowHover
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 10
                                    spacing: 12

                                    Rectangle {
                                        implicitWidth: 30
                                        implicitHeight: 30
                                        radius: 9
                                        color: row.connected ? root.theme.accent : root.theme.alpha(root.theme.accent, 0.1)
                                        Icon {
                                            anchors.centerIn: parent
                                            name: root.iconFor(row.modelData)
                                            size: 15
                                            stroke: 1.4
                                            color: row.connected ? root.theme.textOnAccent : root.theme.accent
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        UiText {
                                            theme: root.theme
                                            Layout.fillWidth: true
                                            text: row.modelData.name || row.modelData.address
                                        }
                                        UiText {
                                            theme: root.theme
                                            text: (row.connected ? "Connected" : row.kind === "paired" ? "Paired" : "Available")
                                                + (row.modelData.batteryAvailable ? " · " + Math.round(row.modelData.battery * 100) + "%" : "")
                                            color: row.connected ? root.theme.ok : root.theme.muted
                                            font.pixelSize: 11
                                        }
                                    }

                                    CcButton {
                                        theme: root.theme
                                        // From when the agent starts, before BlueZ is asked.
                                        readonly property bool ours: root.agent !== null && root.agent.device === row.modelData
                                        readonly property bool pairing: row.modelData.pairing || ours
                                        label: row.connected ? "Disconnect"
                                            : row.kind === "paired" ? (row.modelData.state === BluetoothDeviceState.Connecting ? "Connecting…" : "Connect")
                                            : pairing ? "Pairing…" : "Pair"
                                        onClicked: {
                                            if (row.connected) {
                                                row.modelData.disconnect()
                                            } else if (row.kind === "paired") {
                                                row.modelData.connect()
                                            } else if (ours) {
                                                root.agent.cancel()
                                            } else if (row.modelData.pairing) {
                                                row.modelData.cancelPair()
                                            } else if (root.agent) {
                                                // It also makes it trusted once paired.
                                                root.agent.pair(row.modelData)
                                            } else {
                                                row.modelData.pair()
                                            }
                                        }
                                    }

                                    CcButton {
                                        theme: root.theme
                                        visible: row.kind !== "found"
                                        flat: true
                                        danger: true
                                        icon: "trash"
                                        onClicked: row.modelData.forget()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Item {
        Layout.fillHeight: true
        visible: !root.on
    }
}
