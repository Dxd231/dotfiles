pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import Quickshell.Services.Pam
import Quickshell.Services.Mpris

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
        running: root.locked && !!root.player && (root.player.playbackState === MprisPlaybackState.Playing || root.player.isPlaying) && root.player.positionSupported
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
                source: {
                    const scr = surface.screen;
                    return (scr && scr.name) ? ("file://" + root.shotPath(scr.name)) : "";
                }
                cache: false
                fillMode: Image.PreserveAspectCrop
                asynchronous: false
                layer.enabled: true
                layer.effect: MultiEffect {
                    blurEnabled: true
                    blur: surface.blurLevel
                    blurMax: 32
                    brightness: 0
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.theme.background, 0.45)
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
                    anchors.centerIn: parent
                    spacing: 18
                    opacity: 0
                    scale: 0.90
                    transformOrigin: Item.Center
                    transform: Translate {
                        id: contentTrans
                        y: 20
                    }

                    Component.onCompleted: popIn.start()

                    ParallelAnimation {
                        id: popIn
                        NumberAnimation { target: surface; property: "blurLevel"; to: 1; duration: 320; easing.type: Easing.OutCubic }
                        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 220; easing.type: Easing.OutQuad }
                        NumberAnimation { target: content; property: "scale"; to: 1.0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.12 }
                        NumberAnimation { target: contentTrans; property: "y"; to: 0; duration: 340; easing.type: Easing.OutBack; easing.overshoot: 1.12 }
                        NumberAnimation { target: bottomBar; property: "opacity"; to: 1; duration: 260; easing.type: Easing.OutQuad }
                    }

                    ParallelAnimation {
                        id: exitAnim
                        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InQuad }
                        NumberAnimation { target: content; property: "scale"; to: 1.05; duration: 240; easing.type: Easing.InQuad }
                        NumberAnimation { target: contentTrans; property: "y"; to: -12; duration: 240; easing.type: Easing.InQuad }
                        NumberAnimation { target: bottomBar; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InQuad }
                        NumberAnimation { target: surface; property: "blurLevel"; to: 0; duration: 340; easing.type: Easing.InOutQuad }
                    }

                    Connections {
                        target: root
                        function onUnlockingChanged() {
                            if (root.unlocking) {
                                popIn.stop();
                                exitAnim.start();
                            }
                        }
                    }

                    // Card 1: Clock, Date, and Password Card
                    Rectangle {
                        id: mainCard
                        width: 660
                        height: mainCol.implicitHeight + 64
                        radius: 32
                        color: Qt.lighter(root.theme.background, 1.15)
                        border.width: 0
                        clip: true

                        Column {
                            id: mainCol
                            anchors.centerIn: parent
                            width: parent.width - 64
                            spacing: 14

                            // Top Header: Date and small lock badge
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                spacing: 10

                                Image {
                                    id: lockBadge
                                    anchors.verticalCenter: parent.verticalCenter
                                    source: "../assets/lock-simple-fill.svg"
                                    sourceSize.width: 18
                                    sourceSize.height: 18
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: root.theme.on_background
                                    }
                                    opacity: 0.55
                                }

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                                    color: root.theme.on_background
                                    opacity: 0.75
                                    font.pixelSize: 19
                                    font.family: root.settings.fontmedium
                                }
                            }

                            // Clock
                            Text {
                                id: clockModule
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: Qt.formatDateTime(clock.date, "HH:mm")
                                color: root.theme.on_background
                                font.pixelSize: 130
                                font.family: root.settings.fontdefault
                                font.bold: true
                            }

                            // Spacing
                            Item { width: 1; height: 6 }

                            // Password box
                            Rectangle {
                                id: pwBox
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: 440
                                height: 62
                                radius: 20
                                color: root.failed
                                    ? Qt.alpha(root.theme.error, 0.18)
                                    : (root.buffer.length > 0 ? Qt.alpha(root.theme.on_background, 0.09) : Qt.alpha(root.theme.on_background, 0.05))
                                border.width: 0

                                Behavior on color {
                                    ColorAnimation { duration: 180 }
                                }

                                transform: Translate {
                                    id: pwTrans
                                    x: 0
                                }

                                SequentialAnimation {
                                    id: shakeAnim
                                    running: false
                                    NumberAnimation { target: pwTrans; property: "x"; to: -14; duration: 45; easing.type: Easing.OutQuad }
                                    NumberAnimation { target: pwTrans; property: "x"; to: 14; duration: 55; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pwTrans; property: "x"; to: -10; duration: 55; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pwTrans; property: "x"; to: 10; duration: 55; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pwTrans; property: "x"; to: -4; duration: 45; easing.type: Easing.InOutQuad }
                                    NumberAnimation { target: pwTrans; property: "x"; to: 0; duration: 45; easing.type: Easing.OutQuad }
                                }

                                Connections {
                                    target: root
                                    function onFailedChanged() {
                                        if (root.failed)
                                            shakeAnim.restart();
                                    }
                                }

                                // Typing Dots: Smooth fade and expansion animation
                                Row {
                                    anchors.centerIn: parent
                                    Repeater {
                                        model: 22
                                        Item {
                                            id: slot
                                            required property int index
                                            readonly property bool active: slot.index < root.buffer.length
                                            width: active ? 26 : 0
                                            height: 26
                                            clip: true

                                            Behavior on width {
                                                NumberAnimation { duration: 170; easing.type: Easing.OutCirc }
                                            }

                                            Rectangle {
                                                anchors.centerIn: parent
                                                width: 16
                                                height: 16
                                                radius: 8
                                                color: root.failed ? (root.theme.error || "#ff6b6b") : root.theme.primary
                                                opacity: slot.active ? 1 : 0

                                                Behavior on opacity {
                                                    NumberAnimation { duration: 160 }
                                                }
                                                Behavior on color {
                                                    ColorAnimation { duration: 150 }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Placeholder / Status
                                Row {
                                    anchors.centerIn: parent
                                    spacing: 10
                                    visible: root.buffer.length === 0

                                    Image {
                                        id: pwPlaceholderIcon
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: root.failed ? "../assets/lock-simple-fill.svg" : "../assets/keyboard.svg"
                                        sourceSize.width: 20
                                        sourceSize.height: 20
                                        fillMode: Image.PreserveAspectFit
                                        opacity: root.failed ? 0.9 : 0.45
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.failed ? (root.theme.error || "#ff6b6b") : root.theme.on_background
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: root.failed ? "Incorrect password" : (root.busy ? "Verifying…" : "Enter password")
                                        color: root.failed ? (root.theme.error || "#ff6b6b") : root.theme.on_background
                                        opacity: root.failed ? 0.9 : 0.5
                                        font.pixelSize: 18
                                        font.family: root.settings.fontdefault
                                    }
                                }
                            }
                        }
                    }

                    // Card 2: Now Playing Card
                    Rectangle {
                        id: mediaCard
                        width: 660
                        height: 120
                        radius: 26
                        color: Qt.lighter(root.theme.background, 1.15)
                        border.width: 0
                        visible: !!root.player && (root.player.trackTitle || "").length > 0
                        clip: true

                        readonly property bool isPlaying: {
                            if (!root.player) return false;
                            if (root.player.playbackState !== undefined) {
                                return root.player.playbackState === MprisPlaybackState.Playing;
                            }
                            return !!root.player.isPlaying;
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.margins: 16
                            spacing: 18

                            // Album art container
                            Rectangle {
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 88
                                radius: 18
                                color: Qt.alpha(root.theme.on_background, 0.08)
                                clip: true

                                Image {
                                    id: trackArt
                                    anchors.fill: parent
                                    source: root.player ? (root.player.trackArtUrl || "") : ""
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    visible: status === Image.Ready
                                }

                                Image {
                                    anchors.centerIn: parent
                                    source: "../assets/music-notes-fill.svg"
                                    sourceSize.width: 38
                                    sourceSize.height: 38
                                    visible: trackArt.status !== Image.Ready
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: root.theme.primary
                                    }
                                    opacity: 0.7
                                }
                            }

                            // Track info + progress bar
                            ColumnLayout {
                                id: infoLayout
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 4

                                readonly property real len: root.player ? (root.player.length || 0) : 0
                                readonly property real pos: root.player ? (root.player.position || 0) : 0

                                function fmt(sec) {
                                    const t = Math.max(0, Math.floor(sec));
                                    return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
                                }

                                MarqueeText {
                                    Layout.fillWidth: true
                                    text: root.player ? (root.player.trackTitle || "") : ""
                                    color: root.theme.on_background
                                    textOpacity: 0.95
                                    pixelSize: 18
                                    bold: true
                                    family: root.settings.fontjp
                                }

                                MarqueeText {
                                    Layout.fillWidth: true
                                    text: root.player ? (root.player.trackArtist || "") : ""
                                    visible: text.length > 0
                                    color: root.theme.on_background
                                    textOpacity: 0.65
                                    pixelSize: 14
                                    family: root.settings.fontjp
                                }

                                // Progress bar
                                Rectangle {
                                    Layout.fillWidth: true
                                    Layout.topMargin: 4
                                    height: 5
                                    radius: 3
                                    visible: infoLayout.len > 0
                                    color: Qt.alpha(root.theme.on_background, 0.12)

                                    Rectangle {
                                        height: parent.height
                                        radius: 3
                                        width: parent.width * Math.max(0, Math.min(1, infoLayout.pos / Math.max(1, infoLayout.len)))
                                        color: root.theme.primary
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: mouse => {
                                            if (root.player && infoLayout.len > 0) {
                                                const fraction = Math.max(0, Math.min(1, mouse.x / width));
                                                root.player.position = infoLayout.len * fraction;
                                            }
                                        }
                                    }
                                }

                                // Timestamps
                                Item {
                                    Layout.fillWidth: true
                                    height: 16
                                    visible: infoLayout.len > 0

                                    Text {
                                        anchors.left: parent.left
                                        text: infoLayout.fmt(infoLayout.pos)
                                        color: root.theme.on_background
                                        opacity: 0.5
                                        font.pixelSize: 12
                                        font.family: root.settings.fontdefault
                                    }

                                    Text {
                                        anchors.right: parent.right
                                        text: infoLayout.fmt(infoLayout.len)
                                        color: root.theme.on_background
                                        opacity: 0.5
                                        font.pixelSize: 12
                                        font.family: root.settings.fontdefault
                                    }
                                }
                            }

                            // Playback controls
                            Row {
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 10

                                // Previous button
                                Rectangle {
                                    width: 42
                                    height: 42
                                    radius: 21
                                    color: prevMouse.containsMouse ? Qt.alpha(root.theme.on_background, 0.12) : Qt.alpha(root.theme.on_background, 0.05)
                                    scale: prevMouse.pressed ? 0.90 : (prevMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: prevMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: if (root.player && typeof root.player.previous === "function") root.player.previous()
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        source: "../assets/skip-back-bold.svg"
                                        sourceSize.width: 18
                                        sourceSize.height: 18
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.theme.on_background
                                        }
                                        opacity: 0.85
                                    }
                                }

                                // Play / Pause button
                                Rectangle {
                                    width: 50
                                    height: 50
                                    radius: 25
                                    color: root.theme.primary
                                    scale: playMouse.pressed ? 0.90 : (playMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }

                                    MouseArea {
                                        id: playMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: {
                                            if (!root.player) return;
                                            if (typeof root.player.togglePlaying === "function") {
                                                root.player.togglePlaying();
                                            } else if (typeof root.player.playPause === "function") {
                                                root.player.playPause();
                                            } else if (mediaCard.isPlaying) {
                                                root.player.pause();
                                            } else {
                                                root.player.play();
                                            }
                                        }
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        source: mediaCard.isPlaying ? "../assets/pause-bold.svg" : "../assets/play-bold.svg"
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.theme.background
                                        }
                                    }
                                }

                                // Next button
                                Rectangle {
                                    width: 42
                                    height: 42
                                    radius: 21
                                    color: nextMouse.containsMouse ? Qt.alpha(root.theme.on_background, 0.12) : Qt.alpha(root.theme.on_background, 0.05)
                                    scale: nextMouse.pressed ? 0.90 : (nextMouse.containsMouse ? 1.06 : 1.0)
                                    Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }
                                    Behavior on color { ColorAnimation { duration: 120 } }

                                    MouseArea {
                                        id: nextMouse
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        hoverEnabled: true
                                        onClicked: if (root.player && typeof root.player.next === "function") root.player.next()
                                    }

                                    Image {
                                        anchors.centerIn: parent
                                        source: "../assets/skip-forward-bold.svg"
                                        sourceSize.width: 18
                                        sourceSize.height: 18
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.theme.on_background
                                        }
                                        opacity: 0.85
                                    }
                                }
                            }
                        }
                    }
                }

                // Card 3: Bottom Quick Actions Pill
                Rectangle {
                    id: bottomBar
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 36
                    anchors.horizontalCenter: parent.horizontalCenter
                    height: 54
                    width: actionRow.implicitWidth + 28
                    radius: 27
                    color: Qt.lighter(root.theme.background, 1.15)
                    border.width: 0
                    opacity: 0

                    Row {
                        id: actionRow
                        anchors.centerIn: parent
                        spacing: 10

                        // Suspend / Sleep
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: suspMouse.containsMouse ? Qt.alpha(root.theme.on_background, 0.12) : "transparent"
                            scale: suspMouse.pressed ? 0.90 : (suspMouse.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: suspMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(["systemctl", "suspend"])
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "../assets/moon.svg"
                                sourceSize.width: 20
                                sourceSize.height: 20
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.theme.on_background
                                }
                                opacity: 0.8
                            }
                        }

                        // Reboot
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: rebMouse.containsMouse ? Qt.alpha(root.theme.on_background, 0.12) : "transparent"
                            scale: rebMouse.pressed ? 0.90 : (rebMouse.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: rebMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(["sh", "-c", "hyprshutdown --post-cmd 'systemctl reboot'"])
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "../assets/arrow-clockwise-fill.svg"
                                sourceSize.width: 20
                                sourceSize.height: 20
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.theme.on_background
                                }
                                opacity: 0.8
                            }
                        }

                        // Power Off
                        Rectangle {
                            width: 42
                            height: 42
                            radius: 21
                            color: powMouse.containsMouse ? Qt.alpha(root.theme.error, 0.20) : "transparent"
                            scale: powMouse.pressed ? 0.90 : (powMouse.containsMouse ? 1.08 : 1.0)
                            Behavior on scale { NumberAnimation { duration: 120; easing.type: Easing.OutCirc } }
                            Behavior on color { ColorAnimation { duration: 120 } }
                            MouseArea {
                                id: powMouse
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                hoverEnabled: true
                                onClicked: Quickshell.execDetached(["sh", "-c", "hyprshutdown --post-cmd 'systemctl poweroff'"])
                            }

                            Image {
                                anchors.centerIn: parent
                                source: "../assets/power-fill.svg"
                                sourceSize.width: 20
                                sourceSize.height: 20
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: powMouse.containsMouse ? (root.theme.error || "#ff6b6b") : root.theme.on_background
                                }
                                opacity: 0.8
                            }
                        }
                    }
                }
            }
        }
    }
}
