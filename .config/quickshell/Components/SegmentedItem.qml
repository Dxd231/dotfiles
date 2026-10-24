import QtQuick
import qs

// Container for one item of an M3 Expressive segmented list: 4px corners between items,
// 16px on the outer corners of the first/last item. Stack items with 2px spacing.
Rectangle {
    property bool first: false
    property bool last: false

    color: Colors.surface_container_highest
    radius: Motion.shapeExtraSmall
    // the outer corners spring when the item becomes or stops being the first/last one
    property real _top: first ? Motion.shapeLarge : Motion.shapeExtraSmall
    property real _bottom: last ? Motion.shapeLarge : Motion.shapeExtraSmall
    Behavior on _top { Spring {} }
    Behavior on _bottom { Spring {} }
    topLeftRadius: Math.max(0, _top)
    topRightRadius: Math.max(0, _top)
    bottomLeftRadius: Math.max(0, _bottom)
    bottomRightRadius: Math.max(0, _bottom)

    Behavior on color { ColorFade {} }
}
