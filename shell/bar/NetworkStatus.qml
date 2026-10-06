import QtQuick
import Quickshell.Io
import Quickshell.Networking
import "../services"

// Network (NetworkManager): wired if one is connected (it takes priority),
// otherwise wifi; dimmed with no connection. Click: the Control Center's
// Network tab. "NetworkStatus" and not "Network" so as not to shadow the
// module's type.
BarButton {
    id: root

    // For download/upload in the tooltip (see SystemMonitor.qml).
    property SystemMonitor monitor: null

    readonly property var devices: Networking.devices.values
    readonly property var wired: devices.find(d => d.type === DeviceType.Wired && d.connected) ?? null
    readonly property var wifi: devices.find(d => d.type === DeviceType.Wifi && d.connected) ?? null
    readonly property var wifiNetwork: wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null
    // 0..1 (just in case: if it came as 0..100 it's normalized).
    readonly property real strength: wifiNetwork
        ? (wifiNetwork.signalStrength > 1 ? wifiNetwork.signalStrength / 100 : wifiNetwork.signalStrength)
        : 0
    readonly property var active: wired ?? wifi

    icon: wired ? "ethernet-port" : "wifi"
    dim: !active

    // IP of the active connection: read when the tooltip shows.
    property string ip: ""
    onHoveredChanged: if (hovered && active) ipReader.running = true

    Process {
        id: ipReader
        command: ["sh", "-c", "ip -4 -o addr show dev \"$1\" | awk '{split($4, a, \"/\"); print a[1]; exit}'", "_", root.active ? root.active.name : "lo"]
        stdout: StdioCollector {
            onStreamFinished: root.ip = text.trim()
        }
    }

    tooltip: active ? "" : "Offline"
    tooltipRows: !active ? [] : [
        { label: "Network", value: wired ? "Wired" : "Wi-Fi" },
        { label: "Interface", value: active.name }
    ].concat(wifiNetwork ? [
        { label: "SSID", value: wifiNetwork.name },
        { label: "Signal", value: Math.round(strength * 100) + "%" }
    ] : []).concat(ip ? [{ label: "IP", value: ip }] : [])
    .concat(monitor ? [
        { label: "Download", value: rate(monitor.rxRate) },
        { label: "Upload", value: rate(monitor.txRate) }
    ] : [])

    function rate(bps: real): string {
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }
}
