import QtQuick
import "../common"
import "fileutil.js" as Util

// A file's picture in the views: its thumbnail from the cache (see
// Thumbnails.qml), the image itself if it has none and isn't too big (it's
// decoded already scaled down), or the icon of its kind.
Item {
    id: root

    required property Theme theme
    property string path: ""
    property bool isDir: false
    property real fileSize: 0
    // The cached thumbnail's path ("" = none).
    property string thumbnail: ""
    // The icon's size when there's no picture.
    property real iconSize: 32

    // From the path: in Recent, a name can have its folder after it.
    readonly property string kind: Util.kindOf(Util.baseName(path), isDir)
    // A 20 MB PNG takes a moment to decode even scaled down (PNG can't be
    // decoded at a lower resolution); bigger ones keep their icon.
    readonly property bool decodeImage: kind === "image" && thumbnail === "" && fileSize < 20e6

    Image {
        id: picture
        anchors.fill: parent
        source: root.thumbnail !== "" ? Util.fileUri(root.thumbnail)
            : root.decodeImage ? Util.fileUri(root.path) : ""
        // In logical pixels: Qt multiplies by the screen's scale.
        sourceSize: Qt.size(Math.ceil(width), Math.ceil(height))
        fillMode: Image.PreserveAspectFit
        asynchronous: true
        cache: false
        visible: status === Image.Ready
    }

    // A thin frame around the picture, so a white photo doesn't dissolve
    // into a light background.
    Rectangle {
        visible: picture.visible
        anchors.centerIn: parent
        width: picture.paintedWidth + 2
        height: picture.paintedHeight + 2
        color: "transparent"
        border.width: 1
        border.color: root.theme.alpha(root.theme.text, 0.12)
    }

    Icon {
        anchors.centerIn: parent
        visible: !picture.visible
        name: Util.iconOf(root.kind)
        size: root.iconSize
        stroke: root.iconSize > 24 ? 1.2 : 1.5
        color: root.isDir ? root.theme.accent : root.theme.muted2
    }
}
