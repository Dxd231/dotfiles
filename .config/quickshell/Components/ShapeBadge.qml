import QtQuick
import qs

// A small turning M3 Expressive shape that holds an icon (or any content). It morphs from
// `shapeRest` to `shapeActive` with overshoot when `active`, turns while `spinning`, and
// `badgeScale` is a spring a caller can kick for feedback.
Item {
    id: badge

    property int shapeRest: 1
    property int shapeActive: 4
    property bool active: false
    property bool spinning: false
    property real spinSpeed: 22         // degrees a second while spinning
    // shapes to move through, one after another, each with the same overshooting morph
    property var cycle: []
    property int cycleInterval: 2600
    property color color: Colors.primary_container
    property real badgeScale: 1
    default property alias content: contentHolder.data

    implicitWidth: 24
    implicitHeight: 24
    scale: badgeScale
    Behavior on scale { Spring { speed: "fast" } }

    // morph 0 -> 1 runs between the previous and the current shape; the outline snaps to the old
    // shape and springs to the new one, so every change overshoots
    property int _from: shapeRest
    property int _to: shapeRest
    property real _morph: 1
    property bool _spring: true
    property int _turns: 0
    property real _spin: 0

    Component.onCompleted: {
        _to = active ? shapeActive : shapeRest;
        _from = _to;
    }
    function _go(shape) {
        _from = _to;
        _to = shape;
        _turns += 1;
        _spring = false;
        _morph = 0;
        _spring = true;
        _morph = 1;
    }
    onActiveChanged: _go(active ? shapeActive : shapeRest)
    property int _cycleAt: 0
    Timer {
        interval: badge.cycleInterval
        repeat: true
        running: badge.cycle.length > 1 && badge.visible
        onTriggered: {
            badge._cycleAt = (badge._cycleAt + 1) % badge.cycle.length;
            badge._go(badge.cycle[badge._cycleAt]);
        }
    }
    Behavior on _morph {
        enabled: badge._spring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }
    FrameAnimation {
        running: badge.spinning && badge.visible
        onTriggered: badge._spin = (badge._spin + frameTime * badge.spinSpeed) % 360
    }

    MorphShape {
        anchors.fill: parent
        shape: badge._to
        fromShape: badge._from
        morph: badge._morph
        spin: badge._spin + badge._turns * 90
        color: badge.color
        Behavior on color { ColorFade {} }
    }

    Item {
        id: contentHolder
        anchors.fill: parent
    }
}
