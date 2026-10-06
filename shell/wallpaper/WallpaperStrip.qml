import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// The "Preview on desktop" strip: wallpapers, palette and mode in a band at
// the bottom of the screen, to choose while seeing the desktop, barely
// covering it. Clicking a thumbnail applies the wallpaper right away.
//
// Done / Esc: closeRequested; shell.qml decides whether to go back to
// Settings (if it was opened from there) or just close (if opened by shortcut).
PanelWindow {
    id: root

    required property Theme theme
    required property WallpaperService wallpapers
    property string currentWallpaperSource: ""
    // "dark", "light" or "auto" (theme.mode is the one applied).
    property string modeSetting: "dark"
    property string autoModeHint: ""

    signal closeRequested()
    signal wallpaperChosen(path: string)
    signal paletteChosen(name: string)
    signal themeModeChosen(mode: string)

    anchors.bottom: true
    margins.bottom: 16
    // Above the windows, without reserving space.
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.namespace: "quickshell-wallpaper-strip"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    implicitWidth: Math.min(920, (screen ? screen.width : 952) - 32)
    implicitHeight: column.implicitHeight
    color: "transparent"

    Component.onCompleted: wallpapers.refresh()

    function tint(alpha: real): color {
        return Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, alpha))
    }
    readonly property color cardBg: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.94)
    readonly property color subtle: tint(0.12)
    readonly property color button: tint(0.08)
    readonly property color buttonHover: tint(0.16)
    readonly property color track: tint(0.07)
    readonly property color chipActive: Qt.tint(theme.base, Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.14))
    readonly property color soft: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.75)

    // Plain text, never markup (see common/UiText.qml).
    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 12
        textFormat: Text.PlainText
    }

    ColumnLayout {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        spacing: 6
        // Keys and not Shortcut: see SettingsWindow.qml.
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        // --- Wallpapers ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 84 + 20
            radius: 14
            color: root.cardBg
            border.width: 1
            border.color: root.subtle

            ListView {
                id: list
                anchors.fill: parent
                anchors.margins: 10
                orientation: ListView.Horizontal
                spacing: 10
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.wallpapers.files

                delegate: WallpaperThumb {
                    required property string modelData
                    width: 144
                    height: 84
                    theme: root.theme
                    wallpapers: root.wallpapers
                    path: modelData
                    selected: modelData === root.currentWallpaperSource
                    onChosen: if (modelData !== root.currentWallpaperSource) root.wallpaperChosen(modelData)
                }

                // The mouse's vertical wheel scrolls the horizontal list.
                WheelHandler {
                    acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                    orientation: Qt.Vertical
                    onWheel: (event) => {
                        const max = Math.max(0, list.contentWidth - list.width)
                        const delta = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x
                        list.contentX = Math.max(0, Math.min(max, list.contentX - delta))
                    }
                }

                // On open, brings the current wallpaper into view.
                onCountChanged: {
                    const i = root.wallpapers.files.indexOf(root.currentWallpaperSource)
                    if (i >= 0) positionViewAtIndex(i, ListView.Contain)
                }
            }
        }

        // --- Palette, mode and Done ---
        Rectangle {
            Layout.fillWidth: true
            implicitHeight: 28 + 12
            radius: 12
            color: root.cardBg
            border.width: 1
            border.color: root.subtle

            RowLayout {
                anchors.fill: parent
                anchors.margins: 6
                spacing: 4

                Repeater {
                    model: root.theme.paletteNames

                    Rectangle {
                        id: chip
                        required property string modelData
                        readonly property var colors: root.theme.colorsFor(modelData, root.theme.mode)
                        readonly property bool selected: modelData === root.theme.palette

                        implicitWidth: chipRow.implicitWidth + 16
                        implicitHeight: 28
                        radius: 7
                        opacity: colors ? 1 : 0.4
                        color: selected ? root.chipActive : chipArea.containsMouse ? root.button : "transparent"
                        border.width: selected ? 1 : 0
                        border.color: root.theme.accent

                        Row {
                            id: chipRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 6
                            spacing: 6

                            Rectangle {
                                width: 16
                                height: 16
                                radius: 8
                                anchors.verticalCenter: parent.verticalCenter
                                color: chip.colors ? chip.colors.base : root.button
                                border.width: 1
                                border.color: root.subtle

                                Rectangle {
                                    anchors.centerIn: parent
                                    width: 8
                                    height: 8
                                    radius: 4
                                    color: chip.colors ? chip.colors.accent : "transparent"
                                }
                            }

                            Label {
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.theme.label(chip.modelData)
                                color: chip.selected ? root.theme.text : root.soft
                            }
                        }

                        MouseArea {
                            id: chipArea
                            anchors.fill: parent
                            hoverEnabled: true
                            enabled: chip.colors !== null
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (!chip.selected) root.paletteChosen(chip.modelData)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Rectangle {
                    implicitWidth: modes.implicitWidth + 4
                    implicitHeight: 28
                    radius: 8
                    color: root.track

                    Row {
                        id: modes
                        anchors.centerIn: parent
                        spacing: 2

                        Repeater {
                            model: [{ mode: "light", label: "Light" }, { mode: "dark", label: "Dark" }, { mode: "auto", label: "Auto" }]

                            Rectangle {
                                required property var modelData
                                readonly property bool active: modelData.mode === root.modeSetting

                                width: modeLabel.implicitWidth + 24
                                height: 24
                                radius: 6
                                color: active ? root.theme.accent : modeArea.containsMouse ? root.buttonHover : "transparent"

                                Label {
                                    id: modeLabel
                                    anchors.centerIn: parent
                                    text: modelData.label
                                    color: parent.active ? root.theme.textOnAccent : root.theme.text
                                }

                                MouseArea {
                                    id: modeArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: if (!parent.active) root.themeModeChosen(parent.modelData.mode)
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    Layout.leftMargin: 6
                    implicitWidth: doneLabel.implicitWidth + 28
                    implicitHeight: 28
                    radius: 7
                    color: doneArea.containsMouse ? root.buttonHover : root.button

                    Label {
                        id: doneLabel
                        anchors.centerIn: parent
                        text: "Done"
                        font.weight: Font.Medium
                    }

                    MouseArea {
                        id: doneArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.closeRequested()
                    }
                }
            }
        }
    }
}
