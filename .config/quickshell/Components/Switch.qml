import QtQuick
import qs

// M3 switch: 52×32 track, 16→24 handle (28 while pressed), optional check/close icons.
Item {
    id: sw

    property bool checked: false
    property bool showIcons: true
    readonly property bool hovered: mouse.containsMouse && enabled
    readonly property bool pressed: mouse.pressed && enabled

    signal toggled()

    implicitWidth: 52
    implicitHeight: 32
    opacity: enabled ? 1 : Motion.disabledContent
    Behavior on opacity { Fade {} }

    Rectangle {
        id: track
        anchors.fill: parent
        radius: height / 2
        color: sw.checked ? Colors.primary : Colors.surface_container_highest
        Behavior on color { ColorFade {} }
    }

    Item {
        id: handleSlot
        width: 40
        height: 40
        anchors.verticalCenter: parent.verticalCenter
        x: sw.checked ? sw.width - 36 : -4
        Behavior on x { Spring {} }

        // state layer around the handle
        Rectangle {
            anchors.fill: parent
            radius: width / 2
            color: sw.checked ? Colors.primary : Colors.on_surface
            opacity: sw.pressed ? Motion.statePressed : sw.hovered ? Motion.stateHover : 0
            Behavior on opacity { Fade {} }
            Behavior on color { ColorFade {} }
        }

        Rectangle {
            id: handle
            property real d: sw.pressed ? 28 : (sw.checked || sw.showIcons ? 24 : 16)
            anchors.centerIn: parent
            width: d
            height: d
            radius: d / 2
            color: sw.checked
                ? (sw.pressed || sw.hovered ? Colors.primary_container : Colors.on_primary)
                : (sw.pressed || sw.hovered ? Colors.on_surface_variant : Colors.outline)
            Behavior on d { Spring {} }
            Behavior on color { ColorFade {} }

            Icon {
                visible: sw.showIcons
                // the glyph turns a quarter as it swaps, with the handle's slide
                rotation: sw.checked ? 0 : -90
                Behavior on rotation { Spring {} }
                anchors.centerIn: parent
                size: 16
                name: sw.checked ? "check" : "close"
                color: sw.checked ? Colors.on_primary_container : Colors.surface_container_highest
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: sw.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: sw.toggled()
    }
}
