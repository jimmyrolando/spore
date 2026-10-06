import Quickshell
import Quickshell.Wayland
import Quickshell.Io
import QtQuick
import "../common"
import "../services"

// A real lockscreen at the Wayland protocol level (ext-session-lock-v1),
// not just a window on top. It lives in the same process as the bar to
// share state/services instead of being a third Quickshell process.
//
// It's activated from outside (e.g. a niri bind) via IPC:
//   qs ipc call lock lock
Scope {
    id: root

    property string wallpaperPath: ""
    property int wallpaperVersion: 0
    required property Theme theme
    required property Settings settings

    // Shared by all the lockscreen's screens (one per monitor), and by Settings
    // (it shows the time zone's city if there's no location).
    readonly property Weather weather: lockWeather

    Weather {
        id: lockWeather
        location: root.settings.lockWeather
        units: root.settings.lockUnits
    }

    // The user's first name (the GECOS field of /etc/passwd, e.g. "Ada
    // Lovelace" -> "Ada"; if it's empty, the login) and the hostname.
    property string userName: ""
    property string hostName: ""

    Process {
        running: true
        command: ["sh", "-c", "g=$(getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1); echo \"${g%% *}\"; cat /etc/hostname 2>/dev/null || uname -n"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n")
                root.userName = lines[0].trim() || Quickshell.env("USER")
                root.hostName = (lines[1] || "").trim()
            }
        }
    }

    LockContext {
        id: lockContext
        onUnlocked: sessionLock.locked = false
    }

    WlSessionLock {
        id: sessionLock
        locked: false

        WlSessionLockSurface {
            LockSurface {
                anchors.fill: parent
                context: lockContext
                wallpaperPath: root.wallpaperPath
                wallpaperVersion: root.wallpaperVersion
                theme: root.theme
                weather: lockWeather
                userName: root.userName
                hostName: root.hostName
            }
        }
    }

    // Locked: set by lock(), cleared when the lock is released. Not bound to
    // sessionLock.locked: WlSessionLock only notifies that when it's released,
    // so a binding never turned true, and shell.qml's "the video plays again
    // on unlock" never ran.
    property bool locked: false
    // The compositor confirmed the lock: nothing but the lockscreen shows.
    // Idle.qml waits for it before letting the system sleep.
    readonly property bool secure: sessionLock.secure

    // Also used by Idle.qml (locking on idle and before suspending).
    function lock(): void {
        if (!sessionLock.locked) lockContext.reset()
        sessionLock.locked = true
        locked = true
        Quickshell.watchFiles = !sessionLock.locked
    }

    // No hot reload while locked. In dev mode (devPath) a file saved under
    // shell/ reloads the shell, and Quickshell 0.3.1 doesn't carry a lock
    // across a reload: with `locked: false` it released it (the session
    // unlocked), and with the lock kept, niri ended the shell for locking an
    // output twice. lock() stops watching the files; here watching comes back
    // however the lock ends (WlSessionLock only notifies `locked` when it's
    // released). What's saved meanwhile loads with the next save.
    Connections {
        target: sessionLock
        function onLockStateChanged(): void {
            root.locked = sessionLock.locked
            Quickshell.watchFiles = !sessionLock.locked
        }
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            root.lock()
        }

        function isLocked(): bool {
            return sessionLock.locked
        }
    }
}
