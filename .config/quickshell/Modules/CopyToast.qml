pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.Components

// M3 snackbar: inverse-surface, 4px corners, 48px single line, level 3.
// Bottom-left so it never covers the dock.
Scope {
    id: toast

    property string message: "Copied to clipboard"
    property bool shown: false
    // flips on every copy so the badge morphs each time, and kicks the bar when one lands while it shows
    property bool tick: false
    // an optional text button on the right (e.g. Undo); `action` runs when it is pressed
    property string actionText: ""
    property var action: null

    function showToast(text, actionLabel, callback) {
        message = text || "Copied to clipboard";
        actionText = actionLabel || "";
        action = callback || null;
        hideTimer.interval = actionText !== "" ? 4500 : 2000;
        if (shown)
            bar.pulse = 1;
        shown = true;
        tick = !tick;
        badge.badgeScale = 1.3;
        badgeBack.restart();
        hideTimer.restart();
    }
    Timer {
        id: badgeBack
        interval: 110
        onTriggered: {
            badge.badgeScale = 1;
            bar.pulse = 0;
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: toast.shown = false
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:copy_toast"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.bottom: true
        anchors.left: true
        margins.bottom: 24
        margins.left: 24
        exclusiveZone: 0
        visible: toast.shown || bar.opacity > 0
        implicitWidth: bar.width + 16
        implicitHeight: 48 + 16
        color: "transparent"
        // click-through, except over the bar while it carries a button
        mask: toast.actionText !== "" ? actionRegion : emptyRegion
        Region { id: emptyRegion }
        Region { id: actionRegion; item: bar }

        Elevation {
            anchors.fill: bar
            radius: bar.radius
            level: 3
            opacity: bar.opacity
            scale: bar.scale
            transform: Translate { y: bar.rise }
        }

        Rectangle {
            id: bar
            x: 8
            y: 8
            width: Math.max(288, Math.min(560, row.implicitWidth + 32))
            height: 48
            radius: Motion.shapeExtraSmall
            color: Colors.inverse_surface
            // rises from below the edge on a spring; a repeat copy pulses it
            property real pulse: 0
            property real rise: toast.shown ? 0 : 28
            Behavior on pulse { Spring { speed: "fast" } }
            opacity: toast.shown ? 1 : 0
            transformOrigin: Item.Bottom
            scale: (toast.shown ? 1 : 0.85) * (1 + 0.04 * pulse)
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            Behavior on rise { Spring { speed: "default" } }
            transform: Translate { y: bar.rise }

            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: 8
                spacing: 12
                // the check sits on a shape that morphs and pops on every copy
                ShapeBadge {
                    id: badge
                    anchors.verticalCenter: parent.verticalCenter
                    width: 32
                    height: 32
                    shapeRest: 1
                    shapeActive: 4
                    active: toast.tick
                    color: Colors.inverse_primary
                    Icon {
                        anchors.centerIn: parent
                        name: "check"
                        size: 20
                        color: Colors.inverse_surface
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, toast.actionText !== "" ? 360 : 480)
                    role: "bodyMedium"
                    color: Colors.inverse_on_surface
                    elide: Text.ElideRight
                    text: toast.message
                }
                Clickable {
                    visible: toast.actionText !== ""
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32
                    width: actionLabel.implicitWidth + 24
                    restRadius: 16
                    pressedRadius: 8
                    contentColor: Colors.inverse_primary
                    onClicked: {
                        const cb = toast.action;
                        toast.action = null;
                        toast.shown = false;
                        if (cb)
                            cb();
                    }
                    StyledText {
                        id: actionLabel
                        anchors.centerIn: parent
                        role: "labelLarge"
                        emphasized: true
                        color: Colors.inverse_primary
                        text: toast.actionText
                    }
                }
            }
        }
    }
}
