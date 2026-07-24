pragma ComponentBehavior: Bound
//@ pragma UseQApplication
import Quickshell
import Quickshell.Hyprland
import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import QtQuick.Layouts
import Quickshell.Wayland
import "Colors.qml"
import "Color2.qml"

ShellRoot {
    id: shell
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
    property string fontdefault: "Space Grotesk"
    property string fontjp: "Zen Maru Gothic Medium"
    readonly property bool hasPlayer: activePlayer !== null && activePlayer !== undefined
    property var theme: Colors {}
    property string thumbpath: "file:///run/user/1000/mpv_thumbnail.png"
    property var theme2: Color2 {}
    // Setting Variables
    property int global_radius: 10
    // A list of Kanji numerals from 1 to 10
    readonly property var kanjiNumbers: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十"]

    QtObject {
        id: root
        property string preferredPlayer: "spotify"
        property string cpuUsage: "0%"
        property string memoryUsage: "0%"
        property string memformat: ""
        property bool memPercent: false
        property string networkInfo: "Disconnected"
        property string networkType: "disconnected"
        property int batteryLevelRaw: 0
        property string batteryLevel: "0%"
        property string batteryIcon: "󰂎"
        property bool batteryCharging: false
        property string temperature: "0°C"
        property string time: "--:--"
        property string playing: "No Media"
        property string calendar: "what day is this?"
        property int netStr: 0
    }

    Process {
        id: netProc
        command: ["sh", "-c", "eth=$(nmcli -t -f type,state dev 2>/dev/null | grep '^ethernet:connected'); if [ -n \"$eth\" ]; then echo 'ethernet:Ethernet'; else wifi=$(nmcli -t -f active,ssid dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2); if [ -n \"$wifi\" ]; then echo \"wifi:$wifi\"; else echo 'disconnected:'; fi; fi"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                const result = text.trim();
                const colonIdx = result.indexOf(':');
                const type = result.substring(0, colonIdx);
                const info = result.substring(colonIdx + 1);
                root.networkType = type;
                root.networkInfo = info || "Disconnected";
            }
        }
    }
    Process {
        id: swaync
        command: ["sh", "-c", "swaync-client --toggle-panel"]
        running: false
    }
    Process {
        id: netStrength
        command: ["sh", "-c", "nmcli -t -f active,ssid,signal dev wifi | grep '^yes' | cut -d: -f3"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.netStr = text.trim();
            }
        }
    }
    // CPU Usage
    Process {
        id: cpuProc
        command: ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{printf \"%.0f%%\\n\", 100 - $1}'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.cpuUsage = text.trim();
            }
        }
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
    //Clock
    Process {
        id: timeClock
        command: ["date", "+%H:%M"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.time = text.trim();
            }
        }
    }
    Process {
        id: calendar
        command: ["sh", "-c", "date '+%A, %d %B'"]
        running: true

        stdout: StdioCollector {
            onStreamFinished: {
                root.calendar = text.trim();
            }
        }
    }

    //Mpris
    property var player: Timer {
        interval: 3000
        running: true
        repeat: true
        onTriggered: {
            cpuProc.running = true;
            memUsage.running = true;
            calendar.running = true;
            netProc.running = true;
            netStrength.running = true;
            memUsagePercent.running = true;
            mpvthumb.running = true;
        }
    }
    Timer {
        interval: 60000
        running: true
        repeat: true
        onTriggered: {
            timeClock.running = true;
        }
    }
    //Actual Bar
    PanelWindow {
        WlrLayershell.namespace: "quickshell:thebar"
        id: panelbar
        anchors.top: true
        anchors.left: true
        anchors.right: true
        implicitHeight: 38
        color: "transparent"
        margins.right: 12
        margins.left: 12
        margins.top: 12

        Rectangle {
            anchors.fill: parent
            radius: 8
            bottomLeftRadius: 18
            bottomRightRadius: 18
            border.width: 1
            border.color: shell.theme.surface_bright
            color: Qt.alpha(shell.theme2.bg_color, 0.9)
            Rectangle {
                anchors.left: cpu.left
                anchors.right: netModule.right
                anchors.verticalCenter: parent.verticalCenter
                implicitHeight: 34
                implicitWidth: 24
                anchors.leftMargin: -2
                anchors.rightMargin: -2

                radius: shell.global_radius
                color: "transparent"

                z: 0
            }
            //Cpu Module
            Rectangle {
                id: cpu
                height: 24
                width: cpuContent.width + 20
                radius: shell.global_radius
                anchors.left: parent.left
                anchors.leftMargin: 30
                anchors.verticalCenter: parent.verticalCenter
                color: "transparent"
                Accessible.role: Accessible.StaticText
                Accessible.name: "CPU: " + root.cpuUsage

                Row {
                    id: cpuContent
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "./assets/cpu.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.cpuUsage
                        color: shell.theme.on_background
                        font.pixelSize: 14
                        font.family: shell.fontdefault
                        font.bold: true
                    }
                }
            }
            //Time Module
            Rectangle {
                id: clockmodule
                height: 24
                width: timerContent.width
                radius: shell.global_radius
                anchors.rightMargin: 0
                color: "transparent"
                anchors.left: calendarmodule.right // Snaps to the exact horizontal center
                anchors.verticalCenter: parent.verticalCenter     // Centers it vertic

                Row {
                    id: timerContent
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "./assets/clock.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.time
                        color: shell.theme.on_background
                        font.pixelSize: 14
                        font.family: shell.fontdefault
                        font.bold: true
                    }
                }
            }
            // CALENDAR //
            Rectangle {
                id: calendarmodule
                height: 24
                width: calendarContent.width + 30
                radius: shell.global_radius
                anchors.leftMargin: 60
                color: "transparent"
                anchors.left: netModule.left // Snaps to the exact horizontal center
                anchors.verticalCenter: parent.verticalCenter     // Centers it vertic

                Row {
                    id: calendarContent
                    anchors.centerIn: parent
                    spacing: 6

                    Image {
                        anchors.verticalCenter: parent.verticalCenter
                        source: "./assets/calendar.svg"
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.calendar
                        color: shell.theme.on_background
                        font.pixelSize: 14
                        font.family: shell.fontdefault
                        font.bold: true
                    }
                }
            }

            //Memory Module
            Rectangle {
                id: memModule
                height: 24
                width: memContent.width + 10
                radius: 12
                color: "transparent"
                anchors.left: cpu.right
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
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.memPercent ? root.memoryUsage : root.memformat
                        color: shell.theme.on_background
                        font.pixelSize: 14
                        font.family: shell.fontdefault
                        font.bold: true
                    }
                }
                MouseArea {
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
                width: mprisContent.width + 30
                radius: shell.global_radius
                color: "transparent"
                border.color: shell.theme.on_primary
                border.width: 0
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                Behavior on width {
                    NumberAnimation {
                        duration: 100
                        easing.type: Easing.InOutQuad
                    }
                }
                Row {
                    id: mprisContent
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        elide: Text.ElideRight
                        width: Math.min(implicitWidth, 500)
                        anchors.verticalCenter: parent.verticalCenter
                        text: {
                            if (!shell.activePlayer)
                                return "No Media";
                            const artist = shell.activePlayer.trackArtist || "";
                            const title = shell.activePlayer.trackTitle || "";
                            return artist ? title : title;
                        }
                        color: shell.theme.on_background
                        font.pixelSize: 16
                        font.family: shell.fontjp
                        font.bold: false
                        renderType: Text.NativeRendering
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    onClicked: albumPopup.isOpen = !albumPopup.isOpen
                }
            }
            PopupWindow {
                id: albumPopup
                property string thumbnailPath: ""
                property bool isOpen: false
                property int refreshTrigger: 0
                width: 330
                height: 426
                color: "transparent"
                visible: isOpen && shell.hasPlayer || mprispopup.opacity > 0 && shell.hasPlayer
                anchor {
                    item: mprisModule
                    edges: Edges.Bottom | Edges.Right
                }

                Rectangle {
                    id: mprispopup
                    width: 330
                    height: 420
                    x: 0
                    color: Qt.alpha(shell.theme.background, 0.6)
                    radius: 12
                    border.color: "transparent"
                    border.width: 2
                    transformOrigin: Item.Top
                    opacity: albumPopup.isOpen ? 1.0 : 0.0
                    y: albumPopup.isOpen ? 4 : -270

                    states: [
                        State {
                            name: "open"
                            when: albumPopup.isOpen
                            PropertyChanges {
                                target: mprispopup
                                y: 4
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
                                duration: 190
                                /* easing.type: Easing.InBackd */
                            }
                        },
                        Transition {
                            from: "open"
                            to: "closed"

                            NumberAnimation {
                                properties: "y,opacity"
                                duration: 200
                            }
                        }
                    ]
                    //Album Art
                    Image {
                        id: image
                        width: 294
                        height: 294
                        anchors.top: parent.top
                        anchors.topMargin: 12
                        anchors.horizontalCenter: parent.horizontalCenter
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
                    // Seek Bar
                    Rectangle {
                        id: seekBar
                        anchors.bottom: image.bottom
                        anchors.bottomMargin: -25
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 260
                        height: 6
                        radius: 2

                        color: Qt.alpha(shell.theme.source_color, 0.2)

                        Rectangle {
                            y: bar.height - 8
                            x: bar.width
                            width: 10
                            height: 10
                            radius: 10
                        }

                        Rectangle {
                            id: bar
                            width: shell.hasPlayer && shell.activePlayer.length > 0 ? parent.width * (shell.activePlayer.position / shell.activePlayer.length) : 0
                            height: parent.height
                            radius: parent.radius

                            color: shell.theme.source_color

                            Behavior on width {
                                NumberAnimation {
                                    duration: 80
                                    easing.type: Easing.OutElastic
                                }
                            }
                        }
                        MouseArea {
                            anchors.fill: parent

                            onPressed: mouse => {
                                const pos = mouse.x / seekBar.width;
                                shell.activePlayer.position = shell.activePlayer.length * pos;
                            }
                        }
                        Timer {
                            running: shell.hasPlayer && shell.activePlayer.playbackState == MprisPlaybackState.Playing
                            interval: 1000
                            repeat: true

                            onTriggered: if (shell.hasPlayer)
                                shell.activePlayer.positionChanged()
                        }
                    }

                    //Control Dock
                    Item {
                        id: controlDock
                        anchors.top: image.bottom
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: -20
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
                            color: Qt.alpha(shell.theme.on_background, 0)
                            anchors.centerIn: parent

                            Image {
                                id: playbutton
                                width: 20
                                height: 20
                                sourceSize.width: 22
                                sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
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
                                // Nudges the play triangle slightly right so it centers perfectly by eye
                                // anchors.horizontalCenterOffset: (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing) ? 0 : 1
                            }

                            MouseArea {
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
                                // Nudges the play triangle slightly right so it centers perfectly by eye
                                // anchors.horizontalCenterOffset: (shell.activePlayer && shell.activePlayer.playbackState === MprisPlaybackState.Playing) ? 0 : 1
                            }

                            MouseArea {
                                anchors.fill: parent
                                onClicked: if (shell.activePlayer)
                                    shell.activePlayer.previous()
                            }
                        }
                    }
                }
            }

            // WORKSPACE //
            Row {
                id: workspacemodule
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.leftMargin: 0
                leftPadding: 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: 10
                Repeater {
                    model: Hyprland.workspaces

                    Rectangle {
                        id: rect
                        required property var modelData
                        visible: modelData.id > 0
                        width: 30
                        height: 30
                        radius: 30
                        property bool occupied: modelData.lastIpcObject.windows > 0
                        property bool isCurrent: rect.modelData.active || (rect.modelData.id < 0 && rect.modelData.visible)

                        states: [
                            State {
                                name: "active"
                                when: rect.modelData.active
                                PropertyChanges {
                                    target: rect
                                    color: rect.modelData.id < 0 ? shell.theme.secondary : shell.theme.source_color
                                    height: 30
                                }
                            },
                            State {
                                name: "inactive"
                                when: !rect.modelData.active
                                PropertyChanges {
                                    target: rect
                                    color: "transparent"
                                    height: 30
                                }
                            }
                        ]

                        // Define the entry animation for the active state
                        transitions: [
                            Transition {
                                from: "inactive"
                                to: "active"

                                // Color fades smoothly in parallel with the bounce
                                ParallelAnimation {
                                    ColorAnimation {
                                        duration: 400
                                        easing.type: Easing.OutCirc
                                    }

                                    // This handles the temporary height stretch and return
                                    /* SequentialAnimation {
                                    NumberAnimation {
                                        target: rect
                                        property: "opacity"
                                        to: 0 // Temporary height expansion peak
                                        duration: 1200
                                        easing.type: Easing.OutQuad
                                    }
                                    NumberAnimation {
                                        target: rect
                                        property: "opacity"
                                        to: 1 // Return to base height
                                        duration: 1800
                                        easing.type: Easing.OutBack // Gives a slight snappy elastic settle
                                    }
                                } */
                                }
                            },
                            Transition {
                                from: "active"
                                to: "inactive"
                                // Smooth exit transition when moving away from a workspace
                                ParallelAnimation {
                                    ColorAnimation {
                                        duration: 200
                                    }
                                    /* NumberAnimation { target: rect; property: "opacity"; to: 1; duration: 2000; easing.type: Easing.OutCubic }
                                NumberAnimation { target: rect; property: "opacity"; to: 0; duration: 2000; easing.type: Easing.OutCubic } */
                                }
                            }
                        ]

                        Text {
                            anchors.centerIn: parent
                            text: {
                                if (rect.modelData.id < 0) {
                                    return "特別"; // This will override "-98" with the custom glyph cleanly
                                }
                                if (rect.modelData.id < 9) {
                                    return shell.kanjiNumbers[rect.modelData.id - 1] || String(rect.modelData.id);
                                }
                            }
                            color: rect.modelData.active ? shell.theme.background : rect.occupied ? shell.theme.source_color : shell.theme.on_surface
                            font.family: shell.fontjp
                            font.pixelSize: 16
                            font.bold: true
                            renderType: Text.NativeRendering
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: rect.modelData.activate()
                        }
                    }
                }
            }

            Rectangle {
                id: netModule
                height: 24
                width: netContent.width + 12
                radius: shell.global_radius
                color: "transparent"
                anchors.left: memModule.right
                anchors.leftMargin: 15
                anchors.verticalCenter: parent.verticalCenter
                Row {
                    id: netContent
                    spacing: 6
                    anchors.verticalCenter: parent.verticalCenter
                    Image {
                        anchors.centerIn: parent
                        anchors.verticalCenter: parent.verticalCenter
                        source: {
                            if (root.networkType === "ethernet")
                                return "./assets/network-bold.svg";
                            if (root.networkType === "wifi" && root.netStr >= 50)
                                return "./assets/wifi-high.svg";
                            if (root.networkType === "wifi" && root.netStr < 50)
                                return "./assets/wifi-medium.svg";
                            return "./assets/wifi-x.svg";
                        }
                        width: 20
                        height: 20
                        sourceSize.width: 22
                        sourceSize.height: 22
                        fillMode: Image.PreserveAspectFit
                    }

                    Text {
                        leftPadding: 18
                        anchors.verticalCenter: parent.verticalCenter
                        text: root.netStr + "%"
                        color: shell.theme.on_background
                        font.pixelSize: 14
                        font.family: shell.fontdefault
                        font.bold: true
                    }
                }
            }
            // TRAY //
            Rectangle {
                id: tray_module
                implicitHeight: 24
                implicitWidth: trayIcons.implicitWidth + 4
                radius: shell.global_radius
                color: transparentColor
                anchors.right: mprisModule.left
                anchors.rightMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                property color transparentColor: Qt.alpha(shell.theme.source_color, 0)
                RowLayout {
                    id: trayIcons
                    anchors.centerIn: parent
                    spacing: 2

                    Repeater {
                        model: SystemTray.items

                        MouseArea {
                            id: trayDelegate
                            required property SystemTrayItem modelData

                            Accessible.role: Accessible.Button
                            Accessible.name: modelData.tooltipTitle || modelData.title || "System tray item"

                            Layout.preferredWidth: 24
                            Layout.preferredHeight: 24

                            acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton

                            onClicked: mouse => {
                                if (mouse.button === Qt.LeftButton) {
                                    modelData.activate();
                                } else if (mouse.button === Qt.RightButton) {
                                    if (modelData.hasMenu) {
                                        menuAnchor.open();
                                    }
                                } else if (mouse.button === Qt.MiddleButton) {
                                    modelData.secondaryActivate();
                                }
                            }

                            IconImage {
                                anchors.centerIn: parent
                                source: trayDelegate.modelData.icon
                                implicitSize: 20
                            }

                            QsMenuAnchor {
                                id: menuAnchor
                                menu: trayDelegate.modelData.menu

                                anchor.window: trayDelegate.QsWindow.window
                                anchor.adjustment: PopupAdjustment.Flip
                                anchor.onAnchoring: {
                                    const window = trayDelegate.QsWindow.window;
                                    const widgetRect = window.contentItem.mapFromItem(trayDelegate, 0, trayDelegate.height, trayDelegate.width, trayDelegate.height);
                                    menuAnchor.anchor.rect = widgetRect;
                                }
                            }
                        }
                    }
                }
            }
            ///////
            Rectangle {
                implicitWidth: 24
                implicitHeight: 24
                anchors.left: parent.left
                anchors.leftMargin: 5
                anchors.verticalCenter: parent.verticalCenter
                radius: 12
                color: "transparent"

                MouseArea {
                    anchors.fill: parent
                    onClicked: swaync.running = true
                }

                Image {
                    source: "./assets/bell.svg"
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 20
                    height: 20
                    sourceSize.width: 22
                    sourceSize.height: 22
                    fillMode: Image.PreserveAspectFit
                }
            }
            IdleInhibitor {
                id: inhibit
                window: panelbar
                enabled: toggleBtn.checked
            }

            Rectangle {
                width: 30
                height: 30
                anchors.verticalCenter: parent.verticalCenter
                anchors.right: tray_module.left
                anchors.rightMargin: 10
                color: "transparent"
                radius: 6

                Image {
                    id: inhibit_image
                    anchors.centerIn: parent
                    source: inhibit.enabled ? "./assets/eye-bold.svg" : "./assets/eye-closed-bold.svg"
                }
                states: [
                    State {
                        name: "active"
                        when: toggleBtn.checked
                        PropertyChanges {
                            target: inhibit_image
                            height: 36
                        }
                    },
                    State {
                        name: "inactive"
                        when: !toggleBtn.checked
                        PropertyChanges {
                            target: inhibit_image
                            height: 36
                        }
                    }
                ]

                // Define the entry animation for the active state
                transitions: [
                    Transition {
                        from: "inactive"
                        to: "active"

                        ParallelAnimation {
                            ColorAnimation {
                                duration: 400
                                easing.type: Easing.OutCirc
                            }

                            // This handles the temporary height stretch and return
                            SequentialAnimation {
                                NumberAnimation {
                                    target: inhibit_image
                                    property: "height"
                                    to: 30 // Temporary height expansion peak
                                    duration: 120
                                    easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    target: inhibit_image
                                    property: "height"
                                    to: 36 // Return to base height
                                    duration: 180
                                    easing.type: Easing.OutBack // Gives a slight snappy elastic settle
                                }
                            }
                        }
                    },
                    Transition {
                        from: "active"
                        to: "inactive"

                        ParallelAnimation {
                            ColorAnimation {
                                duration: 200
                            }
                            NumberAnimation { target: ; property: "height"; to: 36; duration: 100; easing.type: Easing.OutCubic }
                            NumberAnimation { target: rect; property: "height"; to: 30; duration: 100; easing.type: Easing.OutCubic } 
                        }
                    }
                ]
                MouseArea {
                    id: toggleBtn
                    property bool checked: false
                    anchors.fill: parent
                    onClicked: checked = !checked

                    Behavior on checked {
                        NumberAnimation {
                            duration: 100
                            easing.type: Easing.InCirc
                        }
                    }
                }
            }
        }
    }
}
