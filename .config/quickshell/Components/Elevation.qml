import QtQuick
import QtQuick.Effects
import qs

// M3 elevation shadow (key + ambient), matching the md-sys-elevation box-shadow levels.
// Declare it as a sibling *before* the surface it belongs to, sized to that surface.
Item {
    id: elevation

    property int level: 1
    property real radius: 0
    property color shadowColor: Colors.shadow

    // [keyY, keyBlur, ambientY, ambientBlur, ambientSpread] per level 0..5
    readonly property var _spec: [
        [0, 0, 0, 0, 0],
        [1, 2, 1, 3, 1],
        [1, 2, 2, 6, 2],
        [1, 3, 4, 8, 3],
        [2, 3, 6, 10, 4],
        [4, 4, 8, 12, 6]
    ][Math.max(0, Math.min(5, level))]

    visible: level > 0

    RectangularShadow {
        anchors.fill: parent
        radius: elevation.radius
        offset.y: elevation._spec[2]
        blur: elevation._spec[3]
        spread: elevation._spec[4]
        color: Qt.alpha(elevation.shadowColor, 0.15)
    }
    RectangularShadow {
        anchors.fill: parent
        radius: elevation.radius
        offset.y: elevation._spec[0]
        blur: elevation._spec[1]
        color: Qt.alpha(elevation.shadowColor, 0.30)
    }
}
