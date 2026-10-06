import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Widgets
import Quickshell.Services.Mpris
import "../common"
import "ccutil.js" as CcUtil

// Control Center → Media (design v2): the large cover, the app, the title,
// the artist, the seek bar and the controls; below, the volume. With more
// than one player, the app's name switches to the next one.
ColumnLayout {
    id: root

    required property Theme theme
    signal pageRequested(string id)

    readonly property var players: Mpris.players.values
    // The one picked by hand; if it's gone, the one playing (or the first).
    property var chosen: null
    readonly property var player: (chosen && players.includes(chosen)) ? chosen
        : (players.find(p => p.isPlaying) ?? players[0] ?? null)

    readonly property string subtitle: player ? (player.isPlaying ? "Playing" : "Paused") + " · " + (player.identity || "") : "Nothing playing"

    spacing: 12

    // MPRIS doesn't report the position while playing: ask every second.
    Timer {
        interval: 1000
        running: root.player !== null && root.player.isPlaying
        repeat: true
        onTriggered: root.player.positionChanged()
    }

    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true

        // No player.
        ColumnLayout {
            anchors.centerIn: parent
            visible: root.player === null
            spacing: 8

            Icon {
                Layout.alignment: Qt.AlignHCenter
                name: "music"
                size: 28
                color: root.theme.muted2
            }
            UiText {
                theme: root.theme
                Layout.alignment: Qt.AlignHCenter
                text: "Nothing playing"
            }
            UiText {
                theme: root.theme
                Layout.alignment: Qt.AlignHCenter
                text: "Play something in a browser or music app"
                color: root.theme.muted
                font.pixelSize: 12
            }
        }

        RowLayout {
            anchors.fill: parent
            anchors.margins: 20
            visible: root.player !== null
            spacing: 24

            // Cover, with a shadow.
            Item {
                implicitWidth: 220
                implicitHeight: 220

                RectangularShadow {
                    anchors.fill: art
                    offset.y: 10
                    blur: 28
                    radius: 16
                    color: Qt.rgba(30 / 255, 32 / 255, 80 / 255, 0.22)
                }

                ClippingRectangle {
                    id: art
                    anchors.fill: parent
                    radius: 16
                    color: root.theme.track

                    Image {
                        id: artImage
                        anchors.fill: parent
                        source: root.player ? root.player.trackArtUrl : ""
                        sourceSize: Qt.size(440, 440)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: artImage.status !== Image.Ready
                        name: "music"
                        size: 56
                        stroke: 1.2
                        color: root.theme.muted2
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                spacing: 16

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    // App (with several players: click = the next one).
                    MonoText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.player ? (root.player.identity || "").toUpperCase()
                            + (root.players.length > 1 ? "  ·  " + (root.players.indexOf(root.player) + 1) + "/" + root.players.length + " ›" : "")
                            : ""
                        color: root.theme.accent
                        font.pixelSize: 11
                        font.letterSpacing: 1.1

                        MouseArea {
                            anchors.fill: parent
                            enabled: root.players.length > 1
                            cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: root.chosen = root.players[(root.players.indexOf(root.player) + 1) % root.players.length]
                        }
                    }

                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.player ? (root.player.trackTitle || "Unknown title") : ""
                        font.pixelSize: 22
                        font.weight: Font.DemiBold
                        lineHeight: 1.1
                        wrapMode: Text.Wrap
                        maximumLineCount: 3
                    }

                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: root.player ? [root.player.trackArtist, root.player.trackAlbum].filter(s => s).join(" · ") : ""
                        color: root.theme.muted
                        font.pixelSize: 14
                    }
                }

                Item { Layout.fillHeight: true }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    visible: root.player !== null && root.player.lengthSupported && root.player.length > 0

                    CcSlider {
                        theme: root.theme
                        Layout.fillWidth: true
                        value: root.player && root.player.length > 0 ? root.player.position / root.player.length : 0
                        onMoved: (v) => {
                            if (root.player.canSeek) root.player.position = v * root.player.length
                        }
                    }

                    RowLayout {
                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.player ? CcUtil.time(root.player.position) : ""
                            color: root.theme.muted
                        }
                        MonoText {
                            theme: root.theme
                            text: root.player ? CcUtil.time(root.player.length) : ""
                            color: root.theme.muted
                        }
                    }
                }

                RowLayout {
                    spacing: 10

                    component Round: Rectangle {
                        id: round
                        property string icon: ""
                        property bool big: false
                        property bool available: true
                        signal clicked()

                        implicitWidth: big ? 52 : 40
                        implicitHeight: implicitWidth
                        radius: width / 2
                        opacity: available ? 1 : 0.4
                        color: big ? root.theme.accent : roundArea.containsMouse ? root.theme.accentHoverStrong : root.theme.accentSoft

                        RectangularShadow {
                            visible: round.big
                            z: -1
                            anchors.fill: parent
                            offset.y: 6
                            blur: 16
                            radius: parent.radius
                            color: root.theme.alpha(root.theme.accent, 0.35)
                        }

                        Icon {
                            anchors.centerIn: parent
                            name: round.icon
                            size: round.big ? 18 : 14
                            filled: true
                            color: round.big ? root.theme.textOnAccent : root.theme.ink2
                        }

                        MouseArea {
                            id: roundArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: round.available ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: if (round.available) round.clicked()
                        }
                    }

                    Round {
                        icon: "skip-back"
                        available: root.player !== null && root.player.canGoPrevious
                        onClicked: root.player.previous()
                    }
                    Round {
                        big: true
                        icon: root.player && root.player.isPlaying ? "pause" : "play"
                        available: root.player !== null && root.player.canTogglePlaying
                        onClicked: root.player.togglePlaying()
                    }
                    Round {
                        icon: "skip-forward"
                        available: root.player !== null && root.player.canGoNext
                        onClicked: root.player.next()
                    }
                }
            }
        }
    }

    CcVolumeRow {
        theme: root.theme
        Layout.fillWidth: true
        onDeviceRequested: root.pageRequested("audio")
    }
}
