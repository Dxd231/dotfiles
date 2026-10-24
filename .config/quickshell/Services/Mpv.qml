pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import qs
import qs.Services

// Live link to mpv over its JSON IPC socket (input-ipc-server in mpv.conf): what is playing, where
// it is, the current subtitle line, and the transport commands. Reconnects by itself when mpv is
// started or closed. The immersion panel's player pane is built on this.
//
// One socket path serves one mpv: a second mpv takes the path over (for new connections only: a link that
// is already up stays on the first mpv, see `pid`), and when it leaves the first one is
// left listening on a socket nobody can reach. Then `viaScript` takes over: the tracker script in mpv
// writes what is playing to live.json, so the card can still show the file (read-only, no controls). The
// script also re-binds its socket when the shell leaves a `heal-<pid>` request (see immersion.lua), which
// brings the full link back by itself.
Singleton {
    id: mpv

    property string socket: Quickshell.env("QS_MPV_SOCKET") || "/tmp/mpv-socket"
    // true while the panel shows the player, so the position is polled only when somebody looks
    property bool watching: false

    property bool connected: false
    // pid of the mpv this link is on (observed); Lexicon compares it with the focused window's pid
    property int pid: 0
    // the external subtitle file in use ("" for an embedded track or none)
    property string subFile: ""
    property bool paused: true
    property real position: 0
    property real duration: 0
    property string title: ""
    property string path: ""
    property bool subsVisible: true
    property real speed: 1
    property int playlistPos: -1
    property int playlistCount: 0
    // the last subtitle line (it stays after it ends, so the panel can keep showing it)
    property string subText: ""
    // true while subText is actually on screen, false in the gaps between lines
    property bool subLive: false
    // when subText started, in seconds (asked from mpv a moment after the line appears)
    property real subStart: 0
    // lines before subText, newest first: { text, start }
    property var subHistory: []
    // counts new lines, so the panel can animate each one
    property int subSeq: 0
    // the line with its line breaks kept (the overlay breaks where the subtitle does)
    property string subRaw: ""
    // when subText ends, in seconds (observed, so it is right as soon as the line shows)
    property real subEnd: 0
    property bool fullscreen: false
    // subtitle timing offset in seconds (positive shows lines later). sub-start / sub-end come from mpv
    // in the subtitle file's own time, so subStart / subEnd add the delay to give playback time
    property real subDelay: 0
    // how mpv draws subtitles, for the overlay to match it (mpv.conf: sub-font-size, sub-margin-y, ...).
    // subScale ignores 0 because the lexicon overlay sets it to 0 to hide mpv's own line
    property real subFontSize: 45
    property real subScale: 1
    property real subPos: 100
    property real subMarginY: 22
    property real subBorder: 3
    property real subShadowOffset: 0
    property real subSpacing: 0
    property bool subBold: false
    property string subFont: ""
    property string subColor: "#FFFFFFFF"
    property string subBorderColor: "#FF000000"
    property string subShadowColor: "#AF000000"
    // mpv's OSD size and the black bars around the picture: { w, h, ml, mr, mt, mb }
    property var osdDims: ({ w: 0, h: 0, ml: 0, mr: 0, mt: 0, mb: 0 })
    // snapshot of the picture, alternating between two files so the Image always sees a new url
    property string thumb: ""
    property int _thumbN: 0
    // false for a file with no picture (music): mpv reports its `vid` as off
    property bool hasVideo: true
    // no socket, but the tracker script says a live mpv is playing this: what is shown comes from live.json
    property bool viaScript: false
    readonly property bool hasFile: (connected || viaScript) && path !== ""
    readonly property bool playing: hasFile && !paused

    // the picture goes next to the immersion log, whose directory mpv's script normally makes
    Component.onCompleted: Quickshell.execDetached(["mkdir", "-p", Immersion.stateDir + "/immersion"])

    // ---- no socket: what the tracker script says ----
    readonly property var _live: Immersion.liveRaw || ({})
    readonly property int _livePid: Number(_live.pid) || 0
    property bool scriptAlive: false
    function _syncScript() {
        if (connected)
            return;
        const l = _live;
        if (scriptAlive && l.path) {
            const pos = Number(l.pos) || 0;
            const ahead = l.playing ? Math.max(0, Immersion.nowSec - (Number(l.updated) || Immersion.nowSec)) : 0;
            const dur = Number(l.dur) || 0;
            viaScript = true;
            path = String(l.path);
            title = String(l.title || "");
            duration = dur;
            position = dur > 0 ? Math.min(dur, pos + ahead) : pos + ahead;
            paused = !l.playing;
        } else if (viaScript) {
            viaScript = false;
            path = "";
            title = "";
            position = 0;
            duration = 0;
            paused = true;
        }
    }
    Connections {
        target: Immersion
        function onLiveRawChanged() { mpv._syncScript(); }
        function onNowSecChanged() { if (mpv.viaScript && mpv.watching) mpv._syncScript(); }
    }
    onScriptAliveChanged: {
        _syncScript();
        if (!scriptAlive)
            _downSince = 0;
    }
    onConnectedChanged: {
        if (connected) {
            viaScript = false;
            _downSince = 0;
        } else {
            _syncScript();
        }
    }
    // is the pid the script reported still an mpv? (checked while there is no socket)
    Timer {
        interval: 5000
        repeat: true
        triggeredOnStart: true
        running: !mpv.connected && mpv._livePid > 0
        onTriggered: {
            alive.command = ["sh", "-c", 'grep -q "^mpv" "/proc/$1/comm" 2>/dev/null', "sh", String(mpv._livePid)];
            alive.running = true;
        }
    }
    Process {
        id: alive
        onExited: code => mpv.scriptAlive = code === 0
    }
    // a socket that keeps refusing while that mpv is alive: ask its script to bind it again
    property real _downSince: 0
    property real _lastHeal: 0
    property int _healTries: 0
    on_LivePidChanged: _healTries = 0
    Timer {
        interval: 2000
        repeat: true
        running: !mpv.connected && mpv.scriptAlive
        onTriggered: {
            const now = Date.now();
            if (mpv._downSince === 0) {
                mpv._downSince = now;
            } else if (now - mpv._downSince > 6000 && now - mpv._lastHeal > 30000 && mpv._healTries < 3) {
                // an mpv started before the script learned to heal will never answer: three tries are enough
                mpv._lastHeal = now;
                mpv._healTries += 1;
                Quickshell.execDetached(["touch", Immersion.stateDir + "/immersion/heal-" + mpv._livePid]);
            }
        }
    }

    // ---- commands ----
    function send(args, id) {
        if (!connected)
            return;
        const msg = { command: args };
        if (id !== undefined)
            msg.request_id = id;
        sock.write(JSON.stringify(msg) + "\n");
    }
    function togglePause() { send(["cycle", "pause"]); }
    function seek(secs) { send(["seek", secs, "relative"]); poll.restart(); }
    function seekTo(secs) { send(["seek", secs, "absolute"]); position = secs; }
    function prev() { send(["playlist-prev"]); }
    function next() { send(["playlist-next"]); }
    // jump back to the start of the line being said
    function replayLine() { send(["sub-seek", 0]); send(["sub-seek", -1]); }
    function skipOp() { seek(85); }
    // back to a line in the history, just before it starts so it shows again
    function jumpTo(secs) { seekTo(Math.max(0, secs - 0.05)); }
    function toggleSubs() { send(["cycle", "sub-visibility"]); }
    function resume(file) {
        if (file)
            Quickshell.execDetached(["mpv", file]);
    }
    function snap() {
        if (!hasFile)
            return;
        const n = (_thumbN + 1) % 2;
        const file = Immersion.stateDir + "/immersion/thumb" + n + ".jpg";
        _pendingThumb = file;
        _thumbN = n;
        send(["screenshot-to-file", file, "video"], 77);
    }
    property string _pendingThumb: ""

    // written straight to the socket: `connected` only turns true once mpv has answered
    function _observe() {
        const names = ["pause", "duration", "media-title", "path", "sub-text", "sub-visibility", "speed",
                       "playlist-pos", "playlist-count", "vid", "fullscreen", "sub-end", "osd-dimensions",
                       "sub-delay", "sub-font-size", "sub-scale", "sub-pos", "sub-margin-y", "sub-border-size",
                       "sub-shadow-offset", "sub-spacing", "sub-bold", "sub-font", "sub-color", "sub-border-color",
                       "sub-shadow-color", "current-tracks/sub/external-filename", "pid"];
        names.forEach((n, i) => sock.write(JSON.stringify({ command: ["observe_property", i + 1, n] }) + "\n"));
        sock.write(JSON.stringify({ command: ["get_property", "time-pos"], request_id: 10 }) + "\n");
    }

    function _onLine(line) {
        let o;
        try {
            o = JSON.parse(line);
        } catch (e) {
            return;
        }
        connected = true;
        if (o.event === "property-change") {
            const d = o.data;
            switch (o.name) {
            case "pid": pid = Number(d) || 0; break;
            case "pause": paused = !!d; break;
            case "duration": duration = d > 0 ? d : 0; break;
            case "media-title": title = d || ""; break;
            case "path":
                path = d || "";
                if (path === "")
                    position = 0;
                // a new file starts with no lines
                subText = "";
                subHistory = [];
                subLive = false;
                break;
            case "sub-visibility": subsVisible = d !== false; break;
            case "speed": speed = d || 1; break;
            case "playlist-pos": playlistPos = d === undefined || d === null ? -1 : d; break;
            case "playlist-count": playlistCount = d || 0; break;
            case "vid": hasVideo = !(d === false || d === "no"); break;
            case "fullscreen": fullscreen = d === true; break;
            case "current-tracks/sub/external-filename": subFile = typeof d === "string" ? d : ""; break;
            case "sub-end": subEnd = typeof d === "number" ? d + subDelay : subEnd; break;
            case "sub-delay": {
                const nd = typeof d === "number" ? d : 0;
                // a line already on screen keeps its file time, so move its playback time along
                subStart += nd - subDelay;
                subEnd += nd - subDelay;
                subHistory = subHistory.map(h => ({ text: h.text, start: h.start + nd - subDelay }));
                subDelay = nd;
                break;
            }
            case "sub-font-size": if (d > 0) subFontSize = d; break;
            case "sub-scale": if (d > 0) subScale = d; break;
            case "sub-pos": if (typeof d === "number") subPos = d; break;
            case "sub-margin-y": if (typeof d === "number") subMarginY = d; break;
            case "sub-border-size": if (typeof d === "number") subBorder = d; break;
            case "sub-shadow-offset": if (typeof d === "number") subShadowOffset = d; break;
            case "sub-spacing": if (typeof d === "number") subSpacing = d; break;
            case "sub-bold": subBold = d === true; break;
            case "sub-font": subFont = d || ""; break;
            case "sub-color": if (d) subColor = d; break;
            case "sub-border-color": if (d) subBorderColor = d; break;
            case "sub-shadow-color": if (d) subShadowColor = d; break;
            case "osd-dimensions":
                if (d && typeof d === "object")
                    osdDims = { w: d.w || 0, h: d.h || 0, ml: d.ml || 0, mr: d.mr || 0, mt: d.mt || 0, mb: d.mb || 0 };
                break;
            case "sub-text": {
                const t = String(d || "").replace(/\s*\n\s*/g, " ").trim();
                subLive = t !== "";
                if (t !== "")
                    subRaw = String(d).trim();
                // the last line stays up (dimmed) between lines; the one it replaces moves to the history
                if (t !== "" && t !== subText) {
                    if (subText !== "")
                        subHistory = [{ text: subText, start: subStart }].concat(subHistory.filter(h => h.text !== subText)).slice(0, 4);
                    subText = t;
                    subSeq++;
                    send(["get_property", "sub-start"], 20);
                }
                break;
            }
            }
        } else if (o.event === "file-loaded") {
            snapSoon.restart();
        } else if (o.event === "seek" || o.event === "playback-restart") {
            poll.restart();
        } else if (o.request_id === 10 && o.data !== undefined) {
            position = o.data;
        } else if (o.request_id === 20 && o.data !== undefined && o.data !== null) {
            subStart = o.data + subDelay;
        } else if (o.request_id === 77 && o.error === "success" && _pendingThumb !== "") {
            thumb = _pendingThumb;
        }
    }

    Timer {
        id: snapSoon
        interval: 1200
        onTriggered: mpv.snap()
    }
    // position, twice a second while the panel shows it
    Timer {
        id: poll
        interval: 500
        repeat: true
        triggeredOnStart: true
        running: mpv.connected && mpv.watching && !mpv.paused
        onTriggered: mpv.send(["get_property", "time-pos"], 10)
    }
    // a fresh picture every so often while it is on screen
    Timer {
        interval: 20000
        repeat: true
        running: mpv.playing && mpv.watching
        onTriggered: mpv.snap()
    }
    onWatchingChanged: {
        if (watching && connected) {
            send(["get_property", "time-pos"], 10);
            snap();
        }
    }

    // retry while mpv isn't there
    Timer {
        interval: 3000
        repeat: true
        running: sock.running === false
        triggeredOnStart: true
        onTriggered: sock.running = true
    }
    Process {
        id: sock
        command: ["sh", "-c", "[ -S '" + mpv.socket + "' ] && exec socat - 'UNIX-CONNECT:" + mpv.socket + "' 2>/dev/null"]
        stdinEnabled: true
        stdout: SplitParser {
            onRead: line => mpv._onLine(line)
        }
        onStarted: mpv._observe()
        onRunningChanged: {
            if (!running) {
                // a connect that failed (the retry timer tries every 3 s) changes nothing; only a link that
                // was up and dropped resets the player, and then it falls back to what the script says
                if (!mpv.connected)
                    return;
                mpv.viaScript = false;
                mpv.path = "";
                mpv.title = "";
                mpv.subText = "";
                mpv.subHistory = [];
                mpv.subLive = false;
                mpv.paused = true;
                mpv.position = 0;
                mpv.duration = 0;
                mpv.pid = 0;
                mpv.connected = false;
            }
        }
    }
}
