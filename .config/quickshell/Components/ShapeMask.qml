import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import qs

// An image cropped to a named shape (Shapes.qml), with a shape skeleton while it loads: a
// surface_container_high shape with a slow highlight sweep. When the picture arrives it fades in and the
// outline springs from cookie4 to `shape`. The outline follows the item's own size, so a tall cover gets a
// stretched calm shape; keep masks to calm / festive shapes, and they never spin (see Shapes.qml).
Item {
    id: root

    property url source
    property var shape: "cookie4"
    // set while the pointer is over the card etc.: morphs to `activeShape`
    property var activeShape: shape
    property bool active: false
    property int sourceWidth: 0
    property int fillMode: Image.PreserveAspectCrop
    property color placeholder: Colors.surface_container_high
    readonly property bool loaded: img.status === Image.Ready
    readonly property int status: img.status

    property var _from: "cookie4"
    property var _to: "cookie4"
    property real _morph: 1
    property bool _spring: true
    readonly property var _want: !loaded ? "cookie4" : active ? activeShape : shape
    on_WantChanged: {
        _from = _to;
        _to = _want;
        _spring = false;
        _morph = 0;
        _spring = true;
        _morph = 1;
    }
    Component.onCompleted: {
        _to = _want;
        _from = _to;
    }
    Behavior on _morph {
        enabled: root._spring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }

    // the outline as a mask (same MultiEffect recipe as the Mpris disc)
    Item {
        id: maskItem
        anchors.fill: parent
        visible: false
        layer.enabled: true
        layer.smooth: true
        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer
            ShapePath {
                strokeWidth: -1
                strokeColor: "transparent"
                fillColor: "black"
                PathPolyline { path: root._pts }
            }
        }
    }

    Item {
        anchors.fill: parent
        opacity: root.loaded ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: Motion.expressiveDefaultEffectsDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultEffects } }
        layer.enabled: true
        layer.smooth: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSource: maskItem
            maskThresholdMin: 0.5
            maskSpreadAtMin: 1.0
        }
        Image {
            id: img
            anchors.fill: parent
            source: root.source
            fillMode: root.fillMode
            asynchronous: true
            sourceSize.width: root.sourceWidth > 0 ? root.sourceWidth : 0
        }
    }

    readonly property var _pts: outline()

    function outline() {
        const w = root.width, h = root.height, cx = w / 2, cy = h / 2;
        const size = Math.min(w, h);
        const a = Shapes.forSize(root._from, size), b = Shapes.forSize(root._to, size), m = root._morph;
        const pts = [];
        for (let i = 0; i <= 120; i++) {
            const t = i / 120 * Math.PI * 2;
            const r = (1 - m) * Shapes.radius(a, t) + m * Shapes.radius(b, t);
            pts.push(Qt.point(cx + cx * r * Math.cos(t), cy + cy * r * Math.sin(t)));
        }
        return pts;
    }

    // skeleton
    Shape {
        anchors.fill: parent
        opacity: img.status === Image.Loading ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { NumberAnimation { duration: Motion.expressiveDefaultEffectsDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultEffects } }
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: root.placeholder
            PathPolyline { path: root._pts }
        }
        ShapePath {
            id: sweep
            property real at: 0
            strokeWidth: -1
            strokeColor: "transparent"
            fillGradient: LinearGradient {
                x1: root.width * (sweep.at - 0.35)
                y1: 0
                x2: root.width * (sweep.at + 0.35)
                y2: root.height * 0.4
                GradientStop { position: 0; color: "transparent" }
                GradientStop { position: 0.5; color: Qt.rgba(Colors.on_surface.r, Colors.on_surface.g, Colors.on_surface.b, 0.07) }
                GradientStop { position: 1; color: "transparent" }
            }
            PathPolyline { path: root._pts }
        }
        NumberAnimation {
            target: sweep
            property: "at"
            from: -0.2
            to: 1.2
            duration: 1800
            loops: Animation.Infinite
            running: !root.loaded && root.visible && root.width > 0
        }
    }
}
