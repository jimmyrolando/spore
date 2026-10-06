import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"

// A screen's brightness (BrightnessService), under the volume in Home: sun,
// slider, value and the monitor's name in a row like the volume's; with
// `compact` (two screens side by side), the name and the value over the
// slider. The slider shows where it's dragged right away; the monitor follows
// a moment later.
CcCard {
    id: root

    required property BrightnessService brightness
    // An entry of brightness.displays.
    required property var display
    property bool compact: false

    // Its own while dragging: the service only sends the latest value.
    property real value: display.value

    implicitHeight: 56

    function moved(v: real): void {
        value = v
        brightness.set(display.id, v)
    }

    // The same place as the volume's mute button, so the sliders line up.
    component Sun: Item {
        implicitWidth: 32
        implicitHeight: 32

        Icon {
            anchors.centerIn: parent
            name: "sun"
            size: 15
            color: root.theme.text
        }
    }

    RowLayout {
        visible: !root.compact
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 14

        Sun {}

        CcSlider {
            theme: root.theme
            Layout.fillWidth: true
            value: root.value
            onMoved: (v) => root.moved(v)
        }

        MonoText {
            theme: root.theme
            Layout.preferredWidth: 48
            horizontalAlignment: Text.AlignRight
            text: Math.round(root.value * 100) + "%"
            font.pixelSize: 13
        }

        MonoText {
            theme: root.theme
            Layout.maximumWidth: 150
            text: root.display.label
            color: root.theme.muted
            elide: Text.ElideRight
            font.pixelSize: 12
        }
    }

    RowLayout {
        visible: root.compact
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        spacing: 8

        Sun {}

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            RowLayout {
                Layout.fillWidth: true

                MonoText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.display.label
                    color: root.theme.muted
                    elide: Text.ElideRight
                    font.pixelSize: 12
                }

                MonoText {
                    theme: root.theme
                    text: Math.round(root.value * 100) + "%"
                    font.pixelSize: 12
                }
            }

            CcSlider {
                theme: root.theme
                Layout.fillWidth: true
                value: root.value
                onMoved: (v) => root.moved(v)
            }
        }
    }
}
