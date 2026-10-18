pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import qs
import qs.Services

// Screenshots and screen recordings for the shell, aware of the windows and workspaces on the
// focused monitor. `open()` freezes the monitor (grim), reads the windows and workspaces from
// hyprctl and lets CaptureOverlay pick a target; the quick actions skip the overlay.
//
//   photo  region / screen   crop of the frozen frame (exact), or a live grim after a delay / with the pointer
//          window            the window itself through screencopy (works for windows that are scrolled
//                            off-screen or on another workspace), grabbed by CaptureGrabber
//          workspace         a panorama of every window of the workspace at its layout position
//   video  gpu-screen-recorder: monitor, region, or a single window through the screencast portal
//          (Picker/run.sh answers the picker from the note this file writes), run detached so a shell
//          reload keeps recording; the state file lets the next shell pick it up again
Singleton {
    id: cap

    readonly property string home: Quickshell.env("HOME")
    readonly property string stateDir: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (home + "/.local/state")) + "/quickshell"
    readonly property string runDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") : "/tmp"
    readonly property string picturesDir: home + "/Pictures/screenshots"
    readonly property string videosDir: home + "/Videos"
    readonly property string thumbDir: stateDir + "/capture-thumbs"
    readonly property string trashDir: stateDir + "/capture-trash"
    readonly property string recState: runDir + "/qs-recording.json"
    readonly property string recLog: runDir + "/qs-recording.log"
    // the shell's PATH has a stale copy of hyprctl in /usr/local/bin ahead of this one, and it cannot start
    readonly property string hyprctl: "/usr/bin/hyprctl"

    property var toast: null
    // when Capture last put something on the clipboard, so the clipboard history does not toast it again
    property real lastCopy: 0

    // ---- options (kept between sessions) ----
    property string mode: "photo"       // photo | video
    property string target: "region"    // region | window | workspace | screen
    property bool pointer: false
    property int delay: 0               // seconds: 0 | 3 | 5 | 10
    property string audio: "system"     // off | system | both  (system sound, or system sound plus the microphone)
    property var lastRegion: null
    readonly property var delays: [0, 3, 5, 10]
    readonly property var audios: ["off", "system", "both"]
    function cycleDelay() { delay = delays[(delays.indexOf(delay) + 1) % delays.length]; _saveStore(); }
    readonly property var audioLabels: ({ off: "Recording without sound", system: "Recording the system sound", both: "Recording the system sound and the microphone" })
    function cycleAudio() {
        audio = audios[(audios.indexOf(audio) + 1) % audios.length];
        _saveStore();
        _say(audioLabels[audio]);
    }
    function setMode(m) { mode = m; _saveStore(); }
    function setTarget(t) { target = t; _saveStore(); }
    function setPointer(v) { pointer = v; _saveStore(); }

    // ---- the flow ----
    // idle | capturing | selecting | counting | shooting | saving
    property string phase: "idle"
    readonly property bool busy: phase !== "idle"
    property string frozen: ""
    // ws: the monitor's workspace, special: the special workspace shown over it (0 for none),
    // visible: what is actually on screen
    property var mon: ({ name: "", x: 0, y: 0, w: 1920, h: 1080, scale: 1, ws: 1, special: 0, specialName: "", visible: 1 })
    // windows of the focused monitor, in monitor-local logical pixels:
    // { addr, cls, title, ws, wsName, x, y, w, h, onScreen, focused, floating }
    property var windows: []
    // { id, name, label, active, windows: [...] }
    property var workspaces: []
    property string wallpaper: ""
    property string usedMonitor: ""
    property int rounding: 18           // Hyprland's window corner radius, which the saved pictures of windows get too
    property int count: 0               // countdown, seconds left
    property var _spec: null
    property string shotMode: "photo"   // what the running capture is: quick actions leave `mode` (the picker's) alone
    property var _quick: null
    property string _action: "overlay"  // overlay | quick

    // ---- what happened last (for the card) ----
    property var last: null             // { kind, path, thumb, w, h, bytes, seconds, label, ts, error }
    property bool cardShown: false

    // ---- the recording ----
    property bool recording: false
    property bool starting: false       // launched, not yet adopted
    property bool recStopping: false
    property bool recPaused: false
    property int recPid: 0
    property string recFile: ""
    property string recLabel: ""
    property string recTarget: ""       // region | window | workspace | screen
    property var recRegion: null        // monitor-local logical rect, for the frame around a region recording
    property var _recData: null
    property real recStart: 0
    property real recPausedAt: 0
    property real recPausedTotal: 0
    property int elapsed: 0             // seconds
    readonly property bool hasRegionFrame: recording && recTarget === "region" && !!recRegion

    function q(s) { return "'" + String(s).replace(/'/g, "'\\''") + "'"; }
    function stamp() {
        const d = new Date();
        const p = n => (n < 10 ? "0" : "") + n;
        return d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()) + "_" + p(d.getHours()) + "-" + p(d.getMinutes()) + "-" + p(d.getSeconds());
    }
    // the picture of a workspace covers the monitor and every window of it, wherever the layout put them
    function wsBounds(ws) {
        let x0 = 0, y0 = 0, x1 = mon.w, y1 = mon.h;
        (ws ? ws.windows : []).forEach(c => {
            x0 = Math.min(x0, c.x);
            y0 = Math.min(y0, c.y);
            x1 = Math.max(x1, c.x + c.w);
            y1 = Math.max(y1, c.y + c.h);
        });
        return { x: x0, y: y0, w: x1 - x0, h: y1 - y0 };
    }
    function windowByAddr(a) { return windows.find(w => w.addr === a) || null; }
    function workspaceById(id) { return workspaces.find(w => w.id === id) || null; }
    // one wording for a workspace everywhere: "Workspace 3", "music (special)"
    function wsLabel(ws) {
        if (!ws)
            return "Workspace";
        return ws.id < 0 ? ws.label + " (special)" : "Workspace " + ws.label;
    }
    function labelOf(spec) {
        if (spec.target === "window") {
            const w = windowByAddr(spec.addr);
            return w ? w.cls : "Window";
        }
        if (spec.target === "workspace")
            return wsLabel(workspaceById(spec.id));
        return spec.target === "region" ? "Region" : "Screen";
    }
    function _ocrBusy() { return Ocr.phase === "selecting" || Ocr.phase === "capturing"; }

    // ---- entry points ----
    // the overlay, in the remembered mode and target (or the ones given)
    function open(m, t) {
        if (busy || snap.running || _ocrBusy())
            return;
        const em = m === "photo" || m === "video" ? m : mode;
        if (em === "video" && (recording || starting)) {
            _say("Already recording");
            return;
        }
        if (m === "photo" || m === "video")
            mode = m;
        if (t === "region" || t === "window" || t === "workspace" || t === "screen")
            target = t;
        _action = "overlay";
        _begin();
    }
    function cancel() {
        if (phase === "selecting" || phase === "capturing" || phase === "counting") {
            countTimer.stop();
            // a capture still in flight deletes its own frame when it finds nobody wants it
            const wasCapturing = phase === "capturing";
            phase = "idle";
            if (!wasCapturing)
                _dropFrozen();
        }
    }
    // no overlay: shoot the screen, the focused window, or the current workspace right away
    // `arg` picks a particular workspace (its id) or window (its address) instead of the current one
    function quick(kind, t, arg) {
        if (busy || snap.running || _ocrBusy())
            return;
        if (kind === "video" && (recording || starting)) {
            _say("Already recording");
            return;
        }
        _quick = { mode: kind === "video" ? "video" : "photo", target: t, arg: arg || "" };
        _action = "quick";
        _begin();
    }
    function toggleRecording() {
        if (recording || starting)
            stopRecording();
        else
            open("video", null);
    }

    function _begin() {
        _dropFrozen();
        const m = Hyprland.focusedMonitor;
        const name = m ? m.name : "";
        frozen = runDir + "/qs-capture-frozen-" + Date.now() + ".png";
        Hyprland.refreshToplevels();
        phase = "capturing";
        // the monitor is the focused one; before Hyprland has reported any focus (a fresh shell) ask hyprctl
        snap.command = ["sh", "-c",
            'h="$3"; m="$1"; [ -n "$m" ] || m=$("$h" monitors -j | python3 -c "import json,sys; ms=json.load(sys.stdin); print(next((x[\'name\'] for x in ms if x[\'focused\']), ms[0][\'name\']))"); ' +
            'grim -o "$m" "$2" || { echo FAIL; exit 1; }; "$h" clients -j; echo @@@; "$h" workspaces -j; echo @@@; "$h" monitors -j; echo @@@; awww query 2>/dev/null; echo @@@; "$h" getoption decoration:rounding -j; echo "@@@$m"',
            "sh", name, frozen, hyprctl];
        snap.running = true;
    }
    function _dropFrozen() {
        if (frozen !== "")
            Quickshell.execDetached(["rm", "-f", frozen]);
        frozen = "";
    }
    Process {
        id: snap
        stdout: StdioCollector {
            onStreamFinished: cap._snapshot(text)
        }
    }
    function _snapshot(text) {
        if (phase !== "capturing") {
            // cancelled while it ran: the frame it made is nobody's
            if (frozen !== "")
                _dropFrozen();
            return;
        }
        if (text.indexOf("FAIL") === 0 || text.indexOf("@@@") < 0) {
            phase = "idle";
            _dropFrozen();
            _say("Could not capture the screen");
            return;
        }
        let clients = [], wss = [], mons = [];
        try {
            const parts = text.split("@@@");
            clients = JSON.parse(parts[0]);
            wss = JSON.parse(parts[1]);
            mons = JSON.parse(parts[2]);
            usedMonitor = (parts[5] || "").trim();
            try {
                rounding = Math.max(0, Number(JSON.parse(parts[4]).int) || 0);
            } catch (e) {
                rounding = 18;
            }
            // the wallpaper of this monitor, else the first one listed
            const lines = (parts[3] || "").split("\n");
            const mine = lines.find(l => l.indexOf(": " + usedMonitor + ":") >= 0) || lines[0] || "";
            const m = /image:\s*(\S.*)$/.exec(mine);
            wallpaper = m ? m[1].trim() : "";
        } catch (e) {
            phase = "idle";
            _dropFrozen();
            _say("Could not read the window list");
            return;
        }
        const mm = mons.find(x => x.name === usedMonitor) || mons.find(x => x.focused) || mons[0];
        if (!mm) {
            phase = "idle";
            _dropFrozen();
            return;
        }
        const sc = mm.scale || 1;
        const sp = mm.specialWorkspace && mm.specialWorkspace.id !== 0 ? mm.specialWorkspace : null;
        const info = { name: mm.name, x: mm.x, y: mm.y, w: Math.round(mm.width / sc), h: Math.round(mm.height / sc), scale: sc,
                       ws: mm.activeWorkspace ? mm.activeWorkspace.id : 1, special: sp ? sp.id : 0, specialName: sp ? String(sp.name).replace(/^special:/, "") : "" };
        info.visible = info.special !== 0 ? info.special : info.ws;
        mon = info;
        const list = [];
        clients.forEach(c => {
            if (!c.mapped || c.hidden || c.monitor !== mm.id || c.size[0] < 2 || c.size[1] < 2)
                return;
            const x = c.at[0] - mm.x, y = c.at[1] - mm.y, w = c.size[0], h = c.size[1];
            const ix = Math.min(x + w, info.w) - Math.max(x, 0), iy = Math.min(y + h, info.h) - Math.max(y, 0);
            list.push({ addr: String(c.address).replace(/^0x/, ""), cls: c.class || c.initialClass || "window", title: c.title || "",
                        ws: c.workspace.id, wsName: c.workspace.name, x: x, y: y, w: w, h: h, floating: !!c.floating, fs: c.fullscreen > 0,
                        onScreen: c.workspace.id === info.visible && ix > 8 && iy > 8, focused: c.focusHistoryID === 0 });
        });
        list.sort((a, b) => (b.onScreen - a.onScreen) || ((a.ws === info.visible ? 0 : 1) - (b.ws === info.visible ? 0 : 1)) || (a.ws - b.ws) || (a.x - b.x));
        windows = list;
        const wl = [];
        wss.filter(w => w.monitor === mm.name || w.monitorID === mm.id || w.id === info.visible).forEach(w => {
            const mine = list.filter(c => c.ws === w.id);
            if (mine.length === 0 && w.id !== info.visible && w.id !== info.ws)
                return;
            wl.push({ id: w.id, name: w.name, label: w.id < 0 ? String(w.name).replace(/^special:/, "") : String(w.name), active: w.id === info.visible, windows: mine });
        });
        wl.sort((a, b) => (b.active - a.active) || ((a.id < 0) - (b.id < 0)) || (a.id - b.id));
        workspaces = wl;

        if (_action === "quick") {
            const k = _quick;
            _quick = null;
            shotMode = k.mode;
            const spec = _specFor(k.target, k.arg);
            if (!spec) {
                phase = "idle";
                _dropFrozen();
                _say("Nothing to capture here");
                return;
            }
            _spec = spec;
            _fire();
            return;
        }
        phase = "selecting";
    }
    function _specFor(t, arg) {
        if (t === "window") {
            const w = arg !== "" ? windowByAddr(String(arg).replace(/^0x/, "")) : windows.find(x => x.focused && x.onScreen) || windows.find(x => x.onScreen);
            return w ? { target: "window", addr: w.addr } : null;
        }
        if (t === "workspace") {
            const id = arg !== "" ? Number(arg) : mon.visible;
            return workspaceById(id) ? { target: "workspace", id: id } : null;
        }
        return { target: "screen", x: 0, y: 0, w: mon.w, h: mon.h };
    }

    // ---- shooting ----
    // the overlay's confirm; `spec` = { target, x, y, w, h } | { target, addr } | { target, id }
    function shoot(spec) {
        if (phase !== "selecting")
            return;
        if (mode === "video" && (recording || starting)) {
            _say("Already recording");
            return;
        }
        if (spec.target === "region")
            lastRegion = { x: spec.x, y: spec.y, w: spec.w, h: spec.h };
        _saveStore();
        _spec = spec;
        shotMode = mode;
        if (delay > 0) {
            count = delay;
            phase = "counting";
            Sound.play("tick");
            countTimer.restart();
        } else {
            _fire();
        }
    }
    Timer {
        id: countTimer
        interval: 1000
        repeat: true
        onTriggered: {
            cap.count -= 1;
            if (cap.count > 0) {
                Sound.play("tick");
            } else {
                stop();
                cap._fire();
            }
        }
    }
    // what is read from the screen again (after the overlay and countdown are gone) rather than cut from the frozen frame
    readonly property bool _live: (_action === "overlay" && delay > 0) || pointer
    function _fire() {
        phase = "shooting";
        const s = _spec;
        if (shotMode === "video") {
            _record(s);
            return;
        }
        if (s.target === "window" || s.target === "workspace") {
            _grabWindows(s);
            return;
        }
        const tmp = runDir + "/qs-capture-" + Date.now() + ".png";
        if (_live) {
            // let the overlay and the countdown finish fading before the screen is read again
            settle.pending = { s: s, tmp: tmp };
            settle.restart();
        } else {
            _cropFrozen(s, tmp);
        }
    }
    Timer {
        id: settle
        interval: 420
        property var pending: null
        onTriggered: {
            const p = pending;
            pending = null;
            if (p)
                cap._grimLive(p.s, p.tmp);
        }
    }
    function _geometry(s) {
        return (mon.x + Math.round(s.x)) + "," + (mon.y + Math.round(s.y)) + " " + Math.max(1, Math.round(s.w)) + "x" + Math.max(1, Math.round(s.h));
    }
    function _grimLive(s, tmp) {
        shotProc.meta = { label: labelOf(s) };
        shotProc.tmp = tmp;
        shotProc.command = ["grim"].concat(pointer ? ["-c"] : []).concat(["-g", _geometry(s), tmp]);
        shotProc.running = true;
    }
    function _cropFrozen(s, tmp) {
        const k = mon.scale;
        shotProc.meta = { label: labelOf(s) };
        shotProc.tmp = tmp;
        shotProc.command = ["magick", frozen, "-crop", Math.round(s.w * k) + "x" + Math.round(s.h * k) + "+" + Math.round(s.x * k) + "+" + Math.round(s.y * k), "+repage", tmp];
        shotProc.running = true;
    }
    Process {
        id: shotProc
        property var meta: ({})
        property string tmp: ""
        onExited: code => {
            if (phase !== "shooting")
                return;
            if (code !== 0)
                cap._fail("The screenshot could not be taken");
            else
                cap._savePhoto(tmp, meta);
        }
    }

    // windows and workspaces go through CaptureGrabber (screencopy of the toplevels): first one picture per
    // window, then, for a workspace, the pictures laid out as the layout has them
    property var grab: null             // a job for the grabber, see CaptureGrabber
    property int _grabSeq: 0
    property var grabMeta: ({})
    property var _pano: null            // { target, items, w, h, out, files, bg, queue, cur, orig, origWs }
    function _grabWindows(s) {
        const stampId = Date.now();
        const out = runDir + "/qs-capture-" + stampId + ".png";
        let items = [], w = 0, h = 0, label = labelOf(s);
        if (s.target === "window") {
            const win = windowByAddr(s.addr);
            if (!win) {
                _fail("That window is gone");
                return;
            }
            items = [{ addr: win.addr, x: 0, y: 0, w: win.w, h: win.h, radius: win.fs ? 0 : rounding }];
            w = win.w;
            h = win.h;
        } else {
            const ws = workspaceById(s.id);
            const list = ws ? ws.windows : [];
            const b = wsBounds(ws);
            w = b.w;
            h = b.h;
            items = list.map(c => ({ addr: c.addr, x: c.x - b.x, y: c.y - b.y, w: c.w, h: c.h, radius: c.fs ? 0 : rounding }));
            label = wsLabel(ws) + " · " + list.length + (list.length === 1 ? " window" : " windows");
        }
        grabMeta = { label: label, target: s.target, addr: s.addr };
        items.forEach((i, n) => { i.out = runDir + "/qs-capture-part-" + stampId + "-" + n + ".png"; });
        const orig = windows.find(x => x.focused);
        _pano = { target: s.target, items: items, w: w, h: h, out: out, files: ({}), bg: s.target === "workspace" ? wallpaper : "", queue: [],
                  cur: "", orig: orig ? orig.addr : "" };
        grab = { id: ++_grabSeq, compose: false, items: items, cursor: pointer };
    }
    function grabDone(id, ok, missing) {
        if (!grab || grab.id !== id || !_pano)
            return;
        const job = grab;
        grab = null;
        const p = _pano;
        if (job.compose) {
            const parts = Object.keys(p.files).map(a => p.files[a]);
            _pano = null;
            Quickshell.execDetached(["rm", "-f"].concat(parts));
            if (ok)
                _savePhoto(p.out, grabMeta);
            else
                _fail("The workspace could not be captured");
            return;
        }
        job.items.forEach(i => {
            if (!missing || missing.indexOf(i.addr) < 0)
                p.files[i.addr] = i.out;
        });
        if (job.rescue) {
            _rescueNext();
            return;
        }
        if (missing && missing.length > 0) {
            // windows scrolled out of the layout give no picture: bring each into view in turn
            p.queue = missing.slice();
            _rescueNext();
            return;
        }
        _composePano();
    }
    // Hyprland's scrolling layout does not draw a window that sits wholly outside the viewport, so it has
    // no picture to copy. Focusing it scrolls it in; it is grabbed, and focus goes back to where it was.
    function _focusWindow(addr) {
        Hyprland.dispatch('hl.dsp.focus({ window = "address:0x' + addr + '" })');
    }
    function _restoreFocus(orig) {
        if (orig !== "")
            _focusWindow(orig);
        else
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + mon.ws + " })");
    }
    function _rescueNext() {
        const p = _pano;
        if (p.queue.length === 0) {
            _restoreFocus(p.orig);
            _composePano();
            return;
        }
        p.cur = p.queue.shift();
        p.polls = 0;
        p.lastX = null;
        _focusWindow(p.cur);
        rescueTick.restart();
    }
    // wait until the window has stopped moving inside the monitor, not for a fixed time
    Timer {
        id: rescueTick
        interval: 170
        onTriggered: {
            rescuePoll.command = [cap.hyprctl, "clients", "-j"];
            rescuePoll.running = true;
        }
    }
    Process {
        id: rescuePoll
        stdout: StdioCollector {
            onStreamFinished: cap._rescuePolled(text)
        }
    }
    function _rescuePolled(text) {
        const p = _pano;
        if (!p || !p.cur)
            return;
        let c = null;
        try {
            c = JSON.parse(text).find(x => String(x.address).replace(/^0x/, "") === p.cur) || null;
        } catch (e) {}
        const item = p.items.find(i => i.addr === p.cur);
        if (!item || !c) {
            _rescueNext();
            return;
        }
        p.polls += 1;
        const x = c.at[0] - mon.x;
        const inView = x + c.size[0] > 8 && x < mon.w - 8;
        const still = p.lastX !== null && Math.abs(p.lastX - x) < 1;
        p.lastX = x;
        if ((inView && still) || p.polls >= 22) {
            rescueGo.restart();
        } else {
            rescueTick.restart();
        }
    }
    // one more beat for the window to draw itself where it came to rest
    Timer {
        id: rescueGo
        interval: 220
        onTriggered: {
            const p = cap._pano;
            const item = p ? p.items.find(i => i.addr === p.cur) : null;
            if (!item) {
                if (p)
                    cap._rescueNext();
                return;
            }
            cap.grab = { id: ++cap._grabSeq, compose: false, rescue: true, items: [item], cursor: false };
        }
    }
    function _composePano() {
        const p = _pano;
        const have = p.items.filter(i => p.files[i.addr]);
        if (p.items.length > 0 && have.length === 0) {
            _fail(p.target === "window" ? "That window could not be captured" : "No window of the workspace could be captured");
            return;
        }
        // a window alone is composed too, on nothing, so its corners come out rounded like on screen
        grab = { id: ++_grabSeq, compose: true, plain: p.target === "window", w: p.w, h: p.h, out: p.out, bg: p.bg,
                 items: have.map(i => ({ addr: i.addr, x: i.x, y: i.y, w: i.w, h: i.h, radius: i.radius, file: p.files[i.addr] })) };
    }

    // ---- saving a photo ----
    function _savePhoto(tmp, meta) {
        phase = "saving";
        const dest = picturesDir + "/Screenshot_" + stamp() + ".png";
        saver.meta = meta;
        // two shots in the same second must not replace each other
        saver.command = ["sh", "-c",
            'd="$2"; base="${d%.png}"; n=1; while [ -e "$d" ]; do n=$((n+1)); d="${base}_$n.png"; done; ' +
            'mkdir -p "$3" && mv -f "$1" "$d" && echo "$d|$(magick identify -format "%w %h" "$d")|$(stat -c %s "$d")"',
            "sh", tmp, dest, picturesDir];
        saver.running = true;
    }
    Process {
        id: saver
        property var meta: ({})
        stdout: StdioCollector {
            onStreamFinished: {
                const m = /^(.+)\|(\d+) (\d+)\|(\d+)/.exec(text.trim());
                if (!m) {
                    cap._fail("The screenshot could not be saved");
                    return;
                }
                cap._shown({ kind: "photo", path: m[1], thumb: m[1], w: Number(m[2]), h: Number(m[3]), bytes: Number(m[4]), seconds: 0,
                             label: saver.meta.label || "", ts: Date.now() });
                cap.lastCopy = Date.now();
                Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < " + cap.q(m[1])]);
                Sound.play("shutter");
            }
        }
    }
    // the card: a result, or a failure. A recording that ends only shows its card; the picker and the
    // screenshot flow are none of its business
    function _present(r) {
        last = r;
        cardShown = true;
    }
    function _shown(r) {
        _clearJobs();
        phase = "idle";
        _dropFrozen();
        _present(r);
    }
    function _fail(message) {
        _clearJobs();
        phase = "idle";
        _dropFrozen();
        _present({ kind: shotMode === "video" ? "video" : "photo", error: message, ts: Date.now() });
    }
    // whatever a capture left behind: the grabber's job, rescue steps, and the pictures of single windows
    function _clearJobs() {
        grab = null;
        rescueTick.stop();
        rescueGo.stop();
        settle.stop();
        launchLater.stop();
        if (_pano) {
            Quickshell.execDetached(["rm", "-f"].concat(_pano.items.map(i => i.out)));
            _pano = null;
        }
    }
    function _say(text) {
        if (toast)
            toast.showToast(text);
    }
    function dismissCard() { cardShown = false; }

    // a capture that never finishes (the grabber gone, a process lost) must not block the next one
    Timer {
        interval: 60000
        running: cap.phase === "shooting" || cap.phase === "saving"
        onTriggered: {
            if (cap._pano)
                cap._restoreFocus(cap._pano.orig);
            cap._fail("The capture timed out");
        }
    }

    // ---- recording ----
    function _record(s) {
        if (recording || starting) {
            phase = "idle";
            _dropFrozen();
            _say("Already recording");
            return;
        }
        const info = { label: labelOf(s), target: s.target, start: Date.now(), region: s.target === "region" ? { x: s.x, y: s.y, w: s.w, h: s.h } : null };
        let capture = ["-w", mon.name];
        let pre = "";
        let audioPart = "";
        let switching = false;
        const win = s.target === "window" ? windowByAddr(s.addr) : null;
        if (s.target === "region") {
            // pixels, and even sizes for the encoder
            const k = mon.scale;
            const rw = Math.max(2, Math.floor(s.w * k / 2) * 2), rh = Math.max(2, Math.floor(s.h * k / 2) * 2);
            capture = ["-w", "region", "-region", rw + "x" + rh + "+" + (mon.x + Math.round(s.x * k)) + "+" + (mon.y + Math.round(s.y * k))];
        } else if (win) {
            capture = ["-w", "portal", "-restore-portal-session", "no"];
            if (!win.onScreen) {
                // a window outside the layout's viewport is not drawn, so there would be nothing to record
                _focusWindow(win.addr);
                switching = true;
            }
            pre = "printf 'window:%s\\n' " + q(win.addr) + " > " + q(runDir + "/qs-share-preselect") + "; ";
        } else if (s.target === "workspace") {
            // the recording is of the monitor: show the workspace on it first
            const ws = workspaceById(s.id);
            if (s.id < 0) {
                if (s.id !== mon.special) {
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + (ws ? ws.label : "") + '")');
                    switching = true;
                }
            } else {
                if (mon.special !== 0) {
                    Hyprland.dispatch('hl.dsp.workspace.toggle_special("' + mon.specialName + '")');
                    switching = true;
                }
                if (s.id !== mon.ws) {
                    Hyprland.dispatch("hl.dsp.focus({ workspace = " + s.id + " })");
                    switching = true;
                }
            }
        }
        if (audio !== "off") {
            if (win) {
                // that program's own sound, when it has a stream; the whole output otherwise
                pre += "app=$(gpu-screen-recorder --list-application-audio 2>/dev/null | grep -ix -m1 -- " + q(win.cls) + "); " +
                       'if [ -n "$app" ]; then src="app:$app"; else src=default_output; fi; ';
            } else {
                pre += "src=default_output; ";
            }
            audioPart = audio === "both" ? '-a "$src|default_input" ' : '-a "$src" ';
        }
        const base = videosDir + "/Video_" + stamp();
        const py = 'import json,sys; d=json.loads(sys.argv[1]); d["file"]=sys.argv[2]; print(json.dumps({"pid": int(sys.argv[3]), "data": d}))';
        // the file name is the first free one; the state file carries it and the pid (the shell becomes the recorder)
        const script = "mkdir -p " + q(videosDir) + "; " + pre +
            "base=" + q(base) + '; out="$base.mp4"; n=1; while [ -e "$out" ]; do n=$((n+1)); out="${base}_$n.mp4"; done; ' +
            "python3 -c " + q(py) + " " + q(JSON.stringify(info)) + ' "$out" "$$" > ' + q(recState + ".tmp") + " && mv -f " + q(recState + ".tmp") + " " + q(recState) + "; " +
            "exec gpu-screen-recorder " + capture.map(q).join(" ") + " -f 60 -k h264 -q very_high -c mp4 -cursor " + (pointer ? "yes" : "no") + " " + audioPart +
            '-o "$out" 2>' + q(recLog);
        launchLater.interval = switching ? 800 : 450;
        launchLater.fn = () => {
            starting = true;
            startingTimer.restart();
            Quickshell.execDetached(["setsid", "-f", "sh", "-c", script]);
            phase = "idle";
            _dropFrozen();
        };
        // the overlay has to be gone (and a switch done), or it ends up in the first frames
        launchLater.restart();
    }
    Timer {
        id: launchLater
        interval: 450
        property var fn: null
        onTriggered: if (fn) fn()
    }
    // a launch that never shows up as a recording stops counting as starting
    Timer {
        id: startingTimer
        interval: 8000
        onTriggered: cap.starting = false
    }

    function stopRecording() {
        if (recPid > 0 && !recStopping) {
            recStopping = true;
            Quickshell.execDetached(["kill", "-INT", String(recPid)]);
        }
    }
    function pauseRecording() {
        if (!recording || recPid <= 0 || recStopping)
            return;
        Quickshell.execDetached(["kill", "-USR2", String(recPid)]);
        if (recPaused) {
            recPausedTotal += Date.now() - recPausedAt;
            recPaused = false;
        } else {
            recPausedAt = Date.now();
            recPaused = true;
        }
        _tick();
        // so a shell that restarts mid-recording knows it is paused
        recWatch.setText(JSON.stringify({ pid: recPid, data: _recData, paused: recPaused, pausedAt: recPausedAt, pausedTotal: recPausedTotal }) + "\n");
    }
    function _tick() {
        const now = recPaused ? recPausedAt : Date.now();
        elapsed = Math.max(0, Math.floor((now - recStart - recPausedTotal) / 1000));
    }
    Timer {
        interval: 500
        repeat: true
        running: cap.recording
        onTriggered: cap._tick()
    }
    // the recorder is not our child, so look for it by pid
    Timer {
        interval: cap.recStopping ? 250 : 1000
        repeat: true
        running: cap.recording && cap.recPid > 0
        onTriggered: alive.running = true
    }
    Process {
        id: alive
        command: ["kill", "-0", String(cap.recPid)]
        onExited: code => {
            if (code !== 0 && cap.recording)
                cap._recordingEnded();
        }
    }
    // a state file only counts when its pid is still our recorder (or the shell about to become it), so a
    // crash or a reused pid never brings back a recording that is not there
    property var _adoptObj: null
    function _adopt(obj) {
        if (recording || adoptCheck.running || !obj || !obj.pid || !obj.data)
            return;
        _adoptObj = obj;
        adoptCheck.command = ["sh", "-c", 'grep -qE "^(sh|gpu-screen)" /proc/$1/comm 2>/dev/null', "sh", String(obj.pid)];
        adoptCheck.running = true;
    }
    Process {
        id: adoptCheck
        onExited: code => {
            const obj = cap._adoptObj;
            cap._adoptObj = null;
            if (code === 0 && obj && !cap.recording)
                cap._adoptNow(obj);
            else if (code !== 0 && !cap.recording && !cap.starting)
                Quickshell.execDetached(["rm", "-f", cap.recState]);
        }
    }
    function _adoptNow(obj) {
        recPid = obj.pid;
        _recData = obj.data;
        recFile = obj.data.file;
        recLabel = obj.data.label;
        recTarget = obj.data.target;
        recRegion = obj.data.region || null;
        recStart = obj.data.start;
        recPausedTotal = obj.pausedTotal || 0;
        recPausedAt = obj.pausedAt || 0;
        recPaused = !!obj.paused;
        recStopping = false;
        starting = false;
        recording = true;
        _tick();
    }
    function _recordingEnded() {
        const file = recFile, label = recLabel;
        recording = false;
        recStopping = false;
        recPaused = false;
        recPid = 0;
        recRegion = null;
        _recData = null;
        Quickshell.execDetached(["rm", "-f", recState]);
        finishing.file = file;
        finishing.label = label;
        // the first frame, the size, the length, and, if the recorder complained, what it said
        finishing.command = ["sh", "-c",
            'mkdir -p "$3"; t="$3/$(basename "$1" .mp4).png"; ffmpeg -v error -y -ss 0.3 -i "$1" -frames:v 1 -vf scale=480:-2 "$t" 2>/dev/null; ' +
            'echo "$t|$(stat -c %s "$1" 2>/dev/null)|$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$1" 2>/dev/null)|$(ffprobe -v error -select_streams v:0 -show_entries stream=width,height -of csv=s=x:p=0 "$1" 2>/dev/null)|$(grep -iE "error|fail|cannot|unable" "$4" 2>/dev/null | tail -n 2 | tr "\\n|" "  ")"',
            "sh", file, "", thumbDir, recLog];
        finishing.running = true;
    }
    Process {
        id: finishing
        property string file: ""
        property string label: ""
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim().split("|");
                const bytes = Number(p[1]) || 0;
                if (bytes < 1024) {
                    const why = (p[4] || "").trim();
                    cap._present({ kind: "video", error: "The recording could not be started" + (why !== "" ? ": " + why : ""), ts: Date.now() });
                    return;
                }
                const dim = (p[3] || "").split("x");
                cap._present({ kind: "video", path: finishing.file, thumb: p[0], w: Number(dim[0]) || 0, h: Number(dim[1]) || 0, bytes: bytes,
                             seconds: Math.round(Number(p[2]) || 0), label: finishing.label, ts: Date.now() });
                Sound.play("recStop");
            }
        }
    }
    FileView {
        id: recWatch
        path: cap.recState
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: {
            try {
                cap._adopt(JSON.parse(text()));
            } catch (e) {}
        }
    }

    // ---- the card's actions ----
    function copyLast() {
        if (!last || !last.path)
            return;
        lastCopy = Date.now();
        if (last.kind === "video")
            Quickshell.execDetached(["sh", "-c", "printf 'file://%s\\n' " + q(last.path) + " | wl-copy -t text/uri-list"]);
        else
            Quickshell.execDetached(["sh", "-c", "wl-copy -t image/png < " + q(last.path)]);
        _say(last.kind === "video" ? "Copied the file" : "Copied the image");
    }
    function openLast() { if (last && last.path) Quickshell.execDetached(["xdg-open", last.path]); }
    function folderLast() {
        if (last && last.path)
            Quickshell.execDetached(["xdg-open", last.path.replace(/\/[^\/]*$/, "")]);
    }
    function editLast() {
        if (last && last.kind === "photo")
            Quickshell.execDetached(["satty", "--filename", last.path, "--output-filename", last.path, "--early-exit", "--copy-command", "wl-copy"]);
    }
    // the file goes to a holding folder for a day; Undo puts that very one back, whatever was captured since
    function deleteLast() {
        if (!last || !last.path)
            return;
        const r = last;
        Quickshell.execDetached(["sh", "-c", 'mkdir -p "$2" && mv -f "$1" "$2/" ; find "$2" -type f -mtime +1 -delete', "sh", r.path, trashDir]);
        cardShown = false;
        if (toast)
            toast.showToast(r.kind === "video" ? "Recording deleted" : "Screenshot deleted", "Undo", () => cap.undoDelete(r));
    }
    function undoDelete(r) {
        Quickshell.execDetached(["sh", "-c", 'mv -f "$2/$(basename "$1")" "$1"', "sh", r.path, trashDir]);
        if (!cardShown) {
            last = r;
            cardShown = true;
        }
    }

    // ---- housekeeping ----
    // leftovers of a shell that went away mid-capture, and old video thumbnails
    Component.onCompleted: Quickshell.execDetached(["sh", "-c",
        'find "$1" -maxdepth 1 -name "qs-capture-*" -mmin +60 -delete 2>/dev/null; find "$2" -type f -mtime +30 -delete 2>/dev/null', "sh", runDir, thumbDir])

    // ---- persistence ----
    function _saveStore() {
        adapter.mode = mode;
        adapter.target = target;
        adapter.pointer = pointer;
        adapter.delay = delay;
        adapter.audio = audio;
        adapter.lastRegion = lastRegion ? lastRegion : ({});
        store.writeAdapter();
    }
    FileView {
        id: store
        path: cap.stateDir + "/capture.json"
        printErrors: false
        blockLoading: true
        onLoaded: {
            cap.mode = adapter.mode === "video" ? "video" : "photo";
            cap.target = ["region", "window", "workspace", "screen"].indexOf(adapter.target) >= 0 ? adapter.target : "region";
            cap.pointer = !!adapter.pointer;
            cap.delay = cap.delays.indexOf(adapter.delay) >= 0 ? adapter.delay : 0;
            // "mic" was the first name for "both"
            cap.audio = adapter.audio === "mic" ? "both" : cap.audios.indexOf(adapter.audio) >= 0 ? adapter.audio : "system";
            const r = adapter.lastRegion;
            cap.lastRegion = r && r.w > 0 ? r : null;
        }
        JsonAdapter {
            id: adapter
            property string mode: "photo"
            property string target: "region"
            property bool pointer: false
            property int delay: 0
            property string audio: "system"
            property var lastRegion: ({})
        }
    }
}
