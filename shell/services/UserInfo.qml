import QtQuick
import Quickshell
import Quickshell.Io

// Who you are, for Home's header (CcHome.qml): full name (GECOS),
// user@host and the photo. Read once when the shell starts, not when the
// Control Center opens: otherwise the page appeared without a name and the
// centered row shifted when the data arrived.
Scope {
    id: root

    property string fullName: ""
    property string userHost: ""

    // User photo: ~/.face (the standard greeters and apps read); if there
    // isn't one, the account's (AccountsService). setAvatar() copies a new one
    // to ~/.face.
    property string avatarPath: ""
    // Goes up when the photo changes: the Image re-reads it.
    property int avatarVersion: 0

    function setAvatar(path: string): void {
        avatarCopy.src = path
        avatarCopy.running = true
    }

    Process {
        running: true
        command: ["sh", "-c", "getent passwd \"$USER\" | cut -d: -f5 | cut -d, -f1; echo \"$USER@$(cat /etc/hostname 2>/dev/null || uname -n)\""]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n")
                root.fullName = lines[0] || ""
                root.userHost = lines[1] || ""
            }
        }
    }

    Process {
        running: true
        command: ["sh", "-c", 'for f in "$HOME/.face" "/var/lib/AccountsService/icons/$USER"; do [ -r "$f" ] && { echo "$f"; break; }; done']
        stdout: StdioCollector {
            onStreamFinished: root.avatarPath = text.trim()
        }
    }

    Process {
        id: avatarCopy
        property string src: ""
        command: ["install", "-m", "644", src, Quickshell.env("HOME") + "/.face"]
        onExited: (code) => {
            if (code !== 0) {
                console.warn("Could not set the profile picture")
                return
            }
            root.avatarPath = Quickshell.env("HOME") + "/.face"
            root.avatarVersion++
        }
    }
}
