pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Pipewire
import qs
import qs.Components

// Output volume chip. Scroll: adjust (expands with a progress indicator).
// Left: mixer popup · Middle: mute · Right: toggle 150% boost ceiling.
BarChip {
    id: mod

    property var popup: null
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property var audio: sink ? sink.audio : null
    readonly property real volume: audio ? audio.volume : 0
    readonly property bool muted: audio ? audio.muted : false

    // the boost state lives on the mixer popup so the OSD can follow it
    readonly property bool boostEnabled: !!popup && popup.boostEnabled
    readonly property real maxVolume: boostEnabled ? 1.5 : 1.0
    property bool showIndicator: false

    readonly property string iconName: muted ? "volume_off" : volume <= 0 ? "volume_mute" : volume < 0.5 ? "volume_down" : "volume_up"

    PwObjectTracker { objects: [mod.sink] }

    function changeVolume(delta) {
        if (!audio)
            return;
        if (delta > 0)
            audio.muted = false;
        audio.volume = Math.max(0, Math.min(maxVolume, audio.volume + delta));
    }
    function flash() {
        showIndicator = true;
        hideTimer.restart();
    }

    checked: !!popup && popup.isOpen
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
    wheelEnabled: true
    implicitWidth: showIndicator ? row.implicitWidth + 4 + 12 : 32
    clip: true
    Behavior on implicitWidth { Spring {} }

    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (popup)
                popup.boostEnabled = !popup.boostEnabled;
            if (audio && audio.volume > maxVolume)
                audio.volume = maxVolume;
            flash();
        } else if (mouse.button === Qt.MiddleButton && audio) {
            audio.muted = !audio.muted;
        } else if (popup) {
            popup.toggle();
        }
    }
    onScrolled: wheel => {
        changeVolume(wheel.angleDelta.y > 0 ? 0.05 : -0.05);
        flash();
    }

    Timer {
        id: hideTimer
        interval: 2000
        onTriggered: mod.showIndicator = false
    }

    Row {
        id: row
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: mod.pressed ? 6 : mod.checked ? Motion.shapeSmall : 12
            color: mod.muted ? Colors.error_container : Colors.primary_container
            Behavior on radius { Spring {} }
            Behavior on color { ColorFade {} }
            Icon {
                anchors.centerIn: parent
                size: 18
                name: mod.iconName
                color: mod.muted ? Colors.on_error_container : Colors.on_primary_container
            }
        }

        LinearProgress {
            anchors.verticalCenter: parent.verticalCenter
            width: 88
            value: mod.muted ? 0 : mod.volume / mod.maxVolume
            activeColor: mod.boostEnabled && mod.volume > 1 ? Colors.tertiary : Colors.primary
            opacity: mod.showIndicator ? 1 : 0
            Behavior on opacity { Fade {} }
        }

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            role: "labelLarge"
            color: mod.contentColor
            text: Math.round(mod.volume * 100) + "%"
            opacity: mod.showIndicator ? 1 : 0
            Behavior on opacity { Fade {} }
        }
    }
}
