pragma ComponentBehavior: Bound
//@ pragma UseQApplication
import Quickshell
import Quickshell.Hyprland
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import QtQuick.Layouts
import Quickshell.Wayland
import QtQuick.Effects
import Quickshell.Widgets
import Qt5Compat.GraphicalEffects
import "./Modules"

ShellRoot {
    id: shell

    /* ScreenFrame {
        id: screenFrame
        theme: root.theme
        // topOffset: panelbar.height   // bind directly instead of hardcoding, see below
    } */

    LockScreen { theme: root.theme; settings: root.settings; player: shell.activePlayer }

    AppDock {
        id: appdock
        theme: root.theme
        settings: root.settings
    }

    VolumePopup {
        theme: root.theme
        settings: root.settings
        anchorItem: volumeModule
        iconHovered: volumeModule.hovered
    }

    Notifications {
        id: notifications
        theme: root.theme
        settings: root.settings
        cpuPercent: root.cpuPercent
        memPercent: root.memValue
    }

    EmojiPicker {
        id: emojiPicker
        theme: root.theme
        settings: root.settings
        copyToast: copyToast
    }

    PowerMenu {
        id: powerMenu
        theme: root.theme
        settings: root.settings
    }

    WallpaperSwitcher {
        id: wallpaperSwitcher
        theme: root.theme
        settings: root.settings
        fontdefault: root.settings.fontdefault
    }

    AppLauncher {
        id: appLauncher
        theme: root.theme
        settings: root.settings
        global_radius: root.global_radius
    }

    OnScreenDisplay {
        id: osd
        theme: root.theme
    }

    CopyToast {
        id: copyToast
        theme: root.theme
        settings: root.settings
    }

    ClipboardManager {
        id: clipboardManager
        theme: root.theme
        settings: root.settings
        global_radius: root.global_radius
        copyToast: copyToast
    }

    ActiveArch {}

    // Get activePlayer
    readonly property var activePlayer: {
        var players = Mpris.players.values || []; // Ensure players is an array, even if Mpris.players is undefined
        var foundPlayer = null;
        for (var i = 0; i < players.length; i++) {
            var player = players[i];
            if (player.identity.toLowerCase() === root.preferredPlayer.toLowerCase()) {
                return player;
            }
            if (player.playbackState === MprisPlaybackState.Playing || player.playbackState === MprisPlaybackState.Paused) {
                foundPlayer = player;
            }
        }
        return foundPlayer;
    }

    // sync system clock
    SystemClock {
        id: clock
        precision: SystemClock.Minutes
    }

    QtObject {
        id: root
        property int fontsize: 12
        property var settings: Settings
        readonly property bool hasPlayer: shell.activePlayer !== null && shell.activePlayer !== undefined
        property var theme: Colors
        property int global_radius: 10
        readonly property var kanjiNumbers: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

        readonly property string time: Qt.formatDateTime(clock.date, "hh:mm")
        readonly property string dateString: Qt.formatDateTime(clock.date, "ddd dd MMM")

        property string preferredPlayer: "spotify"

        // Fixed vinyl spin speed (degrees per rotateTimer tick). No longer BPM-driven.
        property real discSpinSpeed: 0.62

        property string memoryUsage: "0%"
        property string memformat: ""
        readonly property real memValue: parseFloat(memformat) || 0
        property int memCount: 0
        property bool memPercent: false
        property real cpuPercent: 0
        property string calendar: ""
        property string networkInfo: "Disconnected"
        property string networkType: "disconnected"
        property string playing: "No Media"
    }

    //Cpu

    Process {
        id: cpuStatProc
        command: ["cat", "/proc/stat"]
        running: true
        property var prevIdle: 0
        property var prevTotal: 0
        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split("\n")[0].trim().split(/\s+/).slice(1).map(Number);
                const idle = parts[3] + parts[4]; // idle + iowait
                const total = parts.reduce((a, b) => a + b, 0);
                const totalDelta = total - cpuStatProc.prevTotal;
                if (cpuStatProc.prevTotal > 0 && totalDelta > 0)
                    root.cpuPercent = 100 * (1 - (idle - cpuStatProc.prevIdle) / totalDelta);
                cpuStatProc.prevIdle = idle;
                cpuStatProc.prevTotal = total;
            }
        }
    }

    //Memory
    Process {
        id: memProcess
        command: ["sh", "-c", "free -m | awk '/M/ { printf \"%d|%.0f%%|%.0f / %.0fGB\\n\", $3, ($3/$2)*100, $3/1024, $2/1024 }'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.trim().split("|");
                if (parts.length >= 3) {
                    root.memCount = parseInt(parts[0]) || 0;
                    root.memformat = parts[1];
                    root.memoryUsage = parts[2];
                }
            }
        }
    }

    property var memTimer: Timer {
        interval: 4000
        running: true
        repeat: true
        onTriggered: {
            memProcess.running = false;
            memProcess.running = true;
        }
    }

    property var cpuTimer: Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: {
            cpuStatProc.running = false;
            cpuStatProc.running = true;
        }
    }

    PanelWindow {
        id: imageBackdrop
        visible: false
        property var images: [
            "assets/haachama_in_4k.png",
            "assets/aka-haato.png",
            "assets/haachama.png",
        ]
        property int currentIndex: 0
        WlrLayershell.namespace: "arch_logo"
        width: backdrop.width + 20
        height: backdrop.height + 20
        color: "transparent"
        anchors.right: true
        anchors.top: true
        margins {
            top: 20
        }
        WlrLayershell.layer: WlrLayer.Bottom

        MultiEffect {
            source: backdrop
            anchors.fill: backdrop
            shadowEnabled: true
            shadowColor: '#e1000000'
            shadowOpacity: 5
            opacity: 0.8
            shadowBlur: 1.0
            shadowVerticalOffset: 0
            shadowHorizontalOffset: 0
        }
        ClippingRectangle {
            id: haachamaImage
            border.width: 2
            width: 300
            height: 400
            border.color: Qt.alpha(root.theme.primary, 0.2)
            color: Qt.alpha(root.theme.background, 0.5)
            radius: 10
            z: 0
            Image {
                id: backdrop
                source: imageBackdrop.images[imageBackdrop.currentIndex]
                width: 300
                height: 400
                sourceSize.width: width
                sourceSize.height: height
                fillMode: Image.PreserveAspectFit
            }
        }
        Timer {
            interval: 120000
            running: true
            repeat: true
            onTriggered: fadeCycle.start()
        }

        SequentialAnimation {
            id: fadeCycle
            NumberAnimation { target: backdrop; property: "opacity"; to: 0; duration: 400; easing.type: Easing.InOutQuad }
            ScriptAction {
                script: {
                    imageBackdrop.currentIndex = (imageBackdrop.currentIndex + 1) % imageBackdrop.images.length
                    backdrop.source = imageBackdrop.images[imageBackdrop.currentIndex]
                }
            }
            NumberAnimation { target: backdrop; property: "opacity"; to: 1; duration: 400; easing.type: Easing.InOutQuad }
        }
    }

    // frame

    //Actual Bar
    PanelWindow {
        id: panelbar
        WlrLayershell.namespace: "quickshell:thebar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 36 + roundDecorators.height
        color: "transparent"
        margins.right: 5
        margins.left: 5
        margins.top: 5
        margins.bottom: -15


        Item {
            id: roundDecorators
            anchors {
                left: parent.left
                right: parent.right
                top: realbar.bottom
            }
            height: 20  

            RoundCorner {
                id: leftCorner
                visible: false
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: parent.left
                }
                implicitSize: parent.height
                color: Qt.alpha(root.theme.background, 0.7)         
                corner: RoundCorner.CornerEnum.TopLeft 
            }

            RoundCorner {
                id: rightCorner
                visible: false
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                implicitSize: parent.height
                color: Qt.alpha(root.theme.background, 0.7)
                corner: RoundCorner.CornerEnum.TopRight
            }
        }

        MultiEffect {
            source: roundDecorators
            anchors.fill: roundDecorators
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 1.0
            shadowVerticalOffset: 2
            shadowHorizontalOffset: 0
        }

        MultiEffect {
            source: realbar
            anchors.fill: realbar
            shadowEnabled: true
            shadowColor: "#000000"
            shadowOpacity: 0.35
            shadowBlur: 1.0
            shadowVerticalOffset: 1
            shadowHorizontalOffset: 0
        }

        Rectangle {
            id: realbar
            height: 42
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            antialiasing: true
            radius: 10
            border.width: 0
            border.color: root.theme.outline_variant
            color: Qt.alpha(root.theme.background, 0.9)

            //Time Module
            Rectangle {
                id: clockmodule
                height: 24
                width: timerContent.width
                radius: root.global_radius
                anchors.rightMargin: 0
                color: "transparent"
                anchors.left: mprisModule.right
                anchors.leftMargin: 35
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: "時"
                    color: Qt.alpha(root.theme.on_background, 0.6)
                    rightPadding: 160
                    font.pixelSize: 18
                    font.family: root.settings.fontjp
                    font.bold: true
                    /* renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferVerticalHinting */
                }
                Row {
                    id: timerContent
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        text: root.time
                        color: Qt.alpha(root.theme.on_background, 0.6)
                        font.pixelSize: 16
                        font.family: root.settings.fontdefault
                        font.bold: true
                        /* renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferVerticalHinting */
                    }
                    Text {
                        text: root.dateString
                        color: Qt.alpha(root.theme.on_background, 0.6)
                        font.pixelSize: 16
                        font.family: root.settings.fontdefault
                        font.bold: true
                        /* renderType: Text.NativeRendering
                        font.hintingPreference: Font.PreferVerticalHinting */
                    }
                }
            }

            Row {
                id: sysStatsRow
                spacing: 5
                anchors.right: inhibit_module.left
                anchors.rightMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                // Cpu Module
                Rectangle {
                    id: cpuModule
                    visible: true
                    height: 24
                    width: 80
                    radius: 12
                    color: "transparent"

                    Item {
                        id: cpuCirc
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30

                        property real percent: root.cpuPercent / 100
                        Behavior on percent {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.OutCubic
                            }
                        }
                        property color trackColor: Qt.alpha(root.theme.primary, 0.2)
                        property color fillColor: root.theme.primary
                        property real strokeWidth: 3

                        Canvas {
                            id: cpuCanvas
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();

                                var cx = width / 2;
                                var cy = height / 2;
                                var radius = Math.min(width, height) / 2 - cpuCirc.strokeWidth / 2;
                                var startAngle = -Math.PI / 2; // start at top
                                var endAngle = startAngle + (2 * Math.PI * cpuCirc.percent);

                            // background track
                                ctx.beginPath();
                                ctx.arc(cx, cy, radius, 0, 2 * Math.PI, false);
                                ctx.lineWidth = cpuCirc.strokeWidth;
                                ctx.strokeStyle = cpuCirc.trackColor;
                                ctx.stroke();

                            // filled portion
                                ctx.beginPath();
                                ctx.arc(cx, cy, radius, startAngle, endAngle, false);
                                ctx.lineWidth = cpuCirc.strokeWidth;
                                ctx.strokeStyle = cpuCirc.fillColor;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }
                        onPercentChanged: cpuCanvas.requestPaint()

                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenter: parent.verticalCenter
                            source: "./assets/cpu.svg"
                            width: parent.width - (cpuCirc.strokeWidth * 2) - 8
                            height: parent.height - (cpuCirc.strokeWidth * 2) - 8                        
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.theme.primary   // any matugen color
                            }
                        }
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.InOutQuad
                        }
                    }
                    Row {
                        id: cpuContent
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: Math.round(root.cpuPercent) + "%"
                            opacity: 0.7
                            color: root.theme.on_background
                            font.pixelSize: 16
                            leftPadding: 30
                            font.family: root.settings.fontdefault
                            font.bold: true
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */
                        }
                    }
                }
                Rectangle {
                    id: memModule
                    visible: true
                    height: 24
                    width: memContent.width + 10
                    radius: 12
                    color: "transparent"
                    Item {
                        id: memCirc
                        anchors.verticalCenter: parent.verticalCenter
                        width: 30
                        height: 30

                        property real percent: {
                            var n = parseFloat(root.memformat);
                            return isNaN(n) ? 0 : n / 100;
                        }
                        Behavior on percent {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.OutCubic
                            }
                        }
                        property color trackColor: Qt.alpha(root.theme.primary, 0.2)
                        property color fillColor: root.theme.primary
                        property real strokeWidth: 3

                        Canvas {
                            id: memCanvas
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d");
                                ctx.reset();

                                var cx = width / 2;
                                var cy = height / 2;
                                var radius = Math.min(width, height) / 2 - memCirc.strokeWidth / 2;
                                var startAngle = -Math.PI / 2; // start at top
                                var endAngle = startAngle + (2 * Math.PI * memCirc.percent);

                            // background track
                                ctx.beginPath();
                                ctx.arc(cx, cy, radius, 0, 2 * Math.PI, false);
                                ctx.lineWidth = memCirc.strokeWidth;
                                ctx.strokeStyle = memCirc.trackColor;
                                ctx.stroke();

                            // filled portion
                                ctx.beginPath();
                                ctx.arc(cx, cy, radius, startAngle, endAngle, false);
                                ctx.lineWidth = memCirc.strokeWidth;
                                ctx.strokeStyle = memCirc.fillColor;
                                ctx.lineCap = "round";
                                ctx.stroke();
                            }
                        }
                        onPercentChanged: memCanvas.requestPaint()

                        Image {
                            anchors.centerIn: parent
                            anchors.verticalCenter: parent.verticalCenter
                            source: "./assets/memory.svg"
                            width: parent.width - (memCirc.strokeWidth * 2) - 8
                            height: parent.height - (memCirc.strokeWidth * 2) - 8                        
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.theme.primary   
                            }
                        }
                    }

                    Behavior on width {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.OutCirc
                        }
                    }
                    Row {
                        id: memContent
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            id: mem_text
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.memPercent ? root.memoryUsage : root.memformat
                            opacity: 0.7
                            color: root.memCount > 12000 ? root.theme.primary : root.theme.on_background
                            font.pixelSize: 16
                            leftPadding: 35
                            font.family: root.settings.fontdefault
                            font.bold: true
                        }
                    }
                    MouseArea {
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: parent
                        onClicked: {
                            root.memPercent = !root.memPercent;
                        }
                    }
                }
            }
            //Mpris_Module
            Rectangle {
                id: mprisModule
                height: 30
                width: (showVolumeIndicator ? volumeIndicatorContent.width : mprisContent.width) + 31
                radius: root.global_radius
                color: Qt.alpha(root.theme.source_color, 0.1)
                anchors.horizontalCenterOffset: -100
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                clip: true

                // ---- volume indicator overlay state ----
                property bool showVolumeIndicator: false
                property real displayVolume: shell.activePlayer ? shell.activePlayer.volume : 0

                Timer {
                    id: volumeIndicatorTimer
                    interval: 1000
                    onTriggered: mprisModule.showVolumeIndicator = false
                }

                Behavior on width {
                    NumberAnimation {
                        easing.type: Easing.OutCirc
                        duration: 100
                    }
                }

                Row {
                    id: mprisContent
                    anchors.centerIn: parent
                    spacing: 8
                    opacity: mprisModule.showVolumeIndicator ? 0 : 1

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    // ---- tiny equalizer visualizer ----
                    Row {
                        id: visualizer
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        height: 14

                        property bool playing: root.hasPlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing

                        Repeater {
                            model: 3
                            delegate: Rectangle {
                                id: bar
                                required property int index
                                width: 3
                                radius: 1.5
                                color: root.theme.primary
                                anchors.bottom: parent.bottom
                                height: 4

                                SequentialAnimation {
                                    id: barAnim
                                    loops: Animation.Infinite
                                    running: visualizer.playing
                                    onRunningChanged: if (!running)
                                        bar.height = 4   // snap back to baseline instead of freezing mid-bounce
                                    NumberAnimation {
                                        target: bar
                                        property: "height"
                                        to: [10, 14, 8][bar.index]
                                        duration: 280 + bar.index * 60
                                        easing.type: Easing.InOutSine
                                    }
                                    NumberAnimation {
                                        target: bar
                                        property: "height"
                                        to: 4
                                        duration: 280 + bar.index * 60
                                        easing.type: Easing.InOutSine
                                    }
                                }
                                Behavior on height {
                                    enabled: !barAnim.running
                                    NumberAnimation {
                                        duration: 200
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }
                        }
                    }

                    Text {
                        text: "•"
                        anchors.verticalCenter: parent.verticalCenter
                        color: root.theme.primary
                        font.pixelSize: 18
                        visible: shell.activePlayer && shell.activePlayer.loopState === MprisLoopState.Track ? true : false
                    }
                    

                    // ---- scrolling title, fixed-width instead of growing/eliding ----
                    Item {
                        id: marqueeClip
                        width: marqueeText.width < 250 ? marqueeText.width : 250 
                        height: 18
                        clip: true
                        anchors.verticalCenter: parent.verticalCenter

                        property int marqueeThreshold: 5
                        readonly property real overflow: Math.max(0, marqueeText.implicitWidth - width)
                        readonly property bool shouldScroll: overflow > marqueeThreshold

                        Text {
                            id: marqueeText
                            anchors.verticalCenter: parent.verticalCenter
                            x: 0
                            text: {
                                if (!shell.activePlayer)
                                    return "No Media";
                                return shell.activePlayer.trackTitle || "";
                            }
                            color: root.theme.on_background
                            font.pixelSize: 16
                            font.family: root.settings.fontjp
                            opacity: 0.8
                            //font.bold: 
                            font.bold: true
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */

                            onTextChanged: {
                                marqueeAnim.stop();
                                x = 0;
                                if (marqueeClip.shouldScroll) {
                                    marqueeAnim.restart();
                                }
                            }

                            SequentialAnimation {
                                id: marqueeAnim
                                loops: Animation.Infinite
                                running: marqueeClip.shouldScroll && root.hasPlayer

                                onRunningChanged: {
                                    if (!running) {
                                        marqueeText.x = 0;
                                    }
                                }

                                PauseAnimation {
                                    duration: 1800
                                }
                                NumberAnimation {
                                    target: marqueeText
                                    property: "x"
                                    to: -marqueeClip.overflow
                                    duration: Math.max(2000, marqueeClip.overflow * 32)
                                    easing.type: Easing.Linear
                                }
                                PauseAnimation {
                                    duration: 1400
                                }
                                NumberAnimation {
                                    target: marqueeText
                                    property: "x"
                                    to: 0
                                    duration: 3000
                                    easing.type: Easing.Linear
                                }
                                PauseAnimation {
                                    duration: 500
                                }
                            }
                        }
                    }
                    
                }

                // ---- volume indicator (crossfades in over mprisContent) ----
                Row {
                    id: volumeIndicatorContent
                    anchors.centerIn: parent
                    spacing: 8
                    opacity: mprisModule.showVolumeIndicator ? 1 : 0

                    Behavior on opacity {
                        NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                    }

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: mprisModule.displayVolume <= 0 ? "assets/speaker-simple-none-fill.svg" : (mprisModule.displayVolume < 0.5 ? "assets/speaker-low-fill.svg" : "assets/speaker-high-fill.svg")
                        width: 20
                        height: 20
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.theme.primary
                        }
                    }

                    Rectangle {
                        id: volTrack
                        width: 227
                        height: 6
                        radius: 3
                        anchors.verticalCenter: parent.verticalCenter
                        color: Qt.alpha(root.theme.on_background, 0.15)

                        Rectangle {
                            height: parent.height
                            radius: parent.radius
                            color: root.theme.primary
                            width: volTrack.width * mprisModule.displayVolume

                            Behavior on width {
                                NumberAnimation { duration: 120; easing.type: Easing.OutCubic }
                            }
                        }
                    }

                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: Math.round(mprisModule.displayVolume * 100) + "%"
                        color: root.theme.on_background
                        opacity: 0.8
                        font.pixelSize: 14
                        font.bold: true
                        font.family: root.settings.fontdefault
                    }
                }

                function toggleLoop() {
                    if (!shell.activePlayer || !shell.activePlayer.loopSupported || !shell.activePlayer.canControl)
                        return;
                    switch (shell.activePlayer.loopState) {
                    case MprisLoopState.Playlist:
                        shell.activePlayer.loopState = MprisLoopState.Track;
                        break;
                    case MprisLoopState.Track:
                        shell.activePlayer.loopState = MprisLoopState.Playlist;
                        break;
                    }
                }

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                    onWheel: event => {
                        const step = 0.05;   // 5% per scroll step
                        const delta = event.angleDelta.y > 0 ? step : -step;

                        shell.activePlayer.volume = Math.max(0, Math.min(1, shell.activePlayer.volume + delta));

                        mprisModule.displayVolume = shell.activePlayer.volume;
                        mprisModule.showVolumeIndicator = true;
                        volumeIndicatorTimer.restart();

                        event.accepted = true;
                    }
                    onClicked: mouse => {
                        if (mouse.button === Qt.LeftButton) {
                            albumPopup.isOpen = !albumPopup.isOpen;
                        }
                        if (mouse.button === Qt.RightButton) {
                            mprisModule.toggleLoop();
                        } else if (mouse.button === Qt.MiddleButton) {
                            shell.activePlayer.togglePlaying();
                        }
                    }
                }
            }
            // Mpris Panel
            PanelWindow {
                id: albumPopup
                WlrLayershell.namespace: "quickshell:mpris_popup"
                
                property bool animatingClosed: false
                visible: (isOpen || animatingClosed) && root.hasPlayer

                onIsOpenChanged: {
                    if (isOpen) {
                        closeAnim.stop();
                        openAnim.restart();
                    } else {
                        openAnim.stop();
                        closeAnim.restart();
                    }
                }

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

                property bool isOpen: false 
                property int refreshTrigger: 0

                width: mprispopup.width + 100
                height: mprispopup.height + 40
                color: "transparent"


                IpcHandler {
                    target: "mprispopup"
                    function open(): void   { albumPopup.isOpen = true }
                    function close(): void  { albumPopup.isOpen = false }
                    function toggle(): void { albumPopup.isOpen = !albumPopup.isOpen }
                }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.enabled: true
                    Keys.onEscapePressed: {
                        albumPopup.isOpen = !albumPopup.isOpen;
                    }
                }

                anchors { top: true }
                exclusiveZone: 0


                Rectangle {
                    // no opacity = 0 next time
                    id: mprispopup
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.horizontalCenterOffset: -50
                    width: 320
                    height: 500
                    y: 10
                    scale: 0.1
                    border.width: 0
                    border.color: Qt.alpha(root.theme.primary, 0.1)
                    property real t: 0
                    color: "black"

                    ClippingRectangle {
                        id: backImage
                        anchors.fill: parent
                        radius: 20
                        opacity: 0.3
                        color: "transparent"
                        antialiasing: true
                        layer.enabled: true
                        layer.smooth: true

                        Image {
                            id: backArt
                            anchors.fill: parent
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            source: {
                                if (shell.activePlayer && shell.activePlayer.trackArtUrl) {
                                    return shell.activePlayer.trackArtUrl;
                                } else {
                                    return "";
                                }
                            }
                        }
                        MultiEffect {
                            source: backArt
                            anchors.fill: parent
                            blurEnabled: true
                            blur: 0.5
                            blurMax: 32
                            brightness: 0
                        }
                    }

                    radius: 20
                    clip: true

                    transformOrigin: Item.Top

                    /* transform: Scale {
                        origin.x: mprispopup.width / 2
                        origin.y: 0        // grow from the top edge
                        yScale: mprispopup.scale
                        xScale: 1          // keep width constant, only height "grows"
                    } */

                    SequentialAnimation {
                        id: closeAnim

                        onStarted: albumPopup.animatingClosed = true
                        onStopped: albumPopup.animatingClosed = false

                        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 100 }
                        NumberAnimation { target: mprispopup; property: "scale"; to: 0.1; duration: 250; easing.type: Easing.InCirc }
                    }

                    SequentialAnimation {
                        id: openAnim
                        NumberAnimation {
                            target: mprispopup
                            property: "scale"
                            to: 1
                            duration: 200
                            easing.type: Easing.OutCirc
                        }
                        NumberAnimation {
                            target: content
                            property: "opacity"
                            to: 1
                            duration: 100
                        }
                    }
                    ColumnLayout {
                        id: content
                        anchors.fill: parent
                        opacity: 0

                        Item {
                            id: discContainer
                            width: 280
                            height: 280
                            anchors.horizontalCenter: parent.horizontalCenter
                            Layout.topMargin: 20
                            Layout.alignment: Qt.AlignTop

                            // The visual rotating disc
                            ClippingRectangle {
                                id: discImage
                                anchors.fill: parent
                                radius: 320
                                color: "transparent"
                                antialiasing: true
                                layer.enabled: true
                                layer.smooth: true

                                Image {
                                    id: art
                                    anchors.fill: parent
                                    sourceSize.width: discContainer.width + 300
                                    sourceSize.height: discContainer.height + 300
                                    fillMode: Image.PreserveAspectCrop
                                    asynchronous: true
                                    source: {
                                        if (shell.activePlayer && shell.activePlayer.trackArtUrl) {
                                            return shell.activePlayer.trackArtUrl;
                                        } else {
                                            return "";
                                        }
                                    }
                                }
                            }

                            // 1. Smooth, interruptible rotation timer during playback
                            Timer {
                                id: rotateTimer
                                interval: 30 // 25fps for smooth rotation with low CPU usage
                                running: root.hasPlayer && shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing && !discMouseArea.isDragging
                                repeat: true
                                onTriggered: {
                                    discImage.rotation = (discImage.rotation + root.discSpinSpeed) % 360;
                                }
                            }

                            // 2. Interactive Spin-to-Seek MouseArea (Static sibling to discImage to avoid coordinate oscillation)
                            MouseArea {
                                id: discMouseArea
                                anchors.fill: parent
                                cursorShape: Qt.OpenHandCursor
                                property real lastAngle: 0
                                property real initialRotation: 0
                                property real accumulatedDelta: 0
                                property int startPosition: 0
                                property int previewPosition: 0
                                property bool isDragging: false
                                property bool wasPlaying: false

                                function getAngle(x, y) {
                                    var cx = discContainer.width / 2;
                                    var cy = discContainer.height / 2;
                                    var angle = Math.atan2(y - cy, x - cx) * 180 / Math.PI;
                                    return angle < 0 ? angle + 360 : angle;
                                }

                                onPressed: function(mouse) {
                                    isDragging = true;
                                    cursorShape = Qt.ClosedHandCursor;
                                    lastAngle = getAngle(mouse.x, mouse.y);
                                    initialRotation = discImage.rotation;
                                    accumulatedDelta = 0;
                                    startPosition = shell.activePlayer ? shell.activePlayer.position : 0;
                                    previewPosition = startPosition;
                                    
                                    // Pause playback while scrubbing for better control
                                    if (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing) {
                                        wasPlaying = true;
                                        if (shell.activePlayer.canPause) {
                                            shell.activePlayer.pause();
                                        }
                                    } else {
                                        wasPlaying = false;
                                    }
                                }

                                onPositionChanged: function(mouse) {
                                    if (!isDragging || !shell.activePlayer) return;
                                    
                                    var currentAngle = getAngle(mouse.x, mouse.y);
                                    var delta = currentAngle - lastAngle;
                                    
                                    // Handle wrap-around crossing the 0°/360° boundary between mouse events
                                    if (delta > 180) {
                                        delta -= 360;
                                    } else if (delta < -180) {
                                        delta += 360;
                                    }
                                    
                                    lastAngle = currentAngle;
                                    accumulatedDelta += delta;
                                    
                                    // Smoothly rotate disc relative to initial touch rotation
                                    var rot = (initialRotation + accumulatedDelta) % 360;
                                    if (rot < 0) rot += 360;
                                    discImage.rotation = rot;

                                    // Update visual preview position without flooding DBus with SetPosition calls
                                    if (shell.activePlayer.length > 0) {
                                        let targetTime = startPosition + (accumulatedDelta / 720.0) * shell.activePlayer.length;
                                        previewPosition = Math.max(0, Math.min(targetTime, shell.activePlayer.length));
                                    }
                                }

                                onReleased: function() {
                                    // Send seek command exactly once on release to prevent playback delay
                                    if (shell.activePlayer && shell.activePlayer.length > 0) {
                                        shell.activePlayer.position = previewPosition;
                                    }
                                    isDragging = false;
                                    cursorShape = Qt.OpenHandCursor;
                                    // Resume playback if it was playing before the drag
                                    if (shell.activePlayer && wasPlaying && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                }
                                
                                onCanceled: {
                                    if (shell.activePlayer && shell.activePlayer.length > 0) {
                                        shell.activePlayer.position = previewPosition;
                                    }
                                    isDragging = false;
                                    cursorShape = Qt.OpenHandCursor;
                                    if (shell.activePlayer && wasPlaying && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                }
                            }
                        }

                        // Track info
                        Column {
                            id: infoColumn
                            width: 280
                            spacing: 4
                            Layout.alignment: Qt.AlignHCenter
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 80

                            // ---- title, marquee if it overflows ----
                            Item {
                                id: titleClip
                                width: parent.width
                                height: 20
                                clip: true

                                property int marqueeThreshold: 10
                                readonly property real overflow: Math.max(0, titleText.implicitWidth - width)
                                readonly property bool shouldScroll: overflow > marqueeThreshold

                                Text {
                                    id: titleText
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: titleClip.shouldScroll ? 0 : Math.max(0, (titleClip.width - implicitWidth) / 2)

                                    text: shell.activePlayer && shell.activePlayer.trackTitle ? "♫ " + shell.activePlayer.trackTitle : "No Media"
                                    color: root.theme.on_background
                                    font.family: root.settings.fontjp
                                    font.pixelSize: 16
                                    font.bold: true
                                    opacity: 0.8
                                    /* renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting */

                                    transform: Translate {
                                        id: titleTrans
                                        x: 0
                                    }

                                    onTextChanged: {
                                        titleMarqueeAnim.stop();
                                        titleTrans.x = 0;
                                        if (titleClip.shouldScroll) {
                                            titleMarqueeAnim.restart();
                                        }
                                    }

                                    SequentialAnimation {
                                        id: titleMarqueeAnim
                                        loops: Animation.Infinite
                                        running: titleClip.shouldScroll && !!shell.activePlayer

                                        onRunningChanged: {
                                            if (!running) {
                                                titleTrans.x = 0;
                                            }
                                        }

                                        PauseAnimation {
                                            duration: 1800
                                        }
                                        NumberAnimation {
                                            target: titleTrans
                                            property: "x"
                                            to: -titleClip.overflow
                                            duration: Math.max(2000, titleClip.overflow * 32)
                                            easing.type: Easing.Linear
                                        }
                                        PauseAnimation {
                                            duration: 1400
                                        }
                                        NumberAnimation {
                                            target: titleTrans
                                            property: "x"
                                            to: 0
                                            duration: 3000
                                            easing.type: Easing.Linear
                                        }
                                        PauseAnimation {
                                            duration: 500
                                        }
                                    }
                                }
                            }

                            // ---- artist, marquee if it overflows ----
                            Item {
                                id: artistClip
                                width: parent.width
                                height: 16
                                clip: true
                                visible: !!(shell.activePlayer && shell.activePlayer.trackArtist)

                                property int marqueeThreshold: 10
                                readonly property real overflow: Math.max(0, artistText.implicitWidth - width)
                                readonly property bool shouldScroll: overflow > marqueeThreshold

                                Text {
                                    id: artistText
                                    anchors.verticalCenter: parent.verticalCenter
                                    x: artistClip.shouldScroll ? 0 : Math.max(0, (artistClip.width - implicitWidth) / 2)

                                    text: shell.activePlayer ? (shell.activePlayer.trackArtist || "") : ""
                                    color: root.theme.on_background
                                    opacity: 0.6
                                    font.family: root.settings.fontjp
                                    font.pixelSize: 14
                                    /* renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferFullHinting */

                                    transform: Translate {
                                        id: artistTrans
                                        x: 0
                                    }

                                    onTextChanged: {
                                        artistMarqueeAnim.stop();
                                        artistTrans.x = 0;
                                        if (artistClip.shouldScroll) {
                                            artistMarqueeAnim.restart();
                                        }
                                    }

                                    SequentialAnimation {
                                        id: artistMarqueeAnim
                                        loops: Animation.Infinite
                                        running: artistClip.shouldScroll && !!shell.activePlayer

                                        onRunningChanged: {
                                            if (!running) {
                                                artistTrans.x = 0;
                                            }
                                        }

                                        PauseAnimation {
                                            duration: 1800
                                        }
                                        NumberAnimation {
                                            target: artistTrans
                                            property: "x"
                                            to: -artistClip.overflow
                                            duration: Math.max(2000, artistClip.overflow * 32)
                                            easing.type: Easing.Linear
                                        }
                                        PauseAnimation {
                                            duration: 1400
                                        }
                                        NumberAnimation {
                                            target: artistTrans
                                            property: "x"
                                            to: 0
                                            duration: 600
                                            easing.type: Easing.InOutCubic
                                        }
                                        PauseAnimation {
                                            duration: 500
                                        }
                                    }
                                }
                            }
                        }

                        function formatTime(seconds) {
                            if (isNaN(seconds) || seconds < 0) return "0:00"
                            const m = Math.floor(seconds / 60)
                            const s = Math.floor(seconds % 60)
                            return m + ":" + (s < 10 ? "0" + s : s)
                        }

                        Text {
                            id: timeStamps
                            color: Qt.alpha(root.theme.on_background, 0.3)
                            text: {
                                const total = (root.hasPlayer && shell.activePlayer) ? shell.activePlayer.length : 0;
                                const current = (root.hasPlayer && shell.activePlayer && total > 0)
                                    ? (seekBar.progressFraction * total)
                                    : ((root.hasPlayer && shell.activePlayer) ? shell.activePlayer.position : 0);
                                return content.formatTime(current) + "/" + content.formatTime(total);
                            }
                            font.family: root.settings.fontdefault
                            font.pixelSize: 12
                            font.bold: true
                            anchors.right: seekBar.right
                            anchors.bottom: seekBar.top
                            anchors.bottomMargin: 5
                        }


                        // Seek Bar — original flat track restored, with a scrolling wave
                        // overlaid only on the played portion. Wave amplitude, frequency and
                        // speed are fixed values, set via the properties below.
                        Item {
                            id: seekBar
                            width: 240
                            height: 23
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 120
                            Layout.alignment: Qt.AlignHCenter

                            readonly property real targetProgress: {
                                if (!root.hasPlayer || !shell.activePlayer || shell.activePlayer.length <= 0)
                                    return 0;
                                if (seekMouseArea.pressed)
                                    return Math.max(0, Math.min(1, seekMouseArea.mouseX / seekBar.width));
                                if (discMouseArea.isDragging)
                                    return Math.max(0, Math.min(1, discMouseArea.previewPosition / shell.activePlayer.length));
                                return Math.max(0, Math.min(1, shell.activePlayer.position / shell.activePlayer.length));
                            }

                            property real progressFraction: targetProgress
                            Behavior on progressFraction {
                                enabled: !seekMouseArea.isDragging && !discMouseArea.isDragging
                                NumberAnimation {
                                    duration: 250
                                    easing.type: Easing.OutCubic
                                }
                            }

                            readonly property bool isPlaying: root.hasPlayer && shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing

                            // Fixed wave amplitude (px), frequency (number of full sine cycles
                            // across the seek bar's width), and scroll period (ms per cycle).
                            // Change these three properties to tune the wave's look.
                            property real waveAmplitude: 5.5
                            property real waveFrequency: 3.5
                            property real waveSpeed: 800

                            property real amplitude: 0
                            Behavior on amplitude {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                            // Fades to 0 when nothing is playing, otherwise uses the fixed waveAmplitude above.
                            readonly property real targetAmplitude: seekBar.isPlaying ? seekBar.waveAmplitude : 0
                            onTargetAmplitudeChanged: seekBar.amplitude = seekBar.targetAmplitude
                            Component.onCompleted: seekBar.amplitude = seekBar.targetAmplitude

                            // scrolling phase — fixed period, set via waveSpeed above
                            property real phase: 0
                            NumberAnimation on phase {
                                from: 0
                                to: Math.PI * 2
                                duration: seekBar.waveSpeed
                                loops: Animation.Infinite
                                running: seekBar.isPlaying
                            }

                            Rectangle {
                                id: knob
                                anchors.left: progress_bar.right
                                anchors.verticalCenter: progress_bar.verticalCenter
                                width: 8
                                height: 30
                                radius: 20
                                color: root.theme.primary

                            }

                            // original flat track — unchanged from before
                            Rectangle {
                                id: trackBg
                                width: Math.max(0, seekBar.width * (1.0 - seekBar.progressFraction))
                                x: seekBar.width * seekBar.progressFraction
                                height: 5
                                radius: 1
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.alpha(root.theme.primary, 0.2)
                            }

                            // original filled progress bar — unchanged from before
                            Rectangle {
                                id: progress_bar
                                anchors.left: parent.left
                                width: Math.max(0, Math.min(seekBar.width, seekBar.width * seekBar.progressFraction))
                                height: trackBg.height
                                radius: trackBg.radius
                                anchors.verticalCenter: parent.verticalCenter
                                color: "transparent"
                            }

                            // wave overlay — rides on top of progress_bar, ONLY over the played portion
                            Canvas {
                                id: waveCanvas
                                anchors.fill: parent

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    const midY = height / 2;
                                    const amp = seekBar.amplitude;
                                    const freq = (seekBar.waveFrequency * 2 * Math.PI) / width;
                                    const splitX = Math.max(0, Math.min(width, width * seekBar.progressFraction));

                                    if (splitX <= 0)
                                        return;

                                    ctx.beginPath();
                                    ctx.strokeStyle = root.theme.primary;
                                    ctx.lineWidth = 5;
                                    ctx.lineCap = "round";
                                    let first = true;
                                    for (let x = 0; x <= splitX; x += 2) {
                                        const y = midY + Math.sin(x * freq + seekBar.phase) * amp;
                                        if (first) {
                                            ctx.moveTo(x, y);
                                            first = false;
                                        } else {
                                            ctx.lineTo(x, y);
                                        }
                                    }
                                    ctx.stroke();
                                }

                                Connections {
                                    target: seekBar
                                    function onPhaseChanged() { waveCanvas.requestPaint(); }
                                    function onProgressFractionChanged() { waveCanvas.requestPaint(); }
                                    function onAmplitudeChanged() { waveCanvas.requestPaint(); }
                                    function onWaveFrequencyChanged() { waveCanvas.requestPaint(); }
                                }
                            }

                            MouseArea {
                                id: seekMouseArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor

                                property bool isDragging: false
                                property bool savedPlayingState: false

                                function updateSeekPosition(mouse) {
                                    if (root.hasPlayer && shell.activePlayer && shell.activePlayer.length > 0) {
                                        const clampedX = Math.max(0, Math.min(mouse.x, seekBar.width));
                                        shell.activePlayer.position = shell.activePlayer.length * (clampedX / seekBar.width);
                                    }
                                }

                                onPressed: mouse => {
                                    isDragging = false;
                                    if (root.hasPlayer && shell.activePlayer) {
                                        savedPlayingState = (shell.activePlayer.playbackState === MprisPlaybackState.Playing);
                                        if (savedPlayingState && shell.activePlayer.canPause) {
                                            shell.activePlayer.pause();
                                        }
                                    }
                                    updateSeekPosition(mouse);
                                }

                                onPositionChanged: mouse => {
                                    if (pressed) {
                                        isDragging = true;
                                        waveCanvas.requestPaint();
                                    }
                                }

                                onReleased: mouse => {
                                    updateSeekPosition(mouse);   // send the seek exactly once, here
                                    isDragging = false;
                                    if (root.hasPlayer && shell.activePlayer && savedPlayingState && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                    savedPlayingState = false;
                                }

                                onCanceled: {
                                    isDragging = false;
                                    if (root.hasPlayer && shell.activePlayer && savedPlayingState && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                    savedPlayingState = false;
                                }
                            }

                            Timer {
                                running: root.hasPlayer && shell.activePlayer && shell.activePlayer.playbackState == MprisPlaybackState.Playing && !seekMouseArea.pressed && !discMouseArea.isDragging && albumPopup.isOpen
                                interval: 150
                                repeat: true

                                onTriggered: if (root.hasPlayer && shell.activePlayer)
                                    shell.activePlayer.positionChanged()
                            }
                        }

                        //Control Dock
                        Item {
                            id: controlDock
                            width: 250
                            Layout.alignment: Qt.AlignHCenter
                            anchors.top: seekBar.bottom
                            anchors.topMargin: 50

                            Rectangle {
                                id: playButtonContainer
                                property bool pressed: false
                                width: 50
                                height: 50
                                radius: 8
                                color: Qt.alpha(root.theme.primary, 1)
                                anchors.centerIn: parent

                                Image {
                                    id: playbutton
                                    width: 40
                                    height: 40
                                    sourceSize.width: width
                                    sourceSize.height: height
                                    fillMode: Image.PreserveAspectFit
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Qt.alpha(root.theme.background, 1)
                                    }
                                    source: (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing) ? "./assets/pause-bold.svg" : "./assets/play-bold.svg"
                                    property real rotAngle: playButtonContainer.pressed ? 10 : 0
                                    rotation: rotAngle

                                    Behavior on rotation {
                                        NumberAnimation {
                                            duration: 100
                                            easing.type: Easing.InOutQuad
                                        }
                                    }
                                    opacity: playButtonContainer.pressed ? 0.7 : 1.0
                                    Behavior on opacity {
                                        NumberAnimation {
                                            duration: 120
                                        }
                                    }
                                    anchors.centerIn: parent
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    // Nudges the play triangle slightly right so it centers perfectly by eye
                                    anchors.horizontalCenterOffset: (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Paused) ? -1 : 0
                                }

                                MouseArea {
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    onPressed: playButtonContainer.pressed = true
                                    onReleased: playButtonContainer.pressed = false
                                    onCanceled: playButtonContainer.pressed = false
                                    onClicked: if (shell.activePlayer)
                                        shell.activePlayer.togglePlaying()
                                }
                            }
                            Rectangle {
                                id: nextButtonContainer
                                width: 38
                                height: 28
                                radius: 4
                                color: "transparent"
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.rightMargin: 15

                                Image {
                                    id: nextbutton
                                    source: "./assets/skip-forward-bold.svg"
                                    width: 20
                                    height: 20
                                    sourceSize.width: 22
                                    sourceSize.height: 22
                                    fillMode: Image.PreserveAspectFit
                                    anchors.centerIn: parent
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Qt.alpha(root.theme.primary, 0.8)
                                    }
                                }

                                MouseArea {
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    onClicked: if (shell.activePlayer)
                                        shell.activePlayer.next()
                                }
                            }
                            Rectangle {
                                id: prevButtonContainer
                                width: 38
                                height: 28
                                radius: 4
                                color: "transparent"
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 15

                                Image {
                                    id: prevbutton
                                    source: "./assets/skip-back-bold.svg"
                                    width: 20
                                    height: 20
                                    sourceSize.width: 22
                                    sourceSize.height: 22
                                    fillMode: Image.PreserveAspectFit
                                    anchors.centerIn: parent
                                    layer.enabled: true
                                    layer.effect: MultiEffect {
                                        colorization: 1.0
                                        colorizationColor: Qt.alpha(root.theme.primary, 0.8)                                
                                    }
                                }

                                MouseArea {
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    onClicked: if (shell.activePlayer)
                                        shell.activePlayer.previous()
                                }
                            }
                        }
                    }
                }
            }

            // WORKSPACE //
            Rectangle {
                id: workspacemodule
                anchors.left: shell_center.right
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: dotsRow.width
                height: 30
                color: Qt.alpha(root.theme.source_color, 0.15)
                radius: 50

                property bool pillInitialized: false

                // the one true pill — slides/resizes/recolors instead of each dot
                // cross-fading with its neighbor in place
                Rectangle {
                    id: activePill
                    y: Math.round((workspacemodule.height - height) / 2)
                    height: 30
                    radius: 30
                    z: 0

                    Behavior on x {
                        enabled: workspacemodule.pillInitialized
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutCirc
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutCirc
                        }
                    }
                    Behavior on color {
                        ColorAnimation {
                            duration: 280
                        }
                    }
                }

                Row {
                    id: dotsRow
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 5
                    z: 1

                    Repeater {
                        id: wsRepeater
                        model: Hyprland.workspaces
                        onCountChanged: Qt.callLater(workspacemodule.updatePill)

                        Rectangle {
                            id: rect
                            required property var modelData
                            visible: modelData.id > 0 && modelData.id <= 9
                            width: 30
                            height: 30
                            radius: 30
                            color: "transparent"

                            property bool occupied: modelData.lastIpcObject ? modelData.lastIpcObject.windows > 0 : false

                            Connections {
                                target: Hyprland
                                function onRawEvent(event) {
                                    if (event.name === "openwindow" || event.name === "closewindow" || event.name === "movewindow")
                                        Hyprland.refreshWorkspaces();
                                }
                            }
                            property bool isCurrent: rect.modelData.active || rect.modelData.id < 0

                            onIsCurrentChanged: if (isCurrent)
                                Qt.callLater(workspacemodule.updatePill)
                            Component.onCompleted: if (isCurrent)
                                Qt.callLater(workspacemodule.updatePill)

                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: {
                                    if (rect.modelData.id < 10 && rect.occupied || rect.isCurrent)
                                        return root.kanjiNumbers[rect.modelData.id - 1] || String(rect.modelData.id);
                                    return "•";
                                }
                                color: rect.isCurrent ? root.theme.background : rect.occupied ? root.theme.on_background : Qt.alpha(root.theme.primary, 0.8)
                                font.family: root.settings.fontjp
                                font.pixelSize: 20
                                font.bold: true
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality

                                scale: rect.isCurrent ? 1.2 : rect.modelData.id < 9 && rect.occupied || rect.isCurrent ? 0.75 : 1
                                transformOrigin: Item.Center

                                Behavior on color {
                                    ColorAnimation {
                                        duration: 280
                                    }
                                }
                                Behavior on scale {
                                    NumberAnimation {
                                        duration: 280
                                        easing.type: Easing.OutCubic
                                    }
                                }
                            }

                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                anchors.fill: parent
                                onClicked: rect.modelData.activate()
                            }
                        }
                    }
                }

                function updatePill() {
                    for (var i = 0; i < wsRepeater.count; i++) {
                        var item = wsRepeater.itemAt(i);
                        if (item && item.visible && item.isCurrent) {
                            activePill.color = Qt.color(root.theme.primary);
                            activePill.width = 35;
                            activePill.x = item.x - (activePill.width - item.width) / 2;
                            workspacemodule.pillInitialized = true;
                            return;
                        }
                    }
                }

                Timer {
                    id: pillSyncTimer
                    interval: 100
                    running: true
                    repeat: true
                    property int ticks: 0
                    onTriggered: {
                        workspacemodule.updatePill();
                        ticks++;
                        if (ticks >= 10)
                            running = false;
                    }
                }
            }
            // TRAY //
            Rectangle {
                id: tray_module
                implicitHeight: 30
                implicitWidth: rowlayout.implicitWidth + 14
                radius: root.global_radius
                color: Qt.alpha(root.theme.source_color, 0.15)
                anchors.right: powerbutton.left
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                property color transparentColor: Qt.alpha(root.theme.primary, 0)

                RowLayout {
                    id: rowlayout
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.rightMargin: 8
                    spacing: 6

                    Repeater {
                        id: repeater
                        model: SystemTray.items

                        delegate: Item {
                            id: trayIcon
                            required property SystemTrayItem modelData
                            implicitWidth: 20
                            implicitHeight: 20

                            Image {
                                anchors.fill: parent
                                source: trayIcon.modelData.icon
                                sourceSize.width: 20
                                sourceSize.height: 20
                            }
                            readonly property bool isFcitx: {
                                let name = (trayIcon.modelData.id || trayIcon.modelData.icon || "").toLowerCase();
                                return name.includes("fcitx") || name.includes("unikey");
                            }

                            Loader {
                                anchors.fill: parent
                                active: trayIcon.isFcitx
                                sourceComponent: Component {
                                    ColorOverlay {
                                        source: trayIcon
                                        color: root.theme.primary 
                                    }
                                }
                            }          

                            MouseArea {
                                anchors.fill: parent
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton && trayIcon.modelData.hasMenu) {
                                        if (menuWindow.visible && menuWindow.forItem === trayIcon.modelData) {
                                            menuWindow.visible = false;
                                        } else {
                                            menuWindow.forItem = trayIcon.modelData;
                                            menuWindow.anchorItem = trayIcon;
                                            menuWindow.anchor.updateAnchor();
                                            menuWindow.visible = true;
                                        }
                                    } else {
                                        trayIcon.modelData.activate();
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ---- top-level context menu ----
            PopupWindow {
                id: menuWindow
                visible: false

                property SystemTrayItem forItem: null
                property Item anchorItem: null

                anchor.window: panelbar
                anchor.onAnchoring: {
                    if (!anchorItem)
                        return;
                    const pos = anchorItem.mapToItem(null, anchorItem.width / 2, anchorItem.height);
                    anchor.rect.x = pos.x - implicitWidth / 2;
                    anchor.rect.y = pos.y + 8;
                }

                implicitWidth: 200
                implicitHeight: menuColumn.implicitHeight
                color: "transparent"

                onVisibleChanged: if (!visible)
                    submenuWindow.visible = false

                // close on outside click
                PanelWindow {
                    id: dismissLayer
                    visible: menuWindow.visible || submenuWindow.visible

                    WlrLayershell.layer: WlrLayer.Overlay
                    WlrLayershell.exclusiveZone: -1
                    WlrLayershell.namespace: "trayctxmenu-dismiss"
                    color: "transparent"

                    anchors {
                        top: true
                        left: true
                        right: true
                        bottom: true
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: {
                            menuWindow.visible = false;
                            submenuWindow.visible = false;
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    focus: true
                    Keys.onEscapePressed: {
                        menuWindow.visible = false;
                        submenuWindow.visible = false;
                    }
                }

                QsMenuOpener {
                    id: opener
                    menu: menuWindow.forItem ? menuWindow.forItem.menu : null
                }

                Rectangle {
                    anchors.fill: parent
                    color: Qt.alpha(root.theme.background, 0.8)
                    radius: 8

                    Column {
                        id: menuColumn
                        width: parent.width
                        padding: 4

                        Repeater {
                            model: opener.children
                            delegate: MenuEntryDelegate {
                                ownerWindow: menuWindow
                            }
                        }
                    }
                }
            }

            // ---- submenu (one level of nesting) ----
            PopupWindow {
                id: submenuWindow
                visible: false

                property QsMenuEntry forEntry: null
                property Item anchorItem: null

                anchor.window: menuWindow   // <-- same bar id as above
                anchor.onAnchoring: {
                    if (!anchorItem)
                        return;
                    // anchor to the right edge of the hovered entry, vertically aligned
                    const pos = anchorItem.mapToItem(null, anchorItem.width, 0);
                    anchor.rect.x = pos.x + 5;
                    anchor.rect.y = pos.y;
                }

                implicitWidth: 200
                implicitHeight: submenuColumn.implicitHeight
                color: "transparent"

                QsMenuOpener {
                    id: subOpener
                    menu: submenuWindow.forEntry
                }

                Rectangle {
                    anchors.fill: parent
                    color: root.theme.background
                    radius: 8

                    Column {
                        id: submenuColumn
                        width: parent.width
                        padding: 4

                        Repeater {
                            model: subOpener.children
                            delegate: MenuEntryDelegate {
                                ownerWindow: submenuWindow
                            }
                        }
                    }
                }
            }
            ///////
            Rectangle {
                id: shell_center
                implicitWidth: 24
                implicitHeight: 24
                anchors.left: parent.left
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                radius: 12
                color: "transparent"

                // left click: open/close the center, right click: toggle do-not-disturb
                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: mouse => {
                        if (mouse.button === Qt.RightButton)
                            notifications.dnd = !notifications.dnd;
                        else
                            notifications.toggleCenter();
                    }
                }

                // unread badge
                Rectangle {
                    id: new_notification
                    z: 2
                    visible: notifications.unread > 0 && !notifications.dnd
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.rightMargin: -10
                    anchors.topMargin: -5
                    height: 14
                    width: Math.max(14, badgeText.implicitWidth + 6)
                    radius: 7
                    color: root.theme.primary

                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: notifications.unread > 9 ? "9+" : notifications.unread
                        color: root.theme.background
                        font.pixelSize: 9
                        font.bold: true
                        font.family: root.settings.fontdefault
                    }
                }

                Image {
                    id: tux_image
                    source: notifications.dnd ? "./assets/moon.svg" : (notifications.hasNotifications ? "./assets/bell-ringing-fill.svg" : "./assets/linux-logo-bold.svg")
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 20
                    height: 20
                    sourceSize.width: 22
                    sourceSize.height: 22
                    fillMode: Image.PreserveAspectFit
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.theme.primary
                    }

                    Behavior on source {
                        SequentialAnimation {
                            id: blinkAnimationtux
                            NumberAnimation {
                                target: tuxScale
                                property: "yScale"
                                to: 0.05
                                duration: 90
                                easing.type: Easing.InQuad
                            }

                            PropertyAction {}

                            NumberAnimation {
                                target: tuxScale
                                property: "yScale"
                                to: 1.0
                                duration: 160
                                easing.type: Easing.OutBack
                            }
                        }
                    }

                    transform: Scale {
                        id: tuxScale
                        origin.x: tux_image.width / 2
                        origin.y: tux_image.height / 2
                        yScale: 1.0
                    }
                }
            }

            Rectangle {
                id: powerbutton
                implicitWidth: 24
                implicitHeight: 24
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter
                radius: 12
                color: "transparent"

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: togglePowerMenu.running = !togglePowerMenu.running

                    Process {
                        id: togglePowerMenu
                        command: ["sh", "-c", "qs ipc call powermenu toggle"]
                    }
                }

                Image {
                    id: powerButton
                    source: "./assets/power-fill.svg"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 26
                    height: 26
                    sourceSize.width: 32
                    sourceSize.height: 32
                    fillMode: Image.PreserveAspectFit
                    layer.enabled: true
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: root.theme.error
                    }
                }
            }

            IdleInhibitor {
                id: inhibit
                window: panelbar
                enabled: inhibit_module.active
            }

            Rectangle {
                id: inhibit_module
                property int mode: 0
                property double expiresAt: 0
                readonly property bool active: mode > 0
                readonly property bool timed: mode >= 1 && mode <= 4
                readonly property var durations: [0, 5, 15, 30, 60]
                property string remainingText: ""

                function formatRemaining(milliseconds) {
                    const totalSeconds = Math.max(0, Math.ceil(milliseconds / 1000))
                    const minutes = Math.floor(totalSeconds / 60)
                    const seconds = totalSeconds % 60
                    return minutes + ":" + (seconds < 10 ? "0" : "") + seconds
                }

                function updateRemainingTime() {
                    if (!timed)
                        return

                    const millisecondsLeft = expiresAt - Date.now()
                    if (millisecondsLeft <= 0) {
                        mode = 0
                        expiresAt = 0
                        remainingText = ""
                        inhibitTimer.stop()
                        return
                    }

                    remainingText = formatRemaining(millisecondsLeft)
                }

                function advanceMode() {
                    mode = (mode + 1) % 6

                    if (mode === 0 || mode === 5) {
                        expiresAt = 0
                        remainingText = ""
                        inhibitTimer.stop()
                    } else {
                        expiresAt = Date.now() + durations[mode] * 60 * 1000
                        updateRemainingTime()
                        inhibitTimer.start()
                    }

                    blinkAnimation.restart()
                }

                width: timed ? 72 : 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: volumeModule.left
                anchors.rightMargin: 15
                color: "transparent"
                radius: 6

                Behavior on width {
                    NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
                }

                Row {
                    id: inhibitContent
                    anchors.centerIn: parent
                    spacing: 4
                    width: inhibit_module.timed ? 64 : 20
                    height: 20

                    Image {
                        id: inhibit_image
                        source: inhibit_module.active ? "./assets/coffee.svg" : "./assets/moon.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.theme.primary
                        }

                        transform: Scale {
                            id: eyeScale
                            origin.x: inhibit_image.width / 2
                            origin.y: inhibit_image.height / 2
                            yScale: 1.0
                        }
                    }

                    Text {
                        visible: inhibit_module.timed
                        width: 40
                        anchors.verticalCenter: parent.verticalCenter
                        text: inhibit_module.remainingText
                        color: Qt.alpha(root.theme.on_background, 0.75)
                        font.pixelSize: 14
                        font.family: root.settings.fontdefault
                        font.bold: true
                    }
                }

                Timer {
                    id: inhibitTimer
                    interval: 1000
                    repeat: true
                    onTriggered: inhibit_module.updateRemainingTime()
                }

                SequentialAnimation {
                    id: blinkAnimation
                    NumberAnimation {
                        target: eyeScale
                        property: "yScale"
                        to: 0.05
                        duration: 90
                        easing.type: Easing.InQuad
                    }
                    NumberAnimation {
                        target: eyeScale
                        property: "yScale"
                        to: 1.0
                        duration: 160
                        easing.type: Easing.OutBack
                    }
                }

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: inhibit_module.advanceMode()
                }
            }
            VolumeModule {
                id: volumeModule
                theme: root.theme
                settings: root.settings
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: tray_module.left
                anchors.rightMargin: 15
            }
        }
    }

    // shared delegate for menu entries (top-level and submenu) //
    component MenuEntryDelegate: Item {
        id: entryDelegate
        required property QsMenuEntry modelData
        required property Item ownerWindow  // the menu/submenu window this belongs to
        width: parent ? parent.width - 8 : 0
        height: entryDelegate.modelData.isSeparator ? 9 : 28

        // separator
        Rectangle {
            visible: entryDelegate.modelData.isSeparator
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width
            height: 1
            color: root.theme.background
        }

        // normal item
        Rectangle {
            visible: !entryDelegate.modelData.isSeparator
            anchors.fill: parent
            radius: 4
            color: itemHover.hovered ? root.theme.primary : "transparent"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: chevron.left
                text: entryDelegate.modelData.text
                color: entryDelegate.modelData.enabled ? itemHover.hovered ? root.theme.background : root.theme.on_background : root.theme.outline_variant
                font.pixelSize: 13
                elide: Text.ElideRight
            }

            Text {
                id: chevron
                visible: entryDelegate.modelData.hasChildren
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: parent.right
                anchors.rightMargin: 8
                text: "\u203a"
                color: root.theme.on_background
            }

            HoverHandler {
                id: itemHover
            }
            TapHandler {
                enabled: entryDelegate.modelData.enabled
                onTapped: {
                    if (entryDelegate.modelData.hasChildren) {
                        submenuWindow.forEntry = entryDelegate.modelData;
                        submenuWindow.anchorItem = entryDelegate;
                        submenuWindow.anchor.updateAnchor();
                        submenuWindow.visible = true;
                    } //else if (submenuWindow.visible = true) {
                    else
                    //submenuWindow.visible = false
                    {
                        entryDelegate.modelData.triggered();
                        menuWindow.visible = false;
                        submenuWindow.visible = false;
                    }
                }
            }
        }
    }
}
