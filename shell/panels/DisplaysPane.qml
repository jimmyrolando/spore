import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"

// Settings > Displays: each monitor's resolution, refresh rate, scale and
// rotation, and turning it off. It goes through Compositor.configureDisplay,
// so it works with whichever compositor is running.
//
// A change of mode, scale or rotation can leave a black screen, so after one
// the pane asks to keep it and goes back by itself when nobody answers (also
// if Settings is closed meanwhile). What's kept is remembered by
// DisplayMemory, which puts it back when the shell starts or the monitor is
// plugged in (the compositor itself forgets it when it restarts).
Flickable {
    id: root

    required property Theme theme
    required property Compositor compositor
    property DisplayMemory memory: null

    // How long a change waits to be kept.
    readonly property int confirmSeconds: 15

    readonly property var displays: compositor ? compositor.displays : []
    readonly property int onCount: displays.filter(d => d.on).length

    // The change waiting for an answer: { name, previous: the display as it
    // was, seconds: left }, or null.
    property var pending: null

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

    // --- Changing ---

    function apply(d: var, change: var): void {
        // Only the first change of a series is the one to go back to.
        if (!pending || pending.name !== d.name) {
            revert()
            pending = { name: d.name, previous: d, seconds: confirmSeconds }
            countdown.restart()
        } else {
            pending = { name: d.name, previous: pending.previous, seconds: confirmSeconds }
        }
        compositor.configureDisplay(d.name, change)
    }

    function keep(): void {
        const name = pending ? pending.name : ""
        countdown.stop()
        pending = null
        if (!memory || name === "") return
        // The list may not have caught up with the change yet.
        compositor.refreshOutputs()
        remember.name = name
        remember.restart()
    }

    Timer {
        id: remember
        property string name: ""
        interval: 600
        onTriggered: if (root.memory) root.memory.remember(name)
    }

    function revert(): void {
        if (!pending) return
        const p = pending.previous
        countdown.stop()
        pending = null
        if (!p.on) compositor.configureDisplay(p.name, { on: false })
        else compositor.configureDisplay(p.name, { on: true, mode: p.modes[p.mode], scale: p.scale, transform: p.transform })
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        onTriggered: {
            if (!root.pending) return stop()
            if (root.pending.seconds <= 1) return root.revert()
            root.pending = { name: root.pending.name, previous: root.pending.previous, seconds: root.pending.seconds - 1 }
        }
    }

    Component.onDestruction: revert()

    // --- Building blocks ---

    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    // A choice among several, one active.
    component Chip: Rectangle {
        id: chip
        property string label: ""
        // The chosen one: it doesn't react to clicks.
        property bool active: false
        // Looks like the chosen one but is a button (Keep).
        property bool primary: false
        property bool enabled: true
        signal clicked()

        implicitWidth: chipLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 7
        opacity: enabled ? 1 : 0.4
        color: active || primary ? root.theme.accent : chipArea.containsMouse && enabled ? root.buttonHover : root.button

        Label {
            id: chipLabel
            anchors.centerIn: parent
            text: chip.label
            color: chip.active || chip.primary ? root.theme.textOnAccent : root.theme.text
            font.pixelSize: 12
            font.weight: chip.active || chip.primary ? Font.Medium : Font.Normal
        }

        MouseArea {
            id: chipArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: chip.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (chip.enabled && !chip.active) chip.clicked()
        }
    }

    // A label on the left and its choices on the right.
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
            Layout.preferredWidth: 150
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

    function refreshText(r: real): string {
        return String(Math.round(r * 100) / 100) + " Hz"
    }

    // The resolutions of a display (largest first), each once.
    function resolutions(d: var): var {
        const seen = {}
        const list = []
        for (const m of d.modes) {
            const key = m.width + "x" + m.height
            if (seen[key]) continue
            seen[key] = true
            list.push({ width: m.width, height: m.height })
        }
        return list.sort((a, b) => b.width * b.height - a.width * a.height || b.width - a.width)
    }

    // The refresh rates available at the current resolution, each once.
    function refreshRates(d: var): var {
        if (d.mode < 0) return []
        const cur = d.modes[d.mode]
        const seen = {}
        const list = []
        for (const m of d.modes) {
            if (m.width !== cur.width || m.height !== cur.height) continue
            const key = refreshText(m.refresh)
            if (seen[key]) continue
            seen[key] = true
            list.push(m)
        }
        return list.sort((a, b) => b.refresh - a.refresh)
    }

    // The mode of another resolution that keeps the refresh rate as close as
    // it can.
    function modeFor(d: var, res: var): var {
        const cur = d.mode >= 0 ? d.modes[d.mode].refresh : 60
        const same = d.modes.filter(m => m.width === res.width && m.height === res.height)
        return same.sort((a, b) => Math.abs(a.refresh - cur) - Math.abs(b.refresh - cur))[0]
    }

    readonly property var scales: [1, 1.25, 1.5, 1.75, 2]
    readonly property var rotations: [
        { value: "normal", label: "None" }, { value: "90", label: "90°" },
        { value: "180", label: "180°" }, { value: "270", label: "270°" }
    ]

    ColumnLayout {
        id: column
        x: 28
        y: 16
        width: root.width - 56
        spacing: 24

        // The change to keep or undo.
        Rectangle {
            visible: root.pending !== null
            Layout.fillWidth: true
            implicitHeight: pendingRow.implicitHeight + 24
            radius: 10
            color: root.groupBg
            border.width: 1
            border.color: root.theme.accent

            RowLayout {
                id: pendingRow
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                Label {
                    Layout.fillWidth: true
                    text: root.pending ? "Keep this change on " + root.pending.name + "? It goes back in "
                        + root.pending.seconds + " s." : ""
                    wrapMode: Text.WordWrap
                }
                Chip { label: "Revert"; onClicked: root.revert() }
                Chip { label: "Keep"; primary: true; onClicked: root.keep() }
            }
        }

        Label {
            visible: root.displays.length === 0
            Layout.fillWidth: true
            text: "No monitors reported by the compositor."
            color: root.muted
        }

        Repeater {
            model: root.displays

            ColumnLayout {
                id: card
                required property var modelData
                readonly property var d: modelData
                readonly property bool remembered: root.memory !== null && root.memory.saved[d.id] !== undefined

                Layout.fillWidth: true
                spacing: 8

                RowLayout {
                    Layout.fillWidth: true
                    Label {
                        Layout.fillWidth: true
                        text: card.d.name + " · " + card.d.label
                        color: root.theme.accent
                        font.pixelSize: 11
                        font.bold: true
                        font.capitalization: Font.AllUppercase
                        font.letterSpacing: 1
                        elide: Text.ElideRight
                    }
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
                            title: "Enabled"
                            hint: card.d.on && root.onCount < 2 ? "The only one that's on" : ""
                            Chip {
                                label: "On"
                                active: card.d.on
                                onClicked: root.apply(card.d, { on: true })
                            }
                            Chip {
                                label: "Off"
                                active: !card.d.on
                                enabled: !card.d.on || root.onCount > 1
                                onClicked: root.apply(card.d, { on: false })
                            }
                        }

                        Rectangle { visible: card.d.on; Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            visible: card.d.on
                            title: "Resolution"
                            Repeater {
                                model: card.d.on ? root.resolutions(card.d) : []
                                Chip {
                                    required property var modelData
                                    label: modelData.width + " × " + modelData.height
                                    active: card.d.mode >= 0 && card.d.modes[card.d.mode].width === modelData.width
                                        && card.d.modes[card.d.mode].height === modelData.height
                                    onClicked: root.apply(card.d, { mode: root.modeFor(card.d, modelData) })
                                }
                            }
                        }

                        Rectangle { visible: card.d.on; Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            visible: card.d.on
                            title: "Refresh rate"
                            Repeater {
                                model: card.d.on ? root.refreshRates(card.d) : []
                                Chip {
                                    required property var modelData
                                    label: root.refreshText(modelData.refresh)
                                    active: card.d.mode >= 0 && card.d.modes[card.d.mode].refresh === modelData.refresh
                                    onClicked: root.apply(card.d, { mode: modelData })
                                }
                            }
                        }

                        Rectangle { visible: card.d.on; Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            visible: card.d.on
                            title: "Scale"
                            Repeater {
                                model: card.d.on ? root.scales : []
                                Chip {
                                    required property var modelData
                                    label: Math.round(modelData * 100) + "%"
                                    active: Math.abs(card.d.scale - modelData) < 0.01
                                    onClicked: root.apply(card.d, { scale: modelData })
                                }
                            }
                        }

                        Rectangle { visible: card.d.on; Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            visible: card.d.on
                            title: "Rotation"
                            Repeater {
                                model: card.d.on ? root.rotations : []
                                Chip {
                                    required property var modelData
                                    label: modelData.label
                                    active: card.d.transform === modelData.value
                                    onClicked: root.apply(card.d, { transform: modelData.value })
                                }
                            }
                        }

                        Rectangle { visible: card.remembered; Layout.fillWidth: true; height: 1; color: root.subtle }

                        Option {
                            visible: card.remembered
                            title: "Remembered"
                            hint: "Put back when Spore starts or this monitor is plugged in"
                            Chip {
                                label: "Forget"
                                onClicked: root.memory.forget(card.d.id)
                            }
                        }
                    }
                }
            }
        }

        Label {
            Layout.fillWidth: true
            text: "What you keep is remembered and put back when Spore starts, over what the compositor's configuration says. Forget it to go back to that."
            color: root.muted
            font.pixelSize: 12
            wrapMode: Text.WordWrap
        }
    }
}
