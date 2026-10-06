import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import Quickshell
import Quickshell.Networking
import "../common"
import "../services"

// Visual content of the lock screen. WlSessionLock instantiates this once
// per monitor -- they all share the same LockContext (and Weather).
//
// Top: greeting with the initial, date and a circular clock. Bottom:
// weather, password and power actions. Corner: the machine's name.
Rectangle {
    id: root

    required property LockContext context
    required property Theme theme
    required property Weather weather
    property string wallpaperPath: ""
    property int wallpaperVersion: 0
    // First name (from the GECOS field of /etc/passwd) and hostname: Lock.qml
    // reads them once.
    property string userName: ""
    property string hostName: ""

    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.6)
    readonly property color cardColor: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.88)
    readonly property color cardBorder: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)

    // The clock's Timer (secondsTimer) updates it every second.
    property date now: new Date()

    color: theme.crust

    // At the screen's size, like the background (Wallpaper.qml): same URL and
    // size, so they share the decoded image instead of having two.
    Image {
        anchors.fill: parent
        source: root.wallpaperPath && root.width > 0 && root.height > 0
            ? (Qt.resolvedUrl(root.wallpaperPath) + "?" + root.wallpaperVersion)
            : ""
        sourceSize: Qt.size(root.width, root.height)
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
    }

    // Darkens the image so the cards read well.
    Rectangle {
        anchors.fill: parent
        color: theme.crust
        opacity: 0.45
    }

    component Card: Rectangle {
        color: root.cardColor
        radius: 16
        border.width: 1
        border.color: root.cardBorder
    }

    // --- Top card: greeting, date and clock --------------------------------

    Card {
        id: header
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.09
        width: headerRow.implicitWidth + 44
        height: headerRow.implicitHeight + 40

        RowLayout {
            id: headerRow
            anchors.centerIn: parent
            spacing: 18

            // Initial in a circle with the accent.
            Rectangle {
                implicitWidth: 52
                implicitHeight: 52
                radius: 26
                color: "transparent"
                border.width: 2
                border.color: theme.accent

                Text {
                    font.family: theme.uiFont
                    anchors.centerIn: parent
                    text: root.userName ? root.userName.charAt(0).toUpperCase() : ""
                    color: theme.accent
                    font.pixelSize: 22
                }
            }

            ColumnLayout {
                spacing: 2

                // The texts here that come from outside (the name, the weather's
                // place, the network, the machine) show as they are, never as
                // markup (see common/UiText.qml).
                Text {
                    font.family: theme.uiFont
                    text: root.userName ? "Welcome back, " + root.userName : "Welcome back"
                    color: theme.text
                    font.pixelSize: 19
                    textFormat: Text.PlainText
                }

                Text {
                    font.family: theme.uiFont
                    text: Qt.formatDate(root.now, "dddd, MMMM d")
                    color: root.muted
                    font.pixelSize: 14
                }
            }

            // Separates the clock from the text.
            Item { implicitWidth: 28 }

            // Clock: hours and minutes in the center, the ring marks the seconds.
            Item {
                implicitWidth: 50
                implicitHeight: 50

                Shape {
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.2)
                        strokeWidth: 2
                        PathAngleArc { centerX: 25; centerY: 25; radiusX: 24; radiusY: 24; startAngle: 0; sweepAngle: 360 }
                    }

                    ShapePath {
                        fillColor: "transparent"
                        strokeColor: theme.accent
                        strokeWidth: 2
                        capStyle: ShapePath.RoundCap
                        PathAngleArc {
                            id: secondsArc
                            centerX: 25; centerY: 25; radiusX: 24; radiusY: 24
                            startAngle: -90
                            sweepAngle: 0
                        }
                    }
                }

                // One turn per minute in 60 steps: it advances every second with a short
                // transition. At the minute it completes the turn and goes back to 0. The
                // Timer aligns with the clock on every step, so it doesn't drift (not even
                // after suspending).
                NumberAnimation {
                    id: secondsAnim
                    target: secondsArc
                    property: "sweepAngle"
                    duration: 300
                    easing.type: Easing.OutCubic
                    onFinished: if (secondsArc.sweepAngle >= 360) secondsArc.sweepAngle = 0
                }

                Timer {
                    id: secondsTimer
                    // animate: false only on open (starts at the current step).
                    function tick(animate: bool): void {
                        const d = new Date()
                        const step = d.getSeconds()
                        root.now = d
                        secondsAnim.stop()
                        if (animate) {
                            // Step 0 coming from another: complete the turn and restart.
                            secondsAnim.to = step === 0 && secondsArc.sweepAngle > 0 ? 360 : step * 6
                            secondsAnim.start()
                        } else {
                            secondsArc.sweepAngle = step * 6
                        }
                        interval = 1000 - d.getMilliseconds() + 20
                        restart()
                    }
                    onTriggered: tick(true)
                }

                Component.onCompleted: secondsTimer.tick(false)

                Column {
                    anchors.centerIn: parent
                    spacing: -2

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(root.now, "hh")
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: 12
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatTime(root.now, "mm")
                        color: theme.text
                        font.family: theme.fontFamily
                        font.pixelSize: 12
                    }
                }
            }
        }
    }

    // --- Bottom card: weather, password, actions ---------------------------

    Card {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: parent.height * 0.06
        width: 530
        height: panelColumn.implicitHeight + 40

        ColumnLayout {
            id: panelColumn
            anchors.fill: parent
            anchors.margins: 20
            spacing: 18

            // Weather (only if settings.json has a location and it has responded).
            RowLayout {
                Layout.fillWidth: true
                visible: root.weather.enabled && root.weather.ready
                spacing: 0

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2

                    RowLayout {
                        spacing: 8

                        Text {
                            font.family: theme.fontFamily
                            text: Math.round(root.weather.temperature) + root.weather.temperatureUnit
                            color: theme.text
                            font.pixelSize: 20
                            font.bold: true
                        }

                        Text {
                            font.family: theme.fontFamily
                            Layout.alignment: Qt.AlignBaseline
                            text: Math.round(root.weather.windSpeed) + " " + root.weather.windUnit
                            color: root.muted
                            font.pixelSize: 13
                        }
                    }

                    Text {
                        font.family: theme.uiFont
                        Layout.fillWidth: true
                        Layout.rightMargin: 12
                        elide: Text.ElideRight
                        text: (root.weather.placeName ? root.weather.placeName + " · " : "") + root.weather.condition
                        color: root.muted
                        font.pixelSize: 14
                        textFormat: Text.PlainText
                    }
                }

                Repeater {
                    model: root.weather.forecast

                    RowLayout {
                        required property var modelData
                        spacing: 0

                        // A faint vertical separator between days.
                        Rectangle {
                            implicitWidth: 1
                            implicitHeight: 40
                            color: root.cardBorder
                        }

                        ColumnLayout {
                            Layout.preferredWidth: 76
                            spacing: 2

                            Text {
                                font.family: theme.uiFont
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.day
                                color: theme.text
                                font.pixelSize: 14
                            }

                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                text: modelData.max + "°/" + modelData.min + "°"
                                color: root.muted
                                font.family: theme.fontFamily
                                font.pixelSize: 13
                            }
                        }
                    }
                }
            }

            // Password with the Unlock button inside.
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 48
                radius: 10
                color: Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.5)
                border.width: 1
                border.color: root.context.showFailure || root.context.error ? theme.error
                    : passInput.activeFocus ? theme.accent
                    : root.cardBorder

                TextInput {
                    id: passInput
                    anchors.left: parent.left
                    anchors.right: unlockButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    echoMode: TextInput.Password
                    passwordCharacter: "•"
                    color: theme.text
                    font.family: theme.uiFont
                    font.pixelSize: 16
                    enabled: !root.context.unlockInProgress
                    inputMethodHints: Qt.ImhSensitiveData
                    focus: true
                    clip: true

                    onTextChanged: root.context.currentText = text
                    onAccepted: root.context.tryUnlock()
                    Component.onCompleted: forceActiveFocus()

                    // Keeps the field in sync if the context is cleared (auth failure) or it
                    // changes from another monitor.
                    Connections {
                        target: root.context
                        function onCurrentTextChanged() {
                            passInput.text = root.context.currentText
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passInput.text === ""
                        text: root.context.error || (root.context.showFailure ? "Wrong password" : "Password")
                        color: root.context.showFailure || root.context.error ? theme.error : root.muted
                        font: passInput.font
                    }
                }

                Rectangle {
                    id: unlockButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 6
                    implicitWidth: unlockLabel.implicitWidth + 28
                    implicitHeight: 36
                    radius: 8
                    color: unlockArea.containsMouse ? Qt.lighter(theme.accent, 1.08) : theme.accent
                    opacity: root.context.unlockInProgress ? 0.6 : 1

                    Text {
                        font.family: theme.uiFont
                        id: unlockLabel
                        anchors.centerIn: parent
                        text: root.context.unlockInProgress ? "Checking…" : "Unlock"
                        color: theme.textOnAccent
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: unlockArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.context.tryUnlock()
                    }
                }
            }

            // Power and network actions. No Logout: whoever is at a locked screen
            // shouldn't be able to end the session (and its unsaved work) that
            // easily; suspend, reboot and shutdown stay, as on most systems.
            RowLayout {
                Layout.fillWidth: true
                spacing: 0

                Repeater {
                    model: [
                        { id: "suspend", label: "Suspend", confirm: false,
                          command: ["systemctl", "suspend"] },
                        { id: "reboot", label: "Reboot", confirm: true,
                          command: ["systemctl", "reboot"] },
                        { id: "shutdown", label: "Shutdown", confirm: true,
                          command: ["systemctl", "poweroff"] }
                    ]

                    Item {
                        id: action
                        required property var modelData
                        readonly property bool armed: root.armedAction === modelData.id

                        implicitWidth: actionLabel.implicitWidth + 32
                        implicitHeight: 28

                        Text {
                            font.family: theme.uiFont
                            id: actionLabel
                            anchors.centerIn: parent
                            text: action.armed ? "Confirm?" : action.modelData.label
                            color: action.armed ? theme.error
                                : actionArea.containsMouse ? theme.text
                                : root.muted
                            font.pixelSize: 14
                        }

                        MouseArea {
                            id: actionArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAction(action.modelData)
                        }
                    }
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: root.networkLabel
                    color: root.muted
                    font.family: theme.uiFont
                    font.pixelSize: 13
                    textFormat: Text.PlainText
                }
            }
        }
    }

    // --- Corner: the machine's name -----------------------------------------

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 22
        visible: root.hostName !== ""
        implicitWidth: hostLabel.implicitWidth + 20
        implicitHeight: hostLabel.implicitHeight + 10
        radius: 8
        color: root.cardColor

        Text {
            id: hostLabel
            anchors.centerIn: parent
            text: root.hostName
            color: root.muted
            font.family: theme.fontFamily
            font.pixelSize: 13
            textFormat: Text.PlainText
        }
    }

    // --- Logic ---------------------------------------------------------------

    // Reboot and Shutdown ask for a second click: the first one "arms" them
    // (the text changes to "Confirm?") for a few seconds. Suspend goes straight
    // through.
    property string armedAction: ""

    Timer {
        id: disarm
        interval: 3000
        onTriggered: root.armedAction = ""
    }

    function runAction(action: var): void {
        if (action.confirm && armedAction !== action.id) {
            armedAction = action.id
            disarm.restart()
            return
        }
        armedAction = ""
        Quickshell.execDetached(action.command)
    }

    // The connection in use, like the bar's icon: wired takes priority
    // (NetworkManager gives it a lower metric); otherwise, wifi with its name
    // and signal.
    readonly property var networkDevices: Networking.devices.values
    readonly property var wifiNetwork: {
        const wifi = networkDevices.find(d => d.type === DeviceType.Wifi && d.connected)
        return wifi ? (wifi.networks.values.find(n => n.connected) ?? null) : null
    }
    readonly property bool wired: networkDevices.some(d => d.type === DeviceType.Wired && d.connected)
    readonly property string networkLabel: {
        if (wired) return "Ethernet"
        if (wifiNetwork) {
            const s = wifiNetwork.signalStrength
            return wifiNetwork.name + " · " + Math.round(s > 1 ? s : s * 100) + "%"
        }
        return "Offline"
    }
}
