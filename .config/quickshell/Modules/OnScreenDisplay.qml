pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import Quickshell.Io

Scope {
    id: osdroot
    property var theme
    property var settings

    // Keep the sink alive so volume changes are tracked
    PwObjectTracker {
        id: pipewire
        objects: [ Pipewire.defaultAudioSink ]
    }

    readonly property real rawVolume: Pipewire.defaultAudioSink?.audio ? Pipewire.defaultAudioSink.audio.volume : 0
    readonly property real currentVolume: Math.max(0, Math.min(1.0, rawVolume))
    readonly property bool muted: Pipewire.defaultAudioSink?.audio ? Pipewire.defaultAudioSink.audio.muted : false

    property bool shouldShowOsd: false

    function showOsd() {
        osdroot.shouldShowOsd = true
        hideTimer.restart()
    }

    Timer {
        id: hideTimer
        interval: 1800          // Android standard OSD timeout
        onTriggered: osdroot.shouldShowOsd = false
    }

    // Grace period so OSD doesn't show up on initial startup/reload
    property bool ready: false
    Timer {
        interval: 1200
        running: true
        onTriggered: osdroot.ready = true
    }

    Connections {
        target: Pipewire.defaultAudioSink ? Pipewire.defaultAudioSink.audio : null
        function onVolumeChanged() {
            if (osdroot.ready) {
                osdroot.showOsd()
            }
        }
        function onMutedChanged() {
            if (osdroot.ready) {
                osdroot.showOsd()
            }
        }
    }

    IpcHandler {
        target: "osd"   

        function volumeUp() {
            const audio = Pipewire.defaultAudioSink?.audio
            if (audio) {
                if (audio.muted)
                    audio.muted = false
                audio.volume = Math.min(1.0, (audio.volume ?? 0) + 0.05)
            }
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

        function show() {
            osdroot.showOsd()
        }
    }

    PanelWindow {
        id: osdWindow
        WlrLayershell.namespace: "quickshell:osd"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.top: true
        margins.top: 25
        exclusiveZone: 0
        visible: osdroot.shouldShowOsd || osdContainer.opacity > 0.005

        implicitWidth: 440
        implicitHeight: 110
        color: "transparent"

        Item {
            id: osdContainer
            width: 420
            height: 60
            anchors.horizontalCenter: parent.horizontalCenter
            y: osdroot.shouldShowOsd ? 45 : 5
            transformOrigin: Item.Top

            opacity: osdroot.shouldShowOsd ? 1 : 0
            scale: osdroot.shouldShowOsd ? 1 : 0.85

            Behavior on y {
                NumberAnimation {
                    duration: osdroot.shouldShowOsd ? 240 : 170
                    easing.type: osdroot.shouldShowOsd ? Easing.OutBack : Easing.InCirc
                    easing.overshoot: osdroot.shouldShowOsd ? 1.15 : 1.0
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: osdroot.shouldShowOsd ? 240 : 170
                    easing.type: osdroot.shouldShowOsd ? Easing.OutBack : Easing.InCirc
                    easing.overshoot: osdroot.shouldShowOsd ? 1.15 : 1.0
                }
            }
            Behavior on opacity {
                NumberAnimation {
                    duration: osdroot.shouldShowOsd ? 150 : 130
                    easing.type: osdroot.shouldShowOsd ? Easing.OutQuad : Easing.InQuad
                }
            }

            // Soft ambient drop shadow for elevation
            Rectangle {
                anchors.fill: sliderPill
                anchors.topMargin: 4
                anchors.bottomMargin: -4
                radius: sliderPill.radius
                color: Qt.alpha(osdroot.theme.shadow, 0.45)
                z: 0
            }

            // Main Pill Capsule
            ClippingRectangle {
                id: sliderPill
                anchors.fill: parent
                radius: height / 2
                color: Qt.alpha(osdroot.theme.surface_container_high, 0.9)
                border.width: 1
                border.color: sliderMouseArea.containsMouse ? Qt.alpha(osdroot.theme.primary, 0.4) : Qt.alpha(osdroot.theme.primary, 0.2)
                z: 1

                Behavior on border.color {
                    ColorAnimation { duration: 150 }
                }

                // Fill Bar
                Rectangle {
                    id: fillBar
                    anchors.left: parent.left
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: osdroot.muted ? 0 : Math.round(parent.width * osdroot.currentVolume)
                    radius: height / 2
                    color: osdroot.theme.primary

                    Behavior on width {
                        enabled: !sliderMouseArea.pressed
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }

                // Interactive MouseArea for drag & seek & wheel
                MouseArea {
                    id: sliderMouseArea
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    hoverEnabled: true

                    function updateVolume(mouseX) {
                        const fraction = Math.max(0, Math.min(1.0, mouseX / width));
                        const audio = Pipewire.defaultAudioSink?.audio;
                        if (audio) {
                            if (audio.muted && fraction > 0)
                                audio.muted = false;
                            audio.volume = fraction;
                        }
                        osdroot.showOsd();
                    }

                    onPressed: mouse => {
                        hideTimer.stop();
                        updateVolume(mouse.x);
                    }
                    onPositionChanged: mouse => {
                        if (pressed) {
                            hideTimer.stop();
                            updateVolume(mouse.x);
                        }
                    }
                    onReleased: {
                        hideTimer.restart();
                    }
                    onCanceled: {
                        hideTimer.restart();
                    }
                    onWheel: event => {
                        const delta = event.angleDelta.y > 0 ? 0.05 : -0.05;
                        const audio = Pipewire.defaultAudioSink?.audio;
                        if (audio) {
                            if (delta > 0 && audio.muted)
                                audio.muted = false;
                            audio.volume = Math.max(0, Math.min(1.0, (audio.volume ?? 0) + delta));
                        }
                        osdroot.showOsd();
                        event.accepted = true;
                    }
                    onEntered: {
                        hideTimer.stop();
                    }
                    onExited: {
                        if (!pressed)
                            hideTimer.restart();
                    }
                }

                // Content Row with Dynamic Material You Contrast
                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 16
                    anchors.rightMargin: 16
                    spacing: 12

                    // 1. Speaker Button (Mute Toggle)
                    Item {
                        id: speakerBtn
                        Layout.preferredWidth: 32
                        Layout.preferredHeight: 32
                        z: 5

                        Image {
                            id: speakerIcon
                            anchors.centerIn: parent
                            width: 26
                            height: 26
                            sourceSize.width: 26
                            sourceSize.height: 26
                            fillMode: Image.PreserveAspectFit
                            source: {
                                if (osdroot.muted || osdroot.currentVolume <= 0.01) {
                                    return "../assets/speaker-simple-x-fill.svg";
                                }
                                if (osdroot.currentVolume < 0.5) {
                                    return "../assets/speaker-low-fill.svg";
                                }
                                return "../assets/speaker-high-fill.svg";
                            }
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: (fillBar.width > 50 && !osdroot.muted)
                                    ? osdroot.theme.on_primary
                                    : (osdroot.muted ? Qt.alpha(osdroot.theme.on_background, 0.45) : osdroot.theme.primary)
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: hideTimer.stop()
                            onExited: if (!sliderMouseArea.pressed) hideTimer.restart()
                            onClicked: {
                                const audio = Pipewire.defaultAudioSink?.audio;
                                if (audio)
                                    audio.muted = !audio.muted;
                                osdroot.showOsd();
                            }
                        }
                    }

                    // 2. Stream Label
                    Text {
                        id: streamLabel
                        text: osdroot.muted ? "Muted" : "Volume"
                        color: (fillBar.width > 130 && !osdroot.muted)
                            ? osdroot.theme.on_primary
                            : osdroot.theme.on_background
                        font.family: (osdroot.settings && osdroot.settings.fontmedium) ? osdroot.settings.fontmedium : "Google Sans Medium"
                        font.pixelSize: 18
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                        opacity: 0.95
                    }

                    // 3. Flexible Spacer
                    Item {
                        Layout.fillWidth: true
                    }

                    // 4. Percentage Display
                    Text {
                        id: percentLabel
                        text: osdroot.muted ? "0%" : Math.round(osdroot.currentVolume * 100) + "%"
                        color: (fillBar.width > 340 && !osdroot.muted)
                            ? osdroot.theme.on_primary
                            : osdroot.theme.primary
                        font.family: (osdroot.settings && osdroot.settings.fontdefault) ? osdroot.settings.fontdefault : "Google Sans"
                        font.pixelSize: 16
                        font.bold: true
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // 5. Action Button (Three dots / volumePopup toggle)
                    Item {
                        id: actionBtn
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        z: 5

                        Row {
                            anchors.centerIn: parent
                            spacing: 3
                            Repeater {
                                model: 3
                                delegate: Rectangle {
                                    required property int index
                                    width: 4
                                    height: 4
                                    radius: 2
                                    color: (fillBar.width > 395 && !osdroot.muted)
                                        ? osdroot.theme.on_primary
                                        : osdroot.theme.primary
                                }
                            }
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            hoverEnabled: true
                            onEntered: hideTimer.stop()
                            onExited: if (!sliderMouseArea.pressed) hideTimer.restart()
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    const audio = Pipewire.defaultAudioSink?.audio;
                                    if (audio)
                                        audio.muted = !audio.muted;
                                    osdroot.showOsd();
                                } else {
                                    Quickshell.execDetached(["qs", "ipc", "call", "volumePopup", "toggle"]);
                                    osdroot.shouldShowOsd = false;
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
