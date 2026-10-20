pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs.Services

// Pomodoro focus timer: 25 min focus, 5 min short break, 15 min long break after every 4th
// focus. When a phase ends the next one starts on its own (only a phase that ran out while the shell
// was down waits for play). The countdown runs from a deadline, so it stays right while the panel is
// closed, and survives a shell restart. A break is only earned by finishing a focus session, never
// picked by hand. Every task has its own timer (time left, phase, finished sessions) and nothing is shared
// between them: only the linked task's timer runs, linking another one pauses it where it was and it
// picks up from there when linked again. The properties below always describe the linked task's timer.
Singleton {
    id: pomo

    property real focusMinutes: 25
    property real shortBreakMinutes: 5
    property real longBreakMinutes: 15
    property int longBreakEvery: 4
    // the linked task ("" = none): every focus session that finishes is tallied for it, and a full set
    // (the long break starting) counts as one completion of it (Services/Tasks.qml listens)
    property string taskId: ""
    signal focusCompleted(string taskId)
    signal cycleCompleted(string taskId)

    property string mode: "focus"        // focus | short | long
    property bool running: false
    property int completedFocus: 0       // focus sessions finished so far
    property var timers: ({})            // the other tasks' timers: id -> { mode, remaining, done }
    property double deadline: 0          // ms timestamp, while running
    property real remaining: duration    // seconds left in the current phase

    readonly property real duration: (mode === "focus" ? focusMinutes : mode === "short" ? shortBreakMinutes : longBreakMinutes) * 60
    readonly property real fraction: duration > 0 ? Math.max(0, Math.min(1, remaining / duration)) : 0
    // running, or paused part-way through a phase
    readonly property bool active: running || remaining < duration - 0.5
    readonly property bool onBreak: mode !== "focus"
    // focus sessions done in the current set of `longBreakEvery` (a full set during the long break)
    readonly property int doneInSet: mode === "long" ? longBreakEvery : completedFocus % longBreakEvery
    readonly property string modeLabel: mode === "focus" ? "Focus" : mode === "short" ? "Short break" : "Long break"
    readonly property string label: {
        const s = Math.max(0, Math.ceil(remaining));
        return String(Math.floor(s / 60)).padStart(2, "0") + ":" + String(s % 60).padStart(2, "0");
    }

    onDurationChanged: if (!running && !active) remaining = duration

    function start() {
        if (running)
            return;
        if (remaining <= 0)
            remaining = duration;
        deadline = Date.now() + remaining * 1000;
        running = true;
        _save();
    }
    function pause() {
        if (!running)
            return;
        _tick();
        running = false;
        _save();
    }
    function setTask(id) {
        if (id === taskId)
            return;
        pause();
        const saved = Object.assign({}, timers);
        saved[taskId] = { mode: mode, remaining: remaining, done: completedFocus };
        const t = saved[id] || { mode: "focus", remaining: focusMinutes * 60, done: 0 };
        delete saved[id];
        timers = saved;
        taskId = id;
        mode = t.mode;
        completedFocus = t.done;
        remaining = t.remaining;
        _save();
    }
    function toggle() {
        if (running)
            pause();
        else
            start();
    }
    // current phase back to its full length, stopped
    function reset() {
        running = false;
        remaining = duration;
        _save();
    }
    // end a break early; a focus session can only be finished, not skipped
    function skip() {
        if (mode !== "focus")
            _next(false);
    }

    function _tick() {
        remaining = Math.max(0, (deadline - Date.now()) / 1000);
        if (running && remaining <= 0)
            _finish(true);
    }

    // phase over: queue the next one. A natural finish (`notify`) carries straight on into it; one that
    // ran out while the shell was down leaves it stopped
    function _finish(notify) {
        const wasFocus = mode === "focus";
        _next(wasFocus, notify);
        if (!notify)
            return;
        if (wasFocus && taskId !== "")
            pomo.focusCompleted(taskId);
        if (wasFocus && mode === "long" && taskId !== "")
            pomo.cycleCompleted(taskId);
        if (wasFocus) {
            const mins = mode === "long" ? longBreakMinutes : shortBreakMinutes;
            Sound.play("focusDone");
            Quickshell.execDetached(["notify-send", "-a", "Focus timer", "Focus session complete", "Your " + Math.round(mins) + " minute break has started."]);
        } else {
            Sound.play("breakDone");
            Quickshell.execDetached(["notify-send", "-a", "Focus timer", "Break over", "Next focus session started."]);
        }
    }

    // `carryOn` keeps it running straight into the next phase, without `running` ever dropping (the bar
    // would flash the clock for a moment)
    function _next(countFocus, carryOn) {
        const ended = deadline;
        if (!carryOn)
            running = false;
        if (mode === "focus") {
            if (countFocus)
                completedFocus += 1;
            mode = completedFocus > 0 && completedFocus % longBreakEvery === 0 && countFocus ? "long" : "short";
        } else {
            mode = "focus";
        }
        if (carryOn) {
            // chain from the old deadline so the tick's lateness isn't lost; after a long suspend start
            // fresh instead, so the phases don't all fire back to back
            deadline = Math.max(ended, Date.now() - 1000) + duration * 1000;
            remaining = Math.max(0, (deadline - Date.now()) / 1000);
        } else {
            remaining = duration;
        }
        _save();
    }

    Timer {
        interval: 250
        repeat: true
        running: pomo.running
        onTriggered: pomo._tick()
    }

    // ---- persistence ----
    function _save() {
        adapter.mode = mode;
        adapter.running = running;
        adapter.deadline = deadline;
        adapter.remaining = remaining;
        adapter.completedFocus = completedFocus;
        adapter.timers = timers;
        adapter.taskId = taskId;
        store.writeAdapter();
    }

    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/pomodoro.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            pomo.mode = adapter.mode;
            pomo.taskId = adapter.taskId;
            Tasks.adoptLink(pomo.taskId);
            pomo.completedFocus = adapter.completedFocus;
            pomo.timers = Object.assign({}, adapter.timers);
            if (adapter.running) {
                pomo.deadline = adapter.deadline;
                pomo.running = true;
                pomo.remaining = Math.max(0, (pomo.deadline - Date.now()) / 1000);
                // ran out while the shell was down: queue the next phase quietly
                if (pomo.remaining <= 0)
                    pomo._finish(false);
            } else {
                pomo.remaining = adapter.remaining > 0 ? adapter.remaining : pomo.duration;
            }
        }

        JsonAdapter {
            id: adapter
            property string mode: "focus"
            property bool running: false
            property real deadline: 0
            property real remaining: 0
            property int completedFocus: 0
            property var timers: ({})
            property string taskId: ""
        }
    }
}
