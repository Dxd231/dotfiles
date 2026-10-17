pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs.Components

// Briefly marks a monitor while hovering it in the Screen tab: a translucent primary
// wash over the whole output plus a centred name card (no outline).
// PanelWindow is provided dynamically by Quickshell's active layer-shell backend.
// qmllint disable uncreatable-type
PanelWindow {
    id: overlay

    required property var targetScreen
    required property string label

    screen: targetScreen
    visible: targetScreen !== null
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    anchors { left: true; right: true; top: true; bottom: true }
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-share-picker-identify"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colors.primary, 0.16)
        opacity: overlay.visible ? 1 : 0
        Behavior on opacity { Fade {} }
    }

    Elevation {
        anchors.fill: badgeCard
        radius: badgeCard.radius
        level: 3
        opacity: badgeCard.opacity
        scale: badgeCard.scale
    }

    Rectangle {
        id: badgeCard
        anchors.centerIn: parent
        width: Math.min(implicitWidth, overlay.width - 80)
        implicitWidth: badgeRow.implicitWidth + 48
        implicitHeight: badgeRow.implicitHeight + 48
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_high
        scale: overlay.visible ? 1 : 0.88
        opacity: overlay.visible ? 1 : 0
        Behavior on scale { Spring { speed: "default" } }
        Behavior on opacity { Fade {} }

        RowLayout {
            id: badgeRow
            anchors.centerIn: parent
            spacing: 24

            Rectangle {
                implicitWidth: 64
                implicitHeight: 64
                radius: Motion.shapeLarge
                color: Colors.primary_container
                Icon { anchors.centerIn: parent; name: "desktop_windows"; size: 32; color: Colors.on_primary_container }
            }
            StyledText {
                role: "headlineSmall"
                emphasized: true
                text: overlay.label
            }
        }
    }
}
