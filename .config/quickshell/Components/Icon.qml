import QtQuick
import QtQuick.Shapes
import qs
import qs.Components

// Material Symbols Rounded glyph drawn as a vector path (see scripts/gen_icons.py).
// Recoloring is a plain fill change, so no offscreen layer or colorize shader is needed.
Item {
    id: icon

    property string name
    property real size: 24
    property color color: Colors.on_surface
    // M3: filled for selected/active, outlined for unselected toggle states.
    property bool filled: true

    readonly property string _path: (filled ? IconPaths.filled[name] : IconPaths.outlined[name]) || ""

    implicitWidth: size
    implicitHeight: size

    Shape {
        visible: icon._path !== ""
        width: 960
        height: 960
        x: (icon.width - icon.size) / 2
        // glyph grid spans y ∈ [-960, 0]
        y: (icon.height + icon.size) / 2
        scale: icon.size / 960
        transformOrigin: Item.TopLeft
        preferredRendererType: Shape.CurveRenderer

        ShapePath {
            strokeWidth: -1
            strokeColor: "transparent"
            fillColor: icon.color
            PathSvg { path: icon._path }
        }
    }
}
