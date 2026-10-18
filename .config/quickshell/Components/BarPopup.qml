pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs

// Floating panel that drops down from a bar item: surface-container, 28px corners,
// level-3 elevation, expressive spring entrance from the anchor, accelerated exit.
// Children go into a padded ColumnLayout.
PanelWindow {
    id: popup

    property Item anchorItem: null
    property bool isOpen: false
    property real panelWidth: 360
    property int padding: 16
    property alias spacing: body.spacing
    property color panelColor: Colors.surface_container
    property alias panel: panel
    default property alias content: body.data

    readonly property int _shadowPad: 16

    function toggle() { isOpen = !isOpen; }
    function show() { isOpen = true; }
    function hide() { isOpen = false; }

    function reposition() {
        if (!anchorItem)
            return;
        const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0);
        const sw = screen ? screen.width : 1920;
        margins.left = Math.max(0, Math.min(sw - implicitWidth, Math.round(p.x - implicitWidth / 2)));
    }
    onIsOpenChanged: {
        if (isOpen) {
            reposition();
            panel.forceActiveFocus();
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    exclusiveZone: 0
    color: "transparent"
    visible: isOpen || panel.opacity > 0
    anchors.top: true
    anchors.left: true
    margins.top: 0
    implicitWidth: panelWidth + _shadowPad * 2
    implicitHeight: panel.height + _shadowPad * 2 + 4
    // input area follows the panel's size but not its entrance scale, so the bottom edge is
    // clickable from the first frame
    mask: Region { item: hitArea }

    Item {
        id: hitArea
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
    }

    HyprlandFocusGrab {
        windows: [popup]
        active: popup.visible && popup.isOpen
        onCleared: popup.isOpen = false
    }

    Elevation {
        x: panel.x
        y: panel.y
        width: panel.width
        height: panel.height
        radius: panel.radius
        level: 3
        opacity: panel.opacity
        scale: panel.scale
        transformOrigin: Item.Top
    }

    Rectangle {
        id: panel
        x: popup._shadowPad
        y: 4
        width: popup.panelWidth
        height: body.implicitHeight + popup.padding * 2
        radius: Motion.shapeExtraLarge
        color: popup.panelColor
        transformOrigin: Item.Top
        opacity: 0
        scale: 0.9
        focus: popup.isOpen
        Keys.onEscapePressed: popup.hide()

        states: State {
            name: "open"
            when: popup.isOpen
            PropertyChanges { panel.opacity: 1; panel.scale: 1 }
        }
        transitions: [
            Transition {
                to: "open"
                Spring { property: "scale"; speed: "default" }
                Fade { property: "opacity"; speed: "default" }
            },
            Transition {
                from: "open"
                NumberAnimation { property: "scale"; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
                NumberAnimation { property: "opacity"; duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccelerate }
            }
        ]

        ColumnLayout {
            id: body
            x: popup.padding
            y: popup.padding
            width: parent.width - popup.padding * 2
            spacing: 12
        }
    }
}
