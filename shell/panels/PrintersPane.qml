import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "../common/session.js" as Session

// Settings > Printers: the printers CUPS knows, which one is the default, their
// queues, and pausing, removing and printing a test page. It talks to CUPS with
// its own commands (lpstat, lpadmin, cupsenable, cancel, lp), so it works on any
// distro that has CUPS; adding a printer is left to CUPS' web page, which knows
// about drivers.
//
// CUPS has no event stream that's cheap to follow, so the queue is read every
// few seconds, and only while this pane is on screen.
Flickable {
    id: root

    required property Theme theme

    // [{ name, uri, state: "idle" | "printing" | "paused", reason, isDefault,
    //    jobs: [{ id, user, size, date }] }]
    property var printers: []
    // CUPS answered but isn't running (or there is no CUPS).
    property bool offline: false
    // The first read has come back (before it, "no printers" would be a guess).
    property bool loaded: false
    // The last action's error, "" if it went well.
    property string message: ""
    // The printer waiting for "Remove for good?".
    property string confirming: ""
    // The printer being added (its queue name), "" if none: it can take a minute
    // if the printer is in standby.
    property string adding: ""

    clip: true
    contentHeight: column.implicitHeight + 44
    boundsBehavior: Flickable.StopAtBounds

    // --- Colors (like SettingsWindow's, from the theme) ---
    function tint(alpha: real): color {
        return Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, alpha))
    }
    readonly property color groupBg: tint(0.03)
    readonly property color subtle: tint(0.08)
    readonly property color button: tint(0.08)
    readonly property color buttonHover: tint(0.14)
    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.55)

    // --- Reading CUPS ---

    function refresh(): void {
        if (!reader.running) reader.running = true
    }

    // Sections split by markers, in C so the words are the ones parsed below.
    Process {
        id: reader
        command: ["env", "LC_ALL=C", "sh", "-c",
            "lpstat -r; echo '##D'; lpstat -d; echo '##P'; lpstat -p; echo '##V'; lpstat -v; echo '##J'; lpstat -o"]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
    }

    onVisibleChanged: if (visible) refresh()

    Timer {
        interval: 3000
        repeat: true
        running: root.visible
        onTriggered: root.refresh()
    }

    function parse(text: string): void {
        const parts = { R: [], D: [], P: [], V: [], J: [] }
        let into = "R"
        for (const line of text.split("\n")) {
            const mark = /^##([DPVJ])$/.exec(line)
            if (mark) into = mark[1]
            else parts[into].push(line)
        }

        offline = !parts.R.some(l => l.startsWith("scheduler is running"))
        const def = (/destination: (\S+)/.exec(parts.D.join("\n")) || [])[1] || ""

        const uris = {}
        for (const l of parts.V) {
            const m = /^device for (\S+): (.*)$/.exec(l)
            if (m) uris[m[1]] = m[2]
        }

        const list = []
        for (const l of parts.P) {
            const m = /^printer (\S+) (.*)$/.exec(l)
            if (m) {
                const paused = m[2].includes("disabled since")
                list.push({
                    name: m[1], uri: uris[m[1]] || "", reason: "", isDefault: m[1] === def, jobs: [],
                    state: paused ? "paused" : m[2].startsWith("now printing") ? "printing" : "idle"
                })
            } else if (list.length > 0 && /^\s+\S/.test(l)) {
                // The line under a paused printer says why.
                list[list.length - 1].reason = l.trim()
            }
        }

        for (const l of parts.J) {
            const m = /^(\S+)-(\d+)\s+(\S+)\s+(\d+)\s+\w+ (.*)$/.exec(l)
            const p = m ? list.find(x => x.name === m[1]) : null
            if (p) p.jobs.push({ id: m[1] + "-" + m[2], number: m[2], user: m[3], size: +m[4], date: m[5] })
        }
        printers = list
        loaded = true
    }

    // --- Acting on CUPS ---

    // One action at a time; the buttons wait for it.
    readonly property bool busy: action.running

    function run(argv: var): void {
        if (busy) return
        message = ""
        confirming = ""
        action.command = argv
        action.running = true
    }

    Process {
        id: action
        stderr: StdioCollector {
            id: actionErrors
        }
        onExited: (code) => {
            root.adding = ""
            root.message = code === 0 ? "" : actionErrors.text.trim() || "CUPS refused (exit " + code + ")"
            root.refresh()
        }
    }

    function setDefault(name: string): void { run(["lpadmin", "-d", name]) }
    function pause(name: string): void { run(["cupsdisable", name]) }
    function resume(name: string): void { run(["cupsenable", name]) }
    function remove(name: string): void { run(["lpadmin", "-x", name]) }
    function cancelJob(id: string): void { run(["cancel", id]) }
    function cancelAll(name: string): void { run(["cancel", "-a", name]) }
    function testPage(name: string): void {
        run(["sh", "-c", "printf 'Spore test page\\n' | lp -d \"$1\"", "sh", name])
    }

    // --- Finding printers to add ---

    // The printers on the network that say so (mDNS): [{ title, uri, name }].
    // Driverless ones only: they're added as IPP Everywhere.
    property var found: []
    // A search has finished at least once.
    property bool searched: false

    function search(): void {
        if (finder.running) return
        found = []
        finder.running = true
    }

    // The name a queue gets: letters, digits, _ and -.
    function queueName(title: string): string {
        return title.trim().replace(/\s+/g, "_").replace(/[^A-Za-z0-9_-]/g, "")
    }

    function parseFound(text: string): void {
        const list = []
        for (const line of text.split("\n")) {
            const cut = line.lastIndexOf(" | ")
            if (cut < 0) continue
            const title = line.slice(0, cut).trim()
            const uri = line.slice(cut + 3).trim()
            // The same printer can answer as ipp and as ipps: the first one.
            if (title === "" || uri === "" || list.some(x => x.title === title)) continue
            list.push({ title: title, uri: uri, name: queueName(title) })
        }
        found = list
        searched = true
    }

    Process {
        id: finder
        // The browse lasts 4 seconds.
        command: ["ippfind", "-T", "4", "-x", "echo", "{service_name} | {service_uri}", ";"]
        stdout: StdioCollector {
            onStreamFinished: root.parseFound(text)
        }
    }

    function addPrinter(f: var): void {
        if (busy) return
        adding = f.name
        // A printer in standby can miss the first question CUPS asks it ("No
        // IPP attributes"), so it's tried three times, a few seconds apart.
        run(["sh", "-c",
            "for i in 1 2 3; do lpadmin -p \"$1\" -E -v \"$2\" -m everywhere && exit 0; sleep 3; done; exit 1",
            "sh", f.name, f.uri])
    }

    function openCups(): void {
        Quickshell.execDetached(Session.command(["xdg-open", "http://localhost:631/admin"]))
    }

    function kb(bytes: real): string {
        return bytes < 1024 ? bytes + " B" : Math.round(bytes / 1024) + " KB"
    }

    function whereText(uri: string): string {
        if (uri === "") return ""
        if (uri.startsWith("usb:")) return "USB"
        if (uri.startsWith("implicitclass:")) return "Shared by another entry"
        const host = /^[a-z]+:\/\/(?:[^@\/]*@)?([^:\/]+)/.exec(uri)
        return host ? "Network · " + host[1] : uri
    }

    // --- Building blocks ---

    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    component Chip: Rectangle {
        id: chip
        property string label: ""
        property bool enabled: true
        // Looks like the chosen one (the action to confirm).
        property bool primary: false
        signal clicked()

        implicitWidth: chipLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 7
        opacity: enabled ? 1 : 0.4
        color: primary ? root.theme.accent : chipArea.containsMouse && enabled ? root.buttonHover : root.button

        Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            color: chip.primary ? root.theme.textOnAccent : root.theme.text
            font.pixelSize: 12
            font.weight: chip.primary ? Font.Medium : Font.Normal
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (chip.enabled) chip.clicked()
        }
    }

    // A label on the left and its content on the right.
    component Option: RowLayout {
        property string title: ""
        property string hint: ""
        default property alias choices: flow.data

        Layout.fillWidth: true
        Layout.leftMargin: 16
        Layout.rightMargin: 16
        Layout.topMargin: 12
        Layout.bottomMargin: 12
        spacing: 24

        ColumnLayout {
            Layout.minimumWidth: 150
            Layout.maximumWidth: 150
            Layout.alignment: Qt.AlignTop
            spacing: 2
            Label { text: title; font.pixelSize: 14 }
            Label {
                visible: hint !== ""
                Layout.fillWidth: true
                text: hint
                color: root.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
        }

        Flow {
            id: flow
            Layout.fillWidth: true
            spacing: 6
        }
    }

    ColumnLayout {
        id: column
        x: 28
        y: 16
        width: root.width - 56
        spacing: 24

        // What went wrong with the last action.
        Rectangle {
            visible: root.message !== ""
            Layout.fillWidth: true
            implicitHeight: messageText.implicitHeight + 24
            radius: 10
            color: root.groupBg
            border.width: 1
            border.color: root.theme.accent

            Label {
                id: messageText
                anchors.fill: parent
                anchors.margins: 12
                text: root.message
                wrapMode: Text.WordWrap
            }
        }

        Label {
            visible: root.offline
            Layout.fillWidth: true
            text: "CUPS isn't running. Printing needs its service (cups.service)."
            color: root.muted
            wrapMode: Text.WordWrap
        }

        Label {
            visible: root.loaded && !root.offline && root.printers.length === 0
            Layout.fillWidth: true
            text: "No printers added yet."
            color: root.muted
        }

        Repeater {
            model: root.printers

            ColumnLayout {
                id: card
                required property var modelData
                readonly property var p: modelData

                Layout.fillWidth: true
                spacing: 8

                Label {
                    Layout.fillWidth: true
                    text: card.p.name + (root.whereText(card.p.uri) !== "" ? " · " + root.whereText(card.p.uri) : "")
                    color: root.theme.accent
                    font.pixelSize: 11
                    font.bold: true
                    font.capitalization: Font.AllUppercase
                    font.letterSpacing: 1
                    elide: Text.ElideRight
                }

                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: rows.implicitHeight
                    radius: 10
                    color: root.groupBg
                    border.width: 1
                    border.color: root.subtle

                    ColumnLayout {
                        id: rows
                        anchors.left: parent.left
                        anchors.right: parent.right
                        spacing: 0

                        Option {
                            title: "Status"
                            hint: card.p.reason !== "Paused" ? card.p.reason : ""
                            Label {
                                height: 30
                                verticalAlignment: Text.AlignVCenter
                                rightPadding: 12
                                text: card.p.state === "paused" ? "Paused" : card.p.state === "printing" ? "Printing" : "Ready"
                                color: card.p.state === "paused" ? root.muted : root.theme.text
                            }
                            Chip {
                                label: card.p.state === "paused" ? "Resume" : "Pause"
                                enabled: !root.busy
                                onClicked: card.p.state === "paused" ? root.resume(card.p.name) : root.pause(card.p.name)
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            title: "Default"
                            hint: "Where print goes when no printer is chosen"
                            Label {
                                visible: card.p.isDefault
                                height: 30
                                verticalAlignment: Text.AlignVCenter
                                text: "This is the default"
                            }
                            Chip {
                                visible: !card.p.isDefault
                                label: "Make default"
                                enabled: !root.busy
                                onClicked: root.setDefault(card.p.name)
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.subtle }

                        // The queue: one line per job.
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 16
                            Layout.rightMargin: 16
                            Layout.topMargin: 12
                            Layout.bottomMargin: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true
                                Label {
                                    Layout.fillWidth: true
                                    text: "Queue"
                                    font.pixelSize: 14
                                }
                                Label {
                                    visible: card.p.jobs.length === 0
                                    text: "Nothing waiting"
                                    color: root.muted
                                    font.pixelSize: 12
                                }
                                Chip {
                                    visible: card.p.jobs.length > 1
                                    label: "Cancel all"
                                    enabled: !root.busy
                                    onClicked: root.cancelAll(card.p.name)
                                }
                            }

                            Repeater {
                                model: card.p.jobs

                                RowLayout {
                                    id: job
                                    required property var modelData
                                    Layout.fillWidth: true
                                    spacing: 12

                                    Label {
                                        Layout.fillWidth: true
                                        text: "Job " + job.modelData.number + " · " + job.modelData.user
                                            + " · " + root.kb(job.modelData.size) + " · " + job.modelData.date
                                        color: root.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                    Chip {
                                        label: "Cancel"
                                        enabled: !root.busy
                                        onClicked: root.cancelJob(job.modelData.id)
                                    }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            title: "Printer"
                            Chip {
                                label: "Print a test page"
                                enabled: !root.busy && card.p.state !== "paused"
                                onClicked: root.testPage(card.p.name)
                            }
                            Chip {
                                visible: root.confirming !== card.p.name
                                label: "Remove"
                                enabled: !root.busy
                                onClicked: root.confirming = card.p.name
                            }
                            Label {
                                visible: root.confirming === card.p.name
                                height: 30
                                verticalAlignment: Text.AlignVCenter
                                rightPadding: 6
                                text: "Remove it for good?"
                            }
                            Chip {
                                visible: root.confirming === card.p.name
                                label: "Keep it"
                                onClicked: root.confirming = ""
                            }
                            Chip {
                                visible: root.confirming === card.p.name
                                label: "Remove"
                                primary: true
                                enabled: !root.busy
                                onClicked: root.remove(card.p.name)
                            }
                        }
                    }
                }
            }
        }

        // Adding: look on the network, then add one that was found.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8

            Label {
                Layout.fillWidth: true
                text: "Add a printer"
                color: root.theme.accent
                font.pixelSize: 11
                font.bold: true
                font.capitalization: Font.AllUppercase
                font.letterSpacing: 1
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: finding.implicitHeight
                radius: 10
                color: root.groupBg
                border.width: 1
                border.color: root.subtle

                ColumnLayout {
                    id: finding
                    anchors.left: parent.left
                    anchors.right: parent.right
                    spacing: 0

                    Option {
                        title: "On the network"
                        hint: "Printers that announce themselves, added without a driver"
                        Chip {
                            label: finder.running ? "Searching…" : root.searched ? "Search again" : "Search"
                            enabled: !finder.running && !root.busy
                            onClicked: root.search()
                        }
                        Label {
                            visible: root.searched && !finder.running && root.found.length === 0
                            height: 30
                            verticalAlignment: Text.AlignVCenter
                            leftPadding: 6
                            text: "Nothing found"
                            color: root.muted
                        }
                    }

                    Repeater {
                        model: root.found

                        ColumnLayout {
                            id: hit
                            required property var modelData
                            readonly property bool added: root.printers.some(p => p.name === modelData.name)
                            Layout.fillWidth: true
                            spacing: 0

                            Rectangle { Layout.fillWidth: true; height: 1; color: root.subtle }

                            RowLayout {
                                Layout.fillWidth: true
                                Layout.leftMargin: 16
                                Layout.rightMargin: 16
                                Layout.topMargin: 10
                                Layout.bottomMargin: 10
                                spacing: 12

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Label { text: hit.modelData.title; font.pixelSize: 14 }
                                    Label {
                                        Layout.fillWidth: true
                                        text: root.whereText(hit.modelData.uri)
                                        color: root.muted
                                        font.pixelSize: 12
                                        elide: Text.ElideRight
                                    }
                                }
                                Label {
                                    visible: hit.added
                                    text: "Already added"
                                    color: root.muted
                                    font.pixelSize: 12
                                }
                                Chip {
                                    visible: !hit.added
                                    label: root.adding === hit.modelData.name ? "Adding…" : "Add"
                                    primary: true
                                    enabled: !root.busy
                                    onClicked: root.addPrinter(hit.modelData)
                                }
                            }
                        }
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12

            Label {
                Layout.fillWidth: true
                text: "A printer that needs a driver is added on CUPS' own page, which knows about them."
                color: root.muted
                font.pixelSize: 12
                wrapMode: Text.WordWrap
            }
            Chip {
                label: "Open CUPS page"
                onClicked: root.openCups()
            }
        }
    }
}
