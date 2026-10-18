import QtQuick
import QtQuick.Shapes
import qs

// Two rounded-cap history lines (values 0..100, oldest first) with a pulsing dot on the newest
// point of the first one. The newest samples are right-aligned, so the line grows in from the right.
Item {
    id: root

    property var series: []
    property var series2: []
    property color color: Colors.primary
    property color color2: Colors.tertiary
    property real thickness: 4
    property int count: 60

    readonly property real _pad: thickness + 4

    // smooth a little (3-point average) and map to the item's box
    function points(arr) {
        const n = arr.length;
        const pts = [];
        for (let i = 0; i < n; i++) {
            const a = arr[Math.max(0, i - 1)], b = arr[i], c = arr[Math.min(n - 1, i + 1)];
            const v = (a + b + c) / 3;
            const x = _pad + (count - n + i) / (count - 1) * (width - 2 * _pad);
            const y = height - _pad - Math.max(0, Math.min(100, v)) / 100 * (height - 2 * _pad);
            pts.push(Qt.point(x, y));
        }
        return pts;
    }
    readonly property var _p1: points(series)
    readonly property var _p2: points(series2)

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: root.series2.length > 1 ? root.color2 : "transparent"
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._p2 }
        }
        ShapePath {
            strokeColor: root.series.length > 1 ? root.color : "transparent"
            strokeWidth: root.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: root._p1 }
        }
    }

    // the newest point pulses
    Rectangle {
        visible: root._p1.length > 1
        width: 12
        height: 12
        radius: 6
        color: root.color
        x: root._p1.length ? root._p1[root._p1.length - 1].x - width / 2 : 0
        y: root._p1.length ? root._p1[root._p1.length - 1].y - height / 2 : 0
        SequentialAnimation on scale {
            running: root.visible && root._p1.length > 1
            loops: Animation.Infinite
            NumberAnimation { to: 1.5; duration: 600; easing.type: Easing.OutQuad }
            NumberAnimation { to: 1.0; duration: 600; easing.type: Easing.InQuad }
        }
    }
}
