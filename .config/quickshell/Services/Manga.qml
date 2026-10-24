pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Services

// Manga library and reader backend: the Rust helper `qs-manga` (reader/) scans the manga folders, keeps
// progress and hands back page file paths. Pixels never travel over the pipe, QML loads the paths.
//
// The helper runs while the reader is open and for `keepSec` after it was last needed. Requests made
// before its "ready" line wait in _pending.
Singleton {
    id: manga

    readonly property string home: Quickshell.env("HOME")
    readonly property string binary: Quickshell.env("QS_MANGA_BIN") || home + "/.local/bin/qs-manga"
    readonly property int keepSec: 600

    // the reader overlay is showing
    property bool open: false
    // something other than the reader wants the helper (shelf, immersion)
    property bool wanted: false
    property bool ready: false
    property bool missing: false
    property string version: ""

    property int _seq: 0
    property var _cb: ({})
    property var _pending: []
    property bool _lingering: false

    // the library as the helper last reported it: [{ id, key, title, volumes: [{ id, number, title, pages, page, max, finished, cover, ... }] }]
    property var series: []
    property bool libraryLoaded: false
    // reading time and pages: { today, week, total: {secs, pages}, series: [{id, week, total}] }
    property var stats: ({ today: { secs: 0, pages: 0 }, week: { secs: 0, pages: 0 }, total: { secs: 0, pages: 0 }, series: [] })
    // page text recognition, as the helper last reported it: { state, error, current, focus, done, total, bg, idle, paused, rate_ppm, eta_s, worker }
    // state: off | idle | reading | waiting_idle | waiting_memory | paused | missing | error
    property var ocr: ({ state: "off", error: "", current: null, focus: null, done: 0, total: 0, bg: false, idle: false, paused: false, rate_ppm: 0, eta_s: null, worker: { running: false, device: "", rss_mb: 0 } })
    // seconds without input before other volumes may be read in the background (env QS_MANGA_IDLE_SEC)
    readonly property int ocrIdleSec: Number(Quickshell.env("QS_MANGA_IDLE_SEC")) || 300
    // we paused the reading to give a snip engine the memory
    property bool _yielded: false
    // bumped when covers were (re)made, so images reload
    property int covRev: 0
    // the reader writes its state here for `qs ipc call manga state`
    property var readerState: ({})
    // the reader's per-frame values (spring positions), asked for only when `state` is called
    property var reader: null
    // the volume open in the reader, as a plain int so listeners don't re-run on every state change
    property int openVol: -1
    // the volume most recently read, for "continue"
    readonly property var latest: {
        let best = null;
        for (const s of series)
            for (const v of s.volumes)
                if (v.started && (!best || v.updated > best.vol.updated))
                    best = { series: s, vol: v };
        return best;
    }

    signal event(var e)
    // commands for the reader window: open (volume id, -1 = the library), close, next, prev, mode, zoom, page, offset
    signal command(string name, var arg)
    signal extracted(int vol)
    signal extractProgress(int vol, int done, int total)

    function show(vol) {
        open = true;
        command("open", vol === undefined ? -1 : vol);
    }
    function hide() {
        command("close", 0);
        open = false;
    }
    function ocrBackground(on) {
        request({ op: "ocr_bg", on: on }, r => { if (r.state) ocr = r; });
    }
    function ocrPause() {
        request({ op: "ocr_pause" }, r => { if (r.state) ocr = r; });
    }
    function ocrResume() {
        request({ op: "ocr_resume" }, r => { if (r.state) ocr = r; });
    }
    // the volume and page being read: its text comes first (vol < 0: none)
    function ocrFocus(vol, page) {
        request({ op: "ocr_focus", vol: vol, page: page });
    }
    // a snip engine is about to load: with little memory left the page reading steps aside until the engines quit
    function ocrYield() {
        if (ocr.worker.running && !ocr.paused && !_yielded) {
            _yielded = true;
            ocrPause();
        }
    }
    function _sendIdle() {
        request({ op: "ocr_idle", idle: idleWatch.isIdle });
    }
    function refreshLibrary() {
        request({ op: "stats" }, r => {
            if (r.today)
                stats = r;
        });
        request({ op: "library" }, r => {
            if (r.series) {
                series = r.series;
                libraryLoaded = true;
            }
        });
    }
    // 90 -> "2 min", 4000 -> "1 h 7 m"
    function fmtTime(secs) {
        const m = Math.round(secs / 60);
        return m < 60 ? m + " min" : Math.floor(m / 60) + " h " + (m % 60) + " m";
    }
    function seriesWeek(id) {
        const e = stats.series.find(x => x.id === id);
        return e ? e.week : 0;
    }
    function cover(path) {
        return path ? "file://" + path + "?r=" + covRev : "";
    }

    function request(req, done) {
        req.id = ++_seq;
        if (done)
            _cb[req.id] = done;
        keep();
        if (!ready) {
            _pending.push(req);
            return;
        }
        proc.write(JSON.stringify(req) + "\n");
    }

    // start the helper if it is not running and push the idle shutdown back
    function keep() {
        _lingering = true;
        idle.restart();
    }

    function _onLine(line) {
        let o;
        try {
            o = JSON.parse(line);
        } catch (e) {
            return;
        }
        if (o.ready !== undefined) {
            ready = o.ready === true;
            version = o.version || "";
            const q = _pending;
            _pending = [];
            q.forEach(r => proc.write(JSON.stringify(r) + "\n"));
            refreshLibrary();
            request({ op: "ocr_status" }, r => { if (r.state) ocr = r; });
            if (ocr.bg)
                _sendIdle();
            return;
        }
        if (o.event !== undefined) {
            if (o.event === "ocr_state") {
                ocr = o;
                return;
            }
            if (o.event === "ocr_room") {
                if (!Ocr.busy)
                    Ocr.stopEngines();
                return;
            }
            if (o.event === "library")
                refreshLibrary();
            else if (o.event === "covers")
                covRev++;
            else if (o.event === "extracted")
                extracted(o.vol);
            else if (o.event === "extract")
                extractProgress(o.vol, o.done, o.total);
            manga.event(o);
            return;
        }
        const cb = _cb[o.id];
        if (cb) {
            delete _cb[o.id];
            cb(o);
        }
    }

    Timer {
        id: idle
        interval: manga.keepSec * 1000
        onTriggered: manga._lingering = false
    }

    // input idle for ocrIdleSec (playing video and games hold the idle inhibitor, so they count as busy)
    IdleMonitor {
        id: idleWatch
        enabled: manga.ocr.bg
        timeout: manga.ocrIdleSec
        respectInhibitors: true
        onIsIdleChanged: manga._sendIdle()
    }
    // the snip engines are gone again: carry on reading pages
    Timer {
        interval: 5000
        repeat: true
        running: manga._yielded
        onTriggered: {
            if (!Ocr.procOf("manga").running && !Ocr.procOf("paddle").running) {
                manga._yielded = false;
                manga.ocrResume();
            }
        }
    }

    Process {
        id: proc
        command: [manga.binary]
        // background reading keeps the helper alive
        running: !manga.missing && (manga.open || manga.wanted || manga._lingering || manga.ocr.bg)
        stdinEnabled: true
        stdout: SplitParser { onRead: line => manga._onLine(line) }
        onExited: code => {
            manga.ready = false;
            manga._cb = ({});
            manga._pending = [];
            // 127 = sh could not find it; the binary is not installed (reader/install.sh)
            if (code === 127)
                manga.missing = true;
        }
    }

    IpcHandler {
        target: "manga"
        function ping(): string {
            manga.request({ op: "ping" }, r => console.log("manga ping:", JSON.stringify(r)));
            return "sent";
        }
        function state(): string {
            return JSON.stringify(Object.assign({ ready: manga.ready, missing: manga.missing, version: manga.version,
                                                  open: manga.open, binary: manga.binary, series: manga.series.length }, manga.readerState,
                                                  manga.reader ? manga.reader.liveState() : {}));
        }
        // the reader: open a volume (by id), or the library with no id
        function open(vol: int): void { manga.show(vol); }
        function library(): void { manga.show(-1); }
        function toggle(): void { if (manga.open) manga.hide(); else manga.show(-1); }
        function close(): void { manga.hide(); }
        function next(): void { manga.command("next", 0); }
        function prev(): void { manga.command("prev", 0); }
        function mode(m: string): void { manga.command("mode", m); }
        function zoom(f: real): void { manga.command("zoom", f); }
        function page(n: int): void { manga.command("page", n); }
        function offset(): void { manga.command("offset", 0); }
        function nextVolume(): void { manga.command("nextVolume", 0); }
        function chrome(): void { manga.command("chrome", 0); }
        // the text recognition status as JSON
        function ocr(): string { return JSON.stringify(manga.ocr); }
        function ocrBg(on: bool): void { manga.ocrBackground(on); }
        function ocrPause(): void { manga.ocrPause(); }
        function ocrResume(): void { manga.ocrResume(); }
        function rescan(): void { manga.request({ op: "rescan" }, r => console.log("manga rescan:", JSON.stringify(r))); }
        // the Kavita progress, once: prints what matched
        function importKavita(): void { manga.request({ op: "import_kavita" }, r => console.log("manga import:", JSON.stringify(r))); }
        // the library as JSON, titles and volume counts only
        function list(): string {
            return JSON.stringify(manga.series.map(s => ({ id: s.id, title: s.title, volumes: s.volumes.map(v => v.id + ":" + v.title + (v.finished ? "✓" : v.started ? "@" + v.page : "")) })));
        }
    }
}
