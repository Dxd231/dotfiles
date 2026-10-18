pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Services

// Does the picture work for window and workspace screenshots, in a background layer window the user
// never sees. Two kinds of job (Capture.grab):
//   parts    one screencopy view per window, each saved to its own file as soon as it has a picture;
//            the windows that never answer (scrolled out of the layout) are reported back
//   compose  the saved pictures laid out the way the layout had the windows, over the wallpaper (a
//            workspace's windows may sit far off-screen, so the picture can be wider than the monitor),
//            saved as one image
PanelWindow {
    id: win

    readonly property var job: Capture.grab
    property int ready: 0
    property bool finished: false
    property var got: ({})              // addresses that delivered a picture

    visible: !!job
    WlrLayershell.namespace: "quickshell:capturegrab"
    WlrLayershell.layer: WlrLayer.Background
    anchors { left: true; top: true }
    implicitWidth: 64
    implicitHeight: 64
    exclusiveZone: -1
    color: "transparent"
    mask: Region {}

    onJobChanged: {
        got = ({});
        ready = 0;
        finished = false;
        if (job)
            giveUp.restart();
        else
            giveUp.stop();
    }
    function markGot(addr) {
        if (got[addr])
            return;
        got[addr] = true;
        ready += 1;
    }
    function finish(ok) {
        if (finished || !job)
            return;
        finished = true;
        giveUp.stop();
        Capture.grabDone(job.id, ok, job.items.filter(i => !got[i.addr]).map(i => i.addr));
    }
    // a window that never answers (one scrolled out of view) is reported, not waited for
    Timer {
        id: giveUp
        interval: 2600
        onTriggered: {
            if (!win.job)
                return;
            if (win.job.compose && win.ready > 0)
                win.compose();
            else
                win.finish(win.job.compose ? false : true);
        }
    }
    function compose() {
        const j = job;
        if (!j || finished)
            return;
        // keep the file within what a texture can hold
        const k = Math.min(1, 12000 / Math.max(j.w, j.h));
        canvas.grabToImage(r => win.finish(r.saveToFile(j.out)), Qt.size(Math.round(j.w * k), Math.round(j.h * k)));
    }
    Timer {
        id: settle
        interval: 120
        running: !!win.job && win.job.compose && !win.finished && win.ready >= win.job.items.length && (win.job.bg === "" || bg.status === Image.Ready)
        onTriggered: win.compose()
    }
    Timer {
        interval: 60
        running: !!win.job && !win.job.compose && !win.finished && win.ready >= win.job.items.length
        onTriggered: win.finish(true)
    }

    Item {
        id: canvas
        width: win.job ? win.job.w : 1
        height: win.job ? win.job.h : 1

        Rectangle {
            anchors.fill: parent
            visible: !!win.job && win.job.compose && !win.job.plain
            color: Colors.surface_container_lowest
        }
        Image {
            id: bg
            anchors.fill: parent
            visible: !!win.job && win.job.compose && win.job.bg !== ""
            source: win.job && win.job.compose && win.job.bg !== "" ? "file://" + win.job.bg : ""
            fillMode: Image.PreserveAspectCrop
            cache: false
        }
        // compose: the saved pictures
        Repeater {
            model: win.job && win.job.compose ? win.job.items : []
            // each window with the corner radius the compositor gives it
            delegate: ClippingRectangle {
                id: cell
                required property var modelData
                x: modelData.x
                y: modelData.y
                width: modelData.w
                height: modelData.h
                radius: modelData.radius
                color: "transparent"
                Image {
                    anchors.fill: parent
                    source: "file://" + cell.modelData.file
                    cache: false
                    onStatusChanged: if (status === Image.Ready) win.markGot(cell.modelData.addr)
                }
            }
        }
        // parts: the windows themselves
        Repeater {
            model: win.job && !win.job.compose ? win.job.items : []
            delegate: ScreencopyView {
                id: view
                required property var modelData
                readonly property var handle: Hyprland.toplevels.values.find(t => t.address === modelData.addr) || null
                captureSource: handle ? handle.wayland : null
                live: false
                paintCursor: !!win.job && win.job.cursor
                width: modelData.w
                height: modelData.h
                property int tries: 0
                Timer {
                    interval: 250
                    repeat: true
                    running: !!view.captureSource && !view.hasContent && view.tries < 9
                    onTriggered: {
                        view.tries += 1;
                        view.captureFrame();
                    }
                }
                // a moment for the first frame to be drawn before it is read back
                Timer {
                    id: save
                    interval: 160
                    onTriggered: view.grabToImage(r => {
                        if (r.saveToFile(view.modelData.out))
                            win.markGot(view.modelData.addr);
                    })
                }
                onHasContentChanged: if (hasContent) save.restart()
            }
        }
    }
}
