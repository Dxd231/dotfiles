pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.Services

// OCR for the shell. A snip freezes the focused monitor (grim), the overlay lets you pick a region, and
// the text is read by manga_ocr (manga) or PaddleOCR (anything else), copied to the clipboard and pushed
// to the Texthooker UI relay. Each engine is its own process (scripts/ocr_server.py in its venv),
// started the first time it is needed and stopped again after a while without use, so the models only
// occupy RAM / VRAM while they are being used.
//
// phase: idle -> capturing -> selecting -> warming (engine loading) -> running -> done | error
Singleton {
    id: ocr

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (home + "/.local/state")) + "/quickshell"
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") : "/tmp"
    // the snackbar (shell.qml): "Copied" once a result is on the clipboard
    property var toast: null
    // seconds an engine stays loaded without a request
    property int idleSeconds: Number(Quickshell.env("QS_OCR_IDLE_SEC")) || 600
    readonly property var venvPython: ({
        manga: home + "/.venv/bin/python",
        paddle: home + "/.venv/paddle/bin/python"
    })

    property string phase: "idle"
    property string monitor: ""
    // the frozen screenshot the overlay shows and the crop is read from
    property string frozen: ""
    property var current: null
    property var result: null
    property string errorText: ""
    // the focused window's kind when the snip started (kavita / mpv / ttu / "")
    property string startKind: ""
    property var history: []
    property var lastRegion: null
    property bool mangaReady: false
    property bool paddleReady: false
    property string mangaDevice: ""
    property string mangaModel: ""    // which weights the manga engine loaded: "CPT-flex" or "base"
    property string paddleDevice: ""
    property bool hookerSent: false
    // ---- dialogue-box awareness ----
    // text blocks found on the frozen screen, in logical pixels, top to bottom: { x, y, w, h, text, lines, conf, score, dialogue }
    property var blocks: []
    property bool detecting: false
    // who we are snipping: the focused window (app id + monitor size, plus ttu / kavita for a browser)
    property string windowKey: ""
    // the box remembered for that window (or null), and one remembered box per window overall
    property var windowRegion: null
    property var regions: ({})
    property bool _dialogueMode: false
    property int _detectId: -1
    property var _detectPending: null
    property int _seq: 0
    property var _pending: null
    property var _quitting: ({})

    function readyOf(e) { return e === "manga" ? mangaReady : paddleReady; }
    function procOf(e) { return e === "manga" ? mangaProc : paddleProc; }
    function engineLabel(e) { return e === "manga" ? (mangaModel === "CPT-flex" ? "manga-ocr CPT-flex" : "manga_ocr") : "PaddleOCR"; }
    readonly property bool busy: phase === "capturing" || phase === "warming" || phase === "running"

    // ---- which engine ----
    // manga when Kavita is the focused window (or the context we are in while no media window has
    // focus), or when the selection is a tall narrow strip; everything else is general text
    function pick(w, h) {
        if (startKind === "kavita")
            return "manga";
        if (startKind === "" && Immersion.context === "kavita")
            return "manga";
        return w > 0 && h > 2.2 * w ? "manga" : "paddle";
    }

    // ---- per-window memory ----
    function _keyNow() {
        const w = Immersion.activeWin;
        const m = Hyprland.focusedMonitor;
        let k = w && w.appId ? String(w.appId) : "unknown";
        const c = Immersion.activeCtx;
        if (c && (c.kind === "ttu" || c.kind === "kavita"))
            k += ":" + c.kind;
        return k + "@" + (m ? m.width + "x" + m.height : "");
    }
    function regionFor(key) { return regions[key] ? regions[key] : null; }
    function _remember(key, sel) {
        const r = Object.assign({}, regions);
        r[key] = { x: sel.x, y: sel.y, w: sel.w, h: sel.h, ts: Date.now() };
        const keys = Object.keys(r).sort((a, b) => r[b].ts - r[a].ts);
        keys.slice(50).forEach(k => delete r[k]);
        regions = r;
        windowRegion = r[key];
    }
    // the box for this window is forgotten; the next snip starts from the detected dialogue box again
    function forget() {
        const r = Object.assign({}, regions);
        delete r[windowKey !== "" ? windowKey : _keyNow()];
        regions = r;
        windowRegion = null;
        _saveStore();
        if (toast)
            toast.showToast("Forgot the remembered box");
    }
    function _begin() {
        startKind = Immersion.activeCtx ? Immersion.activeCtx.kind : "";
        windowKey = _keyNow();
        windowRegion = regionFor(windowKey);
        blocks = [];
        detecting = false;
    }

    // ---- entry points ----
    // freeze the focused monitor and open the selection overlay
    // the screenshot picker is up (or about to be): it owns the keyboard and the screen
    readonly property bool _captureUp: Capture.phase === "capturing" || Capture.phase === "selecting" || Capture.phase === "counting"
    function snip() {
        if (phase === "capturing" || phase === "selecting" || _captureUp)
            return;
        _begin();
        _capture("selecting");
    }
    // read the most likely dialogue box on screen, no UI: the box remembered for this window if it
    // matches a detected block, else the block that looks most like a dialogue box
    function dialogue() {
        if (phase === "capturing" || phase === "selecting" || busy || _captureUp)
            return;
        _begin();
        _dialogueMode = true;
        _capture("dialogue");
    }
    // read the last region again, no UI: the one-key path for games
    function again() {
        if (phase === "capturing" || phase === "selecting" || _captureUp)
            return;
        _begin();
        if (!windowRegion && !lastRegion) {
            _capture("selecting");
            return;
        }
        _capture("again");
    }
    // OCR the image currently on the clipboard
    function clipboard() {
        if (busy)
            return;
        startKind = Immersion.activeCtx ? Immersion.activeCtx.kind : "";
        _dropFrozen();
        frozen = runDir + "/qs-ocr-clip-" + Date.now() + ".png";
        grab.mode = "clipboard";
        grab.command = ["sh", "-c", "wl-paste --type image/png > '" + frozen + "' && [ -s '" + frozen + "' ]"];
        phase = "capturing";
        grab.running = true;
    }
    // the overlay's confirm: `sel` in logical pixels, `scale` = capture pixels per logical pixel
    function confirm(sel, scale, choice) {
        lastRegion = { x: sel.x, y: sel.y, w: sel.w, h: sel.h };
        _remember(windowKey !== "" ? windowKey : _keyNow(), sel);
        _saveStore();
        const e = choice === "manga" || choice === "paddle" ? choice : pick(sel.w, sel.h);
        run(frozen, [Math.round(sel.x * scale), Math.round(sel.y * scale), Math.round(sel.w * scale), Math.round(sel.h * scale)],
            e, { sel: sel, scale: scale });
    }
    // remember a region by numbers (logical pixels), e.g. a game's dialogue box for `again`
    function setRegion(x, y, w, h) {
        lastRegion = { x: x, y: y, w: Math.max(1, w), h: Math.max(1, h) };
        _saveStore();
    }
    function clearHistory() {
        history = [];
        result = null;
        if (phase === "done" || phase === "error")
            phase = "idle";
        _saveStore();
    }
    function cancel() {
        if (phase === "selecting" || phase === "capturing")
            phase = "idle";
    }
    // closes the result card; leaves a snip in progress alone
    function dismiss() {
        if (phase === "done" || phase === "error")
            phase = "idle";
    }
    // the same crop through the other engine
    function rerun(engine) {
        if (current && !busy)
            run(current.path, current.rect, engine, current.meta);
    }
    function warm(engine) {
        const e = engine === "manga" ? "manga" : "paddle";
        _makeRoom(e);
        if (!procOf(e).running)
            procOf(e).running = true;
        idleTimer.restart();
    }
    function stopEngines() {
        ["manga", "paddle"].forEach(e => _quit(e));
    }

    // ---- running an engine ----
    function run(path, rect, engine, meta) {
        const e = engine === "manga" ? "manga" : "paddle";
        current = { id: ++_seq, path: path, rect: rect, engine: e, meta: meta || {} };
        result = null;
        errorText = "";
        hookerSent = false;
        idleTimer.restart();
        if (readyOf(e)) {
            phase = "running";
            _write(e, current);
        } else {
            phase = "warming";
            _pending = current;
            _makeRoom(e);
            if (!procOf(e).running)
                procOf(e).running = true;
        }
    }
    // Both models together hold about 3.5 GB of RAM. With little memory free, only one engine stays
    // loaded: starting one quits the other (when it isn't busy), and switching reloads it
    property int lowMemoryKb: 6 * 1024 * 1024
    function _freeKb() {
        meminfo.reload();
        const m = String(meminfo.text()).match(/MemAvailable:\s+(\d+)/);
        return m ? Number(m[1]) : 1e9;
    }
    function _makeRoom(e) {
        const other = e === "manga" ? "paddle" : "manga";
        if (other === "paddle" && detecting)
            return;
        if (procOf(other).running && !procOf(e).running && _freeKb() < lowMemoryKb)
            _quit(other);
    }
    FileView {
        id: meminfo
        path: "/proc/meminfo"
        blockLoading: true
        printErrors: false
    }
    // ---- finding text blocks (the general engine) ----
    // the overlay asks for it (B / D); a snip asks for it by itself only when it costs no engine swap
    function detect() {
        if (detecting || frozen === "")
            return;
        _requestDetect(frozen);
    }
    function _requestDetect(path) {
        blocks = [];
        detecting = true;
        _detectId = ++_seq;
        const req = { id: _detectId, path: path, detect: true };
        idleTimer.restart();
        if (paddleReady) {
            paddleProc.write(JSON.stringify(req) + "\n");
        } else {
            _detectPending = req;
            _makeRoom("paddle");
            if (!paddleProc.running)
                paddleProc.running = true;
        }
    }
    // capture pixels -> logical pixels, and the block list for the overlay
    function _gotBlocks(o) {
        detecting = false;
        const m = Hyprland.focusedMonitor;
        const logicalW = m ? m.width / (m.scale || 1) : (o.size ? o.size[0] : 1);
        const k = o.size && logicalW > 0 ? o.size[0] / logicalW : 1;
        blocks = (o.blocks || []).map(b => ({ x: b.x / k, y: b.y / k, w: b.w / k, h: b.h / k, text: b.text, lines: b.lines,
                                              conf: b.conf, score: b.score, dialogue: b.dialogue, k: k }));
        if (_dialogueMode)
            _pickDialogue(o.ms || 0);
    }
    function _iou(a, b) {
        const w = Math.max(0, Math.min(a.x + a.w, b.x + b.w) - Math.max(a.x, b.x));
        const h = Math.max(0, Math.min(a.y + a.h, b.y + b.h) - Math.max(a.y, b.y));
        const inter = w * h;
        return inter / Math.max(1, a.w * a.h + b.w * b.h - inter);
    }
    function _pickDialogue(ms) {
        _dialogueMode = false;
        if (blocks.length === 0) {
            _fail("No text blocks found on the screen.");
            return;
        }
        let best = null, bestScore = -1, matched = false;
        blocks.forEach(b => {
            const iou = windowRegion ? _iou(b, windowRegion) : 0;
            const sc = b.score + iou;
            if (sc > bestScore) {
                best = b;
                bestScore = sc;
                matched = iou > 0.3;
            }
        });
        if (!best || (!matched && !best.dialogue)) {
            _fail("No dialogue box found. Select it once with a snip and it is remembered for this window.");
            return;
        }
        if (current)
            current.rect = [Math.round(best.x * best.k), Math.round(best.y * best.k), Math.round(best.w * best.k), Math.round(best.h * best.k)];
        if (current)
            current.meta = { sel: { x: best.x, y: best.y, w: best.w, h: best.h }, scale: best.k };
        // a guess is not remembered (it would stick); a block that matched the remembered box refreshes it
        if (matched) {
            lastRegion = { x: best.x, y: best.y, w: best.w, h: best.h };
            _remember(windowKey, lastRegion);
            _saveStore();
        }
        _finish({ text: best.text, engine: "paddle", ms: ms });
    }

    // test hooks: show a card with the given text / error without running an engine
    property bool historyOpen: false

    function demo(text) {
        current = { id: 0, path: "", rect: null, engine: "manga", meta: {} };
        result = { text: text, engine: "manga", ms: 123, ts: Date.now() };
        hookerSent = true;
        phase = "done";
    }
    function demoError(text) {
        current = { id: 0, path: "", rect: null, engine: "paddle", meta: {} };
        _fail(text);
    }

    function _write(e, req) {
        procOf(e).write(JSON.stringify({ id: req.id, path: req.path, rect: req.rect }) + "\n");
    }
    function _setReady(e, v, device) {
        if (e === "manga") {
            mangaReady = v;
            mangaDevice = device || "";
        } else {
            paddleReady = v;
            paddleDevice = device || "";
        }
    }
    function _fail(message) {
        errorText = message;
        phase = "error";
    }
    function _onLine(e, line) {
        let o;
        try {
            o = JSON.parse(line);
        } catch (x) {
            return;
        }
        if (o.ready !== undefined) {
            if (o.ready) {
                _setReady(e, true, o.device);
                if (e === "manga")
                    mangaModel = o.model || "";
                if (e === "paddle" && _detectPending) {
                    const dreq = _detectPending;
                    _detectPending = null;
                    paddleProc.write(JSON.stringify(dreq) + "\n");
                    if (phase === "warming" && _dialogueMode)
                        phase = "running";
                }
                if (_pending && _pending.engine === e) {
                    const req = _pending;
                    _pending = null;
                    phase = "running";
                    _write(e, req);
                }
            } else {
                _pending = null;
                _detectPending = null;
                detecting = false;
                _dialogueMode = false;
                _fail(engineLabel(e) + " could not start: " + (o.error || "unknown error"));
            }
            return;
        }
        if (o.id === _detectId) {
            idleTimer.restart();
            if (o.error) {
                detecting = false;
                const wasDialogue = _dialogueMode;
                _dialogueMode = false;
                if (wasDialogue)
                    _fail(o.error);
                return;
            }
            _gotBlocks(o);
            return;
        }
        if (!current || o.id !== current.id)
            return;
        idleTimer.restart();
        if (o.error) {
            _fail(o.error);
            return;
        }
        _finish(o);
    }
    function _finish(o) {
        const text = String(o.text || "").trim();
        result = { text: text, engine: o.engine, ms: o.ms, ts: Date.now() };
        phase = "done";
        if (text === "")
            return;
        copyText(text);
        _hooker(text);
        history = [{ text: text, engine: o.engine, ts: Date.now(), ms: o.ms }].concat(history).slice(0, 30);
        _saveStore();
        if (toast)
            toast.showToast("Copied · " + text.length + (text.length === 1 ? " character" : " characters"));
    }
    function copyText(text) {
        Quickshell.execDetached(["wl-copy", "--", text]);
    }
    // ---- Texthooker UI relay ----
    // scripts/texthook_ws.py runs as a detached background daemon (started here, but it outlives
    // reloads and restarts of the shell, so the Texthooker tab keeps its connection). Lines go to it
    // over a Unix socket; results that arrive while it is unreachable wait here and are sent on connect.
    readonly property string relayPath: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/qs-texthook.sock"
    readonly property bool relayUp: relay.connected
    property var _relayQueue: []
    property real _relayStarted: 0
    function _hooker(text) {
        hookerSent = true;
        const line = text.replace(/\n/g, "\\n") + "\n";
        if (relay.connected) {
            relay.write(line);
            relay.flush();
        } else {
            _relayQueue = _relayQueue.concat([line]).slice(-20);
            _ensureRelay();
        }
    }
    // a no-op when one is already running (the daemon checks); at most one launch per 10 s
    function _ensureRelay() {
        if (Date.now() - _relayStarted < 10000)
            return;
        _relayStarted = Date.now();
        Quickshell.execDetached(["python3", "-I", Quickshell.shellDir + "/scripts/texthook_ws.py", "--socket", relayPath]);
    }

    // ---- engines go away after a while ----
    function _quit(e) {
        const p = procOf(e);
        if (!p.running)
            return;
        const q = Object.assign({}, _quitting);
        q[e] = true;
        _quitting = q;
        p.write(JSON.stringify({ quit: true }) + "\n");
    }
    Timer {
        id: idleTimer
        interval: ocr.idleSeconds * 1000
        onTriggered: {
            if (ocr.phase === "warming" || ocr.phase === "running" || ocr.detecting) {
                restart();
                return;
            }
            ocr.stopEngines();
        }
    }

    function _onExit(e, code) {
        const wasQuit = !!_quitting[e];
        const q = Object.assign({}, _quitting);
        delete q[e];
        _quitting = q;
        _setReady(e, false, "");
        if (e === "paddle" && detecting && !wasQuit) {
            detecting = false;
            _detectPending = null;
            if (_dialogueMode) {
                _dialogueMode = false;
                _fail(engineLabel(e) + " stopped unexpectedly (exit " + code + ")");
            }
        }
        if (!wasQuit && (phase === "warming" || phase === "running") && current && current.engine === e) {
            _pending = null;
            _fail(engineLabel(e) + " stopped unexpectedly (exit " + code + ")");
        }
    }

    Process {
        id: mangaProc
        command: [ocr.venvPython.manga, Quickshell.shellDir + "/scripts/ocr_server.py", "--engine", "manga"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => ocr._onLine("manga", line) }
        onExited: code => ocr._onExit("manga", code)
    }
    Process {
        id: paddleProc
        command: [ocr.venvPython.paddle, Quickshell.shellDir + "/scripts/ocr_server.py", "--engine", "paddle"]
        stdinEnabled: true
        stdout: SplitParser { onRead: line => ocr._onLine("paddle", line) }
        onExited: code => ocr._onExit("paddle", code)
    }
    Socket {
        id: relay
        path: ocr.relayPath
        onConnectedChanged: {
            if (connected) {
                ocr._relayQueue.forEach(l => relay.write(l));
                relay.flush();
                ocr._relayQueue = [];
            }
        }
    }
    // keep the daemon running and the connection up (also reconnects after the daemon was killed)
    Timer {
        interval: 3000
        running: !relay.connected
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            ocr._ensureRelay();
            relay.connected = true;
        }
    }

    // ---- capturing ----
    function _dropFrozen() {
        if (frozen !== "")
            Quickshell.execDetached(["rm", "-f", frozen]);
    }
    function _capture(next) {
        _dropFrozen();
        const m = Hyprland.focusedMonitor;
        monitor = m ? m.name : "";
        frozen = runDir + "/qs-ocr-frozen-" + Date.now() + ".png";
        grab.mode = next;
        grab.command = monitor !== "" ? ["grim", "-o", monitor, frozen] : ["grim", frozen];
        phase = "capturing";
        grab.running = true;
    }
    Process {
        id: grab
        property string mode: "selecting"
        onExited: code => {
            if (ocr.phase !== "capturing")
                return;
            if (code !== 0) {
                ocr._fail(mode === "clipboard" ? "There is no image on the clipboard." : "Could not capture the screen (grim failed).");
                return;
            }
            if (mode === "selecting") {
                ocr.phase = "selecting";
                // the general engine finds the text blocks; when it is not loaded and the context
                // wants manga_ocr, that waits until the overlay asks (B / D)
                if (ocr.pick(0, 0) === "paddle" || ocr.paddleReady)
                    ocr.detect();
            } else if (mode === "dialogue") {
                ocr.current = { id: ++ocr._seq, path: ocr.frozen, rect: null, engine: "paddle", meta: {} };
                ocr.result = null;
                ocr.errorText = "";
                ocr.hookerSent = false;
                ocr.phase = ocr.paddleReady ? "running" : "warming";
                ocr._requestDetect(ocr.frozen);
            } else if (mode === "again") {
                const r = ocr.windowRegion ? ocr.windowRegion : ocr.lastRegion;
                const s = Hyprland.focusedMonitor ? (Hyprland.focusedMonitor.scale || 1) : 1;
                ocr.run(ocr.frozen, [Math.round(r.x * s), Math.round(r.y * s), Math.round(r.w * s), Math.round(r.h * s)],
                        ocr.pick(r.w, r.h), { sel: r, scale: s });
            } else {
                ocr.run(ocr.frozen, null, ocr.pick(0, 0), { scale: 1 });
            }
        }
    }

    // ---- persistence ----
    function _saveStore() {
        adapter.history = history;
        adapter.lastRegion = lastRegion ? lastRegion : ({});
        adapter.regions = regions;
        store.writeAdapter();
    }
    FileView {
        id: store
        path: ocr.stateDir + "/ocr.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            ocr.history = adapter.history || [];
            const r = adapter.lastRegion;
            ocr.lastRegion = r && r.w > 0 ? r : null;
            ocr.regions = adapter.regions || ({});
        }
        JsonAdapter {
            id: adapter
            property var history: []
            property var lastRegion: ({})
            property var regions: ({})
        }
    }
}
