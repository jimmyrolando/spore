import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Greetd

// Login screen (greetd). Similar to the shell's lockscreen, but with the
// wallpaper blurred to tell them apart at a glance. The same as tuigreet
// (--time --remember --cmd niri-session) and a bit more:
//   - large time and date at the top,
//   - editable user, prefilled with the last one who logged in,
//   - password and any extra steps PAM asks for (2FA, questions),
//   - a session picker that remembers the last one (Niri by default),
//   - Suspend / Reboot / Shutdown (the last two ask for confirmation).
// A regular window (xdg toplevel) and not a PanelWindow: cage doesn't
// support layer-shell, and with a PanelWindow the window never appeared (a
// black screen with the cursor). cage makes its only window full screen and
// gives it the keyboard.
FloatingWindow {
    id: root

    property string wallpaperPath: ""
    // If the user's doesn't load (they haven't published anything yet), this
    // one.
    property string defaultWallpaper: ""
    // Another user: try again with their wallpaper.
    onWallpaperPathChanged: wallpaper.failed = false
    required property Theme theme
    // User and session to prefill, and where to save the chosen ones (see
    // shell.qml). userChosen: when a user is confirmed, to show their theme.
    property string lastUser: ""
    property string lastSession: ""
    property string lastUserFile: ""
    property string lastSessionFile: ""
    property string hostName: ""
    signal userChosen(string user)

    color: theme.crust

    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.6)
    readonly property color cardColor: Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.88)
    readonly property color cardBorder: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.08)
    readonly property color fieldColor: Qt.rgba(theme.crust.r, theme.crust.g, theme.crust.b, 0.5)

    property date now: new Date()

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // --- Background: blurred and dimmed wallpaper -------------------------------

    Image {
        id: wallpaper
        anchors.fill: parent
        property bool failed: false
        source: root.width > 0 && root.height > 0
            ? Qt.resolvedUrl(failed || !root.wallpaperPath ? root.defaultWallpaper : root.wallpaperPath) : ""
        // At half the screen's size: it's blurred entirely anyway, and decoding it
        // in full (an 8000 px photo, about 150 MB) makes no visible difference.
        sourceSize: Qt.size(Math.ceil(root.width / 2), Math.ceil(root.height / 2))
        onStatusChanged: if (status === Image.Error && !failed) failed = true
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }

    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        blurEnabled: true
        blur: 1.0
        blurMax: 48
        autoPaddingEnabled: false
    }

    Rectangle {
        anchors.fill: parent
        color: theme.crust
        opacity: 0.4
    }

    // --- Login state ------------------------------------------------------------

    // greetd's flow: createSession(user) -> one or more authMessage (each one
    // answered with respond()) -> readyToLaunch -> launch().
    //
    // The password is typed before the session is created: it's kept in
    // pendingSecret and answers the first secret request. If PAM asks for
    // something else (a code, a question), the field switches to show that
    // request.
    property bool busy: false
    property string pendingSecret: ""
    property bool hasPendingSecret: false
    // Extra PAM request in progress ("" = the field is the password).
    property string prompt: ""
    property bool promptEcho: false
    property string infoText: ""
    property string errorText: ""

    Sessions {
        id: sessions
    }

    // Chosen session: the last one used, otherwise Niri, otherwise the first.
    property int sessionIndex: -1
    readonly property var session: sessions.sessions[sessionIndex] ?? null

    function pickDefaultSession(): void {
        const list = sessions.sessions
        let i = list.findIndex(s => s.name === root.lastSession)
        if (i < 0) i = list.findIndex(s => s.exec.includes("niri"))
        sessionIndex = list.length > 0 ? Math.max(i, 0) : -1
    }

    Connections {
        target: sessions
        function onSessionsChanged() {
            root.pickDefaultSession()
        }
    }
    onLastSessionChanged: pickDefaultSession()
    // The last user is read after the fields are created: when it arrives,
    // focus moves to the password (like tuigreet --remember).
    onLastUserChanged: if (lastUser && !busy) passInput.forceActiveFocus()

    function reset(): void {
        busy = false
        hasPendingSecret = false
        pendingSecret = ""
        prompt = ""
        promptEcho = false
        infoText = ""
        passInput.text = ""
    }

    function submit(): void {
        if (busy && prompt === "") return
        errorText = ""
        // Answer to an extra PAM request.
        if (prompt !== "") {
            const response = passInput.text
            passInput.text = ""
            prompt = ""
            Greetd.respond(response)
            return
        }
        const user = userInput.text.trim()
        if (user === "") {
            userInput.forceActiveFocus()
            return
        }
        if (!session) {
            errorText = "No sessions found"
            return
        }
        root.userChosen(user)
        pendingSecret = passInput.text
        hasPendingSecret = true
        passInput.text = ""
        busy = true
        Greetd.createSession(user)
    }

    Connections {
        target: Greetd

        function onAuthMessage(message: string, error: bool, responseRequired: bool, echoResponse: bool): void {
            if (!responseRequired) {
                // Informational (Quickshell already answers greetd).
                if (error) root.errorText = message
                else root.infoText = message
                return
            }
            if (!echoResponse && root.hasPendingSecret) {
                root.hasPendingSecret = false
                Greetd.respond(root.pendingSecret)
                root.pendingSecret = ""
                return
            }
            // Another request: show it in the field and wait for the answer.
            root.prompt = message.trim()
            root.promptEcho = echoResponse
            passInput.text = ""
            passInput.forceActiveFocus()
        }

        function onAuthFailure(message: string): void {
            Greetd.cancelSession()
            root.reset()
            root.errorText = message || "Wrong username or password"
            passInput.forceActiveFocus()
        }

        function onError(error: string): void {
            Greetd.cancelSession()
            root.reset()
            root.errorText = error
        }

        function onReadyToLaunch(): void {
            // First save the user and session, then launch (in onExited). They used
            // to be saved with execDetached and the session launched right away: the
            // greeter closed, greetd killed its processes, and last-user was never
            // written (the greeter didn't know which theme to show).
            rememberChoice.user = userInput.text.trim()
            rememberChoice.sessionName = root.session.name
            rememberChoice.running = true
        }
    }

    Process {
        id: rememberChoice
        property string user: ""
        property string sessionName: ""
        command: ["sh", "-c", '[ -n "$3" ] && printf "%s" "$1" > "$3"; [ -n "$4" ] && printf "%s" "$2" > "$4"; exit 0',
            "_", user, sessionName, root.lastUserFile, root.lastSessionFile]
        // Even if the write fails, the session launches anyway. (Several spaces
        // in a row in Exec made empty arguments.)
        onExited: Greetd.launch(root.session.exec.split(" ").filter(arg => arg), [], true)
    }

    // --- Time and date ---------------------------------------------------------

    ColumnLayout {
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: parent.height * 0.12
        spacing: 4

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatTime(root.now, "hh:mm")
            color: theme.text
            font.family: theme.fontFamily
            font.pixelSize: 96
            font.weight: Font.Light
        }

        Text {
            Layout.alignment: Qt.AlignHCenter
            text: Qt.formatDate(root.now, "dddd, MMMM d")
            color: theme.text
            opacity: 0.8
            font.family: theme.uiFont
            font.pixelSize: 20
        }
    }

    // --- Card: user, password, session ------------------------------------------

    Rectangle {
        id: card
        anchors.centerIn: parent
        anchors.verticalCenterOffset: parent.height * 0.08
        width: 420
        height: cardColumn.implicitHeight + 56
        radius: 16
        color: root.cardColor
        border.width: 1
        border.color: root.cardBorder

        ColumnLayout {
            id: cardColumn
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            // The user's initial.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 72
                implicitHeight: 72
                radius: 36
                color: "transparent"
                border.width: 2
                border.color: theme.accent

                Text {
                    anchors.centerIn: parent
                    text: userInput.text.trim() ? userInput.text.trim().charAt(0).toUpperCase() : "?"
                    color: theme.accent
                    font.family: theme.uiFont
                    font.pixelSize: 30
                }
            }

            // User: shown as a title, edited with a click.
            Item {
                Layout.fillWidth: true
                implicitHeight: 34

                TextInput {
                    id: userInput
                    anchors.fill: parent
                    horizontalAlignment: TextInput.AlignHCenter
                    verticalAlignment: TextInput.AlignVCenter
                    text: root.lastUser
                    color: theme.text
                    selectionColor: theme.accent
                    selectedTextColor: theme.textOnAccent
                    font.family: theme.uiFont
                    font.pixelSize: 22
                    enabled: !root.busy
                    clip: true
                    KeyNavigation.tab: passInput
                    onAccepted: passInput.forceActiveFocus()
                    onEditingFinished: if (text.trim()) root.userChosen(text.trim())

                    Text {
                        anchors.centerIn: parent
                        visible: userInput.text === ""
                        text: "Username"
                        color: root.muted
                        font: userInput.font
                    }
                }

                // Underline: only while editing or on hover.
                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: Math.min(parent.width, Math.max(120, userInput.contentWidth + 24))
                    height: 1
                    color: userInput.activeFocus ? theme.accent : root.cardBorder
                    opacity: userInput.activeFocus || userHover.hovered ? 1 : 0
                }

                HoverHandler {
                    id: userHover
                    cursorShape: Qt.IBeamCursor
                }
            }

            // Password (or PAM's extra request) with the button inside.
            Rectangle {
                Layout.fillWidth: true
                Layout.topMargin: 4
                implicitHeight: 48
                radius: 10
                color: root.fieldColor
                border.width: 1
                border.color: root.errorText ? theme.error
                    : passInput.activeFocus ? theme.accent
                    : root.cardBorder

                TextInput {
                    id: passInput
                    anchors.left: parent.left
                    anchors.right: loginButton.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: 16
                    anchors.rightMargin: 12
                    echoMode: root.prompt !== "" && root.promptEcho ? TextInput.Normal : TextInput.Password
                    passwordCharacter: "•"
                    color: theme.text
                    font.family: theme.uiFont
                    font.pixelSize: 16
                    enabled: !root.busy || root.prompt !== ""
                    inputMethodHints: Qt.ImhSensitiveData
                    clip: true
                    KeyNavigation.backtab: userInput
                    onAccepted: root.submit()
                    onTextChanged: if (text !== "") root.errorText = ""
                    // With a prefilled user, focus starts on the password.
                    Component.onCompleted: (root.lastUser ? passInput : userInput).forceActiveFocus()

                    // PAM's messages as they are, never as markup: they can come from
                    // a remote server (LDAP, Kerberos), and Qt's default reads a
                    // "<img src=…>" as an image to fetch.
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: passInput.text === ""
                        text: root.prompt !== "" ? root.prompt
                            : root.errorText ? root.errorText
                            : "Password"
                        color: root.errorText && root.prompt === "" ? theme.error : root.muted
                        font: passInput.font
                        elide: Text.ElideRight
                        width: passInput.width
                        textFormat: Text.PlainText
                    }
                }

                Rectangle {
                    id: loginButton
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 6
                    implicitWidth: loginLabel.implicitWidth + 28
                    implicitHeight: 36
                    radius: 8
                    color: loginArea.containsMouse ? Qt.lighter(theme.accent, 1.08) : theme.accent
                    opacity: root.busy && root.prompt === "" ? 0.6 : 1

                    Text {
                        id: loginLabel
                        anchors.centerIn: parent
                        text: root.busy && root.prompt === "" ? "Checking…" : root.prompt !== "" ? "Continue" : "Log in"
                        color: theme.textOnAccent
                        font.family: theme.uiFont
                        font.pixelSize: 15
                    }

                    MouseArea {
                        id: loginArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.submit()
                    }
                }
            }

            // Informational message from PAM (e.g. "Touch the security key").
            Text {
                Layout.fillWidth: true
                visible: root.infoText !== ""
                text: root.infoText
                color: root.muted
                font.family: theme.uiFont
                font.pixelSize: 13
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
            }

            // Session: the chosen one; a click opens the list. Directly in the card's
            // column: inside another ColumnLayout with no fillWidth children it wasn't
            // centered.
            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: sessionRow.implicitWidth + 24
                implicitHeight: 32
                radius: 8
                color: sessionArea.containsMouse || sessionList.visible ? root.fieldColor : "transparent"

                Row {
                    id: sessionRow
                    anchors.centerIn: parent
                    spacing: 8

                    Text {
                        text: "Session"
                        color: root.muted
                        font.family: theme.uiFont
                        font.pixelSize: 13
                    }

                    Text {
                        text: (root.session ? root.session.name : "None") + (sessions.sessions.length > 1 ? (sessionList.visible ? "  ▴" : "  ▾") : "")
                        color: theme.text
                        font.family: theme.uiFont
                        font.pixelSize: 13
                    }
                }

                MouseArea {
                    id: sessionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: sessions.sessions.length > 1 && !root.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onClicked: sessionList.visible = !sessionList.visible
                }
            }

            Column {
                id: sessionList
                Layout.alignment: Qt.AlignHCenter
                visible: false
                spacing: 2

                Repeater {
                    model: sessions.sessions

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool current: index === root.sessionIndex

                        width: 220
                        height: 32
                        radius: 8
                        color: current ? Qt.rgba(theme.accent.r, theme.accent.g, theme.accent.b, 0.18)
                            : itemArea.containsMouse ? root.fieldColor : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: modelData.name
                            color: parent.current ? theme.accent : theme.text
                            font.family: theme.uiFont
                            font.pixelSize: 13
                        }

                        MouseArea {
                            id: itemArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                root.sessionIndex = parent.index
                                sessionList.visible = false
                                passInput.forceActiveFocus()
                            }
                        }
                    }
                }
            }
        }
    }

    // --- Bottom: machine and power ----------------------------------------------

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 24
        visible: root.hostName !== ""
        implicitWidth: hostLabel.implicitWidth + 24
        implicitHeight: 32
        radius: 8
        color: root.cardColor

        Text {
            id: hostLabel
            anchors.centerIn: parent
            text: root.hostName
            color: root.muted
            font.family: theme.fontFamily
            font.pixelSize: 13
        }
    }

    // Reboot and Shutdown ask for a second click ("Confirm?"), which expires
    // after 3 s.
    property string confirming: ""

    Timer {
        id: confirmTimer
        interval: 3000
        onTriggered: root.confirming = ""
    }

    Row {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 24
        spacing: 8

        Repeater {
            model: [
                { name: "Suspend", command: ["systemctl", "suspend"], confirm: false },
                { name: "Reboot", command: ["systemctl", "reboot"], confirm: true },
                { name: "Shutdown", command: ["systemctl", "poweroff"], confirm: true }
            ]

            Rectangle {
                required property var modelData
                readonly property bool confirming: root.confirming === modelData.name

                implicitWidth: actionLabel.implicitWidth + 28
                implicitHeight: 32
                radius: 8
                color: confirming ? theme.error
                    : actionArea.containsMouse ? Qt.rgba(theme.base.r, theme.base.g, theme.base.b, 0.95)
                    : root.cardColor

                Text {
                    id: actionLabel
                    anchors.centerIn: parent
                    text: parent.confirming ? "Confirm?" : parent.modelData.name
                    color: parent.confirming ? theme.textOnAccent : actionArea.containsMouse ? theme.text : root.muted
                    font.family: theme.uiFont
                    font.pixelSize: 13
                }

                MouseArea {
                    id: actionArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (parent.modelData.confirm && !parent.confirming) {
                            root.confirming = parent.modelData.name
                            confirmTimer.restart()
                            return
                        }
                        root.confirming = ""
                        Quickshell.execDetached(parent.modelData.command)
                    }
                }
            }
        }
    }
}
