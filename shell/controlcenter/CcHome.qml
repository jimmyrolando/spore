import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import Quickshell.Bluetooth
import Quickshell.Networking
import Quickshell.Services.UPower
import Quickshell.Services.Mpris
import "../common"
import "../services"
import "ccutil.js" as CcUtil
import "../common/brand.js" as Brand

// Control Center → Home (design v2): who you are over the wallpaper, six
// quick toggles in a row (Wi-Fi, Bluetooth, Caffeine, Do Not Disturb, Power
// Saver: muting is the volume row's), what's playing, the time with the
// weather, the volume and the screens' brightness.
ColumnLayout {
    id: root

    required property Theme theme
    // The wallpaper already cropped to the header's size (see heroGen in
    // shell.qml). "" while it doesn't exist.
    property string heroSource: ""
    property Weather weather: null
    property SystemMonitor monitor: null
    property bool caffeine: false
    property NotificationService notifications: null
    // A row per screen whose brightness can be set.
    property BrightnessService brightness: null
    signal caffeineToggled()
    // Click on the header's wallpaper.
    signal wallpaperPickerRequested()
    // Click on the photo: choose another (the file picker, FilePicker.qml).
    signal avatarPickerRequested()
    // Another Control Center page (e.g. "media" when tapping what's playing).
    signal pageRequested(string id)

    readonly property string subtitle: Qt.formatDate(now, "dddd, MMMM d")

    spacing: 12

    property date now: new Date()
    Timer {
        interval: 10000
        running: true
        repeat: true
        onTriggered: root.now = new Date()
    }

    // --- User data ---

    // Name, user@host and photo: from UserInfo.qml, read when the shell starts
    // (so the page opens already complete).
    property UserInfo user: null
    readonly property string fullName: user ? user.fullName : ""
    readonly property string userHost: user ? user.userHost : ""
    readonly property string avatarPath: user ? user.avatarPath : ""
    readonly property int avatarVersion: user ? user.avatarVersion : 0

    readonly property BluetoothAdapter btAdapter: Bluetooth.defaultAdapter
    readonly property bool dnd: notifications !== null && notifications.dnd
    readonly property bool saver: PowerProfiles.profile === PowerProfile.PowerSaver


    // --- Header: photo, name, user@host with the uptime, and the brand with
    // its version, centered over the wallpaper ---
    ClippingRectangle {
        Layout.fillWidth: true
        implicitHeight: 104
        radius: 16
        color: root.theme.track

        Image {
            anchors.fill: parent
            source: root.heroSource
            fillMode: Image.PreserveAspectCrop
            // Synchronous: the crop loads in ~2 ms, so it's there from the first frame,
            // without the gap when the panel opens.
            asynchronous: false
        }

        // A veil of the panel's background, denser in the middle (where the text
        // goes), so it reads over any wallpaper.
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: root.theme.alpha(root.theme.base, 0.35) }
                GradientStop { position: 0.3; color: root.theme.alpha(root.theme.base, 0.72) }
                GradientStop { position: 0.7; color: root.theme.alpha(root.theme.base, 0.72) }
                GradientStop { position: 1.0; color: root.theme.alpha(root.theme.base, 0.35) }
            }
        }

        // Click on the wallpaper: the wallpaper picker.
        MouseArea {
            anchors.fill: parent
            cursorShape: Qt.PointingHandCursor
            onClicked: root.wallpaperPickerRequested()
        }

        // Photo on the left and next to it the name, user@host with the uptime,
        // and the brand with its version; the group, centered.
        RowLayout {
            id: heroContent
            anchors.centerIn: parent
            spacing: 16

            // Photo (click: choose another). Without a photo, the initial.
            Item {
                implicitWidth: 60
                implicitHeight: 60

                RectangularShadow {
                    anchors.fill: avatarFrame
                    offset.y: 2
                    blur: 8
                    radius: 30
                    color: Qt.rgba(30 / 255, 32 / 255, 80 / 255, 0.2)
                }

                ClippingRectangle {
                    id: avatarFrame
                    anchors.fill: parent
                    radius: 30
                    color: root.theme.cardBg
                    border.width: 2
                    border.color: root.theme.isDark ? root.theme.cardBg : "white"

                    Image {
                        id: avatarImage
                        anchors.fill: parent
                        anchors.margins: 2
                        source: root.avatarPath ? Qt.resolvedUrl(root.avatarPath) + "?" + root.avatarVersion : ""
                        sourceSize: Qt.size(120, 120)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                    }

                    UiText {
                        theme: root.theme
                        anchors.centerIn: parent
                        visible: avatarImage.status !== Image.Ready
                        text: root.fullName ? root.fullName.charAt(0).toUpperCase() : ""
                        color: root.theme.accent
                        font.pixelSize: 24
                    }

                    // On hover: a camera, to change it.
                    Rectangle {
                        anchors.fill: parent
                        visible: avatarArea.containsMouse
                        color: Qt.rgba(0, 0, 0, 0.3)

                        Icon {
                            anchors.centerIn: parent
                            name: "camera"
                            size: 18
                            color: "white"
                        }
                    }
                }

                MouseArea {
                    id: avatarArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.avatarPickerRequested()
                }
            }


            ColumnLayout {
                spacing: 3

                UiText {
                    theme: root.theme
                    text: root.fullName || root.userHost
                    font.pixelSize: 18
                    font.weight: Font.DemiBold
                }

                MonoText {
                    theme: root.theme
                    text: root.userHost + (root.monitor ? " · up " + root.monitor.formatUptime() : "")
                    color: root.theme.soft
                }

                MonoText {
                    theme: root.theme
                    text: Brand.wordmark + " v" + Brand.version
                    color: root.theme.soft
                }
            }
        }
    }

    // --- Quick toggles: a row of five, the icon over the name; on, in the
    // accent ---
    component Tile: Rectangle {
        id: tile
        property string icon: ""
        property string label: ""
        property bool checked: false
        property bool available: true
        signal clicked()

        Layout.fillWidth: true
        Layout.preferredWidth: 1
        implicitHeight: 60
        radius: 14
        opacity: available ? 1 : 0.45
        color: checked ? root.theme.accent
            : tileArea.containsMouse ? Qt.tint(root.theme.cardBg, root.theme.alpha(root.theme.accent, 0.05))
            : root.theme.cardBg
        border.width: 1
        border.color: checked ? root.theme.accent : root.theme.alpha(root.theme.accent, 0.14)

        ColumnLayout {
            anchors.centerIn: parent
            width: parent.width - 12
            spacing: 6

            Icon {
                Layout.alignment: Qt.AlignHCenter
                name: tile.icon
                size: 18
                color: tile.checked ? root.theme.textOnAccent : root.theme.text
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                elide: Text.ElideRight
                text: tile.label
                color: tile.checked ? root.theme.textOnAccent : root.theme.text
                font.pixelSize: 12
                font.weight: Font.Medium
            }
        }

        MouseArea {
            id: tileArea
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: tile.available ? Qt.PointingHandCursor : Qt.ArrowCursor
            onClicked: if (tile.available) tile.clicked()
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 10

        Tile {
            icon: "wifi"
            label: "Wi-Fi"
            checked: Networking.wifiEnabled
            available: Networking.wifiHardwareEnabled
            onClicked: Networking.wifiEnabled = !Networking.wifiEnabled
        }

        Tile {
            icon: "bluetooth"
            label: "Bluetooth"
            checked: root.btAdapter !== null && root.btAdapter.enabled
            available: root.btAdapter !== null
            onClicked: root.btAdapter.enabled = !root.btAdapter.enabled
        }

        Tile {
            icon: "coffee"
            label: "Caffeine"
            checked: root.caffeine
            onClicked: root.caffeineToggled()
        }

        Tile {
            icon: "moon"
            label: "Do Not Disturb"
            checked: root.dnd
            available: root.notifications !== null
            onClicked: root.notifications.toggleDnd()
        }

        Tile {
            icon: "leaf"
            label: "Power Saver"
            checked: root.saver
            onClicked: PowerProfiles.profile = checked ? PowerProfile.Balanced : PowerProfile.PowerSaver
        }
    }

    // --- What's playing and the time ---
    // Taller with whatever room the page has left (no screens' brightness,
    // or only one row of it): never an empty strip at the bottom.
    RowLayout {
        Layout.fillWidth: true
        Layout.fillHeight: true
        spacing: 12

        CcCard {
            id: mediaCard
            theme: root.theme
            Layout.fillWidth: true
            Layout.fillHeight: true
            // Half and half with the time.
            Layout.preferredWidth: 1
            implicitHeight: 110

            readonly property var player: Mpris.players.values.find(p => p.isPlaying) ?? Mpris.players.values[0] ?? null

            Timer {
                interval: 1000
                running: mediaCard.player !== null && mediaCard.player.isPlaying
                repeat: true
                onTriggered: mediaCard.player.positionChanged()
            }

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pageRequested("media")
            }

            RowLayout {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                ClippingRectangle {
                    implicitWidth: 72
                    implicitHeight: 72
                    radius: 12
                    color: root.theme.track

                    Image {
                        id: miniArt
                        anchors.fill: parent
                        source: mediaCard.player ? mediaCard.player.trackArtUrl : ""
                        sourceSize: Qt.size(144, 144)
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                    }

                    Icon {
                        anchors.centerIn: parent
                        visible: miniArt.status !== Image.Ready
                        name: "music"
                        size: 26
                        color: root.theme.muted2
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    ColumnLayout {
                        spacing: 2
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: mediaCard.player ? (mediaCard.player.trackTitle || "Unknown title") : "Nothing playing"
                            font.pixelSize: 14
                            font.weight: Font.DemiBold
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: mediaCard.player
                                ? [mediaCard.player.trackArtist, mediaCard.player.identity].filter(s => s).join(" · ")
                                : "Play something to see it here"
                            color: root.theme.muted
                            font.pixelSize: 12
                        }
                    }

                    CcProgress {
                        theme: root.theme
                        Layout.fillWidth: true
                        visible: mediaCard.player !== null
                        value: mediaCard.player && mediaCard.player.length > 0 ? mediaCard.player.position / mediaCard.player.length : 0
                    }

                    RowLayout {
                        visible: mediaCard.player !== null
                        spacing: 4

                        MonoText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: mediaCard.player && mediaCard.player.lengthSupported
                                ? CcUtil.time(mediaCard.player.position) + " / " + CcUtil.time(mediaCard.player.length)
                                : ""
                            color: root.theme.muted
                            font.pixelSize: 11
                            elide: Text.ElideNone
                        }

                        CcButton {
                            theme: root.theme
                            flat: true
                            icon: "skip-back"
                            iconSize: 12
                            iconFilled: true
                            enabled: mediaCard.player !== null && mediaCard.player.canGoPrevious
                            onClicked: mediaCard.player.previous()
                        }
                        CcButton {
                            theme: root.theme
                            primary: true
                            icon: mediaCard.player && mediaCard.player.isPlaying ? "pause" : "play"
                            iconSize: 12
                            iconFilled: true
                            enabled: mediaCard.player !== null && mediaCard.player.canTogglePlaying
                            onClicked: mediaCard.player.togglePlaying()
                        }
                        CcButton {
                            theme: root.theme
                            flat: true
                            icon: "skip-forward"
                            iconSize: 12
                            iconFilled: true
                            enabled: mediaCard.player !== null && mediaCard.player.canGoNext
                            onClicked: mediaCard.player.next()
                        }
                    }
                }
            }
        }

        CcCard {
            theme: root.theme
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.preferredWidth: 1
            implicitHeight: 110

            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: root.pageRequested("weather")
            }

            // The time on the left and, to its right, the day, the date and the
            // weather; the whole group centered in the card.
            RowLayout {
                anchors.centerIn: parent
                width: Math.min(implicitWidth, parent.width - 32)
                spacing: 16

                // The time measured by its ink (without the air of the text box above or
                // the font's side bearings), to center it with the three lines next to it.
                Item {
                    implicitWidth: clockMetrics.tightBoundingRect(clockText.text).width
                    implicitHeight: clockInk.height

                    FontMetrics {
                        id: clockMetrics
                        font: clockText.font
                    }
                    readonly property rect clockInk: clockMetrics.tightBoundingRect("0")

                    MonoText {
                        id: clockText
                        theme: root.theme
                        x: -clockMetrics.tightBoundingRect(text).x
                        y: -(baselineOffset + parent.clockInk.y)
                        text: Qt.formatTime(root.now, "hh:mm")
                        color: root.theme.accent
                        font.pixelSize: 36
                        font.weight: Font.Normal
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 3

                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.now, "dddd")
                        color: root.theme.accent
                        font.weight: Font.DemiBold
                    }
                    UiText {
                        theme: root.theme
                        Layout.fillWidth: true
                        text: Qt.formatDate(root.now, "MMMM d, yyyy")
                    }
                    RowLayout {
                        visible: root.weather !== null && root.weather.ready
                        spacing: 6

                        Icon {
                            name: root.weather ? CcUtil.weatherIcon(root.weather.code, root.weather.isDay) : "cloud"
                            size: 15
                            stroke: 1.4
                            color: root.theme.accent
                        }
                        MonoText {
                            theme: root.theme
                            text: root.weather && root.weather.ready ? Math.round(root.weather.temperature) + root.weather.temperatureUnit : ""
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: root.weather ? root.weather.condition : ""
                            color: root.theme.soft
                            font.pixelSize: 12
                        }
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

    // One screen: a row like the volume's; more: half cards, two per row
    // (ControlCenter makes room for them).
    GridLayout {
        id: brightnessGrid
        readonly property int count: root.brightness ? root.brightness.displays.length : 0
        visible: count > 0
        Layout.fillWidth: true
        columns: count > 1 ? 2 : 1
        columnSpacing: 12
        rowSpacing: 12

        Repeater {
            model: root.brightness ? root.brightness.displays : []

            CcBrightnessRow {
                required property var modelData
                theme: root.theme
                Layout.fillWidth: true
                // Equal halves.
                Layout.preferredWidth: 1
                compact: brightnessGrid.count > 1
                brightness: root.brightness
                display: modelData
            }
        }
    }
}
