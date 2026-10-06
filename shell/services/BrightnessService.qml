import QtQuick
import Quickshell
import Quickshell.Io

// The screens' brightness, for the Control Center: external monitors over
// DDC/CI (ddcutil, which needs the i2c devices: hardware.i2c.enable on
// NixOS) and a laptop's own screen (its backlight, /sys/class/backlight).
//
// Nothing runs in the background: the monitors are found when the shell
// starts (and again when one is plugged in or out), so the Control Center
// opens with its rows, and the brightness is read again when it opens. A monitor takes about a third of a second to
// answer, so a slider being dragged sends only its latest value, one at a
// time.
QtObject {
    id: root

    // For the test (tools/test.sh): a fake ddcutil and backlight folder.
    readonly property string ddcutil: Quickshell.env("SPORE_DDCUTIL") || "ddcutil"
    readonly property string backlightDir: Quickshell.env("SPORE_BACKLIGHT_DIR") || "/sys/class/backlight"

    // The screens there are, left to right: [{ id, kind ("ddc" or
    // "backlight"), target (the I2C bus or the backlight device), label (the
    // monitor\x27s model), max, value (0..1) }].
    property var displays: []

    // The monitors ddcutil found: [{ bus, connector ("DP-4"), model }].
    property var monitors: []
    property bool detected: false

    // Plugging a monitor in or out: found again next time.
    property Connections screens: Connections {
        target: Quickshell
        function onScreensChanged() {
            root.detected = false
            root.refresh()
        }
    }

    Component.onCompleted: refresh()

    function refresh(): void {
        if (reader.busy) {
            reader.again = true
            return
        }
        reader.busy = true
        const args = root.detected ? [].concat(...monitors.map(m => [m.bus, m.connector, m.model])) : ["detect"]
        reader.command = ["sh", "-c", readScript, "_", ddcutil, backlightDir].concat(args)
        reader.running = true
    }

    // $1 ddcutil, $2 the backlight folder, then "detect" or the monitors
    // already found (bus, connector, model). Prints
    // "ddc\t<bus>\t<connector>\t<model>\tVCP 10 C <value> <max>" for each
    // monitor that answers, and "backlight\t<device>\t<value>\t<max>".
    readonly property string readScript: `
        ddc=$1 dir=$2
        shift 2
        if [ "$1" = detect ]; then
            shift
            set -- $("$ddc" detect --brief 2>/dev/null | awk -F': *' '
                function done() { if (ok && bus != "" && con != "") printf "%s %s %s ", bus, con, model }
                /^Display [0-9]/ { done(); ok = 1; bus = ""; con = ""; model = ""; next }
                /^Invalid display/ { done(); ok = 0; next }
                /I2C bus:/ { bus = $2; sub(/.*i2c-/, "", bus) }
                /DRM connector:/ { con = $2; sub(/^card[0-9]+-/, "", con) }
                # "HPN:HP 524pf:CNK4351R2R": maker, model, serial.
                /Monitor:/ {
                    v = $0; sub(/^[^:]*: */, "", v); split(v, m, ":")
                    model = m[2] == "" ? "-" : m[2]; gsub(/ /, "_", model)
                }
                END { done() }')
        fi
        while [ $# -ge 3 ]; do
            (
                v=$("$ddc" getvcp 10 --bus "$1" --brief 2>/dev/null) &&
                    printf "ddc\\t%s\\t%s\\t%s\\t%s\\n" "$1" "$2" "$3" "$v"
            ) &
            shift 3
        done
        for d in "$dir"/*; do
            [ -r "$d/max_brightness" ] && [ -r "$d/brightness" ] || continue
            printf "backlight\\t%s\\t%s\\t%s\\n" "\${d##*/}" "$(cat "$d/brightness")" "$(cat "$d/max_brightness")"
        done
        wait`

    property Process reader: Process {
        // From the start until its answer is read; and a refresh asked for
        // meanwhile.
        property bool busy: false
        property bool again: false
        stdout: StdioCollector {
            onStreamFinished: {
                root.read(text)
                root.reader.busy = false
                if (!root.reader.again) return
                root.reader.again = false
                root.refresh()
            }
        }
    }

    function read(text: string): void {
        const found = []
        const ddc = []
        for (const line of text.split("\n")) {
            const f = line.split("\t")
            if (f[0] === "ddc" && f.length >= 5) {
                // "VCP 10 C 64 100"
                const v = f[4].trim().split(/\s+/)
                const value = Number(v[3]), max = Number(v[4])
                if (v[0] !== "VCP" || !(max > 0)) continue
                const model = f[3] === "-" ? "" : f[3].replace(/_/g, " ")
                ddc.push({ bus: f[1], connector: f[2], model: f[3] })
                found.push({ id: "ddc:" + f[1], kind: "ddc", target: f[1], connector: f[2],
                    label: model || f[2], max: max, value: value / max })
            } else if (f[0] === "backlight" && f.length >= 4) {
                const value = Number(f[2]), max = Number(f[3])
                if (!(max > 0)) continue
                found.push({ id: "backlight:" + f[1], kind: "backlight", target: f[1], connector: "",
                    label: builtInName(), max: max, value: value / max })
            }
        }
        if (!detected) {
            monitors = ddc
            detected = true
        }
        // Only this session\x27s screens, in their order on the desk; a laptop\x27s
        // own one first.
        const x = {}
        for (const s of Quickshell.screens) x[s.name] = s.x
        displays = found.filter(d => d.kind === "backlight" || d.connector in x)
            .sort((a, b) => (a.kind === "backlight" ? -1e9 : x[a.connector]) - (b.kind === "backlight" ? -1e9 : x[b.connector]))
    }

    // A laptop\x27s own screen ("eDP-1"): its model if niri says it, or else.
    function builtInName(): string {
        for (const s of Quickshell.screens) {
            if (s.name.startsWith("eDP") && s.model) return s.model
        }
        return "Built-in display"
    }

    // --- Setting it ---

    // id -> the raw value still to send.
    property var pending: ({})

    // `value` 0..1. A backlight never goes to 0: it turns the screen off.
    function set(id: string, value: real): void {
        const d = displays.find(d => d.id === id)
        if (!d) return
        const raw = Math.round(Math.max(d.kind === "backlight" ? 0.05 : 0, Math.min(1, value)) * d.max)
        const next = Object.assign({}, pending)
        next[id] = raw
        pending = next
        if (!writer.running) writeNext()
    }

    function writeNext(): void {
        const id = Object.keys(pending)[0]
        if (id === undefined) return
        const d = displays.find(d => d.id === id)
        const raw = pending[id]
        const next = Object.assign({}, pending)
        delete next[id]
        pending = next
        if (!d) {
            writeNext()
            return
        }
        writer.command = ["sh", "-c", writeScript, "_", ddcutil, backlightDir, d.kind, d.target, String(raw)]
        writer.running = true
    }

    // $1 ddcutil, $2 the backlight folder, $3 the kind, $4 its bus or device,
    // $5 the value. A backlight the user can\x27t write to goes through logind,
    // which lets the session\x27s user set it.
    readonly property string writeScript: `
        if [ "$3" = ddc ]; then
            exec "$1" setvcp 10 "$5" --bus "$4" --noverify
        elif [ -w "$2/$4/brightness" ]; then
            printf "%s" "$5" > "$2/$4/brightness"
        else
            exec busctl call org.freedesktop.login1 /org/freedesktop/login1/session/auto \\
                org.freedesktop.login1.Session SetBrightness ssu backlight "$4" "$5"
        fi`

    property Process writer: Process {
        onExited: root.writeNext()
    }
}
