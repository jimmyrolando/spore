.pragma library

// Control Center utilities.

// Seconds -> "6:21" or "1:02:03".
function time(s) {
    const t = Math.max(0, Math.floor(s || 0))
    const h = Math.floor(t / 3600), m = Math.floor(t % 3600 / 60), x = t % 60
    return (h ? h + ":" + (m < 10 ? "0" : "") : "") + m + ":" + (x < 10 ? "0" : "") + x
}

// Open-Meteo WMO code -> Lucide icon (see Weather.describe).
function weatherIcon(code, day) {
    if (code === 0) return day === false ? "moon" : "sun"
    if (code <= 2) return day === false ? "cloud-moon" : "cloud-sun"
    if (code === 3) return "cloud"
    if (code <= 48) return "cloud-fog"
    if (code <= 67) return "cloud-rain"
    if (code <= 77) return "cloud-snow"
    if (code <= 82) return "cloud-rain"
    if (code <= 86) return "cloud-snow"
    return "cloud-lightning"
}

// ISO 8601 week of a date.
function isoWeek(date) {
    const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()))
    const day = d.getUTCDay() || 7
    d.setUTCDate(d.getUTCDate() + 4 - day)
    const yearStart = new Date(Date.UTC(d.getUTCFullYear(), 0, 1))
    return Math.ceil(((d - yearStart) / 86400000 + 1) / 7)
}
