import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// The AppImages in the folder (AppImagesService.qml), newest version of each:
// type to search, ↑/↓ to choose, Enter or a click to run it (and the panel
// closes), Esc to close. One that's already open says so. shell.qml loads it
// with a LazyLoader only while it's open.
PanelWindow {
    id: root

    required property Theme theme
    required property AppImagesService appImages

    signal closeRequested()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-appimages"
    // OnDemand, like Settings and the clipboard: Exclusive broke niri's focus.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // No anchors: centered. width/height and not implicit* (see SettingsWindow).
    width: 520
    height: 560
    color: "transparent"

    // The compositor's window radius (Compositor.qml).
    property Compositor compositor: null

    Component.onCompleted: appImages.refresh()

    // What's open changes while it stays open: read it again now and then.
    Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.appImages.refresh()
    }

    // --- Colors ----------------------------------------------------------------

    function tint(alpha: real): color {
        return Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, alpha))
    }
    readonly property color paneBg: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.4))
    readonly property color subtle: tint(0.08)
    readonly property color inputBg: Qt.tint(theme.base, Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.6))
    readonly property color inputBorder: tint(0.15)
    readonly property color button: tint(0.08)
    readonly property color buttonHover: tint(0.14)
    readonly property color selectedBg: Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.06))
    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.55)

    // --- Search and selection ----------------------------------------------------

    property string query: ""
    readonly property var visibleApps: appImages.apps.filter(a =>
        query === "" || (a.name + " " + a.version).toLowerCase().includes(query.toLowerCase()))

    property int currentIndex: 0
    readonly property var current: visibleApps[Math.min(currentIndex, visibleApps.length - 1)] ?? null

    onVisibleAppsChanged: currentIndex = Math.max(0, Math.min(currentIndex, visibleApps.length - 1))

    function move(delta: int): void {
        if (visibleApps.length === 0) return
        currentIndex = Math.max(0, Math.min(visibleApps.length - 1, currentIndex + delta))
        list.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function runApp(app: var): void {
        if (!app) return
        appImages.run(app)
        root.closeRequested()
    }

    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    component PanelButton: Rectangle {
        id: button
        property string label: ""
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 24
        implicitHeight: 30
        radius: 8
        color: area.containsMouse ? root.buttonHover : root.button

        Label {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            font.pixelSize: 12
        }

        MouseArea {
            id: area
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: button.clicked()
        }
    }

    // --- Window ----------------------------------------------------------------

    Rectangle {
        anchors.fill: parent
        radius: root.compositor ? root.compositor.cornerRadius : 0
        color: root.theme.base
        border.width: 1
        border.color: Window.active ? root.theme.accent : root.theme.inactiveBorder
        clip: true

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 18
            spacing: 12

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 40
                radius: 10
                color: root.inputBg
                border.width: 1
                border.color: search.activeFocus ? root.theme.accent : root.inputBorder

                TextInput {
                    id: search
                    anchors.fill: parent
                    anchors.leftMargin: 14
                    anchors.rightMargin: 14
                    verticalAlignment: TextInput.AlignVCenter
                    clip: true
                    focus: true
                    color: root.theme.text
                    selectionColor: root.theme.accent
                    selectedTextColor: root.theme.textOnAccent
                    font.family: root.theme.uiFont
                    font.pixelSize: 14
                    onTextChanged: root.query = text
                    Component.onCompleted: forceActiveFocus()

                    Keys.onEscapePressed: root.closeRequested()
                    Keys.onUpPressed: root.move(-1)
                    Keys.onDownPressed: root.move(1)
                    Keys.onReturnPressed: root.runApp(root.current)
                    Keys.onEnterPressed: root.runApp(root.current)
                    Keys.onPressed: (event) => {
                        if (event.key === Qt.Key_PageDown) {
                            root.move(8)
                            event.accepted = true
                        } else if (event.key === Qt.Key_PageUp) {
                            root.move(-8)
                            event.accepted = true
                        }
                    }

                    Label {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: search.text === ""
                        text: "Search AppImages"
                        color: root.muted
                        font.pixelSize: 14
                    }
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 2
                boundsBehavior: Flickable.StopAtBounds
                model: root.visibleApps

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property bool selected: index === root.currentIndex
                    readonly property bool running: root.appImages.isRunning(modelData)

                    width: list.width
                    height: 54
                    radius: 10
                    color: selected ? root.selectedBg : rowArea.containsMouse ? root.paneBg : "transparent"

                    // Accent bar of the selected one.
                    Rectangle {
                        visible: row.selected
                        anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 8; bottomMargin: 8 }
                        width: 3
                        radius: 2
                        color: root.theme.accent
                    }

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 12

                        // Its initial, in the accent's tint: AppImages don't
                        // give their icon without opening them.
                        Rectangle {
                            implicitWidth: 34
                            implicitHeight: 34
                            radius: 9
                            color: Qt.rgba(root.theme.accent.r, root.theme.accent.g, root.theme.accent.b, 0.18)

                            Label {
                                anchors.centerIn: parent
                                text: row.modelData.name.charAt(0).toUpperCase()
                                color: root.theme.accent
                                font.pixelSize: 16
                                font.weight: Font.DemiBold
                            }
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 1

                            Label {
                                Layout.fillWidth: true
                                text: row.modelData.name
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                maximumLineCount: 1
                            }
                            Label {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: [row.modelData.version,
                                    row.modelData.older > 0 ? row.modelData.older + " older" : ""].filter(s => s !== "").join(" · ")
                                color: root.muted
                                font.pixelSize: 12
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            visible: row.running
                            implicitWidth: 8
                            implicitHeight: 8
                            radius: 4
                            color: root.theme.accent
                        }
                        Label {
                            visible: row.running
                            text: "Open"
                            color: root.muted
                            font.pixelSize: 12
                        }
                    }

                    MouseArea {
                        id: rowArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: root.currentIndex = row.index
                        onClicked: root.runApp(row.modelData)
                    }
                }

                // Nothing to list: the folder isn't there, it's empty, or the
                // search finds none.
                ColumnLayout {
                    anchors.centerIn: parent
                    visible: list.count === 0 && root.appImages.loaded
                    spacing: 10

                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        text: root.appImages.folderMissing ? "The folder doesn't exist yet"
                            : root.appImages.apps.length === 0 ? "No AppImages here yet" : "No matches"
                        color: root.muted
                    }
                    Label {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.appImages.apps.length === 0
                        text: root.appImages.folderMissing ? "It can be made for you" : "Put them in the folder below"
                        color: root.muted
                        font.pixelSize: 12
                    }
                    PanelButton {
                        Layout.alignment: Qt.AlignHCenter
                        visible: root.appImages.folderMissing
                        label: "Create folder"
                        onClicked: root.appImages.createFolder()
                    }
                }
            }

            // The folder, and a way to open it.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Label {
                    Layout.fillWidth: true
                    text: root.appImages.folderRaw
                    color: root.muted
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    elide: Text.ElideMiddle
                }
                PanelButton {
                    visible: !root.appImages.folderMissing
                    label: "Open folder"
                    onClicked: {
                        root.appImages.openFolder()
                        root.closeRequested()
                    }
                }
            }
        }
    }
}
