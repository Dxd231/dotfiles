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
    // the source the panel's left card is pinned to (mpv | ttu | kavita), "" to follow the context
    property string pane: ""
    property var entries: []
    // seriesKey -> true / false, beating the language rule
    property var overrides: ({})
    // ids of mpv segments the user removed
    property var hidden: []
    // series keys pinned to the front of the shelf, newest pin first
    property var pins: []
    property var segments: []

    // ---- what the log says ----
    // dayKey -> { minutes, watch, read, chars }, counted time only, live segment not included
    property var days: ({})
    // sessions merged per series and day, newest first (uncounted ones included, marked)
    property var recent: []
    // one row per series, most recently watched first
    property var seriesList: []
    // anime thumbnails: episode directory -> an image found there (or in the series folder above it)
    property var animeCovers: ({})
    // folders whose anime all show in the shelf, watched or not
    property var animeRoots: ["/mnt/GAME_DISK/Animes"]
    property var animeFolders: []
    property string _coverDirs: ""
    function dirOf(p) {
        p = String(p || "");
        return p.charAt(0) === "/" ? p.substring(0, p.lastIndexOf("/")) : "";
    }
    function rescanCovers() {
        if (!animeScan.running)
            animeScan.running = true;
        _coverDirs = "";
        coverSoon.restart();
    }
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
    // mpv closes a segment into the log and then reports the next one in live.json, and the shell reads the
    // two files at different moments. So the open segment is left out once the log holds it, and a segment
    // that just closed keeps counting as live (`_carry`) until the log shows up, or the total would jump
    // (the goal chime could fire early) or dip.
    readonly property bool _liveLogged: liveOn && segments.some(s => s.id === liveRaw.segStart + "-" + liveRaw.pid)
    property var _carry: null
    readonly property real _carrySecs: _carry && !segments.some(s => s.id === _carry.id) ? _carry.secs : 0
    Timer {
        id: carryExpiry
        interval: 5000
        onTriggered: imm._carry = null
    }
    // seconds of the open segment, counted only when it earns time
    readonly property real liveSecs: (liveOn && liveCounted && !_liveLogged ? Math.max(0, nowSec - liveRaw.segStart) : 0) + _carrySecs
    // the last thing mpv played, for "Continue"
    readonly property var lastSeen: segments.length > 0 ? segments[segments.length - 1] : null

    readonly property real todayMinutes: (days[todayKey] ? days[todayKey].minutes : 0) + liveSecs / 60
    // a busy day halves the goal
    function goalOn(key) { return DayMarks.goalOn(goal, key); }
    readonly property int todayGoal: goalOn(todayKey)
    readonly property bool goalMet: todayMinutes >= todayGoal
    // how far past the goal: 0 below it, then 0.xx of a lap into the second (overdrive), 1.xx the third...
    readonly property real overLaps: Math.max(0, todayMinutes / Math.max(1, todayGoal) - 1)
    readonly property bool overdrive: todayMinutes > todayGoal

    // ---- the goal chime ----
    // It sounds when time being *added* takes today across the goal, once a day. Not on a restart that finds
    // the goal met, not when the goal itself is lowered, and not while the logs are still being read in.
    // The live and logged minutes are de-duplicated across a segment flush (see `_carry`), so a read that
    // lands between the two files can't take today over the goal early.
    property bool _goalReady: false
    property real _prevMins: 0
    property int _prevGoal: 60
    Timer {
        interval: 12000
        running: true
        onTriggered: {
            imm._prevMins = imm.todayMinutes;
            imm._prevGoal = imm.todayGoal;
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
        _prevGoal = todayGoal;
        if (!_goalReady || g !== todayGoal)
            return;
        if (was < todayGoal && now >= todayGoal && goalDay !== todayKey) {
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

    // Kavita's reader for a series (reopens at the saved page); falls back to the series page, then home
    function kavitaUrl(s) {
        const base = "http://localhost:5000";
        if (!s || !s.library || !s.id)
            return base + "/";
        const root = base + "/library/" + s.library + "/series/" + s.id;
        if (!s.chapter)
            return root;
        return root + (s.format === 3 ? "/book/" : s.format === 4 ? "/pdf/" : "/manga/") + s.chapter;
    }

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
    function levelOf(minutes, key) {
        if (minutes <= 0)
            return 0;
        const r = minutes / Math.max(1, key ? goalOn(key) : goal);
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
    // release folders like "Show S01 1080p BDRip x265-GROUP": the title ends at the first tag
    function showName(n) {
        return String(n).replace(/\s+(S\d{1,2}(-S?\d{1,2})?|\d{3,4}p|BDRip|WEBRip|Dual Audio)\b.*$/i, "").trim() || String(n);
    }
    // a show is made of parts: its seasons ("1", "2"..), "ova", "sp" and one "movie:<slug>" per movie
    function partOf(s, id) {
        return s.parts[id] || (s.parts[id] = { id: id, secs: 0, last: 0, path: "", watchedEp: 0, eps: {}, disk: 0, first: "", label: "", kind: "" });
    }
    function partCards(s) {
        const cards = Object.keys(s.parts).map(id => {
            const p = s.parts[id];
            const kind = p.kind || (/^\d+$/.test(id) ? "season" : id.split(":")[0]);
            const al = AniList.entryFor(s.key, id);
            const path = p.last > 0 ? p.path : (p.first || p.path);
            return { key: s.key, season: id, partKind: kind, showName: s.name, counted: s.counted,
                     name: p.label || (kind === "season" ? "Season " + id : kind === "ova" ? "OVA" : kind === "sp" ? "Specials" : id),
                     minutes: p.secs / 60, last: p.last, path: path, secs: p.secs, length: p.length, hintYear: s.year || 0,
                     episodes: Math.max(Object.keys(p.eps).length, p.disk), watchedEp: p.watchedEp,
                     title: al ? (al.native || al.romaji) : "", total: al && al.episodes ? al.episodes : 0,
                     progress: al && al.episodes && p.watchedEp > 0 ? Math.min(1, p.watchedEp / al.episodes) : null,
                     alId: al ? al.id : 0, related: al && al.related ? al.related : [], year: al && al.year ? al.year : 0,
                     alCover: al ? al.cover : "", localCover: animeCovers[dirOf(path)] || "" };
        });
        return { key: s.key, name: s.name, counted: s.counted, parts: cards };
    }
    function cmpPart(a, b) {
        const rank = { season: 0, ova: 1, sp: 2, movie: 3 };
        if (a.partKind !== b.partKind)
            return rank[a.partKind] - rank[b.partKind];
        if (a.partKind === "season")
            return Number(a.season) - Number(b.season);
        return (a.year || 9999) - (b.year || 9999) || a.name.localeCompare(b.name);
    }
    // folders whose AniList entries are linked (sequels, side stories..) are one show
    function mergeShows(shows) {
        const root = shows.map((x, i) => i);
        const find = i => { while (root[i] !== i) { root[i] = root[root[i]]; i = root[i]; } return i; };
        const owner = {};
        shows.forEach((sh, i) => sh.parts.forEach(p => {
            if (!p.alId)
                return;
            if (owner[p.alId] !== undefined)
                root[find(i)] = find(owner[p.alId]);
            else
                owner[p.alId] = i;
        }));
        shows.forEach((sh, i) => sh.parts.forEach(p => p.related.forEach(r => {
            if (owner[r] !== undefined)
                root[find(i)] = find(owner[r]);
        })));
        const groups = {};
        shows.forEach((sh, i) => { (groups[find(i)] = groups[find(i)] || []).push(sh); });
        return Object.keys(groups).map(g => showCard(groups[g]));
    }
    function showCard(members) {
        const firstSeason = m => Math.min.apply(null, m.parts.filter(p => p.partKind === "season").map(p => Number(p.season)).concat([99]));
        members.sort((a, b) => firstSeason(a) - firstSeason(b) || a.name.localeCompare(b.name));
        const base = members[0];
        const parts = [].concat.apply([], members.map(m => m.parts)).sort(cmpPart);
        const seasons = parts.filter(p => p.partKind === "season");
        // the card shows the part watched last, else the first season
        const cur = parts.filter(p => p.last > 0).sort((a, b) => b.last - a.last)[0] || seasons[0] || parts[0];
        const single = parts.length === 1;
        parts.forEach(p => { p.cover = single ? (p.localCover || p.alCover) : (p.alCover || p.localCover); });
        const lead = ((seasons[0] || parts[0]).cover) || "";
        parts.forEach(p => { if (!p.cover) p.cover = lead; });
        const watched = {};
        seasons.forEach(p => { watched[p.season] = p.watchedEp; });
        let secs = 0, last = 0;
        members.forEach(m => m.parts.forEach(p => { secs += p.secs; last = Math.max(last, p.last); }));
        return { key: base.key, memberKeys: members.map(m => m.key), name: base.name, minutes: secs / 60,
                 counted: members.some(m => m.counted), episodes: cur.episodes, last: last, path: cur.path,
                 season: cur.season, matchKey: cur.key, partKind: cur.partKind, partName: cur.name,
                 watchedEp: cur.watchedEp, watched: watched, title: cur.title, total: cur.total,
                 progress: cur.progress, cover: cur.cover, partCount: parts.length, parts: parts };
    }

    function parsePath(path, title) {
        path = String(path || "");
        title = String(title || "");
        if (path === "")
            return { name: "Unknown", key: "unknown", episode: "", epNum: 0, season: 0 };
        // streamed: the title is all there is
        if (/^[a-z]+:\/\//i.test(path)) {
            const n = stripTags(title) || path;
            return { name: n, key: n.toLowerCase(), episode: "", epNum: 0, season: 0 };
        }
        const parts = path.split("/").filter(p => p !== "");
        const file = stripTags((parts[parts.length - 1] || "").replace(/\.[A-Za-z0-9]{2,4}$/, ""));
        let season = 0, ep = "", token = "", m;
        if ((m = file.match(/\bS(\d{1,2})\s*E(\d{1,3})(?:v\d)?\b/i))) {
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
        if (name === "") {
            // everything sat in brackets ("[Group][Show][01][1080p]"): take the longest group that isn't a tag
            const raw = parts.slice(-3).reverse().find(x => stripTags(x) === "" && /\[[^\]]*[A-Za-z]{3}/.test(x)) || "";
            const groups = (raw.match(/\[[^\]]*\]/g) || []).map(g => g.slice(1, -1))
                .filter(g => /[A-Za-z]{3}/.test(g) && !/^(DBD|BD|BDRip)/i.test(g) && !/\d{3,4}p/i.test(g));
            const best = groups.sort((x, y) => y.length - x.length)[0];
            if (best)
                name = best;
        }
        const label = ep === "" ? "" : (season > 0 ? "S" + season + "E" + ep : "E" + ep);
        return { name: name, key: name.toLowerCase(), episode: label, epNum: Number(ep) || 0, season: season };
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
        const fileIndex = {};
        animeFolders.forEach(f => {
            const fk = parsePath(f.path, "").key;
            const nm = showName(parsePath(f.path, "").name);
            (f.parts || []).forEach(p => p.files.forEach(x => { fileIndex[x[0]] = { key: fk, name: nm, part: p.id, ep: x[1] }; }));
        });
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
            // a file that sits in a scanned folder belongs to that folder's show and part (season, movie..)
            const fi = fileIndex[seg.path];
            const skey = fi ? fi.key : info.key;
            const partId = fi ? fi.part : String(info.season || 1);
            const epN = fi ? fi.ep : info.epNum;
            let s = seriesMap[skey];
            if (!s) {
                s = seriesMap[skey] = { key: skey, name: fi ? fi.name : info.name, secs: 0, counted: counted,
                                        last: 0, path: seg.path, parts: {} };
            }
            s.counted = counted;
            const pt = partOf(s, partId);
            // an episode counts as watched once it is nearly finished
            if (epN > 0 && seg.dur > 0 && (seg.pos >= 0.85 * seg.dur || seg.dur - seg.pos < 120))
                pt.watchedEp = Math.max(pt.watchedEp, epN);
            s.secs += seg.secs;
            pt.secs += seg.secs;
            if (epN > 0)
                pt.eps[epN] = true;
            if (seg.end >= pt.last) {
                pt.last = seg.end;
                pt.path = seg.path;
            }
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
                                     progress: info.progress === undefined ? null : info.progress, cover: info.cover || "", estOnly: true,
                                     url: info.id !== undefined ? "https://reader.ttsu.app/b?id=" + info.id : "" };
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
                m.url = kavitaUrl(info);
            }
        });
        kavitaNewest = kNewest;
        kavitaWork = kWork;
        rows.sort((a, b) => a.day === b.day ? b.last - a.last : (a.day < b.day ? 1 : -1));

        // anime on disk that has never been played still gets a card; its parts are the seasons, movies..
        animeFolders.forEach(f => {
            const info = parsePath(f.path, "");
            let sr = seriesMap[info.key];
            if (!sr)
                sr = seriesMap[info.key] = { key: info.key, name: showName(info.name), secs: 0, counted: true,
                                             last: 0, path: f.path, parts: {} };
            (f.parts || []).forEach(p => {
                const pt = partOf(sr, p.id);
                pt.label = p.label;
                pt.kind = p.kind;
                pt.disk = p.episodes;
                pt.first = p.path;
                pt.length = p.minutes || 0;
            });
            sr.year = f.year || 0;
        });

        const sl = mergeShows(Object.keys(seriesMap).map(k => partCards(seriesMap[k])));
        // books and manga: every volume is a part, a work with several volumes is one card with a sub-shelf
        const volLabel = (v, extra) => v ? (extra ? "Extra " : "Vol ") + v : "";
        const workCard = (kind, group, ownKey, name, list) => {
            list.sort((a, b) => (a.extra ? 1 : 0) - (b.extra ? 1 : 0) || a.vol - b.vol || a.title.localeCompare(b.title));
            const lead = (list.find(p => p.cover) || {}).cover || "";
            list.forEach(p => { p.cover = p.cover || lead; p.kind = kind; p.partKind = "volume"; });
            if (list.length === 1) {
                const p = list[0];
                return Object.assign({}, p, { key: p.ownKey, name: p.title, title: "", partKind: "", episodes: 0 });
            }
            const cur = list.filter(p => p.last > 0).sort((a, b) => b.last - a.last)[0] || list[0];
            const sum = f => list.reduce((t, p) => t + (p[f] || 0), 0);
            list.forEach(p => { p.key = (kind === "book" ? "ttuw:" : "kavitaw:") + group; });
            return { key: (kind === "book" ? "ttuw:" : "kavitaw:") + group, kind: kind, name: name, title: "", minutes: sum("minutes"),
                     counted: list.some(p => p.counted), episodes: list.length, last: Math.max.apply(null, list.map(p => p.last)),
                     path: "", chars: sum("chars"), pages: sum("pages"), progress: cur.progress, cover: cur.cover, url: cur.url,
                     partName: cur.name, partKind: "volume", partCount: list.length, parts: list, est: cur.est };
        };
        const bookGroups = {};
        const bookMeta = {};
        ttuBooks.forEach(b => { bookMeta[b.title] = b; });
        ttuBooks.forEach(b => {
            const own = "ttu:" + b.title.toLowerCase();
            if (!bookMap[own])
                bookMap[own] = { key: own, name: b.title, secs: 0, chars: 0, counted: overrides[own] !== false, last: 0,
                                 progress: b.progress === undefined ? null : b.progress, cover: b.cover || "", estOnly: false,
                                 url: b.id !== undefined ? "https://reader.ttsu.app/b?id=" + b.id : "" };
        });
        Object.keys(bookMap).forEach(k => {
            const b = bookMap[k];
            const meta = bookMeta[b.name] || ({});
            const g = meta.group || b.name.toLowerCase();
            (bookGroups[g] = bookGroups[g] || { work: meta.work || b.name, list: [] }).list.push(
                { ownKey: b.key, season: b.name, title: b.name, name: volLabel(meta.volume, meta.extra), vol: meta.volume ? Number(meta.volume) : 1e6,
                  extra: !!meta.extra, cover: b.cover || "", progress: b.progress, url: b.url, minutes: b.secs / 60, chars: b.chars,
                  last: b.last, counted: b.counted, est: b.estOnly });
        });
        Object.keys(bookGroups).forEach(g => {
            const w = bookGroups[g];
            sl.push(workCard("book", g, "", w.work, w.list));
        });
        const sess = {};
        kavitaRows.forEach(r => {
            if (!(r.secs >= 10) || hid["k:" + r.day + "|" + r.sid])
                return;
            const x = sess[r.sid] = sess[r.sid] || { secs: 0, pages: 0, last: 0 };
            x.secs += r.secs;
            x.pages += r.pages;
            x.last = Math.max(x.last, r.modified);
        });
        const mangaGroups = {};
        kavitaSeries.forEach(si => {
            const own = "kavita:" + si.work.toLowerCase();
            const x = sess[si.id] || { secs: 0, pages: 0, last: 0 };
            const g = si.group || si.work.toLowerCase();
            (mangaGroups[g] = mangaGroups[g] || { work: si.work, vol: 1e6, list: [] }).list.push(
                { ownKey: own, season: String(si.id), title: si.name, name: si.volume || "", vol: si.volume ? Number(si.volume.replace(/\D+/g, "")) : 1e6,
                  extra: false, cover: si.cover || "", progress: si.progress === undefined ? null : si.progress, url: kavitaUrl(si),
                  minutes: x.secs / 60, pages: x.pages, last: x.last, counted: overrides[own] !== false });
            const v = si.volume ? Number(si.volume.replace(/\D+/g, "")) : 1e6;
            if (v < mangaGroups[g].vol) {
                mangaGroups[g].vol = v;
                mangaGroups[g].work = si.work;
            }
        });
        Object.keys(mangaGroups).forEach(g => {
            const w = mangaGroups[g];
            sl.push(workCard("manga", g, "", w.work, w.list));
        });
        sl.forEach(c => { c.pinned = pins.indexOf(c.key) >= 0; });
        sl.sort((a, b) => (b.pinned ? 1 : 0) - (a.pinned ? 1 : 0)
                          || (a.pinned ? pins.indexOf(a.key) - pins.indexOf(b.key) : b.last - a.last));

        // streaks: a day is kept once it reaches the goal (halved on a busy day); a busy or rest day that
        // falls short only pauses the run; today doesn't break the run while open
        const met = k => dayMap[k] && dayMap[k].minutes >= goalOn(k);
        let bestRun = 0, run = 0;
        const first = Object.keys(dayMap).sort()[0];
        if (first) {
            for (let d = Tasks.dateOf(first); Tasks.keyOf(d) <= todayKey; d = Tasks.addDays(d, 1)) {
                const k = Tasks.keyOf(d);
                if (met(k))
                    run++;
                else if (!DayMarks.isMarked(k) && k !== todayKey)
                    run = 0;
                bestRun = Math.max(bestRun, run);
            }
        }
        let s = 0;
        const today = Tasks.dateOf(todayKey);
        for (let i = 0; i < 1100; i++) {
            const k = Tasks.keyOf(Tasks.addDays(today, -i));
            if (met(k))
                s++;
            else if (i > 0 && !DayMarks.isMarked(k))
                break;
        }

        days = dayMap;
        recent = rows;
        seriesList = sl;
        coverSoon.restart();
        streak = s;
        best = Math.max(bestRun, s);
    }

    // marking or clearing a day changes goals and streaks
    Connections {
        target: DayMarks
        function onMarksChanged() { imm.rebuild(); }
    }

    // ---- changes ----
    property var _undo: null

    function _save() {
        adapter.goal = goal;
        adapter.entries = entries;
        adapter.overrides = overrides;
        adapter.hidden = hidden;
        adapter.pins = pins;
        adapter.goalDay = goalDay;
        adapter.pane = pane;
        store.writeAdapter();
    }
    function togglePin(key) {
        pins = pins.indexOf(key) >= 0 ? pins.filter(k => k !== key) : [key].concat(pins);
        _save();
        rebuild();
    }
    function setPane(kind) {
        pane = kind === "mpv" || kind === "ttu" || kind === "kavita" ? kind : "";
        _save();
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
                const old = liveRaw;
                // the segment that was open has just closed: it is in the log, or soon will be
                if (liveOn && liveCounted && old.segStart > 0 && o.pid === old.pid && (o.segStart !== old.segStart || !o.playing)) {
                    const end = o.playing && o.segStart > 0 ? o.segStart : o.updated;
                    _carry = { id: old.segStart + "-" + old.pid, secs: Math.max(0, end - old.segStart) };
                    carryExpiry.restart();
                }
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
    // look for thumbnails when the set of video folders changes (or a rescan is asked for)
    Timer {
        id: coverSoon
        interval: 300
        onTriggered: {
            const dirs = [];
            imm.seriesList.forEach(s => {
                const d = imm.dirOf(s.path);
                if (d !== "" && dirs.indexOf(d) < 0)
                    dirs.push(d);
            });
            const sig = dirs.join("\n");
            if (dirs.length === 0 || sig === imm._coverDirs || coverScan.running)
                return;
            imm._coverDirs = sig;
            coverScan.command = ["python3", "-I", Quickshell.shellDir + "/scripts/anime_covers.py"].concat(dirs);
            coverScan.running = true;
        }
    }
    Connections {
        target: AniList
        function onMatchesChanged() { imm.rebuild(); }
    }
    Process {
        id: animeScan
        command: ["python3", "-I", Quickshell.shellDir + "/scripts/anime_scan.py"].concat(imm.animeRoots)
        running: true
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    if (JSON.stringify(o) !== JSON.stringify(imm.animeFolders)) {
                        imm.animeFolders = o;
                        imm.rebuild();
                    }
                } catch (e) {}
            }
        }
    }
    Process {
        id: coverScan
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const o = JSON.parse(text);
                    if (JSON.stringify(o) !== JSON.stringify(imm.animeCovers)) {
                        imm.animeCovers = o;
                        imm.rebuild();
                    }
                } catch (e) {}
            }
        }
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
            imm.pins = adapter.pins || [];
            imm.goalDay = adapter.goalDay || "";
            imm.pane = adapter.pane || "";
            imm.rebuild();
        }

        JsonAdapter {
            id: adapter
            property int goal: 60
            property var entries: []
            property var overrides: ({})
            property var hidden: []
            property var pins: []
            property string goalDay: ""
            property string pane: ""
        }
    }
}
