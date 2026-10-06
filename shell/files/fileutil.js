.pragma library

// Files utilities: kinds of file, sizes, dates and paths.

// Kinds by extension: the icon (lucide.js) and the name the list shows.
const kinds = {
    image: {
        icon: "file-image", label: "image",
        ext: ["png", "jpg", "jpeg", "webp", "gif", "bmp", "svg", "tif", "tiff", "avif", "heic", "heif", "jxl", "ico"]
    },
    video: {
        icon: "file-video-camera", label: "video",
        ext: ["mp4", "mkv", "webm", "mov", "avi", "m4v", "wmv", "flv", "mpg", "mpeg", "ogv"]
    },
    audio: {
        icon: "file-music", label: "audio",
        ext: ["mp3", "flac", "ogg", "oga", "opus", "wav", "m4a", "aac", "wma"]
    },
    font: {
        icon: "file-type", label: "font",
        ext: ["ttf", "otf", "ttc", "otc", "woff", "woff2"]
    },
    archive: {
        icon: "file-archive", label: "Archive",
        ext: ["zip", "tar", "gz", "tgz", "xz", "bz2", "zst", "7z", "rar", "iso"]
    },
    code: {
        icon: "file-code", label: "Code",
        ext: ["js", "mjs", "ts", "py", "rs", "c", "h", "cpp", "hpp", "go", "java", "sh", "nix", "qml",
              "json", "toml", "yaml", "yml", "xml", "html", "css", "lua", "rb", "php", "kdl"]
    },
    spreadsheet: {
        icon: "file-spreadsheet", label: "Spreadsheet",
        ext: ["xls", "xlsx", "ods", "csv"]
    },
    document: {
        icon: "file-text", label: "Document",
        ext: ["pdf", "doc", "docx", "odt", "rtf", "epub", "ppt", "pptx", "odp"]
    },
    text: {
        icon: "file-text", label: "Text",
        ext: ["txt", "md", "log", "conf", "ini", "cfg", "org", "rst"]
    }
}

const byExt = {}
for (const kind in kinds)
    for (const ext of kinds[kind].ext) byExt[ext] = kind

// Files' Recent place (Recents.qml): not a folder, though a window keeps it
// as its folder.
var recentPath = "recent:///"

function extension(name) {
    const i = name.lastIndexOf(".")
    return i > 0 ? name.slice(i + 1).toLowerCase() : ""
}

// "image", "video", ... or "file" (unknown); folders are "folder".
function kindOf(name, isDir) {
    if (isDir) return "folder"
    return byExt[extension(name)] || "file"
}

function iconOf(kind) {
    return kind === "folder" ? "folder" : kinds[kind] ? kinds[kind].icon : "file"
}

// What the list's Kind column says: "PNG image", "Archive", "DEB file"…
function kindLabel(name, isDir) {
    const kind = kindOf(name, isDir)
    const ext = extension(name).toUpperCase()
    if (kind === "folder") return "Folder"
    if (kind === "image" || kind === "video" || kind === "audio" || kind === "font") return ext + " " + kinds[kind].label
    if (kinds[kind]) return kinds[kind].label
    return ext ? ext + " file" : "File"
}

// Decimal units, like macOS and GNOME: 1 KB = 1000 bytes.
function humanSize(bytes) {
    if (bytes < 1000) return bytes === 1 ? "1 byte" : bytes + " bytes"
    const units = ["KB", "MB", "GB", "TB"]
    let value = bytes / 1000
    let i = 0
    while (value >= 1000 && i < units.length - 1) {
        value /= 1000
        i++
    }
    return (value < 10 ? value.toFixed(1) : Math.round(value)) + " " + units[i]
}

// "Today 14:32", "Yesterday 09:10", "Sep 12 14:32" (this year), "Sep 12, 2025".
// timeFormat: the bar clock's hours ("hh:mm" or "h:mm AP").
function shortDate(date, timeFormat) {
    const now = new Date()
    const day = d => new Date(d.getFullYear(), d.getMonth(), d.getDate()).getTime()
    const days = Math.round((day(now) - day(date)) / 86400000)
    const time = Qt.formatTime(date, timeFormat)
    if (days === 0) return "Today " + time
    if (days === 1) return "Yesterday " + time
    if (date.getFullYear() === now.getFullYear()) return Qt.formatDate(date, "MMM d") + " " + time
    return Qt.formatDate(date, "MMM d, yyyy")
}

function baseName(path) {
    return path === "/" ? "/" : path.slice(path.lastIndexOf("/") + 1)
}

function parentOf(path) {
    return path.slice(0, path.lastIndexOf("/")) || "/"
}

// The URI GLib writes for a path (and so Thunar, tumbler and GTK): the
// freedesktop thumbnail cache names each thumbnail after the MD5 of this
// string, so it has to be byte for byte the same. encodeURI escapes almost
// the same characters; GLib also escapes these three.
function fileUri(path) {
    return "file://" + encodeURI(path).replace(/[?#;]/g, c => "%" + c.charCodeAt(0).toString(16).toUpperCase())
}

// The URL for a FolderListModel's folder. Qt (6.11, and still in its dev
// branch) decodes the URL to a path and then reads that path as a URL once
// more: a "#" or "?" cut it short and a "%41" became "A", so "C# stuff" listed
// the folder "C" next to it, and what was done to the files shown was done to
// C's. With "%", "#" and "?" encoded once more, both readings leave the right
// path (any other path gets fileUri's URL). Not at the model's creation,
// though: until it's complete, it checks the path read once, doesn't find it
// and lists the working folder instead.
function folderUri(path) {
    return fileUri(path.replace(/[%#?]/g, c => encodeURIComponent(c)))
}

// Whether folderUri has to wait for the model to be complete.
function oddFolder(path) {
    return /[%#?]/.test(path)
}

// What "Extract here" opens (bsdtar reads them all; a lone .gz or .xz is a
// compressed file, not an archive) and the name it extracts to.
const archiveTail = /\.(zip|7z|rar|tar|tgz|tbz2?|txz|tzst|tar\.(gz|bz2|xz|zst))$/i

function extractable(name) {
    return archiveTail.test(name)
}

// "photos.tar.gz" -> "photos".
function archiveBase(name) {
    return name.replace(archiveTail, "") || name
}

// A file's name without its extension ("report.pdf" -> "report"); one that
// starts with its only dot (".bashrc") stays as it is.
function stem(name) {
    const dot = name.lastIndexOf(".")
    return dot > 0 ? name.slice(0, dot) : name
}

// Already compressed: an archive other than a plain .tar. Zipping it alone
// again gains nothing.
function compressed(name) {
    return extractable(name) && !/\.tar$/i.test(name)
}

// Names in natural order, ignoring case: "img2" before "img10", like the
// folder's sorting (QML's localeCompare takes no options).
function naturalCompare(a, b) {
    const x = a.toLowerCase().match(/\d+|\D+/g) || []
    const y = b.toLowerCase().match(/\d+|\D+/g) || []
    for (let i = 0; i < Math.min(x.length, y.length); i++) {
        if (x[i] === y[i]) continue
        if (/^\d/.test(x[i]) && /^\d/.test(y[i]))
            return Number(x[i]) - Number(y[i]) || x[i].length - y[i].length
        return x[i] < y[i] ? -1 : 1
    }
    return x.length - y.length
}
