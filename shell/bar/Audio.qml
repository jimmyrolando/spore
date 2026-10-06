import QtQuick
import Quickshell.Services.Pipewire

// Volume of the default audio output (PipeWire), with the percentage.
// Click: its Control Center tab; wheel: 5% steps.
BarButton {
    id: root

    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property bool ready: sink !== null && sink.audio !== null
    readonly property real volume: ready ? sink.audio.volume : 0
    readonly property bool muted: ready ? sink.audio.muted : false

    visible: sink !== null
    // Lucide: muted, at 0, low and high.
    icon: muted ? "volume-x" : volume === 0 ? "volume" : volume < 0.5 ? "volume-1" : "volume-2"
    label: Math.round(volume * 100) + "%"
    dim: muted
    tooltipRows: ready ? [
        { label: "Volume", value: muted ? "Muted" : Math.round(volume * 100) + "%" },
        { label: "Device", value: sink.nickname || sink.description || sink.name }
    ] : []

    onWheel: (delta) => {
        if (ready)
            sink.audio.volume = Math.max(0, Math.min(1, volume + (delta > 0 ? 0.05 : -0.05)))
    }

    // Without a tracker, PipeWire doesn't send the node's volume/mute changes
    // and the `audio` properties stay frozen.
    PwObjectTracker {
        objects: [root.sink]
    }
}
