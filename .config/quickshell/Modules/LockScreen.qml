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
            readonly property bool shown: root.locked && !root.unlocking
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
                    Quickshell.execDetached(["hyprctl", "dispatch", 'hl.dsp.dpms({ action = "on" })']);
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

                Column {
                    id: content
                    anchors.centerIn: parent
                    spacing: 16
                    opacity: surface.shown && surface.blurLevel > 0 ? 1 : 0
                    scale: surface.shown && surface.blurLevel > 0 ? 1 : 0.9
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on scale { Spring { speed: "slow" } }

                    // ---- clock + password ----
                    Item {
                        width: 760
                        height: mainCard.height
                        Elevation { anchors.fill: mainCard; radius: mainCard.radius; level: 3 }
                        Rectangle {
                            id: mainCard
                            width: parent.width
                            height: mainCol.implicitHeight + 64
                            radius: Motion.shapeExtraExtraLarge
                            color: Colors.surface_container_high

                            Column {
                                id: mainCol
                                anchors.centerIn: parent
                                width: parent.width - 64
                                spacing: 8

                                Rectangle {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    height: 40
                                    width: dateRow.implicitWidth + 32
                                    radius: height / 2
                                    color: Colors.secondary_container
                                    Row {
                                        id: dateRow
                                        anchors.centerIn: parent
                                        spacing: 8
                                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "lock"; size: 20; color: Colors.on_secondary_container }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            role: "titleMedium"
                                            color: Colors.on_secondary_container
                                            text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                                        }
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: Qt.formatDateTime(clock.date, "HH:mm")
                                    color: Colors.on_surface
                                    font.family: Typography.family
                                    font.pixelSize: 168
                                    font.weight: Font.Bold
                                    font.letterSpacing: -2
                                }

                                // password field: pill at rest, 20px squircle while typing
                                Rectangle {
                                    id: pwBox
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    width: 480
                                    height: 64
                                    radius: root.buffer.length > 0 || root.busy ? Motion.shapeLargeIncreased : height / 2
                                    color: root.failed ? Colors.error_container : Colors.surface_container_highest
                                    Behavior on radius { Spring {} }
                                    Behavior on color { ColorFade {} }

                                    transform: Translate { id: shake }
                                    SequentialAnimation {
                                        id: shakeAnim
                                        NumberAnimation { target: shake; property: "x"; to: -14; duration: 45; easing.type: Easing.OutQuad }
                                        NumberAnimation { target: shake; property: "x"; to: 14; duration: 55; easing.type: Easing.InOutQuad }
                                        NumberAnimation { target: shake; property: "x"; to: -10; duration: 55; easing.type: Easing.InOutQuad }
                                        NumberAnimation { target: shake; property: "x"; to: 10; duration: 55; easing.type: Easing.InOutQuad }
                                        NumberAnimation { target: shake; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                                    }
                                    Connections {
                                        target: root
                                        function onFailedChanged() {
                                            if (root.failed)
                                                shakeAnim.restart();
                                        }
                                    }

                                    // typed characters: alternating squircles and circles that spring in
                                    Row {
                                        anchors.centerIn: parent
                                        visible: !root.busy
                                        Repeater {
                                            model: 22
                                            delegate: Item {
                                                id: slot
                                                required property int index
                                                readonly property bool active: index < root.buffer.length
                                                property bool inRow: active
                                                onActiveChanged: {
                                                    if (active) {
                                                        collapse.stop();
                                                        inRow = true;
                                                    } else {
                                                        collapse.restart();
                                                    }
                                                }
                                                Timer {
                                                    id: collapse
                                                    interval: 160
                                                    onTriggered: slot.inRow = false
                                                }
                                                width: inRow ? 22 : 0
                                                height: 28
                                                Behavior on width { Spring {} }

                                                Rectangle {
                                                    anchors.centerIn: parent
                                                    width: 16
                                                    height: 16
                                                    radius: slot.index % 2 === 0 ? 5 : 8
                                                    color: root.failed ? Colors.on_error_container : Colors.primary
                                                    opacity: slot.active ? 1 : 0
                                                    scale: slot.active ? 1 : 0.4
                                                    Behavior on scale { Spring {} }
                                                    Behavior on opacity { Fade {} }
                                                }
                                            }
                                        }
                                    }

                                    LoadingIndicator {
                                        anchors.centerIn: parent
                                        visible: root.busy
                                        running: visible
                                    }

                                    Row {
                                        anchors.centerIn: parent
                                        spacing: 12
                                        visible: root.buffer.length === 0 && !root.busy
                                        Icon {
                                            anchors.verticalCenter: parent.verticalCenter
                                            name: root.failed ? "error" : "password"
                                            color: root.failed ? Colors.on_error_container : Colors.on_surface_variant
                                        }
                                        StyledText {
                                            anchors.verticalCenter: parent.verticalCenter
                                            role: "titleMedium"
                                            color: root.failed ? Colors.on_error_container : Colors.on_surface_variant
                                            text: root.failed ? "Incorrect password" : "Enter password"
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // ---- now playing ----
                    Item {
                        id: mediaCard
                        readonly property bool playing: !!root.player && root.player.playbackState === MprisPlaybackState.Playing
                        readonly property real len: root.player ? (root.player.length || 0) : 0
                        readonly property real pos: root.player ? (root.player.position || 0) : 0
                        function fmt(sec) {
                            const t = Math.max(0, Math.floor(sec));
                            return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
                        }

                        visible: !!root.player && (root.player.trackTitle || "").length > 0
                        width: 760
                        height: 128

                        Elevation { anchors.fill: mediaSurface; radius: mediaSurface.radius; level: 3 }
                        Rectangle {
                            id: mediaSurface
                            anchors.fill: parent
                            radius: Motion.shapeExtraLarge
                            color: Colors.surface_container_high

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 16
                                spacing: 16

                                ClippingRectangle {
                                    Layout.preferredWidth: 96
                                    Layout.preferredHeight: 96
                                    radius: Motion.shapeLarge
                                    color: Colors.primary_container
                                    Icon {
                                        anchors.centerIn: parent
                                        visible: art.status !== Image.Ready
                                        name: "music_note"
                                        size: 40
                                        color: Colors.on_primary_container
                                    }
                                    Image {
                                        id: art
                                        anchors.fill: parent
                                        source: root.player ? (root.player.trackArtUrl || "") : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    Marquee {
                                        Layout.fillWidth: true
                                        centered: false
                                        role: "titleMedium"
                                        jp: true
                                        text: root.player ? (root.player.trackTitle || "") : ""
                                    }
                                    Marquee {
                                        Layout.fillWidth: true
                                        centered: false
                                        role: "bodyMedium"
                                        jp: true
                                        color: Colors.on_surface_variant
                                        visible: text.length > 0
                                        text: root.player ? (root.player.trackArtist || "") : ""
                                    }
                                    LinearProgress {
                                        Layout.fillWidth: true
                                        Layout.topMargin: 8
                                        visible: mediaCard.len > 0
                                        value: mediaCard.pos / Math.max(1, mediaCard.len)
                                        MouseArea {
                                            anchors.fill: parent
                                            anchors.margins: -8
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: mouse => root.player.position = mediaCard.len * Math.max(0, Math.min(1, (mouse.x - 8) / parent.width))
                                        }
                                    }
                                    RowLayout {
                                        Layout.fillWidth: true
                                        visible: mediaCard.len > 0
                                        StyledText { role: "labelSmall"; color: Colors.on_surface_variant; text: mediaCard.fmt(mediaCard.pos) }
                                        Item { Layout.fillWidth: true }
                                        StyledText { role: "labelSmall"; color: Colors.on_surface_variant; text: mediaCard.fmt(mediaCard.len) }
                                    }
                                }

                                Row {
                                    spacing: 8
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: "skip_previous"
                                        style: "tonal"
                                        onClicked: root.player.previous()
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: "m"
                                        style: "filled"
                                        icon: mediaCard.playing ? "pause" : "play_arrow"
                                        // round while paused, square while playing
                                        restRadius: mediaCard.playing ? Motion.shapeLarge : height / 2
                                        onClicked: root.player.togglePlaying()
                                    }
                                    IconButton {
                                        anchors.verticalCenter: parent.verticalCenter
                                        icon: "skip_next"
                                        style: "tonal"
                                        onClicked: root.player.next()
                                    }
                                }
                            }
                        }
                    }
                }

                // ---- power actions: floating toolbar ----
                Item {
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 40
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: toolbar.width
                    height: toolbar.height
                    opacity: content.opacity

                    Elevation { anchors.fill: toolbar; radius: toolbar.radius; level: 3 }
                    Rectangle {
                        id: toolbar
                        width: actions.implicitWidth + 16
                        height: 64
                        radius: height / 2
                        color: Colors.surface_container

                        Row {
                            id: actions
                            anchors.centerIn: parent
                            spacing: 4
                            IconButton {
                                icon: "bedtime"
                                style: "tonal"
                                color: Colors.tertiary_container
                                contentColor: Colors.on_tertiary_container
                                onClicked: Quickshell.execDetached(["systemctl", "suspend"])
                            }
                            IconButton {
                                icon: "restart_alt"
                                style: "tonal"
                                onClicked: Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl reboot"])
                            }
                            IconButton {
                                icon: "power_settings_new"
                                style: "tonal"
                                color: Colors.error_container
                                contentColor: Colors.on_error_container
                                onClicked: Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl poweroff"])
                            }
                        }
                    }
                }
            }
        }
    }
}
