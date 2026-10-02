pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import QtQuick.Effects
import QtQuick
import QtQuick.Layouts

Scope {
    id: toastRoot

    required property var theme
    required property var settings
    property bool visibleToast: false
    property string message: "Copied to clipboard"

    function showToast(text) {
        message = text || "Copied to clipboard";
        visibleToast = true;
        hideTimer.restart();
    }

    Timer {
        id: hideTimer
        interval: 1300
        onTriggered: toastRoot.visibleToast = false
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:copy_toast"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true
        margins.top: screen.height / 30
        exclusiveZone: 0
        visible: toastRoot.visibleToast || panel.opacity > 0
        implicitWidth: 270
        implicitHeight: 64
        color: "transparent"
        mask: Region {}

        Rectangle {
            id: panel
            anchors.fill: parent
            radius: 30
            color: Qt.alpha(toastRoot.theme.background, 0.95)
            border.width: 1
            border.color: Qt.alpha(toastRoot.theme.primary, 0.2)
            scale: toastRoot.visibleToast ? 1 : 0.3
            opacity: toastRoot.visibleToast ? 1 : 0

            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCirc }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.InOutCirc }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 14

                Image {
                    source: "../assets/check-fat-fill.svg"
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: toastRoot.theme.primary
                    }
                }

                Text {
                    Layout.fillWidth: true
                    text: toastRoot.message
                    color: toastRoot.theme.on_background
                    font.pixelSize: 16
                    font.bold: true
                    font.family: toastRoot.settings.fontdefault
                    elide: Text.ElideRight
                }
            }
        }
    }
}
