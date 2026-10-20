pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.Services

// Anki mining tracker. Talks to AnkiConnect (127.0.0.1:8765, only there while Anki runs) and turns the
// mining deck into cards mined per day, a streak and a daily goal. Only notes of the mining note type in
// the mining deck count; the suspended Kaishi deck is ignored. A note's id is its creation time in epoch
// milliseconds, so the day it was mined comes from the id alone. Anki starts its day at `rollover`
// o'clock, and so does this.
//
// word = { id, expression, reading, sentence, day, time }
Singleton {
    id: anki

    // today's count just crossed the goal (once a day)
    signal goalReached()

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string url: "http://127.0.0.1:8765"
    readonly property string deck: "Japanese"
    readonly property string noteType: "Kiku"
    readonly property string query: "deck:\"" + deck + "\" note:" + noteType
    // hour at which Anki's day turns over
    readonly property int rollover: 4

    // working copies, written through to anki.json
    property int goal: 10
    // the day the goal chime last played, so it sounds once a day
    property string goalDay: ""

    // ---- what Anki says ----
    // false until a poll succeeds, and again once one fails; the numbers below then show the last good read
    property bool online: false
    // a poll has succeeded at least once since the shell came up
    property bool fresh: false
    // dayKey -> cards mined
    property var days: ({})
    property var words: []
    property int streak: 0
    property int best: 0
    property int due: 0
    property int reviewedToday: 0
    // epoch ms of the newest mined note, 0 when there is none
    property real lastMinedAt: 0

    property real nowMs: Date.now()
    readonly property string todayKey: dayKey(nowMs)
    readonly property int minedToday: days[todayKey] || 0
    // a busy day halves the goal
    function goalOn(key) { return DayMarks.goalOn(goal, key); }
    readonly property int todayGoal: goalOn(todayKey)
    readonly property bool goalMet: minedToday >= todayGoal
    readonly property bool overGoal: minedToday > todayGoal
    readonly property int toGo: Math.max(0, todayGoal - minedToday)
    // minutes since the last card was mined, a large number when none was
    readonly property real minutesSinceMined: lastMinedAt > 0 ? (nowMs - lastMinedAt) / 60000 : 1e6

    function pad(n) {
        return n < 10 ? "0" + n : String(n);
    }
    // the Anki day a moment (epoch ms) falls in, as "yyyy-MM-dd"
    function dayKey(ms) {
        const d = new Date(ms - rollover * 3600000);
        return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
    }
    function strip(html) {
        return String(html || "").replace(/<[^>]*>/g, "").replace(/&nbsp;/g, " ").replace(/&amp;/g, "&").replace(/&lt;/g, "<").replace(/&gt;/g, ">").trim();
    }

    // ---- AnkiConnect ----
    function call(action, params, done, fail) {
        const xhr = new XMLHttpRequest();
        xhr.timeout = 4000;
        xhr.onreadystatechange = () => {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            let r = null;
            try {
                r = JSON.parse(xhr.responseText);
            } catch (e) {}
            if (xhr.status === 200 && r && r.error === null) {
                if (done)
                    done(r.result);
            } else if (fail) {
                fail();
            }
        };
        xhr.open("POST", url);
        xhr.send(JSON.stringify({
            action: action,
            version: 6,
            params: params || ({})
        }));
    }

    property bool _busy: false
    function refresh() {
        if (_busy)
            return;
        _busy = true;
        nowMs = Date.now();
        // the notes themselves come back in one go; ids are the creation times
        call("findNotes", {
            query: query + " added:400"
        }, ids => {
            anki._gotIds(ids);
        }, anki._offline);
    }
    function _offline() {
        _busy = false;
        online = false;
    }
    function _gotIds(ids) {
        const d = {};
        let newest = 0;
        for (const id of ids) {
            const k = dayKey(id);
            d[k] = (d[k] || 0) + 1;
            newest = Math.max(newest, id);
        }
        lastMinedAt = newest;
        days = d;
        _streaks();
        const recent = ids.slice().sort((a, b) => b - a).slice(0, 15);
        call("notesInfo", {
            notes: recent
        }, infos => {
            anki._gotWords(infos);
        }, anki._offline);
    }
    function _gotWords(infos) {
        const out = infos.map(n => ({
                    id: n.noteId,
                    expression: strip(n.fields.Expression ? n.fields.Expression.value : ""),
                    reading: strip(n.fields.ExpressionReading ? n.fields.ExpressionReading.value : ""),
                    sentence: strip(n.fields.Sentence ? n.fields.Sentence.value : ""),
                    day: dayKey(n.noteId),
                    time: n.noteId
                }));
        out.sort((a, b) => b.id - a.id);
        words = out;
        call("getDeckStats", {
            decks: [deck]
        }, stats => {
            for (const k in stats) {
                const s = stats[k];
                anki.due = s.new_count + s.learn_count + s.review_count;
            }
            anki._gotDue();
        }, anki._offline);
    }
    function _gotDue() {
        call("getNumCardsReviewedToday", {}, n => {
            anki.reviewedToday = n;
            anki._busy = false;
            anki.online = true;
            anki.fresh = true;
        }, anki._offline);
    }

    // a streak is a run of goal-met days (goal halved on a busy day); a busy or rest day that falls short only
    // pauses it; today only extends it once it is met, but doesn't break it before
    function _streaks() {
        const met = k => (days[k] || 0) >= goalOn(k);
        const keyAt = d => d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate());
        const t = new Date(nowMs - rollover * 3600000);
        const today = new Date(t.getFullYear(), t.getMonth(), t.getDate());
        let bestRun = 0, run = 0;
        const first = Object.keys(days).sort()[0];
        if (first) {
            const p = first.split("-");
            for (let d = new Date(+p[0], +p[1] - 1, +p[2]); d <= today; d = new Date(d.getFullYear(), d.getMonth(), d.getDate() + 1)) {
                const k = keyAt(d);
                if (met(k))
                    run++;
                else if (!DayMarks.isMarked(k) && k !== todayKey)
                    run = 0;
                bestRun = Math.max(bestRun, run);
            }
        }
        best = bestRun;
        let cur = 0;
        for (let i = 0; i < 1100; i++) {
            const k = keyAt(new Date(today.getFullYear(), today.getMonth(), today.getDate() - i));
            if (met(k))
                cur++;
            else if (i > 0 && !DayMarks.isMarked(k))
                break;
        }
        streak = cur;
    }
    Connections {
        target: DayMarks
        function onMarksChanged() { anki._streaks(); }
    }
    function _dayDiff(a, b) {
        const pa = a.split("-"), pb = b.split("-");
        return Math.round((new Date(+pb[0], +pb[1] - 1, +pb[2]) - new Date(+pa[0], +pa[1] - 1, +pa[2])) / 86400000);
    }
    onGoalChanged: _streaks()

    function setGoal(n) {
        goal = Math.max(1, Math.min(200, Math.round(n)));
        _save();
    }

    // ---- the goal chime ----
    // Sounds when cards being *added* take today across the goal, once a day. Not on a restart that finds
    // the goal met, not when the goal itself is lowered, and not before the first poll has landed.
    property bool _goalReady: false
    property int _prevMined: 0
    property int _prevGoal: 10
    Timer {
        interval: 12000
        running: true
        onTriggered: {
            anki._prevMined = anki.minedToday;
            anki._prevGoal = anki.todayGoal;
            anki._goalReady = true;
            // already met today when the shell came up: nothing to announce
            if (anki.goalMet && anki.goalDay !== anki.todayKey) {
                anki.goalDay = anki.todayKey;
                anki._save();
            }
        }
    }
    onMinedTodayChanged: {
        const now = minedToday, was = _prevMined, g = _prevGoal;
        _prevMined = now;
        _prevGoal = todayGoal;
        if (!_goalReady || !fresh || g !== todayGoal)
            return;
        if (was < todayGoal && now >= todayGoal && goalDay !== todayKey) {
            goalDay = todayKey;
            _save();
            Sound.play("goal");
            goalReached();
        }
    }

    // ---- polling ----
    Timer {
        interval: 30000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: anki.refresh()
    }

    // ---- acting on Anki ----
    // opens the review screen for the mining deck, starting Anki first if it isn't running
    function review() {
        if (online) {
            call("guiDeckReview", {
                name: deck
            });
        } else {
            openAnki();
        }
    }
    function openAnki() {
        launcher.running = false;
        launcher.running = true;
    }
    Process {
        id: launcher
        command: ["anki"]
    }

    // ---- persistence ----
    function _save() {
        adapter.goal = goal;
        adapter.goalDay = goalDay;
        store.writeAdapter();
    }
    FileView {
        id: store
        path: anki.stateDir + "/anki.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            anki.goal = adapter.goal > 0 ? adapter.goal : 10;
            anki.goalDay = adapter.goalDay || "";
            anki._prevGoal = anki.todayGoal;
        }
        onLoadFailed: anki._save()

        JsonAdapter {
            id: adapter
            property int goal: 10
            property string goalDay: ""
        }
    }

    IpcHandler {
        target: "anki"
        function refresh(): void { anki.refresh(); }
        function goal(n: int): void { anki.setGoal(n); }
        function review(): void { anki.review(); }
        function dump(): string {
            return JSON.stringify({
                online: anki.online,
                today: anki.todayKey,
                mined: anki.minedToday,
                goal: anki.goal,
                streak: anki.streak,
                best: anki.best,
                due: anki.due,
                reviewed: anki.reviewedToday,
                days: anki.days,
                words: anki.words.map(w => w.expression)
            });
        }
    }
}
