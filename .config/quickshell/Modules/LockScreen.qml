pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pam
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components

// Session lock. Lock with `qs ipc call lockscreen lock` (or the power menu).
// The screen is captured with grim before locking (once locked, screencopy only sees the
// lock surface), then shown blurred behind the clock / password card.
Scope {
    id: root


    property bool locked: false
    property bool unlocking: false

    function beginUnlock() {
        if (root.unlocking) return; 
        root.unlocking = true;
        unlockTimer.start();
    }

    function finishUnlock() {
        root.locked = false;
        root.cleanup();
        root.buffer = ""; root.failed = false; root.unlocking = false;
    }

    Timer { id: unlockTimer; interval: 700; onTriggered: root.finishUnlock() }

    property string buffer: ""      // what has been typed so far (shared across monitors)
    property bool failed: false
    property bool busy: false
    property int keyTick: 0         // bumped on every key press so the view can ripple
    property bool capsOn: false
    property double lastWake: 0

    // wake the display on input, but not with a hyprctl call per key press
    function wake() {
        const now = Date.now();
        if (now - root.lastWake < 3000)
            return;
        root.lastWake = now;
        Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "on" })']);
    }

    // Caps Lock: read the keyboard LED (any keyboard's LED being lit counts)
    Process {
        id: capsProc
        command: ["sh", "-c", "cat /sys/class/leds/*capslock/brightness 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: root.capsOn = text.split(/\s+/).some(v => v === "1")
        }
    }
    function pollCaps() {
        if (!capsProc.running)
            capsProc.running = true;
    }
    Timer {
        interval: 400
        repeat: true
        running: root.locked
        triggeredOnStart: true
        onTriggered: root.pollCaps()
    }
    // the LED updates just after the key event
    Timer { id: capsSoon; interval: 60; onTriggered: root.pollCaps() }

    // ---- screenshot background ----
    // The screen has to be captured BEFORE the session lock is active; once locked, the
    // compositor only shows lock surfaces, so screencopy would just return the lock/black.
    property int shotId: 0
    readonly property string shotDir: Quickshell.env("XDG_RUNTIME_DIR") || "/tmp"
    function shotPath(screenName) {
        return root.shotDir + "/qs-lock-" + screenName + "-" + root.shotId + ".png";
    }

    Process {
        id: captureProc
        // grim captures every output in parallel; when they're all done we lock
        onExited: root.locked = true
    }

    // Wait for whatever triggered the lock (e.g. the power menu's close animation, ~420ms)
    // to disappear before taking the screenshot.
    Timer {
        id: captureDelay
        interval: 500
        repeat: false
        onTriggered: root.capture()
    }

    function lock() {
        if (root.locked || captureProc.running || captureDelay.running)
            return;
        captureDelay.start();
    }

    function capture() {
        root.buffer = "";
        root.failed = false;
        root.shotId++;
        const cmds = Quickshell.screens.map(s => "grim -o '" + s.name + "' '" + root.shotPath(s.name) + "'");
        captureProc.command = ["sh", "-c", cmds.join(" & ") + " & wait"];
        captureProc.running = true;
    }

    function cleanup() {
        Quickshell.execDetached(["sh", "-c", "rm -f '" + root.shotDir + "'/qs-lock-*.png"]);
    }

    IpcHandler {
        target: "lockscreen"
        function lock(): void { root.lock() }
    }

    // Pass in shell.qml's activePlayer so the lock screen shows the same player as the bar
    property var player: null

    // MPRIS doesn't push position updates, so poke it once a second while playing
    Timer {
        interval: 1000
        repeat: true
        running: root.locked && !!root.player && root.player.playbackState === MprisPlaybackState.Playing && root.player.positionSupported
        onTriggered: root.player.positionChanged()
    }

    SystemClock {
        id: clock
        precision: SystemClock.Seconds
    }

    // ---- authentication ----
    PamContext {
        id: pam
        // config: "login" -> /etc/pam.d/login. If auth never succeeds, check that file
        // exists on your distro (or create /etc/pam.d/quickshell and set config: "quickshell").

        onPamMessage: {
            // PAM is asking for the password; hand it what we've typed
            if (responseRequired)
                respond(root.buffer);
        }

        onCompleted: result => {
            root.busy = false;
            if (result === PamResult.Success) {
                root.beginUnlock();
            } else {
                root.failed = true;
                root.buffer = "";
            }
        }
    }

    function submit() {
        if (root.busy || root.buffer.length === 0)
            return;
        root.busy = true;
        root.failed = false;
        pam.start();
    }

    // ---- the lock itself ----
    WlSessionLock {
        id: lock
        locked: root.locked

        // one surface per monitor
        WlSessionLockSurface {
            id: surface
            color: Colors.background

            // drives the entrance: background blurs in, content springs up
            property real blurLevel: 0
            Component.onCompleted: blurLevel = 1

            Behavior on blurLevel { Fade { speed: "slow" } }
            Connections {
                target: root
                function onUnlockingChanged() {
                    if (root.unlocking)
                        surface.blurLevel = 0;
                }
            }

            // frozen, blurred screenshot taken just before locking
            Image {
                anchors.fill: parent
                source: surface.screen && surface.screen.name ? "file://" + root.shotPath(surface.screen.name) : ""
                cache: false
                fillMode: Image.PreserveAspectCrop
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: surface.blurLevel
                    blurMax: 32
                }
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colors.scrim, 0.32)
                opacity: surface.blurLevel
            }

            FocusScope {
                id: keys
                anchors.fill: parent
                focus: true

                Connections {
                    target: root
                    function onLockedChanged() {
                        if (root.locked)
                            Qt.callLater(() => keys.forceActiveFocus());
                    }
                }
                Component.onCompleted: if (root.locked) Qt.callLater(() => keys.forceActiveFocus())
                Timer {
                    interval: 250
                    repeat: true
                    running: root.locked && !root.busy
                    onTriggered: if (!keys.activeFocus) keys.forceActiveFocus()
                }

                Keys.onPressed: event => {
                    event.accepted = true;
                    if (root.busy || root.unlocking)
                        return;
                    root.wake();
                    if (event.key === Qt.Key_CapsLock) {
                        capsSoon.restart();
                        return;
                    }
                    root.keyTick++;
                    if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                        root.submit();
                    } else if (event.key === Qt.Key_Backspace) {
                        root.buffer = root.buffer.slice(0, -1);
                    } else if (event.key === Qt.Key_Escape) {
                        root.buffer = "";
                    } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32) {
                        root.buffer += event.text;
                        root.failed = false;
                    }
                }

                LockView {
                    anchors.fill: parent
                    date: clock.date
                    buffer: root.buffer
                    failed: root.failed
                    busy: root.busy
                    unlocking: root.unlocking
                    shown: root.locked
                    capsOn: root.capsOn
                    keyTick: root.keyTick
                    player: root.player
                    onSuspendRequested: Quickshell.execDetached(["systemctl", "suspend"])
                    onRestartRequested: Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl reboot"])
                    onPoweroffRequested: Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl poweroff"])
                }
            }
        }
    }
}
