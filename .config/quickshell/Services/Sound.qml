pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Short alert sounds for the shell's own alarms (task reminders, the focus timer). One sound plays at
// a time, so a new alert replaces the one still ringing; `stop()` cuts it, e.g. once a reminder has been
// answered. Do not disturb mutes it (the notification server sets `muted`).
Singleton {
    id: sound

    property bool muted: false

    readonly property string dir: "/usr/share/sounds/freedesktop/stereo/"
    readonly property var files: ({
        alarm: "alarm-clock-elapsed.oga",   // a task reminder
        nudge: "dialog-warning.oga",        // the streak is about to end
        recap: "complete.oga",              // the weekly recap
        focusDone: "complete.oga",          // a focus session finished
        breakDone: "message-new-instant.oga",
        shutter: "camera-shutter.oga",      // a screenshot was taken
        recStop: "device-removed.oga",      // a recording was saved
        tick: "audio-volume-change.oga",    // the screenshot countdown
        goal: "service-login.oga"           // the immersion goal was reached
    })

    function play(kind) {
        if (muted || !files[kind])
            return;
        player.running = false;
        player.command = ["pw-play", dir + files[kind]];
        player.running = true;
    }
    function stop() {
        player.running = false;
    }

    Process {
        id: player
    }
}
