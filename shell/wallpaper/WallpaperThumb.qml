import QtQuick
import Quickshell.Widgets
import "../common"
import "../services"

// Thumbnail of a wallpaper (SettingsWindow's grid and the strip). Shows the
// thumbnail cached by WallpaperService; if it couldn't be generated, the
// original. Border: accent if it's the current wallpaper or hovered.
Item {
    id: root

    required property Theme theme
    required property WallpaperService wallpapers
    required property string path
    property bool selected: false
    property int radius: 8
    signal chosen()

    readonly property color idleBorder: Qt.tint(theme.base, Qt.rgba(theme.text.r, theme.text.g, theme.text.b, 0.1))

    // ClippingRectangle rather than Rectangle + clip: Qt's clip is rectangular,
    // and the image's corners covered the radius.
    ClippingRectangle {
        anchors.fill: parent
        radius: root.radius
        color: Qt.tint(root.theme.base, Qt.rgba(root.theme.text.r, root.theme.text.g, root.theme.text.b, 0.04))

        Image {
            id: image
            // If the thumbnail couldn't be generated (and thumbGen already finished), it
            // falls back to the original.
            property bool useOriginal: false

            anchors.fill: parent
            source: useOriginal ? Qt.resolvedUrl(root.path) : root.wallpapers.thumbFor(root.path)
            sourceSize.width: 400
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            onStatusChanged: if (status === Image.Error && root.wallpapers.thumbsReady) useOriginal = true

            Connections {
                target: root.wallpapers
                function onThumbsReadyChanged() {
                    if (root.wallpapers.thumbsReady && image.status === Image.Error) image.useOriginal = true
                }
            }
        }
    }

    // Video: ▶ in the corner (the thumbnail is its last frame).
    Rectangle {
        visible: root.wallpapers.videosEnabled && root.wallpapers.isVideo(root.path)
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.margins: 6
        width: 20
        height: 20
        radius: 10
        color: Qt.rgba(0, 0, 0, 0.55)

        Icon {
            anchors.centerIn: parent
            name: "play"
            filled: true
            size: 10
            stroke: 1
            color: "white"
        }
    }

    // Border on top of the image (inside the ClippingRectangle it would get
    // clipped).
    Rectangle {
        anchors.fill: parent
        radius: root.radius
        color: "transparent"
        border.width: 2
        border.color: root.selected || area.containsMouse ? root.theme.accent : root.idleBorder
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: root.chosen()
    }
}
