pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.Services

// Interactive subtitles: scripts/lexicon.py cuts the current mpv subtitle line into words, looks them
// up through the Yomitan API (LibreWolf must be running for definitions) and gives each a status from the
// known-words store (Anki + manual marks). SubOverlay draws `line`; the popup asks `define`.
//
// The helper runs while mpv is connected and quits when it is gone. Requests made before its "ready"
// line wait in _pending.
Singleton {
    id: lex

    readonly property string home: Quickshell.env("HOME")
    readonly property string python: home + "/.venv/bin/python"
    // the user's switch (Alt+s); the overlay also needs mpv to be fullscreen
    property bool enabled: true
    readonly property bool wanted: enabled && Mpv.connected && Mpv.hasFile
    // the focused window is mpv: tabbing away takes the overlay down and gives mpv's own line back
    readonly property var activeWin: ToplevelManager.activeToplevel
    // Hyprland's view of the focused window: its pid tells which mpv it is (the shell's link is on one of them)
    readonly property var hyprWin: Hyprland.activeToplevel
    readonly property int focusedPid: Number(hyprWin && hyprWin.lastIpcObject ? hyprWin.lastIpcObject.pid : 0) || 0
    readonly property bool mpvFocused: !!activeWin && activeWin.appId === "mpv" && (Mpv.pid || 0) > 0 && focusedPid === Mpv.pid
    // lastIpcObject only fills on a refresh
    Timer {
        id: pidRefresh
        interval: 100
        onTriggered: Hyprland.refreshToplevels()
    }
    Connections {
        target: lex
        function onActiveWinChanged() { pidRefresh.restart(); }
    }
    Connections {
        target: Mpv
        function onPidChanged() { pidRefresh.restart(); }
    }
    // tests drive a windowed mpv: QS_LEXICON_WINDOWED=1 drops the fullscreen requirement
    readonly property bool windowedOk: Quickshell.env("QS_LEXICON_WINDOWED") === "1"
    // overlay and mpv's own subs swap places only when this is true
    // the Words page is showing (it has a search box): our layer can take the keyboard on a click, and then the
    // focused window is no longer mpv, so the overlay must not switch off
    property bool panelSearch: false
    // some other window took focus (a layer surface of ours holding the keyboard reports no window at all)
    readonly property bool otherFocused: activeWin !== null && activeWin !== undefined && activeWin.appId !== "mpv"
    readonly property bool overlayOn: wanted && ready && (mpvFocused || (panelSearch && !otherFocused)) && (Mpv.fullscreen || windowedOk)

    // readings over the kanji of the line: unknown (words being learned), all, off. Alt+f cycles; remembered.
    property string furigana: "unknown"
    function cycleFurigana() {
        furigana = furigana === "unknown" ? "all" : furigana === "all" ? "off" : "unknown";
        prefs.writeAdapter();
    }
    FileView {
        id: prefs
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/lexicon-prefs.json"
        printErrors: false
        blockLoading: true
        atomicWrites: true
        onLoaded: {
            if (["unknown", "all", "off"].indexOf(adapter.furigana) >= 0)
                lex.furigana = adapter.furigana;
            lex.reviewPause = adapter.reviewPause === true;
        }
        JsonAdapter {
            id: adapter
            property string furigana: lex.furigana
            property bool reviewPause: lex.reviewPause
        }
    }

    // pause at the end of a line holding a word that is due today or a leech (Alt+r); remembered
    property bool reviewPause: false
    function setReviewPause(on) {
        reviewPause = on;
        prefs.writeAdapter();
        if (on)
            _armReview();
        else
            Mpv.send(["script-message", "lexicon-pause-at", "0"]);
    }
    // a line that is on screen with such a word tells the mpv script when it ends; the script does the pausing,
    // so it lands on the frame even when the shell is busy
    function _armReview() {
        if (!reviewPause || !overlayOn || Mpv.paused || !Mpv.subLive || Mpv.subEnd <= Mpv.position + 0.15)
            return;
        for (const row of rows)
            for (const t of row)
                if (t.k === "word" && statusOf(t) === "learning" && (t.due === true || t.leech === true)) {
                    Mpv.send(["script-message", "lexicon-pause-at", String(Mpv.subEnd)]);
                    return;
                }
    }

    // known and learning shares of a subtitle file (0..1), or null before the helper has read it
    function comprehensionParts(path) {
        if (!path || statsFor !== path || !stats.tokens)
            return null;
        return { known: stats.pct / 100, learning: (stats.learnPct || 0) / 100 };
    }

    // "79% known · 204 new" for a subtitle file once the helper has read it, else ""
    function comprehension(path) {
        if (!path || statsFor !== path || !stats.tokens)
            return "";
        return Math.round(stats.pct) + "% known · " + stats.newWords + " new";
    }

    property bool ready: false
    property bool yomitanUp: false
    property int knownWords: 0
    // [[token]] for the current line, one array per subtitle row; token: { s, k, term, reading, status, freq, key }
    property var rows: []
    // the line the rows belong to (so a late answer for an older line is dropped)
    property string rowsFor: ""
    // comprehension of the subtitle file: { lines, tokens, known, unknown, pct, newWords, plusOne }
    property var stats: ({})
    property string statsFor: ""

    property int _seq: 0
    property var _cb: ({})
    property var _pending: []

    // ---- requests ----
    function request(req, done) {
        req.id = ++_seq;
        if (done)
            _cb[req.id] = done;
        if (!ready) {
            _pending.push(req);
            return;
        }
        proc.write(JSON.stringify(req) + "\n");
    }

    // what the screen shows for a word: marks made this session count at once, before the helper has answered
    property var overrides: ({})
    property int rev: 0
    function statusOf(tok) {
        rev;
        if (tok && (tok.status === "name" || tok.status === "none"))
            return tok.status;
        return (tok && overrides[tok.term]) || (tok && termStatus[tok.term]) || (tok && tok.status) || "unknown";
    }
    // what the helper last said about each word shown (line or transcript): a card or underline holding an older
    // token reads the newest status instead of the one it was cut with
    property var termStatus: ({})
    function _index(rows) {
        const o = Object.assign({}, termStatus);
        for (const row of rows)
            for (const t of (row.toks || row))
                if (t.k === "word" && t.term)
                    o[t.term] = t.status;
        termStatus = o;
    }
    function _override(term, status) {
        const o = Object.assign({}, overrides);
        if (status === "")
            delete o[term];
        else
            o[term] = status;
        overrides = o;
        rev++;
    }
    function mark(token, status) {
        if (!token || !token.term)
            return;
        _override(token.term, status === "clear" ? "unknown" : status);
        request({ op: "mark", term: token.term, reading: token.reading || "", rank: token.rank || 0, status: status }, r => {
            if (!r.error)
                lex._override(token.term, r.status);
            lex.refreshLine();
            statsDebounce.restart();
            if (lex.panelOpen)
                lex.loadLearning();
        });
    }

    // ---- names and wrong cuts: rules kept by the helper, applied to every line from then on ----
    function _reparse(surface) {
        for (const k of Object.keys(_defs))
            if (k.indexOf("|" + surface) >= 0)
                delete _defs[k];
        refreshLine();
        loadTranscript(true);
    }
    // flag: 1 it is a name, 0 it is not, "clear" back to what the dictionary says
    function setName(tok, flag, done) {
        if (!tok)
            return;
        request({ op: "name", surface: tok.s, flag: flag }, r => {
            if (!r.error)
                lex._reparse(tok.s);
            if (done)
                done(r);
        });
    }
    // which dictionary entry a word means (term "" clears the choice, back to what unidic's context suggests)
    function setPick(tok, term, reading, done) {
        if (!tok)
            return;
        request({ op: "pick", surface: tok.s, base: tok.base || tok.s, term: term, reading: reading }, r => {
            if (!r.error)
                lex._reparse(tok.s);
            if (done)
                done(r);
        });
    }

    // Jisho in its own LibreWolf window (profile + app_id qs-lookup, floated by a Hyprland rule); mpv stays paused
    // while it is read, and the lexicon-hold flag keeps ModernX's OSC from popping on that pause
    function lookupOnline(tok) {
        if (!tok)
            return;
        const word = tok.term || tok.s;
        if (!Mpv.paused) {
            Mpv.send(["set_property", "user-data/lexicon-hold", true]);
            Mpv.send(["set_property", "pause", true]);
            holdFlag.restart();
        }
        const dir = (Quickshell.env("XDG_STATE_HOME") || (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/lookup-profile";
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$1" && exec librewolf --class qs-lookup --name qs-lookup --profile "$1" --new-window "$2"',
            "sh", dir, "https://jisho.org/search/" + encodeURIComponent(word)]);
    }

    // span: the text of the run being re-cut; parts: the pieces it should become
    function setCut(span, parts, done) {
        request({ op: "cut", span: span, parts: parts }, r => {
            if (!r.error)
                lex._reparse(span);
            if (done)
                done(r);
        });
    }

    // ---- mining ----
    // The helper adds the word the way Yomitan's card format would (lexicon.py `mine`), taking in the lines
    // before / after that the sentence runs into, then cuts the sentence's audio and the line's picture with
    // ffmpeg (`capture`) using mpvacious's subs2srs.conf settings. mpv is never seeked or paused for it.
    // State per term: adding | finishing | done | partial | dup | error:<code>; mineLines is how many lines the card holds.
    property var mineState: ({})
    property var mineLines: ({})
    // the lines the user chose for a word's sentence in one cue (key term|start), [first, last] cue indexes; unset means what mining picks itself
    property var mineSpan: ({})
    property var _mineJobs: ({})
    property var _spanCache: ({})
    // the cue under the word and its neighbours (op span), cached per word and cue
    function spanOf(tok, ctx, done) {
        // a manga bubble: the bubbles of its page, in reading order, stand in for the subtitle cues
        if (tok && ctx && ctx.kind === "manga" && ctx.mline >= 0) {
            const lo = Math.max(0, ctx.mline - 4), hi = Math.min(ctx.mlines.length - 1, ctx.mline + 4);
            done({ line: ctx.mline, auto: [ctx.mline, ctx.mline], lines: ctx.mlines.slice(lo, hi + 1).map((t, k) => ({ i: lo + k, text: t })) });
            return;
        }
        const path = subPath();
        if (!tok || !ctx || ctx.start === undefined || ctx.start < 0 || path === "") {
            done(null);
            return;
        }
        const key = tok.term + "|" + ctx.start;
        if (_spanCache[key]) {
            done(_spanCache[key]);
            return;
        }
        request({ op: "span", path: path, start: ctx.start }, r => {
            if (r.error || r.line === undefined || r.line < 0) {
                done(null);
                return;
            }
            lex._spanCache[key] = r;
            done(r);
        });
    }
    // the user changed the lines: remembered for Mine, or, for a card already mined, written to the note after a pause
    property var _respanArgs: null
    function spanKey(tok, ctx) {
        if (ctx && ctx.kind === "manga")
            return tok.term + "|m" + ctx.vol + "|" + ctx.idx + "|" + ctx.bi;
        return tok.term + "|" + (ctx ? ctx.start : -1);
    }
    function setSpan(tok, ctx, span) {
        if (!tok || !tok.term)
            return;
        const m = Object.assign({}, mineSpan);
        m[spanKey(tok, ctx)] = span;
        mineSpan = m;
        const st = mineState[tok.term] || "";
        if (mineNote[tok.term] && (st === "done" || st === "partial")) {
            _respanArgs = { tok: tok, ctx: ctx || {} };
            respanTimer.restart();
        }
    }
    Timer {
        id: respanTimer
        interval: 600
        onTriggered: {
            const a = lex._respanArgs;
            lex._respanArgs = null;
            if (!a)
                return;
            const st = lex.mineState[a.tok.term] || "";
            if (st === "adding" || st === "finishing") {
                lex._respanArgs = a;
                restart();
                return;
            }
            lex._setMine(a.tok.term, "finishing");
            lex._mineQ.push({ kind: "respan", tok: a.tok, ctx: a.ctx, span: lex.mineSpan[lex.spanKey(a.tok, a.ctx)], path: lex.subPath(), video: Mpv.path });
            lex._mineNext();
        }
    }
    property var mineNote: ({})
    // open the card in Anki's browser
    function browse(tok) {
        const id = tok ? mineNote[tok.term] : 0;
        if (id)
            request({ op: "browse", noteId: id }, () => {});
    }
    function browseNote(id) {
        if (id)
            request({ op: "browse", noteId: id }, () => {});
    }
    property var focusTok: null
    property var focusCtx: null
    property var _mineQ: []
    property bool _mineBusy: false
    function _setMine(term, st) {
        const o = Object.assign({}, mineState);
        o[term] = st;
        mineState = o;
    }
    // replace: overwrite the card already mined for the word instead of adding a second one
    function mine(tok, ctx, replace) {
        if (!tok || !tok.term)
            return;
        const st = mineState[tok.term] || "";
        if (st === "adding" || st === "finishing")
            return;
        _setMine(tok.term, "adding");
        _mineQ.push({ tok: tok, ctx: ctx || {}, force: !!replace, replace: replace ? (mineNote[tok.term] || 0) : 0, path: subPath(), video: Mpv.path, span: mineSpan[spanKey(tok, ctx)] });
        _mineNext();
    }
    function _mineNext() {
        if (_mineBusy || _mineQ.length === 0)
            return;
        _mineBusy = true;
        const job = _mineQ.shift();
        const tok = job.tok;
        const end = (st) => { lex._setMine(tok.term, st); lex._mineBusy = false; lex._mineNext(); };
        if (job.ctx && job.ctx.kind === "manga") {
            lex._mangaMine(job, end);
            return;
        }
        if (job.kind === "respan") {
            request({ op: "respan", noteId: lex.mineNote[tok.term], term: tok.term, reading: tok.reading || "", surface: tok.s,
                      prefix: job.ctx.prefix || "", body: tok.s, suffix: job.ctx.suffix || "", path: job.path,
                      start: job.ctx.start === undefined ? -1 : job.ctx.start, span: job.span }, r => {
                if (r.error) {
                    end("partial");
                    return;
                }
                const m = Object.assign({}, lex.mineLines);
                m[tok.term] = r.lines || 1;
                lex.mineLines = m;
                lex.request({ op: "capture", noteId: r.noteId, path: job.path, video: job.video, span: r.span, line: r.line }, c => end(c.done ? "done" : "partial"));
            });
            return;
        }
        request({ op: "mine", term: tok.term, reading: tok.reading || "", surface: tok.s, force: job.force, replace: job.replace,
                  prefix: job.ctx.prefix || "", body: tok.s, suffix: job.ctx.suffix || "",
                  path: job.path, start: job.ctx.start === undefined ? -1 : job.ctx.start, span: job.span }, r => {
            if (r.error) {
                end("error:" + r.error.split(":")[0]);
            } else if (r.dup) {
                if (r.noteId) { const n = Object.assign({}, lex.mineNote); n[tok.term] = r.noteId; lex.mineNote = n; }
                end("dup");
            } else {
                const m = Object.assign({}, lex.mineLines);
                m[tok.term] = r.lines || 1;
                lex.mineLines = m;
                const n = Object.assign({}, lex.mineNote);
                n[tok.term] = r.noteId;
                lex.mineNote = n;
                lex._setMine(tok.term, "finishing");
                lex._override(tok.term, "learning");
                lex.request({ op: "capture", noteId: r.noteId, path: job.path, video: job.video, span: r.span, line: r.line }, c => {
                    end(c.done ? "done" : "partial");
                    lex.sync();
                });
            }
        });
    }

    // a word of a manga bubble: the sentence is the bubbles of the span (no video, so no start/path), the picture
    // is the panel around them cut from the page. A span changed after mining rewrites the same note.
    function _mangaMine(job, end) {
        const tok = job.tok, ctx = job.ctx, respan = job.kind === "respan";
        const sp = job.span || [ctx.mline, ctx.mline];
        const a = Math.max(0, Math.min(ctx.mline, sp[0])), b = Math.min(ctx.mlines.length - 1, Math.max(ctx.mline, sp[1]));
        const prefix = ctx.mlines.slice(a, ctx.mline).join("") + (ctx.prefix || "");
        const suffix = (ctx.suffix || "") + ctx.mlines.slice(ctx.mline + 1, b + 1).join("");
        const r = [1e9, 1e9, -1, -1];
        for (let k = a; k <= b; k++) {
            const bx = ctx.mboxes[k];
            r[0] = Math.min(r[0], bx[0]); r[1] = Math.min(r[1], bx[1]); r[2] = Math.max(r[2], bx[2]); r[3] = Math.max(r[3], bx[3]);
        }
        const picture = (noteId, after) => request({ op: "capture_image", noteId: noteId, image: ctx.mpath, rect: r, pw: ctx.mw, ph: ctx.mh,
                                                      title: ctx.mtitle, page: ctx.mpage }, c => after(c));
        const lines = b - a + 1;
        const keepLines = () => { const m = Object.assign({}, lex.mineLines); m[tok.term] = lines; lex.mineLines = m; };
        request({ op: "mine", term: tok.term, reading: tok.reading || "", surface: tok.s, force: job.force,
                  replace: respan ? (mineNote[tok.term] || 0) : job.replace, prefix: prefix, body: tok.s, suffix: suffix,
                  path: "", start: -1 }, m => {
            if (m.error) {
                end(respan ? "partial" : "error:" + m.error.split(":")[0]);
            } else if (m.dup) {
                if (m.noteId) { const n = Object.assign({}, lex.mineNote); n[tok.term] = m.noteId; lex.mineNote = n; }
                end("dup");
            } else {
                keepLines();
                const n = Object.assign({}, lex.mineNote);
                n[tok.term] = m.noteId;
                lex.mineNote = n;
                if (!respan) {
                    lex._setMine(tok.term, "finishing");
                    lex._override(tok.term, "learning");
                }
                picture(m.noteId, c => {
                    end(c.done ? "done" : "partial");
                    if (!respan)
                        lex.sync();
                });
            }
        });
    }

    // dictionary entries, newest 200 kept; failures are not remembered (LibreWolf may be opened a moment later)
    property var _defs: ({})
    property var _defOrder: []
    function define(token, done) {
        const key = token.term + "|" + (token.reading || "") + "|" + token.s;
        const hit = _defs[key];
        if (hit) {
            done(hit);
            return;
        }
        request({ op: "define", term: token.term, reading: token.reading || "", surface: token.s }, r => {
            if (!r.error) {
                lex._defs[key] = r;
                lex._defOrder.push(key);
                if (lex._defOrder.length > 200)
                    delete lex._defs[lex._defOrder.shift()];
            }
            done(r);
        });
    }
    // kanji entries (KANJIDIC + JPDB Kanji, merged by the helper) for the card's kanji viewer; the data never changes
    property var _kanji: ({})
    function kanji(ch, done) {
        const hit = _kanji[ch];
        if (hit !== undefined) {
            done(hit ? { kanji: hit } : { error: "none" });
            return;
        }
        request({ op: "kanji", chars: [ch] }, r => {
            if (r.error) {
                done(r);
                return;
            }
            const k = r.kanji && r.kanji[0];
            lex._kanji[ch] = k || null;
            done(k ? { kanji: k } : { error: "none" });
        });
    }
    // Anki can change behind our back (a card deleted, suspended, matured): the word under the card is asked about
    // again each time it opens, and the whole deck is re-read now and then while the overlay is up
    function recheck(tok) {
        if (!ready || !tok || !tok.term || tok.status === "name" || tok.status === "none")
            return;
        const term = tok.term;
        request({ op: "recheck", term: term, reading: tok.reading || "", rank: tok.rank || 0 }, r => {
            if (r.error || !r.changed)
                return;
            lex._override(term, r.status);
            if (!r.noteId) {
                const m = Object.assign({}, lex.mineState);
                delete m[term];
                lex.mineState = m;
                const n = Object.assign({}, lex.mineNote);
                delete n[term];
                lex.mineNote = n;
            }
            lex.refreshLine();
            if (lex.panelOpen)
                lex.loadTranscript(true);
            statsDebounce.restart();
        });
    }
    Timer {
        interval: 300000
        repeat: true
        running: lex.overlayOn
        onTriggered: lex.sync()
    }
    function sync() {
        request({ op: "sync" }, r => {
            if (!r.error) {
                lex.knownWords = (r.known || 0) + (r.learning || 0);
                lex.rev++;
                lex.refreshStats();
                lex.loadTranscript(true);
                if (lex.panelOpen)
                    lex.loadLearning();
            }
            // the overrides stand in until the line has been cut again with the new statuses, so a word just mined
            // does not fall back to unknown meanwhile
            lex.refreshLine(() => { lex.overrides = ({}); lex.rev++; });
        });
    }

    // ---- the OCR card: its text is cut into words and looked up like a subtitle, without marks or mining ----
    // the helper is started for it when no video is open and left running for ten minutes after the last use
    property bool ocrKeep: false
    Timer {
        id: ocrKeepTimer
        interval: 600000
        onTriggered: lex.ocrKeep = false
    }
    function segmentText(text, done) {
        ocrKeep = true;
        ocrKeepTimer.restart();
        request({ op: "segment", lines: text.split("\n").map(s => s.trim()).filter(s => s !== "") }, r => done(r.error ? [] : r.lines));
    }

    // known / learning shares of some text (a manga volume's bubbles): { tokens, pct, learnPct, newWords }
    function textStats(texts, done) {
        ocrKeep = true;
        ocrKeepTimer.restart();
        request({ op: "text_stats", texts: texts }, done);
    }

    // the line on screen, cut into words
    function refreshLine(done) {
        const text = Mpv.subRaw;
        if (text === "") {
            rows = [];
            rowsFor = "";
            if (done)
                done();
            return;
        }
        const lines = text.split("\n").map(s => s.trim()).filter(s => s !== "");
        request({ op: "segment", lines: lines }, r => {
            if (r.error || text !== Mpv.subRaw) {
                if (done)
                    done();
                return;
            }
            lex._index(r.lines);
            lex.rows = r.lines;
            lex.rowsFor = text;
            lex._armReview();
            if (done)
                done();
        });
    }

    // the external .srt mpv has loaded, else the one Jimaku saves next to the video: <stem>.ja.srt
    function subPath() {
        if (/\.srt$/i.test(Mpv.subFile))
            return Mpv.subFile;
        const p = Mpv.path;
        if (!p || /^[a-z]+:\/\//i.test(p))
            return "";
        return p.replace(/\.[^./]+$/, "") + ".ja.srt";
    }
    function refreshStats() {
        const sp = subPath();
        if (sp === "") {
            stats = {};
            statsFor = "";
            return;
        }
        request({ op: "parse_file", path: sp }, r => {
            lex.stats = r.error ? ({}) : r;
            lex.statsFor = sp;
        });
    }

    // ---- every word being learned, for the panel's Words page: { term, reading, ivl, lapses, due, leech, note, source, here } ----
    property var learningList: []
    // the user's own known / unknown / ignored marks, newest first: { term, reading, status, updated, ivl, lapses, due, leech, note, anki, here }
    property var markedList: []
    property bool learningBusy: false
    function loadLearning() {
        if (!ready)
            return;
        learningBusy = true;
        request({ op: "learning", path: subPath() }, r => {
            lex.learningBusy = false;
            if (!r.error) {
                lex.learningList = r.words;
                lex.markedList = r.marks || [];
            }
        });
    }

    // ---- transcript: every line of the subtitle file, for the side panel ----
    property var transcript: []
    property string transcriptFor: ""
    property bool transcriptBusy: false
    function loadTranscript(force) {
        const sp = subPath();
        if (sp === "" || !ready) {
            transcript = [];
            transcriptFor = "";
            return;
        }
        if (!force && transcriptFor === sp)
            return;
        transcriptBusy = true;
        request({ op: "transcript", path: sp }, r => {
            lex.transcriptBusy = false;
            if (r.error || sp !== lex.subPath()) {
                if (r.error)
                    lex.transcript = [];
                return;
            }
            lex._index(r.lines);
            lex.transcript = r.lines;
            lex.transcriptFor = sp;
            lex.stats = r.stats;
            lex.statsFor = sp;
        });
    }
    // the last line that has started, by the playback clock (the file's times shifted by sub-delay)
    readonly property int currentIndex: {
        const t = Mpv.position - Mpv.subDelay + 0.05;
        const a = transcript;
        let lo = 0, hi = a.length - 1, best = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (a[mid].start <= t) {
                best = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return best;
    }

    // the side panel: opened by the right screen edge (SubOverlay) or Alt+t, which pins it
    property bool panelOpen: false
    property bool panelPinned: false
    onPanelOpenChanged: {
        if (panelOpen) {
            loadTranscript(false);
            loadLearning();
        }
    }
    function togglePanel() {
        panelPinned = !panelPinned;
        panelOpen = panelPinned;
    }

    // hovering a word of the live line pauses; letting go resumes, but only a pause we made ourselves
    property bool _ourPause: false
    function holdPause() {
        if (_ourPause || Mpv.paused)
            return;
        _ourPause = true;
        // ModernX shows its OSC on every pause; this flag (read by scripts/modernx-lower-hover.py's patch) tells it this one is ours
        Mpv.send(["set_property", "user-data/lexicon-hold", true]);
        Mpv.send(["set_property", "pause", true]);
        holdFlag.restart();
    }
    Timer {
        id: holdFlag
        interval: 400
        onTriggered: Mpv.send(["set_property", "user-data/lexicon-hold", false])
    }
    function releasePause() {
        if (!_ourPause)
            return;
        _ourPause = false;
        if (Mpv.paused)
            Mpv.send(["set_property", "pause", false]);
    }
    Connections {
        target: Mpv
        // the user took over (Space): the pause is theirs now
        function onPausedChanged() { if (!Mpv.paused) lex._ourPause = false; }
    }

    Timer {
        id: statsDebounce
        interval: 1500
        onTriggered: lex.refreshStats()
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
            yomitanUp = o.yomitan === true;
            knownWords = o.words || 0;
            const q = _pending;
            _pending = [];
            q.forEach(r => proc.write(JSON.stringify(r) + "\n"));
            // started for the OCR card alone: no Anki sync, no subtitle work
            if (ready && lex.wanted) {
                lex.sync();
                lex.refreshStats();
                lex.refreshLine();
                if (lex.panelOpen)
                    lex.loadTranscript(true);
            }
            return;
        }
        const cb = _cb[o.id];
        if (cb) {
            delete _cb[o.id];
            cb(o);
        }
    }

    Connections {
        target: Mpv
        function onSubSeqChanged() { lex.refreshLine(); }
        function onPathChanged() {
            lex.stats = {};
            lex.statsFor = "";
            lex.rows = [];
            lex.transcript = [];
            lex.transcriptFor = "";
            lex._ourPause = false;
            lex.refreshStats();
            if (lex.panelOpen)
                lex.loadTranscript(false);
        }
        function onSubFileChanged() {
            lex.refreshStats();
            if (lex.panelOpen)
                lex.loadTranscript(false);
        }
    }
    // a card just mined (or an Anki session) changes what counts as known
    Connections {
        target: Anki
        function onLastMinedAtChanged() { if (lex.ready) lex.sync(); }
    }
    // a freshly fetched subtitle (Jimaku) changes the comprehension figure
    Connections {
        target: Jimaku
        function onSearchingChanged() { if (!Jimaku.searching && lex.ready) lex.refreshStats(); }
    }

    // mpv's own subtitles step aside while the overlay is up. Scaled to nothing rather than switched
    // off: sub-visibility is in watch-later-options, so a crash would leave the video without subs for good.
    property bool _hidden: false
    onOverlayOnChanged: {
        if (!overlayOn) {
            Mpv.send(["script-message", "lexicon-pause-at", "0"]);
            _ourPause = false;
            panelOpen = false;
            panelPinned = false;
        }
        if (overlayOn === _hidden)
            return;
        _hidden = overlayOn;
        Mpv.send(["set_property", "sub-scale", overlayOn ? 0 : Mpv.subScale]);
    }
    Component.onDestruction: if (_hidden) Mpv.send(["set_property", "sub-scale", Mpv.subScale])

    // Yomitan comes and goes with the browser; ask again every so often while a file is open
    Timer {
        interval: 30000
        repeat: true
        running: lex.ready
        onTriggered: lex.request({ op: "status" }, r => { lex.yomitanUp = r.yomitan === true; lex.knownWords = r.words || 0; })
    }

    Process {
        id: proc
        command: [lex.python, Quickshell.shellDir + "/scripts/lexicon.py"]
        running: lex.wanted || lex.ocrKeep
        stdinEnabled: true
        stdout: SplitParser { onRead: line => lex._onLine(line) }
        onExited: code => {
            lex.ready = false;
            lex._cb = ({});
            lex._pending = [];
            lex.rows = [];
            lex._ourPause = false;
        }
    }

    IpcHandler {
        target: "subs"
        function toggle(): void { lex.enabled = !lex.enabled; }
        function sync(): void { lex.sync(); }
        function mine(): void { lex.mine(lex.focusTok, lex.focusCtx); }
        function known(): void { if (lex.focusTok) lex.mark(lex.focusTok, "known"); }
        function ignore(): void { if (lex.focusTok) lex.mark(lex.focusTok, "ignored"); }
        function name(): void { if (lex.focusTok) lex.setName(lex.focusTok, lex.focusTok.status === "name" ? 0 : 1); }
        function furigana(): void { lex.cycleFurigana(); }
        function reviewpause(): void { lex.setReviewPause(!lex.reviewPause); }
        function panel(): void { lex.togglePanel(); }
        function open(): void { lex.panelOpen = true; }
        function close(): void { lex.panelOpen = false; lex.panelPinned = false; }
        function state(): string {
            return JSON.stringify({ ready: lex.ready, yomitan: lex.yomitanUp, enabled: lex.enabled, overlayOn: lex.overlayOn,
                                    focused: lex.mpvFocused, fullscreen: Mpv.fullscreen, subDelay: Mpv.subDelay,
                                    subStart: Mpv.subStart, subEnd: Mpv.subEnd, live: Mpv.subLive, panel: lex.panelOpen, pinned: lex.panelPinned,
                                    lines: lex.transcript.length, current: lex.currentIndex, subPath: lex.subPath(),
                                    known: lex.knownWords, reviewPause: lex.reviewPause, stats: lex.stats, rows: lex.rows });
        }
    }
}
