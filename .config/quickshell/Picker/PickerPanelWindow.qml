pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick
import qs.Components

Scope {
    id: root

    // PanelWindow is provided dynamically by Quickshell's active layer-shell backend.
    // qmllint disable uncreatable-type
    PanelWindow {
        id: surface

        color: "transparent"
        screen: content.preferredScreen
        visible: content.windowModelReady && content.preferredScreen !== null
        implicitWidth: content.preferredWidth
        implicitHeight: content.preferredHeight
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-share-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        // M3 dialog surface: surface-container-high, 28px corners
        Rectangle {
            id: panelBg
            anchors.fill: parent
            color: content.backgroundColor
            radius: Motion.shapeExtraLarge
            scale: surface.visible ? 1 : 0.94
            opacity: surface.visible ? 1 : 0
            Behavior on scale { Spring { speed: "default" } }
            Behavior on opacity { Fade { speed: "default" } }
        }

        PickerWindow {
            id: content
            anchors.fill: parent
            hostWindow: surface
            scale: panelBg.scale
            opacity: panelBg.opacity
        }

        onClosed: content.cancel()
    }

    ScreenIdentificationOverlay {
        targetScreen: content.identificationVisible ? content.identificationScreen : null
        label: content.identificationLabel
    }
}
