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
import "Colors.qml"
import "Settings.qml"
import "./Modules"

ShellRoot {
    id: shell

    Notifications {
        id: notifications
        theme: root.theme
        settings: root.settings
        calendarOpen: shell.calendarOpen
        shellRoot: shell
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
        property string fontdefault: "Google Sans"
        property string fontjp: "Zen Maru Gothic Medium"
        property int fontsize: 12
        property var settings: Settings {}
        readonly property bool hasPlayer: shell.activePlayer !== null && shell.activePlayer !== undefined
        property var theme: Colors {}
        property int global_radius: 10
        readonly property var kanjiNumbers: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

        readonly property string time: {
            Qt.formatDateTime(clock.date, "hh:mm");
        }
        readonly property string dateString: Qt.formatDateTime(clock.date, "ddd dd MMM")

        property string preferredPlayer: "spotify"
        property string memoryUsage: "0%"
        property string memformat: ""
        property string memCount: ""
        property bool memPercent: false
        property string calendar: ""
        property string networkInfo: "Disconnected"
        property string networkType: "disconnected"
        property string playing: "No Media"
    }

    //Memory
    Process {
        id: memUsage
        command: ["sh", "-c", "free -m | awk 'NR==2{printf \"%.0f of %.0fGB\\n\", $3/1024, $2/1024}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.memoryUsage = text.trim();
            }
        }
    }
    Process {
        id: memUsagePercent
        command: ["sh", "-c", "free | grep Mem | awk '{printf \"%.0f%%\", ($3/$2) * 100.0}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.memformat = text.trim();
            }
        }
    }

    Process {
        id: memUsageCount
        command: ["sh", "-c", "free -m | awk '/Mem:/{print $3}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.memCount = parseInt(this.text.trim()) || 0;
            }
        }
    }

    property var player: Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            memUsage.running = true;
            memUsagePercent.running = true;
            memUsageCount.running = true;
        }
    }

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
        margins.bottom: -24


        Item {
            id: roundDecorators
            anchors {
                left: parent.left
                right: parent.right
                top: realbar.bottom
            }
            height: 24   // or hardcode e.g. 20–30

            RoundCorner {
                id: leftCorner
                anchors {
                    top: parent.top
                    bottom: parent.bottom
                    left: parent.left
                }
                implicitSize: parent.height
                color: Qt.alpha(root.theme.background, 0.8)         
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
                color: Qt.alpha(root.theme.background, 0.8)
                corner: RoundCorner.CornerEnum.TopRight
            }
        }

        Rectangle {
            id: realbar
            height: 36
            anchors {
                top: parent.top
                left: parent.left
                right: parent.right
            }
            radius: 0
            bottomLeftRadius: 0
            bottomRightRadius: 0
            border.width: 0
            border.color: root.theme.surface_bright
            color: Qt.alpha(root.theme.background, 0.8)

            //Time Module
            Rectangle {
                id: clockmodule
                height: 24
                width: timerContent.width
                radius: root.global_radius
                anchors.rightMargin: 0
                color: "transparent"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.leftMargin: 0
                anchors.verticalCenter: parent.verticalCenter

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.verticalCenter: parent.verticalCenter
                    text: "時"
                    color: Qt.alpha(root.theme.on_background, 0.6)
                    rightPadding: 100
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

                    /* Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "./assets/clock.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.theme.source_color   // any matugen color
                        }
                    } */

                    ColumnLayout {
                        spacing: 0
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: root.time
                            color: root.theme.on_background
                            font.pixelSize: 16
                            font.family: root.settings.fontdefault
                            font.bold: true
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */
                        }
                        Text {
                            text: root.dateString
                            color: Qt.alpha(root.theme.on_background, 0.6)
                            font.pixelSize: 12
                            font.family: root.settings.fontdefault
                            font.bold: true
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */
                        }
                    }
                }
            }

            //Memory Module
            Rectangle {
                id: memModule
                visible: true
                height: 24
                width: memContent.width + 10
                radius: 12
                color: "transparent"
                anchors.right: tray_module.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter

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

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "./assets/memory.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                        layer.enabled: true
                        layer.effect: MultiEffect {
                            colorization: 1.0
                            colorizationColor: root.theme.source_color   // any matugen color
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.memPercent ? "Mem: " + root.memoryUsage : root.memformat
                        color: root.memCount > 12000 ? root.theme.source_color : root.theme.on_background
                        font.pixelSize: 14
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
            //Mpris
            Rectangle {
                id: mprisModule
                height: 30
                width: mprisContent.width + 24
                radius: root.global_radius
                color: "transparent"
                border.color: root.theme.source_color
                border.width: 0
                anchors.right: parent.right
                anchors.rightMargin: 10
                anchors.verticalCenter: parent.verticalCenter

                Row {
                    id: mprisContent
                    anchors.centerIn: parent
                    spacing: 8

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
                                color: root.theme.source_color
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

                    // ---- scrolling title, fixed-width instead of growing/eliding ----
                    Item {
                        id: marqueeClip
                        width: 120
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
                            font.pixelSize: 12
                            font.family: root.settings.fontjp
                            font.bold: shell.activePlayer && shell.activePlayer.loopState === MprisLoopState.Track ? true : false
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
            PanelWindow {
                id: albumPopup
                WlrLayershell.namespace: "quickshell:mpris_popup"

                WlrLayershell.layer: WlrLayer.Overlay
                WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
                exclusionMode: ExclusionMode.Auto

                property bool isOpen: false
                property int refreshTrigger: 0

                width: 360
                height: 530
                color: "transparent"
                visible: isOpen && root.hasPlayer || mprispopup.opacity > 0 && root.hasPlayer


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

                anchors {
                    top: true
                    right: true
                }
                margins.top: -1
                margins.right: 6

                Rectangle {
                    id: mprispopup
                    width: 360
                    height: 500
                    x: 0
                    color: Qt.alpha(root.theme.background, 0.8)
                    radius: 18
                    border.color: root.theme.surface_bright
                    border.width: 1
                    transformOrigin: Item.Top
                    opacity: 0
                    y: -270

                    states: [
                        State {
                            name: "open"
                            when: albumPopup.isOpen
                            PropertyChanges {
                                target: mprispopup
                                y: 8
                                opacity: 1
                            }
                        },
                        State {
                            name: "closed"
                            when: !albumPopup.isOpen
                            PropertyChanges {
                                target: mprispopup
                                y: -270
                                opacity: 0
                            }
                        }
                    ]

                    transitions: [
                        Transition {
                            from: "closed"
                            to: "open"

                            NumberAnimation {
                                properties: "y,opacity"
                                duration: 280
                                easing.type: Easing.OutCubic
                            }
                        },
                        Transition {
                            from: "open"
                            to: "closed"

                            NumberAnimation {
                                properties: "y,opacity"
                                duration: 240
                                easing.type: Easing.InCubic
                            }
                        }
                    ]
                    //Album Art
                    ClippingRectangle {
                        id: image
                        radius: 18
                        width: 320
                        height: 320
                        anchors.top: parent.top
                        color: "transparent"
                        anchors.topMargin: 12
                        anchors.horizontalCenter: parent.horizontalCenter
                        Image {
                            sourceSize.width: 320
                            sourceSize.height: 320
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            source: {
                                const isMPV = shell.activePlayer && shell.activePlayer.identity?.toLowerCase().includes("mpv");

                                if (isMPV) {
                                    return shell.thumbpath;
                                }
                                if (shell.activePlayer && shell.activePlayer.trackArtUrl) {
                                    return shell.activePlayer.trackArtUrl;
                                } else
                                    return "";
                            }
                            layer.enabled: true
                            layer.effect: ShaderEffect {}
                        }
                    }

                    // Track info
                    Column {
                        id: infoColumn
                        anchors.top: image.bottom
                        anchors.topMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 280
                        spacing: 4

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

                                text: shell.activePlayer && shell.activePlayer.trackTitle ? shell.activePlayer.trackTitle : "No Media"
                                color: root.theme.on_background
                                font.family: root.settings.fontjp
                                font.pixelSize: 15
                                font.bold: false
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
                                        duration: 600
                                        easing.type: Easing.InOutCubic
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
                                font.pixelSize: 12
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

                    // Seek Bar
                    Rectangle {
                        id: seekBar
                        anchors.top: infoColumn.bottom
                        anchors.topMargin: 14
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 200
                        height: 7
                        radius: 2

                        color: Qt.alpha(root.theme.source_color, 0.2)

                        Rectangle {
                            y: progress_bar.height - 9
                            x: progress_bar.width - 2
                            width: 11
                            height: 11
                            radius: 11
                            color: root.theme.source_color
                        }

                        Rectangle {
                            id: progress_bar
                            width: {
                                if (!root.hasPlayer || shell.activePlayer.length <= 0)
                                    return 0;
                                if (seekMouseArea.pressed) {
                                    return Math.max(0, Math.min(seekBar.width, seekMouseArea.mouseX));
                                }
                                return Math.min(seekBar.width, seekBar.width * (shell.activePlayer.position / shell.activePlayer.length));
                            }
                            height: parent.height
                            radius: parent.radius

                            color: root.theme.source_color

                            Behavior on width {
                                enabled: !seekMouseArea.pressed
                                NumberAnimation {
                                    duration: 80
                                    easing.type: Easing.OutBack
                                }
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
                            running: root.hasPlayer && shell.activePlayer.playbackState == MprisPlaybackState.Playing && !seekMouseArea.pressed
                            interval: 1
                            repeat: true

                            onTriggered: if (root.hasPlayer)
                                shell.activePlayer.positionChanged()
                        }
                    }

                    //Control Dock
                    Item {
                        id: controlDock
                        anchors.top: infoColumn.bottom
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -10
                        anchors.left: parent.left
                        anchors.leftMargin: 30
                        anchors.right: parent.right
                        anchors.rightMargin: 30

                        Rectangle {
                            id: playButtonContainer
                            property bool pressed: false
                            width: 40
                            height: 40
                            radius: 40
                            color: Qt.alpha(root.theme.on_background, 0)
                            anchors.centerIn: parent

                            Image {
                                id: playbutton
                                width: 20
                                height: 20
                                sourceSize.width: 22
                                sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.theme.source_color
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
                                anchors.horizontalCenterOffset: (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing) ? 0 : 1
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
                                    colorizationColor: root.theme.source_color
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
                                    colorizationColor: root.theme.source_color   // any matugen color
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

            // WORKSPACE //
            Item {
                id: workspacemodule
                anchors.left: shell_center.right
                anchors.leftMargin: 20
                anchors.verticalCenter: parent.verticalCenter
                width: dotsRow.width
                height: parent.height

                property bool pillInitialized: false

                // the one true pill — slides/resizes/recolors instead of each dot
                // cross-fading with its neighbor in place
                Rectangle {
                    id: activePill
                    y: Math.round((workspacemodule.height - height) / 2)
                    height: 28
                    radius: 30
                    z: 0

                    Behavior on x {
                        enabled: workspacemodule.pillInitialized
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutCubic
                        }
                    }
                    Behavior on width {
                        NumberAnimation {
                            duration: 280
                            easing.type: Easing.OutCubic
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
                            property bool isCurrent: rect.modelData.active || (rect.modelData.id < 0 && rect.modelData.visible)

                            onIsCurrentChanged: if (isCurrent)
                                Qt.callLater(workspacemodule.updatePill)
                            Component.onCompleted: if (isCurrent)
                                Qt.callLater(workspacemodule.updatePill)

                            Text {
                                id: label
                                anchors.centerIn: parent
                                text: {
                                    if (rect.modelData.id < 9)
                                        return root.kanjiNumbers[rect.modelData.id - 1] || String(rect.modelData.id);
                                    return String(rect.modelData.id);
                                }
                                color: rect.isCurrent ? root.theme.background : rect.occupied ? root.theme.source_color : root.theme.on_surface
                                font.family: root.settings.fontjp
                                font.pixelSize: 18
                                font.bold: true
                                renderType: Text.QtRendering
                                renderTypeQuality: Text.HighRenderTypeQuality

                                scale: rect.isCurrent ? 1.0 : 14 / 18
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
                            activePill.color = item.modelData.id < 0 ? root.theme.secondary : root.theme.source_color;
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
                implicitHeight: 24
                implicitWidth: rowlayout.implicitWidth + 4
                radius: root.global_radius
                color: transparentColor
                anchors.right: mprisModule.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                property color transparentColor: Qt.alpha(root.theme.source_color, 0)

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

                            // Render recolored layer ONLY for Fcitx5
                            Loader {
                                anchors.fill: parent
                                active: trayIcon.isFcitx
                                sourceComponent: Component {
                                    ColorOverlay {
                                        source: trayIcon
                                        color: root.theme.source_color // Replace with your desired hex color or dynamic Pywal/Matugen variable
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
                    border.color: root.theme.surface_bright
                    border.width: 1

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
                    border.color: root.theme.surface_bright
                    border.width: 1

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
                    color: notifications.hasNotifications === true ? root.theme.source_color : "transparent"
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
                        colorizationColor: root.theme.source_color
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
                anchors.right: memModule.left
                anchors.rightMargin: 10
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
                        colorizationColor: root.theme.source_color
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
            color: itemHover.hovered ? root.theme.source_color : "transparent"

            Text {
                anchors.verticalCenter: parent.verticalCenter
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.right: chevron.left
                text: entryDelegate.modelData.text
                color: entryDelegate.modelData.enabled ? root.theme.on_background : root.theme.surface_bright
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
