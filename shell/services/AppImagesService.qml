import QtQuick
import Quickshell
import Quickshell.Io
import "../common/appimages.js" as AppImages
import "../common/session.js" as Session

// The AppImages in a folder (~/Applications by default; the widget's
// options in Settings > Bar), for the bar widget and its panel
// (AppImagePanel.qml). Of each app only the newest version is listed (the
// naming is in common/appimages.js). Nothing runs on its own: the panel
// reads the folder and what's running when it opens, and again every few
// seconds while it stays open.
//
// An AppImage is a program from wherever it was downloaded: only the ones in
// this folder are listed, and one runs when it's clicked, never before.
Scope {
    id: root

    required property Settings settings

    // As written (with "~/") and expanded.
    readonly property string folderRaw: settings.widgetOption("appImages", "folder") || "~/Applications"
    readonly property string folder: settings.expandHome(folderRaw)
    // Empty: appimage-run if it's installed (NixOS needs it), else the file.
    readonly property string runner: String(settings.widgetOption("appImages", "runner") || "").trim()

    // [{ name, version, key, file, path, mtime, older }] (see appimages.js).
    property var apps: []
    property bool folderMissing: false
    // The folder has been read at least once.
    property bool loaded: false
    // The AppImages that are running: every one sets APPIMAGE to its own file
    // in its processes' environment (appimage-run too), which tells them
    // apart even when the process is something unpacked elsewhere.
    property var runningPaths: []

    function refresh(): void {
        if (!lister.running) lister.running = true
        if (!envReader.running) envReader.running = true
    }

    function isRunning(app: var): bool {
        return runningPaths.includes(app.path)
    }

    function run(app: var): void {
        const argv = runner !== "" ? runner.split(/\s+/).concat([app.path])
            : ["sh", "-c", 'if command -v appimage-run >/dev/null 2>&1; then exec appimage-run "$1"; fi; chmod +x "$1" && exec "$1"',
                "sh", app.path]
        // execDetached and not a Process: the app must not die if the shell
        // reloads. As an app (session.js): with the session's environment.
        Quickshell.execDetached(Session.command(argv))
        // It shows as running a moment later.
        later.restart()
    }

    function openFolder(): void {
        Quickshell.execDetached(Session.command(["gio", "open", folder]))
    }

    function createFolder(): void {
        Quickshell.execDetached(["mkdir", "-p", folder])
        later.restart()
    }

    Timer {
        id: later
        interval: 1500
        onTriggered: root.refresh()
    }

    onFolderChanged: if (loaded) refresh()

    Process {
        id: lister
        command: ["sh", "-c",
            'test -d "$1" || { echo "##missing"; exit 0; }; find -L "$1" -maxdepth 1 -type f -iname "*.appimage" -printf "%f\\t%T@\\n"',
            "sh", root.folder]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l !== "")
                root.folderMissing = lines[0] === "##missing"
                const entries = root.folderMissing ? [] : lines.map(l => {
                    const [file, mtime] = l.split("\t")
                    return { file: file, path: root.folder + "/" + file, mtime: Number(mtime) || 0 }
                })
                const list = AppImages.newest(entries)
                // The same list: don't reassign, so the views aren't rebuilt.
                if (JSON.stringify(list) !== JSON.stringify(root.apps)) root.apps = list
                root.loaded = true
            }
        }
    }

    // One grep over the processes' environments (the ones that aren't the
    // user's can't be read, and are skipped).
    Process {
        id: envReader
        command: ["sh", "-c", "grep -a -h -o -s 'APPIMAGE=[^[:cntrl:]]*' /proc/[0-9]*/environ | sort -u"]
        stdout: StdioCollector {
            onStreamFinished: {
                const paths = text.split("\n").filter(l => l.startsWith("APPIMAGE=")).map(l => l.slice(9))
                if (JSON.stringify(paths) !== JSON.stringify(root.runningPaths)) root.runningPaths = paths
            }
        }
    }
}
