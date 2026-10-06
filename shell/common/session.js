// Starting apps (the launcher, a drive's folder, a file's app, a terminal)
// with the session's environment instead of Spore's. Spore's wrappers
// (nix/bin/spore, nix/bin/spore-files) and Quickshell's put their own
// programs first in PATH and their Qt's plugins and QML in QT_PLUGIN_PATH
// and NIXPKGS_QT6_QML_IMPORT_PATH, and whatever Spore started inherited
// them: a terminal opened from it ran Spore's ls, find or curl instead of
// the user's and had programs the session doesn't (ffmpeg), and a Qt app
// built with another Qt was handed this one's plugins. The wrappers keep the
// session's own values in SPORE_SESSION, a line each: "name=value", or
// "-name" for one it didn't have.

// app PROGRAM ARGS…: runs PROGRAM in place of the shell, without Spore's own
// variables (Files' QT_WAYLAND_DISABLE_WINDOWDECORATION among them) and with
// the session's values back. PROGRAM is looked for in Spore's PATH (gio is
// there, and maybe not in the session's).
var appScript = `
    app() {
        program=$(command -v "$1") || return 127
        shift
        unset SPORE_QUICKSHELL SPORE_PCI_IDS SPORE_FILES_OPEN QS_APP_ID QT_WAYLAND_DISABLE_WINDOWDECORATION
        set -f
        IFS='
'
        for line in \${SPORE_SESSION-}; do
            case $line in
                -*) unset "\${line#-}" ;;
                *) export "$line" ;;
            esac
        done
        unset SPORE_SESSION
        exec "$program" "$@"
    }
`

// The command line that starts `argv` (a program and its arguments) as an
// app.
function command(argv) {
    return ["sh", "-c", appScript + 'app "$@"', "_"].concat(argv)
}
