import QtQuick
import "../services"

// External drives in the bar: the eject icon (Lucide), only when one is
// connected. Tooltip: each volume with its used space; click: the Control
// Center's Drives page (open, mount, eject).
BarButton {
    id: root

    property DrivesService service: null

    // `shown` and not just visible: with no drives, its capsule hides too (see
    // Group in Bar.qml).
    readonly property bool shown: service !== null && service.count > 0
    visible: shown

    function gb(bytes: real): string {
        return bytes >= 1e12 ? (bytes / 1e12).toFixed(1) + " TB" : Math.round(bytes / 1e9) + " GB"
    }

    icon: "eject"
    tooltipRows: !shown ? [] : service.drives.reduce((rows, d) => rows.concat(
        d.volumes.length === 0 ? [{ label: d.name, value: "Not mounted" }]
        : d.volumes.map(v => ({
            label: v.label || d.name,
            value: v.mountpoint && v.total > 0 ? gb(v.used) + " / " + gb(v.total) : "Not mounted"
        }))), [])
}
