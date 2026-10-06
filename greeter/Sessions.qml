import QtQuick
import Quickshell
import Quickshell.Io

// Reads the .desktop files of the installed sessions (Niri, Hyprland, etc.)
// for the session picker. On NixOS they aren't in /run/current-system/sw:
// the module (nix/nixos.nix) passes the sessionData.desktops folders in
// SPORE_SESSIONS_DIRS (separated by ":"); without it, the usual ones.
Item {
    id: root

    property var sessions: []   // [{ name: "Niri", exec: "niri-session" }, ...]

    readonly property string dirs: Quickshell.env("SPORE_SESSIONS_DIRS")
        || "/run/current-system/sw/share/wayland-sessions:/usr/share/wayland-sessions"

    function refresh() {
        proc.running = true
    }

    Process {
        id: proc
        command: ["sh", "-c", `
            IFS=:
            for d in $1; do
                for f in "$d"/*.desktop; do
                    [ -f "$f" ] || continue
                    grep -q '^NoDisplay=true' "$f" && continue
                    name=$(grep '^Name=' "$f" | head -n1 | cut -d= -f2-)
                    exec=$(grep '^Exec=' "$f" | head -n1 | cut -d= -f2-)
                    printf '%s\\t%s\\n' "$name" "$exec"
                done
            done`, "_", root.dirs]
        stdout: StdioCollector {
            onStreamFinished: {
                const seen = new Set()
                root.sessions = text.trim().split("\n")
                    .filter(l => l.length > 0)
                    .map(line => {
                        const [name, exec] = line.split("\t")
                        return { name: name, exec: exec }
                    })
                    // The same session in two folders: only once.
                    .filter(s => !seen.has(s.name) && seen.add(s.name))
            }
        }
    }

    Component.onCompleted: refresh()
}
