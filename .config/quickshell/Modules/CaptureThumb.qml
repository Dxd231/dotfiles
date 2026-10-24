import QtQuick
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.Components

// A still picture of one window, found by its Hyprland address (screencopy, so it works for windows
// that are off-screen or on another workspace). Size it from `sourceSize` to keep the aspect.
ScreencopyView {
    id: view

    property string addr
    readonly property var handle: Hyprland.toplevels.values.find(t => t.address === addr) || null

    captureSource: handle ? handle.wayland : null
    live: false
    paintCursor: false
    // the first frame can only be asked for once the window's context exists, so ask until it arrives
    property int tries: 0
    Timer {
        interval: 300
        repeat: true
        running: !!view.captureSource && !view.hasContent && view.tries < 12
        onTriggered: {
            view.tries += 1;
            view.captureFrame();
        }
    }

    // windows that are scrolled out of the layout have no picture to show
    Icon {
        anchors.centerIn: parent
        opacity: view.hasContent ? 0 : 0.6
        visible: opacity > 0
        Behavior on opacity { Fade {} }
        size: Math.max(12, Math.min(32, Math.min(view.width, view.height) * 0.4))
        name: "web_asset"
        color: Colors.on_surface_variant
    }
}
