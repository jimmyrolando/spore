import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// Control Center ("Control Center v2" design): a 620x600 panel with the
// pages as tabs at the top (plus Settings and close) and the chosen page.
// It opens below the bar, on the side of the widget that opened it (a click
// on each one opens its page). shell.qml loads it with a LazyLoader only
// while it's open; each page is created when shown (so the wifi only scans
// for networks with Network open).
PanelWindow {
    id: root

    required property Theme theme
    property string tab: "home"
    // Height taken by the bar: the window goes right below it.
    property int topOffset: 36
    // Home's header: the wallpaper already cropped (see heroGen in shell.qml).
    property string heroSource: ""
    property Weather weather: null
    property bool caffeine: false
    property NotificationService notifications: null
    property SystemMonitor monitor: null
    // Name, user@host and photo for Home (UserInfo.qml).
    property UserInfo user: null
    property DrivesService drives: null
    // Pairing with an agent (the Bluetooth page).
    property BluetoothAgent bluetoothAgent: null
    // The compositor (Compositor.qml), for the System page.
    property Compositor compositor: null

    signal closeRequested()
    signal tabRequested(string tab)
    signal caffeineToggled()
    signal settingsRequested()
    signal wallpaperPickerRequested()
    signal avatarPickerRequested()

    // The pages' width is the old one with the rail on the side (680 - 60).
    readonly property int panelWidth: 620
    readonly property int panelHeight: 600

    // Which side of the screen it comes out on, below the bar zone of the widget
    // that opened it: "left", "center" (anchored to the top only: centered) or
    // "right".
    property string side: "right"

    anchors { top: true; left: side === "left"; right: side === "right" }
    margins { top: topOffset + 8; left: 16; right: 16 }
    exclusionMode: ExclusionMode.Ignore
    implicitWidth: panelWidth
    implicitHeight: panelHeight
    color: "transparent"
    mask: Region { item: panel }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-control-center"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    readonly property var pages: [
        // icon: a Lucide name (lucide.js, see Icon.qml).
        { id: "home", label: "Home", icon: "house" },
        { id: "media", label: "Media", icon: "music" },
        { id: "audio", label: "Audio", icon: "volume-2" },
        { id: "system", label: "System", icon: "cpu" },
        { id: "network", label: "Network", icon: "wifi" },
        { id: "bluetooth", label: "Bluetooth", icon: "bluetooth" },
        { id: "drives", label: "Drives", icon: "eject" },
        { id: "weather", label: "Weather", icon: "cloud-sun" },
        { id: "calendar", label: "Calendar", icon: "calendar" },
        { id: "notifications", label: "Notifications", icon: "bell" }
    ]
    readonly property var current: pages.find(p => p.id === tab) || pages[0]
    // Pending (the badge): the ones that arrived since Notifications was last
    // opened.
    readonly property int unread: notifications ? notifications.unread : 0

    Rectangle {
        id: panel
        width: root.panelWidth
        height: root.panelHeight
        radius: 20
        color: root.theme.panelBg
        border.width: 1
        border.color: root.theme.panelBorder
        clip: true
        // Keys and not Shortcut (see SettingsWindow).
        focus: true
        Keys.onEscapePressed: root.closeRequested()

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // --- Tabs: the pages in a row, and Settings and close on the right. At the
            // top rather than in a rail on the side: the panel looks even whichever side
            // it comes out on (left, center or right).
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 56
                color: root.theme.railBg
                // The panel clips the top corners (clip + radius): the band rounds them
                // the same way.
                topLeftRadius: 19
                topRightRadius: 19

                // Line on the page's side.
                Rectangle {
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 1
                    color: root.theme.alpha(root.theme.accent, 0.1)
                }

                component TabButton: Rectangle {
                    id: tabButton
                    property string icon: ""
                    property real stroke: 1.5
                    property bool selected: false
                    property string badge: ""
                    signal clicked()

                    implicitWidth: 40
                    implicitHeight: 40
                    radius: 11
                    color: selected ? root.theme.accent
                        : tabArea.containsMouse ? root.theme.alpha(root.theme.accent, 0.16)
                        : "transparent"

                    Icon {
                        anchors.centerIn: parent
                        name: tabButton.icon
                        size: 18
                        stroke: tabButton.stroke
                        color: tabButton.selected ? root.theme.textOnAccent : root.theme.ink2
                    }

                    Rectangle {
                        visible: tabButton.badge !== ""
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 7
                        width: Math.max(14, badgeText.implicitWidth + 6)
                        height: 14
                        radius: 7
                        color: root.theme.danger

                        Text {
                            id: badgeText
                            anchors.centerIn: parent
                            text: tabButton.badge
                            color: root.theme.onColor
                            font.family: root.theme.fontFamily
                            font.pixelSize: 9
                        }
                    }

                    MouseArea {
                        id: tabArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: tabButton.clicked()
                    }
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 3

                    Repeater {
                        model: root.pages

                        TabButton {
                            required property var modelData
                            icon: modelData.icon
                            selected: modelData.id === root.current.id
                            badge: modelData.id === "notifications" && root.unread > 0 ? String(Math.min(root.unread, 99)) : ""
                            onClicked: root.tabRequested(modelData.id)
                        }
                    }

                    Item { Layout.fillWidth: true }

                    TabButton {
                        icon: "settings"
                        stroke: 1.4
                        onClicked: root.settingsRequested()
                    }

                    TabButton {
                        icon: "x"
                        onClicked: root.closeRequested()
                    }
                }
            }

            // --- Page ---
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 14
                Layout.bottomMargin: 12
                spacing: 12

                UiText {
                    theme: root.theme
                    Layout.alignment: Qt.AlignBaseline
                    text: root.current.label
                    font.pixelSize: 19
                    font.weight: Font.DemiBold
                }

                MonoText {
                    theme: root.theme
                    Layout.fillWidth: true
                    Layout.alignment: Qt.AlignBaseline
                    text: page.item && page.item.subtitle !== undefined ? page.item.subtitle : ""
                    color: root.theme.muted
                }
            }

            Loader {
                id: page
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.bottomMargin: 20
                sourceComponent: ({ home: homePage, media: mediaPage, audio: audioPage, system: systemPage, network: networkPage,
                    bluetooth: bluetoothPage, drives: drivesPage, weather: weatherPage, calendar: calendarPage,
                    notifications: notificationsPage })[root.current.id]
            }
        }
    }

    Component {
        id: homePage
        CcHome {
            theme: root.theme
            user: root.user
            heroSource: root.heroSource
            weather: root.weather
            monitor: root.monitor
            caffeine: root.caffeine
            notifications: root.notifications
            onCaffeineToggled: root.caffeineToggled()
            onPageRequested: (id) => root.tabRequested(id)
            onWallpaperPickerRequested: root.wallpaperPickerRequested()
            onAvatarPickerRequested: root.avatarPickerRequested()
        }
    }

    Component {
        id: mediaPage
        CcMedia {
            theme: root.theme
            onPageRequested: (id) => root.tabRequested(id)
        }
    }

    Component {
        id: audioPage
        CcAudio { theme: root.theme }
    }

    Component {
        id: networkPage
        CcNetwork { theme: root.theme }
    }

    Component {
        id: bluetoothPage
        CcBluetooth {
            theme: root.theme
            agent: root.bluetoothAgent
        }
    }

    Component {
        id: drivesPage
        CcDrives {
            theme: root.theme
            service: root.drives
        }
    }

    Component {
        id: systemPage
        CcSystem {
            theme: root.theme
            compositor: root.compositor
            monitor: root.monitor
        }
    }

    Component {
        id: weatherPage
        CcWeather {
            theme: root.theme
            weather: root.weather
        }
    }

    Component {
        id: calendarPage
        CcCalendar { theme: root.theme }
    }

    Component {
        id: notificationsPage
        CcNotifications {
            theme: root.theme
            service: root.notifications
        }
    }
}
