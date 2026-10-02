pragma ComponentBehavior: Bound
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Effects

Rectangle {
    id: mod

    required property var theme
    required property var settings

    // ---- audio state ----
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false
    readonly property real shownVolume: muted ? 0 : volume

    readonly property bool hovered: hover.hovered
    property bool showIndicator: false

    // ---- volume boost (raise ceiling above 100%) ----
    property bool boostEnabled: false
    readonly property real maxVolume: boostEnabled ? 1.5 : 1.0

    readonly property string iconSource: muted ? "../assets/speaker-simple-x-fill.svg" : volume <= 0 ? "../assets/speaker-simple-none-fill.svg" : volume < 0.5 ? "../assets/speaker-low-fill.svg" : "../assets/speaker-high-fill.svg"

    PwObjectTracker {
        objects: [mod.sink]
    }

    function changeVolume(delta) {
        if (!mod.audio)
            return;
        if (delta > 0)
            mod.audio.muted = false;
        mod.audio.volume = Math.max(0, Math.min(mod.maxVolume, mod.audio.volume + delta));
    }

    height: 24
    width: showIndicator ? volumeRow.implicitWidth + 8 : 28
    radius: 12
    clip: true
    color: showIndicator ? Qt.alpha(theme.source_color, 0.1) : "transparent"

    Behavior on width {
        NumberAnimation {
            easing.type: Easing.OutCirc
            duration: 100
        }
    }
    Behavior on color {
        ColorAnimation {
            duration: 150
        }
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: mod.showIndicator = false
    }

    Row {
        id: volumeRow
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Image {
            anchors.verticalCenter: parent.verticalCenter
            source: mod.iconSource
            width: 20
            height: 20
            sourceSize.width: 22
            sourceSize.height: 22
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: mod.theme.primary
            }
        }

        Rectangle {
            id: track
            anchors.verticalCenter: parent.verticalCenter
            width: 90
            height: 6
            radius: 3
            color: Qt.alpha(mod.theme.on_background, 0.15)
            opacity: mod.showIndicator ? 1 : 0
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Rectangle {
                height: parent.height
                radius: parent.radius
                color: mod.theme.primary
                width: track.width * Math.min(1, mod.shownVolume / mod.maxVolume)
                Behavior on width {
                    NumberAnimation {
                        duration: 120
                        easing.type: Easing.OutCubic
                    }
                }
            }
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            text: Math.round(mod.volume * 100) + "%"
            color: mod.theme.on_background
            opacity: mod.showIndicator ? 0.8 : 0
            font.pixelSize: 14
            font.bold: true
            font.family: mod.settings.fontdefault
            Behavior on opacity {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }
    }

    HoverHandler {
        id: hover
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton) {
                mod.boostEnabled = !mod.boostEnabled;
                // pull the volume back down if it's above the new ceiling
                if (mod.audio && mod.audio.volume > mod.maxVolume)
                    mod.audio.volume = mod.maxVolume;
                mod.showIndicator = true;
                hideTimer.restart();
            } else if (mod.audio) {
                mod.audio.muted = !mod.audio.muted;
            }
        }
        onWheel: event => {
            mod.changeVolume(event.angleDelta.y > 0 ? 0.05 : -0.05);
            mod.showIndicator = true;
            hideTimer.restart();
            event.accepted = true;
        }
    }
}
