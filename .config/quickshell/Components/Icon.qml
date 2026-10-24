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
    // fast | default | slow, for the colour fade
    property string colorSpeed: "fast"
    // a new glyph pops in from small instead of swapping in place; off for callers that run their own kick
    property bool kick: true

    readonly property string _path: (filled ? IconPaths.filled[name] : IconPaths.outlined[name]) || ""

    implicitWidth: size
    implicitHeight: size

    property bool fadeColor: true
    Behavior on color { enabled: icon.fadeColor; ColorFade { speed: icon.colorSpeed } }

    property bool _ready: false
    property real _pop: 1
    Behavior on _pop { id: popBehavior; Spring { speed: "fast" } }
    Component.onCompleted: _ready = true
    on_PathChanged: {
        if (!_ready || !kick || !visible)
            return;
        popBehavior.enabled = false;
        _pop = 0.4;
        popBehavior.enabled = true;
        _pop = 1;
    }

    Shape {
        visible: icon._path !== "" && icon._pop > 0
        width: 960
        height: 960
        x: (icon.width - icon.size * Math.max(0, icon._pop)) / 2
        // glyph grid spans y ∈ [-960, 0]
        y: (icon.height + icon.size * Math.max(0, icon._pop)) / 2
        scale: icon.size / 960 * Math.max(0, icon._pop)
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
