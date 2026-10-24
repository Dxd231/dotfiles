import QtQuick
import qs
import qs.Components
import qs.Services

// Shown in the bar while a screen recording runs: a breathing dot, the time, what is being recorded.
// Click stops it, right-click pauses and resumes.
BarChip {
    id: chip

    readonly property bool on: Capture.recording
    function clock(s) {
        const m = Math.floor(s / 60), h = Math.floor(m / 60);
        const p = n => (n < 10 ? "0" : "") + n;
        return h > 0 ? h + ":" + p(m % 60) + ":" + p(s % 60) : m + ":" + p(s % 60);
    }

    visible: implicitWidth > 1 || on
    danger: true
    checked: true
    clip: true
    acceptedButtons: Qt.LeftButton | Qt.RightButton
    implicitWidth: on ? row.implicitWidth + 24 : 0
    Behavior on implicitWidth { Spring {} }
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton)
            Capture.pauseRecording();
        else
            Capture.stopRecording();
    }

    Row {
        id: row
        x: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 8

        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            // the recording mark: a small boom that turns while it records
            Item {
                id: dotSlot
                anchors.fill: parent
                // the mark and the pause glyph trade places, rather than one popping over the other
                opacity: Capture.recPaused ? 0 : 1
                scale: Capture.recPaused ? 0.4 : 1
                Behavior on opacity { Fade {} }
                Behavior on scale { Spring { speed: "fast" } }
            ShapeBadge {
                id: dot
                anchors.centerIn: parent
                width: 14
                height: 14
                shapeRest: "boom"
                shapeActive: "boom"
                color: Colors.error
                spinning: chip.on && !Capture.recPaused
                spinSpeed: 40
                SequentialAnimation on opacity {
                    running: chip.on && !Capture.recPaused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.5; duration: 700; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 700; easing.type: Easing.InOutSine }
                }
            }
            }
            Icon {
                anchors.centerIn: parent
                opacity: Capture.recPaused ? 1 : 0
                scale: Capture.recPaused ? 1 : 0.4
                Behavior on opacity { Fade {} }
                Behavior on scale { Spring { speed: "fast" } }
                size: 16
                name: "pause"
                color: chip.contentColor
            }
        }
        RollingDigits {
            anchors.verticalCenter: parent.verticalCenter
            opacity: Capture.recStopping ? 0 : 1
            visible: opacity > 0
            width: implicitWidth * Math.max(0, opacity)
            Behavior on opacity { Fade {} }
            pixelSize: 14
            color: chip.contentColor
            text: chip.clock(Capture.elapsed)
        }
        // between pressing stop and the file being finished
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            opacity: Capture.recStopping ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            role: "labelLarge"
            emphasized: true
            color: chip.contentColor
            text: "Saving…"
        }
        Icon {
            anchors.verticalCenter: parent.verticalCenter
            size: 18
            color: chip.contentColor
            name: Capture.recTarget === "window" ? "web_asset" : Capture.recTarget === "workspace" ? "view_carousel" : Capture.recTarget === "region" ? "crop_free" : "desktop_windows"
        }
    }
}
