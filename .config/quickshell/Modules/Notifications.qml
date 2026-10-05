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
import Quickshell.Bluetooth

Scope {
    id: notify_root

    // ---- wired from shell.qml ----
    property var theme
    property var settings
    property real cpuPercent: 0
    property real memPercent: 0

    // ---- bluetooth ----
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: !!btAdapter && btAdapter.enabled
    // paired / connected / named devices, connected first
    readonly property var btDevices: {
        if (!btAdapter || !btAdapter.devices)
            return [];
        return Array.from(btAdapter.devices.values)
            .filter(d => d.connected || d.paired || (d.name && d.name !== d.address.replace(/:/g, "-")))
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || ""));
    }
    // device shown on the bar: prefer a connected one that reports battery
    readonly property var btDevice: {
        const conn = btDevices.filter(d => d.connected);
        return conn.find(d => d.batteryAvailable) ?? conn[0] ?? null;
    }
    function toggleBluetooth() {
        if (btAdapter)
            btAdapter.enabled = !btAdapter.enabled;
    }

    // ---- night light (hyprsunset) ----
    property bool nightLightOn: false
    Process {
        id: sunsetCheckProc
        command: ["pgrep", "-x", "hyprsunset"]
        running: true
        onExited: exitCode => {
            notify_root.nightLightOn = (exitCode === 0);
        }
    }
    function toggleNightLight() {
        if (nightLightOn) {
            Quickshell.execDetached(["pkill", "hyprsunset"]);
            nightLightOn = false;
        } else {
            Quickshell.execDetached(["hyprsunset"]);
            nightLightOn = true;
        }
    }

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
            sunsetCheckProc.running = false;
            sunsetCheckProc.running = true;
            closeAnim.stop();
            openAnim.restart();
        } else {
            _closedAt = Date.now();
            _prevRx = 0;
            _prevTx = 0;
            netDown = 0;
            netUp = 0;
            wifiMenu.wifiMenu_open = false;
            btMenu.btMenu_open = false;
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
            border.width: 0
            color: Qt.lighter(notify_root.theme.background, 1.15)
            x: -410
            y: 10
            clip: true

            ParallelAnimation {
                id: closeAnim
                onStarted: centerPanel.animatingClosed = true
                onStopped: centerPanel.animatingClosed = false

                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 0
                    duration: 140
                    easing.type: Easing.InQuad
                }
                NumberAnimation {
                    target: panelBg
                    property: "x"
                    to: -410
                    duration: 200
                    easing.type: Easing.InCirc
                }
            }

            ParallelAnimation {
                id: openAnim
                NumberAnimation {
                    target: panelBg
                    property: "x"
                    to: 10
                    duration: 260
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.08
                }
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 1
                    duration: 200
                    easing.type: Easing.OutQuad
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

                    // ------------------------------------------------ controls card (profiles / toggles)
                    Rectangle {
                        id: controlsCard
                        Layout.fillWidth: true
                        Layout.margins: 4
                        Layout.bottomMargin: 0
                        Layout.preferredHeight: controlsInner.implicitHeight + 24
                        radius: 14
                        color: Qt.alpha(notify_root.theme.source_color, 0.10)
                        border.width: 0
                        clip: true

                        ColumnLayout {
                                id: controlsInner
                                anchors.fill: parent
                                anchors.margins: 12
                                spacing: 10

                                // power profiles
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    Repeater {
                                        model: notify_root.profiles
                                        delegate: Rectangle {
                                            id: profileRect
                                            required property var modelData
                                            readonly property bool current: modelData === notify_root.current_profile
                                            Layout.fillWidth: true
                                            Layout.preferredHeight: 34
                                            radius: 10
                                            color: profileRect.current ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.06)
                                            border.width: 0
                                            Behavior on color {
                                                ColorAnimation {
                                                    duration: 250
                                                    easing.type: Easing.OutCubic
                                                }
                                            }

                                            Image {
                                                anchors.centerIn: parent
                                                width: 20
                                                height: 20
                                                sourceSize.width: 20
                                                sourceSize.height: 20
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

                                // Quick Toggles: DND, Night Light, Bluetooth
                                RowLayout {
                                    Layout.fillWidth: true
                                    spacing: 8

                                    // DND toggle
                                    Rectangle {
                                        id: dndToggle
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: 10
                                        color: notify_root.dnd ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.06)
                                        border.width: 0

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "../assets/moon.svg"
                                                width: 18
                                                height: 18
                                                sourceSize.width: 18
                                                sourceSize.height: 18
                                                fillMode: Image.PreserveAspectFit
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: notify_root.dnd ? notify_root.theme.background : notify_root.theme.primary
                                                }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "DND"
                                                color: notify_root.dnd ? notify_root.theme.background : notify_root.theme.on_background
                                                font.pixelSize: notify_root.settings.fontsize - 1
                                                font.bold: true
                                                font.family: notify_root.settings.fontdefault
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notify_root.dnd = !notify_root.dnd
                                        }
                                    }

                                    // Night Light toggle
                                    Rectangle {
                                        id: nightLightToggle
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: 10
                                        color: notify_root.nightLightOn ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.06)
                                        border.width: 0

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "../assets/coffee.svg"
                                                width: 18
                                                height: 18
                                                sourceSize.width: 18
                                                sourceSize.height: 18
                                                fillMode: Image.PreserveAspectFit
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: notify_root.nightLightOn ? notify_root.theme.background : notify_root.theme.primary
                                                }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "Night"
                                                color: notify_root.nightLightOn ? notify_root.theme.background : notify_root.theme.on_background
                                                font.pixelSize: notify_root.settings.fontsize - 1
                                                font.bold: true
                                                font.family: notify_root.settings.fontdefault
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notify_root.toggleNightLight()
                                        }
                                    }

                                    // Bluetooth toggle
                                    Rectangle {
                                        id: btToggle
                                        Layout.fillWidth: true
                                        Layout.preferredHeight: 34
                                        radius: 10
                                        color: notify_root.bluetoothOn ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.06)
                                        border.width: 0

                                        Behavior on color {
                                            ColorAnimation { duration: 200 }
                                        }

                                        Row {
                                            anchors.centerIn: parent
                                            spacing: 6

                                            Image {
                                                anchors.verticalCenter: parent.verticalCenter
                                                source: "../assets/bluetooth.svg"
                                                width: 18
                                                height: 18
                                                sourceSize.width: 18
                                                sourceSize.height: 18
                                                fillMode: Image.PreserveAspectFit
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    colorization: 1.0
                                                    colorizationColor: notify_root.bluetoothOn ? notify_root.theme.background : notify_root.theme.primary
                                                }
                                            }
                                            Text {
                                                anchors.verticalCenter: parent.verticalCenter
                                                text: "BT"
                                                color: notify_root.bluetoothOn ? notify_root.theme.background : notify_root.theme.on_background
                                                font.pixelSize: notify_root.settings.fontsize - 1
                                                font.bold: true
                                                font.family: notify_root.settings.fontdefault
                                            }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notify_root.toggleBluetooth()
                                        }
                                    }
                                }
                        }
                    }

                    // ------------------------------------------------ polling card (net / bluetooth)
                    Rectangle {
                        id: statsCard
                        Layout.fillWidth: true
                        Layout.margins: 4
                        Layout.topMargin: 0
                        Layout.preferredHeight: statsInner.implicitHeight + 24
                        radius: 14
                        color: Qt.alpha(notify_root.theme.source_color, 0.10)
                        border.width: 0
                        clip: true

                        ColumnLayout {
                            id: statsInner
                            anchors.fill: parent
                            anchors.margins: 12
                            spacing: 10

                            ColumnLayout {
                                id: statsTop
                                Layout.fillWidth: true
                                spacing: 12

                                NotifStatBar {
                                    theme: notify_root.theme
                                    settings: notify_root.settings
                                    icon: notify_root.wifiIcon
                                    label: "NET"
                                    extraText: "\u2193 " + notify_root.formatSpeed(notify_root.netDown) + "  \u2191 " + notify_root.formatSpeed(notify_root.netUp)
                                    valueText: Math.round(notify_root.wifiPercent) + "%"
                                    fraction: notify_root.wifiPercent / 100
                                    clickable: true
                                    onClicked: {
                                        btMenu.btMenu_open = false;
                                        wifiMenu.wifiMenu_open = !wifiMenu.wifiMenu_open;
                                    }
                                }

                                // bluetooth: track shows the connected device's battery
                                NotifStatBar {
                                    theme: notify_root.theme
                                    settings: notify_root.settings
                                    icon: notify_root.bluetoothOn ? "../assets/bluetooth.svg" : "../assets/bluetooth-slash.svg"
                                    label: notify_root.btDevice ? (notify_root.btDevice.name || "BT") : "BT"
                                    extraText: !notify_root.bluetoothOn ? "Off" : (notify_root.btDevice ? "" : "No device")
                                    valueText: (notify_root.btDevice && notify_root.btDevice.batteryAvailable)
                                        ? Math.round(notify_root.btDevice.battery * 100) + "%"
                                        : (notify_root.btDevice ? "\u2014" : "")
                                    fraction: (notify_root.btDevice && notify_root.btDevice.batteryAvailable) ? notify_root.btDevice.battery : 0
                                    clickable: true
                                    onClicked: {
                                        wifiMenu.wifiMenu_open = false;
                                        btMenu.btMenu_open = !btMenu.btMenu_open;
                                    }
                                }
                            }

                            // ---- wifi menu: takes only the space it needs ----
                            ColumnLayout {
                                id: wifiMenu
                                Layout.fillWidth: true
                                readonly property real targetHeight: {
                                    if (notify_root.sortedNetworks.length === 0)
                                        return 70;
                                    const listH = Math.min(200, Math.max(50, wifiList.contentHeight > 0 ? wifiList.contentHeight : notify_root.sortedNetworks.length * 48));
                                    return listH + 32;
                                }
                                implicitHeight: wifiExpand * targetHeight
                                Layout.preferredHeight: implicitHeight
                                visible: wifiExpand > 0.001
                                clip: true
                                spacing: 6

                                property bool wifiMenu_open: false
                                property real wifiExpand: wifiMenu_open ? 1 : 0
                                Behavior on wifiExpand {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutCubic
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

                                Text {
                                    visible: notify_root.sortedNetworks.length === 0
                                    Layout.fillWidth: true
                                    text: "Scanning for networks\u2026"
                                    opacity: 0.5
                                    font.family: notify_root.settings.fontdefault
                                    font.pixelSize: notify_root.settings.fontsize - 1
                                    color: notify_root.theme.on_background
                                }

                                ListView {
                                    id: wifiList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 8
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }
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
                                        color: netCard.isConnected ? Qt.alpha(notify_root.theme.primary, 0.15) : Qt.alpha(notify_root.theme.on_background, 0.05)
                                        border.width: 0

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
                                                        font.pixelSize: notify_root.settings.fontsize + 1
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
                                                        border.width: 0
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
                                                        border.width: 0
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

                            // ---- bluetooth menu: takes only the space it needs ----
                            ColumnLayout {
                                id: btMenu
                                Layout.fillWidth: true
                                readonly property real targetHeight: {
                                    if (notify_root.btDevices.length === 0)
                                        return 70;
                                    const listH = Math.min(200, Math.max(44, btList.contentHeight > 0 ? btList.contentHeight : notify_root.btDevices.length * 46));
                                    return listH + 36;
                                }
                                implicitHeight: btExpand * targetHeight
                                Layout.preferredHeight: implicitHeight
                                visible: btExpand > 0.001
                                clip: true
                                spacing: 6

                                property bool btMenu_open: false
                                property real btExpand: btMenu_open ? 1 : 0
                                Behavior on btExpand {
                                    NumberAnimation {
                                        duration: 250
                                        easing.type: Easing.OutCubic
                                    }
                                }
                                // only discover while the list is actually open
                                onBtMenu_openChanged: {
                                    const a = notify_root.btAdapter;
                                    if (a && a.enabled)
                                        a.discovering = btMenu_open;
                                }

                                RowLayout {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 26
                                    spacing: 8

                                    Text {
                                        Layout.fillWidth: true
                                        text: "Bluetooth devices"
                                        font.bold: true
                                        font.family: notify_root.settings.fontdefault
                                        font.pixelSize: notify_root.settings.fontsize
                                        color: notify_root.theme.on_background
                                    }

                                    // adapter power switch
                                    Rectangle {
                                        Layout.preferredWidth: 40
                                        Layout.preferredHeight: 22
                                        radius: 11
                                        color: notify_root.bluetoothOn ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.12)
                                        Behavior on color { ColorAnimation { duration: 200 } }

                                        Rectangle {
                                            width: 16
                                            height: 16
                                            radius: 8
                                            anchors.verticalCenter: parent.verticalCenter
                                            x: notify_root.bluetoothOn ? parent.width - width - 3 : 3
                                            color: notify_root.bluetoothOn ? notify_root.theme.background : notify_root.theme.on_background
                                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: notify_root.toggleBluetooth()
                                        }
                                    }
                                }

                                Text {
                                    visible: notify_root.btDevices.length === 0
                                    Layout.fillWidth: true
                                    text: !notify_root.btAdapter ? "No Bluetooth adapter" : (notify_root.bluetoothOn ? "Searching for devices\u2026" : "Bluetooth is off")
                                    opacity: 0.5
                                    font.family: notify_root.settings.fontdefault
                                    font.pixelSize: notify_root.settings.fontsize - 1
                                    color: notify_root.theme.on_background
                                }

                                ListView {
                                    id: btList
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    clip: true
                                    spacing: 6
                                    boundsBehavior: Flickable.StopAtBounds
                                    ScrollBar.vertical: ScrollBar {
                                        policy: ScrollBar.AsNeeded
                                    }
                                    model: ScriptModel {
                                        values: notify_root.btDevices
                                    }
                                    delegate: Rectangle {
                                        id: btCard
                                        required property var modelData
                                        readonly property bool isConnected: btCard.modelData.connected === true
                                        readonly property bool busy: btCard.modelData.pairing === true
                                            || btCard.modelData.state === BluetoothDeviceState.Connecting
                                            || btCard.modelData.state === BluetoothDeviceState.Disconnecting

                                        width: ListView.view.width
                                        height: 40
                                        radius: 10
                                        color: btCard.isConnected
                                            ? Qt.alpha(notify_root.theme.primary, 0.15)
                                            : (btMouse.containsMouse ? Qt.alpha(notify_root.theme.on_background, 0.09) : Qt.alpha(notify_root.theme.on_background, 0.05))
                                        Behavior on color { ColorAnimation { duration: 120 } }

                                        RowLayout {
                                            anchors.fill: parent
                                            anchors.leftMargin: 10
                                            anchors.rightMargin: 10
                                            spacing: 8

                                            Text {
                                                Layout.fillWidth: true
                                                text: btCard.modelData.name || btCard.modelData.address
                                                color: btCard.isConnected ? notify_root.theme.primary : Qt.alpha(notify_root.theme.on_background, 0.75)
                                                font.family: notify_root.settings.fontdefault
                                                font.pixelSize: notify_root.settings.fontsize
                                                font.bold: true
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                visible: btCard.isConnected && btCard.modelData.batteryAvailable
                                                text: Math.round((btCard.modelData.battery ?? 0) * 100) + "%"
                                                color: notify_root.theme.on_background
                                                opacity: 0.6
                                                font.family: notify_root.settings.fontdefault
                                                font.pixelSize: notify_root.settings.fontsize - 1
                                            }
                                            Text {
                                                text: btCard.busy ? "\u2026" : (btCard.isConnected ? "Disconnect" : (btCard.modelData.paired ? "Connect" : "Pair"))
                                                color: btCard.isConnected ? notify_root.theme.primary : notify_root.theme.on_background
                                                opacity: 0.7
                                                font.family: notify_root.settings.fontdefault
                                                font.pixelSize: 12
                                                font.bold: true
                                            }
                                        }
                                        MouseArea {
                                            id: btMouse
                                            anchors.fill: parent
                                            hoverEnabled: true
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: {
                                                const d = btCard.modelData;
                                                if (btCard.busy)
                                                    return;
                                                if (d.connected) {
                                                    d.disconnect();
                                                } else if (d.paired) {
                                                    d.connect();
                                                } else {
                                                    d.trusted = true;
                                                    d.pair();
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

                        Rectangle {
                            visible: history.count > 0
                            Layout.preferredHeight: 22
                            Layout.preferredWidth: Math.max(22, countText.implicitWidth + 12)
                            radius: 11
                            color: Qt.alpha(notify_root.theme.primary, 0.18)
                            border.width: 0

                            Text {
                                id: countText
                                anchors.centerIn: parent
                                text: history.count
                                color: notify_root.theme.primary
                                font.family: notify_root.settings.fontdefault
                                font.pixelSize: 12
                                font.bold: true
                            }
                        }

                        Item {
                            Layout.fillWidth: true
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
            top: 0
            left: 0
        }
        implicitWidth: 364
        implicitHeight: Math.max(0, column.y + column.implicitHeight + 10)
        color: "transparent"
        visible: !notify_root.centerOpen && server.trackedNotifications.values.length > 0
        exclusionMode: ExclusionMode.Auto

        mask: Region {
            item: column
        }

        Column {
            id: column
            x: 14
            y: 48
            width: 340
            spacing: 8

            Repeater {
                model: server.trackedNotifications
                delegate: NotifCard {
                    id: pcard
                    required property var modelData

                    width: 340
                    height: implicitHeight
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
                        interval: 220
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
