import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Pipewire
import "../common"

// Volume row (design v2, in Home and Media): mute, slider, value ("Muted"
// when muted) and the output device, which leads to the Audio page.
CcCard {
    id: root

    signal deviceRequested()

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property bool muted: ready && sink.audio.muted

    implicitHeight: 56

    // Without a tracker, PipeWire doesn't send volume/mute changes.
    PwObjectTracker {
        objects: [root.sink]
    }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        CcButton {
            theme: root.theme
            size: 32
            icon: root.muted ? "volume-x" : "volume-2"
            iconSize: 15
            enabled: root.ready
            onClicked: root.sink.audio.muted = !root.sink.audio.muted
        }

        CcSlider {
            theme: root.theme
            Layout.fillWidth: true
            value: root.ready ? root.sink.audio.volume : 0
            dimmed: root.muted
            onMoved: (v) => {
                if (root.ready) root.sink.audio.volume = v
            }
        }

        MonoText {
            theme: root.theme
            Layout.preferredWidth: 48
            horizontalAlignment: Text.AlignRight
            text: !root.ready ? "" : root.muted ? "Muted" : Math.round(root.sink.audio.volume * 100) + "%"
            font.pixelSize: 13
        }

        CcButton {
            theme: root.theme
            visible: root.sink !== null
            mono: true
            label: root.sink ? (root.sink.nickname || root.sink.description || root.sink.name) + " ›" : ""
            maxLabelWidth: 150
            onClicked: root.deviceRequested()
        }
    }
}
