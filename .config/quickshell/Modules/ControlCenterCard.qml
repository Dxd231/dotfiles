pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Quick settings: header, 2-column M3 Expressive tiles and a night-light slider. The Internet
// and Bluetooth tiles replace this whole card with a detail page (and back), Android style.
Rectangle {
    id: ccCard

    required property var controlCenter
    readonly property var cc: controlCenter
    // entrance stage (steps while the center is open) and whether it is open at all
    property int stage: 0
    property bool live: false

    readonly property bool onDetail: !!cc && cc.page !== ""
    readonly property int detailHeight: 480

    width: 400
    height: onDetail ? detailHeight : mainCol.implicitHeight + 32
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

        // slides out and fades while a detail page takes the card over
        opacity: ccCard.onDetail ? 0 : 1
        visible: opacity > 0
        enabled: !ccCard.onDetail
        Behavior on opacity { Fade {} }
        transform: Translate {
            x: ccCard.onDetail ? -24 : 0
            Behavior on x { Spring { speed: "default" } }
        }

        // ---- header ----
        RowLayout {
            id: headerRow
            Layout.fillWidth: true
            spacing: 8
            property real appear: ccCard.stage >= 1 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            transform: Translate { y: (1 - headerRow.appear) * 16 }

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
                id: internetTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 2 ? 1 : 0
                live: ccCard.live
                shapeOn: 4
                title: "Internet"
                subtitle: ccCard.cc ? ccCard.cc.activeSsid : ""
                icon: ccCard.cc && ccCard.cc.wifiOn ? "wifi" : "wifi_off"
                on: !!ccCard.cc && ccCard.cc.wifiOn && ccCard.cc.activeNetwork !== null
                split: true
                onToggled: ccCard.cc.toggleWifi()
                onOpened: ccCard.cc.page = "wifi"
            }
            QuickTile {
                id: bluetoothTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 3 ? 1 : 0
                live: ccCard.live
                shapeOn: 5
                title: "Bluetooth"
                subtitle: !ccCard.cc ? "" : ccCard.cc.activeBtDevice ? (ccCard.cc.activeBtDevice.name || "Connected") : ccCard.cc.bluetoothOn ? "On" : "Off"
                icon: ccCard.cc && ccCard.cc.bluetoothOn ? (ccCard.cc.activeBtDevice ? "bluetooth_connected" : "bluetooth") : "bluetooth_disabled"
                on: !!ccCard.cc && ccCard.cc.bluetoothOn
                split: true
                onToggled: ccCard.cc.toggleBluetooth()
                onOpened: ccCard.cc.page = "bluetooth"
            }
            QuickTile {
                id: nightTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 4 ? 1 : 0
                live: ccCard.live
                shapeOn: 2
                title: "Night light"
                subtitle: ccCard.cc && ccCard.cc.sunsetActive ? ccCard.cc.sunsetGamma + "%" : "Off"
                icon: "nightlight"
                on: !!ccCard.cc && ccCard.cc.sunsetActive
                onToggled: ccCard.cc.toggleSunset()
            }
            QuickTile {
                id: dndTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 5 ? 1 : 0
                live: ccCard.live
                shapeOn: 0
                title: "Do not disturb"
                subtitle: ccCard.cc && ccCard.cc.dnd ? "On" : "Off"
                icon: "do_not_disturb_on"
                on: !!ccCard.cc && ccCard.cc.dnd
                onToggled: ccCard.cc.toggleDnd()
            }
            QuickTile {
                id: powerTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 6 ? 1 : 0
                live: ccCard.live
                shapeOn: 1
                title: "Power mode"
                subtitle: ccCard.cc ? ccCard.cc.currentProfileText : ""
                icon: !ccCard.cc ? "eco" : ccCard.cc.currentProfile === "performance" ? "bolt" : ccCard.cc.currentProfile === "power-saver" ? "energy_savings_leaf" : "balance"
                on: !!ccCard.cc && ccCard.cc.currentProfile !== "balanced"
                onToggled: ccCard.cc.cyclePowerProfile()
            }
            QuickTile {
                id: awakeTile
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                appear: ccCard.stage >= 7 ? 1 : 0
                live: ccCard.live
                shapeOn: 4
                title: "Keep awake"
                subtitle: !ccCard.cc || !ccCard.cc.keepAwake ? "Off" : ccCard.cc.inhibitModule && ccCard.cc.inhibitModule.timed ? ccCard.cc.inhibitModule.remainingText : "On"
                icon: "coffee"
                on: !!ccCard.cc && ccCard.cc.keepAwake
                onToggled: ccCard.cc.toggleKeepAwake()
            }
        }

        // ---- night light strength ----
        ColumnLayout {
            id: nightCol
            Layout.fillWidth: true
            Layout.topMargin: 4
            spacing: 4
            property real appear: ccCard.stage >= 8 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            transform: Translate { y: (1 - nightCol.appear) * 16 }

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
    }

    // ---- shared-container transition: the tile that opened a page swells to fill the card (and
    // shrinks back into the tile on the way out), with the page fading in over it ----
    property real fromX: 0
    property real fromY: 0
    property real fromW: 0
    property real fromH: 0
    property real fromR: 0
    property color fromC: Colors.surface_container_highest
    property bool revealOpen: false
    property bool revealSpring: false

    function tileFor(p) {
        return p === "wifi" ? internetTile : p === "bluetooth" ? bluetoothTile : null;
    }
    function syncReveal() {
        const p = cc ? cc.page : "";
        if (p !== "") {
            const t = tileFor(p);
            if (!revealOpen && t) {
                const pt = t.mapToItem(ccCard, 0, 0);
                fromX = pt.x; fromY = pt.y; fromW = t.width; fromH = t.height; fromR = t.radius; fromC = t.color;
                revealHide.stop();
                revealSpring = false;
                reveal.x = fromX; reveal.y = fromY; reveal.width = fromW; reveal.height = fromH;
                reveal.radius = fromR; reveal.color = fromC;
                reveal.opacity = 1;
                revealSpring = true;
            }
            reveal.x = 0; reveal.y = 0; reveal.width = ccCard.width; reveal.height = detailHeight;
            reveal.radius = Motion.shapeExtraLarge; reveal.color = Colors.surface_container;
            revealOpen = true;
        } else if (revealOpen) {
            revealOpen = false;
            reveal.x = fromX; reveal.y = fromY; reveal.width = fromW; reveal.height = fromH;
            reveal.radius = fromR; reveal.color = fromC;
            revealHide.restart();
        }
    }
    Connections {
        target: ccCard.cc
        function onPageChanged() { ccCard.syncReveal(); }
    }
    Timer {
        id: revealHide
        interval: 420
        onTriggered: reveal.opacity = 0
    }
    Rectangle {
        id: reveal
        opacity: 0
        visible: opacity > 0
        Behavior on x { enabled: ccCard.revealSpring; Spring { speed: "default" } }
        Behavior on y { enabled: ccCard.revealSpring; Spring { speed: "default" } }
        Behavior on width { enabled: ccCard.revealSpring; Spring { speed: "default" } }
        Behavior on height { enabled: ccCard.revealSpring; Spring { speed: "default" } }
        Behavior on radius { enabled: ccCard.revealSpring; Spring { speed: "default" } }
        Behavior on color { enabled: ccCard.revealSpring; ColorFade {} }
        Behavior on opacity { Fade { speed: "fast" } }
    }

    // ---- detail pages (each fades / slides in over the card while its page is open) ----
    Loader {
        anchors.fill: parent
        active: !!ccCard.cc
        sourceComponent: NetworkPage {
            cc: ccCard.cc
            shown: ccCard.cc.page === "wifi"
        }
    }
    Loader {
        anchors.fill: parent
        active: !!ccCard.cc
        sourceComponent: BluetoothPage {
            cc: ccCard.cc
            shown: ccCard.cc.page === "bluetooth"
        }
    }
}
