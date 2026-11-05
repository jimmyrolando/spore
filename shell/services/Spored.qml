import QtQuick
import Quickshell
import Quickshell.Io
import "../common/session.js" as Session

// spored (spored/ in the repo): Spore's services, the parts Quickshell can't
// do on its own: org.freedesktop.FileManager1 (a browser's "Show in folder"
// opens Spore Files), the lock before the system sleeps (Idle.qml) and the
// drives' events (DrivesService.qml). Running for the whole session, with
// the session's environment (what it starts, Files, sets up its own), and
// started again if it ends.
//
// In a nested test session it runs with -nested: only the drives. The
// session bus and logind are the real session's: it would take the name
// and open Files there, and hold the real sleep.
//
// It talks in JSON lines (the protocol is at the top of spored/service.go).
// Its hello says what's working (`services`); for what isn't, or without
// spored (install.sh with no Go), or with another protocol (dev mode: this
// QML from the checkout, spored from the package), Idle and DrivesService
// keep their scripts.
Scope {
    id: root

    property bool enabled: true
    property bool nested: false
    readonly property string program: Quickshell.env("SPORE_SPORED") || ""

    readonly property int protocol: 1
    // What the hello offered ([] until then, and when it isn't running).
    property var services: []
    readonly property bool logind: services.includes("logind")
    readonly property bool drives: services.includes("drives")

    signal sleepComing()
    signal lockAsked()
    signal drivesEvent()

    // The lock is up: the system can sleep.
    function locked(): void {
        if (logind) daemon.write('{"op":"locked"}\n')
    }

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
            "-files", root.program.slice(0, root.program.lastIndexOf("/") + 1) + "spore-files"]
            .concat(root.nested ? ["-nested"] : []))
        stdinEnabled: true
        stdout: SplitParser {
            onRead: (line) => root.heard(line)
        }
        stderr: SplitParser {
            onRead: (line) => console.info(line)
        }
        onStarted: startedAt.restart()
        onExited: (exitCode) => {
            root.services = []
            if (!root.enabled) return
            root.failures++
            restart.interval = Math.min(60000, 2000 * Math.pow(2, root.failures - 1))
            restart.restart()
        }
    }

    function heard(line: string): void {
        let message
        try {
            message = JSON.parse(line)
        } catch (e) {
            return
        }
        if (message.hello !== undefined) {
            if (message.protocol === protocol) {
                services = message.services || []
                console.info("spored:", services.join(", ") || "nothing")
            } else {
                // It stays: FileManager1 doesn't need the shell.
                console.warn("spored speaks protocol " + message.protocol + ", the shell " + protocol + ": using the scripts")
            }
            return
        }
        if (message.event === "sleep") sleepComing()
        else if (message.event === "lock") lockAsked()
        else if (message.event === "drives") drivesEvent()
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
