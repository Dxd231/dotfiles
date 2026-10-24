import QtQuick

// A spring that moves with the real frame time. SpringAnimation steps in fixed 16 ms slices (at most ~62
// updates a second), which judders on a 100 Hz screen; this integrates every frame, in sub-steps, and
// only runs while it is moving. `value` follows `target`; `jump()` sets both without motion, and
// `instant` makes it follow with no motion (while a drag holds the thing).
Item {
    id: sv

    property real target: 0
    property real value: 0          // set to `target` on completion: a binding here would swallow the first move
    property real velocity: 0
    property real stiffness: 500    // 1/s²: 500 settles in about 0.25 s
    property real ratio: 1          // 1 = critically damped, below 1 overshoots
    property real epsilon: 0.01
    property bool instant: false
    readonly property bool moving: anim.running

    visible: false

    Component.onCompleted: value = target

    function jump(v) {
        anim.stop();
        velocity = 0;
        target = v;
        value = v;
    }
    // aim at `t` with a push already in flight (a fling)
    function fling(t, v) {
        velocity = v;
        target = t;
        if (value !== t || v !== 0)
            anim.start();
    }

    onInstantChanged: {
        if (instant) {
            anim.stop();
            velocity = 0;
            value = target;
        }
    }
    onTargetChanged: {
        if (instant) {
            anim.stop();
            velocity = 0;
            value = target;
        } else if (value !== target) {
            anim.start();
        }
    }

    FrameAnimation {
        id: anim
        onTriggered: {
            let dt = Math.min(frameTime, 0.05);
            const k = sv.stiffness, c = 2 * sv.ratio * Math.sqrt(k);
            let v = sv.value, vel = sv.velocity;
            while (dt > 0) {
                const h = Math.min(dt, 0.004);
                vel += (k * (sv.target - v) - c * vel) * h;
                v += vel * h;
                dt -= h;
            }
            if (Math.abs(sv.target - v) < sv.epsilon && Math.abs(vel) < sv.epsilon * 10) {
                sv.value = sv.target;
                sv.velocity = 0;
                anim.stop();
            } else {
                sv.value = v;
                sv.velocity = vel;
            }
        }
    }
}
