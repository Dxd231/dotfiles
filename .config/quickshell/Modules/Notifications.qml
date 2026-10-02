pragma ComponentBehavior: Bound
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import Quickshell.Networking

Scope {
    id: notify_root

    // ---- wired from shell.qml ----
    property var theme
    property var settings
    property real cpuPercent: 0
    property real memPercent: 0

    // ---- state ----
    property bool centerOpen: false
    property bool dnd: false            // do not disturb: no popups / sound (critical still shows)
    property int unread: 0              // notifications received while the center was closed
    property int maxHistory: 100
    property var mutedApps: []
    readonly property bool hasNotifications: history.count > 0
    property alias centerPanelHeight: centerPanel.height

    property double nowMs: Date.now()   // drives the relative timestamps
    property double _closedAt: 0

    property var profiles: ["power-saver", "balanced", "performance"]
    property string current_profile: "balanced"

    property real netDown: 0            // KB/s download
    property real netUp: 0              // KB/s upload
    property real _prevRx: 0
    property real _prevTx: 0

    ListModel {
        id: history
    }

    // ---------------------------------------------------------------- helpers

    // Bell button in the bar uses this: if the focus grab just closed the panel
    // on the same click, don't reopen it.
    function toggleCenter() {
        if (!notify_root.centerOpen && Date.now() - notify_root._closedAt < 250)
            return;
        notify_root.centerOpen = !notify_root.centerOpen;
    }

    function iconFor(n) {
        if (n.image)
            return n.image;
        const ic = n.appIcon || "";
        if (ic === "")
            return "";
        if (ic.startsWith("/") || ic.indexOf("://") !== -1)
            return ic;
        return Quickshell.iconPath(ic, true) || "";
    }

    function relTime(ms) {
        const s = Math.max(0, (notify_root.nowMs - ms) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m ago";
        if (s < 86400)
            return Math.floor(s / 3600) + "h ago";
        return Qt.formatDateTime(new Date(ms), "d MMM");
    }

    function formatSpeed(kb) {
        if (kb >= 1024)
            return (kb / 1024).toFixed(1) + " MB/s";
        if (kb >= 1)
            return kb.toFixed(0) + " KB/s";
        return "0 KB/s";
    }

    function playSound() {
        Quickshell.execDetached(["paplay", Quickshell.shellPath("assets/notification.mp3")]);
    }

    onCenterOpenChanged: {
        if (centerOpen) {
            unread = 0;
            nowMs = Date.now();
            calendarCard.reset();
            powerprofilesctl.running = false;
            powerprofilesctl.running = true;
            closeAnim.stop();
            openAnim.restart();
        } else {
            _closedAt = Date.now();
            _prevRx = 0;
            _prevTx = 0;
            netDown = 0;
            netUp = 0;
            wifiMenu.wifiMenu_open = false;
            openAnim.stop();
            closeAnim.restart();
        }
    }

    // ---------------------------------------------------------------- wifi

    property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
    readonly property string wifiIface: (wifiDevice && wifiDevice.name) ? wifiDevice.name : "wlan0"

    function isActive(n) {
        return n.connected === true || n.state === ConnectionState.Connected;
    }

    // connected first, then strongest first; ScriptModel diffs it so delegates (and any
    // half-typed password) survive re-sorts
    readonly property var sortedNetworks: {
        if (!notify_root.wifiDevice || !notify_root.wifiDevice.networks)
            return [];
        return Array.from(notify_root.wifiDevice.networks.values).filter(n => n.name !== "").sort((a, b) => (notify_root.isActive(b) - notify_root.isActive(a)) || (b.signalStrength - a.signalStrength));
    }

    ScriptModel {
        id: networkModel
        values: notify_root.sortedNetworks
    }

    property real wifiPercent: {
        if (!notify_root.wifiDevice || !notify_root.wifiDevice.networks)
            return 0;
        const active = notify_root.wifiDevice.networks.values.find(n => notify_root.isActive(n));
        return active ? Math.round(active.signalStrength * 100) : 0;
    }

    property string wifiIcon: {
        if (wifiPercent > 50)
            return "../assets/wifi-high.svg";
        if (wifiPercent > 0 && wifiDevice && wifiDevice.active !== false)
            return "../assets/wifi-medium.svg";
        return "../assets/wifi-x.svg";
    }

    function reasonText(reason) {
        if (reason === ConnectionFailReason.NoSecrets)
            return "wrong password";
        return "unknown error";
    }

    function connectTo(network, password) {
        if (password.length > 0)
            network.connectWithPsk(password);
        else
            network.connect();
        wifiMenu.wifiMenu_open = false;
    }

    Process {
        id: netSpeedProc
        command: ["sh", "-c", "cat /sys/class/net/" + notify_root.wifiIface + "/statistics/rx_bytes /sys/class/net/" + notify_root.wifiIface + "/statistics/tx_bytes"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.trim().split("\n");
                const rx = parseFloat(lines[0]) || 0;
                const tx = parseFloat(lines[1]) || 0;
                if (notify_root._prevRx > 0) {
                    notify_root.netDown = Math.max(0, (rx - notify_root._prevRx) / 1024);
                    notify_root.netUp = Math.max(0, (tx - notify_root._prevTx) / 1024);
                }
                notify_root._prevRx = rx;
                notify_root._prevTx = tx;
            }
        }
    }

    // ---------------------------------------------------------------- power profiles

    Process {
        id: powerprofilesctl
        command: ["powerprofilesctl", "get"]
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

    // ---------------------------------------------------------------- timers

    Timer {
        interval: 1000
        running: notify_root.centerOpen
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            netSpeedProc.running = false;
            netSpeedProc.running = true;
        }
    }

    // keeps "5m ago" fresh while the panel is open
    Timer {
        interval: 30000
        running: notify_root.centerOpen
        repeat: true
        onTriggered: notify_root.nowMs = Date.now()
    }

    // ---------------------------------------------------------------- server

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
                stamp: Date.now(),
                image: notify_root.iconFor(n)
            });
            while (history.count > notify_root.maxHistory)
                history.remove(history.count - 1);

            if (!notify_root.centerOpen)
                notify_root.unread++;

            const muted = notify_root.mutedApps.indexOf(n.appName) !== -1;
            const critical = n.urgency === NotificationUrgency.Critical;
            if (muted || (notify_root.dnd && !critical))
                return;   // kept in history, but no popup and no sound

            n.tracked = true;
            notify_root.playSound();
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void {
            notify_root.toggleCenter();
        }
        function show(): void {
            notify_root.centerOpen = true;
        }
        function hide(): void {
            notify_root.centerOpen = false;
        }
        function toggleDnd(): void {
            notify_root.dnd = !notify_root.dnd;
        }
        function clear(): void {
            history.clear();
        }
        function mute(app: string): void {
            if (notify_root.mutedApps.indexOf(app) === -1)
                notify_root.mutedApps = notify_root.mutedApps.concat([app]);
        }
        function unmute(app: string): void {
            notify_root.mutedApps = notify_root.mutedApps.filter(a => a !== app);
        }
    }

    // ---------------------------------------------------------------- notification center

    // closes the panel when you click anywhere else
    HyprlandFocusGrab {
        windows: [centerPanel]
        active: centerPanel.visible && notify_root.centerOpen
        onCleared: notify_root.centerOpen = false
    }

    PanelWindow {
        id: centerPanel
        WlrLayershell.namespace: "quickshell:center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        exclusiveZone: 0
        exclusionMode: ExclusionMode.Auto

        anchors {
            top: true
            left: true
        }
        margins {
            top: 0
            left: 0
        }
        implicitWidth: 420
        implicitHeight: panelBg.height + 20
        color: "transparent"
        property bool animatingClosed: false
        visible: notify_root.centerOpen || animatingClosed

        Item {
            anchors.fill: parent
            focus: true
            Keys.enabled: true
            Keys.onEscapePressed: notify_root.centerOpen = false
        }

        Rectangle {
            id: panelBg
            width: 400
            height: Math.min(900, (centerPanel.screen ? centerPanel.screen.height : 1080) - 60)
            radius: 14
            border.color: Qt.alpha(notify_root.theme.primary, 0.1)
            border.width: 0
            color: Qt.lighter(notify_root.theme.background, 1.15)
            x: -410
            y: 10
            clip: true

            SequentialAnimation {
                id: closeAnim
                onStarted: centerPanel.animatingClosed = true
                onStopped: centerPanel.animatingClosed = false

                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 0
                    duration: 180
                }
                NumberAnimation {
                    target: panelBg
                    property: "x"
                    to: -410
                    duration: 300
                    easing.type: Easing.InCirc
                }
            }

            SequentialAnimation {
                id: openAnim
                NumberAnimation {
                    target: panelBg
                    property: "x"
                    to: 10
                    duration: 300
                    easing.type: Easing.OutCirc
                }
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 1
                    duration: 300
                }
            }

            Item {
                id: content
                anchors.fill: parent
                anchors.margins: 14
                opacity: 0

                ColumnLayout {
                    id: centerCol
                    anchors.fill: parent
                    spacing: 10

                    // ------------------------------------------------ system card
                    Rectangle {
                        id: statsCard
                        Layout.fillWidth: true
                        Layout.margins: 4
                        Layout.preferredHeight: statsInner.implicitHeight + 20
                        radius: 18
                        color: Qt.alpha(notify_root.theme.source_color, 0.10)
                        clip: true

                        ColumnLayout {
                            id: statsInner
                            anchors.fill: parent
                            anchors.margins: 10
                            spacing: 10

                            ColumnLayout {
                                id: statsTop
                                Layout.fillWidth: true
                                spacing: 10

                                // power profiles
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 6

                                    Repeater {
                                        model: notify_root.profiles
                                        delegate: Rectangle {
                                            id: profileRect
                                            required property var modelData
                                            readonly property bool current: modelData === notify_root.current_profile
                                            Layout.preferredWidth: 50
                                            Layout.preferredHeight: 28
                                            radius: 4
                                            color: profileRect.current ? notify_root.theme.primary : Qt.alpha(notify_root.theme.source_color, 0)
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 250
                                                    easing.type: Easing.OutCubic
                                                }
                                            }

                                            Image {
                                                anchors.centerIn: parent
                                                width: 22
                                                height: 22
                                                sourceSize.width: 22
                                                sourceSize.height: 22
                                                fillMode: Image.PreserveAspectFit
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: profileRect.current ? notify_root.theme.background : notify_root.theme.primary
                                                }
                                                source: {
                                                    if (profileRect.modelData === "performance")
                                                        return "../assets/lightning-fill.svg";
                                                    if (profileRect.modelData === "balanced")
                                                        return "../assets/scales-fill.svg";
                                                    return "../assets/leaf-fill.svg";
                                                }
                                            }
                                            MouseArea {
                                                anchors.fill: parent
                                                cursorShape: Qt.PointingHandCursor
                                                onClicked: notify_root.setPowerprofile(profileRect.modelData)
                                            }
                                        }
                                    }
                                }

                                NotifStatBar {
                                    theme: notify_root.theme
                                    settings: notify_root.settings
                                    icon: "../assets/cpu.svg"
                                    label: "CPU"
                                    valueText: Math.round(notify_root.cpuPercent) + "%"
                                    fraction: notify_root.cpuPercent / 100
                                }

                                NotifStatBar {
                                    theme: notify_root.theme
                                    settings: notify_root.settings
                                    icon: "../assets/memory.svg"
                                    label: "RAM"
                                    valueText: Math.round(notify_root.memPercent) + "%"
                                    fraction: notify_root.memPercent / 100
                                }

                                NotifStatBar {
                                    theme: notify_root.theme
                                    settings: notify_root.settings
                                    icon: notify_root.wifiIcon
                                    label: "NET"
                                    extraText: "\u2193 " + notify_root.formatSpeed(notify_root.netDown) + "  \u2191 " + notify_root.formatSpeed(notify_root.netUp)
                                    valueText: Math.round(notify_root.wifiPercent) + "%"
                                    fraction: notify_root.wifiPercent / 100
                                    clickable: true
                                    onClicked: wifiMenu.wifiMenu_open = !wifiMenu.wifiMenu_open
                                }
                            }

                            // ---- wifi menu: grows to fill the panel, hides everything below it ----
                            ColumnLayout {
                                id: wifiMenu
                                Layout.fillWidth: true
                                Layout.preferredHeight: wifiExpand * Math.max(0, content.height - statsTop.implicitHeight - 44)
                                visible: wifiExpand > 0.001
                                clip: true
                                spacing: 6

                                property bool wifiMenu_open: false
                                property real wifiExpand: wifiMenu_open ? 1 : 0
                                Behavior on wifiExpand {
                                    NumberAnimation {
                                        duration: 400
                                        easing.type: Easing.InOutCubic
                                    }
                                }
                                // only scan while the list is actually open
                                onWifiMenu_openChanged: {
                                    if (notify_root.wifiDevice)
                                        notify_root.wifiDevice.scannerEnabled = wifiMenu_open;
                                }

                                Text {
                                    Layout.fillWidth: true
                                    text: "Wi-Fi networks"
                                    font.bold: true
                                    font.family: notify_root.settings.fontdefault
                                    font.pixelSize: notify_root.settings.fontsize
                                    color: notify_root.theme.on_background
                                }

                                ListView {
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 8
                                    boundsBehavior: Flickable.StopAtBounds
                                    model: networkModel
                                    delegate: Rectangle {
                                        id: netCard
                                        required property var modelData
                                        readonly property bool isConnected: notify_root.isActive(netCard.modelData)
                                        readonly property bool known: netCard.modelData.known === true
                                        property bool needsPassword: false
                                        onIsConnectedChanged: if (isConnected) wifiMenu.wifiMenu_open = false
                                        property bool expanded: false

                                        width: ListView.view.width
                                        height: contentCol.implicitHeight + 12
                                        radius: 10
                                        clip: true
                                        color: Qt.alpha(notify_root.theme.background, 1)
                                        border.width: 2
                                        border.color: netCard.isConnected ? notify_root.theme.primary : notify_root.theme.outline_variant

                                        Behavior on height {
                                            NumberAnimation {
                                                duration: 150
                                                easing.type: Easing.InOutCubic
                                            }
                                        }

                                        Connections {
                                            target: netCard.modelData
                                            function onConnectionFailed(reason) {
                                            if (reason === ConnectionFailReason.NoSecrets) {
                                                netCard.needsPassword = true;
                                                netCard.expanded = true;
                                            }
                                                Quickshell.execDetached(["notify-send", "-i", Quickshell.shellPath("assets/wifi-x.svg"), "-a", "Wi-Fi", "Connect failed", notify_root.reasonText(reason)]);
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
                                                        color: netCard.isConnected ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.7)
                                                        font.family: notify_root.settings.fontdefault
                                                        font.pixelSize: notify_root.settings.fontsize + 2
                                                        font.bold: true
                                                        elide: Text.ElideRight
                                                    }
                                                    Text {
                                                        text: Math.round((netCard.modelData.signalStrength ?? 0) * 100) + "%"
                                                        color: notify_root.theme.on_background
                                                        opacity: 0.6
                                                        font.family: notify_root.settings.fontdefault
                                                        font.pixelSize: notify_root.settings.fontsize
                                                    }
                                                }
                                                MouseArea {
                                                    anchors.fill: parent
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: netCard.expanded = !netCard.expanded
                                                }
                                            }

                                            ColumnLayout {
                                                Layout.fillWidth: true
                                                spacing: 6
                                                visible: netCard.expanded

                                                TextField {
                                                    id: netPasswordField
                                                    Layout.fillWidth: true
                                                    // known networks already have a saved password
                                                    visible: !netCard.isConnected && (netCard.needsPassword || !netCard.known)
                                                    placeholderText: "Password"
                                                    placeholderTextColor: Qt.alpha(notify_root.theme.on_background, 0.4)
                                                    echoMode: TextInput.Password
                                                    color: notify_root.theme.on_background
                                                    font.family: notify_root.settings.fontdefault
                                                    font.pixelSize: notify_root.settings.fontsize
                                                    background: Rectangle {
                                                        radius: 6
                                                        color: Qt.alpha(notify_root.theme.on_background, 0.08)
                                                        border.width: netPasswordField.activeFocus ? 1 : 0
                                                        border.color: notify_root.theme.primary
                                                    }
                                                    onAccepted: {
                                                        notify_root.connectTo(netCard.modelData, text);
                                                        text = "";
                                                    }
                                                }
                                                Button {
                                                    id: connectBtn
                                                    Layout.fillWidth: true
                                                    text: netCard.isConnected ? "Disconnect" : "Connect"
                                                    onClicked: {
                                                        if (netCard.isConnected) {
                                                            netCard.modelData.disconnect();
                                                        } else {
                                                            notify_root.connectTo(netCard.modelData, netPasswordField.text);
                                                            netPasswordField.text = "";
                                                        }
                                                    }

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
                                                        color: notify_root.theme.on_background
                                                        font.family: notify_root.settings.fontdefault
                                                        font.pixelSize: notify_root.settings.fontsize
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

                    // ------------------------------------------------ header
                    RowLayout {
                        Layout.fillWidth: true
                        opacity: 1 - wifiMenu.wifiExpand
                        Layout.preferredHeight: implicitHeight * (1 - wifiMenu.wifiExpand)
                        visible: wifiMenu.wifiExpand < 1
                        clip: true
                        spacing: 8

                        Text {
                            Layout.fillWidth: true
                            text: "Notifications"
                            color: notify_root.theme.on_background
                            font {
                                family: notify_root.settings.fontdefault
                                pixelSize: notify_root.settings.fontsize + 2
                                bold: true
                            }
                        }

                        // do-not-disturb chip
                        Rectangle {
                            id: dndChip
                            Layout.preferredHeight: 24
                            Layout.preferredWidth: dndText.implicitWidth + 20
                            radius: 12
                            color: notify_root.dnd ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.1)
                            Behavior on color {
                                ColorAnimation {
                                    duration: 150
                                }
                            }
                            Text {
                                id: dndText
                                anchors.centerIn: parent
                                text: "Do not disturb"
                                color: notify_root.dnd ? notify_root.theme.on_primary : Qt.alpha(notify_root.theme.on_background, 0.8)
                                font.family: notify_root.settings.fontdefault
                                font.pixelSize: 11
                                font.bold: true
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: Qt.PointingHandCursor
                                onClicked: notify_root.dnd = !notify_root.dnd
                            }
                        }

                        Image {
                            source: "../assets/trash-simple-bold.svg"
                            sourceSize.width: 20
                            sourceSize.height: 20
                            opacity: notify_root.hasNotifications ? 0.9 : 0
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: notify_root.theme.primary
                            }
                            MouseArea {
                                anchors.fill: parent
                                enabled: notify_root.hasNotifications
                                cursorShape: Qt.PointingHandCursor
                                onClicked: history.clear()
                            }
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 120
                                }
                            }
                        }
                    }

                    // ------------------------------------------------ history
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        opacity: 1 - wifiMenu.wifiExpand
                        visible: wifiMenu.wifiExpand < 1
                        clip: true

                        ListView {
                            id: historyList
                            anchors.fill: parent
                            spacing: 8
                            clip: true
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
                                    from: -24
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
                                    duration: 220
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

                            delegate: NotifCard {
                                id: hcard
                                required property var model
                                required property int index

                                width: historyList.width
                                height: implicitHeight
                                theme: notify_root.theme
                                settings: notify_root.settings
                                summary: hcard.model.summary
                                body: hcard.model.body
                                appName: hcard.model.appName
                                iconSource: hcard.model.image
                                urgency: hcard.model.urgency
                                timeText: notify_root.relTime(hcard.model.stamp)

                                // history entries can't run actions (the app's notification is gone),
                                // so clicking just expands/collapses long ones
                                onActivated: hcard.toggleExpanded()
                                onCloseRequested: history.remove(hcard.index)
                            }
                        }

                        // empty state
                        Column {
                            anchors.centerIn: parent
                            spacing: 10
                            visible: history.count === 0
                            opacity: 0.5

                            Image {
                                anchors.horizontalCenter: parent.horizontalCenter
                                source: notify_root.dnd ? "../assets/moon.svg" : "../assets/bell.svg"
                                sourceSize.width: 32
                                sourceSize.height: 32
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: notify_root.theme.on_background
                                }
                            }
                            Text {
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: notify_root.dnd ? "Do not disturb is on" : "No notifications"
                                color: notify_root.theme.on_background
                                font.family: notify_root.settings.fontdefault
                                font.pixelSize: notify_root.settings.fontsize
                            }
                        }
                    }

                    // ------------------------------------------------ calendar
                    NotifCalendar {
                        id: calendarCard
                        theme: notify_root.theme
                        settings: notify_root.settings
                        Layout.fillWidth: true
                        opacity: 1 - wifiMenu.wifiExpand
                        Layout.preferredHeight: implicitHeight * (1 - wifiMenu.wifiExpand)
                        visible: wifiMenu.wifiExpand < 1
                        clip: true
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- popups

    PanelWindow {
        id: popupWindow
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors {
            top: true
            left: true
        }
        margins {
            top: 30
            left: 10
        }
        implicitWidth: 340
        implicitHeight: Math.max(0, column.implicitHeight + 10)
        color: "transparent"
        visible: !notify_root.centerOpen && server.trackedNotifications.values.length > 0
        exclusionMode: ExclusionMode.Auto

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 8

            Repeater {
                model: server.trackedNotifications
                delegate: NotifCard {
                    id: pcard
                    required property var modelData

                    Layout.fillWidth: true
                    theme: notify_root.theme
                    settings: notify_root.settings
                    slideIn: true
                    summary: pcard.modelData.summary
                    body: pcard.modelData.body
                    appName: pcard.modelData.appName
                    iconSource: notify_root.iconFor(pcard.modelData)
                    urgency: pcard.modelData.urgency
                    actions: pcard.modelData.actions
                    // critical notifications stay until dismissed; others use the app's timeout (seconds) or 5s
                    timeoutMs: pcard.modelData.urgency === NotificationUrgency.Critical ? 0 : (pcard.modelData.expireTimeout > 0 ? Math.min(30000, pcard.modelData.expireTimeout * 1000) : 5000)

                    function startClose() {
                        if (pcard.closing)
                            return;
                        pcard.closing = true;
                        closeTimer.start();
                    }

                    // wait for the slide-out before telling the server to drop it
                    Timer {
                        id: closeTimer
                        interval: 300
                        onTriggered: pcard.modelData.dismiss()
                    }

                    onCloseRequested: pcard.startClose()
                    onActivated: {
                        // left click runs the app's default action (if it has one), then closes
                        const acts = pcard.modelData.actions;
                        if (acts && acts.length > 0) {
                            const def = acts.find(a => a.identifier === "default");
                            if (def)
                                def.invoke();
                        }
                        pcard.startClose();
                    }
                }
            }
        }
    }
}
