import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import "../common"
import "fileutil.js" as Util

// "Open with…", over the dimmed window: the apps the system has for this kind
// of file (gio mime), the default first, with their names and icons (the same
// desktop entries a launcher shows). "Other apps" lists every app. A click
// opens the file with it; with "Always" on, that app becomes the default for
// this kind of file (gio mime writes it in ~/.config/mimeapps.list). Esc or a
// click outside closes it.
Item {
    id: root

    required property Theme theme
    // The file ({ name, path, … }); set, the dialog shows.
    property var entry: null
    // desktopId like "org.gnome.Loupe.desktop"; always: make it the default for
    // mimeType.
    signal chosen(string desktopId, bool always, string mimeType)
    signal canceled()

    property string mimeType: ""
    // The desktop ids gio knows for the type, the default first.
    property var ids: []
    property string defaultId: ""
    property bool showAll: false
    property bool always: false

    visible: entry !== null
    onEntryChanged: if (entry) load()
    onVisibleChanged: if (visible) card.forceActiveFocus()

    function load(): void {
        mimeType = ""
        ids = []
        defaultId = ""
        showAll = false
        always = false
        typer.command = ["gio", "info", "-a", "standard::content-type", "--", entry.path]
        typer.running = true
    }

    Process {
        id: typer
        stdout: StdioCollector {
            onStreamFinished: {
                root.mimeType = (text.match(/standard::content-type: (\S+)/) || [])[1] || "application/octet-stream"
                lister.command = ["gio", "mime", root.mimeType]
                lister.running = true
            }
        }
    }

    // "Default application for “x”: a.desktop", then "Registered
    // applications:" and "Recommended applications:" with an id per line.
    Process {
        id: lister
        stdout: StdioCollector {
            onStreamFinished: {
                const found = []
                let first = ""
                for (const line of text.split("\n")) {
                    const def = line.match(/: (\S+\.desktop)$/)
                    if (def && line.startsWith("Default")) first = def[1]
                    const listed = line.match(/^\s+(\S+\.desktop)$/)
                    if (listed && !found.includes(listed[1])) found.push(listed[1])
                }
                root.defaultId = first
                root.ids = first ? [first].concat(found.filter(id => id !== first)) : found
            }
        }
    }

    // { id, name, icon } for each app that's installed (a registered id with
    // no desktop entry is left out). Quickshell reads the apps in the
    // background: the list is remade when they arrive.
    readonly property var apps: {
        const all = DesktopEntries.applications.values
        if (showAll) {
            return all
                .filter(app => !app.noDisplay)
                .map(app => ({ id: app.id + ".desktop", name: app.name, icon: app.icon }))
                .sort((a, b) => a.name.localeCompare(b.name))
        }
        const out = []
        for (const id of ids) {
            const app = DesktopEntries.byId(id.replace(/\.desktop$/, ""))
            // The same app installed twice (two ids, one name): once.
            if (app && !out.some(a => a.name === app.name)) out.push({ id: id, name: app.name, icon: app.icon })
        }
        return out
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.alpha(root.theme.crust, 0.45)

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: root.canceled()
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(420, parent.width - 40)
        height: Math.min(parent.height - 60, column.implicitHeight + 36)
        radius: 14
        color: root.theme.base
        border.width: 1
        border.color: root.theme.accent

        Keys.onEscapePressed: root.canceled()

        // Clicks on the card stay on the card.
        MouseArea {
            anchors.fill: parent
        }

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 18
            spacing: 10

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                text: root.entry ? "Open “" + root.entry.name + "” with" : ""
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideMiddle
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(contentHeight, 340)
                Layout.fillHeight: true
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                model: root.apps

                delegate: Rectangle {
                    id: app
                    required property var modelData
                    width: list.width
                    height: 40
                    radius: 9
                    color: appArea.containsMouse ? root.theme.accentHover : "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 10
                        anchors.rightMargin: 10
                        spacing: 12

                        Item {
                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24

                            Image {
                                id: appIcon
                                anchors.fill: parent
                                source: app.modelData.icon ? Quickshell.iconPath(app.modelData.icon, true) : ""
                                sourceSize: Qt.size(24, 24)
                                visible: status === Image.Ready
                            }
                            Icon {
                                anchors.centerIn: parent
                                visible: !appIcon.visible
                                name: "app-window"
                                size: 18
                                color: root.theme.ink2
                            }
                        }
                        UiText {
                            theme: root.theme
                            Layout.fillWidth: true
                            text: app.modelData.name
                        }
                        UiText {
                            theme: root.theme
                            visible: app.modelData.id === root.defaultId && !root.showAll
                            text: "Default"
                            color: root.theme.muted
                            font.pixelSize: 11
                        }
                    }

                    MouseArea {
                        id: appArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.chosen(app.modelData.id, root.always, root.mimeType)
                    }
                }
            }

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                visible: root.apps.length === 0 && root.mimeType !== ""
                text: "No app is registered for this kind of file: try Other apps"
                color: root.theme.muted
            }

            // Always use the chosen one for this kind of file.
            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                CcSwitch {
                    theme: root.theme
                    checked: root.always
                    onToggled: root.always = !root.always
                }
                UiText {
                    theme: root.theme
                    Layout.fillWidth: true
                    text: "Always open " + (root.entry ? Util.kindLabel(Util.baseName(root.entry.path), false) : "") + " files with it"
                    color: root.theme.muted
                    font.pixelSize: 12
                    wrapMode: Text.Wrap
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                CcButton {
                    theme: root.theme
                    size: 30
                    flat: true
                    visible: !root.showAll
                    label: "Other apps"
                    onClicked: root.showAll = true
                }
                Item { Layout.fillWidth: true }
                CcButton {
                    theme: root.theme
                    size: 30
                    label: "Cancel"
                    onClicked: root.canceled()
                }
            }
        }
    }
}
