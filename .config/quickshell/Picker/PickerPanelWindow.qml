pragma ComponentBehavior: Bound

import Quickshell
import Quickshell.Wayland
import QtQuick

Scope {
    id: root

    // PanelWindow is provided dynamically by Quickshell's active layer-shell backend.
    // qmllint disable uncreatable-type
    PanelWindow {
        id: surface

        color: "transparent" //content.backgroundColor
        screen: content.preferredScreen
        visible: content.windowModelReady && content.preferredScreen !== null
        implicitWidth: content.preferredWidth
        implicitHeight: content.preferredHeight
        exclusiveZone: 0
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell-share-picker"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

        Rectangle {
            color: content.backgroundColor
            radius: 24
            anchors.fill: parent
            border.color: content.borderColor
            border.width: 1
        }

        PickerWindow {
            id: content

            anchors.fill: parent
            hostWindow: surface
        }

        onClosed: content.cancel()
    }

    ScreenIdentificationOverlay {
        targetScreen: content.identificationVisible ? content.identificationScreen : null
        label: content.identificationLabel
    }
}
