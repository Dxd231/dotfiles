pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs
import qs.Components

// Volume OSD: floating surface with an M3 Expressive medium slider (inset icon),
// mute toggle and a shortcut to the full mixer.
Scope {
    id: osd

    property var volumePopup: null

    PwObjectTracker { objects: [Pipewire.defaultAudioSink] }
    readonly property var audio: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
    // the bar chip's boost ceiling (what the keys may raise the volume to)
    readonly property real ceiling: volumePopup ? volumePopup.maxVolume : 1
    // slider scale: 0-100%, or 0-150% with boost on or a level above 100% set elsewhere
    // (two fixed scales, so the slider doesn't rescale while it's being dragged)
    readonly property real maxVolume: ceiling > 1 || (audio && audio.volume > 1) ? 1.5 : 1
    readonly property real volume: audio ? Math.max(0, Math.min(maxVolume, audio.volume)) : 0
    readonly property bool muted: audio ? audio.muted : false

    property bool shown: false
    property bool ready: false // suppress the OSD for volume events fired during startup

    function show() {
        shown = true;
        hideTimer.restart();
    }
    function setVolume(v) {
        if (!audio)
            return;
        if (v > 0)
            audio.muted = false;
        // never raise past the ceiling, but don't snap down a level that's already above it
        audio.volume = Math.max(0, Math.min(maxVolume, v, Math.max(ceiling, audio.volume)));
    }

    Timer {
        id: hideTimer
        interval: 1800
        onTriggered: if (!panelHover.hovered && !slider.pressed) osd.shown = false
    }
    Timer {
        interval: 1200
        running: true
        onTriggered: osd.ready = true
    }

    Connections {
        target: osd.audio
        function onVolumeChanged() { if (osd.ready) osd.show(); }
        function onMutedChanged() { if (osd.ready) osd.show(); }
    }

    IpcHandler {
        target: "osd"
        function volumeUp(): void { osd.setVolume(osd.volume + 0.05); osd.show(); }
        function volumeDown(): void { osd.setVolume(osd.volume - 0.05); osd.show(); }
        function mute(): void { if (osd.audio) osd.audio.muted = !osd.audio.muted; osd.show(); }
        function show(): void { osd.show(); }
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true
        exclusiveZone: 0
        visible: osd.shown || surface.opacity > 0
        implicitWidth: surface.width + 32
        implicitHeight: surface.height + 32
        color: "transparent"
        mask: Region { item: surface }

        Elevation {
            anchors.fill: surface
            radius: surface.radius
            level: 3
            opacity: surface.opacity
            scale: surface.scale
        }

        Rectangle {
            id: surface
            x: 16
            y: 8
            width: 420
            height: 72
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container
            transformOrigin: Item.Top
            opacity: osd.shown ? 1 : 0
            scale: osd.shown ? 1 : 0.9
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }

            HoverHandler {
                id: panelHover
                onHoveredChanged: if (!hovered) hideTimer.restart()
            }

            Row {
                anchors.centerIn: parent
                spacing: 8

                Slider {
                    id: slider
                    anchors.verticalCenter: parent.verticalCenter
                    width: 268
                    size: "m"
                    to: osd.maxVolume
                    icon: osd.muted ? "volume_off" : osd.volume <= 0 ? "volume_mute" : osd.volume < 0.5 ? "volume_down" : "volume_up"
                    value: osd.muted ? 0 : osd.volume
                    activeColor: osd.muted ? Colors.outline : osd.volume > 1 ? Colors.tertiary : Colors.primary
                    onMoved: v => {
                        osd.setVolume(v);
                        osd.show();
                    }
                    onPressedChanged: if (!pressed) hideTimer.restart()
                }

                Item {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 48
                    height: pct.implicitHeight
                    // the digits roll as the volume moves
                    RollingDigits {
                        id: pct
                        anchors.centerIn: parent
                        pixelSize: 14
                        weight: Font.Medium
                        color: Colors.on_surface_variant
                        text: osd.muted ? "Off" : String(Math.round(osd.volume * 100))
                    }
                }

                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: osd.muted ? "volume_off" : "volume_up"
                    style: "tonal"
                    checkable: true
                    checked: osd.muted
                    onClicked: if (osd.audio) osd.audio.muted = !osd.audio.muted
                }
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "tune"
                    onClicked: {
                        if (osd.volumePopup)
                            osd.volumePopup.show();
                        osd.shown = false;
                    }
                }
            }
        }
    }
}
