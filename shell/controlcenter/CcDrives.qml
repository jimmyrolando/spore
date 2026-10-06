import QtQuick
import QtQuick.Layouts
import "../common"
import "../services"

// Control Center → Drives: the external disks (DrivesService.qml). One card
// per disk with its volumes: used space, open in the file manager, mount or
// unmount; and eject the whole disk (unmounts it and powers it off, to
// unplug it safely). Only the list scrolls.
ColumnLayout {
    id: root

    required property Theme theme
    required property DrivesService service

    readonly property string subtitle: service.count === 0 ? "None connected" : service.count + " connected"

    spacing: 12

    function size(bytes: real): string {
        if (bytes >= 1e12) return (bytes / 1e12).toFixed(1) + " TB"
        if (bytes >= 1e9) return Math.round(bytes / 1e9) + " GB"
        return Math.round(bytes / 1e6) + " MB"
    }

    // Empty (or just ejected): like Notifications'.
    CcCard {
        theme: root.theme
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.service.count === 0

        ColumnLayout {
            anchors.centerIn: parent
            width: Math.min(parent.width - 48, 320)
            spacing: 0

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.bottomMargin: 16
                implicitWidth: 64
                implicitHeight: 64
                radius: 32
                color: root.service.lastEjected ? root.theme.alpha(root.theme.ok, 0.14) : root.theme.alpha(root.theme.accent, 0.1)

                Icon {
                    anchors.centerIn: parent
                    name: root.service.lastEjected ? "eject" : "hard-drive"
                    size: 26
                    stroke: 1.4
                    color: root.service.lastEjected ? root.theme.ok : root.theme.accent
                }
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: root.service.lastEjected ? "Safe to remove" : "No external drives"
                font.pixelSize: 15
                font.weight: Font.DemiBold
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                Layout.topMargin: 4
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.service.lastEjected
                    ? root.service.lastEjected + " can be unplugged now"
                    : "Connect a USB drive to see it here"
                color: root.theme.muted
                font.pixelSize: 12
            }
        }
    }

    Flickable {
        Layout.fillWidth: true
        Layout.fillHeight: true
        visible: root.service.count > 0
        contentHeight: list.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        Column {
            id: list
            width: parent.width
            spacing: 12

            Repeater {
                model: root.service.drives

                CcCard {
                    id: card
                    required property var modelData
                    readonly property bool busy: root.service.working === modelData.path
                    readonly property string message: root.service.messages[modelData.path] ?? ""

                    theme: root.theme
                    width: list.width
                    height: cardColumn.implicitHeight + 32

                    ColumnLayout {
                        id: cardColumn
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 16
                        spacing: 14

                        // Disk: name, connection and size; eject.
                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12

                            Rectangle {
                                implicitWidth: 40
                                implicitHeight: 40
                                radius: 11
                                color: root.theme.alpha(root.theme.accent, 0.1)
                                Icon {
                                    anchors.centerIn: parent
                                    name: "hard-drive"
                                    size: 18
                                    stroke: 1.4
                                    color: root.theme.accent
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 1
                                UiText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: card.modelData.name
                                    font.pixelSize: 14
                                    font.weight: Font.DemiBold
                                }
                                MonoText {
                                    theme: root.theme
                                    Layout.fillWidth: true
                                    text: [card.modelData.transport, root.size(card.modelData.size), card.modelData.path].filter(s => s).join(" · ")
                                    color: root.theme.muted
                                }
                            }

                            CcButton {
                                theme: root.theme
                                icon: "eject"
                                label: card.busy ? "Working…" : "Eject"
                                enabled: !card.busy && root.service.working === ""
                                onClicked: root.service.eject(card.modelData.path)
                            }
                        }

                        // Result of the last action (e.g. busy).
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            visible: card.message !== ""
                            text: card.message
                            color: root.theme.danger
                            font.pixelSize: 12
                            wrapMode: Text.Wrap
                        }

                        UiText {
                            theme: root.theme
                            visible: card.modelData.volumes.length === 0
                            text: "No readable volumes"
                            color: root.theme.muted
                            font.pixelSize: 12
                        }

                        // Volumes.
                        Repeater {
                            model: card.modelData.volumes

                            ColumnLayout {
                                id: volume
                                required property var modelData
                                required property int index
                                readonly property bool mounted: modelData.mountpoint !== ""
                                readonly property real pct: modelData.total > 0 ? modelData.used / modelData.total : 0

                                Layout.fillWidth: true
                                spacing: 8

                                Rectangle {
                                    Layout.fillWidth: true
                                    visible: volume.index > 0
                                    implicitHeight: 1
                                    color: root.theme.alpha(root.theme.accent, 0.1)
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 10

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 1
                                        UiText {
                                            theme: root.theme
                                            Layout.fillWidth: true
                                            text: volume.modelData.label || volume.modelData.path
                                            font.weight: Font.Medium
                                        }
                                        MonoText {
                                            theme: root.theme
                                            Layout.fillWidth: true
                                            text: volume.modelData.fstype + " · " + (volume.mounted ? volume.modelData.mountpoint : "Not mounted")
                                            color: root.theme.muted
                                            font.pixelSize: 11
                                        }
                                    }

                                    CcButton {
                                        theme: root.theme
                                        visible: volume.mounted
                                        label: "Open"
                                        onClicked: root.service.open(volume.modelData.mountpoint)
                                    }
                                    CcButton {
                                        theme: root.theme
                                        visible: volume.mounted
                                        flat: true
                                        label: "Unmount"
                                        enabled: root.service.working === ""
                                        onClicked: root.service.unmount(card.modelData.path, volume.modelData.path)
                                    }
                                    CcButton {
                                        theme: root.theme
                                        visible: !volume.mounted
                                        label: "Mount"
                                        enabled: root.service.working === ""
                                        onClicked: root.service.mount(card.modelData.path, volume.modelData.path)
                                    }
                                }

                                // Used space (only when mounted: unmounted, it isn't known).
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    visible: volume.mounted && volume.modelData.total > 0
                                    spacing: 4

                                    Rectangle {
                                        Layout.fillWidth: true
                                        implicitHeight: 5
                                        radius: 3
                                        color: root.theme.track
                                        Rectangle {
                                            width: parent.width * volume.pct
                                            height: parent.height
                                            radius: 3
                                            color: volume.pct >= 0.9 ? root.theme.danger : volume.pct >= 0.7 ? root.theme.warn : root.theme.accent
                                        }
                                    }
                                    RowLayout {
                                        MonoText {
                                            theme: root.theme
                                            Layout.fillWidth: true
                                            text: root.size(volume.modelData.used) + " used · " + Math.round(volume.pct * 100) + "%"
                                            color: root.theme.muted
                                            font.pixelSize: 11
                                        }
                                        MonoText {
                                            theme: root.theme
                                            text: root.size(Math.max(0, volume.modelData.total - volume.modelData.used)) + " free of " + root.size(volume.modelData.total)
                                            color: root.theme.muted
                                            font.pixelSize: 11
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
