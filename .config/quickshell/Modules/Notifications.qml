pragma ComponentBehavior: Bound
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Notifications
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Scope {
    id: notify_root

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
    property real wifiPercent: 0
    property string wifiIcon: "../assets/wifi-x.svg"

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
    property var networks: []
    property string selectedSsid: ""
    property string expandedSsid: ""
    // 1. Get the list of wifi networks — now reports errors too
    Process {
        id: scanProc
        command: ["nmcli", "-t", "-f", "ACTIVE,SSID,SIGNAL,SECURITY", "device", "wifi", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                notify_root.networks = lines.map(line => {
                    let parts = line.split(":");
                    return {
                        active: parts[0] === "yes",
                        ssid: parts[1],
                        signal: parts[2],
                        security: parts[3]
                    };
                }).filter(n => n.ssid.length > 0);
                console.log("wifi scan found:", notify_root.networks.length, "networks");
            }
        }
        stderr: StdioCollector {
            onStreamFinished: {
                if (this.text.trim().length > 0)
                    console.log("nmcli error:", this.text);
            }
        }
    }

    // 2. Connect to a chosen network
    Process {
        id: connectProc
        property string ssid: ""
        property string password: ""
        command: password.length > 0 ? ["nmcli", "device", "wifi", "connect", ssid, "password", password] : ["nmcli", "device", "wifi", "connect", ssid]
        onExited: exitCode => {
            if (exitCode === 0) {
                notify_root.expandedSsid = "";
                notify_root.scan();
            }
        }
    }

    function connectTo(ssid, password) {
        connectProc.ssid = ssid;
        connectProc.password = password;
        connectProc.running = true;
        wifiMenu.wifiMenu_open = false;
    }

    function scan() {
        scanProc.running = true;
    }

    Component.onCompleted: scan()

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

    Process {
        id: wifiStatProc
        command: ["nmcli", "-t", "-f", "active,signal", "dev", "wifi", "list", "--rescan", "no"]
        stdout: StdioCollector {
            onStreamFinished: {
                const match = text.match(/^yes:(\d+)/m);
                const val = match ? parseFloat(match[1]) : NaN;
                notify_root.wifiPercent = isNaN(val) ? 0 : val;
                notify_root.wifiIcon = isNaN(val) ? "../assets/wifi-x.svg" : val < 50 ? "../assets/wifi-medium.svg" : "../assets/wifi-high.svg";
            }
        }
    }

    function refreshStats() {
        netSpeedProc.running = false;
        netSpeedProc.running = true;
        cpuStatProc.running = false;
        cpuStatProc.running = true;
        memStatProc.running = false;
        memStatProc.running = true;
        wifiStatProc.running = false;
        wifiStatProc.running = true;
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
        visible: notify_root.centerOpen || panelBg.opacity > 0
        anchors {
            top: true
            left: true
        }
        margins {
            top: 6
            left: -10
            bottom: -4
        }
        implicitHeight: panelBg.height + 10
        implicitWidth: panelBg.width + 50
        color: "transparent"
        exclusionMode: ExclusionMode.Auto

        Item {
            anchors.fill: parent
            focus: true
            Keys.enabled: true
            Keys.onEscapePressed: {
                notify_root.centerOpen = false
            }
        }

        Rectangle {
            id: panelBg
            width: 380
            height: 1020
            radius: 18
            color: Qt.alpha(notify_root.theme.background, 0.8)
            border.width: 1
            border.color: Qt.alpha(notify_root.theme.surface_bright, 0.8)
            opacity: 0
            x: -270

            states: [
                State {
                    name: "open"
                    when: notify_root.centerOpen
                    PropertyChanges {
                        target: panelBg
                        x: 16
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !notify_root.centerOpen
                    PropertyChanges {
                        target: panelBg
                        x: -270
                        opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "open"

                    NumberAnimation {
                        properties: "x,opacity"
                        duration: 440
                        easing.type: Easing.OutBack
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "x,opacity"
                        duration: 400
                        easing.type: Easing.InBack
                    }
                }
            ]

            Image {
                id: yukari
                source: "../assets/marisa.png"
                sourceSize.width: 350
                sourceSize.height: 350
                Layout.preferredWidth: 350
                Layout.preferredHeight: 350
                anchors.verticalCenterOffset: -60
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 0.2
                    colorizationColor: root.theme.source_color
                }
                opacity: history.count === 0 ? 0.3 : 0.2

                Behavior on opacity {
                    NumberAnimation {
                        duration: 1000
                        easing.type: Easing.OutCirc
                    }
                }
            }

            ColumnLayout {
                id: centerCol
                anchors.fill: parent
                anchors.margins: 12
                spacing: 10

                Rectangle {
                    id: statsCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: statsRow.implicitHeight + 24
                    radius: 18
                    color: Qt.alpha(notify_root.theme.background, 1)
                    border.width: 0
                    border.color: Qt.alpha(notify_root.theme.on_background, 0)
                    clip: true

                    ColumnLayout {
                        id: statsRow
                        anchors.fill: parent
                        anchors.margins: 14
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
                                        color: (modelData === notify_root.current_profile) ? notify_root.theme.source_color : notify_root.theme.background
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
                                                colorizationColor: (modelData === notify_root.current_profile) ? notify_root.theme.background : notify_root.theme.source_color   // any matugen color
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
                                        colorizationColor: notify_root.theme.source_color   // any matugen color
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
                                    color: notify_root.theme.source_color
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
                                        colorizationColor: notify_root.theme.source_color   // any matugen color
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
                                    color: notify_root.theme.source_color
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
                                        colorizationColor: notify_root.theme.source_color   // any matugen color
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
                                    color: notify_root.theme.source_color
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
                                    if (wifiMenu.wifiMenu_open)
                                        notify_root.scan();
                                    wifiMenu.wifiMenu_open = !wifiMenu.wifiMenu_open;
                                }
                            }
                        }
                        // Wifi Menu
                        ColumnLayout {
                            id: wifiMenu
                            Layout.fillWidth: true
                            Layout.preferredHeight: wifiMenu_open ? implicitHeight : 0
                            Layout.maximumHeight: implicitHeight
                            clip: true
                            spacing: 6

                            property bool wifiMenu_open: false

                            Behavior on Layout.preferredHeight {
                                NumberAnimation {
                                    duration: 400
                                    easing.type: Easing.InOutCubic
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
                                Layout.preferredHeight: Math.min(contentHeight, 200)
                                clip: true
                                spacing: 4
                                model: notify_root.networks
                                delegate: Rectangle {
                                    id: netCard
                                    required property var modelData
                                    property bool expanded: notify_root.expandedSsid === modelData.ssid

                                    width: ListView.view.width
                                    height: contentCol.implicitHeight + 12
                                    radius: 18
                                    color: netCard.expanded ? Qt.alpha(notify_root.theme.on_background, 0.05) : (headerMouse.containsMouse ? Qt.alpha(notify_root.theme.on_background, 0.05) : "transparent")
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
                                                    text: netCard.modelData.ssid
                                                    color: netCard.modelData.active ? notify_root.theme.source_color : Qt.alpha(notify_root.theme.on_background, 0.7)
                                                    font.family: notify_root.theme.fontdefault
                                                    font.pixelSize: notify_root.theme.fontsize + 2
                                                    font.bold: true
                                                    elide: Text.ElideRight
                                                }
                                                Text {
                                                    text: netCard.modelData.signal + "%"
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
                                                onClicked: notify_root.expandedSsid = netCard.expanded ? "" : netCard.modelData.ssid
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
                                                    notify_root.connectTo(netCard.modelData.ssid, text);
                                                    text = "";
                                                }
                                            }
                                            Button {
                                                id: connectBtn
                                                text: "Connect"
                                                Layout.fillWidth: true
                                                onClicked: notify_root.connectTo(netCard.modelData.ssid, netPasswordField.text)

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
                            colorizationColor: notify_root.theme.source_color
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
                    Layout.preferredHeight: contentHeight
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

                // ---- calendar, pinned at the bottom (Windows-notification-center
                // style), reusing shell.qml's own state rather than a second
                // independent calendar ----
                Rectangle {
                    id: calendarCard
                    Layout.fillWidth: true
                    Layout.preferredHeight: calendarCol.implicitHeight + 24
                    radius: 18
                    color: "transparent"
                    border.width: 0
                    border.color: Qt.alpha(notify_root.theme.on_background, 0)
                    visible: !!notify_root.shellRoot

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
                                    color: notify_root.shellRoot.isHighlighted(modelData.date) || notify_root.shellRoot.isToday(modelData.date) ? notify_root.theme.source_color : "transparent"
                                    border.width: (notify_root.shellRoot.isToday(modelData.date) && !notify_root.shellRoot.isHighlighted(modelData.date)) ? 2 : 0
                                    border.color: notify_root.theme.source_color

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

    // pop up
    PanelWindow {
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors {
            top: true
            left: true
        }
        margins {
            top: 20
            left: 0
        }
        implicitWidth: 380
        implicitHeight: Math.max(0, column.implicitHeight)
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
                            // don't double-trigger from timer + click both firing
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
                        interval: 500   // must match the animation durations below
                        onTriggered: card.modelData.dismiss()
                    }
                    onClosingChanged: if (closing)
                        closeAnimTimer.start()

                    Layout.fillWidth: true
                    Layout.preferredHeight: closing ? 56 : layout.implicitHeight + 20

                    Behavior on Layout.preferredHeight {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.InCirc
                        }
                    }

                    opacity: closing ? 0 : 1
                    Behavior on opacity {
                        NumberAnimation {
                            duration: 500
                            easing.type: Easing.InCirc
                        }
                    }

                    transform: Translate {
                        x: card.closing ? -(card.width + 0) : 0
                        Behavior on x {
                            NumberAnimation {
                                duration: 500
                                easing.type: Easing.InCirc
                            }
                        }
                    }

                    radius: 8
                    color: Qt.alpha(notify_root.theme.background, 0.8)
                    clip: true
                    border.width: 2
                    border.color: modelData.urgency === NotificationUrgency.Critical ? notify_root.theme.source_color : Qt.alpha(notify_root.theme.surface_bright, 0.2)

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
                                onEntered: card.hovered = true
                                onExited: card.hovered = false
                                onClicked: card.startClose()   // was: card.modelData.dismiss()
                            }
                        }
                    }
                }
            }
        }
    }
}
