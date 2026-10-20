pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs

// Busy and rest days, shared by every heatmap and streak (tasks, immersion, Anki). A busy day halves
// that day's goal; a rest day keeps the goal but a miss only pauses the streak. Meeting the goal on
// either still counts. Rest days are limited per month, busy days are not.
//
// marks = { "yyyy-MM-dd": "busy" | "rest" }
Singleton {
    id: marksStore

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string todayKey: {
        const d = new Date();
        return d.getFullYear() + "-" + String(d.getMonth() + 1).padStart(2, "0") + "-" + String(d.getDate()).padStart(2, "0");
    }

    // the whole object is replaced on a change so bindings re-evaluate
    property var marks: ({})
    // rest days allowed per month
    property int restsPerMonth: 2

    function markOf(key) { return marks[key] || ""; }
    function isBusy(key) { return marks[key] === "busy"; }
    function isRest(key) { return marks[key] === "rest"; }
    function isMarked(key) { return !!marks[key]; }

    function restsUsed(key) {
        const ym = String(key).slice(0, 7);
        return Object.keys(marks).filter(k => marks[k] === "rest" && k.slice(0, 7) === ym).length;
    }
    function restsLeft(key) { return Math.max(0, restsPerMonth - restsUsed(key)); }
    function canMark(key, kind) { return kind !== "rest" || isRest(key) || restsLeft(key) > 0; }

    // `kind` "" clears; the kind the day already has toggles off
    function setMark(key, kind) {
        if (kind === marks[key])
            kind = "";
        if (kind !== "" && kind !== "busy" && kind !== "rest")
            return false;
        if (!canMark(key, kind))
            return false;
        const next = Object.assign({}, marks);
        if (kind === "")
            delete next[key];
        else
            next[key] = kind;
        marks = next;
        _save();
        return true;
    }
    // the goal that applies on a day
    function goalOn(goal, key) { return isBusy(key) ? Math.max(1, Math.ceil(goal / 2)) : goal; }

    function _save() {
        adapter.marks = marks;
        store.writeAdapter();
    }
    FileView {
        id: store
        path: marksStore.stateDir + "/daymarks.json"
        printErrors: false
        blockLoading: true

        onLoaded: marksStore.marks = adapter.marks || ({})
        onLoadFailed: marksStore._save()

        JsonAdapter {
            id: adapter
            property var marks: ({})
        }
    }

    IpcHandler {
        target: "daymarks"
        function set(kind: string, key: string): string {
            const k = key === "" ? marksStore.todayKey : key;
            return marksStore.setMark(k, kind === "clear" ? "" : kind) ? marksStore.markOf(k) || "cleared" : "refused";
        }
        function get(key: string): string { return marksStore.markOf(key === "" ? marksStore.todayKey : key); }
        function dump(): string { return JSON.stringify(marksStore.marks); }
    }
}
