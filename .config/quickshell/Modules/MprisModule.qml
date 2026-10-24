pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Services.Mpris
import qs
import qs.Components

// Now-playing chip: equalizer badge + marquee title. Scroll adjusts the player's volume.
BarChip {
    id: mpris

    property var player: null
    readonly property bool hasPlayer: !!player
    property var albumPopup: null
    readonly property bool playing: hasPlayer && player.playbackState === MprisPlaybackState.Playing
    property bool showVolume: false

    checked: !!albumPopup && albumPopup.isOpen
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    wheelEnabled: true
    implicitWidth: (showVolume ? volumeRow.implicitWidth : titleRow.implicitWidth) + 4 + 14
    clip: true
    Behavior on implicitWidth { Spring {} }

    onClicked: mouse => {
        if (mouse.button === Qt.LeftButton && albumPopup)
            albumPopup.isOpen = !albumPopup.isOpen;
        else if (mouse.button === Qt.MiddleButton && player)
            player.togglePlaying();
        else if (mouse.button === Qt.RightButton && player && player.loopSupported && player.canControl)
            player.loopState = player.loopState === MprisLoopState.Track ? MprisLoopState.Playlist : MprisLoopState.Track;
    }
    onScrolled: wheel => {
        if (!player)
            return;
        player.volume = Math.max(0, Math.min(1, player.volume + (wheel.angleDelta.y > 0 ? 0.05 : -0.05)));
        showVolume = true;
        volumeHide.restart();
    }

    Timer {
        id: volumeHide
        interval: 1200
        onTriggered: mpris.showVolume = false
    }

    Row {
        id: titleRow
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        opacity: mpris.showVolume ? 0 : 1
        Behavior on opacity { Fade {} }

        // equalizer badge: a turning shape while playing, the sunny shape while the popup is open
        ShapeBadge {
            anchors.verticalCenter: parent.verticalCenter
            shapeRest: "softBurst"
            shapeActive: "flower"
            active: mpris.checked
            spinning: mpris.playing
            badgeScale: mpris.pressed ? 0.85 : mpris.playing ? 1 : 0.9
            color: mpris.playing ? Colors.primary : Colors.primary_container

            Row {
                anchors.centerIn: parent
                spacing: 2
                Repeater {
                    model: 3
                    delegate: Rectangle {
                        id: eqBar
                        required property int index
                        anchors.verticalCenter: parent.verticalCenter
                        width: 3
                        radius: 1.5
                        height: 4
                        color: mpris.playing ? Colors.on_primary : Colors.on_primary_container
                        Behavior on color { ColorFade {} }

                        SequentialAnimation on height {
                            running: mpris.playing
                            loops: Animation.Infinite
                            onRunningChanged: if (!running) eqBar.height = 4
                            NumberAnimation { to: [10, 14, 8][eqBar.index]; duration: 260 + eqBar.index * 55; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 4; duration: 260 + eqBar.index * 55; easing.type: Easing.InOutSine }
                        }
                    }
                }
            }
        }

        Icon {
            // grows in beside the title, which makes way for it
            property real grow: mpris.hasPlayer && mpris.player.loopState === MprisLoopState.Track ? 1 : 0
            Behavior on grow { Spring { speed: "fast" } }
            visible: grow > 0.01
            width: 18 * Math.max(0, Math.min(1, grow))
            opacity: Math.max(0, Math.min(1, grow))
            scale: Math.max(0, grow)
            anchors.verticalCenter: parent.verticalCenter
            name: "repeat_one"
            size: 18
            color: Colors.primary
        }

        Item {
            id: marquee
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(title.implicitWidth, 240)
            height: title.implicitHeight
            clip: true
            readonly property real overflow: Math.max(0, title.implicitWidth - width)

            StyledText {
                id: title
                role: "labelLarge"
                jp: true
                color: mpris.contentColor
                text: mpris.hasPlayer ? (mpris.player.trackTitle || "Unknown track") : "No media"
                onTextChanged: {
                    scroll.stop();
                    x = 0;
                    if (marquee.overflow > 5)
                        scroll.restart();
                }

                SequentialAnimation {
                    id: scroll
                    loops: Animation.Infinite
                    running: marquee.overflow > 5 && mpris.hasPlayer
                    onRunningChanged: if (!running) title.x = 0
                    PauseAnimation { duration: 1800 }
                    NumberAnimation { target: title; property: "x"; to: -marquee.overflow; duration: Math.max(2000, marquee.overflow * 32) }
                    PauseAnimation { duration: 1400 }
                    NumberAnimation { target: title; property: "x"; to: 0; duration: 600; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
                    PauseAnimation { duration: 500 }
                }
            }
        }
    }

    // player volume feedback while scrolling
    Row {
        id: volumeRow
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8
        opacity: mpris.showVolume ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Fade {} }

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 24
            radius: 12
            color: Colors.primary_container
            Icon {
                anchors.centerIn: parent
                size: 18
                name: !mpris.hasPlayer || mpris.player.volume <= 0 ? "volume_mute" : mpris.player.volume < 0.5 ? "volume_down" : "volume_up"
                color: Colors.on_primary_container
            }
        }
        LinearProgress {
            anchors.verticalCenter: parent.verticalCenter
            width: 160
            value: mpris.hasPlayer ? mpris.player.volume : 0
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            width: 36
            horizontalAlignment: Text.AlignRight
            role: "labelLarge"
            text: Math.round((mpris.hasPlayer ? mpris.player.volume : 0) * 100) + "%"
        }
    }
}
