import QtQuick
import "../common"
import "../services"

// The laptop's battery in the bar (BatteryService.qml): the battery with its
// charge and the percentage; a bolt while charging, a plug when it's on the
// charger but not charging. The fill is red when it's critical, amber with
// Low Power Mode on (as on macOS) and green while charging. Only shown when
// there's a battery. Click: the Control Center's Battery page.
BarButton {
    id: root

    property BatteryService service: null
    property bool showPercent: true

    // `shown` and not just visible: with no battery, its capsule hides too (see
    // Group in Bar.qml).
    readonly property bool shown: service !== null && service.present
    visible: shown

    readonly property color fill: !shown ? theme.ink2
        : service.critical ? theme.danger
        : service.lowPower ? theme.warn
        : service.charging ? theme.ok
        : theme.ink2

    tooltipRows: !shown ? [] : [
        { label: "Battery", value: service.percent + "%" },
        { label: "Status", value: service.status }
    ].concat(service.timeText ? [{ label: "Time", value: service.timeText }] : [])
    .concat([{ label: "Low Power", value: service.lowPower ? "On" : "Off" }])

    Row {
        spacing: 4

        BatteryIcon {
            anchors.verticalCenter: parent.verticalCenter
            level: root.shown ? root.service.percent / 100 : 0
            color: root.theme.alpha(root.theme.ink2, 0.75)
            fillColor: root.fill
        }

        Icon {
            anchors.verticalCenter: parent.verticalCenter
            visible: root.shown && !root.service.onBattery
            name: root.shown && root.service.charging ? "zap" : "plug"
            size: 11
            stroke: 1.4
            filled: root.shown && root.service.charging
            color: root.shown && root.service.charging ? root.theme.ok : root.theme.ink2
        }

        BarText {
            theme: root.theme
            visible: root.showPercent
            text: root.shown ? root.service.percent + "%" : ""
            color: root.shown && root.service.critical ? root.theme.danger : root.theme.text
        }
    }
}
