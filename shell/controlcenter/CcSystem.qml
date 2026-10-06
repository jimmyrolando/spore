import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import "../common"
import "../services"

// Control Center → System (design v2): graphs of the last minute (CPU,
// memory, GPU and network) and below, the system's data and the disks. The
// measurements come from SystemMonitor.qml, which always measures: the
// graphs already have the last minute when the page opens.
ColumnLayout {
    id: root

    required property Theme theme
    required property SystemMonitor monitor

    readonly property string subtitle: "up " + monitor.formatUptime() + " · load " + (monitor.load.split(" / ")[0] || "")

    spacing: 12

    function gib(bytes: real): string {
        return (bytes / 1073741824).toFixed(1)
    }

    function rate(bps: real): string {
        if (bps >= 1048576) return (bps / 1048576).toFixed(1) + " MB/s"
        if (bps >= 1024) return Math.round(bps / 1024) + " KB/s"
        return Math.round(bps) + " B/s"
    }

    // Green below 60°, orange 60-80°, red from 80°.
    function tempColor(t: real): color {
        return t >= 80 ? theme.danger : t >= 60 ? theme.warn : theme.ok
    }

    // The compositor (Compositor.qml): name and version.
    property Compositor compositor: null

    // Fixed data: read once.
    property var info: ({})
    property var disks: []

    Process {
        running: true
        command: ["sh", "-c", `
            echo "cpu $(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
            for d in /sys/class/drm/card*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                echo "gpu $(basename "$(readlink "$d/driver")")"
                break
            done
            echo "os $(. /etc/os-release; echo "$PRETTY_NAME")"
            echo "kernel $(uname -r)"
            df -B1 --output=source,target,used,size 2>/dev/null | awk 'NR > 1 && $1 ~ /^\\/dev\\// && !seen[$1]++ { t = $2; for (i = 3; i <= NF - 2; i++) t = t " " $i; printf "disk\\t%s\\t%s\\t%s\\n", t, $(NF - 1), $NF }'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {}
                const disks = []
                for (const line of text.trim().split("\n")) {
                    if (line.startsWith("disk\t")) {
                        // Tab-separated: the mount point can contain spaces.
                        const [, target, used, size] = line.split("\t")
                        disks.push({ target: target, used: Number(used), size: Number(size) })
                    } else {
                        const sp = line.indexOf(" ")
                        const value = line.slice(sp + 1).trim()
                        if (value) info[line.slice(0, sp)] = value
                    }
                }
                root.info = info
                root.disks = disks
            }
        }
    }

    // "Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz" -> "i7-10700";
    // "AMD Ryzen 7 5800X 8-Core Processor" -> "Ryzen 7 5800X".
    readonly property string cpuShort: (info.cpu || "")
        .replace(/\((R|TM)\)/g, "").replace(/ CPU @.*$/, "").replace(/ \d+-Core.*$/, "")
        .replace(/ Processor$/, "").replace(/^(Intel|AMD) /, "").replace(/^Core /, "").trim()

    // --- Graphs ---
    component GraphCard: CcCard {
        id: card
        required property string title
        property string sub: ""
        property string value: ""
        property real temp: -1
        property alias values: graph.values
        property alias values2: graph.values2

        theme: root.theme
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 112

        ColumnLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            anchors.topMargin: 14
            anchors.bottomMargin: 14
            spacing: 10

            RowLayout {
                spacing: 10

                CcSection {
                    theme: root.theme
                    Layout.alignment: Qt.AlignBaseline
                    text: card.title
                }
                MonoText {
                    theme: root.theme
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: card.sub
                    color: root.theme.muted
                }
                MonoText {
                    theme: root.theme
                    Layout.alignment: Qt.AlignBaseline
                    visible: card.value !== ""
                    text: card.value
                    font.pixelSize: 20
                    font.weight: Font.Medium
                }
                Row {
                    Layout.alignment: Qt.AlignVCenter
                    visible: card.temp >= 0
                    spacing: 5
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 7; height: 7; radius: 3.5
                        color: root.tempColor(card.temp)
                    }
                    MonoText {
                        theme: root.theme
                        text: Math.round(card.temp) + "°"
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 8
                color: root.theme.insetBg
                clip: true

                CcGraph {
                    id: graph
                    anchors.fill: parent
                    samples: root.monitor.samples
                    color: root.theme.accent
                    color2: root.theme.ok
                }
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        columns: 2
        rowSpacing: 12
        columnSpacing: 12

        GraphCard {
            title: "CPU"
            sub: [root.cpuShort, root.monitor.threads ? root.monitor.threads + " threads" : ""].filter(s => s).join(" · ")
            value: Math.round(Math.max(0, root.monitor.cpu) * 100) + "%"
            temp: root.monitor.cpuTemp
            values: root.monitor.cpuHistory
        }

        GraphCard {
            title: "Memory"
            sub: root.gib(root.monitor.memUsed) + " / " + root.gib(root.monitor.memTotal) + " GiB"
            value: Math.round(Math.max(0, root.monitor.mem) * 100) + "%"
            values: root.monitor.memHistory
        }

        GraphCard {
            visible: root.monitor.gpu >= 0
            title: "GPU"
            sub: [root.info.gpu || "", root.monitor.vramUsed >= 0 ? root.gib(root.monitor.vramUsed) + " GiB VRAM" : ""].filter(s => s).join(" · ")
            value: Math.round(Math.max(0, root.monitor.gpu) * 100) + "%"
            temp: root.monitor.gpuTemp
            values: root.monitor.gpuHistory
        }

        // Download in the accent color, upload in green.
        GraphCard {
            title: "Network"
            sub: "↓ " + root.rate(root.monitor.rxRate) + "  ↑ " + root.rate(root.monitor.txRate)
            values: root.monitor.rxHistory
            values2: root.monitor.txHistory
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        CcCard {
            theme: root.theme
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 9

                CcSection {
                    theme: root.theme
                    text: "System"
                }

                Repeater {
                    model: [
                        ["CPU", root.info.cpu],
                        ["GPU", root.info.gpu],
                        ["OS", root.info.os],
                        ["Kernel", root.info.kernel],
                        ["WM", root.compositor && root.compositor.version ? root.compositor.name + " " + root.compositor.version : ""],
                        ["Load", root.monitor.load]
                    ].filter(r => r[1])

                    RowLayout {
                        required property var modelData
                        spacing: 12
                        UiText {
                            theme: root.theme
                            Layout.preferredWidth: 52
                            text: modelData[0]
                            color: root.theme.muted
                            font.pixelSize: 12
                        }
                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: modelData[1]
                        }
                    }
                }

                Item { Layout.fillHeight: true }
            }
        }

        CcCard {
            theme: root.theme
            Layout.fillWidth: true
            Layout.preferredWidth: 1
            Layout.fillHeight: true

            ColumnLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                anchors.topMargin: 14
                anchors.bottomMargin: 14
                spacing: 9

                CcSection {
                    theme: root.theme
                    text: "Storage"
                }

                Flickable {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentHeight: diskList.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: diskList
                        width: parent.width
                        spacing: 9

                        Repeater {
                            model: root.disks

                            Column {
                                id: disk
                                required property var modelData
                                readonly property real pct: modelData.size > 0 ? modelData.used / modelData.size : 0
                                width: diskList.width
                                spacing: 4

                                RowLayout {
                                    width: parent.width
                                    spacing: 10
                                    MonoText {
                                        theme: root.theme
                                        Layout.fillWidth: true
                                        text: disk.modelData.target
                                    }
                                    MonoText {
                                        theme: root.theme
                                        text: root.gib(disk.modelData.used) + " / " + root.gib(disk.modelData.size) + " GiB · " + Math.round(disk.pct * 100) + "%"
                                        color: root.theme.muted
                                        elide: Text.ElideNone
                                    }
                                }

                                Rectangle {
                                    width: parent.width
                                    height: 5
                                    radius: 3
                                    color: root.theme.track
                                    Rectangle {
                                        width: parent.width * disk.pct
                                        height: parent.height
                                        radius: 3
                                        color: disk.pct >= 0.9 ? root.theme.danger : disk.pct >= 0.7 ? root.theme.warn : root.theme.accent
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
