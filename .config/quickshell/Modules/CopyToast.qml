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

    function showToast(text) {
        message = text || "Copied to clipboard";
        shown = true;
        hideTimer.restart();
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
        mask: Region {}

        Elevation {
            anchors.fill: bar
            radius: bar.radius
            level: 3
            opacity: bar.opacity
        }

        Rectangle {
            id: bar
            x: 8
            y: 8
            width: Math.max(288, Math.min(560, row.implicitWidth + 32))
            height: 48
            radius: Motion.shapeExtraSmall
            color: Colors.inverse_surface
            opacity: toast.shown ? 1 : 0
            transformOrigin: Item.Bottom
            scale: toast.shown ? 1 : 0.85
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }

            Row {
                id: row
                anchors.verticalCenter: parent.verticalCenter
                x: 16
                spacing: 12
                Icon {
                    anchors.verticalCenter: parent.verticalCenter
                    name: "check_circle"
                    color: Colors.inverse_primary
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    width: Math.min(implicitWidth, 480)
                    role: "bodyMedium"
                    color: Colors.inverse_on_surface
                    elide: Text.ElideRight
                    text: toast.message
                }
            }
        }
    }
}
