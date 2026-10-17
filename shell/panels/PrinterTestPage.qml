import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"
import "../common/brand.js" as Brand

// The sheet PrintersPane prints as a test page: the Spore mark and some
// details of the machine (like About), and patterns to see what the printer
// does: colors, grays, text sizes, thin lines and a circle. It is drawn like
// any other item, then saved as an image and sent to the printer (the image
// is what CUPS prints best, on any printer). Always black on white: it is
// paper, so the theme's palette doesn't apply, only its font.
Rectangle {
    id: root

    required property Theme theme
    property SystemInfo system: null

    property string printer: ""
    property string address: ""
    // "Letter" or "A4".
    property string paper: "Letter"
    property string printed: ""

    // 96 dpi, which is what the sizes below assume.
    readonly property real pageWidth: paper === "A4" ? 794 : 816
    readonly property real pageHeight: paper === "A4" ? 1123 : 1056

    width: pageWidth
    height: pageHeight
    color: "white"

    readonly property color ink: "#1b1c2e"
    readonly property color faint: "#6b6d80"
    readonly property string family: theme.uiFont

    function pt(points: real): real {
        return points * 96 / 72
    }

    component Label: Text {
        color: root.ink
        font.family: root.family
        font.pixelSize: root.pt(10)
        textFormat: Text.PlainText
    }

    // A small heading over each pattern.
    component Heading: Label {
        color: Brand.colors.spore
        font.pixelSize: root.pt(8)
        font.bold: true
        font.letterSpacing: 1.2
        font.capitalization: Font.AllUppercase
    }

    // The corners, where a printer that crops shows it.
    Repeater {
        model: [[0, 0], [1, 0], [0, 1], [1, 1]]

        Item {
            required property var modelData
            x: modelData[0] === 0 ? 30 : root.width - 30 - 22
            y: modelData[1] === 0 ? 30 : root.height - 30 - 22
            width: 22
            height: 22
            Rectangle {
                width: parent.width; height: 1.5; color: root.ink
                y: modelData[1] === 0 ? 0 : parent.height - 1.5
            }
            Rectangle {
                width: 1.5; height: parent.height; color: root.ink
                x: modelData[0] === 0 ? 0 : parent.width - 1.5
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: 72
        anchors.rightMargin: 72
        anchors.topMargin: 64
        anchors.bottomMargin: 64
        spacing: 22

        // Mark, name and what this is.
        RowLayout {
            Layout.fillWidth: true
            spacing: 22

            SporeMark {
                theme: root.theme
                onDark: false
                size: 96
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                Label {
                    text: Brand.shortName
                    font.pixelSize: root.pt(34)
                    font.weight: Font.DemiBold
                }
                Label {
                    text: "Printer test page"
                    font.pixelSize: root.pt(14)
                }
                Label {
                    text: Brand.slogan
                    color: root.faint
                    font.pixelSize: root.pt(9)
                    font.italic: true
                }
            }
        }

        Rectangle { Layout.fillWidth: true; height: 1; color: "#d9dae6" }

        // Details, in two columns: this print and this machine.
        RowLayout {
            Layout.fillWidth: true
            spacing: 28

            Repeater {
                model: {
                    const s = root.system ? root.system.info : ({})
                    return [
                        [["Printer", root.printer], ["Address", root.address], ["Printed", root.printed], ["Paper", root.paper]],
                        [["System", s.os || ""], ["Kernel", s.kernel || ""], ["Compositor", root.system ? root.system.wm : ""],
                         ["Shell", Brand.name + " " + Brand.version]]
                    ]
                }

                ColumnLayout {
                    id: column
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 100
                    Layout.alignment: Qt.AlignTop
                    spacing: 6

                    Repeater {
                        model: column.modelData

                        RowLayout {
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 12

                            Label {
                                Layout.preferredWidth: 74
                                text: modelData[0]
                                color: Brand.colors.spore
                                font.weight: Font.DemiBold
                                font.pixelSize: root.pt(9)
                            }
                            Label {
                                Layout.fillWidth: true
                                text: modelData[1]
                                font.pixelSize: root.pt(9)
                                elide: Text.ElideRight
                            }
                        }
                    }
                }
            }
        }


        Rectangle { Layout.fillWidth: true; height: 1; color: "#d9dae6" }

        // Colors: the printer's inks and what they make together.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Heading { text: "Color" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [
                        ["Cyan", "#00aeef"], ["Magenta", "#ec008c"], ["Yellow", "#fff200"], ["Black", "#000000"],
                        ["Red", "#ed1c24"], ["Green", "#00a651"], ["Blue", "#2e3192"]
                    ]
                    ColumnLayout {
                        required property var modelData
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 3
                        Rectangle { Layout.fillWidth: true; height: 44; color: modelData[1] }
                        Label { text: modelData[0]; font.pixelSize: root.pt(7); color: root.faint }
                    }
                }
            }
            // The Spore brand colors, a gradient of one hue and a rainbow.
            RowLayout {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: [Brand.colors.spore, Brand.colors.mycel, Brand.colors.ink, Brand.colors.bone]
                    Rectangle {
                        required property color modelData
                        width: 44; height: 22
                        color: modelData
                        border.width: modelData === Brand.colors.bone ? 1 : 0
                        border.color: "#d9dae6"
                    }
                }
                Rectangle {
                    Layout.fillWidth: true
                    height: 22
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop { position: 0.00; color: "#ff0000" }
                        GradientStop { position: 0.17; color: "#ffff00" }
                        GradientStop { position: 0.33; color: "#00ff00" }
                        GradientStop { position: 0.50; color: "#00ffff" }
                        GradientStop { position: 0.67; color: "#0000ff" }
                        GradientStop { position: 0.83; color: "#ff00ff" }
                        GradientStop { position: 1.00; color: "#ff0000" }
                    }
                }
            }
        }

        // Grays: 0 to 100 %, in steps of 10. Two next to each other that
        // look the same are a printer that crushes its darks or its lights.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 8
            Heading { text: "Gray, 0 to 100 %" }
            RowLayout {
                Layout.fillWidth: true
                spacing: 0
                Repeater {
                    model: 11
                    ColumnLayout {
                        required property int index
                        Layout.fillWidth: true
                        Layout.preferredWidth: 1
                        spacing: 3
                        Rectangle {
                            Layout.fillWidth: true; height: 30
                            color: Qt.rgba(0, 0, 0, index / 10)
                            border.width: index === 0 ? 1 : 0
                            border.color: "#d9dae6"
                        }
                        Label { text: index * 10; font.pixelSize: root.pt(7); color: root.faint }
                    }
                }
            }
        }

        // Text, from the size of fine print up.
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 4
            Heading { text: "Text" }
            Repeater {
                model: [6, 8, 10, 12, 16]
                Label {
                    required property int modelData
                    Layout.fillWidth: true
                    text: modelData + " pt · The quick brown fox jumps over the lazy dog 0123456789"
                    font.pixelSize: root.pt(modelData)
                    elide: Text.ElideRight
                }
            }
        }

        // Lines and a circle: thin lines that break up and an oval that
        // isn't round are the first signs of a bad print.
        RowLayout {
            Layout.fillWidth: true
            spacing: 28

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 8
                Heading { text: "Lines" }
                Repeater {
                    model: [0.5, 1, 1.5, 2, 3]
                    RowLayout {
                        required property real modelData
                        Layout.fillWidth: true
                        spacing: 10
                        Label { text: modelData + " px"; font.pixelSize: root.pt(7); color: root.faint; Layout.preferredWidth: 34 }
                        Rectangle { Layout.fillWidth: true; height: modelData; color: root.ink }
                    }
                }
            }

            Item {
                Layout.preferredWidth: 120
                Layout.preferredHeight: 120
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.width: 2
                    border.color: root.ink
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: parent.width * 0.55
                    height: width
                    radius: width / 2
                    color: Brand.colors.spore
                }
                Rectangle { anchors.centerIn: parent; width: parent.width; height: 1; color: root.ink; opacity: 0.4 }
                Rectangle { anchors.centerIn: parent; width: 1; height: parent.height; color: root.ink; opacity: 0.4 }
            }
        }

        Item { Layout.fillHeight: true }

        Label {
            Layout.fillWidth: true
            horizontalAlignment: Text.AlignHCenter
            text: "If you can read this, the printer works."
            color: root.faint
            font.pixelSize: root.pt(9)
        }
    }
}
