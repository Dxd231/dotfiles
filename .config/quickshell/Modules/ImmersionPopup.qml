pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Immersion panel, opened from the bar chip. Left: a player for whatever mpv is playing (picture,
// seek bar, transport, the current subtitle line, and whether it counts). Middle: today's ring
// against the daily goal, streak, and a form to log reading by hand. Right: the heatmap of past days
// with the recent sessions and per-series totals underneath.
BarPopup {
    id: win

    // the snackbar that offers Undo (shell.qml)
    property var copyToast: null

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 1196
    spacing: 0

    // ---- state ----
    property string tab: "recent"          // recent | series
    // a day picked on the heatmap narrows the list to it
    property string dayFilter: ""
    // heatmap window: 4-week steps back from the current week
    property int back: 0
    property bool reading: false
    property real readingP: reading ? 1 : 0
    // snaps while the panel is opening, so it never starts on the page it was left on
    Behavior on readingP { enabled: win.stage > 0; Spring { speed: "default" } }
    property int formMinutes: 30
    property bool formYesterday: false
    property int stage: 0

    // which source the lists show ("" = all). It follows the context and stays cleared once cleared
    property string ctxFilter: ""
    function srcOf(r) { return r.src || (r.kind === "book" ? "ttu" : r.kind === "manga" ? "kavita" : "mpv"); }
    // a manual reading entry belongs with the book apps
    function inContext(r, c) { return c === "" || srcOf(r) === c || (srcOf(r) === "manual" && c !== "mpv"); }
    readonly property var rows: {
        const base = tab === "series" ? Immersion.seriesList
            : (dayFilter !== "" ? Immersion.recent.filter(r => r.day === dayFilter) : Immersion.recent);
        return ctxFilter === "" ? base : base.filter(r => inContext(r, ctxFilter));
    }
    Connections {
        target: Immersion
        function onContextChanged() {
            win.ctxFilter = Immersion.context;
        }
    }
    Component.onCompleted: ctxFilter = Immersion.pane !== "" ? Immersion.pane : Immersion.context
    // the card on the left follows the context, unless a source was picked by hand (`pinned`, kept until
    // it is tapped again; saved with the rest of the immersion state)
    readonly property string pinned: Immersion.pane
    // picking a source also points the list's filter chip at it; tapping the pin again goes back to the context
    function pick(kind) {
        const off = pinned === kind;
        Immersion.setPane(off ? "" : kind);
        ctxFilter = off ? Immersion.context : kind;
    }
    readonly property string pane: pinned !== "" ? pinned : autoPane
    // a source with nothing to show falls back to the next
    readonly property string autoPane: {
        const c = Immersion.context;
        if (c === "mpv" && Mpv.hasFile)
            return "mpv";
        if (c === "kavita" && Immersion.hasKavita)
            return "kavita";
        if (c === "ttu" && Immersion.hasTtu)
            return "ttu";
        if (Mpv.hasFile)
            return "mpv";
        if (Immersion.hasKavita && (!Immersion.hasTtu || Immersion.kavitaMod > Immersion.ttuMod))
            return "kavita";
        if (Immersion.hasTtu)
            return "ttu";
        return Immersion.hasKavita ? "kavita" : "idle";
    }
    // the cover on show, and a colour taken from it that tints the left card (transparent = no cover)
    readonly property string coverPath: pane === "mpv" ? (Mpv.hasFile && Mpv.hasVideo && Mpv.thumb !== "" ? Mpv.thumb : "")
        : pane === "ttu" ? (Immersion.readerBook && Immersion.readerBook.cover ? Immersion.readerBook.cover : "")
        : pane === "kavita" ? (Immersion.mangaSeries && Immersion.mangaSeries.cover ? Immersion.mangaSeries.cover : "") : ""
    ColorQuantizer {
        id: quant
        source: win.isOpen && win.coverPath !== "" ? "file://" + win.coverPath : ""
        depth: 3
        rescaleSize: 64
    }
    readonly property color seed: {
        const cs = quant.colors;
        if (win.coverPath === "" || !cs || cs.length === 0)
            return "transparent";
        // the most colourful one that is not nearly black or white
        let best = null, score = -1;
        for (let i = 0; i < cs.length; i++) {
            const c = cs[i], l = c.hslLightness;
            const sc = c.hslSaturation * (1 - Math.abs(l - 0.5));
            if (sc > score) { score = sc; best = c; }
        }
        if (!best || best.hslSaturation < 0.12)
            return "transparent";
        // light enough to read on a dark card, dark enough on a light one
        const dark = Colors.surface.hslLightness < 0.5;
        return Qt.hsla(best.hslHue, Math.min(0.75, Math.max(0.35, best.hslSaturation)), dark ? 0.72 : 0.38, 1);
    }
    readonly property color mpvMain: win.pane === "mpv" && seed.a > 0 ? seed : Colors.primary
    readonly property color mpvOnMain: win.pane === "mpv" && seed.a > 0 ? (seed.hslLightness > 0.55 ? "#1b1b1f" : "#ffffff") : Colors.on_primary
    readonly property color cardTint: seed.a > 0 ? Qt.tint(Colors.surface_container_high, Qt.alpha(seed, 0.12)) : Colors.surface_container_high
    // what mpv is playing is known to the script (it wrote live.json for this very file)
    readonly property bool tracked: Mpv.hasFile && Immersion.liveRaw.path === Mpv.path
    readonly property var playInfo: Mpv.hasFile ? Immersion.parsePath(Mpv.path, Mpv.title) : null
    readonly property real sessionElapsed: Immersion.liveOn
        ? (Immersion.liveRaw.sessionSecs || 0) + Math.max(0, Immersion.nowSec - (Immersion.liveRaw.updated || 0)) : 0

    function dayLabel(key) {
        if (key === Tasks.todayKey)
            return "Today";
        if (key === Tasks.keyOf(Tasks.addDays(Tasks.dateOf(Tasks.todayKey), -1)))
            return "Yesterday";
        return Qt.formatDate(Tasks.dateOf(key), "ddd d MMM");
    }
    // the newest day that reached the goal: the only one the heatmap draws as a spinning star
    readonly property string lastGoalDay: {
        let best = "";
        for (const k in Immersion.days) {
            const m = k === Tasks.todayKey ? Immersion.todayMinutes : Immersion.days[k].minutes;
            if (m >= Immersion.goalOn(k) && k > best)
                best = k;
        }
        return best;
    }
    // what the heatmap shows for each day, worked out once per day and kept: a past day only changes
    // when the day data, the goal or the star day does, and then the cache starts over
    readonly property var dayCache: {
        Immersion.days;
        Immersion.goal;
        DayMarks.marks;
        lastGoalDay;
        return ({});
    }
    // heatmap shading and hover text for one day
    function dayInfo(key) {
        const cache = dayCache;
        return cache[key] || (cache[key] = dayInfoOf(key));
    }
    function dayInfoOf(key) {
        const d = Immersion.days[key];
        const m = d ? d.minutes : 0;
        if (m < 0.5)
            return { level: 0, label: "Nothing logged" };
        let label = Immersion.fmt(m);
        if (d.read > 0 && d.watch > 0.5)
            label += " · " + Immersion.fmt(d.watch) + " watched, " + Immersion.fmt(d.read) + " read";
        else if (d.read > 0)
            label += " reading";
        if (d.chars > 0)
            label += " · " + Math.round(d.chars).toLocaleString(Qt.locale(), "f", 0) + " chars";
        if (d.pages > 0)
            label += " · " + Math.round(d.pages) + " pages";
        if (d.est)
            label += " (estimated)";
        return { level: Immersion.levelOf(m, key), label: label, star: key === lastGoalDay };
    }

    function openTtu() { Quickshell.execDetached(["xdg-open", "https://reader.ttsu.app/"]); }
    // the newest ttu reading is over a week old
    readonly property bool ttuStale: Immersion.ttuLatest !== "" && !Immersion.ttuIdle && !Immersion.ttuNow
        && Immersion.ttuLatest < Tasks.keyOf(Tasks.addDays(Tasks.dateOf(Tasks.todayKey), -7))


    // ---- facts for the left card ----
    function nf(n) { return Math.round(n).toLocaleString(Qt.locale(), "f", 0); }
    function lastLabel(day, verb) { return day !== "" ? "Last " + verb + "  ·  " + dayLabel(day) : ""; }
    // anime: where in the playlist, the speed, sound only, and the time on this series
    readonly property var mpvChips: {
        const out = [];
        if (!Mpv.hasFile)
            return out;
        // no IPC link (a second mpv took the socket over): the card is read-only
        if (Mpv.viaScript)
            out.push({ icon: "link_off", text: "Controls off · restart mpv" });
        if (Mpv.playlistCount > 1)
            out.push({ icon: "playlist_play", text: (Mpv.playlistPos + 1) + " / " + Mpv.playlistCount });
        if (Math.abs(Mpv.speed - 1) > 0.01)
            out.push({ icon: "speed", text: String(Math.round(Mpv.speed * 100) / 100) + "×" });
        if (!Mpv.hasVideo)
            out.push({ icon: "music_note", text: "Audio only" });
        // subtitles from Jimaku (the panel on Alt+j in mpv has the details)
        if (Jimaku.state === "saved")
            out.push({ icon: "subtitles", text: "Jimaku subs" });
        else if (Jimaku.searching)
            out.push({ icon: "subtitles", text: "Finding subs…" });
        else if (Jimaku.state === "none")
            out.push({ icon: "subtitles_off", text: "No subs on Jimaku" });
        const cp = Lexicon.comprehension(Lexicon.subPath());
        if (cp !== "")
            out.push({ icon: "translate", text: cp, ring: Lexicon.comprehensionParts(Lexicon.subPath()) });
        const sr = playInfo ? Immersion.seriesList.find(x => x.key === playInfo.key || (x.memberKeys || []).indexOf(playInfo.key) >= 0) : null;
        if (sr)
            out.push({ icon: "schedule", text: Immersion.fmt(sr.minutes) + " in total" });
        return out;
    }
    // books: the last days spent on the one shown, what is left of it, and its facts
    readonly property var bookRecent: {
        const b = Immersion.readerBook;
        if (!b)
            return [];
        return Immersion.ttuRows.filter(r => r.title === b.title && (r.secs >= 30 || r.chars > 0))
            .slice().sort((a, c) => a.day < c.day ? 1 : -1).slice(0, 5)
            .map(r => ({ label: dayLabel(r.day),
                         detail: [r.secs >= 30 ? Immersion.fmt(r.secs / 60) : "", r.chars > 0 ? nf(r.chars) + " chars" : ""].filter(t => t !== "").join("  ·  ") + (r.est ? "  (estimated)" : "") }));
    }
    readonly property string bookEta: {
        const b = Immersion.readerBook;
        if (!b || !b.chars || b.explored === null || b.explored === undefined)
            return "";
        const left = b.chars - b.explored;
        if (left <= 0)
            return "Finished";
        // at today's pace, when there is one to go by and it gives a sensible answer
        const hours = Immersion.charsPerHour > 0 && !Immersion.ttuEstimated ? left / Immersion.charsPerHour : 0;
        return hours > 0 && hours <= 99 ? "~" + Immersion.fmt(hours * 60) + " left" : nf(left) + " chars left";
    }
    readonly property var bookChips: {
        const out = [], b = Immersion.readerBook;
        if (b && b.chars)
            out.push({ icon: "text_fields", text: nf(b.chars) + " characters" });
        if (Immersion.ttuEstimated)
            out.push({ icon: "schedule", text: "Estimated time" });
        else if (Immersion.ttuIdle)
            out.push({ icon: "timer_off", text: "Tracker off" });
        return out;
    }
    readonly property string ttuHint: Immersion.ttuEstimated
        ? "Time is estimated from your reading position. Start the tracker in ttu for exact numbers."
        : Immersion.ttuIdle
        ? "ttu has not saved any reading time yet. Turn on its tracker in the reader's statistics menu, or just read: time is then estimated from your reading position."
        : ttuStale ? "The last reading saved by ttu is from " + dayLabel(Immersion.ttuLatest) + "." : ""
    // manga: the same for the series shown
    readonly property var mangaRecent: {
        const m = Immersion.mangaSeries;
        if (!m)
            return [];
        return Immersion.kavitaRows.filter(r => r.work === m.work && (r.secs >= 30 || r.pages > 0))
            .slice().sort((a, c) => a.day < c.day ? 1 : -1).slice(0, 5)
            .map(r => ({ label: dayLabel(r.day),
                         detail: [r.secs >= 30 ? Immersion.fmt(r.secs / 60) : "", r.pages > 0 ? Math.round(r.pages) + (Math.round(r.pages) === 1 ? " page" : " pages") : ""].filter(t => t !== "").join("  ·  ") }));
    }
    readonly property string mangaEta: {
        const m = Immersion.mangaSeries;
        if (!m || !m.pages)
            return "";
        const left = m.pages - Math.min(m.pages, m.read);
        if (left <= 0)
            return "Finished";
        const t = Immersion.mangaToday;
        const hours = t.secs >= 60 && t.pages > 0 ? left / (t.pages / (t.secs / 3600)) : 0;
        return hours > 0 && hours <= 99 ? "~" + Immersion.fmt(hours * 60) + " left" : left + (left === 1 ? " page" : " pages") + " left";
    }
    readonly property var mangaChips: {
        const out = [], m = Immersion.mangaSeries;
        if (m && m.volume)
            out.push({ icon: "bookmark", text: m.volume });
        if (m && m.pages)
            out.push({ icon: "description", text: m.pages + " pages" });
        return out;
    }
    readonly property string mangaHint: Immersion.kavitaLatest !== "" && Immersion.kavitaLatest < Tasks.keyOf(Tasks.addDays(Tasks.dateOf(Tasks.todayKey), -7)) && !Immersion.kavitaNow
        ? "The last manga reading saved is from " + dayLabel(Immersion.kavitaLatest) + "." : ""
    function openKavita() { Manga.show(Immersion.mangaSeries && Immersion.mangaSeries.vol !== undefined ? Immersion.mangaSeries.vol : -1); }
    // "Continue" is only offered for .mkv files: the newest one played, even if something else came after it
    readonly property var lastMkv: {
        const segs = Immersion.segments;
        for (let i = segs.length - 1; i >= 0; i--) {
            if (/\.mkv$/i.test(String(segs[i].path || "")))
                return segs[i];
        }
        return null;
    }
    function continueText() {
        if (!lastMkv)
            return "";
        const i = Immersion.parsePath(lastMkv.path, lastMkv.title);
        // a long title would make the button wider than the card
        const name = i.name.length > 26 ? i.name.slice(0, 25) + "…" : i.name;
        return "Continue " + name + (i.episode !== "" ? " " + i.episode : "");
    }

    function openReading() {
        reading = true;
        show();
        Qt.callLater(() => titleField.forceActiveFocus());
    }
    function closeReading() {
        reading = false;
        titleField.text = "";
        charsField.text = "";
        formMinutes = 30;
        formYesterday = false;
    }
    function saveReading() {
        const key = formYesterday ? Tasks.keyOf(Tasks.addDays(Tasks.dateOf(Tasks.todayKey), -1)) : Tasks.todayKey;
        Immersion.addReading(titleField.text, formMinutes, Number(charsField.text.replace(/\D/g, "")) || 0, key);
        closeReading();
    }
    // titles read before, newest first, for one-tap re-use
    readonly property var recentTitles: {
        const seen = {}, out = [];
        for (let i = Immersion.entries.length - 1; i >= 0 && out.length < 3; i--) {
            const t = Immersion.entries[i].title;
            if (!seen[t]) {
                seen[t] = true;
                out.push(t);
            }
        }
        return out;
    }

    // ---- entrance ----
    onIsOpenChanged: {
        if (isOpen) {
            stageTimer.restart();
        } else {
            stageTimer.stop();
            stage = 0;
            reading = false;
            dayFilter = "";
        }
    }
    Timer {
        id: stageTimer
        interval: 70
        repeat: true
        onTriggered: {
            if (win.stage < 6)
                win.stage++;
            else
                stop();
        }
    }
    // the player polls the position only while somebody is looking at it
    Binding {
        target: Mpv
        property: "watching"
        value: win.isOpen
    }

    Connections {
        target: Immersion
        function onUndoable(message) {
            if (win.copyToast)
                win.copyToast.showToast(message, "Undo", () => Immersion.undo());
        }
    }

    IpcHandler {
        target: "immersion"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
        function reading(): void { win.openReading(); }
        function log(title: string, minutes: int): void { Immersion.addReading(title, minutes, 0, Tasks.todayKey); }
        function goal(minutes: int): void { Immersion.setGoal(minutes); }
        function count(series: string, on: bool): void { Immersion.setCounted(series.toLowerCase(), on); }
        function undo(): void { Immersion.undo(); }
        function tab(name: string): void { win.tab = name === "series" ? "series" : "recent"; }
        function day(key: string): void { win.dayFilter = key; }
        function remove(index: int): void { Immersion.removeRow(win.rows[index]); }
        // mpv transport, for key binds: pause, replay, skipop, subs, next, prev
        function player(cmd: string): void {
            if (cmd === "pause") Mpv.togglePause();
            else if (cmd === "replay") Mpv.replayLine();
            else if (cmd === "skipop") Mpv.skipOp();
            else if (cmd === "subs") Mpv.toggleSubs();
            else if (cmd === "next") Mpv.next();
            else if (cmd === "prev") Mpv.prev();
        }
        // jump back to the nth earlier subtitle line (0 = the one before the current)
        function line(index: int): void {
            const h = Mpv.subHistory[index];
            if (h)
                Mpv.jumpTo(h.start);
        }
        // ttu: sync() reads the browser's stats now, ttu() dumps what was read
        function sync(): void { Immersion.sync(); }
        function ttu(): string {
            return JSON.stringify({
                hasTtu: Immersion.hasTtu, idle: Immersion.ttuIdle, latest: Immersion.ttuLatest, now: Immersion.readingNow,
                title: Immersion.ttuTitle, charsToday: Immersion.charsToday, perHour: Immersion.charsPerHour,
                book: Immersion.readerBook, rows: Immersion.ttuRows.length
            });
        }
        // Kavita and the context: kavita() dumps the manga state, ctx() the context, classify() what a
        // window class and title mean, ctxset() forces a context (tests)
        function kavita(): string {
            return JSON.stringify({
                has: Immersion.hasKavita, now: Immersion.kavitaNow, latest: Immersion.kavitaLatest, work: Immersion.kavitaWork,
                series: Immersion.mangaSeries, today: Immersion.mangaToday, pagesToday: Immersion.pagesToday, rows: Immersion.kavitaRows.length
            });
        }
        function ctx(): string {
            return JSON.stringify({ context: Immersion.context, kind: Immersion.ctxKind, name: Immersion.ctxName, pane: win.pane, pinned: win.pinned, filter: win.ctxFilter, seed: String(win.seed), cover: win.coverPath });
        }
        // pin the left card to a source (mpv | ttu | kavita), or "auto" to follow the context again
        function pane(kind: string): void { Immersion.setPane(kind === "auto" ? "" : kind); }
        function classify(appId: string, title: string): string { return JSON.stringify(Immersion.classify(appId, title)); }
        function ctxset(kind: string): void { Immersion.ctxKind = kind; Immersion.ctxName = ""; }
        function parse(path: string): string { return JSON.stringify(Immersion.parsePath(path, "")); }
        function dump(): string {
            return JSON.stringify({
                today: Immersion.todayMinutes, goal: Immersion.todayGoal, streak: Immersion.streak, best: Immersion.best,
                live: { on: Immersion.liveOn, counted: Immersion.liveCounted, series: Immersion.liveInfo ? Immersion.liveInfo.name : "" },
                segments: Immersion.segments.length,
                recent: Immersion.recent.map(r => ({ day: r.day, title: r.title, detail: r.detail, min: Math.round(r.minutes * 10) / 10, counted: r.counted })),
                series: Immersion.seriesList.map(s => ({ name: s.name, min: Math.round(s.minutes * 10) / 10, eps: s.episodes, counted: s.counted }))
            });
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 620
        spacing: 16

        // ======================= left: mpv player =======================
        Rectangle {
            id: player
            Layout.preferredWidth: 380
            Layout.fillHeight: true
            radius: Motion.shapeLarge
            color: win.cardTint
            Behavior on color { ColorFade { speed: "slow" } }
            clip: true
            property real appear: win.stage >= 1 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            scale: 0.95 + 0.05 * Math.min(1, player.appear)
            transform: Translate { y: (1 - player.appear) * 14 }

            // ---- playing ----
            ColumnLayout {
                id: live
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 64
                spacing: 10
                opacity: win.pane === "mpv" && Mpv.hasFile ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }

                // the picture: squarer while playing, rounder while paused
                ClippingRectangle {
                    Layout.fillWidth: true
                    // 16:9 when there's room; gives way (before the lines history does) so nothing below is cut off
                    Layout.fillHeight: true
                    Layout.preferredHeight: Math.round(width * 9 / 16)
                    Layout.maximumHeight: Math.round(width * 9 / 16)
                    Layout.minimumHeight: 96
                    radius: Mpv.playing ? Motion.shapeLarge : 40
                    color: Colors.surface_container_highest
                    Behavior on radius { Spring {} }
                    Appear { visible: false; shown: win.stage >= 1 && live.visible; delay: 60; lift: 12; from: 0.94 }

                    Image {
                        anchors.fill: parent
                        source: Mpv.thumb !== "" && Mpv.hasVideo ? "file://" + Mpv.thumb : ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        opacity: status === Image.Ready ? 1 : 0
                        Behavior on opacity { Fade {} }
                    }
                    ShapeBadge {
                        anchors.centerIn: parent
                        width: 64
                        height: 64
                        shapeRest: "cookie4"
                        spinning: Mpv.playing && win.isOpen
                        color: Colors.primary_container
                        opacity: Mpv.thumb === "" || !Mpv.hasVideo ? 1 : 0
                        Behavior on opacity { Fade {} }
                        Icon { anchors.centerIn: parent; size: 28; name: Mpv.hasVideo ? "movie" : "music_note"; color: Colors.on_primary_container }
                    }
                    // the same pill the book cards wear while they are being read
                    Rectangle {
                        anchors.top: parent.top
                        anchors.right: parent.right
                        anchors.margins: 10
                        height: 28
                        // the label changes length; the pill eases to it (a spring can undershoot, so clamp)
                        property real fit: stateLabel.implicitWidth + 24
                        Behavior on fit { Spring { speed: "fast" } }
                        width: Math.max(0, fit)
                        radius: 14
                        color: Mpv.playing ? win.mpvMain : Qt.alpha(Colors.surface_container_highest, 0.92)
                        Behavior on color { ColorFade {} }
                        StyledText {
                            id: stateLabel
                            anchors.centerIn: parent
                            role: "labelLarge"
                            emphasized: true
                            color: Mpv.playing ? win.mpvOnMain : Colors.on_surface
                            text: Mpv.playing ? "Playing" : "Paused"
                        }
                    }
                }

                ColumnLayout {
                    Appear { visible: false; shown: win.stage >= 1 && live.visible; delay: 110; lift: 12; from: 0.94 }
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        jp: true
                        role: "titleMedium"
                        emphasized: true
                        elide: Text.ElideRight
                        text: win.playInfo ? win.playInfo.name : ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        jp: true
                        role: "bodyMedium"
                        color: Colors.on_surface_variant
                        elide: Text.ElideRight
                        text: win.playInfo && win.playInfo.episode !== "" ? win.playInfo.episode + "  ·  " + Mpv.title : Mpv.title
                    }
                    Collapse {
                        open: win.mpvChips.length > 0
                        Layout.fillWidth: true
                        Layout.topMargin: 6
                        Flow {
                            spacing: 6
                            move: Transition { Spring { properties: "x,y"; speed: "default" } }
                            Repeater {
                                model: win.mpvChips.length
                                delegate: ImmersionChip {
                                    required property int index
                                    readonly property var d: win.mpvChips[index] || ({})
                                    icon: d.icon || ""
                                    text: d.text || ""
                                    ring: d.ring || null
                                }
                            }
                        }
                    }
                }

                // seek bar and times
                ColumnLayout {
                    Appear { visible: false; shown: win.stage >= 1 && live.visible; delay: 160; lift: 12; from: 0.94 }
                    Layout.fillWidth: true
                    spacing: 0
                    Slider {
                        Layout.fillWidth: true
                        size: "xs"
                        from: 0
                        to: Math.max(1, Mpv.duration)
                        enabled: Mpv.connected
                        value: Mpv.position
                        onMoved: v => Mpv.seekTo(v)
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        StyledText {
                            role: "labelMedium"
                            color: Colors.on_surface_variant
                            text: Immersion.fmtClock(Mpv.position)
                        }
                        Item { Layout.fillWidth: true }
                        StyledText {
                            role: "labelMedium"
                            color: Colors.on_surface_variant
                            text: "-" + Immersion.fmtClock(Math.max(0, Mpv.duration - Mpv.position))
                        }
                    }
                }

                // transport
                RowLayout {
                    Appear { visible: false; shown: win.stage >= 1 && live.visible; delay: 210; lift: 12; from: 0.94 }
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    IconButton {
                        size: "s"
                        style: "tonal"
                        icon: "replay"
                        enabled: Mpv.connected
                        onClicked: Mpv.replayLine()
                    }
                    IconButton {
                        size: "m"
                        style: "tonal"
                        icon: "skip_previous"
                        enabled: Mpv.connected && Mpv.playlistCount > 1
                        onClicked: Mpv.prev()
                    }
                    IconButton {
                        id: play
                        size: "m"
                        style: "filled"
                        icon: Mpv.playing ? "pause" : "play_arrow"
                        iconSize: 28
                        widthMode: "wide"
                        enabled: Mpv.connected
                        // round while paused, square while playing
                        restRadius: Mpv.playing ? Motion.shapeLarge : height / 2
                        property bool spinSpring: true
                        iconKick: false
                        Behavior on iconRotation { enabled: play.spinSpring; Spring {} }
                        Behavior on iconScale { enabled: play.spinSpring; Spring {} }
                        Connections {
                            target: Mpv
                            function onPausedChanged() {
                                play.spinSpring = false;
                                play.iconRotation = -90;
                                play.iconScale = 0.4;
                                play.spinSpring = true;
                                play.iconRotation = 0;
                                play.iconScale = 1;
                            }
                        }
                        onClicked: Mpv.togglePause()
                    }
                    IconButton {
                        size: "m"
                        style: "tonal"
                        icon: "skip_next"
                        enabled: Mpv.connected && Mpv.playlistCount > 1
                        onClicked: Mpv.next()
                    }
                    IconButton {
                        size: "s"
                        style: "tonal"
                        icon: "fast_forward"
                        enabled: Mpv.connected
                        onClicked: Mpv.skipOp()
                    }
                }

                // the line being said: a caption that is only as tall as it needs to be
                Rectangle {
                    id: caption
                    Appear { visible: false; shown: win.stage >= 1 && live.visible; delay: 260; lift: 12; from: 0.94 }
                    Layout.fillWidth: true
                    visible: Mpv.connected && (Mpv.hasVideo || Mpv.subText !== "" || Mpv.subHistory.length > 0)
                    Layout.preferredHeight: Math.max(52, Math.min(104, curLine.implicitHeight + 24))
                    Behavior on Layout.preferredHeight { Spring { speed: "default" } }
                    radius: Motion.shapeLarge
                    color: Colors.surface_container
                    clip: true

                    // 0 -> 1 on every new line: the old text rises out, the new one comes up under it
                    property real slide: 1
                    property bool slideSpring: true
                    property string shownText: Mpv.subText
                    property string oldText: ""
                    Behavior on slide { enabled: caption.slideSpring; Spring { speed: "default" } }
                    Connections {
                        target: Mpv
                        function onSubSeqChanged() {
                            caption.oldText = caption.shownText;
                            caption.shownText = Mpv.subText;
                            caption.slideSpring = false;
                            caption.slide = 0;
                            caption.slideSpring = true;
                            caption.slide = 1;
                        }
                        function onSubTextChanged() {
                            if (Mpv.subText === "") {
                                caption.oldText = "";
                                caption.shownText = "";
                            }
                        }
                    }

                    Item {
                        id: captionText
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 52

                        StyledText {
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: -24 * caption.slide
                            jp: true
                            role: "titleMedium"
                            emphasized: true
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: caption.oldText
                            opacity: Math.max(0, 1 - caption.slide * 1.6) * (Mpv.subsVisible ? 1 : 0)
                        }
                        StyledText {
                            id: curLine
                            width: parent.width
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 24 * (1 - caption.slide)
                            jp: true
                            role: "titleMedium"
                            emphasized: true
                            horizontalAlignment: Text.AlignLeft
                            wrapMode: Text.WordWrap
                            maximumLineCount: 2
                            elide: Text.ElideRight
                            text: caption.shownText
                            opacity: (Mpv.subsVisible && caption.shownText !== "" ? Math.min(1, caption.slide * 1.6) : 0) * (Mpv.subLive ? 1 : 0.55)
                            Behavior on opacity { enabled: caption.slide >= 1; Fade {} }
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            opacity: Mpv.subsVisible ? (caption.shownText === "" ? 0.7 : 0) : 0.7
                            Behavior on opacity { Fade {} }
                            text: Mpv.subsVisible ? "No subtitles yet" : "Subtitles hidden"
                        }
                    }
                    IconButton {
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        size: "xs"
                        icon: "subtitles"
                        checkable: true
                        checked: Mpv.subsVisible
                        onClicked: Mpv.toggleSubs()
                    }
                }

                // the lines before it, fading with age; click one to hear it again
                Item {
                    id: history
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    clip: true
                    // as many 32 px rows as the card has room for, three at most
                    readonly property int fit: Math.max(0, Math.min(3, Math.floor(height / 32)))
                    Column {
                      width: parent.width
                      spacing: 2
                    Repeater {
                        // a slot count: rows stay put and their text changes as lines come in
                        model: 3
                        delegate: Item {
                            id: hist
                            required property int index
                            readonly property var h: Mpv.subHistory[index]
                            width: history.width
                            readonly property bool room: index < history.fit
                            height: h && room ? 30 : 0
                            visible: !!h && room
                            opacity: h ? [0.75, 0.55, 0.38][index] : 0
                            // pops up from below whenever a new line pushes it down a slot
                            property real nudge: 0
                            property bool nudgeSpring: true
                            Behavior on nudge { enabled: hist.nudgeSpring; Spring { speed: "default" } }
                            transform: Translate { y: hist.nudge * -10 }
                            Connections {
                                target: Mpv
                                function onSubSeqChanged() {
                                    hist.nudgeSpring = false;
                                    hist.nudge = -1;
                                    hist.nudgeSpring = true;
                                    hist.nudge = 0;
                                }
                            }
                            HoverHandler { id: histHover }
                            Rectangle {
                                anchors.fill: parent
                                radius: Motion.shapeMedium
                                color: histHover.hovered ? Colors.surface_container_highest : "transparent"
                                Behavior on color { ColorFade {} }
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 12
                                anchors.rightMargin: 8
                                spacing: 8
                                StyledText {
                                    Layout.fillWidth: true
                                    jp: true
                                    role: "bodyMedium"
                                    emphasized: true
                                    color: Colors.on_surface_variant
                                    elide: Text.ElideRight
                                    text: hist.h ? hist.h.text : ""
                                }
                                Icon {
                                    size: 16
                                    name: "replay"
                                    color: Colors.on_surface_variant
                                    opacity: histHover.hovered ? 1 : 0
                                    Behavior on opacity { Fade {} }
                                }
                            }
                            TapHandler {
                                onTapped: if (hist.h) Mpv.jumpTo(hist.h.start)
                            }
                        }
                    }
                    }
                }

                // does this count?
                Collapse {
                    open: win.tracked
                    Layout.alignment: Qt.AlignHCenter
                    Chip {
                        kind: "filter"
                        icon: "block"
                        selected: Immersion.liveCounted
                        text: win.tracked && Immersion.liveInfo
                            ? (Immersion.liveCounted ? "Counting" : "Not counting") + "  ·  "
                              + Immersion.reasonOf(Immersion.liveInfo.key, Immersion.liveRaw.alang, Immersion.liveRaw.slang, Immersion.liveRaw.title + " " + Immersion.liveRaw.path)
                            : ""
                        onClicked: if (Immersion.liveInfo) Immersion.setCounted(Immersion.liveInfo.key, !Immersion.liveCounted)
                        Appear { shown: win.tracked && live.visible; delay: 320; lift: 10; from: 0.85 }
                    }
                }
            }

            // ---- anime: nothing playing ----
            ImmersionEmpty {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 24
                width: parent.width - 48
                accent: "primary"
                icon: "movie"
                active: win.isOpen && win.pane === "mpv" && !Mpv.hasFile
                title: Mpv.connected ? "mpv is idle" : "Nothing playing in mpv"
                text: "Whatever you play with Japanese audio is tracked on its own."
                actions: win.lastMkv ? [{ id: "continue", icon: "play_arrow", text: win.continueText() }] : []
                opacity: win.pane === "mpv" && !Mpv.hasFile ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onTriggered: id => { if (id === "continue" && win.lastMkv) Mpv.resume(win.lastMkv.path); }
            }

            // ---- a book (ttu) ----
            ImmersionBookCard {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 64
                accent: "tertiary"
                icon: "auto_stories"
                seed: win.pane === "ttu" ? win.seed : "transparent"
                active: win.isOpen
                shown: win.pane === "ttu" && win.isOpen
                cover: Immersion.readerBook && Immersion.readerBook.cover ? Immersion.readerBook.cover : ""
                title: Immersion.readerBook ? Immersion.readerBook.title : ""
                subtitle: "ttu reader"
                live: Immersion.ttuNow
                status: win.lastLabel(Immersion.ttuLatest, "read")
                chips: win.bookChips
                progress: Immersion.readerBook ? Immersion.readerBook.progress : null
                progressText: {
                    const b = Immersion.readerBook;
                    if (!b || b.progress === null || b.progress === undefined)
                        return "";
                    const pct = Math.round(b.progress * 100) + "% read";
                    return b.chars && b.explored !== null && b.explored !== undefined ? pct + "  ·  " + win.nf(b.explored) + " of " + win.nf(b.chars) : pct;
                }
                eta: win.bookEta
                tiles: [
                    { v: (Immersion.ttuEstimated ? "~" : "") + Immersion.fmt(Immersion.todayRead), l: "read today" },
                    { v: (Immersion.ttuEstimated ? "~" : "") + win.nf(Immersion.charsToday), l: "characters" },
                    { v: Immersion.charsPerHour > 0 ? (Immersion.ttuEstimated ? "~" : "") + Immersion.charsPerHour.toLocaleString(Qt.locale(), "f", 0) : "–", l: "chars / h" }
                ]
                recent: win.bookRecent
                hint: win.ttuHint
                actionIcon: "auto_stories"
                actionText: "Open ttu"
                opacity: win.pane === "ttu" && Immersion.hasTtu ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onAction: win.openTtu()
            }
            ImmersionEmpty {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 24
                width: parent.width - 48
                accent: "tertiary"
                icon: "auto_stories"
                active: win.isOpen && win.pane === "ttu" && !Immersion.hasTtu
                title: "No book yet"
                text: "Read something in ttu: its cover, progress and reading time show up here."
                actions: [{ id: "open", icon: "auto_stories", text: "Open ttu" }]
                opacity: win.pane === "ttu" && !Immersion.hasTtu ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onTriggered: win.openTtu()
            }

            // ---- manga (the reader; named kavita internally) ----
            ImmersionBookCard {
                anchors.fill: parent
                anchors.margins: 16
                anchors.topMargin: 64
                accent: "secondary"
                icon: "menu_book"
                seed: win.pane === "kavita" ? win.seed : "transparent"
                active: win.isOpen
                shown: win.pane === "kavita" && win.isOpen
                cover: Immersion.mangaSeries && Immersion.mangaSeries.cover ? Immersion.mangaSeries.cover : ""
                title: Immersion.mangaSeries ? Immersion.mangaSeries.work : ""
                subtitle: "Manga reader"
                live: Immersion.kavitaNow
                status: win.lastLabel(Immersion.kavitaLatest, "read")
                chips: win.mangaChips
                progress: Immersion.mangaSeries ? Immersion.mangaSeries.progress : null
                progressText: {
                    const m = Immersion.mangaSeries;
                    return m && m.pages > 0 ? "page " + Math.min(m.pages, m.read) + " of " + m.pages : "";
                }
                eta: win.mangaEta
                tiles: [
                    { v: Immersion.fmt(Immersion.mangaToday.secs / 60), l: "read today" },
                    { v: String(Math.round(Immersion.mangaToday.pages)), l: "pages" },
                    { v: Immersion.mangaToday.secs >= 60 ? String(Math.round(Immersion.mangaToday.pages / (Immersion.mangaToday.secs / 3600))) : "–", l: "pages / h" }
                ]
                recent: win.mangaRecent
                hint: win.mangaHint
                actionIcon: "menu_book"
                actionText: "Read"
                opacity: win.pane === "kavita" && Immersion.hasKavita ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onAction: win.openKavita()
            }
            ImmersionEmpty {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 24
                width: parent.width - 48
                accent: "secondary"
                icon: "menu_book"
                active: win.isOpen && win.pane === "kavita" && !Immersion.hasKavita
                title: "No manga yet"
                text: "Read manga in the shell: the cover, your page and the reading time show up here."
                actions: [{ id: "open", icon: "menu_book", text: "Read manga" }]
                opacity: win.pane === "kavita" && !Immersion.hasKavita ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onTriggered: win.openKavita()
            }

            // ---- nothing anywhere yet ----
            ImmersionEmpty {
                anchors.centerIn: parent
                anchors.verticalCenterOffset: 24
                width: parent.width - 48
                accent: "primary"
                icon: "auto_awesome"
                active: win.isOpen && win.pane === "idle"
                title: "Nothing to show yet"
                text: "Play something in mpv with Japanese audio, or read in ttu or the manga reader."
                actions: (win.lastMkv ? [{ id: "continue", icon: "play_arrow", text: win.continueText() }] : [])
                    .concat([{ id: "ttu", icon: "auto_stories", text: "Open ttu", style: "text" }, { id: "kavita", icon: "menu_book", text: "Read manga", style: "text" }])
                opacity: win.pane === "idle" ? 1 : 0
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                onTriggered: id => {
                    if (id === "continue" && win.lastMkv)
                        Mpv.resume(win.lastMkv.path);
                    else if (id === "ttu")
                        win.openTtu();
                    else if (id === "kavita")
                        win.openKavita();
                }
            }

            // which media the card shows; floats over the picture so it costs the layout nothing
            ImmersionSourceSwitch {
                id: sourceSwitch
                // in a strip of its own above the picture or cover
                x: 16
                y: 16
                z: 5
                current: win.pane === "idle" ? "mpv" : win.pane
                pinned: win.pinned !== ""
                liveMpv: Mpv.playing
                liveTtu: Immersion.ttuNow
                liveKavita: Immersion.kavitaNow
                onPicked: kind => win.pick(kind)
            }
        }

        // ======================= middle: today / log reading =======================
        Item {
            id: middle
            Layout.preferredWidth: 300
            Layout.fillHeight: true

            // ---- today ----
            ColumnLayout {
                id: todayPage
                anchors.fill: parent
                spacing: 12
                opacity: Math.max(0, Math.min(1, 1 - win.readingP * 1.6))
                visible: opacity > 0.02
                transform: Translate { x: -win.readingP * 50 }

                RowLayout {
                    id: todayHeader
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    property real appear: win.stage >= 2 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    transform: Translate { y: (1 - todayHeader.appear) * 12 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            role: "headlineSmall"
                            emphasized: true
                            text: "Immersion"
                        }
                        StyledText {
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            elide: Text.ElideRight
                            Layout.fillWidth: true
                            text: Immersion.liveOn && Immersion.liveCounted ? "Listening now · " + Immersion.fmtClock(win.sessionElapsed)
                                : Immersion.readingNow ? "Reading now · " + Immersion.readingTitle
                                : Qt.formatDate(Tasks.dateOf(Tasks.todayKey), "dddd d MMM")
                        }
                    }
                    Button {
                        icon: "add"
                        text: "Read"
                        style: "tonal"
                        onClicked: win.openReading()
                    }
                }

                // today's ring
                Item {
                    id: ringBox
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 232
                    Layout.preferredHeight: 232
                    property real appear: win.stage >= 3 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    // the goal was just crossed: the ring swells and a few shapes fly out of it
                    property real kick: 0
                    property real burst: 1
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    scale: (0.75 + 0.25 * appear) * (1 + 0.08 * kick)
                    // the lap being filled past the goal (0 = the second lap) picks the colour of the arc on top
                    readonly property int lap: Math.floor(Immersion.overLaps)
                    readonly property color lapColor: lap % 2 === 0 ? Colors.primary : Colors.secondary

                    SequentialAnimation {
                        id: kickAnim
                        NumberAnimation { target: ringBox; property: "kick"; to: 1; duration: 1 }
                        Spring { target: ringBox; property: "kick"; to: 0; speed: "fast" }
                    }
                    NumberAnimation {
                        id: burstAnim
                        target: ringBox
                        property: "burst"
                        from: 0
                        to: 1
                        duration: 700
                        easing.type: Easing.OutCubic
                    }
                    Connections {
                        target: Immersion
                        function onGoalReached() {
                            if (win.isOpen) {
                                kickAnim.restart();
                                burstAnim.restart();
                            }
                        }
                    }

                    WavyRing {
                        anchors.fill: parent
                        // fills in with the card when the panel opens
                        value: Math.min(1, Immersion.todayMinutes / Math.max(1, Immersion.todayGoal)) * Math.max(0, Math.min(1, ringBox.appear))
                        idleDrift: win.isOpen ? 1.5 : 0
                        quicken: true
                        pace: Immersion.todayMinutes / Math.max(1, Immersion.todayGoal)
                        waving: ((Immersion.liveOn && Immersion.liveCounted) || Immersion.readingNow) && win.isOpen
                        overdrive: Immersion.overdrive && win.isOpen
                        overValue: Immersion.overLaps - Math.floor(Immersion.overLaps)
                        overColor: ringBox.lapColor
                        Behavior on overColor { ColorFade {} }
                        activeColor: Immersion.goalMet ? Colors.tertiary : Colors.primary
                        Behavior on activeColor { ColorFade {} }
                    }
                    // the burst: shapes thrown outward from the ring
                    Repeater {
                        model: 8
                        delegate: MorphShape {
                            required property int index
                            readonly property real ang: index / 8 * Math.PI * 2
                            readonly property real dist: 104 + 28 * ringBox.burst
                            width: 12
                            height: 12
                            shape: index % 3 === 0 ? "sunny" : index % 3 === 1 ? "cookie9" : "cookie4"
                            fromShape: shape
                            color: index % 2 === 0 ? Colors.tertiary : Colors.primary
                            x: ringBox.width / 2 + Math.sin(ang) * dist - 6
                            y: ringBox.height / 2 - Math.cos(ang) * dist - 6
                            scale: ringBox.burst >= 1 ? 0 : 1 - 0.6 * ringBox.burst
                            opacity: ringBox.burst >= 1 ? 0 : 1 - ringBox.burst * ringBox.burst
                            z: 3
                        }
                    }
                    ColumnLayout {
                        anchors.centerIn: parent
                        spacing: 0
                        RollingDigits {
                            Layout.alignment: Qt.AlignHCenter
                            pixelSize: 56
                            // reads 0 until the card has landed, then rolls once to today's value
                            text: win.stage >= 3 ? String(Math.floor(Immersion.todayMinutes)) : "0"
                            color: Immersion.overdrive ? ringBox.lapColor : Immersion.goalMet ? Colors.tertiary : Colors.on_surface
                        }
                        // past the goal: how far, with a bolt
                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 4
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: Immersion.overdrive ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                size: 16
                                name: "bolt"
                                color: ringBox.lapColor
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "labelLarge"
                                emphasized: Immersion.overdrive
                                color: Immersion.overdrive ? ringBox.lapColor : Colors.on_surface_variant
                                text: Immersion.overdrive ? "+" + Math.max(1, Math.round(Immersion.todayMinutes - Immersion.todayGoal)) + " min over"
                                    : Immersion.goalMet ? "goal reached"
                                    : Immersion.todayMinutes < 1 && !Immersion.liveOn ? Immersion.todayGoal + " min to go" : "of " + Immersion.todayGoal + " min"
                            }
                        }
                    }
                }

                // daily goal
                RowLayout {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 8
                    IconButton { icon: "remove"; style: "tonal"; size: "xs"; enabled: Immersion.goal > 10; onClicked: Immersion.setGoal(Immersion.goal - 10) }
                    StyledText {
                        Layout.preferredWidth: 96
                        horizontalAlignment: Text.AlignHCenter
                        role: "labelLarge"
                        color: Colors.on_surface_variant
                        text: "Goal " + Immersion.goal + " min"
                    }
                    IconButton { icon: "add"; style: "tonal"; size: "xs"; enabled: Immersion.goal < 600; onClicked: Immersion.setGoal(Immersion.goal + 10) }
                }

                // streak and best
                RowLayout {
                    id: pills
                    Layout.fillWidth: true
                    spacing: 8
                    property real appear: win.stage >= 4 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    transform: Translate { y: (1 - pills.appear) * 12 }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: Motion.shapeLarge
                        color: Colors.tertiary_container
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            // the cookie turns slowly once today's goal is met: the streak is safe
                            ShapeBadge {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                shapeRest: "cookie4"
                                shapeActive: "cookie9"
                                active: Immersion.goalMet
                                spinning: Immersion.goalMet && win.isOpen
                                spinSpeed: 18
                                color: Colors.tertiary
                                Icon { anchors.centerIn: parent; size: 18; name: "local_fire_department"; color: Colors.on_tertiary }
                            }
                            ColumnLayout {
                                spacing: 0
                                Row {
                                    RollingDigits { pixelSize: 16; color: Colors.on_tertiary_container; text: String(Immersion.streak) }
                                    StyledText { role: "titleMedium"; emphasized: true; color: Colors.on_tertiary_container; text: Immersion.streak === 1 ? " day" : " days" }
                                }
                                StyledText { role: "labelSmall"; color: Colors.on_tertiary_container; text: "streak" }
                            }
                        }
                    }
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 56
                        radius: Motion.shapeLarge
                        color: Colors.secondary_container
                        RowLayout {
                            anchors.centerIn: parent
                            spacing: 8
                            ShapeBadge {
                                Layout.preferredWidth: 34
                                Layout.preferredHeight: 34
                                shapeRest: "star4"
                                shapeActive: "star4"
                                color: Colors.secondary
                                Icon { anchors.centerIn: parent; size: 16; name: "star"; color: Colors.on_secondary }
                            }
                            ColumnLayout {
                                spacing: 0
                                Row {
                                    RollingDigits { pixelSize: 16; color: Colors.on_secondary_container; text: String(Immersion.best) }
                                    StyledText { role: "titleMedium"; emphasized: true; color: Colors.on_secondary_container; text: Immersion.best === 1 ? " day" : " days" }
                                }
                                StyledText { role: "labelSmall"; color: Colors.on_secondary_container; text: "best" }
                            }
                        }
                    }
                }

                // watching vs reading today
                ColumnLayout {
                    id: split
                    Layout.fillWidth: true
                    spacing: 6
                    property real appear: win.stage >= 5 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    transform: Translate { y: (1 - split.appear) * 12 }
                    readonly property real total: Immersion.todayWatch + Immersion.todayRead

                    // two pills with a gap: watching and reading, each carrying its icon and time (an empty day
                    // shows both, faint)
                    Item {
                        id: splitBar
                        Layout.fillWidth: true
                        Layout.preferredHeight: 34
                        readonly property real usable: width - 4
                        readonly property bool empty: split.total <= 0
                        readonly property real watchW: empty ? usable / 2 : Math.max(70, Math.min(usable - 70, usable * Immersion.todayWatch / split.total))
                        readonly property bool watchOn: Immersion.todayWatch > 0 || empty
                        readonly property bool readOn: Immersion.todayRead > 0 || empty
                        Rectangle {
                            id: watchBar
                            height: parent.height
                            radius: height / 2
                            color: splitBar.empty ? Colors.surface_container_highest : Colors.primary
                            opacity: splitBar.watchOn ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            width: splitBar.watchOn && splitBar.readOn ? splitBar.watchW : splitBar.width
                            clip: true
                            Behavior on width { Spring {} }
                            Behavior on color { ColorFade {} }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "movie"; color: splitBar.empty ? Colors.on_surface_variant : Colors.on_primary }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: watchBar.width >= 140 ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    role: "labelLarge"
                                    emphasized: true
                                    color: splitBar.empty ? Colors.on_surface_variant : Colors.on_primary
                                    text: "Watching"
                                }
                                RollingDigits {
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: watchBar.width >= 70 ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    pixelSize: 14
                                    color: splitBar.empty ? Colors.on_surface_variant : Colors.on_primary
                                    text: Immersion.fmt(Immersion.todayWatch)
                                }
                            }
                        }
                        Rectangle {
                            id: readBar
                            height: parent.height
                            radius: height / 2
                            color: splitBar.empty ? Colors.surface_container_highest : Colors.tertiary
                            opacity: splitBar.readOn ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            x: splitBar.watchOn ? watchBar.width + 4 : 0
                            width: Math.max(0, splitBar.watchOn ? splitBar.width - watchBar.width - 4 : splitBar.width)
                            clip: true
                            Behavior on color { ColorFade {} }
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon { anchors.verticalCenter: parent.verticalCenter; size: 16; name: "auto_stories"; color: splitBar.empty ? Colors.on_surface_variant : Colors.on_tertiary }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: readBar.width >= 140 ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    role: "labelLarge"
                                    emphasized: true
                                    color: splitBar.empty ? Colors.on_surface_variant : Colors.on_tertiary
                                    text: "Reading"
                                }
                                RollingDigits {
                                    anchors.verticalCenter: parent.verticalCenter
                                    opacity: readBar.width >= 70 ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    pixelSize: 14
                                    color: splitBar.empty ? Colors.on_surface_variant : Colors.on_tertiary
                                    text: Immersion.fmt(Immersion.todayRead)
                                }
                            }
                        }
                    }
                    // characters read today, and how fast
                    Collapse {
                        open: Immersion.charsToday > 0
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        Layout.rightMargin: 4
                        RowLayout {
                            StyledText {
                                role: "labelLarge"
                                color: Colors.on_surface_variant
                                text: Math.round(Immersion.charsToday).toLocaleString(Qt.locale(), "f", 0) + " characters"
                            }
                            Item { Layout.fillWidth: true }
                            StyledText {
                                role: "labelLarge"
                                color: Colors.on_surface_variant
                                opacity: Immersion.charsPerHour > 0 ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                text: Immersion.charsPerHour.toLocaleString(Qt.locale(), "f", 0) + " / h"
                            }
                        }
                    }
                }
                Item { Layout.fillHeight: true }
            }

            // ---- log reading ----
            ColumnLayout {
                id: readingPage
                anchors.fill: parent
                spacing: 12
                opacity: Math.max(0, Math.min(1, win.readingP * 1.6 - 0.6))
                visible: opacity > 0.02
                transform: Translate { x: (1 - win.readingP) * 50 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    IconButton { icon: "arrow_back"; size: "xs"; onClicked: win.closeReading() }
                    StyledText {
                        Layout.fillWidth: true
                        role: "headlineSmall"
                        emphasized: true
                        text: "Log reading"
                    }
                }

                TextField {
                    id: titleField
                    Layout.fillWidth: true
                    label: "What did you read?"
                    leadingIcon: "auto_stories"
                    onAccepted: charsField.forceActiveFocus()
                }
                Collapse {
                    open: win.recentTitles.length > 0
                    Layout.fillWidth: true
                    Flow {
                        spacing: 6
                        Repeater {
                            model: win.recentTitles
                            delegate: Chip {
                                required property string modelData
                                kind: "suggestion"
                                text: modelData.length > 22 ? modelData.slice(0, 21) + "…" : modelData
                                onClicked: titleField.text = modelData
                            }
                        }
                    }
                }

                // minutes
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    spacing: 4
                    StyledText { role: "labelLarge"; color: Colors.on_surface_variant; text: "Time" }
                    RowLayout {
                        spacing: 8
                        IconButton { icon: "remove"; style: "tonal"; size: "xs"; enabled: win.formMinutes > 5; onClicked: win.formMinutes = Math.max(5, win.formMinutes - 5) }
                        RollingDigits {
                            Layout.preferredWidth: implicitWidth + 4
                            pixelSize: 28
                            text: String(win.formMinutes)
                        }
                        StyledText { role: "titleMedium"; color: Colors.on_surface_variant; text: "min" }
                        IconButton { icon: "add"; style: "tonal"; size: "xs"; enabled: win.formMinutes < 600; onClicked: win.formMinutes = Math.min(600, win.formMinutes + 5) }
                        Item { Layout.fillWidth: true }
                    }
                    RowLayout {
                        spacing: 6
                        Repeater {
                            model: [15, 30, 60, 90]
                            delegate: Chip {
                                required property int modelData
                                kind: "filter"
                                selected: win.formMinutes === modelData
                                text: String(modelData)
                                onClicked: win.formMinutes = modelData
                            }
                        }
                    }
                }

                TextField {
                    id: charsField
                    Layout.fillWidth: true
                    label: "Characters (optional)"
                    leadingIcon: "edit_note"
                    onAccepted: win.saveReading()
                }

                RowLayout {
                    Layout.leftMargin: 4
                    spacing: 6
                    Chip { kind: "filter"; text: "Today"; selected: !win.formYesterday; onClicked: win.formYesterday = false }
                    Chip { kind: "filter"; text: "Yesterday"; selected: win.formYesterday; onClicked: win.formYesterday = true }
                }

                Item { Layout.fillHeight: true }
                RowLayout {
                    Layout.alignment: Qt.AlignRight
                    spacing: 8
                    Button { style: "text"; text: "Cancel"; onClicked: win.closeReading() }
                    Button { icon: "check"; text: "Add"; onClicked: win.saveReading() }
                }
            }
        }

        // ======================= right: heatmap + history =======================
        Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Motion.shapeLarge
            color: Colors.surface_container_high
            clip: true
            property real appear: win.stage >= 3 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            transform: Translate { y: (1 - card.appear) * 14 }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 10

                // heatmap window controls
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        role: "titleMedium"
                        emphasized: true
                        text: heat.cells.length > 0
                            ? Qt.formatDate(heat.cells[0].date, "MMM yyyy") + "  –  " + Qt.formatDate(heat.cells[heat.cells.length - 1].date, "MMM yyyy")
                            : ""
                    }
                    // the day picked on the heatmap: up here, beside the range it belongs to, where the Recent / Series
                    // row has no room for it
                    Collapse {
                        horizontal: true
                        open: win.dayFilter !== ""
                        Chip {
                            id: dayChip
                            kind: "input"
                            icon: "check"
                            trailingIcon: "close"
                            text: win.dayFilter !== "" ? win.dayLabel(win.dayFilter) : ""
                            onTrailingClicked: win.dayFilter = ""
                            onClicked: win.dayFilter = ""
                            Appear { shown: dayChip.visible; lift: 0; from: 0.7 }
                        }
                    }
                    IconButton { icon: "chevron_left"; style: "tonal"; size: "xs"; onClicked: win.back += 1 }
                    IconButton { icon: "chevron_right"; style: "tonal"; size: "xs"; enabled: win.back > 0; onClicked: win.back -= 1 }
                }

                DayMarkPicker {
                    Layout.fillWidth: true
                    key: win.dayFilter !== "" ? win.dayFilter : Tasks.todayKey
                }

                HeatmapGrid {
                    id: heat
                    Layout.alignment: Qt.AlignHCenter
                    weeks: 20
                    endOffset: win.back * 4
                    dayInfo: win.dayInfo
                    selectedKey: win.dayFilter
                    onDaySelected: key => {
                        win.dayFilter = win.dayFilter === key ? "" : key;
                        // the day narrows the Recent list, so show it
                        if (win.dayFilter !== "")
                            win.tab = "recent";
                    }
                }

                // Recent | Series, with a pill that slides between them
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Rectangle {
                        id: tabs
                        Layout.preferredWidth: 200
                        Layout.preferredHeight: 36
                        radius: 18
                        color: Colors.surface_container_highest
                        readonly property int idx: win.tab === "series" ? 1 : 0

                        Rectangle {
                            id: tabBlob
                            y: 3
                            height: 30
                            width: (tabs.width - 6) / 2
                            x: 3 + tabs.idx * width
                            radius: 15
                            color: Colors.secondary_container
                            Behavior on x { Spring { speed: "default" } }
                        }
                        Row {
                            anchors.fill: parent
                            anchors.margins: 3
                            Repeater {
                                model: [{ k: "recent", t: "Recent" }, { k: "series", t: "Series" }]
                                delegate: Clickable {
                                    id: tabBtn
                                    required property var modelData
                                    width: (tabs.width - 6) / 2
                                    height: 30
                                    restRadius: 15
                                    pressedRadius: 10
                                    onClicked: win.tab = modelData.k
                                    StyledText {
                                        anchors.centerIn: parent
                                        role: "labelLarge"
                                        emphasized: true
                                        color: win.tab === tabBtn.modelData.k ? Colors.on_secondary_container : Colors.on_surface_variant
                                        text: tabBtn.modelData.t
                                    }
                                }
                            }
                        }
                    }
                    Item { Layout.fillWidth: true }
                    // the source the context points at
                    Collapse {
                        horizontal: true
                        open: win.ctxFilter !== ""
                        Chip {
                            kind: "input"
                            icon: win.ctxFilter === "mpv" ? "play_arrow" : win.ctxFilter === "kavita" ? "menu_book" : "auto_stories"
                            trailingIcon: "close"
                            text: win.ctxFilter === "kavita" ? "Manga" : win.ctxFilter
                            onTrailingClicked: win.ctxFilter = ""
                            onClicked: win.ctxFilter = ""
                        }
                    }
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    // a row count, not the rows: delegates stay put while the data underneath changes
                    model: win.rows.length
                    // another day (or none): start from the top
                    Connections {
                        target: win
                        function onDayFilterChanged() { list.positionViewAtBeginning(); }
                    }

                    StyledText {
                        parent: list
                        anchors.centerIn: parent
                        opacity: win.rows.length === 0 ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        horizontalAlignment: Text.AlignHCenter
                        role: "bodyMedium"
                        color: Colors.on_surface_variant
                        text: win.dayFilter !== "" && win.tab === "recent" ? "Nothing on that day." : "Play something in mpv or log reading,\nand it shows up here."
                    }

                    delegate: Item {
                        id: row
                        required property int index
                        readonly property var r: win.rows[index]
                        readonly property bool isSeries: win.tab === "series"
                        readonly property bool dim: !!r && (isSeries ? !r.counted : !r.counted)
                        width: list.width
                        height: 60
                        // the rows come in one after the other, again whenever the day changes
                        Appear { id: rowIn; delay: Math.min(row.index, 6) * 40; lift: 10 }
                        Connections {
                            target: win
                            function onDayFilterChanged() { rowIn.replay(); }
                        }

                        HoverHandler { id: rowHover }

                        // a grouped list: the outer corners of the first and last rows are round, the inner ones
                        // tight; a row under the pointer rounds right off
                        Rectangle {
                            id: rowFill
                            anchors.fill: parent
                            readonly property real outer: Motion.shapeLarge
                            readonly property real inner: 4
                            readonly property real hov: rowHover.hovered ? 30 : -1
                            topLeftRadius: hov >= 0 ? hov : row.index === 0 ? outer : inner
                            topRightRadius: Math.max(0, topLeftRadius)
                            bottomLeftRadius: hov >= 0 ? hov : row.index === win.rows.length - 1 ? outer : inner
                            bottomRightRadius: Math.max(0, bottomLeftRadius)
                            Behavior on topLeftRadius { Spring { speed: "fast" } }
                            Behavior on bottomLeftRadius { Spring { speed: "fast" } }
                            color: rowHover.hovered ? Colors.surface_container_highest : Colors.surface_container
                            Behavior on color { ColorFade {} }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            spacing: 12
                            opacity: row.dim ? 0.55 : 1

                            ShapeBadge {
                                id: rowBadge
                                Layout.preferredWidth: 40
                                Layout.preferredHeight: 40
                                readonly property bool hasCover: !!row.r && !!row.r.cover
                                readonly property bool book: !!row.r && (row.r.kind === "read" || row.r.kind === "book" || row.r.kind === "manga")
                                shapeRest: book ? "cookie9" : "cookie4"
                                active: rowHover.hovered
                                spinning: active && visible
                                color: book ? Colors.tertiary_container : Colors.primary_container
                                Icon {
                                    anchors.centerIn: parent
                                    size: 20
                                    name: rowBadge.book ? "auto_stories" : "play_arrow"
                                    color: rowBadge.book ? Colors.on_tertiary_container : Colors.on_primary_container
                                    opacity: rowBadge.hasCover ? 0 : 1
                                }
                                // a book's cover, once ttu has one
                                ClippingRectangle {
                                    anchors.centerIn: parent
                                    width: 30
                                    height: 40
                                    radius: 8
                                    color: "transparent"
                                    opacity: rowBadge.hasCover ? 1 : 0
                                    Behavior on opacity { Fade {} }
                                    Image {
                                        anchors.fill: parent
                                        source: rowBadge.hasCover ? "file://" + row.r.cover : ""
                                        sourceSize.width: 80
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    jp: true
                                    role: "bodyLarge"
                                    emphasized: true
                                    elide: Text.ElideRight
                                    text: row.r ? (row.isSeries ? row.r.name : row.r.title) : ""
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "bodySmall"
                                    color: Colors.on_surface_variant
                                    elide: Text.ElideRight
                                    text: {
                                        if (!row.r)
                                            return "";
                                        if (row.isSeries && row.r.kind === "book")
                                            return [Math.round(row.r.chars).toLocaleString(Qt.locale(), "f", 0) + " chars",
                                                    row.r.progress !== null && row.r.progress !== undefined ? Math.round(row.r.progress * 100) + "% read" : "",
                                                    "last " + win.dayLabel(Tasks.keyOf(new Date(row.r.last * 1000))),
                                                    row.r.counted ? "" : "not counted"].filter(t => t !== "").join(" · ");
                                        if (row.isSeries && row.r.kind === "manga")
                                            return [row.r.episodes + (row.r.episodes === 1 ? " volume" : " volumes"), row.r.pages + " pages",
                                                    row.r.progress !== null && row.r.progress !== undefined ? Math.round(row.r.progress * 100) + "% read" : "",
                                                    "last " + win.dayLabel(Tasks.keyOf(new Date(row.r.last * 1000))),
                                                    row.r.counted ? "" : "not counted"].filter(t => t !== "").join(" · ");
                                        if (row.isSeries)
                                            return row.r.episodes + (row.r.episodes === 1 ? " episode" : " episodes") + " · last " + win.dayLabel(Tasks.keyOf(new Date(row.r.last * 1000)))
                                                + (row.r.counted ? "" : " · not counted");
                                        return [row.r.detail, win.dayLabel(row.r.day), row.r.counted ? "" : "not counted"].filter(s => s !== "").join(" · ");
                                    }
                                }
                            }
                            StyledText {
                                role: "titleSmall"
                                emphasized: true
                                color: row.dim ? Colors.on_surface_variant : Colors.primary
                                text: row.r ? (row.r.est ? "~" : "") + Immersion.fmt(row.r.minutes) : ""
                            }
                            // series: continue it, or flip whether it counts
                            Collapse {
                                horizontal: true
                                open: row.isSeries && !!row.r && row.r.kind !== "book" && row.r.kind !== "manga"
                                IconButton {
                                    size: "xs"
                                    style: "tonal"
                                    icon: "play_arrow"
                                    onClicked: if (row.r) Mpv.resume(row.r.path)
                                }
                            }
                            Collapse {
                                horizontal: true
                                open: row.isSeries
                                Switch {
                                    checked: !!row.r && row.r.counted
                                    onToggled: if (row.r) Immersion.setCounted(row.r.key, !row.r.counted)
                                }
                            }
                            // sessions: remove (undo from the snackbar)
                            Collapse {
                                horizontal: true
                                open: !row.isSeries
                                IconButton {
                                    size: "xs"
                                    icon: "delete"
                                    opacity: rowHover.hovered ? 1 : 0
                                    Behavior on opacity { Fade {} }
                                    onClicked: if (row.r) Immersion.removeRow(row.r)
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
