import Quickshell
import Quickshell.Io

ShellRoot {
    id: root

    // What each user's shell publishes (see publishDir in shell/shell.qml):
    // /var/lib/spore/<user>/{wallpaper.jpg, theme-mode, palette, colors.json},
    // readable by the greeter group. The NixOS module (services.spore) creates
    // the folders.
    readonly property string baseDir: Quickshell.env("SPORE_GREETER_DIR") || "/var/lib/spore"
    // The last user who logged in: Greeter.qml writes it when launching the
    // session, in a folder of the greeter's (.greeter, only it writes there).
    readonly property string lastUserFile: baseDir + "/.greeter/last-user"
    // The last session chosen (the .desktop's name, e.g. "Niri").
    readonly property string lastSessionFile: baseDir + "/.greeter/last-session"
    property string lastSession: ""
    property string hostName: ""

    // User whose theme is shown: the last one who logged in, and whoever is
    // typed in the user field as soon as it's confirmed (see Greeter.qml).
    property string themeUser: ""
    readonly property string userDir: themeUser ? baseDir + "/" + themeUser : ""

    readonly property string defaultWallpaper: Quickshell.shellPath("../assets/wallpapers/spore-dome.jpg")
    // The user's; if it doesn't exist or doesn't load, Greeter.qml falls back
    // to the factory one. (A Process used to check whether it existed: it ran
    // before the path was updated and the factory one always won.)
    readonly property string wallpaperPath: userDir ? userDir + "/wallpaper.jpg" : defaultWallpaper

    Theme {
        id: sessionTheme
    }

    FileView {
        path: root.lastUserFile
        onLoaded: root.themeUser = text().trim()
    }

    FileView {
        path: root.lastSessionFile
        onLoaded: root.lastSession = text().trim()
    }

    Process {
        running: true
        command: ["sh", "-c", "cat /etc/hostname 2>/dev/null || uname -n"]
        stdout: StdioCollector {
            onStreamFinished: root.hostName = text.trim()
        }
    }

    // Each FileView re-reads only when themeUser changes (the path changes).
    // If the user hasn't published anything yet, the factory values stay.
    FileView {
        path: root.userDir ? root.userDir + "/theme-mode" : ""
        onLoaded: {
            const m = text().trim()
            sessionTheme.mode = m === "light" ? "light" : "dark"
        }
        onLoadFailed: sessionTheme.mode = "dark"
    }

    FileView {
        path: root.userDir ? root.userDir + "/palette" : ""
        onLoaded: {
            const p = text().trim()
            sessionTheme.palette = sessionTheme.paletteNames.includes(p) ? p : "spore"
        }
        onLoadFailed: sessionTheme.palette = "spore"
    }

    // The user's interface and numbers fonts (Settings → Appearance → Fonts);
    // without the file, the factory ones.
    FileView {
        path: root.userDir ? root.userDir + "/fonts.json" : ""
        onLoaded: {
            try {
                const f = JSON.parse(text())
                if (f.interface) sessionTheme.uiFont = f.interface
                if (f.monospace) sessionTheme.fontFamily = f.monospace
            } catch (e) {
                console.warn("Invalid fonts.json:", e)
            }
        }
        onLoadFailed: {
            sessionTheme.uiFont = "Noto Sans"
            sessionTheme.fontFamily = "JetBrainsMono Nerd Font Mono"
        }
    }

    // Colors of the "wallpaper" palette (matugen); without it, falls back to
    // catppuccin.
    FileView {
        path: root.userDir ? root.userDir + "/colors.json" : ""
        onLoaded: {
            try {
                sessionTheme.matugen = JSON.parse(text()).colors
            } catch (e) {
                console.warn("Invalid colors.json:", e)
            }
        }
        onLoadFailed: sessionTheme.matugen = null
    }

    // A single window: cage shows one at a time, full screen (on the last
    // connected monitor; see cage -m).
    Greeter {
        implicitWidth: Quickshell.screens[0]?.width ?? 1920
        implicitHeight: Quickshell.screens[0]?.height ?? 1080
        wallpaperPath: root.wallpaperPath
        defaultWallpaper: root.defaultWallpaper
        theme: sessionTheme
        lastUser: root.themeUser
        lastUserFile: root.lastUserFile
        lastSession: root.lastSession
        lastSessionFile: root.lastSessionFile
        hostName: root.hostName
        // Only a name a user can have: the theme is read from a folder named
        // after it, and a typed "../x" would have the greeter read whatever it
        // can there.
        onUserChosen: (user) => {
            if (/^[A-Za-z0-9_][A-Za-z0-9._-]*\$?$/.test(user)) root.themeUser = user
        }
    }
}
