import QtQuick
import Quickshell

// Day or night from sunrise and sunset at a location, for the "Auto" mode
// (dark at night, light by day). Computed right here, with no network (the
// Almanac for Computers / NOAA algorithm, ~1 minute precision).
//
// With no location yet, it approximates: day between 7:00 and 19:00.
Scope {
    id: root

    property real latitude: NaN
    property real longitude: NaN
    readonly property bool hasLocation: !isNaN(latitude) && !isNaN(longitude)

    property bool isDay: true
    // Next change (sunrise or sunset).
    property date nextChange: new Date()

    onLatitudeChanged: Qt.callLater(update)
    onLongitudeChanged: Qt.callLater(update)
    Component.onCompleted: update()

    // Until the next change, but 5 minutes at most: Timers' clock doesn't run
    // during suspend, so this corrects itself after waking up.
    Timer {
        id: timer
        onTriggered: root.update()
    }

    function update(): void {
        const now = new Date()
        let day, next
        if (hasLocation) {
            const today = eventsFor(now)
            if (today.always !== undefined) {
                // Midnight sun or polar night: check every so often.
                day = today.always
                next = new Date(now.getTime() + 3600000)
            } else {
                // Yesterday's, today's and tomorrow's events in order: the last one that
                // passed says whether it's day, the following one is the next change. (With
                // a location far from the system's time zone, sunset can come before
                // sunrise in the local day.)
                const events = []
                for (const offset of [-1, 0, 1]) {
                    const e = offset === 0 ? today : eventsFor(new Date(now.getTime() + offset * 86400000))
                    if (e.always !== undefined) continue
                    events.push({ time: e.rise, day: true }, { time: e.set, day: false })
                }
                events.sort((a, b) => a.time - b.time)
                const past = events.filter(e => e.time <= now)
                const upcoming = events.find(e => e.time > now)
                day = past.length > 0 ? past[past.length - 1].day : !(upcoming && upcoming.day)
                next = upcoming ? upcoming.time : new Date(now.getTime() + 3600000)
            }
        } else {
            const at = h => new Date(now.getFullYear(), now.getMonth(), now.getDate(), h)
            day = now >= at(7) && now < at(19)
            next = now < at(7) ? at(7) : now < at(19) ? at(19) : new Date(at(7).getTime() + 86400000)
        }
        isDay = day
        nextChange = next
        timer.interval = Math.max(1000, Math.min(next.getTime() - now.getTime() + 1000, 5 * 60000))
        timer.restart()
    }

    // Sunrise and sunset of the local day of `date`: { rise, set } as Dates, or
    // { always: true/false } if the sun doesn't rise or set that day.
    function eventsFor(date: date): var {
        const rise = event(date, true)
        const set = event(date, false)
        if (typeof rise === "boolean") return { always: rise }
        if (typeof set === "boolean") return { always: set }
        return { rise: rise, set: set }
    }

    // An event (rising true = sunrise) as a Date; if it doesn't happen, a bool:
    // true = daylight all day, false = night all day.
    function event(date: date, rising: bool): var {
        const rad = Math.PI / 180
        const deg = 180 / Math.PI
        const midnight = new Date(date.getFullYear(), date.getMonth(), date.getDate())
        const n = Math.round((midnight - new Date(date.getFullYear(), 0, 0)) / 86400000)
        const lngHour = longitude / 15
        const t = n + ((rising ? 6 : 18) - lngHour) / 24

        const M = 0.9856 * t - 3.289
        const L = (M + 1.916 * Math.sin(M * rad) + 0.020 * Math.sin(2 * M * rad) + 282.634 + 360) % 360
        let RA = (Math.atan(0.91764 * Math.tan(L * rad)) * deg + 360) % 360
        // Same quadrant as L.
        RA = (RA + Math.floor(L / 90) * 90 - Math.floor(RA / 90) * 90) / 15

        const sinDec = 0.39782 * Math.sin(L * rad)
        const cosDec = Math.cos(Math.asin(sinDec))
        // 90.833°: the sun "rises" with its upper edge and with refraction.
        const cosH = (Math.cos(90.833 * rad) - sinDec * Math.sin(latitude * rad))
            / (cosDec * Math.cos(latitude * rad))
        if (cosH > 1) return false
        if (cosH < -1) return true

        const H = (rising ? 360 - Math.acos(cosH) * deg : Math.acos(cosH) * deg) / 15
        const T = H + RA - 0.06571 * t - 6.622
        const UT = ((T - lngHour) % 24 + 24) % 24

        // UT is the event's UTC time: it's moved to the matching local day.
        let ms = Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()) + UT * 3600000
        while (ms < midnight.getTime()) ms += 86400000
        while (ms >= midnight.getTime() + 86400000) ms -= 86400000
        return new Date(ms)
    }
}
