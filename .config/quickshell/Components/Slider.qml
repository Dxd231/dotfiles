import QtQuick
import qs

// M3 Expressive slider: split track with a 4px bar handle, 6px gaps, 2px inner corners,
// end stop indicator, optional inset icon (m+ sizes) and value indicator while dragging.
Item {
    id: slider

    property real from: 0
    property real to: 1
    property real value: 0
    property real stepSize: (to - from) / 20 // wheel step
    property string size: "xs"   // xs | s | m | l | xl
    property string icon         // inset icon, shown for m/l/xl
    property bool valueIndicator: false
    property string valueText: Math.round((value - from) / (to - from) * 100)
    property color activeColor: Colors.primary
    property color inactiveColor: Colors.secondary_container

    readonly property bool hovered: mouse.containsMouse && enabled
    readonly property bool pressed: mouse.pressed && enabled

    // emitted for user input only; bind `value` and write it back from the handler
    signal moved(real value)

    // [trackHeight, handleHeight, corner, insetIcon]
    readonly property var _t: ({
        xs: [16, 44, 8, 0],
        s: [24, 44, 8, 0],
        m: [40, 52, 12, 24],
        l: [56, 68, 16, 24],
        xl: [96, 108, 28, 32]
    })[size] || [16, 44, 8, 0]
    readonly property real trackHeight: _t[0]
    readonly property real gap: 6
    readonly property real handleWidth: pressed ? 2 : 4
    readonly property real fraction: Math.max(0, Math.min(1, (value - from) / (to - from)))

    property real _visual: fraction
    Behavior on _visual {
        enabled: !slider.pressed
        Spring {}
    }
    readonly property real _handleX: 2 + _visual * (width - 4)

    implicitWidth: 200
    implicitHeight: _t[1]

    function _setFromX(x) {
        const f = Math.max(0, Math.min(1, (x - 2) / (width - 4)));
        moved(from + f * (to - from));
    }

    // Active track
    Rectangle {
        id: active
        anchors.verticalCenter: parent.verticalCenter
        height: slider.trackHeight
        width: Math.max(0, slider._handleX - slider.handleWidth / 2 - slider.gap)
        visible: width > 0.5
        color: slider.enabled ? slider.activeColor : Qt.alpha(Colors.on_surface, Motion.disabledContent)
        topLeftRadius: slider._t[2]
        bottomLeftRadius: slider._t[2]
        topRightRadius: 2
        bottomRightRadius: 2
        Behavior on color { ColorFade {} }
    }

    // Inactive track
    Rectangle {
        id: inactive
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        height: slider.trackHeight
        width: Math.max(0, slider.width - slider._handleX - slider.handleWidth / 2 - slider.gap)
        visible: width > 0.5
        color: slider.enabled ? slider.inactiveColor : Qt.alpha(Colors.on_surface, 0.12)
        topLeftRadius: 2
        bottomLeftRadius: 2
        topRightRadius: slider._t[2]
        bottomRightRadius: slider._t[2]
        Behavior on color { ColorFade {} }

        // stop indicator at the end of the range
        Rectangle {
            width: 4
            height: 4
            radius: 2
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: slider.trackHeight / 2 - 2
            visible: parent.width > slider.trackHeight
            color: slider.enabled ? slider.activeColor : Qt.alpha(Colors.on_surface, Motion.disabledContent)
        }
    }

    // Inset icon: inside the active track when it fits, otherwise at the start of the inactive one
    Icon {
        readonly property bool inActive: active.width >= size + 20
        visible: slider.icon !== "" && slider._t[3] > 0
        name: slider.icon
        size: slider._t[3]
        anchors.verticalCenter: parent.verticalCenter
        x: inActive ? 10 : active.width + slider.handleWidth + slider.gap * 2 + 10
        color: inActive ? Colors.on_primary : Colors.on_secondary_container
    }

    // Handle
    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        x: slider._handleX - width / 2
        width: slider.handleWidth
        height: slider._t[1]
        radius: width / 2
        color: slider.enabled ? slider.activeColor : Qt.alpha(Colors.on_surface, Motion.disabledContent)
        Behavior on width { Spring {} }
    }

    // Value indicator
    Rectangle {
        visible: slider.valueIndicator
        opacity: slider.pressed ? 1 : 0
        scale: slider.pressed ? 1 : 0.6
        transformOrigin: Item.Bottom
        width: Math.max(48, valueLabel.implicitWidth + 24)
        height: 44
        radius: height / 2
        x: slider._handleX - width / 2
        anchors.bottom: parent.top
        anchors.bottomMargin: 4
        color: Colors.inverse_surface
        Behavior on opacity { Fade {} }
        Behavior on scale { Spring {} }

        StyledText {
            id: valueLabel
            anchors.centerIn: parent
            role: "labelLarge"
            text: slider.valueText
            color: Colors.inverse_on_surface
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        preventStealing: true
        cursorShape: slider.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        onPressed: m => slider._setFromX(m.x)
        onPositionChanged: m => {
            if (pressed)
                slider._setFromX(m.x);
        }
        onWheel: w => {
            const dir = (w.angleDelta.y || -w.angleDelta.x) > 0 ? 1 : -1;
            slider.moved(Math.max(slider.from, Math.min(slider.to, slider.value + dir * slider.stepSize)));
        }
    }
}
