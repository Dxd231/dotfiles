import QtQuick
import QtQuick.Shapes
import qs

// A filled M3 Expressive shape that morphs between the spec's shapes (soft burst, 9-sided cookie,
// pentagon, pill, sunny, 4-sided cookie, oval, four-point star): the outline is the blend of two polar radius
// functions. Set `fromShape` and `shape`, then animate `morph` 0 -> 1.
Item {
    id: root

    property int shape: 0
    property int fromShape: 0
    property real morph: 1
    property real spin: 0
    property color color: Colors.primary

    implicitWidth: 180
    implicitHeight: 180

    // polar radius functions, normalised to a max of 1
    function radiusAt(kind, t) {
        switch (kind) {
        case 0: return 1 - 0.06 * (1 - Math.cos(10 * t));          // soft burst
        case 1: return 1 - 0.07 * (1 - Math.cos(9 * t));           // cookie 9
        case 2: return 1 - 0.09 * (1 - Math.cos(5 * t));           // pentagon (rounded)
        case 3: return 1 / Math.pow(Math.pow(Math.abs(Math.cos(t)), 4) + Math.pow(Math.abs(Math.sin(t) / 0.62), 4), 0.25); // pill
        case 4: return 1 - 0.1 * (1 - Math.cos(8 * t));            // sunny
        case 5: return 1 - 0.14 * (1 - Math.cos(4 * t));           // cookie 4
        case 7: return 0.6 + 0.4 * Math.pow((1 + Math.cos(4 * t)) / 2, 1.5); // four-point star (sparkle)
        default: return 1 / Math.sqrt(Math.pow(Math.cos(t), 2) + Math.pow(Math.sin(t) / 0.78, 2)) * 0.95; // oval
        }
    }

    Shape {
        anchors.fill: parent
        // a quarter turn per morph on top of the slow drift
        rotation: root.spin + root.morph * 90
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: root.color
            PathPolyline {
                path: {
                    const cx = root.width / 2, cy = root.height / 2, R = Math.min(cx, cy);
                    const m = root.morph;
                    const pts = [];
                    for (let i = 0; i <= 120; i++) {
                        const t = i / 120 * Math.PI * 2;
                        const r = R * ((1 - m) * root.radiusAt(root.fromShape, t) + m * root.radiusAt(root.shape, t));
                        pts.push(Qt.point(cx + r * Math.cos(t), cy + r * Math.sin(t)));
                    }
                    return pts;
                }
            }
        }
    }
}
