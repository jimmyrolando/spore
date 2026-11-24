import QtQuick
import Quickshell
import Quickshell.Services.Notifications
import "../common/session.js" as Session

// Receiving files with LocalSend: the LocalSend app on an iPhone, a Mac or
// Android sends straight to this computer, which shows up in its list by
// the name in Settings (localsend.name, or the computer's). spored does the
// protocol (spored/localsend.go); here are its questions and news, as the
// shell's own notifications:
//
// - "iPhone wants to send 3 files": Accept or Decline. It waits for an
//   answer two minutes at most, and one request at a time.
// - While they come: how much has come, and Cancel.
// - "Received 3 files from iPhone": Show in Files (the folder,
//   localsend.folder, with them selected).
// - A message (text sent from the app): the text, and Copy.
//
// Off unless localsend.enabled is true: it's a server on the network
// (port 53317, TCP and UDP, which the firewall has to let in). In a nested
// test session it's on only with SPORE_LOCALSEND_PORT, on 127.0.0.1.
Scope {
    id: root

    required property Settings settings
    required property NotificationService notifications
    required property Spored spored
    property string stateDir: ""
    property bool nested: false

    readonly property int testPort: Number(Quickshell.env("SPORE_LOCALSEND_PORT") || 0)
    readonly property bool wanted: settings.localsendEnabled && spored.localsend && stateDir !== ""
        && (!nested || testPort > 0)

    // "off", "on" or "error" (errorMessage says why).
    property string status: "off"
    property string errorMessage: ""
    // The name the others see, once it's on.
    property string alias: ""
    // session id -> { key, from, count, size }.
    property var sessions: ({})
    // The last request's session, for the IPC (accept/decline from a test).
    property string lastSession: ""

    function configure(): void {
        if (!spored.localsend) {
            status = "off"
            return
        }
        spored.localsendOp({
            op: "localsend", enabled: wanted,
            alias: settings.localsendName, folder: settings.localsendFolder, stateDir: stateDir + "/localsend",
            port: nested ? testPort : 0, local: nested
        })
        if (!wanted) status = "off"
    }

    // Once per change, after the settings and spored's hello settle.
    onWantedChanged: Qt.callLater(configure)
    Connections {
        target: root.settings
        function onLocalsendNameChanged() { Qt.callLater(root.configure) }
        function onLocalsendFolderChanged() { Qt.callLater(root.configure) }
    }
    // spored started again: it starts off.
    Connections {
        target: root.spored
        function onLocalsendChanged() { Qt.callLater(root.configure) }
        function onLocalsendEvent(message) { root.heard(message) }
    }

    readonly property string icon: "folder-download"

    function heard(m: var): void {
        const s = sessions[m.session]
        switch (m.kind) {
        case "ready":
            status = "on"
            alias = m.alias || ""
            errorMessage = ""
            console.info("LocalSend: receiving as", alias)
            break
        case "error":
            status = "error"
            // Once per reason, not at each start.
            if (m.message !== errorMessage)
                notifications.post("LocalSend", icon, "Can't receive files", m.message, NotificationUrgency.Normal)
            errorMessage = m.message
            console.warn("LocalSend:", m.message)
            break
        case "request":
            request(m)
            break
        case "progress":
            if (s) notifications.update(s.key, { body: size(m.received) + " of " + size(m.size) }, false)
            break
        case "done":
            if (s) {
                notifications.update(s.key, {
                    summary: "Received " + files(m.count) + " from " + m.from,
                    body: (m.paths || []).map(p => p.slice(p.lastIndexOf("/") + 1)).join(", "),
                    actions: [{ identifier: "show", text: "Show in Files" }],
                    onAction: () => show(m.paths || []),
                    sticky: false
                }, true)
            }
            forget(m.session)
            break
        case "failed":
            if (s) notifications.update(s.key, { summary: m.message, body: "", actions: [], onAction: null, sticky: false }, true)
            else notifications.post("LocalSend", icon, m.message, "", NotificationUrgency.Normal)
            forget(m.session)
            break
        case "declined":
            // Not answered in time (an answer already changed it).
            if (s && !s.answered)
                notifications.update(s.key, { summary: "Didn't receive from " + s.from, body: "No answer in time",
                    actions: [], onAction: null, sticky: false }, false)
            forget(m.session)
            break
        case "text":
            notifications.postWithActions("LocalSend", icon, "Message from " + m.from, m.text, NotificationUrgency.Normal,
                [{ identifier: "copy", text: "Copy" }], (id) => { if (id === "copy") copy(m.text) }, false)
            break
        }
    }

    function request(m: var): void {
        const names = (m.names || []).join(", ") + (m.count > (m.names || []).length ? ", …" : "")
        const key = notifications.postWithActions("LocalSend", icon,
            m.from + " wants to send " + files(m.count),
            names + " · " + size(m.size),
            NotificationUrgency.Normal,
            [{ identifier: "accept", text: "Accept" }, { identifier: "decline", text: "Decline" }],
            (id) => {
                if (id === "accept") answer(m.session, true)
                else if (id === "decline") answer(m.session, false)
            },
            true)
        const next = Object.assign({}, sessions)
        next[m.session] = { key: key, from: m.from, count: m.count, size: m.size, answered: false }
        sessions = next
        lastSession = m.session
    }

    // Accept or Decline (the notification's buttons, or the IPC).
    function answer(session: string, accept: bool): void {
        const s = sessions[session]
        if (!s || s.answered) return
        s.answered = true
        spored.localsendOp({ op: "localsend-answer", session: session, accept: accept })
        if (accept) {
            notifications.update(s.key, {
                summary: "Receiving " + files(s.count) + " from " + s.from,
                body: "0 B of " + size(s.size),
                actions: [{ identifier: "cancel", text: "Cancel" }],
                onAction: (id) => { if (id === "cancel") spored.localsendOp({ op: "localsend-cancel", session: session }) },
                sticky: true
            }, true)
        } else {
            notifications.update(s.key, { summary: "Declined " + files(s.count) + " from " + s.from,
                actions: [], onAction: null, sticky: false }, false)
        }
    }

    function forget(session: string): void {
        if (!(session in sessions)) return
        const next = Object.assign({}, sessions)
        delete next[session]
        sessions = next
    }

    // In the file manager, selected (org.freedesktop.FileManager1: Spore
    // Files through spored, or whichever has the name).
    function show(paths: var): void {
        if (paths.length === 0) return
        // Each part encoded ("#", "?", "'" too): a GVariant list of strings.
        const uris = paths.map(p => "'file://" + p.split("/").map(encodeURIComponent).join("/").replace(/'/g, "%27") + "'")
        Quickshell.execDetached(Session.command(["gdbus", "call", "--session", "--dest", "org.freedesktop.FileManager1",
            "--object-path", "/org/freedesktop/FileManager1", "--method", "org.freedesktop.FileManager1.ShowItems",
            "[" + uris.join(", ") + "]", ""]))
    }

    function copy(text: string): void {
        Quickshell.execDetached(["wl-copy", "--", text])
    }

    function files(n: int): string {
        return n === 1 ? "1 file" : n + " files"
    }

    function size(bytes: real): string {
        const units = ["B", "KB", "MB", "GB", "TB"]
        let i = 0
        while (bytes >= 1000 && i < units.length - 1) {
            bytes /= 1000
            i++
        }
        return (i === 0 || bytes >= 100 ? Math.round(bytes) : bytes.toFixed(1)) + " " + units[i]
    }

    // For the IPC: { status, alias, error, pending }.
    function describe(): string {
        return JSON.stringify({ status: status, alias: alias, error: errorMessage, pending: Object.keys(sessions).length })
    }
}
