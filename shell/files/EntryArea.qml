import QtQuick

// An entry's mouse in the views (FileGrid, FileList): a click selects (with
// Ctrl adds or takes away, with Shift selects up to it), a double click
// opens, the right button asks for the menu, and dragging with the left one
// takes the files somewhere: the view passes it on to the window, which
// draws what's dragged and drops it.
MouseArea {
    id: area

    // The view, whose signals these are, and the entry's row.
    required property Item view
    required property int rowIndex

    // Moved far enough while pressed: a drag, and its release isn't a click.
    property point pressedAt
    property bool dragging: false

    hoverEnabled: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    // Dragging an entry moves files, it doesn't scroll the view.
    preventStealing: true

    onPressed: (mouse) => {
        pressedAt = Qt.point(mouse.x, mouse.y)
        dragging = false
    }
    onPositionChanged: (mouse) => {
        if (!(mouse.buttons & Qt.LeftButton)) return
        const at = mapToItem(null, mouse.x, mouse.y)
        if (dragging) {
            view.entryDragMoved(at, mouse.modifiers)
        } else if (Math.hypot(mouse.x - pressedAt.x, mouse.y - pressedAt.y) >= Qt.styleHints.startDragDistance) {
            dragging = true
            view.entryDragStarted(rowIndex, at, mouse.modifiers)
        }
    }
    onReleased: (mouse) => {
        if (dragging) view.entryDragEnded(mouse.modifiers)
    }
    onCanceled: {
        if (dragging) view.entryDragCanceled()
        dragging = false
    }
    onClicked: (mouse) => {
        if (dragging) return
        // The keyboard to the view first: the menu that opens takes it after
        // (otherwise Esc would reach the view, clearing the selection, and
        // not the menu).
        view.forceActiveFocus()
        if (mouse.button === Qt.RightButton) {
            const point = mapToItem(null, mouse.x, mouse.y)
            view.menuRequested(rowIndex, point.x, point.y)
        } else {
            view.picked(rowIndex, mouse.modifiers)
        }
    }
    onDoubleClicked: (mouse) => {
        if (mouse.button === Qt.LeftButton) view.activated(rowIndex)
    }
}
