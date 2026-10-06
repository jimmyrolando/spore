import QtQuick
import Quickshell
import Quickshell.Io

// Looks up a place by name with Open-Meteo's geocoding (free, no API key) and
// returns its coordinates. Used by SettingsWindow (what you type in
// "Location") and Weather (the time zone's city, if there's no location).
//
//   search("Springfield, IL")      -> Springfield, Illinois
//   search("New York", "America/New_York")
//
// What comes after the comma filters by state/province, country or country
// code (for the US, also the state's abbreviation). With no filter, the
// first result wins (Open-Meteo sorts them by relevance/population).
Scope {
    id: root

    // { name, region, latitude, longitude } or null if nothing was found.
    signal done(var result)

    readonly property bool busy: proc.running

    // If another search arrives while one is running, it runs when it finishes.
    property var pending: null

    function search(text: string, timezone: string): void {
        const q = { text: text, timezone: timezone || "" }
        if (proc.running) {
            pending = q
            return
        }
        start(q)
    }

    function start(q: var): void {
        const parts = q.text.split(",")
        proc.city = parts[0].trim()
        proc.qualifier = parts.slice(1).join(",").trim()
        proc.timezone = q.timezone
        if (proc.city === "") {
            root.done(null)
            return
        }
        proc.running = true
    }

    readonly property var usStates: ({
        AL: "Alabama", AK: "Alaska", AZ: "Arizona", AR: "Arkansas", CA: "California",
        CO: "Colorado", CT: "Connecticut", DE: "Delaware", FL: "Florida", GA: "Georgia",
        HI: "Hawaii", ID: "Idaho", IL: "Illinois", IN: "Indiana", IA: "Iowa",
        KS: "Kansas", KY: "Kentucky", LA: "Louisiana", ME: "Maine", MD: "Maryland",
        MA: "Massachusetts", MI: "Michigan", MN: "Minnesota", MS: "Mississippi", MO: "Missouri",
        MT: "Montana", NE: "Nebraska", NV: "Nevada", NH: "New Hampshire", NJ: "New Jersey",
        NM: "New Mexico", NY: "New York", NC: "North Carolina", ND: "North Dakota", OH: "Ohio",
        OK: "Oklahoma", OR: "Oregon", PA: "Pennsylvania", RI: "Rhode Island", SC: "South Carolina",
        SD: "South Dakota", TN: "Tennessee", TX: "Texas", UT: "Utah", VT: "Vermont",
        VA: "Virginia", WA: "Washington", WV: "West Virginia", WI: "Wisconsin", WY: "Wyoming",
        DC: "District of Columbia"
    })

    function matchesQualifier(r: var, q: string): bool {
        const l = q.toLowerCase()
        const fields = [r.admin1, r.admin2, r.country, r.country_code].filter(f => f)
        if (fields.some(f => f.toLowerCase() === l || f.toLowerCase().startsWith(l)))
            return true
        return r.country_code === "US" && usStates[q.toUpperCase()] === r.admin1
    }

    Process {
        id: proc
        property string city: ""
        property string qualifier: ""
        property string timezone: ""

        command: ["curl", "-sf", "--max-time", "15",
            "https://geocoding-api.open-meteo.com/v1/search?count=20&language=en&format=json&name="
            + encodeURIComponent(city)]
        stdout: StdioCollector {
            onStreamFinished: root.pick(text)
        }
        onExited: (exitCode) => {
            if (exitCode !== 0) root.done(null)
            if (root.pending) {
                const q = root.pending
                root.pending = null
                root.start(q)
            }
        }
    }

    function pick(json: string): void {
        let results = []
        try {
            results = JSON.parse(json).results || []
        } catch (e) {
            // No network or a broken response: onExited already reports if curl failed.
            if (json.trim() !== "") root.done(null)
            return
        }
        if (proc.qualifier !== "")
            results = results.filter(r => matchesQualifier(r, proc.qualifier))
        else if (proc.timezone !== "") {
            // The time zone's city: the one in that zone (there are many "Paris").
            const sameZone = results.filter(r => r.timezone === proc.timezone)
            if (sameZone.length > 0) results = sameZone
        }
        const r = results[0]
        if (!r) {
            root.done(null)
            return
        }
        root.done({
            name: r.name,
            region: [r.admin1, r.country].filter(f => f).join(", "),
            latitude: Math.round(r.latitude * 100) / 100,
            longitude: Math.round(r.longitude * 100) / 100
        })
    }
}
