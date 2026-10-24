import QtQuick
import qs

// Springs its parent into view: it rises a little, swells from a smaller size and fades up, after `delay`
// ms, on the shell's spatial spring (so it overshoots a touch, as everything else does). Drop it inside any
// item; `shown` replays it: going true puts the parent back at the start and runs it again, going false
// leaves it as it is (the thing it sits in is fading out, and must not lose its parts while it does).
// It drives the parent's opacity, scale and transform, so use it on items that don't animate those.
Item {
    id: appear

    property bool shown: true
    property int delay: 0
    property real lift: 8
    property real from: 0.92
    // created while its surroundings are already shown and settled (a card scrolling into a list): start at rest, no entrance
    property bool instant: false

    property real t: 0
    property bool _animate: true
    Behavior on t { enabled: appear._animate; Spring { speed: "default" } }

    function _restart() {
        wait.stop();
        _animate = false;
        t = 0;
        _animate = true;
        if (shown)
            wait.restart();
    }
    // run it again from the start (for items that stay put while their data changes)
    function replay() { if (shown) _restart(); }
    onShownChanged: {
        if (shown)
            _restart();
        else
            wait.stop();
    }
    Component.onCompleted: {
        if (instant && shown) {
            _animate = false;
            t = 1;
            _animate = true;
        } else {
            _restart();
        }
    }
    Timer {
        id: wait
        interval: Math.max(1, appear.delay)
        onTriggered: appear.t = 1
    }

    Translate { id: rise; y: (1 - appear.t) * appear.lift }
    Binding { target: appear.parent; property: "opacity"; value: Math.max(0, Math.min(1, appear.t * 1.6)) }
    Binding { target: appear.parent; property: "scale"; value: appear.from + (1 - appear.from) * appear.t }
    Binding { target: appear.parent; property: "transform"; value: [rise] }
}
