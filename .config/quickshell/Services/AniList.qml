pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.Services

// AniList for the shelf: matches anime series to AniList entries (cover, native title, episode count)
// and pushes watch progress to the user's list. The work is done by scripts/anilist.py, which keeps its
// state in immersion/anilist.json and the access token in its own file outside the dotfiles repo.
// Series and the token go to the script on stdin, never on the command line.
Singleton {
    id: al

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string script: Quickshell.shellDir + "/scripts/anilist.py"

    property var matches: ({})
    property var pushed: ({})
    property var viewer: null
    property string clientId: ""
    readonly property bool connected: viewer !== null

    property var searchResults: []
    property bool searching: false
    property bool loginFailed: false
    property string _matchSig: ""
    property string _mangaSig: ""

    function entryFor(key, season) {
        const m = matches[key + "|" + (season || 1)];
        return m && !m.miss ? m : null;
    }
    function openEntry(key, season) {
        const m = entryFor(key, season);
        if (m)
            Quickshell.execDetached(["librewolf", "--new-window", m.siteUrl]);
    }
    function authUrl(id) {
        return "https://anilist.co/api/v2/oauth/authorize?client_id=" + encodeURIComponent(id) + "&response_type=token";
    }

    // one run of the script at a time per command; a request that arrives meanwhile runs afterwards
    component Runner: Process {
        id: r
        required property string sub
        property var queued: null
        property string payload: ""
        signal finished(string text)
        command: ["python3", "-I", al.script, sub]
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
            const p = JSON.stringify(obj);
            if (running) {
                queued = obj;
                return;
            }
            payload = p;
            running = true;
        }
    }

    // series worth matching: anime played from a local file
    function _animeItems() {
        const out = [];
        Immersion.seriesList.forEach(s => {
            if (s.kind !== undefined || !s.counted)
                return;
            s.parts.forEach(p => {
                if (String(p.path).charAt(0) === "/" && p.partKind !== "sp")
                    out.push({ key: p.key, name: p.showName, season: p.season, label: p.name, kind: p.partKind,
                               episodes: p.episodes, minutes: p.length, year: p.hintYear });
            });
        });
        return out;
    }
    // manga series from the reader's library
    function _mangaItems() {
        return Manga.series.map(x => ({ key: x.key, title: x.title }));
    }
    function mangaKey(key) { return "manga:" + key; }
    function rematch() {
        _matchSig = "";
        _mangaSig = "";
        matchSoon.restart();
        mangaSoon.restart();
    }
    function syncProgress() {
        if (!connected)
            return;
        const items = [];
        Immersion.seriesList.forEach(s => {
            (s.kind === undefined ? s.parts : []).forEach(p => {
                const m = entryFor(p.key, p.season);
                if (m && p.watchedEp > 0 && p.watchedEp > (pushed[String(m.id)] || 0))
                    items.push({ id: m.id, episode: p.watchedEp, total: m.episodes });
            });
        });
        if (items.length > 0)
            pushProc.run(items);
        // volumes finished in the reader
        const vols = [];
        Manga.series.forEach(x => {
            const m = entryFor(mangaKey(x.key), 1);
            // the highest volume finished: earlier ones count as read even when they were never marked
            const n = x.volumes.reduce((t, v) => v.finished && v.number ? Math.max(t, v.number) : t, 0);
            if (m && n > (pushed["m" + m.id] || 0))
                vols.push({ id: m.id, volumes: n, total: m.volumes });
        });
        if (vols.length > 0)
            pushMangaProc.run(vols);
    }
    function search(q, type) {
        searching = true;
        searchResults = [];
        searchProc.run({ q: q, type: type || "ANIME" });
    }
    function pin(key, season, id, name, type) {
        pinProc.run({ key: key, season: season, id: id, name: name, type: type || "ANIME" });
    }
    function login(token, id) {
        loginFailed = false;
        loginProc.run({ token: token, clientId: id });
    }
    function logout() { logoutProc.run(null); }
    function saveClient(id) {
        clientId = id;
        clientProc.run({ clientId: id });
    }

    Runner { id: matchProc; sub: "match" }
    Runner { id: pushProc; sub: "push" }
    Runner { id: matchMangaProc; sub: "match_manga" }
    Runner { id: pushMangaProc; sub: "push_manga" }
    Runner { id: pinProc; sub: "pin" }
    Runner { id: clientProc; sub: "client" }
    Runner { id: logoutProc; sub: "logout" }
    Runner {
        id: searchProc
        sub: "search"
        onFinished: text => {
            al.searching = false;
            try { al.searchResults = JSON.parse(text); } catch (e) { al.searchResults = []; }
        }
    }
    Runner {
        id: loginProc
        sub: "login"
        onFinished: text => {
            try { al.loginFailed = !JSON.parse(text).ok; } catch (e) { al.loginFailed = true; }
        }
    }

    Timer {
        id: matchSoon
        interval: 1500
        onTriggered: {
            const items = al._animeItems();
            const sig = JSON.stringify(items);
            if (items.length === 0 || sig === al._matchSig)
                return;
            al._matchSig = sig;
            matchProc.run(items);
        }
    }
    Timer {
        id: syncSoon
        interval: 2500
        onTriggered: al.syncProgress()
    }
    Timer {
        id: mangaSoon
        interval: 3000
        onTriggered: {
            const items = al._mangaItems();
            const sig = JSON.stringify(items);
            if (items.length === 0 || sig === al._mangaSig)
                return;
            al._mangaSig = sig;
            matchMangaProc.run(items);
        }
    }
    Connections {
        target: Manga
        function onSeriesChanged() {
            mangaSoon.restart();
            syncSoon.restart();
        }
    }
    Connections {
        target: Immersion
        function onSeriesListChanged() {
            matchSoon.restart();
            syncSoon.restart();
        }
    }
    onMatchesChanged: syncSoon.restart()
    onConnectedChanged: syncSoon.restart()

    FileView {
        id: file
        path: al.stateDir + "/immersion/anilist.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                const o = JSON.parse(text());
                al.matches = o.matches || ({});
                al.pushed = o.pushed || ({});
                al.viewer = o.viewer || null;
                al.clientId = o.clientId || "";
            } catch (e) {}
        }
    }

    IpcHandler {
        target: "anilist"
        function rematch(): void { al.rematch(); }
        function sync(): void { al.syncProgress(); }
    }
}
