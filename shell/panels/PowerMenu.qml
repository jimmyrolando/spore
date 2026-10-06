import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// Power menu (design v2, "Power overlay"): the screen dimmed and, at the top
// center, five actions: Lock, Log Out, Suspend (locks first), Reboot and
// Shut Down. Lock, Log Out and Suspend run immediately; Reboot and Shut Down
// count down 5 seconds with Cancel and Now. Keyboard: 1-5 picks, ←/→ moves,
// Enter runs, Esc cancels the countdown or closes. A click outside closes
// it. shell.qml loads it with a LazyLoader only while it's open.
PanelWindow {
    id: root

    required property Theme theme
    property int topOffset: 36
    property SystemMonitor monitor: null

    signal closeRequested()
    signal actionChosen(string action)

    anchors { top: true; bottom: true; left: true; right: true }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-power-menu"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    readonly property var actions: [
        { id: "lock", label: "Lock", icon: "lock" },
        { id: "logout", label: "Log Out", icon: "log-out" },
        { id: "suspend", label: "Suspend", icon: "moon" },
        { id: "reboot", label: "Reboot", icon: "rotate-cw" },
        { id: "poweroff", label: "Shut Down", icon: "power" }
    ]
    // Selected with the keyboard (starts on Shut Down).
    property int current: actions.length - 1

    // Reboot / Shut Down countdown ("" = none).
    property string confirming: ""
    property int count: 0

    function run(id: string): void {
        if (id === "reboot" || id === "poweroff") {
            confirming = id
            count = 5
            countdown.restart()
        } else {
            actionChosen(id)
        }
    }

    Timer {
        id: countdown
        interval: 1000
        repeat: true
        running: root.confirming !== ""
        onTriggered: {
            if (root.count <= 1) {
                const id = root.confirming
                root.confirming = ""
                root.actionChosen(id)
            } else {
                root.count--
            }
        }
    }

    // Dimmed background: a click closes it.
    Rectangle {
        anchors.fill: parent
        color: Qt.rgba(20 / 255, 22 / 255, 60 / 255, 0.3)

        MouseArea {
            anchors.fill: parent
            onClicked: root.closeRequested()
        }
    }

    RectangularShadow {
        anchors.fill: card
        offset.y: 24
        blur: 64
        radius: card.radius
        color: Qt.rgba(30 / 255, 32 / 255, 80 / 255, 0.35)
    }

    Rectangle {
        id: card
        anchors.horizontalCenter: parent.horizontalCenter
        y: 72
        width: column.implicitWidth + 24
        height: column.implicitHeight + 24
        radius: 20
        color: root.theme.alpha(root.theme.base, 0.98)
        border.width: 1
        border.color: root.theme.panelBorder

        // So a click on the card doesn't close it.
        MouseArea {
            anchors.fill: parent
        }

        focus: true
        Keys.onEscapePressed: {
            if (root.confirming !== "") root.confirming = ""
            else root.closeRequested()
        }
        Keys.onLeftPressed: root.current = (root.current + root.actions.length - 1) % root.actions.length
        Keys.onRightPressed: root.current = (root.current + 1) % root.actions.length
        Keys.onTabPressed: root.current = (root.current + 1) % root.actions.length
        Keys.onReturnPressed: root.confirming !== "" ? root.actionChosen(root.confirming) : root.run(root.actions[root.current].id)
        Keys.onEnterPressed: root.confirming !== "" ? root.actionChosen(root.confirming) : root.run(root.actions[root.current].id)
        Keys.onPressed: (event) => {
            const n = event.key - Qt.Key_1
            if (n >= 0 && n < root.actions.length) {
                root.current = n
                root.run(root.actions[n].id)
                event.accepted = true
            }
        }

        ColumnLayout {
            id: column
            anchors.centerIn: parent
            spacing: 12

            RowLayout {
                spacing: 8

                Repeater {
                    model: root.actions

                    Rectangle {
                        id: tile
                        required property var modelData
                        required property int index
                        readonly property bool danger: modelData.id === "poweroff"
                        readonly property bool confirming: root.confirming === modelData.id
                        readonly property bool selected: index === root.current || tileArea.containsMouse
                        readonly property color fg: confirming ? root.theme.onColor : danger ? root.theme.danger : root.theme.text

                        implicitWidth: 132
                        implicitHeight: 104
                        radius: 14
                        color: confirming ? root.theme.danger : danger ? root.theme.dangerSoft : root.theme.cardBg
                        border.width: 1
                        border.color: confirming ? root.theme.danger
                            : selected ? (danger ? root.theme.danger : root.theme.accent)
                            : danger ? root.theme.alpha(root.theme.danger, 0.25) : root.theme.alpha(root.theme.accent, 0.14)

                        // Shortcut number.
                        Rectangle {
                            anchors.top: parent.top
                            anchors.right: parent.right
                            anchors.margins: 8
                            width: 18
                            height: 18
                            radius: 5
                            color: tile.confirming ? Qt.rgba(1, 1, 1, 0.25) : root.theme.alpha(root.theme.accent, 0.1)

                            MonoText {
                                theme: root.theme
                                anchors.centerIn: parent
                                text: tile.index + 1
                                color: tile.fg
                                font.pixelSize: 11
                            }
                        }

                        ColumnLayout {
                            anchors.centerIn: parent
                            spacing: 10

                            Icon {
                                Layout.alignment: Qt.AlignHCenter
                                name: tile.modelData.icon
                                size: 22
                                stroke: 1.4
                                color: tile.fg
                            }
                            UiText {
                                theme: root.theme
                                Layout.alignment: Qt.AlignHCenter
                                text: tile.modelData.label
                                color: tile.fg
                            }
                        }

                        MouseArea {
                            id: tileArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: root.current = tile.index
                            onClicked: root.run(tile.modelData.id)
                        }
                    }
                }
            }

            // Countdown.
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: root.confirming !== ""
                spacing: 12

                UiText {
                    theme: root.theme
                    text: (root.confirming === "reboot" ? "Rebooting" : "Shutting down") + " in " + root.count + "s"
                }
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 5
                    radius: 3
                    color: root.theme.track
                    clip: true
                    Rectangle {
                        width: parent.width * root.count / 5
                        height: parent.height
                        color: root.theme.danger
                        Behavior on width { NumberAnimation { duration: 1000 } }
                    }
                }
                CcButton {
                    theme: root.theme
                    size: 30
                    label: "Cancel"
                    onClicked: root.confirming = ""
                }
                Rectangle {
                    implicitWidth: nowLabel.implicitWidth + 28
                    implicitHeight: 30
                    radius: 8
                    color: root.theme.danger
                    UiText {
                        id: nowLabel
                        theme: root.theme
                        anchors.centerIn: parent
                        text: "Now"
                        color: root.theme.onColor
                        font.pixelSize: 12
                        font.weight: Font.Medium
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.actionChosen(root.confirming)
                    }
                }
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                visible: root.confirming === ""

                MonoText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.monitor ? "up " + root.monitor.formatUptime() : ""
                    color: root.theme.muted
                    font.pixelSize: 11
                }
                MonoText {
                    theme: root.theme
                    text: "1–5 select · Esc close"
                    color: root.theme.muted
                    font.pixelSize: 11
                }
            }
        }
    }
}
