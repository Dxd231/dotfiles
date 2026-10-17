pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell.Networking
import qs
import qs.Components

// Quick settings: header, 2-column M3 Expressive tiles, night-light slider, and
// Wi-Fi / Bluetooth drawers as segmented lists.
Rectangle {
    id: ccCard

    required property var controlCenter
    readonly property var cc: controlCenter

    width: 400
    height: mainCol.implicitHeight + 32
    radius: Motion.shapeExtraLarge
    color: Colors.surface_container
    clip: true
    Behavior on height { Spring { speed: "default" } }

    ColumnLayout {
        id: mainCol
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 12

        // ---- header ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Chip {
                icon: "schedule"
                text: ccCard.cc ? ccCard.cc.uptimeText : ""
                enabled: false
                opacity: 1
            }
            Item { Layout.fillWidth: true }
            IconButton {
                icon: "settings_power"
                style: "tonal"
                onClicked: if (ccCard.cc) ccCard.cc.openPowerMenu()
            }
        }

        // ---- tiles ----
        GridLayout {
            Layout.fillWidth: true
            columns: 2
            columnSpacing: 8
            rowSpacing: 8

            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Internet"
                subtitle: ccCard.cc ? ccCard.cc.activeSsid : ""
                icon: ccCard.cc && ccCard.cc.wifiOn ? "wifi" : "wifi_off"
                on: !!ccCard.cc && ccCard.cc.wifiOn && ccCard.cc.activeNetwork !== null
                split: true
                drawerOpen: !!ccCard.cc && ccCard.cc.wifiDrawerOpen
                onToggled: ccCard.cc.toggleWifi()
                onOpened: {
                    ccCard.cc.btDrawerOpen = false;
                    ccCard.cc.wifiDrawerOpen = !ccCard.cc.wifiDrawerOpen;
                }
            }
            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Bluetooth"
                subtitle: !ccCard.cc ? "" : ccCard.cc.activeBtDevice ? (ccCard.cc.activeBtDevice.name || "Connected") : ccCard.cc.bluetoothOn ? "On" : "Off"
                icon: ccCard.cc && ccCard.cc.bluetoothOn ? (ccCard.cc.activeBtDevice ? "bluetooth_connected" : "bluetooth") : "bluetooth_disabled"
                on: !!ccCard.cc && ccCard.cc.bluetoothOn
                split: true
                drawerOpen: !!ccCard.cc && ccCard.cc.btDrawerOpen
                onToggled: ccCard.cc.toggleBluetooth()
                onOpened: {
                    ccCard.cc.wifiDrawerOpen = false;
                    ccCard.cc.btDrawerOpen = !ccCard.cc.btDrawerOpen;
                }
            }
            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Night light"
                subtitle: ccCard.cc && ccCard.cc.sunsetActive ? ccCard.cc.sunsetGamma + "%" : "Off"
                icon: "nightlight"
                on: !!ccCard.cc && ccCard.cc.sunsetActive
                onToggled: ccCard.cc.toggleSunset()
            }
            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Do not disturb"
                subtitle: ccCard.cc && ccCard.cc.dnd ? "On" : "Off"
                icon: "do_not_disturb_on"
                on: !!ccCard.cc && ccCard.cc.dnd
                onToggled: ccCard.cc.toggleDnd()
            }
            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Power mode"
                subtitle: ccCard.cc ? ccCard.cc.currentProfileText : ""
                icon: !ccCard.cc ? "eco" : ccCard.cc.currentProfile === "performance" ? "bolt" : ccCard.cc.currentProfile === "power-saver" ? "energy_savings_leaf" : "balance"
                on: !!ccCard.cc && ccCard.cc.currentProfile !== "balanced"
                onToggled: ccCard.cc.cyclePowerProfile()
            }
            QuickTile {
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                title: "Keep awake"
                subtitle: !ccCard.cc || !ccCard.cc.keepAwake ? "Off" : ccCard.cc.inhibitModule && ccCard.cc.inhibitModule.timed ? ccCard.cc.inhibitModule.remainingText : "On"
                icon: "coffee"
                on: !!ccCard.cc && ccCard.cc.keepAwake
                onToggled: ccCard.cc.toggleKeepAwake()
            }
        }

        // ---- night light strength ----
        ColumnLayout {
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 4

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                StyledText { Layout.fillWidth: true; role: "titleSmall"; text: "Night light strength" }
                Button {
                    size: "xs"
                    style: "text"
                    text: "Reset"
                    visible: !!ccCard.cc && ccCard.cc.sunsetGamma !== 100
                    onClicked: {
                        ccCard.cc.setSunsetGamma(100);
                        ccCard.cc.applyGamma();
                    }
                }
            }
            Slider {
                Layout.fillWidth: true
                size: "m"
                icon: "brightness_6"
                valueIndicator: true
                from: ccCard.cc ? ccCard.cc.minGamma : 20
                to: ccCard.cc ? ccCard.cc.maxGamma : 100
                stepSize: 5
                value: ccCard.cc ? ccCard.cc.sunsetGamma : 100
                valueText: Math.round(value) + "%"
                activeColor: ccCard.cc && ccCard.cc.sunsetActive ? Colors.primary : Colors.outline
                onMoved: v => ccCard.cc.setSunsetGamma(v)
                onPressedChanged: if (!pressed && ccCard.cc) ccCard.cc.flushGamma()
            }
        }

        // ---- Wi-Fi drawer ----
        DrawerSection {
            open: !!ccCard.cc && ccCard.cc.wifiDrawerOpen
            title: "Wi-Fi"
            busy: !!ccCard.cc && ccCard.cc.wifiScanning
            onClose: ccCard.cc.wifiDrawerOpen = false

            EmptyRow {
                visible: !!ccCard.cc && !ccCard.cc.wifiOn
                icon: "wifi_off"
                title: "Wi-Fi is off"
                actionText: "Turn on"
                onAction: ccCard.cc.toggleWifi()
            }
            EmptyRow {
                visible: !!ccCard.cc && ccCard.cc.wifiOn && ccCard.cc.sortedNetworks.length === 0
                icon: "wifi_find"
                title: "Searching for networks…"
            }

            ScrollableList {
                visible: !!ccCard.cc && ccCard.cc.wifiOn && ccCard.cc.sortedNetworks.length > 0
                model: ccCard.cc ? ccCard.cc.sortedNetworks : []
                delegate: SegmentedItem {
                    id: net
                    required property var modelData
                    required property int index
                    readonly property bool connected: !!ccCard.cc && ccCard.cc.isActiveNetwork(modelData)
                    readonly property int signal: Math.round((modelData.signalStrength ?? 0) * 100)
                    readonly property bool secured: modelData.security !== WifiSecurityType.Open
                    readonly property bool needsPassword: secured && !modelData.known
                    property bool askPassword: false

                    width: parent ? parent.width : 0
                    first: index === 0
                    last: index === (ccCard.cc ? ccCard.cc.sortedNetworks.length - 1 : 0)
                    color: connected ? Colors.secondary_container : Colors.surface_container_highest
                    implicitHeight: netCol.implicitHeight + 16
                    Behavior on implicitHeight { Spring { speed: "default" } }

                    ColumnLayout {
                        id: netCol
                        x: 16
                        y: 8
                        width: parent.width - 32
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 16
                            Item {
                                implicitWidth: 24
                                implicitHeight: 24
                                Icon {
                                    anchors.centerIn: parent
                                    name: net.signal >= 75 ? "signal_wifi_4_bar" : net.signal >= 50 ? "network_wifi_3_bar" : net.signal >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar"
                                    color: net.connected ? Colors.on_secondary_container : Colors.on_surface_variant
                                }
                                Icon {
                                    visible: net.secured
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.margins: -3
                                    name: "lock"
                                    size: 12
                                    color: net.connected ? Colors.on_secondary_container : Colors.on_surface_variant
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "bodyLarge"
                                    color: net.connected ? Colors.on_secondary_container : Colors.on_surface
                                    elide: Text.ElideRight
                                    text: net.modelData.name || "Hidden network"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "bodyMedium"
                                    color: net.connected ? Colors.on_secondary_container : Colors.on_surface_variant
                                    elide: Text.ElideRight
                                    text: net.connected ? "Connected" : (net.secured ? (net.modelData.known ? "Saved" : "Secured") : "Open")
                                }
                            }
                            Button {
                                size: "xs"
                                style: net.connected || net.askPassword ? "text" : "tonal"
                                text: net.connected ? "Disconnect" : net.askPassword ? "Cancel" : "Connect"
                                onClicked: {
                                    if (net.connected)
                                        net.modelData.disconnect();
                                    else if (net.askPassword)
                                        net.askPassword = false;
                                    else if (net.needsPassword)
                                        net.askPassword = true;
                                    else
                                        ccCard.cc.connectNetwork(net.modelData, "");
                                }
                            }
                        }

                        RowLayout {
                            visible: net.askPassword
                            Layout.fillWidth: true
                            spacing: 8
                            TextField {
                                id: pass
                                Layout.fillWidth: true
                                label: "Password"
                                password: true
                                onVisibleChanged: if (visible) forceActiveFocus()
                                onAccepted: text => {
                                    ccCard.cc.connectNetwork(net.modelData, text);
                                    net.askPassword = false;
                                }
                            }
                            IconButton {
                                icon: "arrow_forward"
                                style: "filled"
                                size: "m"
                                widthMode: "narrow"
                                onClicked: {
                                    ccCard.cc.connectNetwork(net.modelData, pass.text);
                                    net.askPassword = false;
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- Bluetooth drawer ----
        DrawerSection {
            open: !!ccCard.cc && ccCard.cc.btDrawerOpen
            title: "Bluetooth"
            busy: !!ccCard.cc && ccCard.cc.btDiscovering
            onClose: ccCard.cc.btDrawerOpen = false

            EmptyRow {
                visible: !!ccCard.cc && !ccCard.cc.bluetoothOn
                icon: "bluetooth_disabled"
                title: "Bluetooth is off"
                actionText: "Turn on"
                onAction: ccCard.cc.toggleBluetooth()
            }
            EmptyRow {
                visible: !!ccCard.cc && ccCard.cc.bluetoothOn && ccCard.cc.btDevices.length === 0
                icon: "bluetooth_searching"
                title: "Looking for devices…"
            }

            ScrollableList {
                visible: !!ccCard.cc && ccCard.cc.bluetoothOn && ccCard.cc.btDevices.length > 0
                model: ccCard.cc ? ccCard.cc.btDevices : []
                delegate: SegmentedItem {
                    id: dev
                    required property var modelData
                    required property int index
                    readonly property bool connected: modelData.connected

                    width: parent ? parent.width : 0
                    first: index === 0
                    last: index === (ccCard.cc ? ccCard.cc.btDevices.length - 1 : 0)
                    color: connected ? Colors.secondary_container : Colors.surface_container_highest
                    implicitHeight: 64

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 16
                        Icon {
                            name: dev.connected ? "bluetooth_connected" : "bluetooth"
                            color: dev.connected ? Colors.on_secondary_container : Colors.on_surface_variant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyLarge"
                                color: dev.connected ? Colors.on_secondary_container : Colors.on_surface
                                elide: Text.ElideRight
                                text: dev.modelData.name || dev.modelData.address || "Device"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyMedium"
                                color: dev.connected ? Colors.on_secondary_container : Colors.on_surface_variant
                                elide: Text.ElideRight
                                text: dev.connected
                                    ? "Connected" + (dev.modelData.batteryAvailable ? " · " + Math.round((dev.modelData.battery ?? 0) * 100) + "% battery" : "")
                                    : dev.modelData.paired ? "Saved" : "Available to pair"
                            }
                        }
                        Button {
                            size: "xs"
                            style: dev.connected ? "text" : "tonal"
                            text: dev.connected ? "Disconnect" : dev.modelData.paired ? "Connect" : "Pair"
                            onClicked: {
                                const d = dev.modelData;
                                if (d.connected)
                                    d.disconnect();
                                else if (d.paired)
                                    d.connect();
                                else {
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
}
