import QtQuick
import qs

// One segment of an M3 Expressive connected button group (place in a Row with spacing 2).
// Outer corners stay fully round; inner corners are 8px, 4px while pressed, and the
// whole segment rounds fully when selected.
Clickable {
    id: segment

    property string text
    property string icon
    property string position: "middle" // first | middle | last | only
    property bool selected: false

    readonly property real _outer: height / 2
    property real _inner: selected ? height / 2 : pressed ? Motion.shapeExtraSmall : Motion.shapeSmall
    Behavior on _inner { Spring {} }

    implicitHeight: 32
    implicitWidth: Math.max(0, _w)
    property real _w: row.implicitWidth + 24
    Behavior on _w { Spring { speed: "fast" } }
    restRadius: _outer
    pressedRadius: _outer
    topLeftRadius: position === "first" || position === "only" ? _outer : _inner
    bottomLeftRadius: position === "first" || position === "only" ? _outer : _inner
    topRightRadius: position === "last" || position === "only" ? _outer : _inner
    bottomRightRadius: position === "last" || position === "only" ? _outer : _inner
    color: selected ? Colors.secondary : Colors.secondary_container
    contentColor: selected ? Colors.on_secondary : Colors.on_secondary_container

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon {
            visible: segment.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: segment.selected ? "check" : segment.icon
            size: 18
            color: segment.contentColor
            fadeColor: false
        }
        StyledText {
            visible: segment.text !== ""
            anchors.verticalCenter: parent.verticalCenter
            role: "labelLarge"
            text: segment.text
            color: segment.contentColor
            fadeColor: false
        }
    }
}
