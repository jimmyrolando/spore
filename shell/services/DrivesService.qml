import QtQuick
import Quickshell
import Quickshell.Io
import "../common/session.js" as Session

// External drives (USB and other hotplug), for the bar widget, the Control
// Center's Drives page and Files; and, for Files only, the internal disks'
// volumes (`internal`). The data comes from lsblk; `udisksctl
// monitor` reports when something is plugged in, mounted or unplugged, and
// only then is it read again (no polling). Automounting is still done by
// udiskie; here we mount, unmount and eject with udisksctl.
Scope {
    id: root

    // [{ path: "/dev/sdb", name: "Samsung Portable SSD T5", transport: "USB",
    //    size, volumes: [{ path, label, fstype, size, mountpoint, used, total }] }]
    property var drives: []
    // Per disk (path): "" or the message of the last action ("Busy: ...").
    property var messages: ({})
    // Disk with an action in progress ("" = none).
    property string working: ""
    // Name of the last ejected disk: its card disappears, so the page shows the
    // "safe to unplug" message separately.
    property string lastEjected: ""

    readonly property int count: drives.length

    // The internal disks' volumes worth opening (Files' sidebar; the bar and
    // the Control Center only show `drives`): [{ disk, path, label, fstype,
    // size, mountpoint, target, system }]. Not the ones only the system uses:
    // boot (EFI), swap, Windows' reserved and recovery ones, containers
    // (LUKS, LVM, RAID; their volumes inside do show) and small unmounted
    // ones. target: where /etc/fstab mounts it ("" = not there); system: it's
    // "/".
    property var internal: []

    Process {
        id: reader
        running: true
        command: ["lsblk", "-J", "-b", "-e7", "-o",
            "NAME,PATH,TYPE,TRAN,HOTPLUG,SIZE,FSTYPE,LABEL,MODEL,VENDOR,MOUNTPOINTS,FSUSED,FSSIZE,UUID,PARTTYPENAME"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const devices = JSON.parse(text).blockdevices || []
                    root.drives = root.parse(devices)
                    root.internal = root.parseInternal(devices)
                } catch (e) {
                    console.warn("Drives: could not read lsblk:", e)
                }
            }
        }
    }

    // Where fstab mounts each volume (by UUID, label or device): an internal
    // one that's in fstab is opened there (an automount mounts it when it's
    // entered) instead of being mounted again by udisks somewhere else.
    property var fstab: ({})

    FileView {
        path: "/etc/fstab"
        printErrors: false
        onLoaded: {
            const map = {}
            for (const line of text().split("\n")) {
                const fields = line.trim().split(/\s+/)
                if (fields.length < 2 || fields[0].startsWith("#")) continue
                // Spaces are \040 in fstab.
                const target = fields[1].replace(/\\040/g, " ")
                if (target === "none" || !target.startsWith("/")) continue
                map[fields[0].replace(/\\040/g, " ")] = target
            }
            root.fstab = map
            root.refresh()
        }
    }

    function fstabTarget(volume: var): string {
        const keys = [volume.path]
        if (volume.uuid) keys.push("UUID=" + volume.uuid, "/dev/disk/by-uuid/" + volume.uuid)
        if (volume.label) keys.push("LABEL=" + volume.label, "/dev/disk/by-label/" + volume.label)
        for (const key of keys) {
            if (fstab[key]) return fstab[key]
        }
        return ""
    }

    function parseInternal(devices: var): var {
        const hiddenTypes = ["EFI System", "Microsoft reserved", "Windows recovery environment", "BIOS boot", "Linux swap"]
        const containers = ["swap", "crypto_LUKS", "LVM2_member", "linux_raid_member", "zfs_member"]
        const out = []
        // The volumes are the leaves: a partition, or what's inside an unlocked
        // LUKS or an LVM.
        const leaves = (device, into) => {
            if (device.children && device.children.length) {
                for (const child of device.children) leaves(child, into)
            } else {
                into.push(device)
            }
        }
        for (const d of devices) {
            if (d.type !== "disk" || d.hotplug) continue
            const found = []
            leaves(d, found)
            for (const v of found) {
                if (!v.fstype || containers.includes(v.fstype) || hiddenTypes.includes(v.parttypename)) continue
                const mounts = (v.mountpoints || []).filter(m => m && m !== "[SWAP]")
                // A root filesystem also shows up as its bind mounts (/nix/store).
                const mountpoint = mounts.includes("/") ? "/" : mounts[0] || ""
                if (["/boot", "/boot/efi", "/efi"].includes(mountpoint)) continue
                const target = fstabTarget(v)
                if (!mountpoint && !target && v.size < 1073741824) continue
                out.push({
                    disk: d.path,
                    path: v.path,
                    label: v.label || "",
                    fstype: v.fstype,
                    size: v.size,
                    mountpoint: mountpoint,
                    target: target,
                    system: mountpoint === "/"
                })
            }
        }
        // "/" first.
        return out.sort((a, b) => b.system - a.system)
    }

    function refresh(): void {
        if (!reader.running) reader.running = true
        else refreshLater.restart()
    }

    // A udisks event arrives in a burst (several lines): a single read.
    Timer {
        id: refreshLater
        interval: 400
        onTriggered: root.refresh()
    }

    Process {
        id: monitor
        running: true
        // Dies with the shell (setpriv --pdeathsig): otherwise every restart left
        // one alive.
        command: ["setpriv", "--pdeathsig", "TERM", "udisksctl", "monitor"]
        stdout: SplitParser {
            onRead: refreshLater.restart()
        }
        // If udisks restarts, the monitor stops: open it again.
        onExited: restartMonitor.restart()
    }

    Timer {
        id: restartMonitor
        interval: 3000
        onTriggered: monitor.running = true
    }

    // Used space changes without udisks events: re-read it every so often while
    // there's an external disk.
    Timer {
        interval: 30000
        running: root.count > 0
        repeat: true
        onTriggered: root.refresh()
    }

    // Only external disks (hotplug). Their volumes: the ones with a filesystem,
    // except small unmounted partitions (the 200 MB EFI one many disks ship
    // with) that only add noise.
    function parse(devices: var): var {
        const out = []
        for (const d of devices) {
            if (d.type !== "disk" || !d.hotplug) continue
            const parts = (d.children && d.children.length) ? d.children : [d]
            const volumes = parts
                .filter(p => p.fstype && p.fstype !== "swap")
                .map(p => ({
                    path: p.path,
                    label: p.label || "",
                    fstype: p.fstype,
                    size: p.size,
                    mountpoint: (p.mountpoints || []).find(m => m) || "",
                    used: p.fsused ?? -1,
                    total: p.fssize ?? -1
                }))
                .filter(v => v.mountpoint !== "" || v.size >= 1073741824)
            out.push({
                path: d.path,
                name: (d.model || [d.vendor, d.label].filter(s => s).join(" ") || d.name).trim(),
                transport: (d.tran || "").toUpperCase(),
                size: d.size,
                volumes: volumes
            })
        }
        return out
    }

    // --- Actions ---

    function setMessage(disk: string, text: string): void {
        const m = Object.assign({}, messages)
        m[disk] = text
        messages = m
    }

    // One process at a time: the script runs and, if it fails, its stderr
    // becomes the disk's message.
    Process {
        id: action
        property string disk: ""
        property string done: ""
        stderr: StdioCollector {
            id: actionErr
        }
        onExited: (code) => {
            const err = actionErr.text.trim().split("\n").pop() || ""
            if (code === 0 && done === "Safe to remove") {
                const d = root.drives.find(x => x.path === disk)
                root.lastEjected = d ? d.name : disk
            }
            root.setMessage(disk, code === 0 ? done
                : /busy/i.test(err) ? "Busy: close the files and apps using it"
                : err.replace(/^Error [^:]*: /, "") || "Something went wrong")
            root.working = ""
            root.refresh()
        }
    }

    function run(disk: string, script: string, done: string, args: var): void {
        if (action.running) return
        lastEjected = ""
        working = disk
        setMessage(disk, "")
        action.disk = disk
        action.done = done
        action.command = ["sh", "-c", script, "_"].concat(args)
        action.running = true
    }

    function mount(disk: string, volume: string): void {
        run(disk, 'udisksctl mount --no-user-interaction -b "$1" >/dev/null', "", [volume])
    }

    function unmount(disk: string, volume: string): void {
        run(disk, 'udisksctl unmount --no-user-interaction -b "$1" >/dev/null', "", [volume])
    }

    // Unmounts everything mounted from the disk and powers it off: then it can
    // be unplugged.
    function eject(disk: string): void {
        const drive = drives.find(d => d.path === disk)
        const mounted = drive ? drive.volumes.filter(v => v.mountpoint).map(v => v.path) : []
        run(disk, `
            disk=$1; shift
            for v in "$@"; do udisksctl unmount --no-user-interaction -b "$v" >/dev/null || exit 1; done
            udisksctl power-off --no-user-interaction -b "$disk"`,
            "Safe to remove", [disk].concat(mounted))
    }

    // In the file manager the user has, as an app (session.js). With gio:
    // outside GNOME and KDE, xdg-open asks perl's mimetype, which calls a
    // mount point inode/mount-point, a type with no app, and it opened the
    // web browser instead. gio says inode/directory, a folder's.
    function open(mountpoint: string): void {
        Quickshell.execDetached(Session.command(["gio", "open", mountpoint]))
    }
}
