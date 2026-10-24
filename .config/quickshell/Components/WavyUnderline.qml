import QtQuick
import QtQuick.Shapes
import qs

// A rounded wavy line along the bottom of a word: the mark for a leech. Sized by the parent's width; the
// wave keeps a fixed wavelength, so a longer word just gets more crests.
Item {
    id: u

    property color color: Colors.secondary
    property real thickness: 3
    property real amplitude: 1.5
    property real wavelength: 10

    implicitHeight: thickness + amplitude * 2

    Behavior on color { ColorFade {} }

    readonly property var _pts: {
        const pts = [];
        const w = Math.max(0, width - thickness);
        const mid = height / 2;
        const step = 1.5;
        for (let x = 0; x <= w + 0.01; x += step)
            pts.push(Qt.point(thickness / 2 + x, mid + amplitude * Math.sin(x / wavelength * 2 * Math.PI)));
        return pts;
    }

    Shape {
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeColor: u.color
            strokeWidth: u.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: u._pts }
        }
    }
}
