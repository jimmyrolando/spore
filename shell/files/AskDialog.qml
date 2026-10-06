import QtQuick
import QtQuick.Layouts
import "../common"

// A question inside the window (a paste that finds names already there,
// deleting for good): the text, a line more, and its buttons, over the
// dimmed window. Enter answers `acceptValue`, Esc `cancelValue`.
Item {
    id: root

    required property Theme theme
    property string text: ""
    property string detail: ""
    // [{ value, label, primary, danger }]
    property var buttons: []
    property string acceptValue: buttons.length ? buttons[0].value : ""
    property string cancelValue: buttons.length ? buttons[buttons.length - 1].value : ""
    signal answered(string value)

    onVisibleChanged: if (visible) card.forceActiveFocus()

    Rectangle {
        anchors.fill: parent
        color: root.theme.alpha(root.theme.crust, 0.45)

        // The window behind waits.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
    }

    Rectangle {
        id: card
        anchors.centerIn: parent
        width: Math.min(480, parent.width - 40)
        height: column.implicitHeight + 40
        radius: 14
        color: root.theme.base
        border.width: 1
        border.color: root.theme.accent

        Keys.onReturnPressed: root.answered(root.acceptValue)
        Keys.onEnterPressed: root.answered(root.acceptValue)
        Keys.onEscapePressed: root.answered(root.cancelValue)

        ColumnLayout {
            id: column
            anchors.fill: parent
            anchors.margins: 20
            spacing: 8

            UiText {
                theme: root.theme
                Layout.fillWidth: true
                text: root.text
                font.pixelSize: 14
                font.weight: Font.DemiBold
                wrapMode: Text.Wrap
            }
            UiText {
                theme: root.theme
                Layout.fillWidth: true
                visible: root.detail !== ""
                text: root.detail
                color: root.theme.muted
                wrapMode: Text.Wrap
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.topMargin: 10
                spacing: 8

                Item { Layout.fillWidth: true }

                Repeater {
                    model: root.buttons

                    CcButton {
                        required property var modelData
                        theme: root.theme
                        size: 32
                        label: modelData.label
                        primary: modelData.primary === true
                        danger: modelData.danger === true
                        onClicked: root.answered(modelData.value)
                    }
                }
            }
        }
    }
}
