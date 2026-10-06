import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// Spore's video wallpaper player: a separate, short-lived process. The shell
// (shell/wallpaper/VideoPlayer.qml) starts it with SPORE_VIDEO=<path>; it
// draws the video on the Bottom layer of each monitor (above the wallpaper,
// below the windows), plays it once and exits. That way the shell never
// loads QtMultimedia and the decoder's ~330 MB are freed when it ends
// (inside the shell they stayed held even after unloading the Video).
//
// Messages to the shell (through the log): "SPORE_VIDEO:showing" once
// there's a frame on screen, and "SPORE_VIDEO:failed <error>" if it couldn't
// play.
ShellRoot {
    id: root

    readonly property string source: Quickshell.env("SPORE_VIDEO") || ""
    property bool announced: false

    function showing(): void {
        if (announced) return
        announced = true
        console.info("SPORE_VIDEO:showing")
    }

    Component.onCompleted: if (!source) {
        console.warn("SPORE_VIDEO:failed no video (SPORE_VIDEO is empty)")
        Qt.quit()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            required property var modelData
            screen: modelData
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            // No input: clicks pass through (there's nothing to touch here).
            mask: Region {}

            WlrLayershell.layer: WlrLayer.Bottom
            WlrLayershell.namespace: "spore-video"

            Video {
                id: video
                anchors.fill: parent
                // Encoded like preview.qml's: a name with "%41" in it was read
                // as "A" (Could not open file).
                source: root.source ? "file://" + encodeURI(root.source).replace(/[?#]/g, c => c === "?" ? "%3F" : "%23") : ""
                fillMode: VideoOutput.PreserveAspectCrop
                loops: 1
                muted: true
                // Only with a frame: no black before the first frame or after the last one
                // (the last frame stays underneath as a still image).
                visible: playbackState === MediaPlayer.PlayingState && position > 0
                onVisibleChanged: if (visible) root.showing()

                property bool started: false
                onPlaying: started = true
                // Finished: the process exits (and with it all its memory).
                onStopped: if (started) Qt.quit()
                onErrorOccurred: (error, errorString) => {
                    console.warn("SPORE_VIDEO:failed " + errorString)
                    Qt.quit()
                }
                Component.onCompleted: if (root.source) play()
            }
        }
    }
}
