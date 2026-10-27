import QtQuick
import Quickshell
import Quickshell.Io
import "../common/session.js" as Session

// spored (spored/ in the repo): Spore's services, the parts Quickshell can't
// do on its own, such as org.freedesktop.FileManager1 (a browser's "Show in
// folder" opens Spore Files). Running for the whole session, with the
// session's environment (what it starts, Files, sets up its own), and
// started again if it ends. Not in a nested test session, which shares the
// real one's bus: it would take the name and open Files there. Without it
// (install.sh with no Go), nothing else changes.
Scope {
    id: root

    property bool enabled: true
    readonly property string program: Quickshell.env("SPORE_SPORED") || ""

    // Each restart waits longer, up to a minute: a spored that can't start
    // doesn't spin.
    property int failures: 0

    // Not straight away: whether the session is nested is known once the
    // compositor's backend is up, and a test shell mustn't take the name
    // on the real bus in the meantime.
    Timer {
        running: true
        interval: 2000
        onTriggered: if (root.enabled && root.program) daemon.running = true
    }
    onEnabledChanged: if (!enabled) daemon.running = false

    Process {
        id: daemon
        // setpriv: it goes when the shell does, even if the shell is killed.
        // spore-files is beside it (the package's bin, or install.sh's).
        command: Session.command(["setpriv", "--pdeathsig", "TERM", root.program,
            "-files", root.program.slice(0, root.program.lastIndexOf("/") + 1) + "spore-files"])
        stderr: SplitParser {
            onRead: (line) => console.info(line)
        }
        onStarted: startedAt.restart()
        onExited: (exitCode) => {
            if (!root.enabled) return
            root.failures++
            restart.interval = Math.min(60000, 2000 * Math.pow(2, root.failures - 1))
            restart.restart()
        }
    }

    // A run of a minute or more counts as working: the next failure starts
    // the waits over.
    Timer {
        id: startedAt
        interval: 60000
        onTriggered: root.failures = 0
    }

    Timer {
        id: restart
        onTriggered: if (root.enabled && root.program) daemon.running = true
    }
}
