pragma ComponentBehavior: Bound
// Modules/ScreenFrame.qml
import Quickshell
import Quickshell.Wayland
import QtQuick
import QtQuick.Shapes

Variants {
    id: root
    property var theme
    property int thickness: 5
    property int rounding: 15
    property real topInset: 40

    model: Quickshell.screens

    PanelWindow {
        id: frameWindow
        required property var modelData
        screen: modelData

        WlrLayershell.namespace: "quickshell:screen_frame"
        WlrLayershell.layer: WlrLayer.Top
        exclusionMode: ExclusionMode.Ignore
        anchors { top: true; bottom: true; left: true; right: true }
        color: "transparent"
        mask: Region { x: 0; y: 0; width: 0; height: 0 }

        property color frameColor: root.theme ? root.theme.background : "black"

        Shape {
            anchors.fill: parent
            preferredRendererType: Shape.CurveRenderer

            ShapePath {
                fillColor: frameWindow.frameColor
                strokeWidth: 0
                fillRule: ShapePath.OddEvenFill

                PathSvg {
                    path: {
                        const w = frameWindow.width;
                        const h = frameWindow.height;
                        const t = root.thickness;
                        const r = root.rounding;
                        const topT = root.topInset;

                        const outer = `M0,${topT} H${w} V${h} H0 Z`;

                        const ix = t, iy = topT, iw = w - 2 * t, ih = h - topT - t;
                        const inner =
                            `M${ix + r},${iy} ` +
                            `H${ix + iw - r} A${r},${r} 0 0 1 ${ix + iw},${iy + r} ` +
                            `V${iy + ih - r} A${r},${r} 0 0 1 ${ix + iw - r},${iy + ih} ` +
                            `H${ix + r} A${r},${r} 0 0 1 ${ix},${iy + ih - r} ` +
                            `V${iy + r} A${r},${r} 0 0 1 ${ix + r},${iy} Z`;

                        return outer + " " + inner;
                    }
                }
            }
        }
    }
}