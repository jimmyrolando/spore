import QtQuick
import Quickshell
import Quickshell.Io
import "fileutil.js" as Util

// Files' operations on files: copy, cut and paste, rename, new folder,
// compress and extract, and the Trash. files.qml creates one for every
// window (the clipboard is shared: copy in one, paste in another), and they
// run one after the other. The work is done by coreutils, gio and bsdtar in
// small scripts that get the paths as arguments, never pasted into the
// script.
//
// The rules, so nothing is ever lost:
// - Nothing is overwritten. A name that already exists keeps both (the new
//   one becomes "name (2)"), is skipped, or, if the user says Replace, the
//   old one goes to the Trash first.
// - A copy, a zip or an extracted archive is written under a hidden
//   temporary name in the destination and renamed when it's complete: one
//   that fails or is canceled never leaves a half file with the real name
//   (only its own temporary is removed).
// - Deleting is the Trash (gio trash), never rm.
//
// A window that asks for something passes itself as `origin`: questions,
// errors and results go to it.
QtObject {
    id: root

    // Cut or copied: { mode: "copy" | "move", paths: [...] }, or null.
    property var clipboard: null
    // The cut ones (the views dim them): path -> true.
    readonly property var cutPaths: {
        const out = {}
        if (clipboard && clipboard.mode === "move")
            for (const path of clipboard.paths) out[path] = true
        return out
    }

    // Working (a copy can outlive its window: Files doesn't end until it's done).
    readonly property bool busy: current !== null
    // What's being done, for the status lines: "Copying 3 items to “Work”".
    property string status: ""
    // 0..1 while a copy knows how much there is; -1 otherwise.
    property real progress: -1
    // A paste waiting for an answer: { origin, text, count }.
    property var question: null

    // Done: what it was ("copy" or "move", a paste or a drop; "rename",
    // "mkdir", "extract", "compress", "trash", "restore", "purge" or "empty")
    // and the names it left in `folder`, to select them.
    // For trash, the paths it took; restore, the paths things went back to;
    // purge, the names deleted.
    signal finished(var origin, string kind, string folder, var names)
    signal failed(var origin, string message)

    property var current: null
    property var queue: []

    function copy(paths: var): void {
        clipboard = paths.length ? { mode: "copy", paths: paths } : null
        share(paths)
    }

    function cut(paths: var): void {
        clipboard = paths.length ? { mode: "move", paths: paths } : null
        share(paths)
    }

    // Copied or cut, they go to the system's clipboard too, for other apps:
    // one image as the picture itself, as PNG (every app takes it: a chat, a
    // document), and anything else as the list of files (file managers,
    // Chromium-based apps). Ctrl+V in Files still pastes from `clipboard`.
    function share(paths: var): void {
        if (!paths.length) return
        const image = paths.length === 1 && Util.kindOf(baseName(paths[0]), false) === "image" && !/\.svg$/i.test(paths[0])
        Quickshell.execDetached(["sh", "-c", shareScript, "_", image ? paths[0] : ""].concat(paths.map(p => Util.fileUri(p))))
    }

    // Into `folder`: first it checks what's already there, and if anything is,
    // asks (question) before starting.
    function paste(origin: var, folder: string): void {
        if (!clipboard) return
        const mode = clipboard.mode
        // A cut goes once: after the paste, the clipboard is empty.
        if (transfer(origin, mode, clipboard.paths.slice(), folder, true) && mode === "move") clipboard = null
    }

    // Copies or moves (mode) `paths` into `folder`, the way a paste does: a
    // drag and drop goes straight here, leaving the clipboard alone.
    // fromClipboard: a cut whose question is canceled goes back to it.
    function transfer(origin: var, mode: string, paths: var, folder: string, fromClipboard: bool): bool {
        for (const path of paths) {
            if (folder === path || folder.startsWith(path + "/")) {
                failed(origin, "Can't " + (mode === "move" ? "move" : "copy") + " a folder into itself")
                return false
            }
        }
        run({ kind: "check", origin: origin, mode: mode, folder: folder, paths: paths, fromClipboard: fromClipboard })
        return true
    }

    // The answer to `question`: "replace", "keep", "skip" or "cancel".
    function answer(choice: string): void {
        const asked = question
        if (!asked) return
        question = null
        if (choice !== "cancel") run(Object.assign({}, asked.job, { kind: "transfer", policy: choice }))
        else if (asked.job.mode === "move" && asked.job.fromClipboard) clipboard = { mode: "move", paths: asked.job.paths }
    }

    // Each archive into the folder it's in (see extractScript).
    function extract(origin: var, paths: var): void {
        for (const path of paths) {
            const name = baseName(path)
            if (Util.extractable(name))
                run({ kind: "extract", origin: origin, path: path, folder: path.slice(0, path.lastIndexOf("/")) || "/",
                    base: Util.archiveBase(name) })
        }
    }

    // `names` (in `folder`) into one zip there, called `zip` (or "zip (2)"…).
    function compress(origin: var, folder: string, names: var, zip: string): void {
        if (names.length) run({ kind: "compress", origin: origin, folder: folder, names: names, zip: zip })
    }

    function rename(origin: var, path: string, name: string): void {
        run({ kind: "rename", origin: origin, path: path, name: name, folder: path.slice(0, path.lastIndexOf("/")) || "/" })
    }

    function newFolder(origin: var, folder: string): void {
        run({ kind: "mkdir", origin: origin, folder: folder })
    }

    function trash(origin: var, paths: var): void {
        if (paths.length) run({ kind: "trash", origin: origin, paths: paths })
    }

    // The Trash, the home one as the freedesktop spec has it: files/ with what
    // was deleted and info/ with where each came from. (Things deleted on
    // another disk go to that disk's own Trash, which isn't shown here.)
    readonly property string trashDir: (Quickshell.env("XDG_DATA_HOME") || Quickshell.env("HOME") + "/.local/share") + "/Trash"
    readonly property string trashFiles: trashDir + "/files"

    // It may not exist yet (nothing ever deleted): the Trash place needs it.
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", trashFiles, trashDir + "/info"])

    // Back where they came from: `names` are in the Trash's files/.
    function restore(origin: var, names: var): void {
        if (names.length) run({ kind: "restore", origin: origin, names: names, folder: trashFiles })
    }

    // Gone for good (asked first by the window).
    function purge(origin: var, names: var): void {
        if (names.length) run({ kind: "purge", origin: origin, names: names, folder: trashFiles })
    }

    function emptyTrash(origin: var): void {
        run({ kind: "empty", origin: origin, folder: trashFiles })
    }

    // Stops a copy or a move: what's done stays done, the item in progress is
    // undone (a copy's temporary is removed; a move within a disk is instant).
    function cancel(): void {
        if (worker.running) worker.signal(15)
    }

    function run(job: var): void {
        queue = queue.concat([job])
        if (!current) next()
    }

    function next(): void {
        if (queue.length === 0) {
            current = null
            status = ""
            progress = -1
            return
        }
        current = queue[0]
        queue = queue.slice(1)
        const job = current
        const count = job.paths ? job.paths.length : 1
        const items = count === 1 ? "“" + (job.paths ? baseName(job.paths[0]) : "") + "”" : count + " items"
        const where = "“" + baseName(job.folder || "") + "”"
        progress = -1
        if (job.kind === "check") {
            status = ""
            worker.start(["sh", "-c", checkScript, "_", job.folder].concat(job.paths))
        } else if (job.kind === "transfer") {
            status = (job.mode === "move" ? "Moving " : "Copying ") + items + " to " + where
            job.total = 0
            job.placed = []
            worker.start(["sh", "-c", freeScript + transferScript, "_", job.mode, job.folder, job.policy].concat(job.paths))
        } else if (job.kind === "rename") {
            status = ""
            worker.start(["sh", "-c", renameScript, "_", job.path, job.name])
        } else if (job.kind === "mkdir") {
            status = ""
            worker.start(["sh", "-c", mkdirScript, "_", job.folder])
        } else if (job.kind === "extract") {
            status = "Extracting “" + baseName(job.path) + "”"
            worker.start(["sh", "-c", freeScript + extractScript, "_", job.path, job.folder, job.base])
        } else if (job.kind === "compress") {
            status = "Compressing " + (job.names.length === 1 ? "“" + job.names[0] + "”" : job.names.length + " items")
                + " into “" + job.zip + "”"
            job.total = 0
            worker.start(["sh", "-c", freeScript + compressScript, "_", job.folder, job.zip].concat(job.names))
        } else if (job.kind === "trash") {
            status = "Moving " + items + " to the Trash"
            worker.start(["gio", "trash", "--"].concat(job.paths))
        } else if (job.kind === "restore") {
            status = "Restoring " + (job.names.length === 1 ? "“" + job.names[0] + "”" : job.names.length + " items")
            worker.start(["sh", "-c", freeScript + restoreScript, "_", trashDir].concat(job.names))
        } else if (job.kind === "purge") {
            status = "Deleting " + (job.names.length === 1 ? "“" + job.names[0] + "”" : job.names.length + " items") + " for good"
            worker.start(["sh", "-c", writableScript + purgeScript, "_", trashDir].concat(job.names))
        } else if (job.kind === "empty") {
            status = "Emptying the Trash"
            worker.start(["sh", "-c", writableScript + emptyScript, "_", trashDir])
        }
    }

    function baseName(path: string): string {
        return path === "/" ? "/" : path.slice(path.lastIndexOf("/") + 1)
    }

    // --- The scripts ---

    // free <path> <the item going there>: "name (2).ext", "name (3).ext"…, the
    // first that's free (folders keep their dots). Goes before the scripts
    // that use it.
    readonly property string freeScript: `
        free() {
            free_dir=$(dirname -- "$1")
            free_name=$(basename -- "$1")
            free_base=$free_name
            free_ext=
            if ! [ -d "$2" ]; then
                case $free_name in
                ?*.*) free_base=\${free_name%.*}; free_ext=.\${free_name##*.} ;;
                esac
            fi
            free_k=2
            while [ -e "$free_dir/$free_base ($free_k)$free_ext" ] || [ -L "$free_dir/$free_base ($free_k)$free_ext" ]; do
                free_k=$((free_k + 1))
            done
            printf '%s\\n' "$free_dir/$free_base ($free_k)$free_ext"
        }
`

    // Arguments: the destination, then the sources. Prints the names that
    // already exist there (another file, not the source itself). (The "x"
    // after basename keeps a name's trailing newlines, which $( ) drops.)
    readonly property string checkScript: `
        dest=$1
        shift
        for src in "$@"; do
            name=$(basename -- "$src"; echo x)
            target=$dest/\${name%??}
            if { [ -e "$target" ] || [ -L "$target" ]; } && ! [ "$src" -ef "$target" ]; then
                basename -- "$src"
            fi
        done`

    // Arguments: copy or move, the destination, what to do with a name that's
    // already there (replace, keep or skip), then the sources. Prints TOTAL
    // <bytes> (a copy), COPIED <bytes so far>, PLACED <the name it got> and,
    // if it stops, ERROR <why>. Pasting into its own folder, a copy keeps both
    // and a move does nothing. Like every mv here, it never replaces: if
    // another program takes the name after the check, it stops with an error
    // (--update=none-fail, an atomic rename) instead of overwriting that.
    readonly property string transferScript: `
        mode=$1
        dest=$2
        policy=$3
        shift 3
        pid=
        tmp=
        trap 'if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid"; fi; if [ -n "$tmp" ]; then rm -rf -- "\${tmp:?}"; fi; exit 130' TERM INT
        [ "$mode" = copy ] && echo "TOTAL $(du -scb -- "$@" 2>/dev/null | tail -n 1 | cut -f1)"
        copied=0
        for src in "$@"; do
            # (The "x" keeps a name's trailing newlines, which $( ) drops: "a" +
            # newline would otherwise land on "a".)
            name=$(basename -- "$src"; echo x)
            name=\${name%??}
            target=$dest/$name
            if [ -e "$target" ] || [ -L "$target" ]; then
                if [ "$src" -ef "$target" ]; then
                    [ "$mode" = move ] && continue
                    what=keep
                else
                    what=$policy
                fi
                case $what in
                skip) continue ;;
                replace)
                    # What's pasted is inside the one it replaces (a/b/b pasted
                    # into a): it would go to the Trash along with it.
                    case $src/ in "$target"/*) echo "ERROR Can't replace “$name” with something inside it"; exit 1 ;; esac
                    gio trash -- "$target" || { echo "ERROR Couldn't move the old “$name” to the Trash"; exit 1; } ;;
                *) target=$(free "$target" "$src") ;;
                esac
            fi
            if [ "$mode" = move ]; then
                mv -T --update=none-fail -- "$src" "$target" || { echo "ERROR Couldn't move “$name”"; exit 1; }
            else
                # Not named after the file: one of 235 bytes or more (80
                # Japanese characters) left no room for the rest in the 255 a
                # name can have.
                tmp=$dest/.spore-copy-$$
                cp -a -T -- "$src" "$tmp" &
                pid=$!
                # du's first line only: it prints the name too, and a name with
                # a newline in it made a second line that broke the count (and
                # the script, which left its temporary behind).
                while kill -0 "$pid" 2>/dev/null; do
                    sleep 0.4
                    now=$(du -sb -- "$tmp" 2>/dev/null | head -n 1 | cut -f1)
                    echo "COPIED $((copied + \${now:-0}))"
                done
                if ! wait "$pid"; then
                    pid=
                    rm -rf -- "\${tmp:?}"
                    echo "ERROR Couldn't copy “$name”"
                    exit 1
                fi
                pid=
                mv -T --update=none-fail -- "$tmp" "$target" || { rm -rf -- "\${tmp:?}"; echo "ERROR Couldn't copy “$name”"; exit 1; }
                tmp=
                now=$(du -sb -- "$target" 2>/dev/null | head -n 1 | cut -f1)
                copied=$((copied + \${now:-0}))
                echo "COPIED $copied"
            fi
            echo "PLACED $(basename -- "$target")"
        done`

    // Arguments: the file and its new name. Prints EXISTS if the name is taken.
    readonly property string renameScript: `
        target=$(dirname -- "$1")/$2
        if [ -e "$target" ] || [ -L "$target" ]; then
            echo EXISTS
            exit 1
        fi
        mv -T --update=none-fail -- "$1" "$target"`

    // Argument: where. Makes "New folder" (or "New folder 2"…) and prints its
    // name.
    readonly property string mkdirScript: `
        name="New folder"
        k=2
        while [ -e "$1/$name" ] || [ -L "$1/$name" ]; do
            name="New folder $k"
            k=$((k + 1))
        done
        mkdir -- "$1/$name" && printf '%s\\n' "$name"`

    // Arguments: one image to share as a picture ("" for none), then the URIs
    // of what's shared. The image goes as PNG (as it is, or converted by
    // ffmpeg); one that can't be converted, and anything else, goes as a
    // text/uri-list. wl-copy stays behind serving it, as any copy does.
    readonly property string shareScript: `
        image=$1
        shift
        if [ -n "$image" ] && [ -f "$image" ]; then
            case $image in
            *.[pP][nN][gG]) exec wl-copy --type image/png < "$image" ;;
            esac
            png=$(mktemp) || exit 1
            if ffmpeg -v error -i "$image" -frames:v 1 -c:v png -f image2pipe - > "$png" && [ -s "$png" ]; then
                wl-copy --type image/png < "$png"
                rm -f -- "$png"
                exit 0
            fi
            rm -f -- "$png"
        fi
        printf '%s\\r\\n' "$@" | wl-copy --type text/uri-list`

    // Arguments: the archive, where to (its folder), and the name without the
    // archive's extension. It's extracted into a hidden folder first (bsdtar
    // refuses paths with "..", and absolute ones stay inside); then one thing
    // inside (a folder, usually) comes out as it is, and several go in a
    // folder named after the archive: no "photos/photos". Prints TOTAL <the
    // archive's size>, READ <bytes bsdtar has read so far>, PLACED <the name
    // it got> and, if it stops, ERROR <why>.
    readonly property string extractScript: `
        archive=$1
        dest=$2
        base=$3
        # Not named after the archive, like a copy's (see transferScript).
        tmp=$dest/.spore-extract-$$
        log=
        pid=
        trap 'if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid"; fi; rm -rf -- "\${tmp:?}"; if [ -n "$log" ]; then rm -f -- "$log"; fi; exit 130' TERM INT
        failed() {
            rm -rf -- "\${tmp:?}"
            if [ -n "$log" ]; then rm -f -- "$log"; fi
            echo "ERROR Couldn't extract “$(basename -- "$archive")”$1"
            exit 1
        }
        log=$(mktemp) || exit 1
        mkdir -- "$tmp" || failed ""
        echo "TOTAL $(stat -c %s -- "$archive")"
        bsdtar -xf "$archive" -C "$tmp" 2> "$log" &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.4
            echo "READ $(awk '/^rchar:/ { print $2 }' "/proc/$pid/io" 2>/dev/null)"
        done
        if ! wait "$pid"; then
            pid=
            why=$(grep -v 'Error exit delayed' "$log" | tail -n 1 | sed -e 's/^bsdtar: //' -e 's/: Unknown error -1$//')
            failed "\${why:+: $why}"
        fi
        pid=
        rm -f -- "$log"
        log=
        if [ "$(find "$tmp" -mindepth 1 -maxdepth 1 | wc -l)" -eq 1 ]; then
            only=$(find "$tmp" -mindepth 1 -maxdepth 1)
            target=$dest/$(basename -- "$only")
            if [ -e "$target" ] || [ -L "$target" ]; then target=$(free "$target" "$only"); fi
            mv -T --update=none-fail -- "$only" "$target" || failed ""
            rmdir -- "$tmp"
        else
            target=$dest/$base
            if [ -e "$target" ] || [ -L "$target" ]; then target=$(free "$target" "$tmp"); fi
            mv -T --update=none-fail -- "$tmp" "$target" || failed ""
        fi
        printf 'PLACED %s\\n' "$(basename -- "$target")"`

    // Arguments: the folder, the zip's name, then the names in the folder that
    // go in it. Written as a hidden file and renamed when complete; a name
    // that's taken gets a number. Prints TOTAL <bytes to read>, READ <bytes
    // bsdtar has read so far>, PLACED <the name it got> and, if it stops,
    // ERROR <why>.
    readonly property string compressScript: `
        cd -- "$1" || exit 1
        name=$2
        shift 2
        # Each name as ./name: bsdtar reads one that starts with "@" (even
        # after --) as an archive whose entries go in instead, so "@x.tar"
        # zipped what x.tar holds. -s takes the ./ off again inside the zip.
        for n do
            set -- "$@" "./$n"
            shift
        done
        # Not named after the zip, like a copy's (see transferScript).
        tmp=.spore-compress-$$
        log=
        pid=
        trap 'if [ -n "$pid" ]; then kill "$pid" 2>/dev/null; wait "$pid"; fi; rm -f -- "$tmp"; if [ -n "$log" ]; then rm -f -- "$log"; fi; exit 130' TERM INT
        log=$(mktemp) || exit 1
        echo "TOTAL $(du -scb -- "$@" 2>/dev/null | tail -n 1 | cut -f1)"
        bsdtar --format zip -cf "$tmp" -s ',^\\./,,' -- "$@" 2> "$log" &
        pid=$!
        while kill -0 "$pid" 2>/dev/null; do
            sleep 0.4
            echo "READ $(awk '/^rchar:/ { print $2 }' "/proc/$pid/io" 2>/dev/null)"
        done
        if ! wait "$pid"; then
            pid=
            why=$(grep -v 'Error exit delayed' "$log" | tail -n 1 | sed -e 's/^bsdtar: //' -e 's/: Unknown error -1$//')
            rm -f -- "$tmp" "$log"
            echo "ERROR Couldn't compress\${why:+: $why}"
            exit 1
        fi
        pid=
        rm -f -- "$log"
        log=
        target=$name
        if [ -e "$target" ] || [ -L "$target" ]; then target=$(basename -- "$(free "./$name" "./$name")"); fi
        mv -T --update=none-fail -- "$tmp" "$target" || { rm -f -- "$tmp"; echo "ERROR Couldn't compress"; exit 1; }
        printf 'PLACED %s\\n' "$target"`

    // The three below get the Trash's folder, and only act if it's called
    // Trash: they delete for good, so they check it twice.

    // Arguments: the Trash, then names in its files/. Each goes back to the
    // path its info/<name>.trashinfo has (percent-encoded, like a URL): the
    // folder is made again if it's gone, and a name taken there gets a number.
    // Prints RESTORED <where it went> for each.
    readonly property string restoreScript: `
        trash=$1
        shift
        case $trash in */Trash) ;; *) exit 2 ;; esac
        for name in "$@"; do
            info=$trash/info/$name.trashinfo
            if ! [ -f "$info" ]; then
                echo "ERROR There's no record of where “$name” came from"
                exit 1
            fi
            encoded=$(sed -n 's/^Path=//p' "$info" | head -n 1)
            path=$(printf '%b' "$(printf '%s' "$encoded" | sed 's/%/\\\\x/g')")
            case $path in
            /*) ;;
            *) echo "ERROR There's no record of where “$name” came from"; exit 1 ;;
            esac
            folder=$(dirname -- "$path")
            mkdir -p -- "$folder" || { echo "ERROR Couldn't make “$folder” again"; exit 1; }
            target=$path
            if [ -e "$target" ] || [ -L "$target" ]; then target=$(free "$target" "$trash/files/$name"); fi
            mv -T --update=none-fail -- "$trash/files/$name" "$target" || { echo "ERROR Couldn't restore “$name”"; exit 1; }
            rm -f -- "$info"
            printf 'RESTORED %s\\n' "$target"
        done`

    // Folders without write permission (a Go module cache, files from a
    // read-only disk) can't have what's inside them deleted, so the Trash
    // could never be emptied: the ones in the Trash get it back first. Before
    // descending (\\; and not +), and never through a link: find doesn't follow
    // them, and one given to it isn't a folder (-type d).
    readonly property string writableScript: `
        writable() { find "$1" -type d ! -perm -u=rwx -exec chmod u+rwx {} \\; 2>/dev/null; }
`

    // Arguments: the Trash, then names in its files/: deleted for good, with
    // their records.
    readonly property string purgeScript: `
        trash=$1
        shift
        case $trash in */Trash) ;; *) exit 2 ;; esac
        for name in "$@"; do
            case $name in ""|.|..|*/*) continue ;; esac
            writable "\${trash:?}/files/$name"
            rm -rf -- "\${trash:?}/files/$name" || { echo "ERROR Couldn't delete “$name”"; exit 1; }
            rm -f -- "\${trash:?}/info/$name.trashinfo"
        done`

    // Argument: the Trash. Everything in it, gone for good.
    readonly property string emptyScript: `
        trash=$1
        case $trash in */Trash) ;; *) exit 2 ;; esac
        if [ -d "$trash/files" ]; then writable "\${trash:?}/files"; find "\${trash:?}/files" -mindepth 1 -delete || exit 1; fi
        if [ -d "$trash/info" ]; then find "\${trash:?}/info" -mindepth 1 -delete || exit 1; fi
        rm -f -- "\${trash:?}/directorysizes"`

    // --- Running them ---

    property Process worker: Process {
        property string output: ""
        property string errors: ""
        // Whether this run started: one that can't only turns `running` off,
        // and never exits.
        property bool began: false

        function start(args: var): void {
            output = ""
            errors = ""
            began = false
            command = args
            running = true
        }

        stdout: SplitParser {
            onRead: (line) => root.heard(line)
        }
        stderr: SplitParser {
            onRead: (line) => root.worker.errors += line + "\n"
        }
        onStarted: began = true
        onExited: (exitCode) => root.ended(exitCode)
        // Later, not from inside the start that failed: the next job starts
        // from there.
        onRunningChanged: if (!running && !began) Qt.callLater(root.couldntStart)
    }

    // The job's run couldn't start. With tens of thousands of paths, that's
    // the system's limit on arguments (2 MB with the usual 8 MB stack). It
    // fails, and the queue goes on: it used to wait for an end that never
    // came, and every copy, move or Trash after it waited too.
    function couldntStart(): void {
        const job = current
        if (!job) return
        const count = (job.paths || job.names || []).length
        failed(job.origin, count > 1000 ? "Too many items at once (" + count + "): try with fewer" : "Something went wrong")
        next()
    }

    function heard(line: string): void {
        const job = current
        if (!job) return
        worker.output += line + "\n"
        if (job.kind !== "transfer" && job.kind !== "extract" && job.kind !== "compress") return
        const space = line.indexOf(" ")
        const word = line.slice(0, space)
        const rest = line.slice(space + 1)
        if (word === "TOTAL") job.total = Number(rest)
        // Copied, or read by bsdtar (the archive, or what goes in the zip).
        else if ((word === "COPIED" || word === "READ") && job.total > 0) progress = Math.min(1, Number(rest) / job.total)
        else if (word === "PLACED" && job.kind === "transfer") job.placed.push(rest)
    }

    function ended(exitCode: int): void {
        const job = current
        if (!job) return
        const lines = worker.output.trim().split("\n").filter(l => l)
        if (job.kind === "check") {
            // Names already there: ask what to do (the transfer waits); none: go.
            const transfer = Object.assign({}, job, { kind: "transfer", policy: "keep" })
            if (lines.length) {
                const into = "“" + baseName(job.folder) + "”"
                question = {
                    origin: job.origin,
                    job: transfer,
                    count: lines.length,
                    text: (lines.length === 1 ? "“" + lines[0] + "” already exists" : lines.length + " items already exist")
                        + " in " + into + "."
                }
            } else {
                queue = [transfer].concat(queue)
            }
        } else if (job.kind === "transfer") {
            if (exitCode === 130) failed(job.origin, (job.mode === "move" ? "Move" : "Copy") + " canceled")
            else if (exitCode !== 0) failed(job.origin, (lines.find(l => l.startsWith("ERROR ")) || "ERROR Something went wrong").slice(6))
            if (job.placed.length) finished(job.origin, job.mode, job.folder, job.placed)
        } else if (job.kind === "rename") {
            if (exitCode === 0) finished(job.origin, "rename", job.folder, [job.name])
            else if (lines.includes("EXISTS")) failed(job.origin, "There's already something called “" + job.name + "” here")
            else failed(job.origin, "Couldn't rename “" + baseName(job.path) + "”" + reason())
        } else if (job.kind === "mkdir") {
            if (exitCode === 0 && lines.length) finished(job.origin, "mkdir", job.folder, [lines[0]])
            else failed(job.origin, "Couldn't make a folder here" + reason())
        } else if (job.kind === "extract" || job.kind === "compress") {
            const placed = lines.filter(l => l.startsWith("PLACED ")).map(l => l.slice(7))
            if (exitCode === 130) failed(job.origin, (job.kind === "extract" ? "Extracting" : "Compressing") + " canceled")
            else if (exitCode !== 0) failed(job.origin, (lines.find(l => l.startsWith("ERROR ")) || "ERROR Something went wrong").slice(6))
            else if (placed.length) finished(job.origin, job.kind, job.folder, placed)
        } else if (job.kind === "trash") {
            if (exitCode !== 0) failed(job.origin, "Couldn't move it to the Trash" + reason())
            else finished(job.origin, "trash", "", job.paths)
        } else if (job.kind === "restore") {
            const restored = lines.filter(l => l.startsWith("RESTORED ")).map(l => l.slice(9))
            if (exitCode !== 0) failed(job.origin, (lines.find(l => l.startsWith("ERROR ")) || "ERROR Couldn't restore it" + reason()).slice(6))
            if (restored.length) finished(job.origin, "restore", "", restored)
        } else if (job.kind === "purge") {
            if (exitCode !== 0) failed(job.origin, (lines.find(l => l.startsWith("ERROR ")) || "ERROR Couldn't delete it" + reason()).slice(6))
            else finished(job.origin, "purge", "", job.names)
        } else if (job.kind === "empty") {
            if (exitCode !== 0) failed(job.origin, "Couldn't empty the Trash" + reason())
            else finished(job.origin, "empty", "", [])
        }
        next()
    }

    // The tool's own message, briefly ("Permission denied").
    function reason(): string {
        const line = worker.errors.trim().split("\n").pop() || ""
        const why = line.slice(line.lastIndexOf(": ") + 2)
        return why ? ": " + why.charAt(0).toLowerCase() + why.slice(1) : ""
    }
}
