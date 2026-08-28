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
        // No screen → compositor usually picks the focused monitor
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true
        margins.top: screen.height / 30
        exclusiveZone: 0
        visible: osdroot.shouldShowOsd || panelBg.opacity > 0

        implicitWidth: 300
        implicitHeight: 70
        color: "transparent"
        // Empty region = click-through
        mask: Region {}

        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 18
            color: Qt.alpha(osdroot.theme.background, 0.95)
            border.width: 1
            border.color: Qt.alpha(osdroot.theme.surface_bright, 0.8)

            states: [
                State {
                    name: "open"
                    when: osdroot.shouldShowOsd
                    PropertyChanges {
                        target: panelBg
                        scale: 1
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !osdroot.shouldShowOsd
                    PropertyChanges {
                        target: panelBg
                        scale: 0.1
                        opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "open"

                    NumberAnimation {
                        properties: "scale,opacity"
                        duration: 300
                        easing.type: Easing.OutCirc
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "scale,opacity"
                        duration: 150
                        easing.type: Easing.InCirc
                    }
                }
            ]


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
                        if (Pipewire.defaultAudioSink?.audio.volume < 0.75) { 
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