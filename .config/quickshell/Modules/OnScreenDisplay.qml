pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Pipewire
import QtQuick.Effects
import Quickshell.Wayland

Scope {
    id: osdroot
    property var theme
    // Keep the sink alive so volume changes are tracked
    PwObjectTracker {
        id: pipewire
        objects: [ Pipewire.defaultAudioSink ]
    }

    Connections {
        target: Pipewire.defaultAudioSink?.audio

        function onVolumeChanged() {
            osdroot.shouldShowOsd = true
            hideTimer.restart()
        }
    }

    property bool shouldShowOsd: false

    Timer {
        id: hideTimer
        interval: 1000          // how long the OSD stays visible
        onTriggered: osdroot.shouldShowOsd = false
    }

    // Only create the window while it needs to be shown
    LazyLoader {
        active: osdroot.shouldShowOsd

        PanelWindow {
            // No screen → compositor usually picks the focused monitor
            WlrLayershell.namespace: "quickshell:osd"
            WlrLayershell.layer: WlrLayer.Overlay
            anchors.top: true
            margins.top: screen.height / 30
            exclusiveZone: 0

            implicitWidth: 300
            implicitHeight: 70
            color: "transparent"
            // Empty region = click-through
            mask: Region {}

            Rectangle {
                anchors.fill: parent
                radius: 8
                color: Qt.alpha(osdroot.theme.background, 0.8)
                border.width: 1
                border.color: osdroot.theme.surface_bright


                RowLayout {
                    anchors {
                        fill: parent
                        leftMargin: 10
                        rightMargin: 15
                    }

                    Image {
                        fillMode: Image.PreserveAspectFit
                        sourceSize {
                            width: 40
                            height: 40
                        }
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: osdroot.theme.source_color
                        }
                        source: {
                            if (Pipewire.defaultAudioSink?.audio.muted || Pipewire.defaultAudioSink?.audio.volume <= 0.01) {
                                return "../assets/speaker-simple-none-fill.svg"; 
                            }
                            if (Pipewire.defaultAudioSink?.audio.volume < 0.5) { 
                                return "../assets/speaker-low-fill.svg"; 
                            }
                            else return "../assets/speaker-high-fill.svg"; 
                        }
                    }

                    // Progress bar
                    Rectangle {
                        Layout.fillWidth: true
                        implicitHeight: 10
                        radius: 20
                        color: Qt.alpha(osdroot.theme.scrim, 0.2)

                        Rectangle {
                            anchors {
                                left: parent.left
                                top: parent.top
                                bottom: parent.bottom
                            }
                            width: parent.width * Math.min(1, Math.max(0, Pipewire.defaultAudioSink?.audio.volume ?? 0))
                            radius: parent.radius
                            color: osdroot.theme.source_color

                            Behavior on width {
                                NumberAnimation {
                                    duration: 200
                                    easing.type: Easing.InOutCirc
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}