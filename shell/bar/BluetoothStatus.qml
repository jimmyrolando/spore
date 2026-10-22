import QtQuick
import Quickshell.Bluetooth

// Bluetooth (BlueZ): dimmed when off. Click: its Control Center tab.
// "BluetoothStatus" and not "Bluetooth" so as not to shadow the singleton.
BarButton {
    id: root

    readonly property BluetoothAdapter adapter: Bluetooth.defaultAdapter
    readonly property bool enabled: adapter !== null && adapter.enabled
    readonly property var connected: Bluetooth.devices.values.filter(d => d.connected)

    // `shown` and not just visible: with no adapter (a VM), its capsule hides
    // too, if it's alone in it (see Group in Bar.qml).
    readonly property bool shown: adapter !== null
    visible: shown
    icon: "bluetooth"
    dim: !enabled
    // Connected devices with their battery; otherwise, the state.
    tooltip: !adapter ? "No Bluetooth adapter" : !enabled ? "Bluetooth off" : connected.length === 0 ? "No devices connected" : ""
    tooltipRows: enabled ? connected.map(d => ({ label: d.name || d.address, value: d.batteryAvailable ? Math.round(d.battery * 100) + "%" : "Connected" })) : []
}
