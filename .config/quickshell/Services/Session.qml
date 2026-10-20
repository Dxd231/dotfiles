pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland

// Remembers which apps were open where, and offers to bring them back in a new Hyprland session.
// The snapshot (class, desktop entry, workspace, floating geometry) is rewritten whenever the window
// set changes. A restore launches each app's desktop entry and, as its window appears, moves it to
// its old workspace (and old spot, when it floated). Tabs and the like are the app's own business.
Singleton {
    id: session

    // snapshot as saved: { instance, savedAt, apps: [{ cls, desktopId, name, ws, floating, at, size }] }
    property var saved: ({ instance: "", savedAt: 0, apps: [] })
    // the previous Hyprland session's snapshot, archived at startup in its own file so the new session's
    // live snapshot can never overwrite it; the restore offer reads this one
    property var last: ({ instance: "", savedAt: 0, apps: [] })
    // set from shell.qml while the lock screen is up: the offer waits so the card is not hidden under it
    property bool blocked: false
    // apps still to place during a restore, with `done` set as each window lands
    property var items: []
    readonly property int placed: items.filter(i => i.done).length
    // the card is up
    property bool offering: false
    property bool restoring: false
    // set by power actions before they close anything, so the snapshot keeps the open apps
    property bool frozen: false
    property bool ready: false
    readonly property string instance: Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    property double startedAt: Date.now()

    // a power action is about to close everything: write the current state first, then lock it
    // (the file is marked `final`, so another shell process in a closing session can't thin it either)
    function freeze() {
        if (ready && !frozen && !offering && !restoring)
            _write(true);
        frozen = true;
    }
    function unfreeze() {
        frozen = false;
        if (saved.final) {
            // a cancelled power action: the apps it closed (or the user closed to finish it) are still
            // part of the layout worth restoring
            if (saved.instance === instance && saved.apps.length > 0) {
                carried = saved.apps;
                carriedAt = Date.now();
                console.info("session: carrying " + carried.length + " apps from a cancelled power action");
            }
            saved = Object.assign({}, saved, { final: false });
        }
        snapshot();
    }
    property var carried: []
    property double carriedAt: 0

    // the file the shell knows mpv is playing, for the mpv window with this pid
    function _mediaFor(o, first) {
        if (o.class !== "mpv")
            return null;
        const pid = Mpv._livePid;
        if (pid > 0 && o.pid !== pid && !first)
            return null;
        const path = Mpv.hasFile ? Mpv.path : String((Immersion.liveRaw || {}).path || "");
        if (!path)
            return null;
        return { path: path, title: Mpv.hasFile ? Mpv.title : String((Immersion.liveRaw || {}).title || "") };
    }

    // numbered workspaces first, special ones (negative ids) after them
    function _byWs(a, b) {
        return (a.ws > 0 ? a.ws : 1000) - (b.ws > 0 ? b.ws : 1000);
    }

    function _entryFor(cls) {
        if (!cls)
            return null;
        const low = cls.toLowerCase();
        return DesktopEntries.byId(cls) ?? DesktopEntries.byId(cls + ".desktop") ?? DesktopEntries.byId(low)
            ?? DesktopEntries.heuristicLookup(cls) ?? DesktopEntries.heuristicLookup(low);
    }

    function _collect() {
        const apps = [];
        let mpvSeen = 0;
        for (const t of Hyprland.toplevels.values) {
            const o = t.lastIpcObject || {};
            const ws = o.workspace ? o.workspace.id : -1;
            const wsName = o.workspace ? String(o.workspace.name || "") : "";
            const special = wsName.startsWith("special:");
            if (!o.mapped || !o.class || (ws < 1 && !special))
                continue;
            const de = _entryFor(o.class);
            if (!de)
                continue;
            const app = {
                cls: o.class,
                desktopId: de.id,
                name: de.name,
                ws: ws,
                wsName: special ? wsName : "",
                title: String(o.title || ""),
                floating: !!o.floating,
                at: o.at || [0, 0],
                size: o.size || [0, 0]
            };
            if (o.class === "mpv") {
                // without a known pid the first mpv window gets the file
                const media = _mediaFor(o, Mpv._livePid <= 0 && mpvSeen === 0);
                if (media)
                    app.media = media;
                mpvSeen++;
            }
            apps.push(app);
        }
        apps.sort(_byWs);
        return apps;
    }

    function snapshot() {
        if (frozen || offering || restoring || !ready)
            return;
        Hyprland.refreshToplevels();
        snapDelay.restart();
    }
    // toplevel data lands a beat after refreshToplevels()
    Timer {
        id: snapDelay
        interval: 250
        onTriggered: {
            if (session.frozen || session.offering || session.restoring)
                return;
            session._write();
        }
    }
    property bool _confirmed: false
    function _write(final) {
        let apps = _collect();
        if (carried.length > 0) {
            if (Date.now() - carriedAt < 1800000) {
                const counts = {};
                for (const a of apps)
                    counts[a.cls] = (counts[a.cls] || 0) + 1;
                apps = apps.concat(_unmatched(carried, counts));
                apps.sort(_byWs);
            } else {
                console.info("session: dropped carried layout");
                carried = [];
            }
        }
        if (!final && carried.length === 0) {
            // right after login the windows are still opening: don't wipe a good snapshot with a thin one
            if (apps.length === 0 && saved.apps.length > 0 && Date.now() - startedAt < 30000)
                return;
            // a closing session already saved its last good layout (stale after ten minutes)
            if (saved.final && saved.instance === instance && Date.now() - saved.savedAt < 600000)
                return;
            // several apps vanishing at once may be the session coming down without the power menu: if
            // the shell is still alive 8 s later it was only the user closing windows
            if (!_confirmed && saved.apps.length - apps.length >= 2) {
                if (!shrinkHold.running) {
                    console.info("session: holding a snapshot that drops " + (saved.apps.length - apps.length) + " apps");
                    shrinkHold.start();
                }
                return;
            }
        }
        _confirmed = false;
        saved = { instance: instance, savedAt: Date.now(), final: !!final, apps: apps };
        store.setText(JSON.stringify(saved));
        if (final)
            console.info("session: final snapshot of " + apps.length + " apps");
    }
    Timer {
        id: shrinkHold
        interval: 8000
        onTriggered: {
            session._confirmed = true;
            session.snapshot();
        }
    }

    Timer {
        id: debounce
        interval: 2000
        onTriggered: session.snapshot()
    }
    Timer {
        interval: 60000
        repeat: true
        running: session.ready
        onTriggered: session.snapshot()
    }

    // ---- restore offer ----
    function _missing() {
        const running = {};
        for (const t of Hyprland.toplevels.values) {
            const c = (t.lastIpcObject || {}).class;
            if (c)
                running[c] = (running[c] || 0) + 1;
        }
        return _unmatched(last.apps, running);
    }

    // one running window cancels one saved window of the same class (autostart apps, restarted shell)
    function _unmatched(list, running) {
        const left = Object.assign({}, running);
        return list.filter(a => {
            if (left[a.cls] > 0) {
                left[a.cls]--;
                return false;
            }
            return true;
        });
    }

    function offer() {
        const missing = _missing();
        console.info("session: " + missing.length + " of " + last.apps.length + " saved apps missing");
        if (missing.length === 0) {
            ready = true;
            return;
        }
        items = missing.map(a => Object.assign({ done: false }, a));
        offering = true;
    }

    function _resolve() {
        last = Object.assign({}, last, { resolved: true });
        lastStore.setText(JSON.stringify(last));
    }

    function dismiss() {
        _resolve();
        offering = false;
        restoring = false;
        items = [];
        ready = true;
        snapshot();
    }

    function restore() {
        if (items.length === 0)
            return;
        offering = false;
        restoring = true;
        // launch in workspace order, a little apart so the compositor can map them in turn
        launchIndex = 0;
        launchedCls = {};
        pool = {};
        tries = {};
        toppedUp = false;
        topUp.stop();
        launcher.restart();
        giveUp.restart();
    }

    property int launchIndex: 0
    property var launchedCls: ({})
    // windows of classes with several saved windows, waiting to be paired with their items by title
    property var pool: ({})
    property var tries: ({})

    function _multi(cls) {
        return items.filter(i => i.cls === cls && !(i.media && i.media.path)).length >= 2;
    }

    // quiet for 3 s: first launch the windows an app did not bring back itself, then pair what opened
    Timer {
        id: topUp
        interval: 3000
        onTriggered: {
            if (!session.restoring)
                return;
            if (launcher.running) {
                restart();
                return;
            }
            const need = [];
            const seen = {};
            for (const it of session.items) {
                if (it.done || (it.media && it.media.path) || !session._multi(it.cls))
                    continue;
                const have = (session.pool[it.cls] || []).length;
                seen[it.cls] = (seen[it.cls] || 0) + 1;
                if (seen[it.cls] > have)
                    need.push(it);
            }
            if (need.length > 0 && !session.toppedUp) {
                session.toppedUp = true;
                session.topList = need;
                topLauncher.restart();
                return;
            }
            Hyprland.refreshToplevels();
            pairDelay.restart();
        }
    }
    property bool toppedUp: false
    property var topList: []
    Timer {
        id: topLauncher
        interval: 350
        repeat: true
        onTriggered: {
            const it = session.topList.shift();
            if (!it) {
                stop();
                topUp.restart();
                return;
            }
            const de = session._entryFor(it.cls) ?? DesktopEntries.byId(it.desktopId);
            if (de)
                de.execute();
        }
    }
    Timer {
        id: pairDelay
        interval: 300
        onTriggered: session._pair()
    }

    function _titleScore(a, b) {
        a = String(a || "").trim();
        b = String(b || "").trim();
        if (!a || !b)
            return 0;
        if (a === b)
            return 100;
        const pa = a.split(" — ")[0], pb = b.split(" — ")[0];
        if (pa && pa === pb)
            return 80;
        const wa = pa.toLowerCase().split(/\s+/), wb = new Set(pb.toLowerCase().split(/\s+/));
        return Math.min(50, wa.filter(w => w.length > 1 && wb.has(w)).length * 10);
    }

    // pair the windows of each multi-window class with its saved items: best title match first,
    // the rest in workspace order
    function _pair() {
        if (!restoring)
            return;
        for (const cls of Object.keys(pool)) {
            const wins = [];
            for (const addr of pool[cls]) {
                const bare = addr.replace(/^0x/, "");
                const t = Hyprland.toplevels.values.find(w => String(w.address).replace(/^0x/, "") === bare);
                if (t && t.lastIpcObject && t.lastIpcObject.class === cls)
                    wins.push({ addr: bare, title: t.lastIpcObject.title || "" });
            }
            const idxs = [];
            items.forEach((it, i) => { if (!it.done && it.cls === cls) idxs.push(i); });
            const cand = [];
            for (const i of idxs)
                for (let w = 0; w < wins.length; w++)
                    cand.push({ i: i, w: w, s: _titleScore(items[i].title, wins[w].title) });
            cand.sort((x, y) => y.s - x.s || x.i - y.i || x.w - y.w);
            const usedI = {}, usedW = {};
            for (const c of cand) {
                if (usedI[c.i] || usedW[c.w])
                    continue;
                usedI[c.i] = true;
                usedW[c.w] = true;
                _apply(wins[c.w].addr, c.i);
            }
        }
        pool = {};
        if (items.length > 0 && items.every(i => i.done))
            finishDelay.restart();
    }
    Timer {
        id: launcher
        interval: 350
        repeat: true
        onTriggered: {
            if (session.launchIndex >= session.items.length) {
                stop();
                topUp.restart();
                return;
            }
            const it = session.items[session.launchIndex++];
            // mpv comes back on the episode it was playing; mpv itself resumes the position
            if (it.media && it.media.path) {
                Mpv.resume(it.media.path);
                return;
            }
            // one launch per class: a second launch of a running browser only opens a "New Tab"
            // window. Apps with their own session restore bring the rest back; whatever is still
            // missing is launched by topUp.
            if (session.launchedCls[it.cls])
                return;
            session.launchedCls[it.cls] = true;
            const de = session._entryFor(it.cls) ?? DesktopEntries.byId(it.desktopId);
            if (de)
                de.execute();
        }
    }
    // after this the card closes with whatever got placed
    Timer {
        id: giveUp
        interval: 25000
        onTriggered: session._finish()
    }
    function _finish() {
        _resolve();
        launcher.stop();
        giveUp.stop();
        restoring = false;
        const n = placed, total = items.length;
        items = [];
        ready = true;
        if (toast)
            toast.showToast(n + " of " + total + " apps restored");
        snapshot();
    }

    property var toast: null

    // place a window that just opened against the first pending item of its class
    function _place(address) {
        const bare = address.replace(/^0x/, "");
        const t = Hyprland.toplevels.values.find(w => String(w.address).replace(/^0x/, "") === bare);
        const o = t ? t.lastIpcObject : null;
        if (!o || !o.class) {
            // some apps (Spotify) set their class a moment after mapping
            tries[bare] = (tries[bare] || 0) + 1;
            if (tries[bare] < 10)
                placeDelay.enqueue(bare);
            return;
        }
        const idx = items.findIndex(i => !i.done && i.cls === o.class);
        if (idx < 0)
            return;
        if (_multi(o.class)) {
            const list = pool[o.class] || [];
            if (!list.includes(bare))
                list.push(bare);
            pool[o.class] = list;
            topUp.restart();
            return;
        }
        _apply(bare, idx);
        if (items.every(i => i.done))
            finishDelay.restart();
    }

    function _apply(bare, idx) {
        const it = items[idx];
        const sel = 'window = "address:0x' + bare + '"';
        const target = it.wsName ? '"' + it.wsName + '"' : it.ws;
        Hyprland.dispatch('hl.dsp.window.move({ workspace = ' + target + ', follow = false, ' + sel + ' })');
        if (it.floating) {
            Hyprland.dispatch('hl.dsp.window.float({ action = "enable", ' + sel + ' })');
            Hyprland.dispatch('hl.dsp.window.resize({ x = ' + it.size[0] + ', y = ' + it.size[1] + ', exact = true, ' + sel + ' })');
            Hyprland.dispatch('hl.dsp.window.move({ x = ' + it.at[0] + ', y = ' + it.at[1] + ', exact = true, ' + sel + ' })');
        }
        const next = items.slice();
        next[idx] = Object.assign({}, it, { done: true });
        items = next;
    }
    Timer {
        id: finishDelay
        interval: 900
        onTriggered: session._finish()
    }

    // a new episode opens no window, so catch it here
    Connections {
        target: Mpv
        function onPathChanged() { if (Mpv.path !== "") debounce.restart(); }
    }

    Connections {
        target: Hyprland
        function onRawEvent(ev) {
            const n = ev.name;
            if (n === "openwindow") {
                // data: address,workspace,class,title
                const addr = ev.data.split(",")[0];
                if (session.restoring)
                    placeDelay.enqueue(addr);
                debounce.restart();
            } else if (n === "closewindow" || n === "changefloatingmode" || n === "movewindowv2" || n === "movewindow" || n === "resizewindow") {
                debounce.restart();
            }
        }
    }
    // the window's class arrives with the event, but its IPC object needs a refresh first
    Timer {
        id: placeDelay
        interval: 300
        property var queue: []
        function enqueue(addr) {
            queue.push(addr);
            Hyprland.refreshToplevels();
            restart();
        }
        onTriggered: {
            const q = queue;
            queue = [];
            for (const a of q)
                session._place("0x" + a.replace(/^0x/, ""));
        }
    }

    // ---- persistence ----
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/session.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d && Array.isArray(d.apps))
                    session.saved = d;
            } catch (e) {}
        }
    }

    FileView {
        id: lastStore
        path: store.path.replace(/session\.json$/, "last-session.json")
        printErrors: false
        blockLoading: true
        onLoaded: {
            try {
                const d = JSON.parse(text());
                if (d && Array.isArray(d.apps))
                    session.last = d;
            } catch (e) {}
        }
    }

    // a fresh Hyprland session (different instance): archive the old snapshot before the live one can
    // overwrite it, then offer it; the same instance just keeps snapshotting
    Timer {
        running: true
        interval: 4000
        onTriggered: {
            // not under the lock screen
            if (session.blocked) {
                restart();
                return;
            }
            console.info("session: loaded " + session.saved.apps.length + " apps" + (session.saved.final ? " (final)" : "")
                + ", same instance: " + (session.saved.instance === session.instance));
            if (session.saved.apps.length > 0 && session.saved.instance !== session.instance) {
                session.last = session.saved;
                lastStore.setText(JSON.stringify(session.last));
                session.offer();
            } else {
                session.ready = true;
            }
        }
    }

    IpcHandler {
        target: "session"
        function snapshot(): void { session.ready = true; session.snapshot(); }
        function restore(): void { if (!session.offering) session.offer(); session.restore(); }
        function show(): void { session.offer(); }
        function freeze(): void { session.freeze(); }
    }
}
