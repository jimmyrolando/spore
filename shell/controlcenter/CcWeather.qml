import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"
import "ccutil.js" as CcUtil

// Control Center → Weather: a single card, like Calendar. At the top the
// current weather (icon, temperature, condition, high and low) and
// Daily/Hourly; in the middle the forecast in seven columns, each with its
// range over a vertical bar (all on the same scale); at the bottom the
// details (feels like, humidity, wind, UV, sunrise and sunset). The data
// comes from Weather.qml (Open-Meteo), the same as the lockscreen's.
Item {
    id: root

    required property Theme theme
    property Weather weather: null

    readonly property bool ready: weather !== null && weather.ready
    readonly property var place: weather ? weather.place : null
    readonly property string placeFull: place ? place.name + (place.region ? ", " + place.region : "")
        + (weather && weather.approximate ? " (time zone)" : "") : ""
    readonly property string subtitle: placeFull

    property string mode: "daily"

    function deg(t: real): string {
        return Math.round(t) + "°"
    }

    // No data (no location, off, or loading).
    ColumnLayout {
        anchors.centerIn: parent
        visible: !root.ready
        spacing: 8
        Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "cloud"
            size: 32
            stroke: 1.2
            color: root.theme.muted2
        }
        UiText {
            theme: root.theme
            Layout.alignment: Qt.AlignHCenter
            text: root.weather && !root.weather.enabled ? "Weather is turned off" : "Loading weather…"
        }
        UiText {
            theme: root.theme
            Layout.alignment: Qt.AlignHCenter
            text: "Settings → Lock screen → Weather"
            color: root.theme.muted
            font.pixelSize: 12
        }
    }

    CcCard {
        id: card
        theme: root.theme
        anchors.fill: parent
        visible: root.ready

        // Days: today first ("TODAY", then "SAT"...). Hours: the next 7 from the
        // current one ("NOW", then "19:00"...).
        readonly property var columns: {
            if (!root.ready) return []
            if (root.mode === "daily")
                return root.weather.daily.slice(0, 7).map((d, i) => ({
                    label: i === 0 ? "TODAY" : d.day.slice(0, 3).toUpperCase(), code: d.code, day: true, lo: d.min, hi: d.max
                }))
            const hour = Qt.formatTime(new Date(), "hh") + ":00"
            const start = Math.max(0, root.weather.hourly.findIndex(h => h.time === hour))
            return root.weather.hourly.slice(start, start + 7).map((h, i) => ({
                label: i === 0 ? "NOW" : h.time, code: h.code, day: h.isDay, lo: h.temperature, hi: h.temperature
            }))
        }
        // Bar scale: from the minimum to the maximum of the columns.
        readonly property real low: columns.length ? Math.min(...columns.map(c => c.lo)) : 0
        readonly property real high: columns.length ? Math.max(...columns.map(c => c.hi)) : 1
        readonly property real span: Math.max(1, high - low)

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // --- Now ---
            RowLayout {
                Layout.fillWidth: true
                spacing: 14

                Icon {
                    name: root.ready ? CcUtil.weatherIcon(root.weather.code, root.weather.isDay) : "cloud"
                    size: 44
                    stroke: 1.1
                    color: root.theme.accent
                }
                MonoText {
                    theme: root.theme
                    text: root.ready ? root.deg(root.weather.temperature) : ""
                    color: root.theme.accent
                    font.pixelSize: 38
                    font.weight: Font.Medium
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.ready ? root.weather.condition : ""
                        font.pixelSize: 15
                        font.weight: Font.DemiBold
                    }
                    MonoText {
                        theme: root.theme
                        text: root.ready ? "H " + root.deg(root.weather.todayMax) + " · L " + root.deg(root.weather.todayMin) : ""
                        color: root.theme.muted
                    }
                }
                CcSegmented {
                    theme: root.theme
                    Layout.alignment: Qt.AlignVCenter
                    options: [{ value: "daily", label: "Daily" }, { value: "hourly", label: "Hourly" }]
                    current: root.mode
                    onPicked: (v) => root.mode = v
                }
            }

            // --- Forecast: seven columns ---
            RowLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: 4

                Repeater {
                    model: card.columns

                    Rectangle {
                        id: column
                        required property var modelData
                        required property int index

                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        Layout.preferredWidth: 1
                        radius: 12
                        // Today (or the current hour), like the calendar's chosen day.
                        color: index === 0 ? root.theme.accentSoft : "transparent"

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.topMargin: 10
                            anchors.bottomMargin: 10
                            spacing: 6

                            UiText {
                                theme: root.theme
                                Layout.alignment: Qt.AlignHCenter
                                text: column.modelData.label
                                color: root.theme.accent
                                font.pixelSize: 11
                                font.weight: Font.DemiBold
                                font.letterSpacing: 0.66
                            }
                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.topMargin: 2
                                name: CcUtil.weatherIcon(column.modelData.code, column.modelData.day)
                                size: 22
                                stroke: 1.3
                                color: root.theme.text
                            }
                            MonoText {
                                theme: root.theme
                                Layout.alignment: Qt.AlignHCenter
                                text: root.deg(column.modelData.hi)
                                font.pixelSize: 14
                                font.weight: Font.Medium
                            }

                            // Range (or the hour's temperature), from warm at the top to cold at the
                            // bottom, on the shared scale.
                            Rectangle {
                                id: track
                                Layout.alignment: Qt.AlignHCenter
                                Layout.fillHeight: true
                                implicitWidth: 6
                                radius: 3
                                color: root.theme.insetBg

                                Rectangle {
                                    readonly property real from: (card.high - column.modelData.hi) / card.span
                                    readonly property real to: (card.high - column.modelData.lo) / card.span
                                    readonly property real minH: track.width
                                    width: parent.width
                                    height: Math.max(minH, parent.height * (to - from))
                                    y: Math.min(parent.height - height, parent.height * from)
                                    radius: 3
                                    gradient: Gradient {
                                        GradientStop { position: 0; color: root.theme.warn }
                                        GradientStop { position: 1; color: Qt.tint(root.theme.accent, root.theme.alpha("white", 0.35)) }
                                    }
                                }
                            }

                            MonoText {
                                theme: root.theme
                                Layout.alignment: Qt.AlignHCenter
                                visible: root.mode === "daily"
                                text: root.deg(column.modelData.lo)
                                color: root.theme.muted
                            }
                        }
                    }
                }
            }

            // --- Details: a band at the bottom ---
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 2
                implicitHeight: 1
                color: root.theme.cardBorder
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 2
                spacing: 8

                Repeater {
                    model: !root.ready ? [] : [
                        ["Feels like", root.deg(root.weather.feelsLike)],
                        ["Humidity", root.weather.humidity + "%"],
                        ["Wind", Math.round(root.weather.windSpeed) + " " + root.weather.windUnit + " " + root.weather.windDirection],
                        ["UV index", String(Math.round(root.weather.uvIndex))],
                        ["Sunrise", root.weather.sunrise],
                        ["Sunset", root.weather.sunset]
                    ]

                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 2
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: modelData[0]
                            color: root.theme.muted
                            font.pixelSize: 11
                        }
                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: modelData[1]
                            font.pixelSize: 13
                            font.weight: Font.Medium
                        }
                    }
                }
            }
        }
    }
}
