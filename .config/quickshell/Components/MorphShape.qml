import QtQuick
import QtQuick.Shapes
import qs

// A filled M3 Expressive shape that morphs between the spec's shapes (soft burst, 9-sided cookie,
// pentagon, pill, sunny, 4-sided cookie, oval, four-point star): the outline is the blend of two polar radius
// functions. Set `fromShape` and `shape`, then animate `morph` 0 -> 1.
Item {
    id: root

    // a name from Shapes (numbers from before the names still resolve)
    property var shape: "cookie4"
    property var fromShape: "cookie4"
    // optional second "from" shape blended in by fromMix (0..1), for re-targeting mid-morph without a jump
    property var fromShape2: null
    property real fromMix: 0
    property real morph: 1
    property real spin: 0
    property color color: Colors.primary
    // draw thin shapes even when small (see the rule in Shapes)
    property bool allowThin: false

    Behavior on color { ColorFade {} }

    implicitWidth: 180
    implicitHeight: 180

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
                    const size = Math.min(root.width, root.height);
                    const a = Shapes.forSize(root.fromShape, size, root.allowThin), b = Shapes.forSize(root.shape, size, root.allowThin);
                    const a2 = root.fromShape2 === null ? null : Shapes.forSize(root.fromShape2, size, root.allowThin);
                    const k = root.fromMix;
                    for (let i = 0; i <= 240; i++) {
                        const t = i / 240 * Math.PI * 2;
                        const ra = a2 ? (1 - k) * Shapes.radius(a, t) + k * Shapes.radius(a2, t) : Shapes.radius(a, t);
                        const r = R * ((1 - m) * ra + m * Shapes.radius(b, t));
                        pts.push(Qt.point(cx + r * Math.cos(t), cy + r * Math.sin(t)));
                    }
                    return pts;
                }
            }
        }
    }
}
