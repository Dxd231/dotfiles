pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland

// Log out / restart / shut down. Every window gets a close request first, so apps can ask to save; the
// real command runs once they are all gone (phase "closing" -> "leaving" -> command). A window that
// stays open (a save prompt) is brought to the front and waited for: nothing is forced unless asked.
// Only windows are asked: background and tray apps without one are ended by systemd / Hyprland exiting.
Singleton {
    id: power

    // "logout" | "reboot" | "poweroff"
    property string kind: ""
    // "idle" | "closing" (waiting on windows) | "leaving" (goodbye screen, then the command)
    property string phase: "idle"
    readonly property bool closing: phase !== "idle"
    property string reason: ""
    // some window is still open well after being asked: it is probably showing a prompt
    property bool stuck: false
    // test hooks: a notification in place of the real command; `testApp` limits closing to one app id
    property bool dryRun: false
    property string testApp: ""

    // updates that need a reboot: packages the pacman hook appended to /run (tmpfs, so it clears itself
    // on reboot), or a stale driver / kernel module found by the probe
    property var pendingPackages: []
    property bool stale: false
    property bool testPending: false
    // the power menu's hero spin angle at the hand-off, so the closing card's shape keeps turning from there
    property real handoffSpin: 0
    readonly property bool rebootPending: testPending || stale || pendingPackages.length > 0

    readonly property var remaining: closing ? ToplevelManager.toplevels.values.filter(t => testApp === "" || t.appId === testApp) : []
    property int initialCount: 0
    readonly property real progress: initialCount > 0 ? Math.max(0, Math.min(1, 1 - remaining.length / initialCount)) : 1

    readonly property var labels: ({
        logout: { word: "Log out", title: "Logging out", icon: "logout" },
        reboot: { word: "Restart", title: "Restarting", icon: "restart_alt" },
        poweroff: { word: "Shut down", title: "Shutting down", icon: "power_settings_new" }
    })

    function _post() {
        if (dryRun || testApp !== "")
            return "notify-send 'power: " + kind + "'";
        if (kind === "reboot")
            return "systemctl reboot";
        if (kind === "poweroff")
            return "systemctl poweroff";
        return "hyprctl dispatch 'hl.dsp.exit()'";
    }

    function _reason() {
        if (kind === "reboot" && rebootPending)
            return "Applying your updates";
        return "Closing your apps first";
    }

    function run(k) {
        if (closing)
            return;
        _stopResume();
        kind = k;
        reason = _reason();
        stuck = false;
        emptyTicks = 0;
        // the apps are about to close one by one: keep the saved layout as it is now
        Session.freeze();
        phase = "closing";
        initialCount = remaining.length;
        for (const t of remaining)
            t.close();
        poll.restart();
        stuckTimer.restart();
    }

    // everything is gone (or the user said go): show the goodbye screen for a beat, then act
    function _leave(ms) {
        if (phase === "leaving")
            return;
        poll.stop();
        stuckTimer.stop();
        phase = "leaving";
        leaveTimer.interval = ms;
        leaveTimer.restart();
    }

    function force() {
        if (phase === "closing")
            _leave(900);
    }

    function cancel() {
        leaveTimer.stop();
        poll.stop();
        stuckTimer.stop();
        // cancelled with windows still open (a save prompt in the way): ask again once they are gone
        const open = phase === "closing" ? remaining.length : 0;
        const k = kind, app = testApp;
        phase = "idle";
        stuck = false;
        testApp = "";
        if (open > 0) {
            resumeKind = k;
            resumeApp = app;
            resumeOpen = open;
            resumeEmpty = 0;
            resumeWatch.restart();
            resumeExpire.restart();
        }
        Session.unfreeze();
    }

    // a cancelled action waiting for its last windows to be closed by hand
    property string resumeKind: ""
    property string resumeApp: ""
    property int resumeOpen: 0
    property int resumeEmpty: 0
    // every window is gone and nothing has been done yet: the closing card stays up as a confirmation
    function _confirm(k) {
        testApp = resumeApp;
        kind = k;
        reason = "All your apps are closed";
        stuck = false;
        Session.freeze();
        phase = "closing";
        initialCount = 0;
    }
    function _stopResume() {
        resumeKind = "";
        resumeWatch.stop();
        resumeExpire.stop();
    }
    Timer {
        id: resumeWatch
        interval: 500
        repeat: true
        onTriggered: {
            const n = ToplevelManager.toplevels.values.filter(t => power.resumeApp === "" || t.appId === power.resumeApp).length;
            if (power.closing || n > power.resumeOpen) {
                power._stopResume();
                return;
            }
            power.resumeEmpty = n === 0 ? power.resumeEmpty + 1 : 0;
            if (power.resumeEmpty >= 2) {
                const k = power.resumeKind;
                power._stopResume();
                power._confirm(k);
            }
        }
    }
    Timer {
        id: resumeExpire
        interval: 600000
        onTriggered: power._stopResume()
    }

    property int emptyTicks: 0
    Timer {
        id: poll
        interval: 500
        repeat: true
        onTriggered: {
            power.emptyTicks = power.remaining.length === 0 ? power.emptyTicks + 1 : 0;
            if (power.emptyTicks >= 2)
                power._leave(1200);
        }
    }

    // a window still open this long after the request is waiting on its user: bring the first one forward
    Timer {
        id: stuckTimer
        interval: 4000
        onTriggered: {
            if (power.remaining.length === 0)
                return;
            power.stuck = true;
            power.remaining[0].activate();
        }
    }

    Timer {
        id: leaveTimer
        onTriggered: {
            Quickshell.execDetached(["sh", "-c", power._post()]);
            // a real command ends the session; a test notification must not leave the screen up
            if (power.dryRun || power.testApp !== "")
                power.cancel();
        }
    }

    // stale: the loaded nvidia module no longer matches the installed userspace, or the running kernel's
    // modules were replaced; either way a reboot is needed
    readonly property var staleCheck: ["sh", "-c", "v=$(cat /sys/module/nvidia/version 2>/dev/null); u=$(pacman -Q nvidia-utils 2>/dev/null | cut -d' ' -f2); " + "[ -d \"/usr/lib/modules/$(uname -r)\" ] || { echo stale; exit; }; " + "if [ -n \"$v\" ] && [ -n \"$u\" ]; then case \"$u\" in \"$v\"*) ;; *) echo stale; exit;; esac; fi; echo ok"]

    Process {
        id: staleProbe
        command: power.staleCheck
        running: true
        stdout: StdioCollector {
            onStreamFinished: power.stale = text.trim() === "stale"
        }
    }

    FileView {
        id: pendingFile
        path: "/run/quickshell-reboot-required"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: power.pendingPackages = [...new Set(text().split("\n").map(s => s.trim()).filter(s => s !== ""))]
        onLoadFailed: power.pendingPackages = []
    }

    IpcHandler {
        target: "power"
        // closes only windows of `appId`, and notifies instead of acting
        function test(kind: string, appId: string): void {
            power.testApp = appId;
            power.run(kind);
        }
        function dryrun(on: bool): void { power.dryRun = on; }
        // the real flow, but only while dry-run is on (a notification replaces the command)
        function run(kind: string): void { if (power.dryRun) power.run(kind); }
        // called by the pacman hook after a transaction
        function refresh(): void {
            pendingFile.reload();
            staleProbe.running = true;
        }
        function fakepending(on: bool): void { power.testPending = on; }
        function cancel(): void { power.cancel(); }
        function force(): void { power.force(); }
    }
}
