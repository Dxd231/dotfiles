import QtQuick
import qs

// Container for one item of an M3 Expressive segmented list: 4px corners between items,
// 16px on the outer corners of the first/last item. Stack items with 2px spacing.
Rectangle {
    property bool first: false
    property bool last: false

    color: Colors.surface_container_highest
    radius: Motion.shapeExtraSmall
    topLeftRadius: first ? Motion.shapeLarge : radius
    topRightRadius: first ? Motion.shapeLarge : radius
    bottomLeftRadius: last ? Motion.shapeLarge : radius
    bottomRightRadius: last ? Motion.shapeLarge : radius
}
