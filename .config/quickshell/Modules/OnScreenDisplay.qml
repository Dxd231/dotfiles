pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick.Effects
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: osdroot
    property var theme
    // Keep the sink alive so volume changes are tracked
    PwObjectTracker {
        id: pipewire
        objects: [ Pipewire.defaultAudioSink ]
    }

    function showOsd() {
        osdroot.shouldShowOsd = true
        hideTimer.restart()
    }

    IpcHandler {
        target: "osd"   

        function volumeUp() {
            const audio = Pipewire.defaultAudioSink?.audio
            if (audio)
                audio.volume = Math.min(1.0, (audio.volume ?? 0) + 0.05)
            osdroot.showOsd()
        }

        function volumeDown() {
            const audio = Pipewire.defaultAudioSink?.audio
            if (audio)
                audio.volume = Math.max(0, (audio.volume ?? 0) - 0.05)
            osdroot.showOsd()
        }

        function mute() {
            const audio = Pipewire.defaultAudioSink?.audio
            if (audio)
                audio.muted = !audio.muted
            osdroot.showOsd()
        }
    }

    property bool shouldShowOsd: false

    Timer {
        id: hideTimer
        interval: 1000          // how long the OSD stays visible
        onTriggered: osdroot.shouldShowOsd = false
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true
        margins.top: screen.height / 30
        exclusiveZone: 0
        visible: osdroot.shouldShowOsd || panelBg.opacity > 0

        implicitWidth: 300
        implicitHeight: 70
        color: "transparent"
        mask: Region {}

        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 30
            color: Qt.alpha(osdroot.theme.background, 0.95)
            border.width: 1
            border.color: Qt.alpha(osdroot.theme.primary, 0.2)
            scale: osdroot.shouldShowOsd ? 1 : 0.3
            opacity: osdroot.shouldShowOsd ? 1 : 0
            readonly property real currentVolume: Math.max(0, Math.min(1, Pipewire.defaultAudioSink?.audio.volume ?? 0))
            readonly property bool muted: Pipewire.defaultAudioSink?.audio.muted ?? false

            Behavior on scale {
                NumberAnimation { duration: 180; easing.type: Easing.OutCirc }
            }
            Behavior on opacity {
                NumberAnimation { duration: 150; easing.type: Easing.InOutCirc }
            }

            RowLayout {
                anchors {
                    fill: parent
                    leftMargin: 10
                    rightMargin: 15
                }

                Image {
                    Layout.preferredWidth: 40
                    Layout.preferredHeight: 40
                    fillMode: Image.PreserveAspectFit
                    sourceSize {
                        width: 40
                        height: 40
                    }
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: osdroot.theme.primary
                    }
                    source: {
                        if (panelBg.muted || panelBg.currentVolume <= 0.01) {
                            return "../assets/speaker-simple-none-fill.svg"; 
                        }
                        if (panelBg.currentVolume < 0.75) { 
                            return "../assets/speaker-low-fill.svg"; 
                        }
                        else return "../assets/speaker-high-fill.svg"; 
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Repeater {
                        model: 20
                        delegate: Rectangle {
                            required property int index
                            Layout.fillWidth: true
                            Layout.preferredHeight: 10
                            radius: 2
                            color: index < Math.round(panelBg.currentVolume * 20)
                                ? osdroot.theme.primary
                                : Qt.alpha(osdroot.theme.scrim, 0.2)

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }
                    }
                }
            }
        }
    }
}
