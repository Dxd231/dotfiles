import QtQuick
import QtQuick.Shapes
import qs

// M3 Expressive wavy linear progress: a rounded wavy active indicator, a 4px gap, a flat track and a
// stop dot. With `waving` the wave drifts along the bar; its height stays steady. `indeterminate` (a job of
// unknown length) sends a wave segment of steady height travelling along the track.
Item {
    id: bar

    property real value: 0 // 0..1
    property real thickness: 6
    property real amplitude: 2.5
    property real wavelength: 22
    property bool waving: false
    property bool indeterminate: false
    property color activeColor: Colors.primary
    property color trackColor: Colors.secondary_container
    property bool showStop: true

    property real _visual: Math.max(0, Math.min(1, value))
    Behavior on _visual { Spring { expressive: false } }

    // the wave settles flat a little before it reaches the end, and eases in from the start
    property real _amp: _visual > 0.02 || indeterminate ? amplitude : 0
    Behavior on _amp { Spring { speed: "slow" } }
    property real _phase: 0
    FrameAnimation {
        running: (bar.waving || bar.indeterminate) && bar.visible
        onTriggered: bar._phase = (bar._phase + frameTime * 3) % (Math.PI * 2)
    }

    implicitWidth: 200
    implicitHeight: thickness + amplitude * 2 + 2

    readonly property real _cap: thickness / 2
    // the travelling segment of an indeterminate bar, as a share of the width
    readonly property real _seg: 0.32
    property real _ind: 0
    NumberAnimation on _ind {
        from: 0
        to: 1
        duration: 1500
        loops: Animation.Infinite
        running: bar.indeterminate && bar.visible
    }
    readonly property real _start: indeterminate ? Math.max(0, (_ind * (1 + _seg) - _seg) * width) : 0
    readonly property real _end: indeterminate ? Math.min(width, _ind * (1 + _seg) * width) : _visual * width
    readonly property bool _hasActive: _end - _start > _cap * 2
    readonly property real _trackStart: indeterminate ? _cap : _hasActive ? _end + 4 + _cap : _cap

    function wave() {
        const pts = [];
        const x0 = _start + _cap, x1 = Math.max(_cap, _end - _cap);
        const n = Math.max(2, Math.ceil((x1 - x0) / 3));
        const k = Math.PI * 2 / wavelength;
        for (let i = 0; i <= n; i++) {
            const x = x0 + (x1 - x0) * i / n;
            pts.push(Qt.point(x, height / 2 + _amp * Math.sin(k * x - _phase)));
        }
        return pts;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: bar._trackStart < bar.width - bar._cap ? bar.trackColor : "transparent"
            strokeWidth: bar.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            startX: bar._trackStart
            startY: bar.height / 2
            PathLine { x: Math.max(bar._trackStart, bar.width - bar._cap); y: bar.height / 2 }
        }
        ShapePath {
            strokeColor: bar._hasActive ? bar.activeColor : "transparent"
            strokeWidth: bar.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: bar._hasActive ? bar.wave() : [] }
        }
    }
    Rectangle {
        visible: bar.showStop && !bar.indeterminate && bar._trackStart < bar.width - bar._cap * 2
        anchors.verticalCenter: parent.verticalCenter
        x: bar.width - bar._cap - 2
        width: 4
        height: 4
        radius: 2
        color: bar.activeColor
    }
}
