import QtQuick
import qs

// Base for M3 interactive containers: state layer, pointer handling, and
// shape morphing (rest → pressed / selected corner radius on a spatial spring).
Rectangle {
    id: control

    property bool checkable: false
    property bool checked: false
    property color contentColor: Colors.on_surface

    property real restRadius: height / 2
    property real pressedRadius: restRadius
    property real checkedRadius: restRadius

    property alias acceptedButtons: mouse.acceptedButtons
    property alias cursorShape: mouse.cursorShape
    property alias hoverEnabled: mouse.hoverEnabled
    readonly property alias mouseArea: mouse
    readonly property bool hovered: mouse.containsMouse && enabled
    readonly property bool pressed: mouse.pressed && enabled
    // extra emphasis, e.g. when the popup this control opens is showing
    property bool highlighted: false
    // set to receive `scrolled`; otherwise wheel events pass through to what's below
    property bool wheelEnabled: false
    // false snaps shape and colour changes (a card that is still being placed)
    property bool animate: true

    signal clicked(var mouse)
    signal scrolled(var wheel)

    radius: pressed ? pressedRadius : (checked ? checkedRadius : restRadius)
    color: "transparent"
    antialiasing: true

    Behavior on radius { enabled: control.animate; Spring {} }
    Behavior on color { enabled: control.animate; ColorFade {} }
    Behavior on contentColor { enabled: control.animate; ColorFade {} }

    StateLayer {
        tint: control.contentColor
        hovered: control.hovered
        pressed: control.pressed
        focused: control.highlighted
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: control.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: m => control.clicked(m)
        onWheel: w => {
            if (control.wheelEnabled)
                control.scrolled(w);
            else
                w.accepted = false;
        }
    }
}
