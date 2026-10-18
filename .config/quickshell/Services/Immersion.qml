pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Services

// Immersion tracker. mpv (through ~/.config/mpv/scripts/immersion.lua) appends one line per
// playback segment to mpv.jsonl and keeps live.json current; reading is logged by hand. This
// singleton turns that into days, streaks, recent sessions and per-series totals. The script only
// records facts: what counts (Japanese audio, or a manual override per series) is decided here, so
// a changed rule also applies to everything already logged.
//
// segment = { id, start, end, secs, path, title, dur, pos, alang, aname, slang }
// entry   = { id, type: "reading", title, minutes, chars, day: "yyyy-MM-dd" }
// kavita  = scripts/kavita_stats.py reads Kavita's own reading sessions (series, pages, start/end) into
//           kavita.json: one { work, volume, day, secs, pages, modified } per series and day
// context = which of mpv / ttu / Kavita the user is "in": the last of them to be the focused window
//           (matched by window class and title), so the panel can show the matching card
// ttu     = scripts/ttu_stats.py copies ttu (ッツ Ebook Reader) reading statistics out of the LibreWolf
//           profile into ttu.json: one { title, day, chars, secs, modified } per book and day
Singleton {
    id: imm

    // a day was changed from the UI; `undo()` puts it back
    signal undoable(string message)
    // today's time just crossed the goal (once a day)
    signal goalReached()

    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell"
    readonly property string todayKey: Tasks.todayKey

    // working copies, written through to immersion.json (the JSON adapter notifies a beat late)
    property int goal: 60
    // the day the goal chime last played, so it sounds once a day
    property string goalDay: ""
    property var entries: []
    // seriesKey -> true / false, beating the language rule
    property var overrides: ({})
    // ids of mpv segments the user removed
    property var hidden: []
    property var segments: []

    // ---- what the log says ----
    // dayKey -> { minutes, watch, read, chars }, counted time only, live segment not included
    property var days: ({})
    // sessions merged per series and day, newest first (uncounted ones included, marked)
    property var recent: []
    // one row per series, most recently watched first
    property var seriesList: []
    property int streak: 0
    property int best: 0

    // ---- ttu reader ----
    property var ttuRows: []
    property var ttuBooks: []
    property string ttuLatest: ""
    property string ttuLastTitle: ""
    // newest reading save that counts, and its book (set by rebuild)
    property real ttuNewest: 0
    property string ttuTitle: ""
    // ttu saves while a page is being read
    readonly property bool ttuNow: ttuNewest > 0 && nowSec - ttuNewest < 90
    // the stats exist but hold no reading time at all (the reader's tracker is off)
    // reading time exists, but only as an estimate from the reading position (ttu's tracker is off)
    readonly property bool ttuEstimated: ttuRows.some(r => r.secs >= 30) && !ttuRows.some(r => r.secs >= 30 && !r.est)
    readonly property bool ttuIdle: ttuRows.length > 0 && !ttuRows.some(r => r.secs >= 30)
    readonly property bool hasTtu: ttuRows.length > 0 || ttuBooks.length > 0

    // ---- Kavita (manga) ----
    property var kavitaRows: []
    property var kavitaSeries: []
    property string kavitaLatest: ""
    property real kavitaMod: 0
    property var kavitaActiveSeries: null
    // newest counted manga save (set by rebuild) and its work
    property real kavitaNewest: 0
    property string kavitaWork: ""
    readonly property bool kavitaNow: kavitaNewest > 0 && nowSec - kavitaNewest < 90
    readonly property bool hasKavita: kavitaRows.length > 0 || kavitaSeries.length > 0
    // reading in either book app right now, and what
    readonly property bool readingNow: ttuNow || kavitaNow
    readonly property string readingTitle: kavitaNow && (!ttuNow || kavitaNewest >= ttuNewest) ? kavitaWork : ttuTitle

    // ---- context: mpv, ttu or kavita, by the focused window's class and title ----
    property string ctxKind: ""
    property string ctxName: ""
    readonly property var activeWin: ToplevelManager.activeToplevel
    readonly property var activeCtx: activeWin ? classify(activeWin.appId, activeWin.title) : null
    // a window that isn't one of the three (a terminal, this panel) leaves the context alone
    onActiveCtxChanged: {
        if (activeCtx) {
            ctxKind = activeCtx.kind;
            ctxName = activeCtx.name;
        }
    }
    // until a window has been focused: whatever is live, else whichever was saved last
    readonly property real ttuMod: ttuRows.reduce((m, r) => Math.max(m, r.modified || 0), 0)
    readonly property string fallbackKind: {
        if (liveOn)
            return "mpv";
        const t = ttuMod;
        if (t === 0 && kavitaMod === 0)
            return segments.length > 0 ? "mpv" : "";
        return kavitaMod > t ? "kavita" : "ttu";
    }
    readonly property string context: ctxKind !== "" ? ctxKind : fallbackKind
    // class and title -> { kind, name } or null. The rules live here so they are easy to change.
    function classify(appId, title) {
        const a = String(appId || "").toLowerCase();
        const t = String(title || "");
        if (a === "mpv")
            return { kind: "mpv", name: t };
        if (/librewolf|firefox/.test(a)) {
            const page = t.replace(/\s+[—–-]\s+(LibreWolf|Mozilla Firefox)$/, "");
            if (page.indexOf("ッツ Ebook Reader") >= 0) {
                const i = page.indexOf(" | ");
                return { kind: "ttu", name: i > 0 ? page.slice(0, i) : "" };
            }
            const m = page.match(/^(.*?)\s*\(Kavita\)$/);
            if (m)
                return { kind: "kavita", name: m[1] };
            if (page === "Kavita")
                return { kind: "kavita", name: "" };
        }
        return null;
    }

    // ---- what mpv is doing right now ----
    property var liveRaw: ({})
    property real nowSec: Date.now() / 1000
    readonly property bool liveOn: !!liveRaw.playing && nowSec - (liveRaw.updated || 0) < 20
    readonly property var liveInfo: liveRaw.path ? parsePath(liveRaw.path, liveRaw.title) : null
    readonly property bool liveCounted: !!liveInfo && isCounted(liveInfo.key, liveRaw.alang, liveRaw.slang, liveRaw.title + " " + liveRaw.path)
    // seconds of the open segment, counted only when it earns time
    readonly property real liveSecs: liveOn && liveCounted ? Math.max(0, nowSec - liveRaw.segStart) : 0
    // the last thing mpv played, for "Continue"
    readonly property var lastSeen: segments.length > 0 ? segments[segments.length - 1] : null

    readonly property real todayMinutes: (days[todayKey] ? days[todayKey].minutes : 0) + liveSecs / 60
    readonly property bool goalMet: todayMinutes >= goal
    // how far past the goal: 0 below it, then 0.xx of a lap into the second (overdrive), 1.xx the third...
    readonly property real overLaps: Math.max(0, todayMinutes / Math.max(1, goal) - 1)
    readonly property bool overdrive: todayMinutes > goal

    // ---- the goal chime ----
    // It sounds when time being *added* takes today across the goal, once a day. Not on a restart that finds
    // the goal met, not when the goal itself is lowered, and not while the logs are still being read in.
    property bool _goalReady: false
    property real _prevMins: 0
    property int _prevGoal: 60
    Timer {
        interval: 12000
        running: true
        onTriggered: {
            imm._prevMins = imm.todayMinutes;
            imm._prevGoal = imm.goal;
            imm._goalReady = true;
            // already met today when the shell came up: nothing to announce
            if (imm.goalMet && imm.goalDay !== imm.todayKey) {
                imm.goalDay = imm.todayKey;
                imm._save();
            }
        }
    }
    onTodayMinutesChanged: {
        const now = todayMinutes, was = _prevMins, g = _prevGoal;
        _prevMins = now;
        _prevGoal = goal;
        if (!_goalReady || g !== goal)
            return;
        if (was < goal && now >= goal && goalDay !== todayKey) {
            goalDay = todayKey;
            _save();
            Sound.play("goal");
            goalReached();
        }
    }
    readonly property real todayWatch: (days[todayKey] ? days[todayKey].watch : 0) + liveSecs / 60
    readonly property real todayRead: days[todayKey] ? days[todayKey].read : 0
    readonly property real charsToday: days[todayKey] ? days[todayKey].chars : 0
    readonly property real charsPerHour: todayRead >= 1 ? Math.round(charsToday / (todayRead / 60)) : 0
    readonly property real pagesToday: days[todayKey] ? days[todayKey].pages || 0 : 0
    // the book the reader card shows: the one the window title names, else the one being read, else
    // the last one read
    readonly property var readerBook: {
        const named = context === "ttu" && ctxName ? ttuBooks.find(b => b.title === ctxName) : null;
        if (named)
            return named;
        const t = ttuNow ? ttuTitle : (ttuTitle || ttuLastTitle);
        return t ? (ttuBooks.find(b => b.title === t) || { title: t, progress: null }) : null;
    }
    // the manga the card shows: named by the window, else being read / last read
    readonly property var mangaSeries: {
        if (kavitaSeries.length === 0)
            return null;
        const byName = context === "kavita" && ctxName
            ? kavitaSeries.find(s => s.name === ctxName || s.work === ctxName || ctxName.indexOf(s.work) === 0) : null;
        if (byName)
            return byName;
        const act = kavitaActiveSeries !== null ? kavitaSeries.find(s => s.id === kavitaActiveSeries) : null;
        return act || kavitaSeries.slice().sort((a, b) => b.modified - a.modified)[0];
    }
    // time and pages in that manga's work today
    readonly property var mangaToday: {
        const w = mangaSeries ? mangaSeries.work : "";
        let secs = 0, pages = 0;
        kavitaRows.forEach(r => {
            if (r.day === todayKey && r.work === w && overrides["kavita:" + w.toLowerCase()] !== false) {
                secs += r.secs;
                pages += r.pages;
            }
        });
        return { secs: secs, pages: pages };
    }

    onTodayKeyChanged: rebuild()
    onGoalChanged: rebuild()

    // ---- formatting ----
    function pad(n) { return String(n).padStart(2, "0"); }
    // 42m, 1h 05m
    function fmt(minutes) {
        const m = Math.round(minutes);
        if (m < 60)
            return m + "m";
        return Math.floor(m / 60) + "h " + pad(m % 60) + "m";
    }
    function fmtClock(secs) {
        const s = Math.max(0, Math.floor(secs));
        const h = Math.floor(s / 3600), m = Math.floor(s % 3600 / 60), r = s % 60;
        return (h > 0 ? h + ":" + pad(m) : m) + ":" + pad(r);
    }
    // 0..4 against the goal, for heatmap shading
    function levelOf(minutes) {
        if (minutes <= 0)
            return 0;
        const r = minutes / Math.max(1, goal);
        return r >= 1 ? 4 : r >= 0.5 ? 3 : r >= 0.25 ? 2 : 1;
    }
    function dayMinutes(key) {
        const d = days[key];
        const live = key === todayKey ? liveSecs / 60 : 0;
        return (d ? d.minutes : 0) + live;
    }

    // ---- turning a path into a series and an episode ----
    function stripTags(s) {
        let t = String(s).replace(/\[[^\]]*\]|\([^)]*\)|【[^】]*】/g, " ").replace(/[_]+/g, " ").replace(/\s+/g, " ").trim();
        // "Some.Show.S02E03.1080p": dots stand in for spaces when there are no spaces at all
        if (t.indexOf(" ") < 0 && (t.match(/\./g) || []).length >= 2)
            t = t.replace(/\./g, " ").replace(/\s+/g, " ").trim();
        return t;
    }
    function parsePath(path, title) {
        path = String(path || "");
        title = String(title || "");
        if (path === "")
            return { name: "Unknown", key: "unknown", episode: "", season: 0 };
        // streamed: the title is all there is
        if (/^[a-z]+:\/\//i.test(path)) {
            const n = stripTags(title) || path;
            return { name: n, key: n.toLowerCase(), episode: "", season: 0 };
        }
        const parts = path.split("/").filter(p => p !== "");
        const file = stripTags((parts[parts.length - 1] || "").replace(/\.[A-Za-z0-9]{2,4}$/, ""));
        let season = 0, ep = "", token = "", m;
        if ((m = file.match(/\bS(\d{1,2})\s*E(\d{1,3})\b/i))) {
            season = Number(m[1]);
            ep = String(Number(m[2]));
            token = m[0];
        } else if ((m = file.match(/(?:^|[\s.\-])(?:EP|E|Episode)\s*\.?(\d{1,3})\b/i))) {
            ep = String(Number(m[1]));
            token = m[0];
        } else if ((m = file.match(/\s[-–]\s*(\d{1,3})(?:v\d)?(?=\s|$)/))) {
            ep = String(Number(m[1]));
            token = m[0];
        }
        const home = (Quickshell.env("HOME") || "").split("/").pop();
        const seasonRe = /^(season\s*\d+|s\d+|specials?|extras?|ova|oad|movies?)$/i;
        const genericRe = /^(videos?|downloads?|animes?|tv|tmp|anime|media|shows?)$/i;
        let folder = stripTags(parts.length >= 2 ? parts[parts.length - 2] : "");
        const folderSeason = folder.match(/(?:^|[\s\-–]+)(?:S|Season\s*)(\d{1,2})$/i);
        if (folderSeason && season === 0)
            season = Number(folderSeason[1]);
        folder = folder.replace(/(?:^|[\s\-–]+)(?:S|Season\s*)\d{1,2}$/i, "").trim();
        if ((folder === "" || seasonRe.test(folder)) && parts.length >= 3) {
            const up = stripTags(parts[parts.length - 3]);
            folder = up.replace(/(?:^|[\s\-–]+)(?:S|Season\s*)\d{1,2}$/i, "").trim();
        }
        let name;
        if (ep !== "" && folder !== "" && !genericRe.test(folder) && folder !== home && !seasonRe.test(folder))
            name = folder;
        else
            name = file.replace(token, " ").replace(/[\s\-–.]+$/, "").replace(/\s+/g, " ").trim() || file;
        const label = ep === "" ? "" : (season > 0 ? "S" + season + "E" + ep : "E" + ep);
        return { name: name, key: name.toLowerCase(), episode: label, season: season };
    }

    // ---- what counts ----
    function isJapanese(lang) { return /^(ja|jp|jpn|japanese)$/i.test(String(lang || "")); }
    function isCounted(key, alang, slang, text) {
        if (overrides[key] === true || overrides[key] === false)
            return overrides[key];
        if (alang)
            return isJapanese(alang);
        // untagged audio: believe a Japanese sub track or Japanese text in the name
        return isJapanese(slang) || /[぀-ヿ一-鿿]/.test(String(text || ""));
    }
    // why a session does or doesn't count, for the chip
    function reasonOf(key, alang, slang, text) {
        if (overrides[key] === true)
            return "Marked as counting";
        if (overrides[key] === false)
            return "Marked as not counting";
        if (alang)
            return isJapanese(alang) ? "Japanese audio" : "Audio is " + String(alang).toUpperCase();
        return isCounted(key, alang, slang, text) ? "Looks Japanese" : "No audio language";
    }
    function seriesCounted(key) {
        const s = seriesList.find(x => x.key === key);
        return s ? s.counted : false;
    }

    // ---- rebuild: segments + entries -> days, recent, series, streaks ----
    function dayOf(epoch) { return Tasks.keyOf(new Date(epoch * 1000)); }

    function rebuild() {
        const hid = {};
        hidden.forEach(h => { hid[h] = true; });
        const dayMap = {};
        function day(k) { return dayMap[k] || (dayMap[k] = { minutes: 0, watch: 0, read: 0, chars: 0 }); }

        // sessions: one row per series and day
        const groups = {};
        const seriesMap = {};
        segments.forEach(seg => {
            if (hid[seg.id])
                return;
            const info = parsePath(seg.path, seg.title);
            const counted = isCounted(info.key, seg.alang, seg.slang, seg.title + " " + seg.path);
            const k = dayOf(seg.start);
            const gk = k + "|" + info.key;
            let g = groups[gk];
            if (!g) {
                g = groups[gk] = { id: "m:" + gk, kind: "watch", day: k, key: info.key, name: info.name,
                                   episodes: {}, secs: 0, last: 0, counted: counted, segIds: [],
                                   path: seg.path, reason: reasonOf(info.key, seg.alang, seg.slang, seg.title + " " + seg.path) };
            }
            g.secs += seg.secs;
            g.segIds.push(seg.id);
            if (info.episode !== "")
                g.episodes[info.episode] = true;
            if (seg.end >= g.last) {
                g.last = seg.end;
                g.path = seg.path;
            }
            if (counted) {
                const d = day(k);
                d.minutes += seg.secs / 60;
                d.watch += seg.secs / 60;
            }
            let s = seriesMap[info.key];
            if (!s) {
                s = seriesMap[info.key] = { key: info.key, name: info.name, secs: 0, counted: counted,
                                            episodes: {}, last: 0, path: seg.path };
            }
            s.counted = counted;
            s.secs += seg.secs;
            if (info.episode !== "")
                s.episodes[info.episode] = true;
            if (seg.end >= s.last) {
                s.last = seg.end;
                s.path = seg.path;
            }
        });

        const rows = Object.keys(groups).map(gk => {
            const g = groups[gk];
            const eps = Object.keys(g.episodes);
            return { id: g.id, kind: "watch", src: "mpv", day: g.day, key: g.key, title: g.name,
                     detail: eps.length === 0 ? "" : eps.length === 1 ? eps[0] : eps.length + " episodes",
                     minutes: g.secs / 60, chars: 0, counted: g.counted, reason: g.reason, last: g.last,
                     path: g.path, segIds: g.segIds };
        });
        entries.forEach(e => {
            const d = day(e.day);
            d.minutes += Number(e.minutes) || 0;
            d.read += Number(e.minutes) || 0;
            d.chars += Number(e.chars) || 0;
            rows.push({ id: e.id, kind: "read", src: "manual", day: e.day, key: "", title: e.title || "Reading",
                        detail: Number(e.chars) > 0 ? Number(e.chars).toLocaleString(Qt.locale(), "f", 0) + " chars" : "",
                        minutes: Number(e.minutes) || 0, chars: Number(e.chars) || 0, counted: true, reason: "",
                        last: Number(String(e.id).split("-")[0]) || 0, path: "", segIds: [] });
        });
        // reading in ttu: one row per book and day, hidden/switched off like mpv sessions
        const bookMap = {};
        let newest = 0, newestTitle = "";
        ttuRows.forEach(r => {
            if (!(r.secs >= 30))
                return;
            const id = "t:" + r.day + "|" + r.title;
            if (hid[id])
                return;
            const key = "ttu:" + r.title.toLowerCase();
            const counted = overrides[key] !== false;
            const mins = r.secs / 60;
            if (counted) {
                const d = day(r.day);
                d.minutes += mins;
                d.read += mins;
                d.chars += r.chars;
                if (r.est)
                    d.est = true;
                if (r.modified > newest) {
                    newest = r.modified;
                    newestTitle = r.title;
                }
            }
            const info = ttuBooks.find(x => x.title === r.title) || ({});
            const perHour = r.chars > 0 ? Math.round(r.chars / (r.secs / 3600)) : 0;
            rows.push({ id: id, kind: "read", src: "ttu", day: r.day, key: key, title: r.title,
                        detail: (r.est ? "estimated" + (r.chars > 0 ? " · " : "") : "")
                            + (r.chars > 0 ? r.chars.toLocaleString(Qt.locale(), "f", 0) + " chars · " + perHour.toLocaleString(Qt.locale(), "f", 0) + "/h" : ""),
                        minutes: mins, chars: r.chars, counted: counted, reason: "ttu", last: r.modified,
                        path: "", segIds: [id], cover: info.cover || "", est: !!r.est });
            let b = bookMap[key];
            if (!b) {
                b = bookMap[key] = { key: key, name: r.title, kind: "book", secs: 0, chars: 0, counted: counted, last: 0,
                                     progress: info.progress === undefined ? null : info.progress, cover: info.cover || "", estOnly: true };
            }
            b.secs += r.secs;
            b.chars += r.chars;
            if (!r.est)
                b.estOnly = false;
            b.last = Math.max(b.last, r.modified);
        });
        ttuNewest = newest;
        ttuTitle = newestTitle;

        // reading manga in Kavita: one row per volume and day, real session time
        const mangaMap = {};
        let kNewest = 0, kWork = "";
        kavitaRows.forEach(r => {
            if (!(r.secs >= 10))
                return;
            const id = "k:" + r.day + "|" + r.sid;
            if (hid[id])
                return;
            const key = "kavita:" + r.work.toLowerCase();
            const counted = overrides[key] !== false;
            const mins = r.secs / 60;
            if (counted) {
                const d = day(r.day);
                d.minutes += mins;
                d.read += mins;
                d.pages = (d.pages || 0) + r.pages;
                if (r.modified > kNewest) {
                    kNewest = r.modified;
                    kWork = r.work + (r.volume ? " " + r.volume : "");
                }
            }
            const info = kavitaSeries.find(x => x.id === r.sid) || ({});
            rows.push({ id: id, kind: "read", src: "kavita", day: r.day, key: key, title: r.work,
                        detail: [r.volume, r.pages + (r.pages === 1 ? " page" : " pages")].filter(t => t !== "").join(" · "),
                        minutes: mins, chars: 0, pages: r.pages, counted: counted, reason: "Kavita", last: r.modified,
                        path: "", segIds: [id], cover: info.cover || "" });
            let m = mangaMap[key];
            if (!m) {
                m = mangaMap[key] = { key: key, name: r.work, kind: "manga", secs: 0, pages: 0, counted: counted, last: 0,
                                      volumes: {}, progress: null, cover: "" };
            }
            m.secs += r.secs;
            m.pages += r.pages;
            m.volumes[r.sid] = true;
            if (r.modified >= m.last) {
                m.last = r.modified;
                m.progress = info.progress === undefined ? null : info.progress;
                m.cover = info.cover || m.cover;
            }
        });
        kavitaNewest = kNewest;
        kavitaWork = kWork;
        rows.sort((a, b) => a.day === b.day ? b.last - a.last : (a.day < b.day ? 1 : -1));

        const sl = Object.keys(seriesMap).map(k => {
            const s = seriesMap[k];
            return { key: s.key, name: s.name, minutes: s.secs / 60, counted: s.counted,
                     episodes: Object.keys(s.episodes).length, last: s.last, path: s.path };
        });
        Object.keys(bookMap).forEach(k => {
            const b = bookMap[k];
            sl.push({ key: b.key, name: b.name, kind: "book", minutes: b.secs / 60, counted: b.counted, episodes: 0,
                      last: b.last, path: "", chars: b.chars, progress: b.progress, cover: b.cover, est: b.estOnly });
        });
        Object.keys(mangaMap).forEach(k => {
            const m = mangaMap[k];
            sl.push({ key: m.key, name: m.name, kind: "manga", minutes: m.secs / 60, counted: m.counted,
                      episodes: Object.keys(m.volumes).length, last: m.last, path: "", pages: m.pages,
                      progress: m.progress, cover: m.cover });
        });
        sl.sort((a, b) => b.last - a.last);

        // streaks: a day is kept once it reaches the goal; today doesn't break the run while open
        const keys = Object.keys(dayMap).filter(k => dayMap[k].minutes >= goal).sort();
        let bestRun = 0, run = 0, prev = null;
        keys.forEach(k => {
            run = prev && Tasks.keyOf(Tasks.addDays(Tasks.dateOf(prev), 1)) === k ? run + 1 : 1;
            bestRun = Math.max(bestRun, run);
            prev = k;
        });
        let s = 0;
        const today = Tasks.dateOf(todayKey);
        for (let i = 0; i < 1100; i++) {
            const k = Tasks.keyOf(Tasks.addDays(today, -i));
            if (dayMap[k] && dayMap[k].minutes >= goal)
                s++;
            else if (i > 0)
                break;
        }

        days = dayMap;
        recent = rows;
        seriesList = sl;
        streak = s;
        best = Math.max(bestRun, s);
    }

    // ---- changes ----
    property var _undo: null

    function _save() {
        adapter.goal = goal;
        adapter.entries = entries;
        adapter.overrides = overrides;
        adapter.hidden = hidden;
        adapter.goalDay = goalDay;
        store.writeAdapter();
    }
    function setGoal(minutes) {
        goal = Math.max(5, Math.min(600, Math.round(minutes)));
        _save();
    }
    function addReading(title, minutes, chars, dayKey) {
        const m = Number(minutes);
        if (!(m > 0))
            return;
        const e = { id: Date.now() + "-" + Math.floor(Math.random() * 1296).toString(36), type: "reading",
                    title: String(title || "Reading").trim() || "Reading", minutes: m,
                    chars: Math.max(0, Number(chars) || 0), day: dayKey || todayKey };
        entries = entries.concat([e]);
        _undo = { type: "add", id: e.id };
        _save();
        rebuild();
        imm.undoable("Logged " + fmt(m) + " of " + e.title);
    }
    // a manual entry is deleted; an mpv session hides its segments
    function removeRow(row) {
        if (!row)
            return;
        if (row.src === "manual") {
            const e = entries.find(x => x.id === row.id);
            if (!e)
                return;
            entries = entries.filter(x => x.id !== row.id);
            _undo = { type: "entry", entry: e };
        } else {
            hidden = hidden.concat(row.segIds);
            _undo = { type: "hide", ids: row.segIds };
        }
        _save();
        rebuild();
        imm.undoable("Removed " + row.title);
    }
    function undo() {
        if (!_undo)
            return;
        const u = _undo;
        _undo = null;
        if (u.type === "add")
            entries = entries.filter(x => x.id !== u.id);
        else if (u.type === "entry")
            entries = entries.concat([u.entry]);
        else if (u.type === "hide")
            hidden = hidden.filter(h => u.ids.indexOf(h) < 0);
        _save();
        rebuild();
    }
    // true / false forces a series in or out, null goes back to the language rule
    function setCounted(key, on) {
        const o = Object.assign({}, overrides);
        if (on === null || on === undefined)
            delete o[key];
        else
            o[key] = !!on;
        overrides = o;
        _save();
        rebuild();
    }

    // ---- reading the files mpv writes ----
    property string _logText: ""
    function _parseLog(text) {
        if (text === _logText)
            return;
        _logText = text;
        const out = [];
        text.split("\n").forEach(line => {
            if (line.length < 2)
                return;
            try {
                const o = JSON.parse(line);
                if (o && o.id && o.secs > 0)
                    out.push(o);
            } catch (e) {}
        });
        segments = out;
        rebuild();
    }
    function _parseTtu(text) {
        try {
            const o = JSON.parse(text);
            ttuRows = o.rows || [];
            ttuBooks = o.books || [];
            ttuLatest = o.latest || "";
            ttuLastTitle = o.lastTitle || "";
            nowSec = Date.now() / 1000;
            rebuild();
        } catch (e) {}
    }
    function _parseKavita(text) {
        try {
            const o = JSON.parse(text);
            kavitaRows = o.rows || [];
            kavitaSeries = o.series || [];
            kavitaLatest = o.latest || "";
            kavitaMod = o.modified || 0;
            kavitaActiveSeries = o.active ? o.activeSeries : null;
            nowSec = Date.now() / 1000;
            rebuild();
        } catch (e) {}
    }
    // read ttu's stats and Kavita's sessions now
    function sync() {
        if (!ttuSync.running)
            ttuSync.running = true;
        if (!kavitaSync.running)
            kavitaSync.running = true;
    }
    function _parseLive(text) {
        try {
            const o = JSON.parse(text);
            if (o) {
                liveRaw = o;
                nowSec = Date.now() / 1000;
            }
        } catch (e) {}
    }

    // the log is read again shortly after live.json changes, so a segment just closed shows up even
    // when the file watcher misses a file that did not exist yet
    Timer {
        id: logSoon
        interval: 350
        onTriggered: logFile.reload()
    }
    Timer {
        interval: 1000
        repeat: true
        running: imm.liveOn
        onTriggered: imm.nowSec = Date.now() / 1000
    }
    // the "reading now" state expires on its own
    Timer {
        interval: 5000
        repeat: true
        running: (imm.ttuNewest > 0 && imm.nowSec - imm.ttuNewest < 100) || (imm.kavitaNewest > 0 && imm.nowSec - imm.kavitaNewest < 100)
        onTriggered: imm.nowSec = Date.now() / 1000
    }
    // ttu: pull its stats every 20 s (the script exits at once while nothing changed)
    Timer {
        interval: 20000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: imm.sync()
    }
    Process {
        id: ttuSync
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/ttu_stats.py", "--out", imm.stateDir + "/immersion/ttu.json"]
    }
    Process {
        id: kavitaSync
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/kavita_stats.py", "--out", imm.stateDir + "/immersion/kavita.json"]
    }
    FileView {
        id: kavitaFile
        path: imm.stateDir + "/immersion/kavita.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: imm._parseKavita(text())
    }
    FileView {
        id: ttuFile
        path: imm.stateDir + "/immersion/ttu.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: imm._parseTtu(text())
    }
    // mpv gone without a clean exit: let the open segment stop counting
    Timer {
        interval: 5000
        repeat: true
        running: !!imm.liveRaw.playing
        onTriggered: imm.nowSec = Date.now() / 1000
    }

    FileView {
        id: logFile
        path: imm.stateDir + "/immersion/mpv.jsonl"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: imm._parseLog(text())
        onLoadFailed: imm._parseLog("")
    }
    FileView {
        id: liveFile
        path: imm.stateDir + "/immersion/live.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            imm._parseLive(text());
            logSoon.restart();
        }
    }

    // ---- persistence ----
    FileView {
        id: store
        path: imm.stateDir + "/immersion.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            imm.goal = adapter.goal > 0 ? adapter.goal : 60;
            imm.entries = adapter.entries || [];
            imm.overrides = adapter.overrides || ({});
            imm.hidden = adapter.hidden || [];
            imm.goalDay = adapter.goalDay || "";
            imm.rebuild();
        }

        JsonAdapter {
            id: adapter
            property int goal: 60
            property var entries: []
            property var overrides: ({})
            property var hidden: []
            property string goalDay: ""
        }
    }
}
