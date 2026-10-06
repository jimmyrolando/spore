import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import "../common"
import "../services"

// Clipboard history (Mod+Alt+V): search, filters, the list and, on the
// right, the preview with Copy / Pin / Delete. The data and actions come
// from ClipboardService.qml.
//
// Keyboard: typing searches; ↑/↓ selects; Enter copies and closes (then
// paste with Ctrl+V); Tab changes the filter; Ctrl+P pins; Shift+Del
// deletes; Esc closes. shell.qml loads it with a LazyLoader only while it's
// open.
PanelWindow {
    id: root

    required property Theme theme
    required property ClipboardService clipboard

    signal closeRequested()

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-clipboard"
    // OnDemand, like Settings: Exclusive broke niri's focus.
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    // No anchors: centered. width/height and not implicit* (see SettingsWindow).
    width: 880
    height: 560
    color: "transparent"

    Component.onCompleted: clipboard.refresh()

    // The compositor's window radius (Compositor.qml).
    property Compositor compositor: null

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
    readonly property color soft: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.75)
    readonly property color muted: Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.55)
    readonly property var ansi: theme.current.ansi || []

    function kindColor(kind: string): color {
        switch (kind) {
        case "img": return ansi[2] ?? theme.accent
        case "url": return ansi[4] ?? theme.accent
        case "code": return theme.accent
        case "hex": return ansi[3] ?? theme.accent
        }
        return muted
    }

    readonly property var kindTag: ({ txt: "TXT", img: "IMG", url: "URL", code: "CODE", hex: "HEX" })
    readonly property var kindName: ({ txt: "Text", img: "Image", url: "Link", code: "Code", hex: "Color" })

    // --- Filter and selection --------------------------------------------------

    readonly property var filters: [
        { id: "all", label: "All" },
        { id: "text", label: "Text" },
        { id: "images", label: "Images" },
        { id: "links", label: "Links" }
    ]
    property string filter: "all"
    property string query: ""

    function matchesFilter(e: var): bool {
        switch (filter) {
        case "text": return e.kind === "txt" || e.kind === "code" || e.kind === "hex"
        case "images": return e.kind === "img"
        case "links": return e.kind === "url"
        }
        return true
    }

    readonly property var visibleEntries: clipboard.entries.filter(e =>
        matchesFilter(e) && (query === "" || e.preview.toLowerCase().includes(query.toLowerCase())))

    property int currentIndex: 0
    readonly property var current: visibleEntries[Math.min(currentIndex, visibleEntries.length - 1)] ?? null

    onVisibleEntriesChanged: currentIndex = Math.max(0, Math.min(currentIndex, visibleEntries.length - 1))
    onCurrentChanged: if ((current ? current.key : "") !== clipboard.detailKey) clipboard.loadDetail(current)

    function move(delta: int): void {
        if (visibleEntries.length === 0) return
        currentIndex = Math.max(0, Math.min(visibleEntries.length - 1, currentIndex + delta))
        list.positionViewAtIndex(currentIndex, ListView.Contain)
    }

    function copyCurrent(): void {
        if (!current) return
        clipboard.copy(current)
        root.closeRequested()
    }

    function titleOf(e: var): string {
        if (e.image) return "Image · " + e.image.width + "×" + e.image.height + " · " + e.image.format.toUpperCase()
        return e.preview.trim()
    }

    // "now", "5m", "2h", "3d" (with no known time: nothing).
    function ago(epoch: int): string {
        if (!epoch) return ""
        const s = Math.max(0, Math.floor(Date.now() / 1000) - epoch)
        if (s < 60) return "now"
        if (s < 3600) return Math.floor(s / 60) + "m"
        if (s < 86400) return Math.floor(s / 3600) + "h"
        return Math.floor(s / 86400) + "d"
    }

    // Refreshes the "5m" labels while it's open.
    property int tick: 0
    Timer {
        interval: 30000
        running: true
        repeat: true
        onTriggered: root.tick++
    }

    // "Clear all" asks for a second click; it expires after 3 s.
    property bool confirmWipe: false
    Timer {
        id: wipeTimer
        interval: 3000
        onTriggered: root.confirmWipe = false
    }

    // Font for the clipboard content by its type: code, links and colors in the
    // monospace one; regular text in Noto Sans.
    function contentFont(kind: string): string {
        return kind === "code" || kind === "url" || kind === "hex" ? theme.fontFamily : theme.uiFont
    }

    // Interface text in Noto Sans (the brand's). Plain text, never markup
    // (see UiText.qml).
    component Label: Text {
        color: root.theme.text
        font.family: root.theme.uiFont
        font.pixelSize: 13
        textFormat: Text.PlainText
    }

    component PanelButton: Rectangle {
        id: button
        property string label: ""
        property bool primary: false
        property bool danger: false
        signal clicked()

        implicitWidth: buttonLabel.implicitWidth + 32
        implicitHeight: 36
        radius: 8
        color: primary ? (area.containsMouse ? Qt.lighter(root.theme.accent, 1.08) : root.theme.accent)
            : danger ? (area.containsMouse ? Qt.rgba(root.theme.error.r, root.theme.error.g, root.theme.error.b, 0.15) : "transparent")
            : (area.containsMouse ? root.buttonHover : root.button)

        Label {
            id: buttonLabel
            anchors.centerIn: parent
            text: button.label
            color: button.primary ? root.theme.textOnAccent
                : button.danger ? (area.containsMouse ? root.theme.error : root.muted)
                : root.theme.text
            font.pixelSize: 14
            font.weight: button.primary ? Font.Medium : Font.Normal
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

        RowLayout {
            anchors.fill: parent
            anchors.margins: 1
            spacing: 0

            // --- Left: search, filters, list ---
            ColumnLayout {
                // Fixed width: the search text (or an empty list) doesn't stretch it.
                Layout.preferredWidth: 360
                Layout.maximumWidth: 360
                Layout.fillHeight: true
                Layout.margins: 18
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
                        Keys.onReturnPressed: root.copyCurrent()
                        Keys.onEnterPressed: root.copyCurrent()
                        Keys.onTabPressed: {
                            const i = root.filters.findIndex(f => f.id === root.filter)
                            root.filter = root.filters[(i + 1) % root.filters.length].id
                        }
                        Keys.onPressed: (event) => {
                            if (event.key === Qt.Key_P && (event.modifiers & Qt.ControlModifier)) {
                                if (root.current) root.clipboard.togglePin(root.current)
                                event.accepted = true
                            } else if (event.key === Qt.Key_Delete && (event.modifiers & Qt.ShiftModifier)) {
                                if (root.current) root.clipboard.remove(root.current)
                                event.accepted = true
                            } else if (event.key === Qt.Key_PageDown) {
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
                            text: "Search clipboard"
                            color: root.muted
                            font.pixelSize: 14
                        }
                    }
                }

                // Filters.
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 38
                    radius: 10
                    color: root.paneBg

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 3
                        spacing: 2

                        Repeater {
                            model: root.filters

                            Rectangle {
                                required property var modelData
                                readonly property bool active: modelData.id === root.filter

                                Layout.fillWidth: true
                                Layout.fillHeight: true
                                radius: 8
                                color: active ? root.theme.accent : filterArea.containsMouse ? root.buttonHover : "transparent"

                                Label {
                                    anchors.centerIn: parent
                                    text: parent.modelData.label
                                    color: parent.active ? root.theme.textOnAccent : root.theme.text
                                    font.pixelSize: 13
                                }

                                MouseArea {
                                    id: filterArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.filter = parent.modelData.id
                                }
                            }
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
                    model: root.visibleEntries

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === root.currentIndex

                        width: list.width
                        height: 60
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

                        ColumnLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 12
                            anchors.topMargin: 9
                            anchors.bottomMargin: 9
                            spacing: 4

                            Label {
                                Layout.fillWidth: true
                                text: root.titleOf(row.modelData)
                                font.family: root.contentFont(row.modelData.kind)
                                font.pixelSize: 14
                                elide: Text.ElideRight
                                maximumLineCount: 1
                                textFormat: Text.PlainText
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 6

                                // Color swatch (HEX).
                                Rectangle {
                                    visible: row.modelData.kind === "hex"
                                    implicitWidth: 10
                                    implicitHeight: 10
                                    radius: 3
                                    color: row.modelData.kind === "hex"
                                        ? (row.modelData.preview.trim().startsWith("#") ? row.modelData.preview.trim() : "#" + row.modelData.preview.trim())
                                        : "transparent"
                                    border.width: 1
                                    border.color: root.subtle
                                }

                                Label {
                                    text: root.kindTag[row.modelData.kind]
                                    font.family: root.theme.fontFamily
                                    color: root.kindColor(row.modelData.kind)
                                    font.pixelSize: 12
                                    font.weight: Font.Medium
                                }

                                Item { Layout.fillWidth: true }

                                Label {
                                    text: {
                                        root.tick
                                        const t = root.ago(row.modelData.time)
                                        return row.modelData.pinned ? "Pinned" + (t ? " · " + t : "") : t
                                    }
                                    color: root.muted
                                    font.pixelSize: 12
                                }
                            }
                        }

                        MouseArea {
                            id: rowArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.currentIndex = row.index
                            onDoubleClicked: root.copyCurrent()
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        text: root.clipboard.entries.length === 0 ? "Clipboard is empty" : "No matches"
                        color: root.muted
                    }
                }

                // Count and "Clear all".
                RowLayout {
                    Layout.fillWidth: true

                    Label {
                        Layout.fillWidth: true
                        text: root.clipboard.entries.length + (root.clipboard.entries.length === 1 ? " item" : " items")
                        color: root.muted
                        font.pixelSize: 12
                    }

                    Label {
                        visible: root.clipboard.entries.some(e => !e.pinned)
                        text: root.confirmWipe ? "Confirm?" : "Clear all"
                        color: root.confirmWipe || wipeArea.containsMouse ? root.theme.error : root.muted
                        font.pixelSize: 12

                        MouseArea {
                            id: wipeArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (!root.confirmWipe) {
                                    root.confirmWipe = true
                                    wipeTimer.restart()
                                    return
                                }
                                root.confirmWipe = false
                                root.clipboard.wipe()
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillHeight: true
                implicitWidth: 1
                color: root.subtle
            }

            // --- Right: preview and actions ---
            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.margins: 24
                spacing: 16

                // Header: type, size and time, and the ✕ (as in Settings).
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12

                    ColumnLayout {
                        Layout.fillWidth: true
                        visible: root.current !== null
                        spacing: 4

                        // fillWidth on a child: otherwise the ColumnLayout doesn't grow and the time
                        // sticks to the type.
                        Label {
                            Layout.fillWidth: true
                            text: root.current ? root.kindName[root.current.kind].toUpperCase() : ""
                            color: root.theme.accent
                            font.pixelSize: 13
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                        }

                        Label {
                            text: {
                                const e = root.current
                                if (!e) return ""
                                if (e.image) return e.image.width + "×" + e.image.height + " · " + e.image.format.toUpperCase() + " · " + e.image.size
                                const t = root.clipboard.detailKey === e.key ? root.clipboard.detailText : ""
                                if (!t) return ""
                                const lines = t.replace(/\n$/, "").split("\n").length
                                return t.length + " chars · " + lines + (lines === 1 ? " line" : " lines")
                            }
                            color: root.muted
                            font.pixelSize: 13
                        }
                    }

                    Label {
                        Layout.alignment: Qt.AlignTop
                        text: {
                            root.tick
                            return root.current ? root.ago(root.current.time) : ""
                        }
                        color: root.muted
                    }

                    Item {
                        Layout.fillWidth: true
                        visible: root.current === null
                    }

                    // Close: 36x36 and radius 8, the same as Settings'.
                    Rectangle {
                        Layout.alignment: Qt.AlignTop
                        implicitWidth: 36
                        implicitHeight: 36
                        radius: 8
                        color: closeArea.containsMouse ? root.buttonHover : root.button

                        Icon {
                            anchors.centerIn: parent
                            name: "x"
                            size: 15
                            stroke: 1.4
                            color: root.theme.text
                        }

                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.closeRequested()
                        }
                    }
                }

                // Content.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: 12
                    color: root.inputBg
                    border.width: 1
                    border.color: root.subtle
                    clip: true

                    // Text (selectable, with scrolling).
                    Flickable {
                        id: textFlick
                        anchors.fill: parent
                        anchors.margins: 18
                        visible: root.current !== null && !root.current.image && root.current.kind !== "hex"
                        contentWidth: width
                        contentHeight: detail.implicitHeight
                        boundsBehavior: Flickable.StopAtBounds
                        clip: true

                        TextEdit {
                            id: detail
                            width: textFlick.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            textFormat: TextEdit.PlainText
                            text: root.current && root.clipboard.detailKey === root.current.key
                                ? root.clipboard.detailText : ""
                            color: root.theme.text
                            selectionColor: root.theme.accent
                            selectedTextColor: root.theme.textOnAccent
                            font.family: root.current ? root.contentFont(root.current.kind) : root.theme.uiFont
                            font.pixelSize: 14
                        }
                    }

                    // Image.
                    Image {
                        anchors.fill: parent
                        anchors.margins: 12
                        visible: root.current !== null && root.current.image !== null
                        source: root.clipboard.detailImage && root.current && root.clipboard.detailKey === root.current.key
                            ? Qt.resolvedUrl(root.clipboard.detailImage) : ""
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        sourceSize.width: 1200
                    }

                    // Color.
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: root.current !== null && root.current.kind === "hex"
                        spacing: 14

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 140
                            implicitHeight: 140
                            radius: 16
                            color: {
                                const e = root.current
                                if (!e || e.kind !== "hex") return "transparent"
                                const v = e.preview.trim()
                                return v.startsWith("#") ? v : "#" + v
                            }
                            border.width: 1
                            border.color: root.subtle
                        }

                        Label {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.current ? root.current.preview.trim() : ""
                            font.family: root.theme.fontFamily
                            font.pixelSize: 18
                        }
                    }

                    Label {
                        anchors.centerIn: parent
                        visible: root.current === null
                        text: "Nothing selected"
                        color: root.muted
                    }
                }

                // Actions.
                RowLayout {
                    Layout.fillWidth: true
                    visible: root.current !== null
                    spacing: 10

                    PanelButton {
                        label: "Copy"
                        primary: true
                        onClicked: root.copyCurrent()
                    }

                    PanelButton {
                        label: root.current && root.current.pinned ? "Unpin" : "Pin"
                        onClicked: if (root.current) root.clipboard.togglePin(root.current)
                    }

                    PanelButton {
                        label: "Delete"
                        danger: true
                        onClicked: if (root.current) root.clipboard.remove(root.current)
                    }

                    Item { Layout.fillWidth: true }
                }
            }
        }
    }
}
