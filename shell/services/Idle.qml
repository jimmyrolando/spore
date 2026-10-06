import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../lock"

// Idle actions: lock, turn off the monitors and suspend. The times
// (seconds, 0 = off) come from the "idle" section of settings.json (see
// Settings.qml), and apply when it's saved. And, whatever puts the system to
// sleep, the screen locks first (see sleepWatch below).
//
// They all respect idle inhibitors (Firefox playing a video, etc.): while
// any is active, nothing locks or turns off.
//
// Each IdleMonitor sits inside a Variants with the time as its model: when
// the time changes (or Caffeine turns on) a new one is created instead of
// changing the `timeout` of the existing one. In Quickshell 0.3.1 an
// IdleMonitor whose timeout changes after creation never reports again; and
// that happened on every startup, when settings.json replaces the factory
// times: the machine didn't lock, turn off the screen or suspend.
Scope {
    id: root

    // To lock (after a timeout and before suspending).
    required property Lock lock
    required property Settings settings
    // To turn off the monitors.
    property Compositor compositor: null

    readonly property int lockAfter: settings.lockAfter
    readonly property int screenOffAfter: settings.screenOffAfter
    readonly property int suspendAfter: settings.suspendAfter
    // Caffeine (Control Center → Home): while it's on, nothing locks, the
    // monitors don't turn off and nothing suspends on idle.
    property bool inhibited: false

    // In a nested test niri (its screen is called "winit") there's never any
    // activity of its own: after suspendAfter seconds it would suspend the whole
    // machine. Nothing is done there.
    readonly property bool active: !(compositor && compositor.nested)
    Component.onCompleted: Qt.callLater(() => console.info("Idle:", active ? "enabled" : "disabled (nested compositor)"))
    onInhibitedChanged: console.info("Idle:", inhibited ? "caffeine on, nothing happens while idle" : "caffeine off")

    // [seconds] if that action runs, [] if not.
    function timeoutModel(seconds: int): var {
        return active && !inhibited && seconds > 0 ? [seconds] : []
    }

    Variants {
        model: root.timeoutModel(root.lockAfter)
        IdleMonitor {
            required property int modelData
            timeout: modelData
            respectInhibitors: true
            onIsIdleChanged: if (isIdle) {
                console.info("Idle: locking after", timeout + "s")
                root.lock.lock()
            }
        }
    }

    // niri turns the monitors back on by itself, with any key or mouse movement.
    Variants {
        model: root.timeoutModel(root.screenOffAfter)
        IdleMonitor {
            required property int modelData
            timeout: modelData
            respectInhibitors: true
            onIsIdleChanged: if (isIdle) {
                console.info("Idle: turning off monitors after", timeout + "s")
                if (root.compositor) root.compositor.powerOffMonitors()
            }
        }
    }

    // Lock first, even if lockAfter is 0: never wake up without a lock.
    Variants {
        model: root.timeoutModel(root.suspendAfter)
        Scope {
            required property int modelData

            IdleMonitor {
                id: suspendMonitor
                timeout: modelData
                respectInhibitors: true
                onIsIdleChanged: {
                    if (!isIdle) return
                    console.info("Idle: suspending after", timeout + "s")
                    root.lock.lock()
                    suspendDelay.restart()
                }
            }

            // Only for the log: the same time without respecting inhibitors. If this
            // one fires and the one above doesn't, an app (a browser with video or
            // audio, a video call) is inhibiting idle and nothing suspends. That way
            // `qs log` shows why the machine didn't sleep.
            IdleMonitor {
                timeout: modelData
                respectInhibitors: false
                onIsIdleChanged: if (isIdle) Qt.callLater(() => {
                    if (!suspendMonitor.isIdle)
                        console.info("Idle: not suspending, an app is inhibiting idle (video, audio or a call)")
                })
            }
        }
    }

    // One second for the lockscreen to get drawn before sleeping: otherwise the
    // desktop flashes for an instant on wake.
    Timer {
        id: suspendDelay
        interval: 1000
        onTriggered: Quickshell.execDetached(["systemctl", "suspend"])
    }

    // --- Before any sleep ---

    // The system can go to sleep without Spore asking: the lid, the power
    // key, `systemctl suspend`, another app. The screen locks first anyway,
    // and `loginctl lock-session` locks it too. The script follows logind's
    // signals and prints "sleep" or "lock". A delay inhibitor (`systemd-inhibit
    // --list` shows it as Spore) makes logind wait for the lock: after "sleep",
    // the script waits up to 2 s for "locked" on its input, lets go of the
    // inhibitor and takes it again on waking. Argument: this session's id
    // (XDG_SESSION_ID; without it, the user's graphical session).
    readonly property string sleepScript: `
        id=\${1:-$(loginctl show-user "$(id -un)" -p Display --value 2>/dev/null)}
        session=
        if [ -n "$id" ]; then
            session=$(gdbus call --system --dest org.freedesktop.login1 --object-path /org/freedesktop/login1 \\
                --method org.freedesktop.login1.Manager.GetSession "$id" 2>/dev/null | cut -d"'" -f2)
        fi
        exec 3<&0
        held=
        hold() {
            setpriv --pdeathsig TERM systemd-inhibit --what=sleep --mode=delay --who=Spore \\
                --why="Locks the screen before sleeping" sleep infinity &
            held=$!
        }
        hold
        setpriv --pdeathsig TERM gdbus monitor --system --dest org.freedesktop.login1 | while IFS= read -r line; do
            case $line in
            "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (true,)")
                echo sleep
                read -r -t 2 _ <&3
                if [ -n "$held" ]; then kill "$held"; held=; fi ;;
            "/org/freedesktop/login1: org.freedesktop.login1.Manager.PrepareForSleep (false,)")
                [ -n "$held" ] || hold ;;
            "$session: org.freedesktop.login1.Session.Lock ()")
                [ -n "$session" ] && echo lock ;;
            esac
        done`

    // setpriv: the script ends with the shell, and what it starts with it.
    // Not in a nested test niri (see `active`): logind and its sleep are the
    // real session's.
    Process {
        id: sleepWatch
        running: root.active
        stdinEnabled: true
        command: ["setpriv", "--pdeathsig", "TERM", "sh", "-c", root.sleepScript, "_", Quickshell.env("XDG_SESSION_ID") || ""]
        stdout: SplitParser {
            onRead: (line) => root.heard(line)
        }
        // If logind or the system bus restarts, the monitor ends: start it again.
        onExited: restartWatch.restart()
    }

    Timer {
        id: restartWatch
        interval: 3000
        onTriggered: if (root.active) sleepWatch.running = true
    }

    // "sleep" heard and the lock not up yet (for 2 s at most, like the script).
    property bool sleepPending: false

    function heard(line: string): void {
        if (line === "lock") {
            console.info("Idle: logind asked to lock")
            root.lock.lock()
        } else if (line === "sleep") {
            console.info("Idle: the system is going to sleep, locking first")
            sleepPending = true
            sleepTimeout.restart()
            root.lock.lock()
            answerWhenLocked()
        }
    }

    // The lock is up: the system can sleep now.
    function answerWhenLocked(): void {
        if (!sleepPending || !root.lock.secure) return
        sleepPending = false
        sleepTimeout.stop()
        sleepWatch.write("locked\n")
    }

    Connections {
        target: root.lock
        function onSecureChanged(): void {
            root.answerWhenLocked()
        }
    }

    Timer {
        id: sleepTimeout
        interval: 2000
        onTriggered: root.sleepPending = false
    }
}
