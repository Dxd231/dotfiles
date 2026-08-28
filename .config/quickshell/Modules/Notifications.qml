pragma ComponentBehavior: Bound
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import Quickshell.Services.Mpris
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Networking

Scope {
    id: notify_root
    
    property var mainroot
    property var theme
    property var settings
    property bool calendarOpen: false
    property bool centerOpen: false

    readonly property bool hasNotifications: history.count > 0
    property var shellRoot
    property var mutedApps: []

    property var profiles: ["power-saver", "balanced", "performance"]
    property string current_profile: "balanced"

    property real netDown: 0        // KB/s download
    property real netUp: 0          // KB/s upload
    property real _prevRx: 0        // internal: previous rx bytes
    property real _prevTx: 0        // internal: previous tx bytes

    onCenterOpenChanged: {
        if (!centerOpen) {
            _prevRx = 0;
            _prevTx = 0;
            netDown = 0;
            netUp = 0;
            wifiMenu.wifiMenu_open = false;
        }
        if (centerOpen) {
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }

    function formatSpeed(kb) {
        if (kb >= 1024) {
            return (kb / 1024).toFixed(1) + " MB/s";
        }
        if (kb >= 1) {
            return kb.toFixed(0) + " KB/s";
        }
        return "0 KB/s";
    }

    // ---- system stats shown at the top of the notification center ----
    property real cpuPercent: 0
    property real memPercent: 0
    property string wifiIcon: { 
        if (wifiPercent > 50) return "../assets/wifi-high.svg";
        if (wifiPercent > 0 && wifiDevice && wifiDevice.active !== false) return "../assets/wifi-medium.svg";
        return "../assets/wifi-x.svg";
    }
    ListModel {
        id: history
    }

    property alias centerPanelHeight: centerPanel.height

    // Wifi Speed
    Process {
        id: netSpeedProc
        command: ["sh", "-c", "cat /sys/class/net/wlan0/statistics/rx_bytes /sys/class/net/wlan0/statistics/tx_bytes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const rx = parseFloat(lines[0]) || 0;
                const tx = parseFloat(lines[1]) || 0;
                if (notify_root._prevRx > 0) {
                    notify_root.netDown = (rx - notify_root._prevRx) / 1024;
                    notify_root.netUp = (tx - notify_root._prevTx) / 1024;
                }
                notify_root._prevRx = rx;
                notify_root._prevTx = tx;
            }
        }
    }

    // wifi menu
    property string selectedSsid: ""
    property string expandedSsid: ""
    property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi) 
    property var networks: wifiDevice ? wifiDevice.networks.values : []
    property real wifiPercent: {
        if (!wifiDevice) return 0;
        let active = wifiDevice.networks?.values.find(n => n.connected);
        return active ? Math.round(active.signalStrength * 100) : 0;
    }

    function reasonText(reason) {
        if (reason === ConnectionFailReason.NoSecrets) return "wrong password";
        return "unknown error";
    }

    Component.onCompleted: {
        let dev = Networking.devices.values.find(d => d.type === DeviceType.Wifi);
        console.log(Object.keys(dev));
        if (wifiDevice) wifiDevice.scannerEnabled = true;
    }

    // 2. Connect to a chosen network
    function connectTo(network, password) {
        if (password.length > 0) {
            network.connectWithPsk(password);
        } else {
            network.connect();
        }
        wifiMenu.wifiMenu_open = false;
    }

    function scan() {
        if (wifiDevice) wifiDevice.scannerEnabled = true;
    }

    

    // pop sound
    Process {
        id: pop
        command: ["mpv", "--no-video", "/home/niconico/.config/quickshell/assets/notification.mp3", "exit"]
        running: false
    }


    // PowerProfilesCtl
    Process {
        id: powerprofilesctl
        command: ["sh", "-c", "powerprofilesctl get"]
        running: true
        stdout: SplitParser {
            onRead: data => notify_root.current_profile = data.trim()
        }
    }

    Process {
        id: setProfile
        property string target: ""
        command: ["powerprofilesctl", "set", target]
    }

    function setPowerprofile(profile) {
        setProfile.target = profile;
        setProfile.running = true;
        notify_root.current_profile = profile;
    }

    ///
    Process {
        id: cpuStatProc
        command: ["sh", "-c", "top -bn1 | grep 'Cpu(s)' | sed 's/.*, *\\([0-9.]*\\)%* id.*/\\1/' | awk '{printf \"%.0f\", 100 - $1}'"]
        stdout: StdioCollector {
            onStreamFinished: notify_root.cpuPercent = parseFloat(text.trim()) || 0
        }
    }

    Process {
        id: memStatProc
        command: ["sh", "-c", "free | grep Mem | awk '{printf \"%.0f\", ($3/$2) * 100.0}'"]
        stdout: StdioCollector {
            onStreamFinished: notify_root.memPercent = parseFloat(text.trim()) || 0
        }
    }

   

    function refreshStats() {
        netSpeedProc.running = false;
        netSpeedProc.running = true;
        cpuStatProc.running = false;
        cpuStatProc.running = true;
        memStatProc.running = false;
        memStatProc.running = true;
    }

    Timer {
        interval: 1000
        running: notify_root.centerOpen ? true : false
        repeat: true
        triggeredOnStart: true
        onTriggered: notify_root.refreshStats()
    }
    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        imageSupported: true
        keepOnReload: true
        onNotification: n => {
            history.insert(0, {
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                urgency: n.urgency,
                time: Qt.formatDateTime(new Date(), "HH:mm"),
                image: n.image || n.appIcon || ""
            });
            if (notify_root.mutedApps.indexOf(n.appName) === -1) {
                n.tracked = true;   // only pops up if not muted
            }
            Quickshell.execDetached(["sh", "-c", "paplay ~/.config/quickshell/assets/notification.mp3"])
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void {
            notify_root.centerOpen = !notify_root.centerOpen;
        }
        function show(): void {
            notify_root.centerOpen = true;
        }
        function hide(): void {
            notify_root.centerOpen = false;
        }
    }

    // notification center
    PanelWindow {
        id: centerPanel
        WlrLayershell.namespace: "quickshell:center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusiveZone: 0
       
        anchors {
            top: true
            left: true
        }
        margins {
            top: 0
        }
        implicitHeight: 1080
        implicitWidth: 1920
        color: "transparent"
        exclusionMode: ExclusionMode.Auto
        property bool animatingClosed: false
        visible: notify_root.centerOpen || animatingClosed

        Item {
            anchors.fill: parent
            focus: true
            Keys.enabled: true
            Keys.onEscapePressed: {
                notify_root.centerOpen = false
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: notify_root.centerOpen = false
        }

        Rectangle {
            id: panelBg
            width: 150
            height: 500
            radius: 18
            color: Qt.alpha(notify_root.theme.background, 0.95)
            border.width: 1
            border.color: Qt.alpha(notify_root.theme.surface_bright, 0.8)
            x: -350
            y: (1080 / 16 - height / 16) -10
            clip: true
            transformOrigin: Item.Right

            

            SequentialAnimation {
                id: closeAnim

                onStarted: centerPanel.animatingClosed = true
                onStopped: centerPanel.animatingClosed = false

                NumberAnimation { target: content; property: "opacity"; to: 0; duration: 180 }

                ParallelAnimation {
                    NumberAnimation { target: panelBg; property: "width"; to: 200; duration: 300; easing.type: Easing.InBack; easing.overshoot: 1.2; }
                    NumberAnimation { target: panelBg; property: "height"; to: 500; duration: 300; easing.type: Easing.InBack; easing.overshoot: 1.2 }
                }

                NumberAnimation { target: panelBg; property: "x"; to: -350; duration: 300; easing.type: Easing.InCirc }

            }

            SequentialAnimation {
                id: openAnim
                NumberAnimation {
                    target: panelBg
                    property: "x"
                    to: 14
                    duration: 300
                    easing.type: Easing.OutCirc
                }

                ParallelAnimation {
                    NumberAnimation {
                        target: panelBg
                        properties: "width"
                        to: 400   
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                    NumberAnimation {
                        target: panelBg
                        properties: "height"
                        to: 800   
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.2
                    }
                    NumberAnimation {
                        target: content
                        property: "opacity"
                        to: 1
                        duration: 300
                    }
                }
            }

            property bool isTouhou: {
                if (!shellRoot.activePlayer) return false;
                var artist = (shellRoot.activePlayer.trackArtist || "").toLowerCase();
                var title = (shellRoot.activePlayer.trackTitle || "").toLowerCase();
                return artist.includes("上海アリス") || 
                artist.includes("zun") || 
                artist.includes("records") || 
                artist.includes("幽閉") || 
                artist.includes("黄昏フロンティア") || 
                artist.includes("東京アクティブneets") ||
                title.includes("砕月") ||
                artist.includes("少女フラクタル");
            }

            property var gifsTH: [  "../assets/reimu-touhou.gif",
                                    "../assets/marisa-touhou.gif",
                                    "../assets/reimu-touhou.gif2.gif"]

            // The currently chosen GIF
            property string currentGifTou: "../assets/reimu-touhou.gif"

            Item {
                id: content
                anchors.fill: parent
                opacity: 0
                anchors.margins: 14
            
                
                AnimatedImage {
                    id: anim
                    source: panelBg.isTouhou ? panelBg.currentGifTou : ""
                    anchors.centerIn: parent
                    fillMode: Image.PreserveAspectFit
                    width: 200
                    height: 200 
                    sourceSize.width: 200
                    sourceSize.height: 200
                    asynchronous: true
                    opacity: notify_root.hasNotifications ? 0.5 : 1

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 200
                            easing.type: Easing.OutCirc
                        }
                    }

                    // Only play when this item is visible and music is playing
                    playing: visible && (!shellRoot.activePlayer || shellRoot.activePlayer.playbackState === MprisPlaybackState.Playing)
                    visible: panelBg.isTouhou && openAnim.stopped

                    // When it becomes visible (and starts playing), pick a new random GIF
                    onVisibleChanged: {
                        if (visible) {
                            panelBg.currentGifTou = panelBg.pickRandomTH()
                        }
                    }
                }

                ColumnLayout {
                    id: centerCol
                    anchors.fill: parent
                    spacing: 10

                    Rectangle {
                        id: statsCard
                        Layout.fillWidth: true
                        Layout.margins: 4
                        Layout.preferredHeight: statsRow.implicitHeight
                        radius: 18
                        color: Qt.alpha(notify_root.theme.background, 1)
                        clip: true

                        Behavior on height {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.InOutCirc
                            }
                        }

                        ColumnLayout {
                            id: statsRow
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 10

                            // Powerprofiles
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.maximumHeight: implicitHeight
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                RowLayout {
                                    spacing: 6

                                    Repeater {
                                        model: notify_root.profiles
                                        Rectangle {
                                            id: profiles_rect
                                            required property var modelData
                                            width: 50
                                            height: 28
                                            color: (modelData === notify_root.current_profile) ? notify_root.theme.primary : notify_root.theme.background
                                            radius: 4

                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 250
                                                    easing.type: Easing.OutCubic
                                                }
                                            }

                                            Image {
                                                anchors.verticalCenter: parent.verticalCenter
                                                anchors.horizontalCenter: parent.horizontalCenter
                                                sourceSize.width: 22
                                                sourceSize.height: 22
                                                Layout.preferredWidth: 22
                                                Layout.preferredHeight: 22
                                                fillMode: Image.PreserveAspectFit
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: (modelData === notify_root.current_profile) ? notify_root.theme.background : notify_root.theme.primary   // any matugen color
                                                }
                                                source: {
                                                    if (profiles_rect.modelData === "performance")
                                                        return "../assets/lightning-fill.svg";
                                                    if (profiles_rect.modelData === "balanced")
                                                        return "../assets/scales-fill.svg";
                                                    if (profiles_rect.modelData === "power-saver")
                                                        return "../assets/leaf-fill.svg";
                                                }
                                            }
                                            MouseArea {
                                                cursorShape: Qt.PointingHandCursor
                                                anchors.fill: parent
                                                onClicked: notify_root.setPowerprofile(profiles_rect.modelData)
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- CPU ----
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.maximumHeight: implicitHeight
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                RowLayout {
                                    spacing: 6
                                    Image {
                                        source: "../assets/cpu.svg"
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: notify_root.theme.primary   // any matugen color
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "CPU"
                                        color: notify_root.theme.on_background
                                        opacity: 0.7
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                    }
                                    Text {
                                        text: Math.round(notify_root.cpuPercent) + "%"
                                        color: notify_root.theme.on_background
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 5
                                    radius: 5
                                    color: Qt.alpha(notify_root.theme.on_background, 0.15)
                                    Rectangle {
                                        height: parent.height
                                        radius: 5
                                        color: notify_root.theme.primary
                                        width: parent.width * Math.min(1, Math.max(0, notify_root.cpuPercent / 100))
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- Memory ----
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.maximumHeight: implicitHeight
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                RowLayout {
                                    spacing: 6
                                    Image {
                                        source: "../assets/memory.svg"
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: notify_root.theme.primary
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "RAM"
                                        color: notify_root.theme.on_background
                                        opacity: 0.7
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                    }
                                    Text {
                                        text: Math.round(notify_root.memPercent) + "%"
                                        color: notify_root.theme.on_background
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 5
                                    radius: 5
                                    color: Qt.alpha(notify_root.theme.on_background, 0.15)
                                    Rectangle {
                                        height: parent.height
                                        radius: 5
                                        color: notify_root.theme.primary
                                        width: parent.width * Math.min(1, Math.max(0, notify_root.memPercent / 100))
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                            }

                            // ---- WiFi ----
                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.maximumHeight: implicitHeight
                                Layout.alignment: Qt.AlignTop
                                spacing: 6

                                RowLayout {
                                    spacing: 6
                                    Image {
                                        source: notify_root.wifiIcon
                                        sourceSize.width: 22
                                        sourceSize.height: 22
                                        Layout.preferredWidth: 22
                                        Layout.preferredHeight: 22
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: notify_root.theme.primary
                                        }
                                    }
                                    Text {
                                        Layout.fillWidth: true
                                        text: "NET"
                                        color: notify_root.theme.on_background
                                        opacity: 0.7
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                        /* renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting */
                                    }
                                    Text {
                                        text: "↓ " + notify_root.formatSpeed(notify_root.netDown) + "  ↑ " + notify_root.formatSpeed(notify_root.netUp)
                                        color: Qt.alpha(notify_root.theme.on_background, 0.75)
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: 11
                                        font.bold: true
                                        /* renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting */
                                    }
                                    Text {
                                        text: Math.round(notify_root.wifiPercent) + "%"
                                        color: notify_root.theme.on_background
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: notify_root.theme.fontsize
                                        font.bold: true
                                        /* renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferFullHinting */
                                    }
                                }
                                Rectangle {
                                    Layout.fillWidth: true
                                    height: 5
                                    radius: 5
                                    color: Qt.alpha(notify_root.theme.on_background, 0.15)
                                    Rectangle {
                                        height: parent.height
                                        radius: 5
                                        color: notify_root.theme.primary
                                        width: parent.width * Math.min(1, Math.max(0, notify_root.wifiPercent / 100))
                                        Behavior on width {
                                            NumberAnimation {
                                                duration: 300
                                                easing.type: Easing.OutCubic
                                            }
                                        }
                                    }
                                }
                                MouseArea {
                                    cursorShape: Qt.PointingHandCursor
                                    anchors.fill: parent
                                    onClicked: {
                                        wifiMenu.wifiMenu_open = !wifiMenu.wifiMenu_open
                                        if (wifiMenu.wifiMenu_open)
                                            notify_root.scan();
                                    }
                                }
                            }
                            // Wifi Menu
                            ColumnLayout {
                                id: wifiMenu
                                Layout.fillWidth: true
                                Layout.preferredHeight: wifiExpand * (content.height - 40) 
                                clip: true
                                spacing: 2

                                property real wifiExpand: wifiMenu.wifiMenu_open ? 1 : 0
                                Behavior on wifiExpand {
                                    NumberAnimation { duration: 400; easing.type: Easing.InOutCubic }
                                }

                                property bool wifiMenu_open: false

                                Behavior on height {
                                    NumberAnimation {
                                        duration: 400
                                        easing.type: Easing.InOutCirc
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "WiFi Networks:"
                                    font.bold: true
                                    color: notify_root.theme.on_background
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 10
                                    model: notify_root.networks
                                    delegate: Rectangle {
                                        id: netCard
                                        border.width: 2
                                        border.color: netCard.modelData.state === ConnectionState.Connected ? notify_root.theme.primary : notify_root.theme.surface_bright
                                        required property var modelData
                                        property bool expanded: notify_root.expandedSsid === modelData.name

                                        

                                        Connections {
                                            target: netCard.modelData
                                            function onConnectionFailed(reason) {
                                                console.log("connectionFailed fired:", reason);
                                                Quickshell.execDetached(["sh", "-c", `notify-send -i "/home/niconico/.config/quickshell/assets/wifi-x.svg" -a "" 'Connect failed'`]);
                                            }
                                        }

                                        width: ListView.view.width
                                        height: contentCol.implicitHeight + 12
                                        radius: 10
                                        color: Qt.alpha(notify_root.theme.background, 1)
                                        clip: true

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 150
                                                easing.type: Easing.InOutCubic
                                            }
                                        }
                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 100
                                            }
                                        }

                                        ColumnLayout {
                                            id: contentCol
                                            anchors.left: parent.left
                                            anchors.right: parent.right
                                            anchors.top: parent.top
                                            anchors.margins: 6
                                            spacing: 6

                                            Item {
                                                Layout.fillWidth: true
                                                Layout.preferredHeight: 28

                                                RowLayout {
                                                    anchors.fill: parent
                                                    anchors.leftMargin: 4
                                                    anchors.rightMargin: 4
                                                    spacing: 8

                                                    Text {
                                                        Layout.fillWidth: true
                                                        text: netCard.modelData.name
                                                        color: netCard.modelData.state === ConnectionState.Connected ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.7)
                                                        font.family: notify_root.theme.fontdefault
                                                        font.pixelSize: notify_root.theme.fontsize + 2
                                                        font.bold: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: Math.round((netCard.modelData.signalStrength ?? 0) * 100) + "%"
                                                        color: notify_root.theme.on_background
                                                        opacity: 0.6
                                                        font.pixelSize: notify_root.theme.fontsize
                                                    }
                                                }

                                                MouseArea {
                                                    id: headerMouse
                                                    anchors.fill: parent
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: notify_root.expandedSsid = netCard.expanded ? "" : netCard.modelData.name
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                visible: netCard.expanded

                                                TextField {
                                                    id: netPasswordField
                                                    Layout.fillWidth: true
                                                    placeholderText: "Password"
                                                    echoMode: TextInput.Password
                                                    onAccepted: {
                                                        notify_root.connectTo(netCard.modelData, text);
                                                        text = "";
                                                    }
                                                }
                                                Button {
                                                    id: connectBtn
                                                    text: "Connect"
                                                    Layout.fillWidth: true
                                                    onClicked: notify_root.connectTo(netCard.modelData, netPasswordField.text)

                                                    background: Rectangle {
                                                        radius: 6
                                                        color: connectBtn.pressed ? Qt.darker(notify_root.theme.source_color, 1.2) : (connectBtn.hovered ? Qt.lighter(notify_root.theme.source_color, 1.1) : notify_root.theme.source_color)
                                                        Behavior on color {
                                                            ColorAnimation {
                                                                duration: 100
                                                            }
                                                        }
                                                    }

                                                    contentItem: Text {
                                                        text: connectBtn.text
                                                        color: notify_root.theme.on_background  // or on_background, whatever fits your theme
                                                        font.family: notify_root.theme.fontdefault
                                                        font.pixelSize: notify_root.theme.fontsize
                                                        font.bold: true
                                                        horizontalAlignment: Text.AlignHCenter
                                                        verticalAlignment: Text.AlignVCenter
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        opacity: 1 - wifiMenu.wifiExpand
                        Layout.preferredHeight: implicitHeight * (1 - wifiMenu.wifiExpand)  // e.g. calendarCol.implicitHeight + 4
                        clip: true
                        visible: wifiMenu.wifiExpand < 1   
                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: notify_root.theme.on_background
                            font {
                                family: notify_root.theme.fontdefault
                                pixelSize: notify_root.theme.fontsize + 2
                                bold: true
                            }
                        }
                        Image {
                            source: "../assets/trash-simple-bold.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            opacity: notify_root.hasNotifications ? 0.9 : 0
                            visible: true
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: notify_root.theme.primary
                            }
                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                anchors.fill: parent
                                onClicked: history.clear()
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }
                    }

                    ListView {
                        id: historyList
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        opacity: 1 - wifiMenu.wifiExpand
                        Layout.preferredHeight: implicitHeight * (1 - wifiMenu.wifiExpand)
                        visible: wifiMenu.wifiExpand < 1
                        clip: true
                        spacing: 8
                        boundsBehavior: Flickable.StopAtBounds
                        ScrollBar.vertical: ScrollBar {
                            policy: ScrollBar.AsNeeded
                        }

                        add: Transition {
                            NumberAnimation {
                                property: "opacity"
                                from: 0
                                to: 1
                                duration: 200
                            }
                            NumberAnimation {
                                property: "y"
                                from: target.y - 24
                                duration: 220
                                easing.type: Easing.OutCubic
                            }
                        }
                        remove: Transition {
                            NumberAnimation {
                                property: "opacity"
                                to: 0
                                duration: 220
                            }
                            NumberAnimation {
                                property: "x"
                                to: -historyList.width
                                duration: 2200
                                easing.type: Easing.OutCubic
                            }
                        }
                        displaced: Transition {
                            NumberAnimation {
                                properties: "y"
                                duration: 200
                                easing.type: Easing.OutCubic
                            }
                        }

                        model: history

                        delegate: Rectangle {
                            id: card
                            z: 1
                            required property string summary
                            required property string body
                            required property string appName
                            required property var urgency
                            required property string time
                            required property string image
                            required property int index

                            width: historyList.width
                            height: entryLayout.implicitHeight + 20
                            radius: 18
                            clip: true
                            color: notify_root.theme.background
                            border.width: 1
                            border.color: Qt.alpha(notify_root.theme.on_background, 0.2)

                            RowLayout {
                                id: entryLayout
                                anchors.fill: parent
                                anchors.margins: 10
                                spacing: 10
                                z: 1

                                Image {
                                    Layout.preferredHeight: 32
                                    Layout.preferredWidth: 32
                                    Layout.alignment: Qt.AlignTop
                                    fillMode: Image.PreserveAspectFit
                                    visible: source.toString() !== ""
                                    source: card.image || ""
                                }

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.summary
                                            color: notify_root.theme.on_background
                                            font.family: notify_root.theme.fontdefault
                                            font.pixelSize: 14
                                            font.bold: true
                                            /* renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferVerticalHinting */
                                            elide: Text.ElideRight
                                            z: 0
                                        }
                                        Text {
                                            text: card.time
                                            color: notify_root.theme.on_background
                                            opacity: 0.6
                                            font.family: notify_root.theme.fontdefault
                                            font.pixelSize: 11
                                            font.bold: true
                                            /* renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferVerticalHinting */
                                        }
                                    }

                                    Text {
                                        Layout.fillWidth: true
                                        visible: text !== ""
                                        text: card.body
                                        color: notify_root.theme.on_background
                                        font.family: notify_root.theme.fontdefault
                                        font.pixelSize: 13
                                        font.bold: true
                                        opacity: 0.5
                                        /* renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferVerticalHinting */
                                        wrapMode: Text.WordWrap
                                    }

                                    RowLayout {
                                        Layout.fillWidth: true
                                        Text {
                                            Layout.fillWidth: true
                                            text: card.appName
                                            color: notify_root.theme.on_background
                                            opacity: 0.5
                                            font.family: notify_root.theme.fontdefault
                                        }
                                    }
                                }
                            }

                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                anchors.fill: parent
                                z: -1
                                onClicked: history.remove(card.index)
                            }
                        }
                    }

                    Rectangle {
                        id: calendarCard
                        Layout.fillWidth: true
                        radius: 18
                        color: "transparent"
                        border.width: 0
                        border.color: Qt.alpha(notify_root.theme.on_background, 0)
                        opacity: 1 - wifiMenu.wifiExpand
                        Layout.preferredHeight: (calendarCol.implicitHeight + 24) * (1 - wifiMenu.wifiExpand)
                        visible: wifiMenu.wifiExpand < 1

                        ColumnLayout {
                            id: calendarCol
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 8

                            RowLayout {
                                Layout.fillWidth: true

                                Text {
                                    text: "\u2039"
                                    color: notify_root.theme.on_background
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.family: notify_root.theme.fontdefault
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferVerticalHinting
                                    MouseArea {
                                        cursorShape: Qt.PointingHandCursor
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        onClicked: notify_root.shellRoot.shiftMonth(-1)
                                    }
                                }
                                Text {
                                    Layout.fillWidth: true
                                    horizontalAlignment: Text.AlignHCenter
                                    text: notify_root.shellRoot ? Qt.formatDate(notify_root.shellRoot.viewDate, "MMMM yyyy") : ""
                                    color: notify_root.theme.on_background
                                    font.pixelSize: 13
                                    font.bold: true
                                    font.family: notify_root.theme.fontdefault
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferVerticalHinting
                                }
                                Text {
                                    text: "\u203A"
                                    color: notify_root.theme.on_background
                                    font.pixelSize: 16
                                    font.bold: true
                                    font.family: notify_root.theme.fontdefault
                                    renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferVerticalHinting
                                    MouseArea {
                                        cursorShape: Qt.PointingHandCursor
                                        anchors.fill: parent
                                        anchors.margins: -6
                                        onClicked: notify_root.shellRoot.shiftMonth(1)
                                    }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Repeater {
                                    model: ["S", "M", "T", "W", "T", "F", "S"]
                                    delegate: Text {
                                        required property string modelData
                                        Layout.fillWidth: true
                                        horizontalAlignment: Text.AlignHCenter
                                        text: modelData
                                        color: notify_root.theme.on_background
                                        opacity: 0.5
                                        font.pixelSize: 10
                                        font.family: notify_root.theme.fontdefault
                                        renderType: Text.NativeRendering
                                        font.hintingPreference: Font.PreferVerticalHinting
                                        font.bold: true
                                    }
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: 7
                                rowSpacing: 3
                                columnSpacing: 3

                                Repeater {
                                    model: notify_root.shellRoot ? notify_root.shellRoot.gridCells : []

                                    delegate: Rectangle {
                                        id: dayCell
                                        required property var modelData

                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 26
                                        radius: 13
                                        opacity: modelData.inMonth ? 1.0 : 0.35
                                        color: notify_root.shellRoot.isHighlighted(modelData.date) || notify_root.shellRoot.isToday(modelData.date) ? notify_root.theme.primary : "transparent"
                                        border.width: (notify_root.shellRoot.isToday(modelData.date) && !notify_root.shellRoot.isHighlighted(modelData.date)) ? 2 : 0
                                        border.color: notify_root.theme.primary

                                        Behavior on color {
                                            ColorAnimation {
                                                duration: 120
                                            }
                                        }

                                        Text {
                                            anchors.centerIn: parent
                                            text: dayCell.modelData.date.getDate()
                                            color: notify_root.shellRoot.isHighlighted(dayCell.modelData.date) || notify_root.shellRoot.isToday(modelData.date) ? notify_root.theme.on_primary : notify_root.theme.on_background
                                            font.pixelSize: 11
                                            font.bold: true
                                            font.family: notify_root.theme.fontdefault
                                            renderType: Text.NativeRendering
                                            font.hintingPreference: Font.PreferVerticalHinting
                                        }

                                        MouseArea {
                                            cursorShape: Qt.PointingHandCursor
                                            anchors.fill: parent
                                            enabled: dayCell.modelData.inMonth
                                            onClicked: notify_root.shellRoot.toggleDay(dayCell.modelData.date)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // pop up
    PanelWindow {
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors {
            top: true
            left: true
        }
        margins {
            top: 30
            left: 0
        }
        implicitWidth: 300
        implicitHeight: Math.max(0, column.implicitHeight + 10)
        color: "transparent"
        visible: !notify_root.centerOpen && !notify_root.calendarOpen

        exclusionMode: ExclusionMode.Auto

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 10

            Repeater {
                id: card_repeater
                model: server.trackedNotifications
                delegate: Rectangle {
                    id: card
                    required property var modelData
                    property bool hovered: false
                    property bool closing: false

                    function startClose() {
                        if (card.closing)
                            return;
                        card.closing = true;
                    }

                    Timer {
                        id: dismiss_timer
                        running: card.modelData.urgency !== NotificationUrgency.Critical && !card.hovered && !card.closing
                        interval: 5000
                        onTriggered: card.startClose()
                    }

                    // once the slide/fade finishes, actually tell the notification server to drop it
                    Timer {
                        id: closeAnimTimer
                        interval: 300   // must match the animation durations below
                        onTriggered: card.modelData.dismiss()
                    }
                    onClosingChanged: if (closing)
                        closeAnimTimer.start()

                    Layout.fillWidth: true
                    Layout.preferredHeight: layout.implicitHeight + 20

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InCirc
                        }
                    }

                    opacity: closing ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 300
                            easing.type: Easing.InCirc
                        }
                    }

                    transform: Translate {
                        x: card.closing ? -(card.width + 20) : 0
                        Behavior on x {
                            NumberAnimation {
                                duration: 300
                                easing.type: Easing.InCirc
                            }
                        }
                    }

                    radius: 18
                    color: Qt.alpha(notify_root.theme.background, 0.8)
                    clip: true
                    border.width: 1
                    border.color: modelData.urgency === NotificationUrgency.Critical ? Qt.alpha(notify_root.theme.primary, 0.5) : Qt.alpha(notify_root.theme.surface_bright, 0.5)

                    RowLayout {
                        id: layout
                        anchors.fill: parent
                        anchors.margins: 10
                        spacing: 10

                        Image {
                            Layout.preferredHeight: 36
                            Layout.preferredWidth: 36
                            Layout.alignment: Qt.AlignTop
                            fillMode: Image.PreserveAspectFit
                            visible: source.toString() !== ""
                            source: card.modelData.image || card.modelData.appIcon || ""
                        }

                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 2
                            Text {
                                Layout.fillWidth: true
                                text: card.modelData.summary
                                color: notify_root.theme.on_background
                                font.family: notify_root.theme.fontdefault
                                font.pixelSize: 13
                                font.bold: true
                                elide: Text.ElideRight
                                /* renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferVerticalHinting */
                            }
                            Text {
                                Layout.fillWidth: true
                                visible: text !== ""
                                text: card.modelData.body
                                color: notify_root.theme.on_background
                                font.family: notify_root.theme.fontdefault
                                font.pixelSize: 12
                                wrapMode: Text.WordWrap
                                //renderType: Text.NativeRendering
                                //font.hintingPreference: Font.PreferVerticalHinting
                            }
                            MouseArea {
                                cursorShape: Qt.PointingHandCursor
                                anchors.fill: parent
                                hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onEntered: card.hovered = true
                                onExited: card.hovered = false
                                onClicked: mouse => {
                                    if (mouse.button === Qt.RightButton) {
                                        card.startClose();
                                        return;
                                    }
                                    // Left click: invoke the default action if the app provided one
                                    const actions = card.modelData.actions;
                                    if (actions && actions.length > 0) {
                                        const defaultAction = actions.find(a => a.identifier === "default") || actions[0];
                                        defaultAction.invoke();
                                    }
                                    card.startClose();
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
