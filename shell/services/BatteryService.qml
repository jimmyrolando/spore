import QtQuick
import Quickshell
import Quickshell.Services.UPower
import Quickshell.Services.Notifications

// The laptop's battery (UPower), once for the whole shell: the bar widget
// (BatteryStatus.qml), the Control Center's Battery page and Home's Low
// Power tile read it from here.
//
// Low Power Mode is the system's Power Saver profile (power-profiles-daemon):
// turning it off goes back to the profile there was before. It also turns on
// by itself on battery at settings' lowPowerAt, and then off again when the
// charger is plugged in (only if it was this that turned it on, as on macOS).
// The low and critical warnings are notifications (NotificationService.post);
// the critical one shows even with Do Not Disturb.
//
// Simulated (`qs ipc call battery simulate 15 discharging`): a fake battery
// for testing on a machine without one, and with it a fake profile, so a
// test never changes the real machine's. A nested session (tools/test.sh)
// never changes it either, even with a real battery.
Scope {
    id: root

    property Settings settings: null
    property NotificationService notifications: null
    property bool nested: false

    // --- The battery ----------------------------------------------------------

    property bool simulated: false
    property int simPercent: 50
    // "discharging", "charging", "full" or "plugged" (on the charger, not
    // charging).
    property string simState: "discharging"
    property bool simLowPower: false

    readonly property var device: UPower.displayDevice

    // UPower can give 0..1 or 0..100 depending on the version: normalized.
    function unit(v: real): real {
        return v > 1 ? v / 100 : v
    }

    readonly property bool present: simulated || (device !== null && device.ready && device.isLaptopBattery && device.isPresent)
    // 0..100.
    readonly property int percent: simulated ? simPercent : present ? Math.round(unit(device.percentage) * 100) : 0
    readonly property bool charging: simulated ? simState === "charging"
        : present && (device.state === UPowerDeviceState.Charging || device.state === UPowerDeviceState.PendingCharge)
    readonly property bool full: simulated ? simState === "full" : present && device.state === UPowerDeviceState.FullyCharged
    readonly property bool onBattery: simulated ? simState === "discharging" : present && UPower.onBattery
    // Seconds; 0 = unknown (UPower is still estimating).
    readonly property real timeToEmpty: simulated ? (simState === "discharging" ? simPercent * 216 : 0) : present ? device.timeToEmpty : 0
    readonly property real timeToFull: simulated ? (simState === "charging" ? (100 - simPercent) * 54 : 0) : present ? device.timeToFull : 0
    // 0..1 of the original capacity; -1 = unknown.
    readonly property real health: simulated ? 0.91 : present && device.healthSupported ? unit(device.healthPercentage) : -1
    // Watts going in or out, and the capacity now (Wh).
    readonly property real rate: simulated ? (simState === "discharging" ? 8.4 : simState === "charging" ? 32 : 0) : present ? Math.abs(device.changeRate) : 0
    readonly property real capacity: simulated ? 52.6 : present ? device.energyCapacity : 0

    readonly property string status: !present ? "No battery"
        : charging ? "Charging"
        : full ? "Fully charged"
        : onBattery ? "On battery"
        : "Plugged in, not charging"

    // "2 h 15 min", "40 min"; "" if unknown.
    function duration(s: real): string {
        if (!(s > 0)) return ""
        const m = Math.round(s / 60)
        const h = Math.floor(m / 60)
        return h > 0 ? h + " h " + (m % 60) + " min" : m + " min"
    }

    // "2 h 15 min left", "Full in 40 min" or "".
    readonly property string timeText: onBattery && timeToEmpty > 0 ? duration(timeToEmpty) + " left"
        : charging && timeToFull > 0 ? "Full in " + duration(timeToFull)
        : ""

    // At or under the critical warning, on battery: red.
    readonly property bool critical: onBattery && percent <= (settings ? Math.max(settings.batteryCriticalAt, 10) : 10)

    // --- Low Power Mode -------------------------------------------------------

    // Simulated or nested: a profile of its own, not the system's.
    readonly property bool fakeProfile: simulated || nested
    readonly property bool lowPower: fakeProfile ? simLowPower : PowerProfiles.profile === PowerProfile.PowerSaver

    readonly property string profileName: lowPower ? "Power Saver"
        : !fakeProfile && PowerProfiles.profile === PowerProfile.Performance ? "Performance"
        : "Balanced"
    // Turned on by the automatic mode (it goes off again when plugged in).
    readonly property bool autoOn: kept.autoOn
    readonly property int lowPowerAt: settings ? settings.batteryLowPowerAt : 0

    // Survives hot reload: which profile to go back to, and whether it was the
    // automatic mode that turned it on.
    PersistentProperties {
        id: kept
        reloadableId: "batteryState"
        property int previousProfile: PowerProfile.Balanced
        property bool autoOn: false
        // Already turned on once this discharge: if you turn it off, it stays off
        // until the next charge.
        property bool autoDone: false
        // The warning already given this discharge: 0 none, 1 low, 2 critical.
        property int warned: 0
        property string popupKey: ""
    }

    function setLowPower(on: bool): void {
        if (on === lowPower) return
        if (!on) kept.autoOn = false
        if (fakeProfile) {
            simLowPower = on
            return
        }
        if (on) {
            kept.previousProfile = PowerProfiles.profile
            PowerProfiles.profile = PowerProfile.PowerSaver
        } else {
            PowerProfiles.profile = kept.previousProfile === PowerProfile.PowerSaver ? PowerProfile.Balanced : kept.previousProfile
        }
    }

    // --- Automatic Low Power and warnings -------------------------------------

    onPercentChanged: Qt.callLater(check)
    onOnBatteryChanged: Qt.callLater(check)
    onPresentChanged: Qt.callLater(check)
    Component.onCompleted: Qt.callLater(check)
    Connections {
        target: root.settings
        function onBatteryLowPowerAtChanged() { Qt.callLater(root.check) }
    }

    function check(): void {
        if (!present || !settings) return
        if (!onBattery) {
            // Plugged in: what the automatic mode turned on goes off, the next
            // discharge warns again, and the warning still on screen goes away.
            if (kept.autoOn) setLowPower(false)
            kept.autoDone = false
            kept.warned = 0
            if (kept.popupKey && notifications) notifications.hidePopup(kept.popupKey)
            kept.popupKey = ""
            return
        }
        let turnedOn = false
        const at = settings.batteryLowPowerAt
        if (at > 0 && percent <= at && !lowPower && !kept.autoDone) {
            setLowPower(true)
            kept.autoOn = true
            turnedOn = true
        }
        if (at > 0 && percent <= at) kept.autoDone = true
        const criticalAt = settings.batteryCriticalAt
        const warnAt = settings.batteryWarnAt
        if (criticalAt > 0 && percent <= criticalAt && kept.warned < 2) {
            kept.warned = 2
            warn("Battery critically low", percent + "% left. Plug in now or save your work.", NotificationUrgency.Critical, "battery-caution")
        } else if (warnAt > 0 && percent <= warnAt && kept.warned < 1) {
            kept.warned = 1
            warn("Battery low", percent + "% left" + (timeText ? " · " + timeText.replace(" left", "") : "") + "."
                + (lowPower ? " Low Power Mode is on." : ""), NotificationUrgency.Normal, "battery-low")
        } else if (turnedOn) {
            warn("Low Power Mode on", "The battery is at " + percent + "%. It turns off again when you plug in.", NotificationUrgency.Low, "battery-low")
        }
    }

    function warn(summary: string, body: string, urgency: int, icon: string): void {
        if (!notifications) return
        if (kept.popupKey) notifications.hidePopup(kept.popupKey)
        kept.popupKey = notifications.post("Battery", icon, summary, body, urgency)
    }

    // For the IPC: { present, percent, status, lowPower, autoOn, warned }.
    function describe(): string {
        return JSON.stringify({ present: present, simulated: simulated, percent: percent, status: status,
            lowPower: lowPower, autoOn: kept.autoOn, warned: kept.warned })
    }
}
