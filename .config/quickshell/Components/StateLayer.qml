import QtQuick
import qs

// M3 interaction state overlay; fills its parent and follows the parent's corner shape.
Rectangle {
    property bool hovered: false
    property bool pressed: false
    property bool focused: false
    property bool dragged: false
    // the content (on-) color of the component this layer sits on
    property color tint: Colors.on_surface

    anchors.fill: parent
    radius: parent ? parent.radius : 0
    topLeftRadius: parent && parent.topLeftRadius !== undefined ? parent.topLeftRadius : radius
    topRightRadius: parent && parent.topRightRadius !== undefined ? parent.topRightRadius : radius
    bottomLeftRadius: parent && parent.bottomLeftRadius !== undefined ? parent.bottomLeftRadius : radius
    bottomRightRadius: parent && parent.bottomRightRadius !== undefined ? parent.bottomRightRadius : radius
    color: tint
    opacity: dragged ? Motion.stateDragged : pressed ? Motion.statePressed : focused ? Motion.stateFocus : hovered ? Motion.stateHover : 0
    visible: opacity > 0

    Behavior on opacity { Fade {} }
    Behavior on color { ColorFade {} }
}
