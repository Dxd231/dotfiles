import QtQuick
import QtQuick.Shapes
import qs

// A ShapeBadge inside a thin progress ring (optional, `ring: false` drops it): the ring fills as the day's goal is
// approached and takes a second lap in `overColor` past it. While `nudging` the badge morphs calmly
// through a few shapes (and settles back to its own shape when the nudge stops). Put the icon inside.
Item {
    id: gb

    property bool ring: true            // false: just the badge, no ring
    property real progress: 0           // 0..1
    property real over: 0               // 0..1, how far the second lap is
    property color arcColor: Colors.primary
    property color overColor: Colors.tertiary
    property color trackColor: Qt.alpha(arcColor, 0.22)
    property real thickness: 2.5
    property bool nudging: false
    property var nudgeShapes: [5, 7, 1]

    property int shapeRest: 1
    property int shapeActive: 7
    property bool active: false
    property bool spinning: false
    property real spinSpeed: 22
    property color color: Colors.primary_container
    property alias badgeScale: badge.badgeScale
    default property alias content: badge.content

    implicitWidth: ring ? 30 : 24
    implicitHeight: ring ? 30 : 24

    property real _p: progress
    property real _o: over
    Behavior on _p { Spring { speed: "default" } }
    Behavior on _o { Spring { speed: "default" } }

    readonly property real _r: (width - thickness) / 2

    onNudgingChanged: {
        if (!nudging)
            badge._go(active ? shapeActive : shapeRest);
    }

    Shape {
        visible: gb.ring
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeColor: gb.trackColor
            strokeWidth: gb.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: gb.width / 2
                centerY: gb.height / 2
                radiusX: gb._r
                radiusY: gb._r
                startAngle: -90
                sweepAngle: 359.9
            }
        }
        ShapePath {
            strokeColor: gb._p > 0.004 ? gb.arcColor : "transparent"
            strokeWidth: gb.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: gb.width / 2
                centerY: gb.height / 2
                radiusX: gb._r
                radiusY: gb._r
                startAngle: -90
                sweepAngle: Math.min(359.9, Math.max(0, gb._p) * 360)
            }
        }
        ShapePath {
            strokeColor: gb._o > 0.004 ? gb.overColor : "transparent"
            strokeWidth: gb.thickness
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            PathAngleArc {
                centerX: gb.width / 2
                centerY: gb.height / 2
                radiusX: gb._r
                radiusY: gb._r
                startAngle: -90
                sweepAngle: Math.min(359.9, Math.max(0, gb._o) * 360)
            }
        }
    }

    ShapeBadge {
        id: badge
        anchors.centerIn: parent
        width: 24
        height: 24
        shapeRest: gb.shapeRest
        shapeActive: gb.shapeActive
        active: gb.active
        spinning: gb.spinning
        spinSpeed: gb.spinSpeed
        color: gb.color
        cycle: gb.nudging ? gb.nudgeShapes : []
        cycleInterval: 3000
    }
}
