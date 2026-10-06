import QtQuick
import Quickshell
import Quickshell.Io

// Plays a video wallpaper in a separate process (video/shell.qml): starts it,
// reads its messages, and the process exits on its own when done. The shell
// never loads QtMultimedia, and the decoder's memory (~330 MB with a 4K
// video) goes back to the system when the process exits. One for all
// monitors (the process opens one surface per monitor).
Scope {
    id: root

    // The video has a frame on screen (Wallpaper.qml waits for this).
    property bool showing: false
    // It couldn't play, or it exited without showing anything.
    signal failed()
    // Finished (the process exited).
    signal finished()

    // Requested while another one plays: the current one is closed and this one
    // is started.
    property string queued: ""

    function play(path: string): void {
        if (!path) return
        if (proc.running) {
            queued = path
            proc.signal(15)
            return
        }
        start(path)
    }

    // Stops whatever is playing (e.g. an image was chosen): the process exits and
    // the background shows through.
    function stop(): void {
        queued = ""
        if (proc.running) proc.signal(15)
    }

    function start(path: string): void {
        showing = false
        proc.video = path
        proc.running = true
    }

    function handle(line: string): void {
        if (line.includes("SPORE_VIDEO:showing")) {
            showing = true
        } else if (line.includes("SPORE_VIDEO:failed")) {
            console.warn("Video wallpaper: " + line.slice(line.indexOf("SPORE_VIDEO:failed") + 19))
        }
    }

    Process {
        id: proc
        property string video: ""
        // The package's Quickshell (exported by the wrapper) or the one in PATH, and
        // the video/ folder next to shell/.
        command: [Quickshell.env("SPORE_QUICKSHELL") || "quickshell", "-p", Quickshell.shellDir + "/../video"]
        environment: ({ SPORE_VIDEO: video })
        stdout: SplitParser {
            onRead: (line) => root.handle(line)
        }
        stderr: SplitParser {
            onRead: (line) => root.handle(line)
        }
        onExited: {
            const shown = root.showing
            root.showing = false
            if (root.queued) {
                const next = root.queued
                root.queued = ""
                root.start(next)
                return
            }
            if (!shown) root.failed()
            root.finished()
        }
    }
}
