import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "../common"
import "fileutil.js" as Util

// The quick view (Space in Files): the selected file, big, in a panel above
// everything, like Settings. It never takes the keyboard: that stays in the
// Files window, whose arrows keep moving the selection while the panel
// follows it (Space or Esc close it, Enter opens the file). Only the card
// takes the pointer; a click around it reaches the windows below.
//
// Following the selection, the card keeps the last file until the next one
// is ready (read, decoded) and then changes in one step: it never empties to
// fill again. Every text is the same page, so moving through a folder of
// code only the text changes.
//
// Images show here; text too (Markdown formatted); a PDF a page at a time
// (drawn by pdftoppm); what an archive holds (listed by bsdtar); videos and
// songs play in a process of their own (video/preview.qml) drawn right over
// the card's empty area, which ends when the view moves on or closes:
// QtMultimedia holds on to the decoder's memory (300+ MB with a 4K video)
// until its process ends. Anything else: a card with what it is, its size
// and its date.
PanelWindow {
    id: root

    required property Theme theme
    // The selected file: { name, path, isDir, size, modified } or null.
    property var entry: null
    // The cached thumbnail of what the card shows, if it has one (documents,
    // see Thumbnails.qml).
    property string thumbnail: ""
    property string timeFormat: "hh:mm"
    signal openRequested()
    signal closeRequested()

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    mask: Region { item: card }
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "spore-quick-view"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    readonly property string path: entry ? entry.path : ""
    // What the card shows: the selected file, once it's ready.
    property var shown: null
    readonly property string shownPath: shown ? shown.path : ""
    // What that is: "image", "text", "pdf", "cover" (an ODF document's or an
    // EPUB's), "archive", "font", "video", "audio" or "info" ("" = it's
    // still being read, see `patience`).
    property string kind: ""

    onPathChanged: prepare()
    // The same file with new details (it changed on disk): only those change.
    onEntryChanged: if (entry && entry.path === shownPath) shown = entry
    Component.onCompleted: prepare()

    // Gets the selected file ready; show() puts it on the card.
    function prepare(): void {
        stopMedia()
        patience.stop()
        // A listing still going on (a big archive): stopped.
        lister.running = false
        if (!entry) {
            stillFile = ""
            movingFile = ""
            show("", "", false)
            return
        }
        // From the path: in Recent, a name can have its folder after it.
        const name = Util.baseName(path)
        const k = Util.kindOf(name, entry.isDir)
        if (k === "image") {
            // Shown once it's decoded (see the images below); a GIF or WebP
            // goes to the one that can move. One that's there already (shown, or
            // decoding) is checked now: its status may not change again.
            const animated = /^(gif|webp)$/.test(Util.extension(path))
            if ((animated ? movingFile : stillFile) === path) decoded(animated ? animatedImage : image)
            else if (animated) movingFile = path
            else stillFile = path
        } else if (k === "text" || k === "code" || Util.extension(name) === "csv") {
            read()
        } else if (k === "video") {
            prober.command = ["ffprobe", "-v", "error", "-select_streams", "v:0", "-show_entries", "stream=width,height",
                "-of", "csv=p=0", "--", path]
            prober.running = true
        } else if (k === "audio") {
            show("audio", "", false)
            startSoon.restart()
        } else if (k === "font" && entry.size > 0) {
            loadFont()
        } else if (/^(odt|ods|odp|odg|ott|ots|otp|otg|epub)$/.test(Util.extension(name)) && entry.size > 0) {
            extractCover()
        } else if (k === "file" && entry.size > 0) {
            // No known extension: it may be text, gio says.
            sniffer.command = ["gio", "info", "-a", "standard::content-type", path]
            sniffer.running = true
        } else if (Util.extension(name) === "pdf" && entry.size > 0) {
            renderPage(1)
        } else if (Util.extractable(name) && entry.size > 0) {
            listArchive()
        } else {
            show("info", "", false)
        }
        if (shownPath !== path) patience.restart()
    }

    // The card changes to the selected file, all at once.
    function show(k: string, text: string, failed: bool): void {
        patience.stop()
        // Emptied first: the new text is laid out once, in its own format.
        textContent = ""
        shown = entry
        kind = k
        imageFailed = failed
        textContent = text
        textView.contentY = 0
        // The image no longer shown isn't kept (while the card waits, the next
        // one goes on decoding); nor a PDF's page, nor an archive's listing.
        if (k !== "") {
            if (k !== "image" || moving) stillFile = ""
            if (k !== "image" || !moving) movingFile = ""
            if (k !== "pdf" && k !== "cover") clearPages()
            if (k !== "archive") archiveRows = []
        }
    }

    // A file that takes long to be ready (a huge image, a slow disk): its card
    // with what it is shows meanwhile.
    property Timer patience: Timer {
        interval: 300
        onTriggered: root.show("", "", false)
    }

    // The helpers below get the file as their last argument and note which one
    // each run is for: moving quickly through files, a run asked for while
    // another was running goes after it (Quickshell queues it), and the older
    // answer, for a file no longer selected, is ignored.

    Process {
        id: sniffer
        property string runFor: ""
        onStarted: runFor = command[command.length - 1]
        stdout: StdioCollector {
            onStreamFinished: {
                if (sniffer.runFor !== root.path) return
                const type = (text.match(/standard::content-type: (\S+)/) || [])[1] || ""
                if (/^text\/|\/(json|xml|javascript|x-shellscript|toml|yaml|x-yaml)$/.test(type)) root.read()
                else root.show("info", "", false)
            }
        }
    }

    // --- Text ---

    property string textContent: ""

    // Markdown, but with nothing Qt would fetch from the network to show it:
    // the images (![…](url)) and raw HTML (a table's background, a style's
    // background-image). Fetching them tells whoever wrote the file that it
    // was opened, and from where. An invisible space (U+200B) after each "<"
    // and inside each "![" leaves them as plain text: the HTML shows as
    // written and an image as a link, while code, where both are common,
    // looks the same.
    function safeMarkdown(text: string): string {
        return text.replace(/</g, "<\u200B").replace(/!\[/g, "!\u200B[")
    }

    // The first 200 KB is plenty to see what it is; a NUL means it isn't text.
    function read(): void {
        reader.command = ["head", "-c", "200000", "--", path]
        reader.running = true
    }

    Process {
        id: reader
        property string runFor: ""
        onStarted: runFor = command[command.length - 1]
        stdout: StdioCollector {
            onStreamFinished: {
                if (reader.runFor !== root.path) return
                if (text.includes("\u0000")) root.show("info", "", false)
                else root.show("text", text, false)
            }
        }
    }

    // --- Images ---

    // The image being decoded (the next file) or shown, in each of the two
    // kinds: while the next one decodes, the last one stays on the card.
    property string stillFile: ""
    property string movingFile: ""
    readonly property bool moving: /^(gif|webp)$/.test(Util.extension(shownPath))
    // Its size, decoded already scaled down to what fits.
    property size imageSize: Qt.size(0, 0)
    property bool imageFailed: false

    // Shows the selected image once it's decoded (or couldn't be) by `item`.
    function decoded(item: Item): void {
        if ((item === image ? stillFile : movingFile) !== path) return
        if (item.status !== Image.Ready && item.status !== Image.Error) return
        imageSize = Qt.size(item.implicitWidth, item.implicitHeight)
        show("image", "", item.status === Image.Error)
    }

    // --- PDFs ---

    // pdftoppm draws one page at a time, just as big as the card shows it (in
    // the screen's pixels), into $XDG_RUNTIME_DIR: uncompressed, as a PNG's
    // compression takes several times longer than drawing the page. The file
    // is removed once decoded, and the page shown stays until the next one is
    // ready.
    property int pdfPages: 0
    property int pdfPage: 0
    property size pageSize: Qt.size(0, 0)
    // The page asked for (drawn, or being drawn), and the one being decoded:
    // { entry, number, pages, file }.
    property int pageAsked: 0
    property var pageLoading: null

    function renderPage(n: int): void {
        pageAsked = n
        pdfRenderer.command = ["sh", "-c", pdfScript, "_", path, String(n),
            String(Math.round(maxWidth * dpr)), String(Math.round(maxHeight * dpr))]
        pdfRenderer.running = true
    }

    // The page before or after: the card's arrows, the wheel, Page Up and
    // Page Down in Files.
    function turn(delta: int): void {
        if (kind !== "pdf" || shownPath !== path) return
        const n = Math.max(1, Math.min(pdfPages, pageAsked + delta))
        if (n !== pageAsked) renderPage(n)
    }

    function removePage(file: string): void {
        if (file) Quickshell.execDetached(["rm", "-f", "--", file])
    }

    // A page drawn: it's decoded next (one still decoding isn't wanted anymore).
    function loadPage(page: var): void {
        if (pageLoading) removePage(pageLoading.file)
        pageLoading = page
        pageView.source = "file://" + page.file
    }

    function pageDecoded(): void {
        const page = pageLoading
        if (!page || pageView.status === Image.Loading) return
        pageLoading = null
        removePage(page.file)
        const selected = page.entry.path === path
        if (pageView.status !== Image.Ready) {
            // It can't be decoded: what it is.
            if (selected && shownPath !== path) show("info", "", false)
            return
        }
        // The counter says what the page shows.
        pageSize = Qt.size(pageView.implicitWidth, pageView.implicitHeight)
        pdfPages = page.pages
        pdfPage = page.number
        if (selected) {
            if (kind !== page.kind || shownPath !== path) show(page.kind, "", false)
        } else if (kind === page.kind) {
            // Another PDF's page (or cover), while the card waits for what's
            // selected now: the card says whose it is.
            shown = page.entry
        } else {
            clearPages()
        }
    }

    // No page anymore: the card shows something else.
    function clearPages(): void {
        if (pageLoading) removePage(pageLoading.file)
        pageLoading = null
        pageView.source = ""
        pdfPages = 0
        pdfPage = 0
    }

    // Arguments: the PDF, the page, the room for it (width and height, in
    // pixels). Prints FOR <the PDF>, PAGE <the page>, PAGES <how many> and
    // FILE <the page drawn, a PPM>. The side that fills the room comes from
    // the page's shape as it shows (turned, if it's rotated). (The path is
    // absolute: poppler takes no "--".)
    readonly property string pdfScript: `
        printf 'FOR %s\\nPAGE %s\\n' "$1" "$2"
        info=$(pdfinfo -f "$2" -l "$2" "$1" 2>/dev/null) || exit 1
        printf '%s\\n' "$info" | awk '/^Pages:/ { print "PAGES " $2 }'
        scale=$(printf '%s\\n' "$info" | awk -v W="$3" -v H="$4" '
            /^Page .*size:/ { for (i = 2; i < NF; i++) if ($i == "x") { w = $(i - 1); h = $(i + 1) } }
            /^Page .*rot:/ { if ($NF % 180) { t = w; w = h; h = t } }
            END {
                if (w * H > h * W) print "-scale-to-x " W " -scale-to-y -1"
                else print "-scale-to-x -1 -scale-to-y " H
            }')
        dir=\${XDG_RUNTIME_DIR:-/tmp}
        # Pages left behind (Files ended while one was drawn).
        find "$dir" -maxdepth 1 -name 'spore-files-page-*.ppm' -mmin +1 -delete 2>/dev/null
        page="$dir/spore-files-page-$$"
        pdftoppm -singlefile -cropbox -scale-dimension-before-rotation -f "$2" -l "$2" $scale "$1" "$page" 2>/dev/null
        [ -s "$page.ppm" ] && echo "FILE $page.ppm"`

    Process {
        id: pdfRenderer
        stdout: StdioCollector {
            onStreamFinished: {
                const field = (key) => (text.match(new RegExp("^" + key + " (.*)$", "m")) || [])[1] || ""
                const file = field("FILE")
                // Drawn for a file or a page that's no longer wanted.
                if (field("FOR") !== root.path || Number(field("PAGE")) !== root.pageAsked) {
                    root.removePage(file)
                    return
                }
                if (!file) {
                    // It can't be drawn (damaged, locked): what it is.
                    if (root.shownPath !== root.path) root.show("info", "", false)
                    return
                }
                root.loadPage({ entry: root.entry, number: root.pageAsked, pages: Number(field("PAGES")) || 1, file: file, kind: "pdf" })
            }
        }
    }

    // --- Fonts ---

    // A font: loaded into Files and shown in itself, big to small. FontLoader
    // keeps each one until Files ends (about 60 KB apiece: 150 of them, CJK
    // ones included, took 8 MB).
    property string fontFor: ""

    function loadFont(): void {
        fontFor = path
        fontLoader.source = Util.fileUri(path)
        // A file loads right away, and one loaded before doesn't change the
        // status again. Shown after, not from here: this runs when `path`
        // changes, maybe while a binding that reads it is being evaluated, and
        // changing what's shown then made a binding loop.
        Qt.callLater(fontReady)
    }

    function fontReady(): void {
        if (fontFor !== path) return
        if (fontLoader.status === FontLoader.Ready) show("font", "", false)
        else if (fontLoader.status === FontLoader.Error) show("info", "", false)
    }

    FontLoader {
        id: fontLoader
        onStatusChanged: Qt.callLater(root.fontReady)
    }

    // --- Covers ---

    // Argument: the document. Prints FOR <it> and, if it has one, FILE <its
    // cover>, taken out into $XDG_RUNTIME_DIR (removed once decoded, like a
    // PDF's page). An ODF document (LibreOffice's) keeps a thumbnail of its
    // first page in Thumbnails/thumbnail.png. An EPUB names its cover in its
    // package file (META-INF/container.xml says which): EPUB 3 as the item
    // with properties="cover-image", EPUB 2 with <meta name="cover">. That
    // name is relative to the package file and %-encoded, like a URL.
    readonly property string coverScript: `
        printf 'FOR %s\\n' "$1"
        dir=\${XDG_RUNTIME_DIR:-/tmp}
        # Covers left behind (Files ended while one was taken out).
        find "$dir" -maxdepth 1 -name 'spore-files-cover-*' -mmin +1 -delete 2>/dev/null
        case $1 in
        *.[eE][pP][uU][bB])
            opf=$(bsdtar -xOf "$1" META-INF/container.xml 2>/dev/null | tr '\\n' ' ' |
                grep -o 'full-path="[^"]*"' | head -n 1 | cut -d'"' -f2)
            [ -n "$opf" ] || exit 0
            tags=$(bsdtar -xOf "$1" "$opf" 2>/dev/null | tr '\\n' ' ' | grep -o '<[a-z:]*\\(item\\|meta\\) [^>]*>')
            href=$(printf '%s\\n' "$tags" | grep 'properties="[^"]*cover-image' |
                grep -o ' href="[^"]*"' | head -n 1 | cut -d'"' -f2)
            if [ -z "$href" ]; then
                id=$(printf '%s\\n' "$tags" | grep 'name="cover"' | grep -o 'content="[^"]*"' | head -n 1 | cut -d'"' -f2)
                [ -n "$id" ] && href=$(printf '%s\\n' "$tags" | grep -F " id=\\"$id\\"" |
                    grep -o ' href="[^"]*"' | head -n 1 | cut -d'"' -f2)
            fi
            [ -n "$href" ] || exit 0
            case $opf in */*) href=\${opf%/*}/$href ;; esac
            # "a/../b" -> "b", "./b" -> "b", %20 -> " ", &amp; -> &.
            while case $href in */../*) true ;; *) false ;; esac; do
                href=$(printf '%s' "$href" | sed 's|[^/]*/\\.\\./||')
            done
            href=$(printf '%s' "$href" | sed -e 's|\\./||g' -e 's|&amp;|\\&|g' -e 's|%\\([0-9A-Fa-f][0-9A-Fa-f]\\)|\\\\x\\1|g')
            entry=$(printf '%bx' "$href")
            entry=\${entry%x} ;;
        *)
            entry=Thumbnails/thumbnail.png ;;
        esac
        cover="$dir/spore-files-cover-$$"
        bsdtar -xOf "$1" "$entry" > "$cover" 2>/dev/null
        if [ -s "$cover" ]; then echo "FILE $cover"; else rm -f "$cover"; fi`

    function extractCover(): void {
        coverExtractor.command = ["sh", "-c", coverScript, "_", path]
        coverExtractor.running = true
    }

    Process {
        id: coverExtractor
        stdout: StdioCollector {
            onStreamFinished: {
                const field = (key) => (text.match(new RegExp("^" + key + " (.*)$", "m")) || [])[1] || ""
                const file = field("FILE")
                // Taken out for a file that's no longer selected.
                if (field("FOR") !== root.path) {
                    root.removePage(file)
                    return
                }
                if (!file) {
                    // None (or it can't be read): what it is.
                    if (root.shownPath !== root.path) root.show("info", "", false)
                    return
                }
                root.loadPage({ entry: root.entry, number: 1, pages: 1, file: file, kind: "cover" })
            }
        }
    }

    // --- Archives ---

    // What's inside a zip, 7z, rar or tar, as bsdtar lists it without
    // extracting anything: a tree, folders first, each with what it weighs.
    // The first 1000 entries show; the counts are of all of them. A tar
    // compressed whole (.tar.gz, .tar.xz…) has to be read through to list it,
    // so a big one takes a while: moving on stops it.
    // Rows: { name, depth, isDir, size }.
    property var archiveRows: []
    property string archiveSummary: ""
    property int archiveMore: 0

    function listArchive(): void {
        lister.command = ["sh", "-c", archiveScript, "_", path]
        lister.running = true
    }

    function listed(text: string): void {
        const lines = text.split("\n")
        if (lines[0] !== "FOR " + path) return
        const entries = []
        const counts = {}
        for (const line of lines) {
            const entry = /^E ([df]) (\d+) (.*)$/.exec(line)
            const count = /^(FILES|FOLDERS|BYTES|MORE) (\d+)$/.exec(line)
            if (entry) entries.push({ isDir: entry[1] === "d", size: Number(entry[2]), path: entry[3] })
            else if (count) counts[count[1]] = Number(count[2])
        }
        if (!entries.length) {
            // Not an archive after all, damaged, or locked: what it is.
            show("info", "", false)
            return
        }
        const files = counts.FILES || 0
        const folders = counts.FOLDERS || 0
        archiveRows = archiveTree(entries)
        archiveMore = counts.MORE || 0
        archiveSummary = (files === 1 ? "1 file" : files + " files")
            + (folders ? " in " + (folders === 1 ? "1 folder" : folders + " folders") : "")
            + " · " + Util.humanSize(counts.BYTES || 0) + " extracted"
        show("archive", "", false)
    }

    // The entries as rows of a tree: folders first, each level in natural
    // order, a folder weighing what it holds. Folders that only show up in
    // their files' paths (zips often leave them out) are there too.
    function archiveTree(entries: var): var {
        const folder = () => ({ folders: Object.create(null), files: [] })
        const top = folder()
        for (const entry of entries) {
            const parts = entry.path.split("/")
            let node = top
            for (let i = 0; i < (entry.isDir ? parts.length : parts.length - 1); i++)
                node = node.folders[parts[i]] || (node.folders[parts[i]] = folder())
            if (!entry.isDir) node.files.push({ name: parts[parts.length - 1], size: entry.size })
        }
        const rows = []
        const walk = (node, depth) => {
            let size = 0
            for (const name of Object.keys(node.folders).sort(Util.naturalCompare)) {
                const row = { name: name, depth: depth, isDir: true, size: 0 }
                rows.push(row)
                row.size = walk(node.folders[name], depth + 1)
                size += row.size
            }
            node.files.sort((a, b) => Util.naturalCompare(a.name, b.name))
            for (const file of node.files) {
                rows.push({ name: file.name, depth: depth, isDir: false, size: file.size })
                size += file.size
            }
            return size
        }
        walk(top, 0)
        return rows
    }

    // Argument: the archive. Prints FOR <it>, then E <d or f> <size> <path>
    // for the first 1000 entries, and FILES, FOLDERS (with the ones only in a
    // path), BYTES and MORE <entries not listed>. bsdtar's lines: mode, links,
    // owner, group, size, month, day, time, then the name (a link's target
    // after it). In C.UTF-8: dates in English, names as they are. bsdtar dies
    // with the script, so stopping it stops a long read.
    readonly property string archiveScript: `
        printf 'FOR %s\\n' "$1"
        LC_ALL=C.UTF-8 setpriv --pdeathsig KILL -- bsdtar --numeric-owner -tvf "$1" 2>/dev/null | awk '
            match($0, /^[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ +[^ ]+ /) {
                name = substr($0, RLENGTH + 1)
                type = substr($1, 1, 1)
                if (type == "l") sub(/ -> .*$/, "", name)
                if (type == "h") sub(/ link to .*$/, "", name)
                while (substr(name, 1, 2) == "./") name = substr(name, 3)
                while (substr(name, 1, 1) == "/") name = substr(name, 2)
                while (name != "" && substr(name, length(name)) == "/") name = substr(name, 1, length(name) - 1)
                if (name == "" || name == ".") next
                n = split(name, parts, "/")
                path = ""
                for (i = 1; i < n; i++) {
                    path = path (i > 1 ? "/" : "") parts[i]
                    if (!(path in seen)) { seen[path] = 1; folders++ }
                }
                if (type == "d") {
                    if (!(name in seen)) { seen[name] = 1; folders++ }
                } else {
                    files++
                    bytes += $5
                }
                if (++entries <= 1000) printf "E %s %d %s\\n", type == "d" ? "d" : "f", $5, name
            }
            END {
                printf "FILES %d\\nFOLDERS %d\\nBYTES %d\\n", files, folders, bytes
                if (entries > 1000) printf "MORE %d\\n", entries - 1000
            }'`

    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: root.listed(text)
        }
    }

    // --- Video and audio ---

    property size videoSize: Qt.size(0, 0)
    // The player shows its first frame (or starts playing a song).
    property bool mediaReady: false
    property string mediaError: ""

    Process {
        id: prober
        property string runFor: ""
        onStarted: runFor = command[command.length - 1]
        stdout: StdioCollector {
            onStreamFinished: {
                if (prober.runFor !== root.path) return
                const [w, h] = text.trim().split(",").map(Number)
                root.videoSize = w > 0 && h > 0 ? Qt.size(w, h) : Qt.size(16, 9)
                root.show("video", "", false)
                root.startSoon.restart()
            }
        }
    }

    // Moving through several videos with the arrows starts only the last one.
    property Timer startSoon: Timer {
        interval: 250
        onTriggered: root.startMedia()
    }

    // The player for this file is wanted: it starts as soon as the previous
    // one (if any) has exited.
    property bool wantMedia: false

    function startMedia(): void {
        if (kind !== "video" && kind !== "audio" || shownPath !== path) return
        wantMedia = true
        if (player.running) player.signal(15)
        else launch()
    }

    function launch(): void {
        const origin = mediaArea.mapToItem(null, 0, 0)
        player.environment = {
            SPORE_PREVIEW: shownPath,
            SPORE_PREVIEW_SCREEN: root.screen ? root.screen.name : "",
            SPORE_PREVIEW_RECT: [origin.x, origin.y, mediaArea.width, mediaArea.height].map(Math.round).join(","),
            SPORE_PREVIEW_AUDIO: kind === "audio" ? "1" : "0",
            SPORE_PREVIEW_COLORS: [theme.text, theme.accent, theme.base].map(c => c.toString()).join(","),
            SPORE_PREVIEW_FONT: theme.fontFamily
        }
        player.runFor = shownPath
        player.running = true
    }

    function stopMedia(): void {
        wantMedia = false
        startSoon.stop()
        mediaReady = false
        mediaError = ""
        if (player.running) player.signal(15)
    }

    Component.onDestruction: {
        stopMedia()
        if (pageLoading) removePage(pageLoading.file)
    }

    // setpriv: if Files goes away without closing it, the player goes too
    // (otherwise it would stay on the screen, over everything).
    Process {
        id: player
        // Its lines only count while it plays this file (a closing one can still
        // say something).
        property string runFor: ""
        command: ["setpriv", "--pdeathsig", "TERM", Quickshell.env("SPORE_QUICKSHELL") || "quickshell",
            "-p", Quickshell.shellDir + "/../video/preview.qml"]
        stdout: SplitParser {
            onRead: (line) => root.playerSaid(line)
        }
        stderr: SplitParser {
            onRead: (line) => root.playerSaid(line)
        }
        onExited: {
            root.mediaReady = false
            if (root.wantMedia && (root.kind === "video" || root.kind === "audio")) root.launch()
        }
    }

    function playerSaid(line: string): void {
        if (player.runFor !== shownPath || !wantMedia) return
        if (line.includes("SPORE_PREVIEW:playing")) mediaReady = true
        else if (line.includes("SPORE_PREVIEW:failed")) mediaError = line.slice(line.indexOf("SPORE_PREVIEW:failed") + 21)
    }

    // --- The card ---

    // The biggest it grows: most of the screen. The panel covers its screen
    // (the bar too), so it's the screen's size, known before the panel is
    // sized: a PDF's first page isn't drawn tiny.
    readonly property real maxWidth: Math.round((screen ? screen.width : width) * 0.72)
    readonly property real maxHeight: Math.round((screen ? screen.height : height) * 0.8) - headerHeight
    // The screen's pixels per point: a PDF's page is drawn with them.
    readonly property real dpr: screen ? screen.devicePixelRatio : 1
    readonly property real headerHeight: 58

    // The size of what's shown, fitted into maxWidth x maxHeight.
    function fit(w: real, h: real, grow: bool): size {
        const scale = Math.min(maxWidth / w, maxHeight / h, grow ? Infinity : 1)
        return Qt.size(Math.round(w * scale), Math.round(h * scale))
    }

    // Images at their size (never enlarged); videos enlarged to fill it; text
    // and an archive's contents on a page, the same for all of them (short or
    // long, the card doesn't change size from one to the next).
    readonly property size mediaSize: {
        if (kind === "image" && !imageFailed && imageSize.width > 0) return fit(imageSize.width, imageSize.height, false)
        if ((kind === "pdf" || kind === "cover") && pageSize.width > 0) return fit(pageSize.width, pageSize.height, false)
        if (kind === "video") return videoSize.width > 0 ? fit(videoSize.width, videoSize.height, true) : Qt.size(640, 360)
        if (kind === "audio") return Qt.size(500, 44)
        if (kind === "text" || kind === "archive") return Qt.size(Math.min(860, maxWidth), Math.min(680, maxHeight))
        if (kind === "font") return Qt.size(Math.min(860, maxWidth), Math.min(520, maxHeight))
        return Qt.size(500, 156)
    }
    // With a margin around, so the card's round corners show.
    readonly property int padding: 12
    readonly property size bodySize: Qt.size(mediaSize.width + 2 * padding, mediaSize.height + 2 * padding)

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.max(420, root.bodySize.width)
        height: root.headerHeight + 1 + root.bodySize.height
        visible: root.shown !== null
        radius: 14
        color: root.theme.base
        border.width: 1
        border.color: root.theme.accent
        clip: true

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // --- Header: what it is, Open and close ---
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: root.headerHeight - 1
                Layout.leftMargin: 16
                Layout.rightMargin: 10
                spacing: 12

                FileIcon {
                    theme: root.theme
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    path: root.shownPath
                    isDir: root.shown ? root.shown.isDir : false
                    iconSize: 18
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 1

                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.shown ? root.shown.name : ""
                        font.weight: Font.DemiBold
                        elide: Text.ElideMiddle
                    }
                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.shown ? Util.kindLabel(Util.baseName(root.shownPath), root.shown.isDir)
                            + (root.shown.isDir ? "" : " · " + Util.humanSize(root.shown.size))
                            + " · " + Util.shortDate(root.shown.modified, root.timeFormat) : ""
                        color: root.theme.muted
                        font.pixelSize: 11
                    }
                }
                // A PDF's pages: the one shown, and the arrows to turn them.
                Row {
                    visible: root.kind === "pdf" && root.pdfPages > 1
                    spacing: 2

                    CcButton {
                        theme: root.theme
                        size: 30
                        flat: true
                        icon: "chevron-left"
                        iconSize: 14
                        enabled: root.pdfPage > 1
                        onClicked: root.turn(-1)
                    }
                    MonoText {
                        theme: root.theme
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.pdfPage + " / " + root.pdfPages
                        color: root.theme.muted
                        font.pixelSize: 12
                    }
                    CcButton {
                        theme: root.theme
                        size: 30
                        flat: true
                        icon: "chevron-right"
                        iconSize: 14
                        enabled: root.pdfPage < root.pdfPages
                        onClicked: root.turn(1)
                    }
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    label: "Open"
                    onClicked: root.openRequested()
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    flat: true
                    icon: "x"
                    iconSize: 14
                    onClicked: root.closeRequested()
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: root.theme.alpha(root.theme.accent, 0.12)
            }

            // --- What's shown ---
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                // Images: decoded already scaled down to what fits (a 4K photo
                // isn't held at full size). GIF and WebP can move.
                Image {
                    id: image
                    anchors.centerIn: parent
                    visible: root.kind === "image" && !root.moving && !root.imageFailed
                    width: root.mediaSize.width
                    height: root.mediaSize.height
                    source: root.stillFile ? Util.fileUri(root.stillFile) : ""
                    sourceSize: Qt.size(root.maxWidth, root.maxHeight)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    // The last one stays while the next one decodes.
                    retainWhileLoading: true
                    cache: false
                    onStatusChanged: root.decoded(image)
                }
                AnimatedImage {
                    id: animatedImage
                    anchors.centerIn: parent
                    visible: root.kind === "image" && root.moving && !root.imageFailed
                    width: root.mediaSize.width
                    height: root.mediaSize.height
                    source: root.movingFile ? Util.fileUri(root.movingFile) : ""
                    fillMode: Image.PreserveAspectFit
                    cache: false
                    playing: visible
                    onStatusChanged: root.decoded(animatedImage)
                }

                // A font: its name, then lines in it from big to small.
                Flickable {
                    id: fontView
                    anchors.fill: parent
                    anchors.margins: root.padding + 12
                    visible: root.kind === "font"
                    contentHeight: fontSamples.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: fontSamples
                        width: fontView.width
                        spacing: 16

                        Repeater {
                            model: [
                                { size: 40, text: fontLoader.name + (fontLoader.font.styleName ? " " + fontLoader.font.styleName : "") },
                                { size: 30, text: "The quick brown fox jumps over the lazy dog" },
                                { size: 20, text: "The quick brown fox jumps over the lazy dog" },
                                { size: 14, text: "The quick brown fox jumps over the lazy dog" },
                                { size: 20, text: "ABCDEFGHIJKLMNOPQRSTUVWXYZ\nabcdefghijklmnopqrstuvwxyz\n0123456789 .,:;!?&@#%*()[]" }
                            ]

                            Text {
                                required property var modelData
                                width: fontSamples.width
                                text: modelData.text
                                textFormat: Text.PlainText
                                color: root.theme.text
                                wrapMode: Text.Wrap
                                // The face itself: a family's other faces may be
                                // installed too.
                                font.family: fontLoader.font.family
                                font.styleName: fontLoader.font.styleName
                                font.pixelSize: modelData.size
                            }
                        }
                    }
                }

                // A PDF's page, drawn by pdftoppm (or a document's cover): the
                // one shown stays while the next one is drawn and decoded. A
                // cover can be big: decoded only as big as the card shows it.
                Image {
                    id: pageView
                    anchors.centerIn: parent
                    visible: root.kind === "pdf" || root.kind === "cover"
                    sourceSize: Qt.size(Math.round(root.maxWidth * root.dpr), Math.round(root.maxHeight * root.dpr))
                    width: root.mediaSize.width
                    height: root.mediaSize.height
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    retainWhileLoading: true
                    cache: false
                    onStatusChanged: root.pageDecoded()
                }
                // The wheel turns pages: a page a notch. On a touchpad, a page
                // a swipe (once it has gone 60 px), however long it goes on,
                // so it doesn't race through them.
                WheelHandler {
                    id: pageWheel
                    property real turned: 0
                    property bool swiped: false
                    // A swipe ends when the fingers lift, or when it stops a
                    // moment (some devices don't say).
                    property Timer swipeEnd: Timer {
                        interval: 300
                        onTriggered: pageWheel.endSwipe()
                    }

                    function endSwipe(): void {
                        swipeEnd.stop()
                        turned = 0
                        swiped = false
                    }

                    // A mouse's wheel too: with niri, Qt (6.11) says every
                    // wheel is the seat's touchpad, and by default a
                    // WheelHandler only takes a mouse.
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    enabled: root.kind === "pdf" && root.pdfPages > 1
                    onWheel: (event) => {
                        if (event.phase === Qt.ScrollBegin || event.phase === Qt.ScrollEnd) {
                            endSwipe()
                        } else if (event.pixelDelta.y === 0) {
                            // A wheel (Qt Wayland gives it no pixels): 120 a
                            // notch, or less on a fine-grained one.
                            turned += event.angleDelta.y
                            const notches = Math.trunc(turned / 120)
                            turned -= notches * 120
                            if (notches) root.turn(-notches)
                        } else {
                            swipeEnd.restart()
                            if (swiped) return
                            turned += event.pixelDelta.y
                            if (Math.abs(turned) < 60) return
                            swiped = true
                            root.turn(turned < 0 ? 1 : -1)
                        }
                    }
                }

                Flickable {
                    id: textView
                    anchors.fill: parent
                    anchors.margins: root.padding
                    visible: root.kind === "text"
                    contentWidth: width
                    contentHeight: textEdit.implicitHeight
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    TextEdit {
                        id: textEdit
                        width: textView.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        textFormat: Util.extension(root.shownPath) === "md" ? TextEdit.MarkdownText : TextEdit.PlainText
                        text: textFormat === TextEdit.MarkdownText ? root.safeMarkdown(root.textContent) : root.textContent
                        color: root.theme.text
                        selectionColor: root.theme.accent
                        selectedTextColor: root.theme.textOnAccent
                        font.family: textFormat === TextEdit.MarkdownText ? root.theme.uiFont : root.theme.fontFamily
                        font.pixelSize: 13
                    }
                }

                // An archive's contents: what it holds on top, then the tree.
                ListView {
                    id: archiveView
                    anchors.fill: parent
                    anchors.margins: root.padding
                    visible: root.kind === "archive"
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds
                    model: root.archiveRows

                    header: UiText {
                        theme: root.theme
                        width: ListView.view.width
                        bottomPadding: 8
                        text: root.archiveSummary
                        color: root.theme.muted
                        font.pixelSize: 12
                    }
                    delegate: Item {
                        id: archiveRow
                        required property var modelData
                        width: ListView.view.width
                        height: 26

                        Icon {
                            id: archiveIcon
                            x: archiveRow.modelData.depth * 18
                            anchors.verticalCenter: parent.verticalCenter
                            name: Util.iconOf(Util.kindOf(archiveRow.modelData.name, archiveRow.modelData.isDir))
                            size: 15
                            color: archiveRow.modelData.isDir ? root.theme.accent : root.theme.muted2
                        }
                        UiText {
                            theme: root.theme
                            anchors.left: archiveIcon.right
                            anchors.leftMargin: 8
                            anchors.right: archiveSize.left
                            anchors.rightMargin: 12
                            anchors.verticalCenter: parent.verticalCenter
                            text: archiveRow.modelData.name
                            elide: Text.ElideMiddle
                        }
                        MonoText {
                            id: archiveSize
                            theme: root.theme
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Util.humanSize(archiveRow.modelData.size)
                            color: root.theme.muted
                        }
                    }
                    footer: UiText {
                        theme: root.theme
                        width: ListView.view.width
                        topPadding: 8
                        visible: root.archiveMore > 0
                        text: "… and " + root.archiveMore + " more"
                        color: root.theme.muted
                        font.pixelSize: 12
                    }
                }

                // Where the player draws (its surface goes right on top).
                Rectangle {
                    id: mediaArea
                    anchors.fill: parent
                    anchors.margins: root.padding
                    radius: 6
                    visible: root.kind === "video" || root.kind === "audio"
                    color: root.kind === "video" ? "black" : "transparent"

                    UiText {
                        theme: root.theme
                        anchors.centerIn: parent
                        // Not while the next file is being read.
                        visible: !root.mediaReady && root.shownPath === root.path
                        text: root.mediaError ? "Can't play it: " + root.mediaError : "Loading…"
                        color: root.kind === "video" ? "white" : root.theme.muted
                    }
                }

                // Anything else (or an image that couldn't be read): what it is.
                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 22
                    visible: root.kind === "info" || root.kind === "" || root.imageFailed
                    spacing: 22

                    FileIcon {
                        theme: root.theme
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 120
                        path: root.shownPath
                        isDir: root.shown ? root.shown.isDir : false
                        fileSize: root.shown ? root.shown.size : 0
                        thumbnail: root.thumbnail
                        iconSize: 72
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 6

                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.shown ? Util.kindLabel(Util.baseName(root.shownPath), root.shown.isDir) : ""
                            font.pixelSize: 15
                            font.weight: Font.DemiBold
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            visible: root.shown !== null && !root.shown.isDir
                            text: root.shown ? Util.humanSize(root.shown.size) : ""
                            color: root.theme.muted
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.shown ? "Modified " + Util.shortDate(root.shown.modified, root.timeFormat) : ""
                            color: root.theme.muted
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.shown ? Util.parentOf(root.shown.path) : ""
                            color: root.theme.muted2
                            elide: Text.ElideMiddle
                            font.pixelSize: 12
                        }
                    }
                }
            }
        }
    }

}
