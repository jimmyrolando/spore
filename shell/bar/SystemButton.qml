import QtQuick
import "../services"

// System button in the bar: the CPU icon (Lucide). Click: the Control
// Center's System page; tooltip: CPU, memory and GPU usage (from
// SystemMonitor.qml).
BarButton {
    id: root

    required property SystemMonitor monitor

    function pct(v: real): string {
        return Math.round(v * 100) + "%"
    }

    function temp(t: real): string {
        return t >= 0 ? "  ·  " + Math.round(t) + "°" : ""
    }

    icon: "cpu"
    tooltipRows: [
        { label: "CPU", value: pct(Math.max(0, monitor.cpu)) + temp(monitor.cpuTemp) },
        { label: "Memory", value: pct(Math.max(0, monitor.mem)) }
    ].concat(monitor.gpu >= 0 ? [{ label: "GPU", value: pct(monitor.gpu) + temp(monitor.gpuTemp) }] : [])
}
