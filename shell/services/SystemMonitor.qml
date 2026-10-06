import QtQuick
import Quickshell
import Quickshell.Io

// System measurements, once for the whole shell: the bar (SystemButton.qml)
// and the Control Center's System tab read them from here. It always
// measures (every `interval` ms) and keeps the last minute, so the graphs
// are already full when the panel opens.
//
// No processes: reads /proc and /sys directly with FileView (a script per
// measurement would cost a fork per second). The sensors are looked up once
// at startup, by name (coretemp/k10temp for the CPU, amdgpu/nouveau for the
// GPU) and not by hwmonN, which can change between boots.
Scope {
    id: root

    property int interval: 1000
    // Stored samples (the graphs' width).
    readonly property int samples: 60

    // 0..1; -1 = not available on this machine.
    property real cpu: -1
    property real mem: -1
    property real gpu: -1
    // °C; -1 = no sensor.
    property real cpuTemp: -1
    property real gpuTemp: -1
    // Bytes.
    property real memUsed: 0
    property real memTotal: 0
    property real swapUsed: 0
    property real swapTotal: 0
    // File cache (Cached + Buffers + SReclaimable): it frees itself.
    property real memCache: 0
    property real vramUsed: -1
    property real vramTotal: -1
    // Seconds since boot.
    property real uptime: 0
    // Physical cores and threads (read once).
    property int cores: 0
    property int threads: 0
    // Bytes per second (not counting lo).
    property real rxRate: 0
    property real txRate: 0
    // "2.21 / 1.99 / 1.68"
    property string load: ""

    // Histories (0..1, newest last).
    property var cpuHistory: []
    property var memHistory: []
    property var gpuHistory: []
    property var rxHistory: []
    property var txHistory: []

    // "3h 12m", "22h 41m", "2d 4h".
    function formatUptime(): string {
        const m = Math.floor(uptime / 60)
        const d = Math.floor(m / 1440), h = Math.floor(m / 60) % 24
        return d > 0 ? d + "d " + h + "h" : h > 0 ? h + "h " + (m % 60) + "m" : (m % 60) + "m"
    }

    function push(list: var, v: real): var {
        const next = list.concat([v])
        return next.length > samples ? next.slice(next.length - samples) : next
    }

    // Sensor paths (found by `discover`).
    property string cpuTempPath: ""
    property string gpuTempPath: ""
    property string gpuBusyPath: ""
    property string vramPath: ""

    Process {
        id: discover
        running: true
        command: ["sh", "-c", `
            for h in /sys/class/hwmon/hwmon*; do
                case "$(cat "$h/name" 2>/dev/null)" in
                    coretemp|k10temp|zenpower) echo "cputemp $h/temp1_input" ;;
                    amdgpu|nouveau) echo "gputemp $h/temp1_input" ;;
                esac
            done
            for d in /sys/class/drm/card*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                echo "gpubusy $d/gpu_busy_percent"
                [ -r "$d/mem_info_vram_used" ] && echo "vram $d/mem_info_vram_used"
                [ -r "$d/mem_info_vram_total" ] && echo "vramtotal $(cat "$d/mem_info_vram_total")"
                break
            done
            echo "threads $(nproc)"
            echo "cores $(grep '^core id' /proc/cpuinfo | sort -u | wc -l)"`]
        stdout: StdioCollector {
            onStreamFinished: {
                for (const line of text.trim().split("\n")) {
                    const [key, path] = line.split(" ")
                    // The first one that shows up (e.g. the first GPU with a sensor).
                    if (key === "cputemp" && !root.cpuTempPath) root.cpuTempPath = path
                    if (key === "gputemp" && !root.gpuTempPath) root.gpuTempPath = path
                    if (key === "gpubusy") root.gpuBusyPath = path
                    if (key === "vram") root.vramPath = path
                    if (key === "vramtotal") root.vramTotal = Number(path)
                    if (key === "threads") root.threads = Number(path)
                    if (key === "cores") root.cores = Number(path)
                }
            }
        }
    }

    // blockLoading: reload() reads right away (small files in /proc and /sys).
    component Source: FileView {
        blockLoading: true
        printErrors: false
        function read(): string {
            if (!path) return ""
            reload()
            return text()
        }
    }

    Source { id: statFile; path: "/proc/stat" }
    Source { id: memFile; path: "/proc/meminfo" }
    Source { id: netFile; path: "/proc/net/dev" }
    Source { id: loadFile; path: "/proc/loadavg" }
    Source { id: uptimeFile; path: "/proc/uptime" }
    Source { id: cpuTempFile; path: root.cpuTempPath }
    Source { id: gpuTempFile; path: root.gpuTempPath }
    Source { id: gpuBusyFile; path: root.gpuBusyPath }
    Source { id: vramFile; path: root.vramPath }

    property var lastCpu: null
    property var lastNet: null
    property real lastNetTime: 0

    Timer {
        interval: root.interval
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.sample()
    }

    function sample(): void {
        // CPU: /proc/stat gives cumulative times; usage comes from the difference.
        const cpuLine = statFile.read().split("\n")[0].trim().split(/\s+/).slice(1, 9).map(Number)
        if (cpuLine.length === 8) {
            const idle = cpuLine[3] + cpuLine[4]
            const total = cpuLine.reduce((a, b) => a + b, 0)
            if (lastCpu && total > lastCpu.total) {
                cpu = 1 - (idle - lastCpu.idle) / (total - lastCpu.total)
                cpuHistory = push(cpuHistory, cpu)
            }
            lastCpu = { idle: idle, total: total }
        }

        // Memory (kB in /proc/meminfo).
        const mi = {}
        for (const line of memFile.read().split("\n")) {
            const m = line.match(/^(\w+):\s+(\d+)/)
            if (m) mi[m[1]] = Number(m[2]) * 1024
        }
        if (mi.MemTotal) {
            memTotal = mi.MemTotal
            memUsed = mi.MemTotal - mi.MemAvailable
            swapTotal = mi.SwapTotal || 0
            swapUsed = (mi.SwapTotal || 0) - (mi.SwapFree || 0)
            memCache = (mi.Cached || 0) + (mi.Buffers || 0) + (mi.SReclaimable || 0)
            mem = memUsed / memTotal
            memHistory = push(memHistory, mem)
        }

        // GPU.
        if (gpuBusyPath) {
            gpu = Number(gpuBusyFile.read()) / 100
            gpuHistory = push(gpuHistory, gpu)
        }
        if (vramPath) vramUsed = Number(vramFile.read())
        if (cpuTempPath) cpuTemp = Number(cpuTempFile.read()) / 1000
        if (gpuTempPath) gpuTemp = Number(gpuTempFile.read()) / 1000

        // Network: total bytes of every interface except lo.
        let rx = 0, tx = 0
        for (const line of netFile.read().split("\n").slice(2)) {
            const [name, rest] = line.split(":")
            if (!rest || name.trim() === "lo") continue
            const f = rest.trim().split(/\s+/).map(Number)
            rx += f[0]
            tx += f[8]
        }
        const now = Date.now()
        if (lastNet) {
            const dt = (now - lastNetTime) / 1000
            rxRate = Math.max(0, (rx - lastNet.rx) / dt)
            txRate = Math.max(0, (tx - lastNet.tx) / dt)
            // Log scale up to ~100 MB/s: that way a little traffic is visible.
            const scale = b => Math.min(1, Math.log10(1 + b) / 8)
            rxHistory = push(rxHistory, scale(rxRate))
            txHistory = push(txHistory, scale(txRate))
        }
        lastNet = { rx: rx, tx: tx }
        lastNetTime = now

        load = loadFile.read().split(" ").slice(0, 3).join(" / ")
        uptime = Number(uptimeFile.read().split(" ")[0]) || 0
    }
}
