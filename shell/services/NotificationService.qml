import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Notifications

// Notification server (org.freedesktop.Notifications): receives them from
// every app, shows them as popups (NotificationPopups.qml) and keeps a
// history for the Control Center (CcNotifications.qml).
//
// There can only be one server per session: if another program already owns
// the name (mako, dunst, another shell), notifications go to it.
Scope {
    id: root

    property string stateDir: ""
    // Do not disturb: no popups (except critical ones); they still go to the
    // history.
    property bool dnd: false

    // History, newest first: [{ key, appName, appIcon, image, summary, body,
    // urgency, time, live }]. `live` is the Notification while the app hasn't
    // closed it (needed for the actions).
    property var history: []
    // Keys of the ones shown as popups.
    property var popups: []

    // Seen up to when (ms): opening the Notifications page marks everything as
    // seen. The newer ones are the pending ones (the bell's dot).
    property real seenAt: 0
    readonly property int unread: history.filter(e => e.time > seenAt).length

    function markSeen(): void {
        if (unread === 0) return
        seenAt = Date.now()
        saveTimer.restart()
    }

    readonly property int maxHistory: 100
    readonly property string file: stateDir + "/notifications.json"

    NotificationServer {
        keepOnReload: true
        bodySupported: true
        bodyMarkupSupported: false
        actionsSupported: true
        imageSupported: true
        persistenceSupported: true

        onNotification: (n) => root.add(n)
    }

    function add(n: var): void {
        n.tracked = true
        const entry = {
            key: "n" + Date.now() + "-" + n.id,
            appName: n.appName || "",
            appIcon: n.appIcon || "",
            image: n.image || "",
            summary: n.summary || "",
            body: n.body || "",
            urgency: n.urgency,
            time: Date.now(),
            live: n
        }
        // If the app closes it, it stays in the history but without actions. Not
        // the ones being removed (removeMany): otherwise each one rebuilt the whole
        // history again.
        n.closed.connect(() => {
            entry.live = null
            if (entry.removed) return
            root.popups = root.popups.filter(k => k !== entry.key)
            root.history = root.history.slice()
        })
        const all = [entry].concat(history)
        // The ones pushed out of the history by the cap: released (as if they
        // expired). Otherwise they stayed alive in memory, with their images, as
        // long as the app didn't close them.
        for (const old of all.slice(maxHistory)) {
            old.removed = true
            if (old.live) old.live.expire()
        }
        history = all.slice(0, maxHistory)
        if (!dnd || n.urgency === NotificationUrgency.Critical)
            popups = [entry.key].concat(popups).slice(0, 5)
        saveTimer.restart()
    }

    function find(key: string): var {
        return history.find(e => e.key === key) ?? null
    }

    // The popup goes away (it stays in the history).
    function hidePopup(key: string): void {
        popups = popups.filter(k => k !== key)
    }

    // Out of the history (and closed for the app).
    function remove(key: string): void {
        removeMany([key])
    }

    // Removes several at once (Clear, Clear all): a single history change.
    // Removing them one by one rebuilt the whole page (groups, counters, rows)
    // for each notification, and with many it took a long time.
    function removeMany(keys: var): void {
        const gone = new Set(keys)
        const kept = []
        for (const e of history) {
            if (!gone.has(e.key)) {
                kept.push(e)
                continue
            }
            e.removed = true
            if (e.live) e.live.dismiss()
        }
        history = kept
        popups = popups.filter(k => !gone.has(k))
        saveTimer.restart()
    }

    function clear(): void {
        removeMany(history.map(e => e.key))
    }

    // Notification action ("default" = click on the card).
    // Click on a notification (action = null) or one of its buttons. The click
    // also takes you to the app's window (focusApp): the default action alone
    // isn't enough, because niri doesn't let an app bring itself to the front
    // without an activation token, and the server doesn't give it one.
    function invoke(key: string, action: var): void {
        const e = find(key)
        if (!e) return
        if (e.live) {
            const a = action ?? e.live.actions.find(x => x.identifier === "default")
            if (a) a.invoke()
        }
        if (!action) focusApp(e)
        hidePopup(key)
    }

    // Window of the app that sent the notification: the ones with its app_id
    // and, among them, the one niri marks as urgent, then the one with the
    // notification's text in its title, then the one showing "waiting" (✳,
    // that's how Claude Code marks it in the terminal) and otherwise the last
    // used.
    // The open windows (Compositor.qml), to go to the app's window.
    property Compositor compositor: null

    function focusApp(e: var): void {
        if (!compositor) return
        const w = pickWindow(compositor.windows, e)
        if (w) compositor.focusWindow(w)
    }

    function pickWindow(windows: var, e: var): var {
        const app = (e.appName || "").toLowerCase()
        const desktop = app ? DesktopEntries.heuristicLookup(e.appName) : null
        const ids = [app, desktop ? String(desktop.id).toLowerCase().replace(/\.desktop$/, "") : ""].filter(s => s)
        const candidates = windows.filter(w => w.appId && ids.includes(w.appId.toLowerCase()))
        if (!candidates.length) return null
        const text = ((e.summary || "") + " " + (e.body || "")).toLowerCase()
        const score = w => {
            const title = (w.title || "").toLowerCase().trim()
            let s = 0
            if (w.urgent) s += 8
            if (title.length > 3 && (text.includes(title) || (e.summary && title.includes(e.summary.toLowerCase())))) s += 4
            if (title.startsWith("✳")) s += 2
            return s
        }
        return candidates.sort((a, b) => score(b) - score(a) || b.lastFocused - a.lastFocused)[0]
    }

    function toggleDnd(): void {
        dnd = !dnd
        if (dnd) popups = popups.filter(k => { const e = find(k); return e && e.urgency === NotificationUrgency.Critical })
        saveTimer.restart()
    }

    // --- History on disk (without the live Notifications or temporary images) ---

    Timer {
        id: saveTimer
        interval: 1000
        onTriggered: writer.setText(JSON.stringify({
            dnd: root.dnd,
            seenAt: root.seenAt,
            history: root.history.map(e => ({
                key: e.key, appName: e.appName, appIcon: e.appIcon, summary: e.summary, body: e.body,
                urgency: e.urgency, time: e.time,
                // Only images that are files: the others don't exist afterward.
                image: e.image.startsWith("/") || e.image.startsWith("file:") ? e.image : ""
            }))
        }))
    }

    // With FileView (tmp + rename) rather than passing the JSON as a process
    // argument: an argument can't exceed 128 KB, and with 100 long
    // notifications the history stopped being saved. No preload: it only writes
    // (the FileView below reads, once at startup).
    FileView {
        id: writer
        path: root.stateDir ? root.file : ""
        preload: false
        onSaveFailed: console.warn("Notifications: could not save the history to " + root.file)
    }

    FileView {
        path: root.stateDir ? root.file : ""
        onLoaded: {
            try {
                const saved = JSON.parse(text())
                root.dnd = saved.dnd === true
                root.seenAt = Number(saved.seenAt) || 0
                // The ones that arrived before the file was read, on top.
                const old = (saved.history || []).map(e => Object.assign({ live: null }, e))
                root.history = root.history.concat(old).slice(0, root.maxHistory)
            } catch (e) {}
        }
    }
}
