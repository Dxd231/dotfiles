pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.Services

// Daily habits with per-day counts, rest days, notes, streaks, and reminders. Each task repeats on
// chosen weekdays; a day is ticked by hand (heatmap click, the list's check, the bar chip or a
// notification button). Reminders and the weekly recap fire from a 20 second ticker as desktop
// notifications.
//
// task = { id, name, days: [0..6] (Sun = 0), reminds: ["HH:mm"], nudge: bool, created: "yyyy-MM-dd",
//          target: n (daily count, default 1), done: { "yyyy-MM-dd": count }, skipped: { key: 1 },
//          notes: { key: "text" }, sessions: { key: n }, archived: bool, style: int,
//          pomodoro: bool (may be linked to the focus timer) }
// (older records with a single `remind` string keep working)
Singleton {
    id: tasks

    // a reminder went off for this task id (the bar chip rings)
    signal fired(string id)
    // a day was changed from the UI; `undo()` puts it back
    signal undoable(string message)

    // the tasks. Held here (and written through to the file) rather than read back from the JSON
    // adapter, whose change notification arrives a beat after a write: a read right after a change
    // would otherwise see the old state
    property var list: []
    // style counter, so a task keeps its shape and colour when others are deleted
    property int _seq: 0
    readonly property var active: list.filter(t => !t.archived)
    // the tasks the focus timer can be linked to
    readonly property var focusable: active.filter(t => t.pomodoro)
    readonly property var archivedList: list.filter(t => !!t.archived)
    readonly property int count: active.length
    // local date, refreshed by the ticker so midnight rolls everything over
    property string todayKey: keyOf(new Date())
    // evening nudge for streaks that would otherwise end tonight
    property int nudgeMinute: 21 * 60
    // rest days allowed per task per month
    property int freezesPerMonth: 6
    // Sunday recap goes out from this hour
    property int recapHour: 20
    readonly property bool weeklyRecap: adapter.weeklyRecap

    readonly property var dueToday: {
        const d = dateOf(todayKey);
        return active.filter(t => isDue(t, d) && !isSkipped(t, todayKey) && !DayMarks.isRest(todayKey));
    }
    readonly property int dueCount: dueToday.length
    readonly property int pendingCount: dueToday.filter(t => !isDone(t, todayKey)).length
    // the longest streak running among active tasks (lock screen)
    readonly property int topStreak: active.reduce((m, t) => Math.max(m, streak(t)), 0)

    // shapes (MorphShape indices) and accents handed out to tasks in turn
    readonly property var shapes: ["cookie4", "sunny", "clover4", "flower"]
    function shapeFor(t) { return shapes[(t && t.style || 0) % shapes.length]; }
    function accentFor(t) { return [Colors.primary, Colors.tertiary, Colors.secondary][(t && t.style || 0) % 3]; }
    function onAccentFor(t) { return [Colors.on_primary, Colors.on_tertiary, Colors.on_secondary][(t && t.style || 0) % 3]; }
    function containerFor(t) { return [Colors.primary_container, Colors.tertiary_container, Colors.secondary_container][(t && t.style || 0) % 3]; }
    function onContainerFor(t) { return [Colors.on_primary_container, Colors.on_tertiary_container, Colors.on_secondary_container][(t && t.style || 0) % 3]; }

    // ---- dates ----
    function pad(n) { return String(n).padStart(2, "0"); }
    function keyOf(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()); }
    function dateOf(key) {
        const p = String(key).split("-").map(Number);
        return new Date(p[0], p[1] - 1, p[2]);
    }
    function addDays(d, n) { return new Date(d.getFullYear(), d.getMonth(), d.getDate() + n); }

    // ---- lookups ----
    function byId(id) { return list.find(t => t.id === id) || null; }
    function byName(name) {
        const n = String(name).toLowerCase();
        return list.find(t => t.name.toLowerCase() === n) || null;
    }
    function isDue(t, date) { return !!t && t.days.indexOf(date.getDay()) >= 0; }
    function targetOf(t) { return Math.max(1, Math.floor(t && t.target || 1)); }
    function countOf(t, key) { return t && t.done && t.done[key] ? Number(t.done[key]) : 0; }
    // a busy day halves the target
    function targetOn(t, key) { return DayMarks.goalOn(targetOf(t), key); }
    function isDone(t, key) { return !!t && countOf(t, key) >= targetOn(t, key); }
    // 0..1 toward the day's target
    function progress(t, key) { return Math.min(1, countOf(t, key) / targetOn(t, key)); }
    function isSkipped(t, key) { return !!t && !!t.skipped && !!t.skipped[key]; }
    // a rest day of the task's own, or a busy / rest day marked for everything
    function isExcused(t, key) { return isSkipped(t, key) || DayMarks.isMarked(key); }
    function noteOf(t, key) { return t && t.notes && t.notes[key] ? String(t.notes[key]) : ""; }
    function sessionsOf(t, key) { return t && t.sessions && t.sessions[key] ? Number(t.sessions[key]) : 0; }
    function remindsOf(t) { return !t ? [] : t.reminds ? t.reminds : t.remind ? [t.remind] : []; }

    // ---- rest days ----
    function skipsUsed(t, key) {
        const ym = String(key).slice(0, 7);
        return Object.keys(t && t.skipped || {}).filter(k => k.slice(0, 7) === ym).length;
    }
    function freezesLeft(t, key) { return Math.max(0, freezesPerMonth - skipsUsed(t, key)); }
    function canSkip(t, key) { return isSkipped(t, key) || (!isDone(t, key) && freezesLeft(t, key) > 0); }

    // ---- streaks ----
    // consecutive done days counting back from today. A due day left undone breaks the run (today
    // doesn't yet: there is still time); days the task doesn't repeat on, and rest days, are skipped.
    function streak(t) {
        if (!t)
            return 0;
        const today = dateOf(todayKey);
        let s = 0;
        for (let i = 0; i < 1100; i++) {
            const d = addDays(today, -i), k = keyOf(d);
            if (k < t.created)
                break;
            if (isDone(t, k))
                s++;
            else if (i > 0 && isDue(t, d) && !isExcused(t, k))
                break;
        }
        return s;
    }
    // length of the run each done day belongs to (the heatmap shades plain tasks by it)
    function runLengths(t) {
        const out = {};
        if (!t)
            return out;
        let run = 0;
        for (let d = dateOf(t.created); keyOf(d) <= todayKey; d = addDays(d, 1)) {
            const k = keyOf(d);
            if (isDone(t, k)) {
                run++;
                out[k] = run;
            } else if (isDue(t, d) && !isExcused(t, k) && k !== todayKey) {
                run = 0;
            }
        }
        return out;
    }
    function bestStreak(t) {
        const runs = runLengths(t);
        let best = 0;
        for (const k in runs)
            best = Math.max(best, runs[k]);
        return best;
    }
    // share of the last 30 days' due days that were done (today only counts once it is done)
    function rate30(t) {
        if (!t)
            return 0;
        const today = dateOf(todayKey);
        let due = 0, done = 0;
        for (let i = 0; i < 30; i++) {
            const d = addDays(today, -i), k = keyOf(d);
            if (k < t.created || !isDue(t, d) || isExcused(t, k))
                continue;
            if (isDone(t, k)) {
                due++;
                done++;
            } else if (i > 0) {
                due++;
            }
        }
        return due > 0 ? Math.round(done / due * 100) : 0;
    }
    function levelOf(run) { return run >= 7 ? 4 : run >= 4 ? 3 : run >= 2 ? 2 : 1; }
    // count tasks shade by how much of the target was reached
    function levelOfProgress(p) { return p >= 1 ? 4 : p >= 0.66 ? 3 : p >= 0.33 ? 2 : 1; }
    function daysLabel(t) {
        if (!t)
            return "";
        const d = t.days.slice().sort();
        if (d.length === 7)
            return "Every day";
        if (d.length === 5 && d.join() === "1,2,3,4,5")
            return "Weekdays";
        if (d.length === 2 && d.join() === "0,6")
            return "Weekends";
        return d.map(n => ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][n]).join(", ");
    }

    // ---- changes: the whole array is replaced so bindings re-evaluate ----
    function _commit(arr) {
        list = arr;
        adapter.tasks = arr;
        adapter.seq = _seq;
        store.writeAdapter();
    }
    function _mutate(id, fn) {
        _commit(list.map(t => t.id === id ? fn(Object.assign({}, t)) : t));
    }
    function addTask(name, days, reminds, nudge, target, pomodoro) {
        const id = Date.now().toString(36) + Math.floor(Math.random() * 1296).toString(36);
        const task = {
            id: id,
            name: String(name).trim(),
            days: days && days.length ? days.slice().sort() : [0, 1, 2, 3, 4, 5, 6],
            reminds: reminds || [],
            nudge: !!nudge,
            pomodoro: !!pomodoro,
            created: todayKey,
            target: Math.max(1, Math.floor(target || 1)),
            done: {},
            skipped: {},
            notes: {},
            sessions: {},
            archived: false,
            style: _seq
        };
        _seq += 1;
        _commit(list.concat([task]));
        return id;
    }
    function updateTask(id, fields) {
        if (fields.pomodoro === false && id === Pomodoro.taskId)
            Pomodoro.setTask("");
        _mutate(id, t => {
            Object.assign(t, fields);
            if (fields.reminds !== undefined)
                t.remind = "";
            return t;
        });
    }
    // before the switch existed any task could be linked: keep the one the timer is on, and nothing else.
    // Both files load on their own schedule, so each side calls this once its half is in.
    function adoptLink(id) {
        if (id === "" || list.length === 0 || list.some(t => t.pomodoro !== undefined))
            return;
        list = list.map(t => Object.assign({}, t, { pomodoro: t.id === id }));
    }
    function removeTask(id) {
        _commit(list.filter(t => t.id !== id));
    }
    function archive(id, on) {
        _mutate(id, t => {
            t.archived = !!on;
            return t;
        });
    }
    // swap with the neighbour above (-1) or below (+1) among the active tasks
    function move(id, delta) {
        const act = active;
        const i = act.findIndex(t => t.id === id), j = i + delta;
        if (i < 0 || j < 0 || j >= act.length)
            return;
        const arr = list.slice();
        const ia = arr.findIndex(t => t.id === act[i].id), ib = arr.findIndex(t => t.id === act[j].id);
        const tmp = arr[ia];
        arr[ia] = arr[ib];
        arr[ib] = tmp;
        _commit(arr);
    }

    // one day's state: count, rest day, note. Marking a day earlier than `created` moves `created` back.
    function _setDay(t, key, st) {
        const done = Object.assign({}, t.done), skipped = Object.assign({}, t.skipped || {}), notes = Object.assign({}, t.notes || {});
        if (st.count !== undefined) {
            if (st.count > 0) {
                done[key] = st.count;
                delete skipped[key];
            } else {
                delete done[key];
            }
        }
        if (st.skipped !== undefined) {
            if (st.skipped) {
                skipped[key] = 1;
                delete done[key];
            } else {
                delete skipped[key];
            }
        }
        if (st.note !== undefined) {
            if (st.note)
                notes[key] = st.note;
            else
                delete notes[key];
        }
        if ((done[key] || skipped[key]) && key < t.created)
            t.created = key;
        t.done = done;
        t.skipped = skipped;
        t.notes = notes;
        return t;
    }

    // undo: the previous state of the last day changed from the UI
    property var _undo: null
    function _change(id, key, st, message) {
        const t = byId(id);
        if (!t)
            return;
        const before = { count: countOf(t, key), skipped: isSkipped(t, key), note: noteOf(t, key), created: t.created };
        _mutate(id, tt => _setDay(tt, key, st));
        if (message) {
            _undo = { id: id, key: key, before: before };
            tasks.undoable(message);
        }
    }
    function undo() {
        if (!_undo)
            return;
        const u = _undo;
        _undo = null;
        if (byId(u.id)) {
            _mutate(u.id, t => {
                _setDay(t, u.key, u.before);
                t.created = u.before.created;
                return t;
            });
        }
    }

    // tick a day: a plain task toggles; a count task goes +1 until the target, then back to 0
    function tick(id, key, announce) {
        const t = byId(id);
        if (!t)
            return;
        const n = countOf(t, key), target = targetOn(t, key);
        const next = n >= target ? 0 : (target === 1 ? 1 : n + 1);
        let msg = "";
        if (announce !== false)
            msg = next === 0 ? "Cleared " + t.name : target > 1 ? t.name + ": " + next + " of " + target : "Marked " + t.name + " done";
        _change(id, key, { count: next }, msg);
    }
    function toggleDone(id, key) { tick(id, key, true); }
    // a plain on/off (IPC): to the full target, or back to nothing
    function setDone(id, key, on) {
        const t = byId(id);
        if (t)
            _change(id, key, { count: on ? targetOn(t, key) : 0 }, "");
    }
    function setCount(id, key, n) {
        _change(id, key, { count: Math.max(0, Math.floor(n)) }, "");
    }
    function setSkip(id, key, on) {
        const t = byId(id);
        if (!t || (on && !canSkip(t, key)))
            return;
        _change(id, key, { skipped: !!on }, on ? "Rest day for " + t.name : "");
    }
    function setNote(id, key, text) {
        _change(id, key, { note: String(text).trim() }, "");
    }
    function clearDay(id, key) {
        const t = byId(id);
        if (t)
            _change(id, key, { count: 0, skipped: false, note: "" }, "Cleared " + t.name);
    }
    function addSession(id, key) {
        _mutate(id, t => {
            const s = Object.assign({}, t.sessions || {});
            s[key] = (s[key] || 0) + 1;
            t.sessions = s;
            return t;
        });
    }

    // ---- focus link: each finished focus session is tallied for the linked task, and a full cycle
    // (the set of sessions ending in the long break) counts as one completion ----
    Connections {
        target: Pomodoro
        function onFocusCompleted(id) {
            const t = tasks.byId(id);
            if (t && !t.archived)
                tasks.addSession(id, tasks.todayKey);
        }
        function onCycleCompleted(id) {
            const t = tasks.byId(id);
            if (!t || t.archived)
                return;
            const n = tasks.countOf(t, tasks.todayKey), target = tasks.targetOn(t, tasks.todayKey);
            if (n < target)
                tasks._change(id, tasks.todayKey, { count: n + 1 }, "Focus cycle counted for " + t.name);
        }
    }

    // ---- reminders ----

    function _minutes(hhmm) {
        const p = String(hhmm).split(":").map(Number);
        return p.length === 2 && !isNaN(p[0]) && !isNaN(p[1]) ? p[0] * 60 + p[1] : -1;
    }
    // 0..15 minutes after the given time of day: late enough to be a real reminder, early enough
    // that a shell restart in the afternoon doesn't replay the morning's
    function _inWindow(nowMin, atMin) { return atMin >= 0 && nowMin >= atMin && nowMin - atMin <= 15; }

    function _tick() {
        const now = new Date();
        todayKey = keyOf(now);
        const nowMin = now.getHours() * 60 + now.getMinutes();
        const fired = Object.assign({}, adapter.fired);
        let changed = false;

        for (const t of active) {
            if (!isDue(t, now) || isDone(t, todayKey) || isSkipped(t, todayKey))
                continue;
            let sent = false;
            for (const at of remindsOf(t)) {
                const k = t.id + ":remind:" + at;
                if (_inWindow(nowMin, _minutes(at)) && fired[k] !== todayKey) {
                    fired[k] = todayKey;
                    changed = true;
                    if (!sent) {
                        sent = true;
                        fire(t.id, "remind");
                    }
                }
            }
            if (!sent && t.nudge && !DayMarks.isMarked(todayKey) && streak(t) >= 3 && _inWindow(nowMin, nudgeMinute) && fired[t.id + ":nudge"] !== todayKey) {
                fired[t.id + ":nudge"] = todayKey;
                changed = true;
                fire(t.id, "nudge");
            }
        }

        const snooze = Object.assign({}, adapter.snoozed);
        for (const id in snooze) {
            if (snooze[id] > now.getTime())
                continue;
            delete snooze[id];
            changed = true;
            const t = byId(id);
            if (t && !t.archived && !isDone(t, todayKey))
                fire(id, "remind");
        }
        if (changed)
            adapter.snoozed = snooze;

        if (now.getDay() === 0 && nowMin >= recapHour * 60 && adapter.weeklyRecap && count > 0 && adapter.summaryWeek !== todayKey) {
            adapter.summaryWeek = todayKey;
            changed = true;
            sendRecap();
        }

        if (changed) {
            adapter.fired = fired;
            store.writeAdapter();
        }
    }

    function fire(id, kind) {
        const t = byId(id);
        if (!t)
            return;
        const s = streak(t);
        let body;
        if (kind === "nudge")
            body = "Your " + s + "-day streak ends tonight. Mark it done?";
        else if (targetOf(t) > 1)
            body = countOf(t, todayKey) + " of " + targetOf(t) + " so far today.";
        else
            body = s > 1 ? "Keep your " + s + "-day streak going." : "Time for today's " + t.name.toLowerCase() + ".";
        tasks.fired(id);
        Sound.play(kind === "nudge" ? "nudge" : "alarm");
        // urgent, so it stays up until answered. The task id rides in the action ids: the
        // notification server (Notifications.qml) hands the picked one to handleAction(), which
        // keeps working for a notification carried over a reload
        Quickshell.execDetached(["notify-send", "-a", "Tasks", "-u", "critical", "-t", "0", "-A", "done:" + id + "=Done", "-A", "snooze10:" + id + "=+10 min", "-A", "snooze60:" + id + "=+1 hour", t.name, body]);
    }

    // Sunday evening: how the week went
    function sendRecap() {
        let due = 0, done = 0, best = null, bestStreak = 0;
        const today = dateOf(todayKey);
        for (const t of active) {
            for (let i = 0; i < 7; i++) {
                const d = addDays(today, -i), k = keyOf(d);
                if (k < t.created || !isDue(t, d) || isExcused(t, k))
                    continue;
                due++;
                if (isDone(t, k))
                    done++;
            }
            const s = streak(t);
            if (s > bestStreak) {
                bestStreak = s;
                best = t;
            }
        }
        if (active.length === 0)
            return;
        const body = done + " of " + due + " done this week" + (best && bestStreak > 1 ? ". Best streak: " + best.name + " (" + bestStreak + " days)" : ".");
        Sound.play("recap");
        Quickshell.execDetached(["notify-send", "-a", "Tasks", "-u", "normal", "-t", "60000", "-A", "open:=Open tasks", "Weekly recap", body]);
    }
    function setWeeklyRecap(on) {
        adapter.weeklyRecap = !!on;
        store.writeAdapter();
    }

    // action ids look like "<action>:<task id>"; false when it isn't one of ours
    function handleAction(identifier) {
        const at = String(identifier).indexOf(":");
        if (at < 0)
            return false;
        const action = identifier.slice(0, at);
        if (["open", "done", "snooze10", "snooze60"].indexOf(action) < 0)
            return false;
        _onAction(identifier.slice(at + 1), action);
        return true;
    }

    function _onAction(id, action) {
        Sound.stop();
        if (action === "open") {
            Quickshell.execDetached(["qs", "ipc", "call", "tasks", "open"]);
        } else if (action === "done") {
            // one reminder answered is one of the day's target, never the whole count
            const t = byId(id);
            if (t)
                setCount(id, todayKey, Math.min(targetOn(t, todayKey), countOf(t, todayKey) + 1));
        } else if (action === "snooze10" || action === "snooze60") {
            const s = Object.assign({}, adapter.snoozed);
            s[id] = Date.now() + (action === "snooze10" ? 10 : 60) * 60000;
            adapter.snoozed = s;
            store.writeAdapter();
        }
    }

    Timer {
        interval: 20000
        repeat: true
        running: true
        onTriggered: tasks._tick()
    }

    // ---- persistence ----
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/tasks.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            tasks.list = adapter.tasks || [];
            tasks.adoptLink(Pomodoro.taskId);
            tasks._seq = adapter.seq;
        }

        JsonAdapter {
            id: adapter
            property var tasks: []
            // "<task id>:remind:<HH:mm>" / "<task id>:nudge" -> the day it last fired
            property var fired: ({})
            // style counter, so a task keeps its shape and colour when others are deleted
            property int seq: 0
            // the Sunday (yyyy-MM-dd) the weekly recap last went out
            property string summaryWeek: ""
            property bool weeklyRecap: true
            // task id -> epoch ms a snoozed reminder fires again
            property var snoozed: ({})
        }
    }
}
