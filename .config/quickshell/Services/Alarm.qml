pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

// One quick alarm: either a countdown ("in 10 minutes") or a wall-clock time ("at 07:30", the next time
// that comes round). It runs from a deadline, so it survives a shell restart. When it goes off it rings
// (the alarm sound repeats) until stopped or snoozed, and posts a notification with Stop / +5 min.
Singleton {
    id: alarm

    property double deadline: 0          // ms timestamp, 0 = no alarm
    property string kind: "timer"        // timer | clock
    property bool ringing: false
    property real remaining: 0           // seconds left
    readonly property bool active: deadline > 0 && !ringing

    readonly property string label: {
        const s = Math.max(0, Math.ceil(remaining));
        const h = Math.floor(s / 3600), m = Math.floor(s / 60) % 60;
        const mm = String(m).padStart(2, "0"), ss = String(s % 60).padStart(2, "0");
        return h > 0 ? h + ":" + mm + ":" + ss : mm + ":" + ss;
    }
    readonly property string atLabel: deadline > 0 ? Qt.formatDateTime(new Date(deadline), "HH:mm") : ""

    function setIn(minutes) {
        _arm(Date.now() + Math.max(1, minutes) * 60000, "timer");
    }
    function setAt(hhmm) {
        const m = /^(\d{1,2}):(\d{2})$/.exec(String(hhmm));
        if (!m || +m[1] > 23 || +m[2] > 59)
            return false;
        const d = new Date();
        d.setHours(+m[1], +m[2], 0, 0);
        if (d.getTime() <= Date.now())
            d.setDate(d.getDate() + 1);
        _arm(d.getTime(), "clock");
        return true;
    }
    // nudge a running alarm; never past now
    function add(minutes) {
        if (!active)
            return;
        deadline = Math.max(Date.now() + 5000, deadline + minutes * 60000);
        _tick();
        _save();
    }
    function cancel() {
        deadline = 0;
        remaining = 0;
        _stopRinging();
        _save();
    }
    function stop() {
        Sound.stop();
        cancel();
    }
    function snooze(minutes) {
        _stopRinging();
        _arm(Date.now() + (minutes || 5) * 60000, "timer");
    }

    // action ids: "alarm:stop" / "alarm:snooze"; false when it isn't ours
    function handleAction(identifier) {
        if (identifier === "alarm:stop")
            stop();
        else if (identifier === "alarm:snooze")
            snooze(5);
        else
            return false;
        return true;
    }

    function _arm(at, k) {
        _stopRinging();
        deadline = at;
        kind = k;
        _tick();
        _save();
    }
    function _tick() {
        remaining = deadline > 0 ? Math.max(0, (deadline - Date.now()) / 1000) : 0;
        if (deadline > 0 && !ringing && remaining <= 0)
            _ring();
    }
    function _ring() {
        ringing = true;
        Sound.play("alarm");
        repeat.restart();
        giveUp.restart();
        Quickshell.execDetached(["notify-send", "-a", "Alarm", "-u", "critical", "-t", "0", "-A", "alarm:stop=Stop", "-A", "alarm:snooze=+5 min", "Alarm", kind === "clock" ? "It's " + atLabel + "." : "Your timer is up."]);
        _save();
    }
    function _stopRinging() {
        ringing = false;
        repeat.stop();
        giveUp.stop();
        Sound.stop();
    }

    Timer {
        interval: 500
        repeat: true
        running: alarm.deadline > 0 && !alarm.ringing
        onTriggered: alarm._tick()
    }
    // the sound is a short clip: keep it going while it rings
    Timer {
        id: repeat
        interval: 5000
        repeat: true
        onTriggered: Sound.play("alarm")
    }
    // nobody answered
    Timer {
        id: giveUp
        interval: 120000
        onTriggered: alarm.cancel()
    }

    // ---- persistence ----
    function _save() {
        adapter.deadline = ringing ? 0 : deadline;
        adapter.kind = kind;
        store.writeAdapter();
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/alarm.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            alarm.kind = adapter.kind;
            const at = adapter.deadline;
            if (at <= 0)
                return;
            alarm.deadline = at;
            alarm._tick();
            // went off while the shell was down: ring only if it was only just now, otherwise forget it
            if (alarm.ringing && Date.now() - at > 10 * 60000)
                alarm.cancel();
        }

        JsonAdapter {
            id: adapter
            property real deadline: 0
            property string kind: "timer"
        }
    }
}
