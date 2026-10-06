import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// The quick view's player (Files, shell/files/QuickView.qml): a video or a
// song in a process of its own, like the video wallpaper's, so the decoder's
// memory (300+ MB with a 4K video, and QtMultimedia keeps it after unloading)
// goes away with it. Files starts it when the quick view shows a video or an
// audio file and ends it when it moves on or closes.
//
// It draws only the media, on the Overlay layer and exactly over the quick
// view's empty area (niri stacks the newest surface on top). It never takes
// the keyboard: that stays in the Files window. A click plays or pauses; the
// bar below seeks.
//
// Environment: SPORE_PREVIEW (the file), SPORE_PREVIEW_SCREEN (the monitor's
// name), SPORE_PREVIEW_RECT ("x,y,width,height" on that monitor, logical
// pixels), SPORE_PREVIEW_AUDIO ("1": a song, with no picture),
// SPORE_PREVIEW_COLORS ("text,accent,background") and SPORE_PREVIEW_FONT (the
// time's). It reports on its standard output: "SPORE_PREVIEW:playing" and
// "SPORE_PREVIEW:failed <error>".
ShellRoot {
    id: root

    readonly property string source: Quickshell.env("SPORE_PREVIEW") || ""
    readonly property bool audio: Quickshell.env("SPORE_PREVIEW_AUDIO") === "1"
    readonly property var rect: (Quickshell.env("SPORE_PREVIEW_RECT") || "0,0,640,360").split(",").map(Number)
    readonly property var colors: (Quickshell.env("SPORE_PREVIEW_COLORS") || "#ffffff,#89b4fa,#1e1e2e").split(",")
    readonly property color textColor: colors[0]
    readonly property color accent: colors[1]
    readonly property color background: colors[2]

    Component.onCompleted: if (!source) {
        console.warn("SPORE_PREVIEW:failed no file (SPORE_PREVIEW is empty)")
        Qt.quit()
    }

    function clock(ms: real): string {
        const s = Math.floor(ms / 1000)
        const pad = n => (n < 10 ? "0" : "") + n
        return s >= 3600 ? Math.floor(s / 3600) + ":" + pad(Math.floor(s / 60) % 60) + ":" + pad(s % 60)
            : Math.floor(s / 60) + ":" + pad(s % 60)
    }

    PanelWindow {
        screen: Quickshell.screens.find(s => s.name === Quickshell.env("SPORE_PREVIEW_SCREEN")) ?? Quickshell.screens[0]
        anchors { top: true; left: true }
        margins { left: root.rect[0]; top: root.rect[1] }
        implicitWidth: root.rect[2]
        implicitHeight: root.rect[3]
        exclusionMode: ExclusionMode.Ignore
        color: root.audio ? root.background : "black"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "spore-preview"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        MediaPlayer {
            id: player
            source: root.source ? "file://" + encodeURI(root.source).replace(/[?#]/g, c => c === "?" ? "%3F" : "%23") : ""
            videoOutput: output
            audioOutput: AudioOutput {}
            onPlayingChanged: if (playing) console.info("SPORE_PREVIEW:playing")
            onErrorOccurred: (error, errorString) => {
                console.warn("SPORE_PREVIEW:failed " + errorString)
                Qt.quit()
            }
            Component.onCompleted: if (root.source) play()
        }

        VideoOutput {
            id: output
            anchors.fill: parent
            visible: !root.audio
            fillMode: VideoOutput.PreserveAspectFit
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            onClicked: player.playing ? player.pause() : player.play()
        }

        // Play/pause, the position (click to seek) and the time: always for a
        // song; for a video, while the pointer is over it or it's paused.
        Rectangle {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            height: 44
            visible: root.audio || area.containsMouse || !player.playing
            color: root.audio ? "transparent" : Qt.rgba(0, 0, 0, 0.55)

            Row {
                anchors.fill: parent
                anchors.leftMargin: 14
                anchors.rightMargin: 14
                spacing: 12

                // Play or pause, drawn: ▶ or ❙❙.
                Item {
                    width: 20
                    height: parent.height

                    Canvas {
                        anchors.centerIn: parent
                        width: 14
                        height: 16
                        property bool playing: player.playing
                        onPlayingChanged: requestPaint()
                        onPaint: {
                            const ctx = getContext("2d")
                            ctx.reset()
                            ctx.fillStyle = root.audio ? root.textColor : "white"
                            if (playing) {
                                ctx.fillRect(1, 1, 4, 14)
                                ctx.fillRect(9, 1, 4, 14)
                            } else {
                                ctx.beginPath()
                                ctx.moveTo(2, 0)
                                ctx.lineTo(14, 8)
                                ctx.lineTo(2, 16)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: player.playing ? player.pause() : player.play()
                    }
                }

                Item {
                    id: track
                    width: parent.width - 20 - time.width - 24
                    height: parent.height

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: parent.width
                        height: 4
                        radius: 2
                        color: root.audio ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.2) : Qt.rgba(1, 1, 1, 0.3)

                        Rectangle {
                            width: player.duration > 0 ? parent.width * player.position / player.duration : 0
                            height: parent.height
                            radius: 2
                            color: root.accent
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: (mouse) => {
                            if (player.duration > 0) player.position = player.duration * mouse.x / width
                        }
                    }
                }

                Text {
                    id: time
                    anchors.verticalCenter: parent.verticalCenter
                    text: root.clock(player.position) + " / " + root.clock(player.duration)
                    color: root.audio ? root.textColor : "white"
                    font.family: Quickshell.env("SPORE_PREVIEW_FONT") || "monospace"
                    font.pixelSize: 12
                }
            }
        }
    }
}
