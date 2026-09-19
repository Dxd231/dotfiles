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

    Notifications {
        id: notifications
        mainroot: root
        theme: root.theme
        settings: root.settings
        calendarOpen: shell.calendarOpen
        shellRoot: shell
        cpuPercent: root.cpuPercent
    }

    EmojiPicker {
        id: emojiPicker
        theme: root.theme
        settings: root.settings
    }

    PowerMenu {
        id: powerMenu
        theme: root.theme
        settings: root.settings
    }

    WallpaperSwitcher {
        id: wallpaperSwitcher
        theme: root.theme
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

    ClipboardManager {
        id: clipboardManager
        theme: root.theme
        settings: root.settings
        global_radius: root.global_radius
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

    // ---- calendar popup state ----
    property bool calendarOpen: false
    property var viewDate: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property var highlightedDays: []
    property var gridCells: shell.buildCalendarGrid()

    function dateKey(d) {
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }
    function isHighlighted(d) {
        return shell.highlightedDays.indexOf(shell.dateKey(d)) !== -1;
    }
    function isToday(d) {
        const t = new Date();
        return d.getFullYear() === t.getFullYear() && d.getMonth() === t.getMonth() && d.getDate() === t.getDate();
    }
    function toggleDay(d) {
        const key = shell.dateKey(d);
        const idx = shell.highlightedDays.indexOf(key);
        const arr = shell.highlightedDays.slice();
        if (idx === -1)
            arr.push(key);
        else
            arr.splice(idx, 1);
        shell.highlightedDays = arr;
    }
    function shiftMonth(delta) {
        shell.viewDate = new Date(shell.viewDate.getFullYear(), shell.viewDate.getMonth() + delta, 1);
    }
    function buildCalendarGrid() {
        const year = shell.viewDate.getFullYear();
        const month = shell.viewDate.getMonth();
        const startWeekday = new Date(year, month, 1).getDay();
        const daysInThisMonth = new Date(year, month + 1, 0).getDate();
        var cells = [];
        for (var i = startWeekday; i > 0; i--)
            cells.push({
                "date": new Date(year, month, 1 - i),
                "inMonth": false
            });
        for (var d = 1; d <= daysInThisMonth; d++)
            cells.push({
                "date": new Date(year, month, d),
                "inMonth": true
            });
        var next = 1;
        while (cells.length < 42) {
            cells.push({
                "date": new Date(year, month + 1, next),
                "inMonth": false
            });
            next++;
        }
        return cells;
    }
    onViewDateChanged: shell.gridCells = shell.buildCalendarGrid()

    QtObject {
        id: root
        property int fontsize: 12
        property var settings: Settings
        readonly property bool hasPlayer: shell.activePlayer !== null && shell.activePlayer !== undefined
        property var theme: Colors
        property int global_radius: 10
        readonly property var kanjiNumbers: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

        readonly property string time: {
            Qt.formatDateTime(clock.date, "hh:mm");
        }
        readonly property string dateString: Qt.formatDateTime(clock.date, "ddd dd MMM")

        property string preferredPlayer: "spotify"

        // ---- live BPM tracking (drives vinyl spin speed) ----
        property real currentBpm: 120        // last detected tempo
        Behavior on currentBpm {
            NumberAnimation { duration: 300; easing.type: Easing.OutQuad }
        }
        property real lastBeatTs: 0          // Date.now() of last beat event
        readonly property real baseBpm: 120  // reference tempo for baseDegPerTick
        readonly property real baseDegPerTick: 0.54 // deg/tick at baseBpm (existing default speed)

        property string memoryUsage: "0%"
        property string memformat: ""
        property string memCount: ""
        property bool memPercent: false
        property string cpuPercent: ""
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
                const line = text.split("\n")[0].trim();
                const parts = line.split(/\s+/).slice(1).map(Number);
                const idle = parts[3] + parts[4]; // idle + iowait
                const total = parts.reduce((a, b) => a + b, 0);
                const idleDelta = idle - cpuStatProc.prevIdle;
                const totalDelta = total - cpuStatProc.prevTotal;
                if (cpuStatProc.prevTotal > 0 && totalDelta > 0) {
                    root.cpuPercent = 100 * (1 - idleDelta / totalDelta);
                }
                cpuStatProc.prevIdle = idle;
                cpuStatProc.prevTotal = total;
                root.cpuPercent = Math.round(100 * (1 - idleDelta / totalDelta))
            }
        }
    }

    // Live BPM detector — only runs while something is actually playing
    Process {
        id: bpmDetector
        running: root.hasPlayer && shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing
        command: [
            "python3",
            (Quickshell.env("HOME") || "") + "/.config/quickshell/scripts/bpm_detect.py",
            shell.activePlayer && shell.activePlayer.identity ? shell.activePlayer.identity : ""
        ]

        stdout: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (!line || line.length === 0)
                    return;
                try {
                    const data = JSON.parse(line);
                    if (data.beat && data.bpm > 0) {
                        root.currentBpm = data.bpm;
                        root.lastBeatTs = Date.now();
                    }
                } catch (e) {
                    // ignore partial/malformed lines
                }
            }
        }

        stderr: SplitParser {
            splitMarker: "\n"
            onRead: line => {
                if (line && line.trim().length > 0)
                    console.info("[bpmDetector]", line.trim());
            }
        }
    }

    //Memory
    Process {
        id: memProcess
        command: ["sh", "-c", "free -m | awk '/Mem:/ { printf \"%d|%.0f%%|%.0f of %.0fGB\\n\", $3, ($3/$2)*100, $3/1024, $2/1024 }'"]
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
        id: archlinux_backdrop
        WlrLayershell.namespace: "arch_logo"
        width: backdrop.width + 20
        height: backdrop.height + 20
        color: "transparent"
        anchors.left: true
        anchors.bottom: true
        visible: false

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

        Image {
            id: backdrop
            anchors.centerIn: parent
            source: "./assets/archbtw.svg"
            width: 300
            height: 300
            sourceSize.width: width
            sourceSize.height: height
            fillMode: Image.PreserveAspectFit
            visible: false
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
        margins.right: 0
        margins.left: 0
        margins.top: 0
        margins.bottom: -20


        Item {
            id: roundDecorators
            anchors {
                left: parent.left
                right: parent.right
                top: realbar.bottom
            }
            height: 20   // or hardcode e.g. 20–30

            RoundCorner {
                id: leftCorner
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: parent.left
                }
                implicitSize: parent.height
                color: Qt.alpha(root.theme.background, 1)         
                corner: RoundCorner.CornerEnum.TopLeft 
            }

            RoundCorner {
                id: rightCorner
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    right: parent.right
                }
                implicitSize: parent.height
                color: Qt.alpha(root.theme.background, 1)
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
            border.width: 0
            border.color: root.theme.outline_variant
            color: Qt.alpha(root.theme.background, 1)

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

            RowLayout {
                anchors.right: inhibit_module.left
                anchors.rightMargin: -40
                anchors.verticalCenter: parent.verticalCenter
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
                            easing.type: Easing.InOutQuad
                        }
                    }
                    Row {
                        id: memContent
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.memPercent ? "Mem: " + root.memoryUsage : root.memformat
                            opacity: 0.7
                            color: root.memCount > 12000 ? root.theme.primary : root.theme.on_background
                            font.pixelSize: 16
                            leftPadding: 30
                            font.family: root.settings.fontdefault
                            font.bold: true
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */
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
                // Cpu Module
                Rectangle {
                    id: cpuModule
                    visible: true
                    height: 24
                    width: 80
                    radius: 12
                    color: "transparent"
                    anchors.right: memModule.left
                    anchors.rightMargin: 5

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
                            text: root.cpuPercent + "%"
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
                    border.width: 1
                    border.color: Qt.alpha(root.theme.primary, 0.1)
                    color: Qt.alpha(root.theme.background, 1)
                    radius: 20
                    clip: true

                    transform: Scale {
                        origin.x: mprispopup.width / 2
                        origin.y: 0        // grow from the top edge
                        yScale: mprispopup.scale
                        xScale: 1          // keep width constant, only height "grows"
                    }

                    SequentialAnimation {
                        id: closeAnim

                        onStarted: albumPopup.animatingClosed = true
                        onStopped: albumPopup.animatingClosed = false

                        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 100 }
                        NumberAnimation { target: mprispopup; property: "scale"; to: 0.1; duration: 200; easing.type: Easing.InCirc }
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
                                    // Scale spin speed to the live-detected tempo. If we haven't
                                    // heard a beat in a while (detector still warming up, or
                                    // silence), fall back to the baseline speed instead of
                                    // freezing or drifting on a stale reading.
                                    const stale = (Date.now() - root.lastBeatTs) > 4000;
                                    const bpm = stale ? root.baseBpm : root.currentBpm;
                                    const degPerTick = root.baseDegPerTick * (bpm / root.baseBpm);
                                    discImage.rotation = (discImage.rotation + degPerTick) % 360;
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
                            text: content.formatTime(shell.activePlayer.position) + "/" + content.formatTime(shell.activePlayer.length)
                            font.family: root.settings.fontdefault
                            font.pixelSize: 12
                            font.bold: true
                            anchors.right: seekBar.right
                            anchors.bottom: seekBar.top
                            anchors.bottomMargin: 5
                        }


                        // Seek Bar — original flat track restored, with a scrolling wave
                        // overlaid only on the played portion. Wave amplitude/speed scale
                        // with the live-detected BPM (clamped so a bad reading can't spike it).
                        Item {
                            id: seekBar
                            width: 240
                            height: 20
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.verticalCenterOffset: 120
                            Layout.alignment: Qt.AlignHCenter

                            readonly property real progressFraction: {
                                if (!root.hasPlayer || shell.activePlayer.length <= 0)
                                    return 0;
                                if (seekMouseArea.pressed)
                                    return Math.max(0, Math.min(1, seekMouseArea.mouseX / seekBar.width));
                                if (discMouseArea.isDragging)
                                    return Math.max(0, Math.min(1, discMouseArea.previewPosition / shell.activePlayer.length));
                                return Math.max(0, Math.min(1, shell.activePlayer.position / shell.activePlayer.length));
                            }

                            readonly property bool isPlaying: root.hasPlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing

                            // how "energetic" the wave should look, derived from tempo,
                            // clamped to 0.6x-1.8x so a bad BPM reading can't spike it
                            readonly property real speedFactor: {
                                const stale = (Date.now() - root.lastBeatTs) > 4000;
                                const bpm = stale ? root.baseBpm : root.currentBpm;
                                return Math.max(0.6, Math.min(1.8, bpm / root.baseBpm));
                            }

                            property real amplitude: 0
                            Behavior on amplitude {
                                NumberAnimation { duration: 300; easing.type: Easing.OutCubic }
                            }
                            readonly property real targetAmplitude: seekBar.isPlaying ? (6 * seekBar.speedFactor) : 0
                            onTargetAmplitudeChanged: seekBar.amplitude = seekBar.targetAmplitude
                            Component.onCompleted: seekBar.amplitude = seekBar.targetAmplitude

                            // scrolling phase — this is what makes the wave move rather than
                            // sit still. Wiggles a bit faster on higher-tempo tracks too.
                            property real phase: 0
                            NumberAnimation on phase {
                                from: 0
                                to: Math.PI * 2
                                duration: 1400 / seekBar.speedFactor
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
                                width: parent.width
                                height: 5
                                radius: 1
                                anchors.verticalCenter: parent.verticalCenter
                                color: Qt.alpha(root.theme.primary, 0.2)
                            }

                            // original filled progress bar — unchanged from before
                            Rectangle {
                                id: progress_bar
                                width: Math.max(0, Math.min(seekBar.width, seekBar.width * seekBar.progressFraction))
                                height: trackBg.height
                                radius: trackBg.radius
                                anchors.verticalCenter: parent.verticalCenter
                                color: root.theme.background
                            }

                            // wave overlay — rides on top of progress_bar, ONLY over the played portion
                            Canvas {
                                id: waveCanvas
                                anchors.fill: parent
                                readonly property int waves: 3

                                onPaint: {
                                    const ctx = getContext("2d");
                                    ctx.clearRect(0, 0, width, height);
                                    const midY = height / 2;
                                    const amp = seekBar.amplitude * 0.7;
                                    const freq = (waves * 2 * Math.PI) / width;
                                    const splitX = width * seekBar.progressFraction;

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
                                }
                            }

                            MouseArea {
                                id: seekMouseArea
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor

                                property bool savedPlayingState: false

                                function updateSeekPosition(mouse) {
                                    if (root.hasPlayer && shell.activePlayer.length > 0) {
                                        const clampedX = Math.max(0, Math.min(mouse.x, seekBar.width));
                                        shell.activePlayer.position = shell.activePlayer.length * (clampedX / seekBar.width);
                                    }
                                }

                                onPressed: mouse => {
                                    if (root.hasPlayer) {
                                        savedPlayingState = (shell.activePlayer.playbackState === MprisPlaybackState.Playing);
                                        if (savedPlayingState && shell.activePlayer.canPause) {
                                            shell.activePlayer.pause();
                                        }
                                    }
                                    updateSeekPosition(mouse);
                                }

                                onPositionChanged: mouse => {
                                    if (pressed)
                                        waveCanvas.requestPaint();
                                }

                                onReleased: mouse => {
                                    updateSeekPosition(mouse);   // send the seek exactly once, here
                                    if (root.hasPlayer && savedPlayingState && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                    savedPlayingState = false;
                                }

                                onCanceled: {
                                    if (root.hasPlayer && savedPlayingState && shell.activePlayer.canPlay) {
                                        shell.activePlayer.play();
                                    }
                                    savedPlayingState = false;
                                }
                            }

                            Timer {
                                running: root.hasPlayer && shell.activePlayer.playbackState == MprisPlaybackState.Playing && !seekMouseArea.pressed && !discMouseArea.isDragging && albumPopup.isOpen
                                interval: 150
                                repeat: true

                                onTriggered: if (root.hasPlayer)
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
                                radius: 12
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
                            visible: modelData.id > 0 && modelData.id <= 8
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
                                    if (rect.modelData.id < 9 && rect.occupied || rect.isCurrent)
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
                anchors.right: parent.right
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

                MouseArea {
                    cursorShape: Qt.PointingHandCursor
                    anchors.fill: parent
                    onClicked: notifications.centerOpen = !notifications.centerOpen

                    Process {
                        id: toggleProc
                        command: ["sh", "-c", "qs -p ~/.config/quickshell/Notifications.qml ipc call notifications toggle"]
                    }
                }

                Rectangle {
                    id: new_notification
                    implicitHeight: 8
                    implicitWidth: 8
                    radius: 8
                    anchors.left: tux_image.right
                    color: notifications.hasNotifications === true ? root.theme.primary : "transparent"
                    visible: notifications.hasNotifications === true
                }

                Image {
                    id: tux_image
                    source: notifications.hasNotifications ? "./assets/bell.svg" : "./assets/linux-logo-bold.svg"
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
            IdleInhibitor {
                id: inhibit
                window: panelbar
                enabled: toggleBtn.checked
            }

            Rectangle {
                id: inhibit_module
                width: 24
                height: 24
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: tray_module.left
                anchors.rightMargin: 15
                color: "transparent"
                radius: 6

                Image {
                    id: inhibit_image
                    anchors.centerIn: parent
                    source: inhibit.enabled ? "./assets/coffee.svg" : "./assets/moon.svg"
                    width: 20
                    height: 20
                    sourceSize.width: 22
                    sourceSize.height: 22
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
                    id: toggleBtn
                    cursorShape: Qt.PointingHandCursor
                    property bool checked: false
                    anchors.fill: parent
                    onClicked: {
                        checked = !checked;
                        blinkAnimation.restart();
                    }
                }
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
