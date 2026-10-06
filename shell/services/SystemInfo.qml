import QtQuick
import Quickshell
import Quickshell.Io

// Machine and system data for About (AboutPanel.qml), fastfetch style. Read
// when the shell starts and refreshed in the background each time About
// opens: that way the panel shows up already filled (reading them on open
// took ~0.5 s, mostly counting packages, and the card grew all at once).
Scope {
    id: root

    // What the script outputs (see `reader`).
    property var info: ({})
    // The compositor (Compositor.qml): name, version and screens.
    property Compositor compositor: null
    readonly property string wm: compositor && compositor.version ? compositor.name + " " + compositor.version : ""

    function refresh(): void {
        if (!reader.running) reader.running = true
        if (compositor) compositor.refreshOutputs()
    }

    Process {
        id: reader
        running: true
        command: ["sh", "-c", `
            . /etc/os-release; echo "os\t$PRETTY_NAME"
            nixos-version --json 2>/dev/null | tr -d '{}"' | tr ',' '\\n' | sed 's/:/\\t/' | sed 's/^/nix_/'
            echo "user\t$(id -un)@$(cat /etc/hostname 2>/dev/null || uname -n)"
            echo "kernel\tLinux $(uname -r)"
            echo "shell\t$(basename "\${SHELL:-sh}")"
            echo "terminal\t\${TERMINAL:-}"
            echo "cpu\t$(awk -F': ' '/^model name/ { print $2; exit }' /proc/cpuinfo)"
            for d in /sys/class/drm/card*/device; do
                [ -r "$d/gpu_busy_percent" ] || continue
                v=$(cut -c3- "$d/vendor"); p=$(cut -c3- "$d/device")
                drv=$(basename "$(readlink "$d/driver")")
                name=""
                [ -r "$SPORE_PCI_IDS" ] && name=$(awk -v v="$v" -v p="$p" '$1 == v { in_v = 1; vendor = substr($0, 7); next } in_v && /^\\t[0-9a-f]/ && $1 == p { sub(/^\\t[0-9a-f]+ +/, ""); print; exit } /^[0-9a-f]/ { in_v = 0 }' "$SPORE_PCI_IDS")
                echo "gpu\t$name\t$v\t$drv"
                break
            done
            echo "pkgs_system\t$(nix-store -qR /run/current-system 2>/dev/null | wc -l)"
            echo "pkgs_user\t$(nix-store -qR "/etc/profiles/per-user/$(id -un)" 2>/dev/null | wc -l)"
            df -B1 --output=used,size / | awk 'NR == 2 { print "disk\\t" $1 "\\t" $2 }'`]
        stdout: StdioCollector {
            onStreamFinished: {
                const info = {}
                for (const line of text.split("\n")) {
                    const tab = line.indexOf("\t")
                    // No trim at the start: an empty field (e.g. the GPU name without pci.ids)
                    // is a leading tab that must not be lost.
                    if (tab > 0) info[line.slice(0, tab).trim()] = line.slice(tab + 1).replace(/\s+$/, "")
                }
                root.info = info
            }
        }
    }

    function gib(bytes: real): string {
        return (bytes / 1073741824).toFixed(1)
    }

    // "Intel(R) Core(TM) i7-10700 CPU @ 2.90GHz" -> "Intel Core i7-10700".
    readonly property string cpuName: (info.cpu || "")
        .replace(/\((R|TM)\)/g, "").replace(/ CPU @.*$/, "").replace(/ \d+-Core.*$/, "").replace(/ Processor$/, "").replace(/\s+/g, " ").trim()

    // "Navi 24 [Radeon PRO W6400]" -> "AMD Radeon PRO W6400"; without pci.ids,
    // the vendor and the driver.
    readonly property string gpuName: {
        const [name, vendor, driver] = (info.gpu || "").split("\t")
        const brand = ({ "1002": "AMD", "10de": "NVIDIA", "8086": "Intel" })[vendor] || ""
        const model = name ? (name.match(/\[(.*)\]/) || [, name])[1] : ""
        return model ? [brand, model].filter(s => s).join(" ") : [brand || "GPU", driver ? "(" + driver + ")" : ""].join(" ").trim()
    }

    readonly property string display: {
        const outputs = compositor ? compositor.outputs : []
        return outputs.map(o => o.width + "×" + o.height + " @ " + Math.round(o.refresh) + " Hz"
            + (o.scale !== 1 ? " · ×" + o.scale : "")).join(", ")
    }

    // "26.05.20260922.1bc55b9" -> "1bc55b9 · Sep 22, 2026".
    readonly property string nixpkgs: {
        const rev = (info.nix_nixpkgsRevision || "").slice(0, 7)
        const m = (info.nix_nixosVersion || "").match(/\.(\d{4})(\d{2})(\d{2})\./)
        const date = m ? Qt.formatDate(new Date(Number(m[1]), Number(m[2]) - 1, Number(m[3])), "MMM d, yyyy") : ""
        return [rev, date].filter(s => s).join(" · ")
    }

}
