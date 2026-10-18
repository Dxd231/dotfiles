import QtQuick
import QtQuick.Shapes
import qs

// M3 Expressive wavy circular progress: a rounded-cap wavy arc covering `value` of the circle
// (clockwise from the top), a gap, then a wavy track for the rest. With `waving` the wave drifts
// slowly around the ring. In `overdrive` (past the goal) the full ring is charged: the wave swells and
// races around, a second lap (`overValue` of it, in `overColor`) fills on top, and a faint wave breathes
// just inside the ring.
Item {
    id: ring

    property real value: 1            // 0..1
    property real thickness: 8
    property real amplitude: 3
    property int waves: 16
    property real gap: 14             // degrees between the active arc and the track
    property bool waving: false
    property real idleDrift: 0        // rad/s the wave drifts at when not `waving`; 0 keeps it still
    property bool quicken: false      // the drift speeds up linearly with `pace`, with no ceiling
    property real pace: 0             // logged time in goals (1 = goal met, 2 = twice it); only read with `quicken`
    property bool overdrive: false
    property real overValue: 0        // 0..1, how far the second lap is
    property color overColor: Colors.primary
    property color activeColor: Colors.primary
    property color trackColor: Colors.secondary_container

    // glide between updates that arrive a few times a second
    property real _visual: value
    Behavior on _visual { NumberAnimation { duration: 280; easing.type: Easing.Linear } }

    // overdrive swells the wave and speeds its drift up, on springs so it winds up rather than switches
    property real _amp: overdrive ? amplitude * 1.5 : amplitude
    Behavior on _amp { Spring { speed: "slow" } }
    // with `quicken` the drift grows linearly with the logged time, past the goal too
    readonly property real _near: quicken ? Math.max(0, pace) : 0
    property real _drift: overdrive && !quicken ? 4.5 : (waving ? (quicken ? 1.8 : 0.9) : idleDrift) * (1 + 1.4 * _near)
    Behavior on _drift { Spring { speed: "slow" } }
    property real _overVisual: overValue
    Behavior on _overVisual { NumberAnimation { duration: 280; easing.type: Easing.Linear } }

    property real _phase: 0           // radians the wave has drifted
    FrameAnimation {
        running: (ring.waving || ring.overdrive || ring.idleDrift > 0) && ring.visible
        onTriggered: ring._phase = (ring._phase + frameTime * Math.max(0, ring._drift)) % (Math.PI * 2)
    }
    // the inner wave's slow breathing, only while charged
    property real _breath: 0
    SequentialAnimation on _breath {
        running: ring.overdrive && ring.visible
        loops: Animation.Infinite
        NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
        NumberAnimation { to: 0; duration: 900; easing.type: Easing.InOutSine }
    }

    implicitWidth: 232
    implicitHeight: 232

    // the radius gives way as the wave swells, so the ring never grows out of its box
    readonly property real _r: (Math.min(width, height) - thickness) / 2 - Math.max(amplitude, _amp)

    // points along the wavy ring from angle a0 to a1 (degrees, clockwise, 0 = top), on a circle of radius
    // `base` with a wave of `amp` and phase `ph`
    function arcOn(a0, a1, base, amp, ph) {
        const pts = [];
        const n = Math.max(2, Math.ceil(Math.abs(a1 - a0) / 2));
        for (let i = 0; i <= n; i++) {
            const t = (a0 + (a1 - a0) * i / n) * Math.PI / 180;
            const r = base + amp * Math.sin(waves * t + ph);
            pts.push(Qt.point(width / 2 + r * Math.sin(t), height / 2 - r * Math.cos(t)));
        }
        return pts;
    }
    function arc(a0, a1) { return arcOn(a0, a1, _r, Math.max(0, _amp), _phase); }

    readonly property real _end: Math.max(0, Math.min(1, _visual)) * 360
    readonly property bool _hasActive: _end > 0.5
    readonly property bool _hasTrack: _end < 360 - gap * 2
    readonly property real _overEnd: Math.max(0, Math.min(1, _overVisual)) * 360
    readonly property bool _hasOver: overdrive && _overEnd > 0.5

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: ring._hasTrack ? ring.trackColor : "transparent"
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: ring._hasTrack ? ring.arc(ring._hasActive ? ring._end + ring.gap : 0, 360 - (ring._hasActive ? ring.gap : 0)) : [] }
        }
        ShapePath {
            strokeColor: ring._hasActive ? ring.activeColor : "transparent"
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: ring._hasActive ? ring.arc(0, ring._end) : [] }
        }
        // overdrive: the next lap, on top of the full ring
        ShapePath {
            strokeColor: ring._hasOver ? ring.overColor : "transparent"
            strokeWidth: ring.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: ring._hasOver ? ring.arc(0, ring._overEnd) : [] }
        }
        // overdrive: a faint wave breathing just inside the ring, running the other way
        ShapePath {
            strokeColor: ring.overdrive ? Qt.alpha(ring.overColor, 0.18 + 0.22 * ring._breath) : "transparent"
            strokeWidth: 2
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: ring.overdrive ? ring.arcOn(0, 360, ring._r - ring.thickness - 7, 2.5, -ring._phase * 1.3) : [] }
        }
    }
}
