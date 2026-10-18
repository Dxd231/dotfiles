pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Hyprland
import Quickshell.Services.Pipewire
import Quickshell.Services.Mpris
import Quickshell.Networking
import Quickshell.Bluetooth
import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import qs
import qs.Services

Scope {
    id: controlCenter

    property var notifications: null
    property var powerMenu: null
    property var activePlayer: null

    property bool centerOpen: notifications ? notifications.centerOpen : false

    function toggle(): void {
        if (notifications)
            notifications.toggleCenter();
    }
    function show(): void {
        if (notifications)
            notifications.centerOpen = true;
    }
    function hide(): void {
        if (notifications)
            notifications.centerOpen = false;
    }

    function openPowerMenu(): void {
        hide();
        if (powerMenu)
            powerMenu.open();
    }

    // Quick-settings navigation: "" is the tiles page; "wifi" / "bluetooth" replace it with a detail page
    property string page: ""
    readonly property bool wifiDrawerOpen: page === "wifi"
    readonly property bool btDrawerOpen: page === "bluetooth"

    function openPage(p): void {
        if (!centerOpen) show();
        page = p;
    }
    function togglePage(p): void {
        if (!centerOpen) {
            show();
            page = p;
        } else {
            page = page === p ? "" : p;
        }
    }

    function openWifiDrawer(): void { openPage("wifi"); }
    function closeWifiDrawer(): void { if (page === "wifi") page = ""; }
    function toggleWifiDrawer(): void { togglePage("wifi"); }
    function openBtDrawer(): void { openPage("bluetooth"); }
    function closeBtDrawer(): void { if (page === "bluetooth") page = ""; }
    function toggleBtDrawer(): void { togglePage("bluetooth"); }

    IpcHandler {
        target: "controlcenter"
        function toggle(): void { controlCenter.toggle(); }
        function show(): void { controlCenter.show(); }
        function hide(): void { controlCenter.hide(); }
        function close(): void { controlCenter.hide(); }
        function openWifi(): void { controlCenter.openWifiDrawer(); }
        function closeWifi(): void { controlCenter.closeWifiDrawer(); }
        function toggleWifi(): void { controlCenter.toggleWifiDrawer(); }
        function openBluetooth(): void { controlCenter.openBtDrawer(); }
        function closeBluetooth(): void { controlCenter.closeBtDrawer(); }
        function toggleBluetooth(): void { controlCenter.toggleBtDrawer(); }
        function scanWifi(): void { controlCenter.scanWifi(); }
        function discoverBluetooth(): void { controlCenter.discoverBluetooth(); }
        function toggleNightLight(): void { controlCenter.toggleSunset(); }
        function setGamma(g: int): void { controlCenter.setSunsetGamma(g); }
        function getGamma(): int { return controlCenter.sunsetGamma; }
    }

    // ---- Audio (Pipewire) ----
    readonly property PwNode sink: Pipewire.defaultAudioSink
    readonly property PwNode source: Pipewire.defaultAudioSource

    PwObjectTracker {
        objects: [controlCenter.sink, controlCenter.source]
    }

    readonly property real volume: sink && sink.audio ? Math.max(0, Math.min(1.0, sink.audio.volume)) : 0
    readonly property bool muted: sink && sink.audio ? sink.audio.muted : false

    function setVolume(v: real): void {
        if (sink && sink.audio) {
            sink.audio.volume = Math.max(0, Math.min(1.0, v));
            if (sink.audio.volume > 0 && sink.audio.muted)
                sink.audio.muted = false;
        }
    }

    function toggleMute(): void {
        if (sink && sink.audio)
            sink.audio.muted = !sink.audio.muted;
    }

    readonly property real micVolume: source && source.audio ? Math.max(0, Math.min(1.0, source.audio.volume)) : 0
    readonly property bool micMuted: source && source.audio ? source.audio.muted : false

    function setMicVolume(v: real): void {
        if (source && source.audio) {
            source.audio.volume = Math.max(0, Math.min(1.0, v));
            if (source.audio.volume > 0 && source.audio.muted)
                source.audio.muted = false;
        }
    }

    function toggleMicMute(): void {
        if (source && source.audio)
            source.audio.muted = !source.audio.muted;
    }

    // ---- Power profiles ----
    property var profiles: ["power-saver", "balanced", "performance"]
    property string currentProfile: "balanced"
    readonly property string currentProfileText: {
        if (currentProfile === "performance") return "Performance";
        if (currentProfile === "power-saver") return "Power Saver";
        return "Balanced";
    }

    Process {
        id: powerProfileGet
        command: ["powerprofilesctl", "get"]
        running: controlCenter.centerOpen
        stdout: SplitParser {
            onRead: data => {
                controlCenter.currentProfile = data.trim();
            }
        }
    }

    function cyclePowerProfile(): void {
        const idx = profiles.indexOf(currentProfile);
        const next = profiles[(idx + 1) % profiles.length];
        currentProfile = next;
        Quickshell.execDetached(["powerprofilesctl", "set", next]);
    }

    // ---- Hyprsunset (Night Light & Gamma) ----
    property bool sunsetActive: true
    property int sunsetGamma: 100
    readonly property int minGamma: 20
    readonly property int maxGamma: 100

    Process {
        id: sunsetQueryProc
        command: ["pgrep", "-x", "hyprsunset"]
        running: false
        onExited: (exitCode) => {
            controlCenter.sunsetActive = (exitCode === 0);
        }
    }

    Process {
        id: loadGammaProc
        command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/hyprsunset-gamma\" 2>/dev/null"]
        running: false
        stdout: SplitParser {
            onRead: data => {
                const parsed = parseInt(data.trim(), 10);
                if (!isNaN(parsed) && parsed >= controlCenter.minGamma && parsed <= controlCenter.maxGamma) {
                    controlCenter.sunsetGamma = parsed;
                }
            }
        }
    }

    Timer {
        id: gammaApplyTimer
        interval: 35
        repeat: false
        onTriggered: {
            controlCenter.applyGamma();
        }
    }

    Timer {
        id: sunsetStartupTimer
        interval: 150
        repeat: false
        onTriggered: {
            controlCenter.applyGamma();
        }
    }

    function applyGamma(): void {
        Quickshell.execDetached(["/usr/bin/hyprctl", "hyprsunset", "gamma", sunsetGamma.toString()]);
        flushGamma();
    }

    function flushGamma(): void {
        Quickshell.execDetached([
            "sh", "-c",
            "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/hyprsunset-gamma\"",
            "sh", sunsetGamma.toString()
        ]);
    }

    function setSunsetGamma(val: int): void {
        const clamped = Math.max(minGamma, Math.min(maxGamma, Math.round(val)));
        sunsetGamma = clamped;
        if (!sunsetActive) {
            sunsetActive = true;
            Quickshell.execDetached(["/usr/bin/hyprsunset"]);
            sunsetStartupTimer.restart();
        } else {
            if (gammaApplyTimer.running)
                gammaApplyTimer.restart();
            else
                gammaApplyTimer.start();
        }
    }

    function toggleSunset(): void {
        if (sunsetActive) {
            sunsetActive = false;
            Quickshell.execDetached(["killall", "-9", "hyprsunset"]);
        } else {
            sunsetActive = true;
            Quickshell.execDetached(["/usr/bin/hyprsunset"]);
            sunsetStartupTimer.restart();
        }
    }

    // ---- Do Not Disturb ----
    readonly property bool dnd: notifications ? notifications.dnd : false
    function toggleDnd(): void {
        if (notifications)
            notifications.dnd = !notifications.dnd;
    }

    // ---- Keep Awake (Idle Inhibitor synced with bar) ----
    property var inhibitModule: null
    readonly property bool keepAwake: inhibitModule ? inhibitModule.active : false
    function toggleKeepAwake(): void {
        if (inhibitModule) {
            if (inhibitModule.toggleActive) {
                inhibitModule.toggleActive();
            } else if (inhibitModule.active) {
                inhibitModule.mode = 0;
                inhibitModule.expiresAt = 0;
                inhibitModule.remainingText = "";
            } else {
                inhibitModule.mode = 5;
                inhibitModule.expiresAt = 0;
                inhibitModule.remainingText = "";
            }
        }
    }

    // ---- Uptime ----
    readonly property string uptimeText: {
        const sec = SystemStats.uptimeSec, h = Math.floor(sec / 3600), m = Math.floor(sec % 3600 / 60);
        return "Up " + (h >= 24 ? Math.floor(h / 24) + "d " + h % 24 + "h" : h > 0 ? h + "h " + m + "m" : m + "m");
    }

    // ---- Networking / Wi-Fi ----
    readonly property var wifiDevice: Networking.devices.values.find(d => d.type === DeviceType.Wifi)
    // the radio switch is the global Networking.wifiEnabled (a device has no "active" property)
    readonly property bool wifiOn: Networking.wifiEnabled
    readonly property bool wifiScanning: !!wifiDevice && wifiDevice.scannerEnabled

    function scanWifi(): void {
        if (wifiDevice && wifiOn) {
            wifiDevice.scannerEnabled = true;
        }
    }

    // restart the scan: the scanner stays enabled while the page is open, so toggle it
    function rescanWifi(): void {
        if (wifiDevice && wifiOn) {
            wifiDevice.scannerEnabled = false;
            wifiDevice.scannerEnabled = true;
        }
    }

    function isActiveNetwork(n) {
        return n && (n.connected === true || n.state === ConnectionState.Connected);
    }

    readonly property var activeNetwork: {
        if (!wifiDevice || !wifiDevice.networks) return null;
        return Array.from(wifiDevice.networks.values).find(n => controlCenter.isActiveNetwork(n)) ?? null;
    }

    readonly property string activeSsid: activeNetwork ? (activeNetwork.name || "Connected") : (wifiOn ? "Disconnected" : "Wi-Fi Off")
    readonly property real wifiPercent: activeNetwork ? Math.round(activeNetwork.signalStrength * 100) : 0

    readonly property var sortedNetworks: {
        if (!wifiDevice || !wifiDevice.networks) return [];
        return Array.from(wifiDevice.networks.values)
            .filter(n => n.name !== "")
            .sort((a, b) => (controlCenter.isActiveNetwork(b) - controlCenter.isActiveNetwork(a)) || (b.signalStrength - a.signalStrength));
    }

    // detail-page groups, strongest signal first
    readonly property var savedNetworks: sortedNetworks.filter(n => !isActiveNetwork(n) && n.known)
    readonly property var availableNetworks: sortedNetworks.filter(n => !isActiveNetwork(n) && !n.known)

    function toggleWifi(): void {
        Networking.wifiEnabled = !Networking.wifiEnabled;
    }

    function connectNetwork(network, password): void {
        if (password && password.length > 0)
            network.connectWithPsk(password);
        else
            network.connect();
    }

    // ---- Bluetooth ----
    readonly property var btAdapter: Bluetooth.defaultAdapter
    readonly property bool bluetoothOn: !!btAdapter && btAdapter.enabled
    readonly property bool btDiscovering: !!btAdapter && btAdapter.discovering

    readonly property var btDevices: {
        if (!btAdapter || !btAdapter.devices) return [];
        return Array.from(btAdapter.devices.values)
            .filter(d => d.connected || d.paired || (d.name && d.name !== d.address.replace(/:/g, "-")))
            .sort((a, b) => (b.connected - a.connected) || (b.paired - a.paired) || (a.name || "").localeCompare(b.name || ""));
    }

    readonly property var connectedBtDevices: btDevices.filter(d => d.connected)
    readonly property var pairedBtDevices: btDevices.filter(d => !d.connected && d.paired)
    readonly property var nearbyBtDevices: btDevices.filter(d => !d.connected && !d.paired)

    readonly property var activeBtDevice: {
        const conn = btDevices.filter(d => d.connected);
        return conn.find(d => d.batteryAvailable) ?? conn[0] ?? null;
    }

    function toggleBluetooth(): void {
        if (btAdapter) {
            btAdapter.enabled = !btAdapter.enabled;
            if (btAdapter.enabled && btDrawerOpen) {
                discoverBluetooth();
            }
        }
    }

    function discoverBluetooth(): void {
        if (btAdapter && bluetoothOn) {
            btAdapter.discovering = true;
        }
    }

    function toggleBtDiscover(): void {
        if (btAdapter && bluetoothOn) {
            btAdapter.discovering = !btAdapter.discovering;
        }
    }

    // scan only while the matching page is showing
    onPageChanged: {
        if (page === "wifi") {
            if (wifiOn) scanWifi();
        } else if (wifiDevice && wifiDevice.scannerEnabled) {
            wifiDevice.scannerEnabled = false;
        }
        if (page === "bluetooth") {
            if (bluetoothOn) discoverBluetooth();
        } else if (btAdapter && btAdapter.discovering) {
            btAdapter.discovering = false;
        }
    }
    onWifiOnChanged: if (page === "wifi" && wifiOn) scanWifi()
    onBluetoothOnChanged: if (page === "bluetooth" && bluetoothOn) discoverBluetooth()

    // Back to the tiles page and refresh processes when the center closes / opens
    onCenterOpenChanged: {
        SystemStats.detailUsers += centerOpen ? 1 : -1;
        if (centerOpen) {
            page = "";
            powerProfileGet.running = false;
            powerProfileGet.running = true;
            sunsetQueryProc.running = false;
            sunsetQueryProc.running = true;
            loadGammaProc.running = false;
            loadGammaProc.running = true;
        } else {
            page = "";
            if (btAdapter && btAdapter.discovering) {
                btAdapter.discovering = false;
            }
        }
    }

    Component.onCompleted: {
        powerProfileGet.running = true;
        sunsetQueryProc.running = true;
        loadGammaProc.running = true;
    }
}
