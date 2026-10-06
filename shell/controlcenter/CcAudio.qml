import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../common"

// Control Center → Audio (design v2): output and input (a list to pick the
// device, mute and volume) and the volume of each application that's
// playing.
ColumnLayout {
    id: root

    required property Theme theme

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property string subtitle: sink && sink.audio
        ? nameOf(sink) + " · " + (sink.audio.muted ? "Muted" : Math.round(sink.audio.volume * 100) + "%")
        : "No output"

    spacing: 12

    // "Hardware" audio nodes (no streams) and the streams of apps playing.
    readonly property var nodes: Pipewire.nodes.values
    readonly property var sinks: nodes.filter(n => n.audio && n.isSink && !n.isStream)
    readonly property var sources: nodes.filter(n => n.audio && !n.isSink && !n.isStream)
    // By type and not by properties["media.class"]: a node's properties are
    // empty until a PwObjectTracker binds it, and the tracker below binds
    // exactly these (the list was always empty).
    readonly property var appStreams: nodes.filter(n => n.type === PwNodeType.AudioOutStream)

    // Without a tracker, a node's audio.volume doesn't update.
    PwObjectTracker {
        objects: [Pipewire.defaultAudioSink, Pipewire.defaultAudioSource].concat(root.appStreams)
    }

    function nameOf(node: var): string {
        if (!node) return ""
        return node.nickname || node.description || node.name
    }

    // Connection type, for each device's second line.
    function kindOf(node: var): string {
        const n = (node.name || "").toLowerCase()
        if (n.includes("bluez")) return "Bluetooth"
        if (n.includes("hdmi")) return "HDMI"
        if (n.includes("usb")) return "USB"
        if (n.includes("analog")) return "Analog"
        return ""
    }

    // Output or input: the list to pick the device, mute and volume. With no
    // devices, a notice.
    component DeviceCard: CcCard {
        id: card
        required property string title
        required property var node
        required property var choices
        required property bool isOutput

        theme: root.theme
        Layout.fillWidth: true
        Layout.preferredWidth: 1
        Layout.fillHeight: true

        readonly property bool ready: node !== null && node.audio !== null
        readonly property bool isMuted: ready && node.audio.muted

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            CcSection {
                theme: root.theme
                text: card.title
            }

            // No devices.
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: card.choices.length === 0
                radius: 10
                color: root.theme.insetBg

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 6
                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        name: card.isOutput ? "volume-x" : "mic-off"
                        size: 20
                        stroke: 1.4
                        color: root.theme.muted2
                    }
                    UiText {
                        theme: root.theme
                        Layout.alignment: Qt.AlignHCenter
                        text: card.isOutput ? "No output device" : "No input device"
                    }
                    UiText {
                        theme: root.theme
                        Layout.alignment: Qt.AlignHCenter
                        text: card.isOutput ? "Connect speakers or headphones" : "Connect a mic or a headset"
                        color: root.theme.muted
                        font.pixelSize: 12
                    }
                }
            }

            // List with radio buttons.
            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                visible: card.choices.length > 0
                contentHeight: deviceList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: deviceList
                    width: parent.width
                    spacing: 2

                    Repeater {
                        model: card.choices

                        Rectangle {
                            id: deviceRow
                            required property var modelData
                            readonly property bool selected: modelData === card.node

                            width: deviceList.width
                            height: 36
                            radius: 9
                            color: deviceArea.containsMouse ? root.theme.alpha(root.theme.accent, 0.1) : "transparent"

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 10
                                anchors.rightMargin: 10
                                spacing: 10

                                Rectangle {
                                    implicitWidth: 14
                                    implicitHeight: 14
                                    radius: 7
                                    color: "transparent"
                                    border.width: deviceRow.selected ? 4 : 1.5
                                    border.color: deviceRow.selected ? root.theme.accent : root.theme.alpha(root.theme.ink2, 0.35)
                                }
                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: root.nameOf(deviceRow.modelData)
                                }
                                UiText {
                                    theme: root.theme
                                    text: root.kindOf(deviceRow.modelData)
                                    color: root.theme.muted
                                    font.pixelSize: 11
                                }
                            }

                            MouseArea {
                                id: deviceArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (card.isOutput) Pipewire.preferredDefaultAudioSink = deviceRow.modelData
                                    else Pipewire.preferredDefaultAudioSource = deviceRow.modelData
                                }
                            }
                        }
                    }
                }
            }

            RowLayout {
                visible: card.choices.length > 0
                spacing: 12

                CcButton {
                    theme: root.theme
                    size: 32
                    icon: card.isOutput ? (card.isMuted ? "volume-x" : "volume-2") : (card.isMuted ? "mic-off" : "mic")
                    iconSize: 15
                    enabled: card.ready
                    onClicked: card.node.audio.muted = !card.node.audio.muted
                }
                CcSlider {
                    theme: root.theme
                    Layout.fillWidth: true
                    value: card.ready ? card.node.audio.volume : 0
                    dimmed: card.isMuted
                    onMoved: (v) => {
                        if (card.ready) card.node.audio.volume = v
                    }
                }
                MonoText {
                    theme: root.theme
                    Layout.preferredWidth: 48
                    horizontalAlignment: Text.AlignRight
                    text: !card.ready ? "" : card.isMuted ? "Muted" : Math.round(card.node.audio.volume * 100) + "%"
                    font.pixelSize: 13
                }
            }
        }
    }

    RowLayout {
        Layout.fillWidth: true
        // Nested layouts stretch on their own: without this they swallowed the
        // applications card.
        Layout.fillHeight: false
        Layout.preferredHeight: 230
        spacing: 12

        DeviceCard {
            title: "Output"
            node: Pipewire.defaultAudioSink
            choices: root.sinks
            isOutput: true
        }

        DeviceCard {
            title: "Input"
            node: Pipewire.defaultAudioSource
            choices: root.sources
            isOutput: false
        }
    }

    // --- Applications ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            CcSection {
                theme: root.theme
                text: "Applications"
            }

            UiText {
                theme: root.theme
                visible: root.appStreams.length === 0
                text: "No application is playing audio"
                color: root.theme.muted
                font.pixelSize: 12
            }

            Flickable {
                Layout.fillWidth: true
                Layout.fillHeight: true
                contentHeight: appList.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Column {
                    id: appList
                    width: parent.width
                    spacing: 10

                    Repeater {
                        model: root.appStreams

                        RowLayout {
                            id: appRow
                            required property var modelData
                            readonly property string appName: modelData.properties["application.name"] || root.nameOf(modelData)
                            readonly property bool ready: modelData.audio !== null

                            width: appList.width
                            spacing: 12

                            // The app's initial, in a fixed color per name.
                            Rectangle {
                                implicitWidth: 32
                                implicitHeight: 32
                                radius: 9
                                color: {
                                    const ansi = root.theme.current.ansi
                                    let h = 0
                                    for (const ch of appRow.appName) h = (h * 31 + ch.charCodeAt(0)) >>> 0
                                    return ansi[1 + h % 6]
                                }
                                UiText {
                                    theme: root.theme
                                    anchors.centerIn: parent
                                    text: appRow.appName.charAt(0).toUpperCase()
                                    color: root.theme.onColor
                                    font.weight: Font.DemiBold
                                }
                            }

                            ColumnLayout {
                                Layout.preferredWidth: 180
                                spacing: 1
                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: appRow.appName
                                }
                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    visible: text !== ""
                                    text: appRow.modelData.properties["media.name"] || ""
                                    color: root.theme.muted
                                    font.pixelSize: 11
                                }
                            }

                            CcSlider {
                                theme: root.theme
                                Layout.fillWidth: true
                                value: appRow.ready ? appRow.modelData.audio.volume : 0
                                dimmed: appRow.ready && appRow.modelData.audio.muted
                                onMoved: (v) => {
                                    if (appRow.ready) appRow.modelData.audio.volume = v
                                }
                            }

                            MonoText {
                                theme: root.theme
                                Layout.preferredWidth: 48
                                horizontalAlignment: Text.AlignRight
                                text: appRow.ready ? Math.round(appRow.modelData.audio.volume * 100) + "%" : ""
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }
        }
    }
}
