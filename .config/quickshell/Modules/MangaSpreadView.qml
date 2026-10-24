pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs
import qs.Components
import qs.Services
import "../Components/MangaLayout.js" as ML

// Spread and single-page reading: a strip of views that slides on a spring. Only the views near the
// current one hold pictures.
Item {
    id: sv

    property var pages: []
    property var views: []
    property int viewIndex: 0
    property bool rtl: true
    property real zoom: 1
    property real gap: 8

    // where the strip is, in views; it follows viewIndex on a spring
    readonly property real viewPos: vp.value
    // M3 Expressive default spatial spring: a little overshoot as the new spread lands
    SpringValue { id: vp; stiffness: 380; ratio: 0.8; epsilon: 0.0005 }
    // (assigned, not bound: jump() would break a binding)
    onViewIndexChanged: vp.target = viewIndex
    Component.onCompleted: vp.jump(viewIndex)
    // a new volume, an offset toggle or a mode switch lands without sliding
    onViewsChanged: Qt.callLater(() => vp.jump(sv.viewIndex))

    clip: true

    Repeater {
        model: sv.views.length
        delegate: Item {
            id: cell
            required property int index
            readonly property var view: sv.views[index] || []
            readonly property bool near: index - sv.viewIndex >= -2 && index - sv.viewIndex <= 3
            readonly property real dist: near ? index - sv.viewPos : 99
            readonly property var size: ML.fit(sv.pages, view, sv.width, sv.height, sv.gap)
            readonly property real totalW: size.ws.reduce((a, b) => a + b, 0) + sv.gap * Math.max(0, view.length - 1)

            // left edge of the j-th page of the view (reading order; the first page is on the right when right to left)
            function xOf(j) {
                const before = size.ws.slice(0, j).reduce((a, b) => a + b, 0) + sv.gap * j;
                const start = (sv.width - totalW) / 2;
                return sv.rtl ? start + totalW - before - (size.ws[j] || 0) : start + before;
            }

            // stack slide: the spread with the higher index is on top and slides in full width; the one
            // behind recedes slower, smaller and dimmer, with rounded corners
            readonly property real behind: dist < 0 ? Math.min(1, -dist) : 0
            readonly property bool moving: near && Math.abs(dist) > 0.001 && Math.abs(dist) < 1.2

            width: sv.width
            height: sv.height
            z: index
            x: (sv.rtl ? -1 : 1) * (dist < 0 ? dist * 0.3 : dist) * sv.width
            scale: 1 - 0.08 * behind
            opacity: Math.max(0, 1 - Math.max(0, Math.abs(dist) - 1) * 2)
            visible: near && opacity > 0.01

            Loader {
                anchors.fill: parent
                asynchronous: true
                active: cell.near
                sourceComponent: Item {
                    Repeater {
                        model: cell.view.length
                        delegate: MangaPage {
                            required property int index
                            info: sv.pages[cell.view[index]] || null
                            width: cell.size.ws[index] || 0
                            height: cell.size.h
                            x: cell.xOf(index)
                            y: (sv.height - height) / 2
                            fitHeight: cell.size.h
                            full: sv.zoom > 1.3 && cell.index === sv.viewIndex
                            vol: Manga.openVol
                            live: cell.index === sv.viewIndex && !cell.moving
                            // the receding spread rounds its corners and dims
                            layer.enabled: cell.moving
                            layer.smooth: true
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: pageMask
                                maskThresholdMin: 0.5
                                maskSpreadAtMin: 1.0
                            }
                            Item {
                                id: pageMask
                                anchors.fill: parent
                                visible: false
                                layer.enabled: true
                                layer.smooth: true
                                Rectangle {
                                    anchors.fill: parent
                                    radius: Motion.shapeLarge * cell.behind
                                }
                            }
                            Rectangle {
                                anchors.fill: parent
                                z: 5
                                color: Colors.scrim
                                opacity: 0.45 * cell.behind
                                visible: opacity > 0.005
                            }
                        }
                    }
                }
            }
        }
    }
}
