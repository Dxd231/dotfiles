import QtQuick
import QtQuick.Shapes
import qs

// M3 Expressive loading indicator: a 38px shape that morphs through the spec's sequence
// (soft burst → 9-sided cookie → pentagon → pill → sunny → 4-sided cookie → oval) while
// rotating. `contained` adds the 48px primary-container circle.
Item {
    id: indicator

    property bool running: visible
    // never tick for a hidden window (e.g. a closed popup whose loading state is still set)
    readonly property bool _active: running && visible && !!Window.window && Window.window.visible
    property bool contained: false
    property color color: contained ? Colors.on_primary_container : Colors.primary

    implicitWidth: 48
    implicitHeight: 48

    // polar radius functions, normalised to a max of 1
    function radiusAt(shape, t) {
        switch (shape) {
        case 0: return 1 - 0.06 * (1 - Math.cos(10 * t));          // soft burst
        case 1: return 1 - 0.07 * (1 - Math.cos(9 * t));           // cookie 9
        case 2: return 1 - 0.09 * (1 - Math.cos(5 * t));           // pentagon (rounded)
        case 3: return 1 / Math.pow(Math.pow(Math.abs(Math.cos(t)), 4) + Math.pow(Math.abs(Math.sin(t) / 0.62), 4), 0.25); // pill
        case 4: return 1 - 0.1 * (1 - Math.cos(8 * t));            // sunny
        case 5: return 1 - 0.14 * (1 - Math.cos(4 * t));           // cookie 4
        default: return 1 / Math.sqrt(Math.pow(Math.cos(t), 2) + Math.pow(Math.sin(t) / 0.78, 2)) * 0.95; // oval
        }
    }

    property int shape: 0
    property real morph: 1
    property real spin: 0

    SequentialAnimation {
        running: indicator._active
        loops: Animation.Infinite
        PauseAnimation { duration: 300 }
        ScriptAction {
            script: {
                indicator.shape = (indicator.shape + 1) % 7;
                indicator.morph = 0;
            }
        }
        NumberAnimation { target: indicator; property: "morph"; to: 1; duration: Motion.expressiveDefaultSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial }
    }
    FrameAnimation {
        running: indicator._active
        onTriggered: indicator.spin = (indicator.spin + frameTime * 220) % 360
    }

    Rectangle {
        visible: indicator.contained
        anchors.fill: parent
        radius: width / 2
        color: Colors.primary_container
    }

    Shape {
        anchors.centerIn: parent
        width: 38
        height: 38
        // extra quarter turn per morph, on top of the continuous spin
        rotation: indicator.spin + (indicator.shape + indicator.morph) * 90
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: indicator.color
            PathPolyline {
                path: {
                    const from = (indicator.shape + 6) % 7, to = indicator.shape, m = indicator.morph;
                    const pts = [];
                    for (let i = 0; i <= 96; i++) {
                        const t = i / 96 * Math.PI * 2;
                        const r = 19 * ((1 - m) * indicator.radiusAt(from, t) + m * indicator.radiusAt(to, t));
                        pts.push(Qt.point(19 + r * Math.cos(t), 19 + r * Math.sin(t)));
                    }
                    return pts;
                }
            }
        }
    }
}
