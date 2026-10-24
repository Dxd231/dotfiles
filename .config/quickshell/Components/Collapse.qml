import QtQuick
import QtQuick.Layouts
import qs

// Opens and closes its one child in a layout: the space it takes springs between nothing and the child's
// size (height, or width when `horizontal`) while it fades, so the things around it slide along instead of
// jumping, and closing plays out instead of vanishing. Use it for a section or a button that a state shows
// or hides. The child is sized across the other axis to the Collapse.
// A layout's `spacing` around it still snaps in and out (it only counts visible items), so in a layout with
// collapsing sections set the spacing to 0 and give each Collapse a `gap`: space before the child that
// opens and closes with it.
Item {
    id: c

    property bool open: true
    property bool horizontal: false
    property real gap: 0
    // false snaps it open or shut (a card that is still being placed)
    property bool animate: true
    default property alias content: holder.data

    property real reveal: open ? 1 : 0
    Behavior on reveal { enabled: animate; Spring { speed: "default"; expressive: false } }
    readonly property real _r: Math.max(0, Math.min(1, reveal))
    readonly property Item _child: holder.children.length > 0 ? holder.children[0] : null
    readonly property real _cw: _child ? _child.implicitWidth : 0
    readonly property real _ch: _child ? _child.implicitHeight : 0

    implicitWidth: horizontal ? (_cw + gap) * _r : _cw
    implicitHeight: horizontal ? _ch : (_ch + gap) * _r
    Layout.fillWidth: !horizontal
    visible: open || reveal > 0.01
    opacity: _r
    clip: true

    Item {
        id: holder
        x: c.horizontal ? c.gap : 0
        y: c.horizontal ? 0 : c.gap
        width: c.horizontal ? c._cw : c.width
        height: c.horizontal ? c.height : c._ch
    }
    Binding { target: c._child; property: "width"; value: c.width; when: c._child !== null && !c.horizontal }
    Binding { target: c._child; property: "height"; value: c.height; when: c._child !== null && c.horizontal }
}
