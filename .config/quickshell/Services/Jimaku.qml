pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.Services

// Jimaku subtitles for the video in mpv. mpv/scripts/jimaku.lua fetches one when a file loads; the work
// is done by scripts/jimaku.py, which keeps what it found in immersion/jimaku.json (this reads it) and
// the API key in jimaku-auth.json outside the dotfiles repo. This tells the script which AniList entry
// each local file belongs to (immersion/jimaku-hints.json), and runs the panel's actions: pick another
// file, block an author, fix the entry. Everything goes to the script on stdin, never on argv.
Singleton {
    id: jk

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string script: Quickshell.shellDir + "/scripts/jimaku.py"

    property var files: ({})
    property var blacklist: []
    property bool hasKey: false
    property string keyError: ""
    property bool keyBusy: false

    // the video the panel is about: what mpv has open
    readonly property string path: Mpv.hasFile ? Mpv.path : ""
    readonly property var current: files[path] || null
    readonly property string state: current ? current.state : ""
    readonly property bool searching: state === "searching" || fetchProc.running
    readonly property var candidates: current && current.candidates ? current.candidates : []

    property var searchResults: []
    property bool entrySearching: false

    function baseName(p) {
        return String(p || "").split("/").pop();
    }

    // one run of the script at a time per command; a request that arrives meanwhile runs afterwards
    component Runner: Process {
        id: r
        required property string sub
        property var queued: null
        property string payload: ""
        signal finished(string text)
        command: ["python3", "-I", jk.script, sub]
        stdinEnabled: true
        stdout: StdioCollector {
            onStreamFinished: r.finished(text)
        }
        onStarted: {
            write(payload);
            stdinEnabled = false;
        }
        onRunningChanged: {
            if (!running) {
                stdinEnabled = true;
                if (queued !== null) {
                    const q = queued;
                    queued = null;
                    run(q);
                }
            }
        }
        function run(obj) {
            if (running) {
                queued = obj;
                return;
            }
            payload = JSON.stringify(obj);
            running = true;
        }
    }

    function _json(text) {
        try { return JSON.parse(text); } catch (e) { return ({}); }
    }
    // mpv loads the new subtitle itself when its script is reachable
    function _load(saved) {
        if (saved && Mpv.connected)
            Mpv.send(["script-message", "jimaku-reload", saved]);
    }

    // look again, even if a subtitle is saved
    function fetch() {
        if (path === "")
            return;
        if (Mpv.connected)
            Mpv.send(["script-message", "jimaku-fetch"]);
        else
            fetchProc.run({ path: path, force: true });
    }
    function pick(c) {
        if (path !== "" && c && c.url)
            pickProc.run({ path: path, url: c.url, name: c.name });
    }
    function block(name) {
        blockProc.run({ name: name });
    }
    function unblock(name) {
        unblockProc.run({ name: name });
    }
    function searchEntry(q) {
        entrySearching = true;
        searchResults = [];
        searchProc.run({ q: q });
    }
    function pinEntry(id) {
        if (path !== "")
            pinProc.run({ path: path, id: id });
    }
    function setKey(k) {
        keyError = "";
        keyBusy = true;
        keyProc.run({ key: k });
    }
    function logout() {
        logoutProc.run(null);
    }
    function openEntry() {
        if (current && current.entry && current.entry.id)
            Quickshell.execDetached(["librewolf", "--new-window", "https://jimaku.cc/entry/" + current.entry.id]);
    }
    function openAccount() {
        Quickshell.execDetached(["librewolf", "--new-window", "https://jimaku.cc/account"]);
    }

    Runner { id: fetchProc; sub: "fetch"; onFinished: text => jk._load(jk._json(text).saved) }
    Runner { id: pickProc; sub: "pick"; onFinished: text => jk._load(jk._json(text).saved) }
    Runner { id: pinProc; sub: "pin"; onFinished: text => jk._load(jk._json(text).saved) }
    Runner { id: blockProc; sub: "block"; onFinished: jk.fetch() }
    Runner { id: unblockProc; sub: "unblock"; onFinished: jk.fetch() }
    Runner { id: logoutProc; sub: "logout" }
    Runner {
        id: searchProc
        sub: "search"
        onFinished: text => {
            jk.entrySearching = false;
            try { jk.searchResults = JSON.parse(text); } catch (e) { jk.searchResults = []; }
        }
    }
    Runner {
        id: keyProc
        sub: "key"
        onFinished: text => {
            const o = jk._json(text);
            jk.keyBusy = false;
            jk.keyError = o.ok ? "" : (o.error || "That key didn't work");
        }
    }

    FileView {
        path: jk.stateDir + "/immersion/jimaku.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const o = JSON.parse(text());
                jk.files = o.files || ({});
                jk.blacklist = o.blacklist || [];
            } catch (e) {}
        }
    }
    FileView {
        path: jk.stateDir + "/jimaku-auth.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try { jk.hasKey = String(JSON.parse(text()).key || "") !== ""; } catch (e) { jk.hasKey = false; }
        }
        onLoadFailed: jk.hasKey = false
    }

    // which AniList entry each local file is, so the script doesn't have to guess from the name
    property string _hintSig: ""
    function writeHints() {
        const out = {};
        Immersion.animeFolders.forEach(f => {
            const fk = Immersion.parsePath(f.path, "").key;
            (f.parts || []).forEach(p => {
                const m = AniList.entryFor(fk, p.id);
                p.files.forEach(x => {
                    out[x[0]] = { anilistId: m ? m.id : 0, ep: x[1], key: fk + "|" + p.id };
                });
            });
        });
        const text = JSON.stringify(out);
        if (text === _hintSig)
            return;
        _hintSig = text;
        hintFile.setText(text);
    }
    FileView {
        id: hintFile
        path: jk.stateDir + "/immersion/jimaku-hints.json"
        printErrors: false
        atomicWrites: true
    }
    Timer {
        id: hintSoon
        interval: 3000
        onTriggered: jk.writeHints()
    }
    Connections {
        target: Immersion
        function onAnimeFoldersChanged() { hintSoon.restart(); }
    }
    Connections {
        target: AniList
        function onMatchesChanged() { hintSoon.restart(); }
    }

    IpcHandler {
        target: "jimaku"
        function fetch(): void { jk.fetch(); }
        function hints(): void { jk.writeHints(); }
        function dump(): string {
            return JSON.stringify({ path: jk.path, state: jk.state, hasKey: jk.hasKey, current: jk.current, blacklist: jk.blacklist });
        }
    }
}
