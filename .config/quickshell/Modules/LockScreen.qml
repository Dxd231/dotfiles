pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam

// Usage: instantiate once in shell.qml, same as your other modules:
//   LockScreen { theme: root.theme; settings: root.settings }
// Lock with:  qs ipc call lockscreen lock      (add `-c <name>` if you use a named config)
Scope {
    id: root
    property var theme
    property var settings

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

    Timer { id: unlockTimer; interval: 440; onTriggered: root.finishUnlock() }

    property string buffer: ""      // what has been typed so far (shared across monitors)
    property bool failed: false
    property bool busy: false

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

    // ---- now playing ----
    // Pass in shell.qml's activePlayer so the lockscreen shows the same player as the bar
    property var player: null

    // Single-line text that scrolls back and forth when it's wider than its box
    // (same behaviour as the marquee in the bar's MPRIS module).
    component MarqueeText: Item {
        id: mq
        property string text: ""
        property color color: "white"
        property int pixelSize: 16
        property bool bold: false
        property string family: ""
        property real textOpacity: 1
        property int threshold: 10

        height: label.implicitHeight
        clip: true

        readonly property real overflow: Math.max(0, label.implicitWidth - width)
        readonly property bool shouldScroll: overflow > threshold

        Text {
            id: label
            anchors.verticalCenter: parent.verticalCenter
            text: mq.text
            color: mq.color
            opacity: mq.textOpacity
            font.pixelSize: mq.pixelSize
            font.bold: mq.bold
            font.family: mq.family

            transform: Translate { id: trans; x: 0 }

            onTextChanged: {
                anim.stop();
                trans.x = 0;
                if (mq.shouldScroll)
                    anim.restart();
            }

            SequentialAnimation {
                id: anim
                loops: Animation.Infinite
                running: mq.shouldScroll

                onRunningChanged: {
                    if (!running)
                        trans.x = 0;
                }

                PauseAnimation { duration: 1800 }
                NumberAnimation {
                    target: trans
                    property: "x"
                    to: -mq.overflow
                    duration: Math.max(2000, mq.overflow * 32)
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 1400 }
                NumberAnimation {
                    target: trans
                    property: "x"
                    to: 0
                    duration: 3000
                    easing.type: Easing.Linear
                }
                PauseAnimation { duration: 500 }
            }
        }
    }

    // MPRIS doesn't push position updates, so poke it once a second while playing
    Timer {
        interval: 1000
        repeat: true
        running: root.locked && !!root.player && root.player.isPlaying && root.player.positionSupported
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

        // One surface is created automatically per monitor
        WlSessionLockSurface {
            id: surface
            color: root.theme.background

            // drives the pop-up: background blurs in, content scales/fades up
            property real blurLevel: 0

            // frozen, blurred screenshot taken just before locking
            Image {
                anchors.fill: parent
                source: "file://" + root.shotPath(surface.screen.name)
                cache: false
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: surface.blurLevel
                    blurMax: 64
                    brightness: 0
                }
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

                Component.onCompleted: {
                    if (root.locked)
                        Qt.callLater(() => keys.forceActiveFocus());
                }

                Timer {
                    id: focusGuard
                    interval: 250
                    repeat: true
                    running: root.locked && !root.busy
                    onTriggered: {
                        if (!keys.activeFocus)
                            keys.forceActiveFocus();
                    }
                }

                Keys.onPressed: event => {
                    if (root.busy || root.unlocking) {
                        event.accepted = true;
                        return;
                    }
                    Quickshell.execDetached([
                        "hyprctl", "dispatch",
                        'hl.dsp.dpms({ action = "on" })'
                    ])
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
                    event.accepted = true;
                }

                Column {
                    id: content
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 100
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 24
                    opacity: 0
                    scale: 0.9
                    transformOrigin: Item.Center

                    Component.onCompleted: popIn.start()

                    ParallelAnimation {
                        id: popIn
                        NumberAnimation { target: surface; property: "blurLevel"; to: 1; duration: 350; easing.type: Easing.OutCubic }
                        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 250; easing.type: Easing.OutCubic }
                        NumberAnimation { target: content; property: "scale"; to: 1; duration: 380; easing.type: Easing.OutBack; easing.overshoot: 1.2 }
                    }

                    ParallelAnimation {
                        id: exitAnim
                        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 200; easing.type: Easing.InCubic }
                        NumberAnimation { target: content; property: "scale"; to: 1.06; duration: 260; easing.type: Easing.InCubic }
                        NumberAnimation { target: surface; property: "blurLevel"; to: 0; duration: 380; easing.type: Easing.InOutCubic }
                    }

                    Connections {
                        target: root
                        function onUnlockingChanged() { if (root.unlocking) { popIn.stop(); exitAnim.start(); } }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "HH:mm")
                        color: root.theme.on_background
                        font.pixelSize: 186
                        font.family: root.settings.fontdefault
                        font.bold: true
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                        color: root.theme.on_background
                        opacity: 0.6
                        font.pixelSize: 20
                        font.family: root.settings.fontmedium
                    }

                    // password box: one dot per typed character
                    Rectangle {
                        id: pwBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 320
                        height: 52
                        radius: 14
                        color: Qt.alpha(root.theme.background, 0.8)
                        border.width: 3
                        border.color: root.failed ? (root.theme.error || "#ff6b6b") : root.theme.primary
                        opacity: root.busy ? 0.5 : 1
                        Behavior on border.color { ColorAnimation { duration: 150 } }
                        Behavior on opacity { NumberAnimation { duration: 150 } }

                        Row {
                            anchors.centerIn: parent
                            Repeater {
                                model: 18
                                Item {
                                    id: slot
                                    required property int index
                                    readonly property bool active: slot.index < root.buffer.length
                                    width: active ? 16 : 0
                                    height: 12
                                    clip: true

                                    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCirc } }

                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 12
                                        height: 12
                                        radius: 6
                                        color: root.theme.primary
                                        opacity: slot.active ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 160 } }
                                    }
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.buffer.length === 0
                            text: root.failed ? "Wrong password" : (root.busy ? "Checking…" : "Password")
                            color: root.failed ? (root.theme.error || "#ff6b6b") : root.theme.on_background
                            opacity: 0.5
                            font.pixelSize: 18
                            font.family: root.settings.fontmedium
                        }
                    }

                    // now playing: art on the left, track info on the right
                    Row {
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 20
                        visible: !!root.player && (root.player.trackTitle || "").length > 0

                        ClippingRectangle {
                            width: 250
                            height: 250
                            radius: 16
                            color: Qt.alpha(root.theme.on_background, 0.08)
                            visible: art.status === Image.Ready

                            Image {
                                id: art
                                anchors.fill: parent
                                source: root.player ? (root.player.trackArtUrl || "") : ""
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                            }
                        }

                        Column {
                            id: info
                            anchors.verticalCenter: parent.verticalCenter
                            width: 300
                            spacing: 4

                            readonly property real len: root.player ? (root.player.length || 0) : 0
                            readonly property real pos: root.player ? (root.player.position || 0) : 0

                            function fmt(sec) {
                                const t = Math.max(0, Math.floor(sec));
                                return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
                            }

                            MarqueeText {
                                width: parent.width
                                text: root.player ? (root.player.trackTitle || "") : ""
                                color: root.theme.on_background
                                textOpacity: 0.9
                                pixelSize: 25
                                bold: true
                                family: root.settings.fontjp
                            }
                            MarqueeText {
                                width: parent.width
                                text: root.player ? (root.player.trackArtist || "") : ""
                                visible: text.length > 0
                                color: root.theme.on_background
                                textOpacity: 0.7
                                pixelSize: 18
                                family: root.settings.fontjp
                            }
                            Text {
                                width: parent.width
                                text: root.player ? (root.player.trackAlbum || "") : ""
                                visible: text.length > 0
                                color: root.theme.on_background
                                opacity: 0.45
                                font.pixelSize: 14
                                font.family: root.settings.fontjp
                                elide: Text.ElideRight
                            }

                            Item { width: 1; height: 8; visible: info.len > 0 }

                            // progress bar
                            Rectangle {
                                width: parent.width
                                height: 4
                                radius: 2
                                visible: info.len > 0
                                color: Qt.alpha(root.theme.on_background, 0.15)

                                Rectangle {
                                    height: parent.height
                                    radius: 2
                                    width: parent.width * Math.max(0, Math.min(1, info.pos / Math.max(1, info.len)))
                                    color: root.theme.primary
                                }
                            }

                            Item {
                                width: parent.width
                                height: 14
                                visible: info.len > 0
                                Text {
                                    anchors.left: parent.left
                                    text: info.fmt(info.pos)
                                    color: root.theme.on_background
                                    opacity: 0.5
                                    font.pixelSize: 12
                                    font.family: root.settings.fontdefault
                                }
                                Text {
                                    anchors.right: parent.right
                                    text: info.fmt(info.len)
                                    color: root.theme.on_background
                                    opacity: 0.5
                                    font.pixelSize: 12
                                    font.family: root.settings.fontdefault
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
