import QtQuick
import qs

// A small turning M3 Expressive shape that holds an icon (or any content). It morphs from
// `shapeRest` to `shapeActive` with overshoot when `active`, turns while `spinning`, and
// `badgeScale` is a spring a caller can kick for feedback.
//
// `busy` makes the badge the loader: it keeps its content, turns at loader speed and moves up through the
// calm and festive shapes. Call `finish(true|false)` when the work ends: it lands on a flower (done) or an
// error-coloured boom (failed), holds for a moment and springs back to rest.
Item {
    id: badge

    property var shapeRest: "cookie4"
    property var shapeActive: "clover4"
    property bool active: false
    property bool spinning: false
    property real spinSpeed: 22         // degrees a second while spinning
    // shapes to move through, one after another, each with the same overshooting morph
    property var cycle: []
    property int cycleInterval: 2600
    property color color: Colors.primary_container
    property real badgeScale: 1
    property bool busy: false
    // keep thin shapes even at badge size (see the rule in Shapes)
    property bool allowThin: false
    property int resultHold: 1800
    // "", "ok" or "error" while a result is showing
    property string landed: ""
    default property alias content: contentHolder.data

    implicitWidth: 24
    implicitHeight: 24
    scale: badgeScale
    Behavior on scale { Spring { speed: "fast" } }

    // morph 0 -> 1 runs between the previous and the current shape; the outline snaps to the old
    // shape and springs to the new one, so every change overshoots
    property var _from: shapeRest
    property var _to: shapeRest
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
    // the active shape changing while active (an alarm starting to ring) morphs there too
    onShapeActiveChanged: if (active) _go(shapeActive)
    // and the rest shape changing while at rest (a mode switch) morphs as well
    onShapeRestChanged: if (!active && !busy && landed === "") _go(shapeRest)
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
        running: (badge.spinning || badge.busy) && badge.visible
        onTriggered: badge._spin = (badge._spin + frameTime * (badge.busy ? 160 : badge.spinSpeed)) % 360
    }

    readonly property var _busyShapes: ["cookie4", "sunny", "flower"]
    property int _busyAt: 0
    onBusyChanged: {
        if (busy) {
            landed = "";
            landTimer.stop();
            _busyAt = 0;
            _go(_busyShapes[0]);
        } else if (landed === "") {
            _go(active ? shapeActive : shapeRest);
        }
    }
    Timer {
        interval: 650
        repeat: true
        running: badge.busy && badge.visible
        onTriggered: {
            badge._busyAt = (badge._busyAt + 1) % badge._busyShapes.length;
            badge._go(badge._busyShapes[badge._busyAt]);
        }
    }
    function finish(ok) {
        busy = false;
        landed = ok ? "ok" : "error";
        _go(ok ? "flower" : "boom");
        landTimer.restart();
    }
    Timer {
        id: landTimer
        interval: badge.resultHold
        onTriggered: {
            badge.landed = "";
            badge._go(badge.active ? badge.shapeActive : badge.shapeRest);
        }
    }

    MorphShape {
        anchors.fill: parent
        shape: badge._to
        fromShape: badge._from
        morph: badge._morph
        allowThin: badge.allowThin
        spin: badge._spin + badge._turns * 90
        color: badge.landed === "error" ? Colors.error_container : badge.color
    }

    Item {
        id: contentHolder
        anchors.fill: parent
    }
}
