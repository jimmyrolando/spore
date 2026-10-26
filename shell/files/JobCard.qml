import QtQuick
import QtQuick.Layouts
import "../common"
import "fileutil.js" as Util

// What FileOps is doing, as a card over the window's corner: a copy, a move,
// a zip, the Trash. It shows once a job has taken more than a moment (a
// rename never does), with the bar, how much is done, about how long is left,
// what waits behind it and Cancel; and then, for a few seconds, that it's
// done or why it stopped. The status line keeps its own short version.
Item {
    id: root

    required property Theme theme
    required property FileOps ops

    // "" (hidden), "working" or "done".
    property string phase: ""
    // What the last one did, or its error.
    property string doneText: ""
    property string doneError: ""
    property string lastIcon: "copy"

    readonly property var icons: ({ copy: "copy", move: "arrow-right", archive: "file-archive",
        restore: "archive-restore", trash: "trash" })

    implicitWidth: 340
    implicitHeight: card.height
    opacity: phase ? 1 : 0
    visible: opacity > 0
    Behavior on opacity { NumberAnimation { duration: 160 } }

    // Quick ones (most renames, a small paste) never show it.
    Timer {
        id: showTimer
        interval: 600
        onTriggered: if (root.ops.status) root.phase = "working"
    }

    Timer {
        id: doneTimer
        interval: root.doneError ? 8000 : 3000
        onTriggered: root.phase = ""
    }

    Connections {
        target: root.ops
        function onStatusChanged() {
            if (root.ops.status) {
                root.lastIcon = root.icons[root.ops.what] || "copy"
                // The next in line: straight on, it's been showing.
                if (root.phase === "done") {
                    doneTimer.stop()
                    root.phase = "working"
                } else if (!root.phase) {
                    showTimer.restart()
                }
            } else {
                showTimer.stop()
                // Ended without a word (it couldn't start).
                if (root.phase === "working") root.phase = ""
            }
        }
        function onJobEnded(done, error, seconds) {
            if (root.phase !== "working") return
            root.doneText = done
            root.doneError = error
            root.phase = "done"
            doneTimer.restart()
        }
    }

    // "about 40 s left", "about 3 min left".
    function timeLeft(seconds: real): string {
        if (seconds < 60) return "about " + Math.max(1, Math.ceil(seconds / 5) * 5) + " s left"
        if (seconds < 3600) return "about " + Math.ceil(seconds / 60) + " min left"
        return "about " + Math.round(seconds / 3600 * 10) / 10 + " h left"
    }

    readonly property string detail: {
        const parts = []
        if (phase === "working" && ops.totalBytes > 0 && ops.progress >= 0) {
            parts.push(Math.floor(ops.progress * 100) + " %")
            parts.push(Util.humanSize(ops.doneBytes) + " of " + Util.humanSize(ops.totalBytes))
            if (ops.secondsLeft >= 0) parts.push(timeLeft(ops.secondsLeft))
        }
        if (ops.waiting > 0) parts.push(ops.waiting + " more waiting")
        return parts.join(" · ")
    }

    Rectangle {
        id: card
        width: parent.width
        height: column.implicitHeight + 28
        radius: 14
        color: root.theme.base
        border.width: 1
        border.color: root.phase === "done" && root.doneError ? root.theme.danger : root.theme.panelBorder

        // A done card goes away when clicked.
        MouseArea {
            anchors.fill: parent
            enabled: root.phase === "done"
            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: {
                doneTimer.stop()
                root.phase = ""
            }
        }

        ColumnLayout {
            id: column
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.top: parent.top
            anchors.margins: 14
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Rectangle {
                    implicitWidth: 30
                    implicitHeight: 30
                    radius: 9
                    color: root.phase === "done" && root.doneError ? root.theme.dangerSoft
                        : root.phase === "done" ? root.theme.alpha(root.theme.ok, 0.14) : root.theme.accentSoft

                    Icon {
                        anchors.centerIn: parent
                        name: root.lastIcon
                        size: 16
                        color: root.phase === "done" && root.doneError ? root.theme.danger
                            : root.phase === "done" ? root.theme.ok : root.theme.accent
                    }
                }

                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: root.phase === "done" ? root.doneError || root.doneText : root.ops.status
                    color: root.phase === "done" && root.doneError ? root.theme.danger : root.theme.text
                    font.pixelSize: 13
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                }

                CcButton {
                    theme: root.theme
                    visible: root.phase === "working" && root.ops.cancelable
                    icon: "x"
                    flat: true
                    size: 26
                    danger: true
                    onClicked: root.ops.cancel()
                }
            }

            // The bar: how far it is, or, when that's not known (the Trash),
            // a piece that goes back and forth.
            Rectangle {
                id: track
                Layout.fillWidth: true
                visible: root.phase === "working"
                implicitHeight: 6
                radius: 3
                color: root.theme.track
                clip: true

                Rectangle {
                    visible: root.ops.progress >= 0
                    width: track.width * Math.max(0, root.ops.progress)
                    height: parent.height
                    radius: parent.radius
                    color: root.theme.accent
                    Behavior on width { NumberAnimation { duration: 300 } }
                }

                Rectangle {
                    id: sweep
                    visible: root.ops.progress < 0
                    width: track.width * 0.3
                    height: parent.height
                    radius: parent.radius
                    color: root.theme.accent

                    SequentialAnimation on x {
                        running: root.phase === "working" && root.ops.progress < 0
                        loops: Animation.Infinite
                        NumberAnimation { from: 0; to: track.width - sweep.width; duration: 900; easing.type: Easing.InOutQuad }
                        NumberAnimation { from: track.width - sweep.width; to: 0; duration: 900; easing.type: Easing.InOutQuad }
                    }
                }
            }

            MonoText {
                theme: root.theme
                Layout.fillWidth: true
                visible: text !== ""
                text: root.detail
                color: root.theme.muted
                font.pixelSize: 11
                wrapMode: Text.Wrap
            }
        }
    }
}
