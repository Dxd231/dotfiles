pragma ComponentBehavior: Bound

import QtQuick
import Quickshell
import Quickshell.Wayland

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
    anchors {
        left: true
        right: true
        top: true
        bottom: true
    }
    mask: Region {}

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "quickshell-share-picker-identify"
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

    Rectangle {
        anchors.fill: parent
        anchors.margins: 10
        color: "transparent"
        border.color: Colors.primary
        border.width: 6
        radius: 18
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(implicitWidth, overlay.width - 80)
        implicitWidth: identificationText.implicitWidth + 48
        implicitHeight: identificationText.implicitHeight + 32
        color: Qt.rgba(Colors.inverse_surface.r, Colors.inverse_surface.g,
            Colors.inverse_surface.b, 0.85)
        border.color: Qt.rgba(Colors.primary.r, Colors.primary.g, Colors.primary.b, 0.5)
        border.width: 1
        radius: 18

        Text {
            id: identificationText
            anchors.centerIn: parent
            color: Colors.inverse_on_surface
            font.pixelSize: 28
            font.weight: Font.DemiBold
            horizontalAlignment: Text.AlignHCenter
            text: overlay.label
        }
    }
}
