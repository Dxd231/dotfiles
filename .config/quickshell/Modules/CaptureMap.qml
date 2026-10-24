pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Widgets
import qs
import qs.Components

// A workspace drawn as the layout has it: the monitor's rectangle and every window of the workspace
// at its place (a scrolling layout can run far past the monitor on either side), scaled to fit. With
// `thumbs` each window shows its own picture.
Item {
    id: map

    property var ws: null
    property var mon: ({ w: 1920, h: 1080 })
    property bool thumbs: false
    property string selectedAddr: ""
    property real corner: 6
    // the monitor's own rectangle, behind the windows
    property color screenColor: Qt.alpha(Colors.on_surface, 0.12)

    readonly property var wins: ws ? ws.windows : []
    readonly property var bb: {
        let x0 = 0, y0 = 0, x1 = mon.w, y1 = mon.h;
        wins.forEach(c => {
            x0 = Math.min(x0, c.x);
            y0 = Math.min(y0, c.y);
            x1 = Math.max(x1, c.x + c.w);
            y1 = Math.max(y1, c.y + c.h);
        });
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }
    readonly property real k: Math.min(width / bb.w, height / bb.h)
    readonly property real ox: (width - bb.w * k) / 2 - bb.x * k
    readonly property real oy: (height - bb.h * k) / 2 - bb.y * k

    Rectangle {
        x: map.ox
        y: map.oy
        width: Math.max(0, map.mon.w * map.k)
        height: Math.max(0, map.mon.h * map.k)
        Behavior on x { Spring { speed: "fast" } }
        Behavior on y { Spring { speed: "fast" } }
        Behavior on width { Spring { speed: "fast" } }
        Behavior on height { Spring { speed: "fast" } }
        radius: map.corner
        color: map.screenColor
        Behavior on color { ColorFade {} }
    }
    Repeater {
        model: map.wins
        delegate: ClippingRectangle {
            id: cell
            required property var modelData
            required property int index
            Appear { delay: cell.index * 30 }
            x: map.ox + modelData.x * map.k
            y: map.oy + modelData.y * map.k
            width: Math.max(0, modelData.w * map.k)
            height: Math.max(0, modelData.h * map.k)
            Behavior on x { Spring { speed: "fast" } }
            Behavior on y { Spring { speed: "fast" } }
            Behavior on width { Spring { speed: "fast" } }
            Behavior on height { Spring { speed: "fast" } }
            radius: map.corner
            color: modelData.addr === map.selectedAddr ? Colors.primary : Qt.alpha(Colors.primary, 0.35)
            Behavior on color { ColorFade {} }
            Loader {
                anchors.fill: parent
                active: map.thumbs
                sourceComponent: CaptureThumb {
                    addr: cell.modelData.addr
                }
            }
        }
    }
}
