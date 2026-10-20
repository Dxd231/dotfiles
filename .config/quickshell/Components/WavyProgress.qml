import QtQuick
import QtQuick.Shapes
import qs

// M3 Expressive wavy linear progress: a rounded wavy active indicator, a 4px gap, a flat track and a
// stop dot. With `waving` the wave drifts along the bar; its height stays steady.
Item {
    id: bar

    property real value: 0 // 0..1
    property real thickness: 6
    property real amplitude: 2.5
    property real wavelength: 22
    property bool waving: false
    property color activeColor: Colors.primary
    property color trackColor: Colors.secondary_container
    property bool showStop: true

    property real _visual: Math.max(0, Math.min(1, value))
    Behavior on _visual { Spring { expressive: false } }

    // the wave settles flat a little before it reaches the end, and eases in from the start
    property real _amp: _visual > 0.02 ? amplitude : 0
    Behavior on _amp { Spring { speed: "slow" } }
    property real _phase: 0
    FrameAnimation {
        running: bar.waving && bar.visible
        onTriggered: bar._phase = (bar._phase + frameTime * 3) % (Math.PI * 2)
    }

    implicitWidth: 200
    implicitHeight: thickness + amplitude * 2 + 2

    readonly property real _cap: thickness / 2
    readonly property real _end: _visual * width
    readonly property bool _hasActive: _end > _cap * 2
    readonly property real _trackStart: _hasActive ? _end + 4 + _cap : _cap

    function wave() {
        const pts = [];
        const x0 = _cap, x1 = Math.max(_cap, _end - _cap);
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
        visible: bar.showStop && bar._trackStart < bar.width - bar._cap * 2
        anchors.verticalCenter: parent.verticalCenter
        x: bar.width - bar._cap - 2
        width: 4
        height: 4
        radius: 2
        color: bar.activeColor
    }
}
