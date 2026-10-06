import QtQuick
import Quickshell
import Quickshell.Io

// Weather for the lockscreen, from Open-Meteo (free, no API key). Fetched
// at startup and every `interval` ms; if it fails (e.g. no network yet),
// it retries in 30 s, 1 min, 2 min… up to 10 min.
//
// Off until it's turned on in Settings: until then nothing goes online for
// it (Open-Meteo would see the IP address every 30 minutes).
//
// Location (settings.json: lock.weather): the one chosen in Settings
// ({ enabled, location, name, region, latitude, longitude }). If there isn't
// one, the city of the system's time zone (America/New_York -> New York),
// with its coordinates from the system's zone table: no lookup online.
Scope {
    id: root

    // lock.weather from settings.json, or null.
    property var location: null
    // "metric" (°C, km/h) or "imperial" (°F, mph): Open-Meteo converts.
    property string units: "metric"
    readonly property bool imperial: units === "imperial"
    readonly property string temperatureUnit: imperial ? "°F" : "°C"
    readonly property string windUnit: imperial ? "mph" : "km/h"
    property int interval: 30 * 60 * 1000

    // null (nothing chosen yet) is off; enabled: false (from Settings) turns
    // it off without losing the location.
    readonly property bool enabled: location !== null && location.enabled !== false
    readonly property bool hasLocation: location !== null
        && location.latitude !== undefined && location.longitude !== undefined

    // The system's time zone and its city (fallback when there's no location).
    property string timezone: ""
    property var timezonePlace: null

    // What's used: the chosen location or the time zone's.
    readonly property var place: hasLocation ? location : timezonePlace
    // Short name for the lockscreen ("Springfield").
    readonly property string placeName: place ? place.name : ""
    readonly property bool approximate: !hasLocation

    // true once at least one valid response has arrived.
    property bool ready: false

    property real temperature: 0
    property real windSpeed: 0
    property string condition: ""
    // [{ day: "Thu", max: 21, min: 12 }, ...] for the next 3 days.
    property var forecast: []

    // Detail for the Control Center (Weather tab).
    property real feelsLike: 0
    property string windDirection: ""
    property int humidity: 0
    property real uvIndex: 0
    property bool isDay: true
    property int code: 0
    property int todayMax: 0
    property int todayMin: 0
    property string sunrise: ""
    property string sunset: ""
    property int elevation: 0
    property string timezoneName: ""
    // 7 days: [{ day: "Friday", code, condition, max, min }] (0 is today).
    property var daily: []
    // 24 hours: [{ time: "14:00", code, isDay, temperature }].
    property var hourly: []

    // callLater: inside the handler, `enabled`/`place` still have the old value
    // (the binding hasn't been re-evaluated) and the request never went out.
    onPlaceChanged: {
        ready = false
        Qt.callLater(fetch)
    }
    onEnabledChanged: Qt.callLater(fetch)
    onUnitsChanged: {
        ready = false
        Qt.callLater(fetch)
    }

    function fetch(): void {
        if (enabled && place && !fetcher.running) fetcher.running = true
    }
    // If the location was already set on creation, onPlaceChanged doesn't fire.
    Component.onCompleted: Qt.callLater(fetch)

    // When the last good response arrived (ms), and consecutive failures.
    property real lastFetch: 0
    property int failures: 0

    // Every 5 min, check the real time of the last response instead of using an
    // `interval` Timer: a Timer doesn't count suspended time, and after waking
    // up the weather stayed stale for up to half an hour more.
    Timer {
        running: root.enabled
        repeat: true
        interval: 5 * 60 * 1000
        onTriggered: if (Date.now() - root.lastFetch >= root.interval) root.fetch()
    }

    Timer {
        id: retry
        interval: Math.min(10 * 60 * 1000, 30 * 1000 * Math.pow(2, Math.max(0, root.failures - 1)))
        onTriggered: root.fetch()
    }

    // Time zone: timedatectl, or the target of /etc/localtime.
    Process {
        running: true
        command: ["sh", "-c", "timedatectl show -p Timezone --value 2>/dev/null || readlink /etc/localtime | sed 's|.*zoneinfo/||'"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.timezone = text.trim()
                if (root.timezone.includes("/")) zoneTable.running = true
            }
        }
    }

    // $1 the time zone: prints the coordinates of its city from the system's
    // zone table (tzdata's zone1970.tab, ISO 6709: +404251-0740023). Auto
    // mode uses them even with the weather off, so they're never looked up
    // online.
    readonly property string zoneScript: `
        for table in "\${TZDIR:-/etc/zoneinfo}/zone1970.tab" /usr/share/zoneinfo/zone1970.tab; do
            if [ -f "$table" ]; then
                awk -F '\\t' -v zone="$1" '$3 == zone { print $2; exit }' "$table"
                exit
            fi
        done`

    Process {
        id: zoneTable
        command: ["sh", "-c", root.zoneScript, "_", root.timezone]
        stdout: StdioCollector {
            onStreamFinished: {
                // ±DDMM[SS]±DDDMM[SS]: degrees, minutes and maybe seconds.
                const m = text.trim().match(/^([+-])(\d\d)(\d\d)(\d\d)?([+-])(\d\d\d)(\d\d)(\d\d)?$/)
                if (!m) {
                    console.warn("Weather: the time zone " + root.timezone + " isn't in the zone table")
                    return
                }
                const degrees = (sign, d, min, s) => (sign === "-" ? -1 : 1) * (Number(d) + Number(min) / 60 + Number(s || 0) / 3600)
                root.timezonePlace = {
                    // "America/Argentina/Buenos_Aires" -> "Buenos Aires"
                    name: root.timezone.split("/").pop().replace(/_/g, " "),
                    latitude: degrees(m[1], m[2], m[3], m[4]),
                    longitude: degrees(m[5], m[6], m[7], m[8]),
                    timezone: root.timezone
                }
            }
        }
    }

    Process {
        id: fetcher
        command: ["curl", "-sf", "--max-time", "15",
            "https://api.open-meteo.com/v1/forecast"
            + "?latitude=" + (root.place ? root.place.latitude : 0)
            + "&longitude=" + (root.place ? root.place.longitude : 0)
            + "&current=temperature_2m,apparent_temperature,relative_humidity_2m,wind_speed_10m,wind_direction_10m,weather_code,is_day,uv_index"
            + "&daily=temperature_2m_max,temperature_2m_min,weather_code,sunrise,sunset"
            + "&hourly=temperature_2m,weather_code,is_day&forecast_hours=24"
            + "&timezone=auto&forecast_days=7"
            + (root.imperial ? "&temperature_unit=fahrenheit&wind_speed_unit=mph" : "")]
        stdout: StdioCollector {
            onStreamFinished: root.parse(text)
        }
        // No network or a server error (curl -f): try again in a while.
        onExited: (code) => {
            if (code === 0) return
            root.failures++
            retry.restart()
        }
    }

    function parse(json: string): void {
        let d
        try {
            d = JSON.parse(json)
        } catch (e) {
            // No network or a broken response: keep the last data we had.
            return
        }
        if (!d.current || !d.daily) return
        temperature = d.current.temperature_2m
        windSpeed = d.current.wind_speed_10m
        condition = describe(d.current.weather_code)
        const days = []
        // Index 0 is today: the forecast shows the next 3.
        for (let i = 1; i < d.daily.time.length && days.length < 3; i++) {
            // Noon: without a time, Date takes it as UTC and in the Americas it falls
            // on the previous day.
            const date = new Date(d.daily.time[i] + "T12:00:00")
            days.push({
                day: Qt.formatDate(date, "ddd"),
                max: Math.round(d.daily.temperature_2m_max[i]),
                min: Math.round(d.daily.temperature_2m_min[i])
            })
        }
        forecast = days

        feelsLike = d.current.apparent_temperature
        humidity = d.current.relative_humidity_2m
        windDirection = compass(d.current.wind_direction_10m)
        uvIndex = d.current.uv_index
        isDay = d.current.is_day === 1
        code = d.current.weather_code
        todayMax = Math.round(d.daily.temperature_2m_max[0])
        todayMin = Math.round(d.daily.temperature_2m_min[0])
        // "2026-09-24T07:03" -> "07:03"
        sunrise = (d.daily.sunrise[0] || "").slice(11, 16)
        sunset = (d.daily.sunset[0] || "").slice(11, 16)
        elevation = Math.round(d.elevation || 0)
        timezoneName = (d.timezone_abbreviation || "") + (d.timezone ? " (" + d.timezone.split("/").pop().replace(/_/g, " ") + ")" : "")
        daily = d.daily.time.map((t, i) => ({
            day: Qt.formatDate(new Date(t + "T12:00:00"), "dddd"),
            code: d.daily.weather_code[i],
            condition: describe(d.daily.weather_code[i]),
            max: Math.round(d.daily.temperature_2m_max[i]),
            min: Math.round(d.daily.temperature_2m_min[i])
        }))
        hourly = d.hourly ? d.hourly.time.map((t, i) => ({
            time: t.slice(11, 16),
            code: d.hourly.weather_code[i],
            isDay: d.hourly.is_day[i] === 1,
            temperature: Math.round(d.hourly.temperature_2m[i])
        })) : []
        ready = true
        lastFetch = Date.now()
        failures = 0
        console.info("Weather:", placeName + (approximate ? " (time zone)" : "") + ":", Math.round(temperature) + temperatureUnit, condition, "·", days.map(x => x.day + " " + x.max + "/" + x.min).join(", "))
    }

    // Degrees -> "N", "NE", ...
    function compass(deg: real): string {
        return ["N", "NE", "E", "SE", "S", "SW", "W", "NW"][Math.round(((deg % 360) + 360) % 360 / 45) % 8]
    }

    // Icon (Nerd Font, Weather Icons) for a WMO code, by day or by night.
    function icon(code: int, day: bool): string {
        if (code === 0) return day ? "\u{e30d}" : "\u{e32b}"
        if (code <= 2) return day ? "\u{e302}" : "\u{e37e}"
        if (code === 3) return "\u{e312}"
        if (code <= 48) return "\u{e313}"
        if (code <= 57) return "\u{e319}"
        if (code <= 67) return "\u{e318}"
        if (code <= 77) return "\u{e31a}"
        if (code <= 82) return "\u{e319}"
        if (code <= 86) return "\u{e35e}"
        return "\u{e31d}"
    }

    // The WMO codes Open-Meteo uses, grouped.
    function describe(code: int): string {
        if (code === 0) return "Clear"
        if (code <= 2) return "Partly cloudy"
        if (code === 3) return "Cloudy"
        if (code <= 48) return "Fog"
        if (code <= 57) return "Drizzle"
        if (code <= 67) return "Rain"
        if (code <= 77) return "Snow"
        if (code <= 82) return "Showers"
        if (code <= 86) return "Snow showers"
        return "Thunderstorm"
    }
}
