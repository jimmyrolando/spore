import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"

// Control Center → Battery (BatteryService.qml): the charge drawn large with
// its status and the time left, Low Power Mode (the Power Saver profile, as
// on macOS) and the battery's details. The tab only shows on a machine with
// a battery (ControlCenter.qml).
ColumnLayout {
    id: root

    required property Theme theme
    required property BatteryService service

    // No subtitle: the card below already says the status and the time.
    readonly property string subtitle: ""

    // Like the bar's: red when critical, amber with Low Power Mode, green
    // while charging.
    readonly property color fill: service.critical ? theme.danger
        : service.lowPower ? theme.warn
        : service.charging ? theme.ok
        : theme.accent

    spacing: 12

    // --- The charge ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        implicitHeight: 124

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 28
            anchors.rightMargin: 24
            spacing: 26

            BatteryIcon {
                bodyWidth: 92
                bodyHeight: 44
                level: root.service.percent / 100
                color: root.theme.alpha(root.theme.ink2, 0.6)
                fillColor: root.fill
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                MonoText {
                    theme: root.theme
                    text: root.service.percent + "%"
                    color: root.fill
                    font.pixelSize: 34
                }

                RowLayout {
                    spacing: 5

                    Icon {
                        visible: !root.service.onBattery
                        name: root.service.charging ? "zap" : "plug"
                        size: 13
                        stroke: 1.5
                        filled: root.service.charging
                        color: root.service.charging ? root.theme.ok : root.theme.ink2
                    }

                    UiText {
                        theme: root.theme
                        text: root.service.status
                        font.pixelSize: 14
                        font.weight: Font.DemiBold
                    }
                }

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.service.timeText
                        || (root.service.onBattery || root.service.charging ? "Estimating the time…" : "")
                    color: root.theme.muted
                    font.pixelSize: 12
                }
            }
        }
    }

    // --- Low Power Mode ---
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        implicitHeight: lowPowerRow.implicitHeight + 32

        RowLayout {
            id: lowPowerRow
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 12

            Rectangle {
                implicitWidth: 40
                implicitHeight: 40
                radius: 11
                color: root.theme.alpha(root.service.lowPower ? root.theme.warn : root.theme.accent, 0.14)

                Icon {
                    anchors.centerIn: parent
                    name: "leaf"
                    size: 18
                    stroke: 1.4
                    color: root.service.lowPower ? root.theme.warn : root.theme.accent
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                UiText {
                    theme: root.theme
                    text: "Low Power Mode"
                    font.pixelSize: 14
                    font.weight: Font.DemiBold
                }

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    wrapMode: Text.Wrap
                    text: root.service.lowPower && root.service.autoOn
                        ? "Turned on at " + root.service.lowPowerAt + "%. It turns off when you plug in."
                        : "The Power Saver profile: the system slows down a little and the battery lasts longer."
                            + (root.service.lowPowerAt > 0 ? " On battery, it turns on by itself at " + root.service.lowPowerAt + "%." : "")
                    color: root.theme.muted
                    font.pixelSize: 12
                }
            }

            CcSwitch {
                theme: root.theme
                checked: root.service.lowPower
                onToggled: root.service.setLowPower(!root.service.lowPower)
            }
        }
    }

    // --- Details: four tiles ---
    component Stat: CcCard {
        id: stat
        property string label: ""
        property string value: ""

        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.preferredWidth: 1
        implicitHeight: 72

        ColumnLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.margins: 16
            spacing: 6

            CcSection {
                theme: root.theme
                text: stat.label
            }

            MonoText {
                theme: root.theme
                Layout.fillWidth: true
                text: stat.value
                font.pixelSize: 17
            }
        }
    }

    GridLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        columns: 2
        rowSpacing: 12
        columnSpacing: 12

        Stat {
            label: "Health"
            value: root.service.health >= 0 ? Math.round(root.service.health * 100) + "%" : "Unknown"
        }

        Stat {
            label: "Capacity"
            value: root.service.capacity > 0 ? root.service.capacity.toFixed(1) + " Wh" : "Unknown"
        }

        Stat {
            label: root.service.charging ? "Charging at" : "Power draw"
            value: root.service.rate > 0 ? root.service.rate.toFixed(1) + " W" : "—"
        }

        Stat {
            label: "Power profile"
            value: root.service.profileName
        }
    }
}
