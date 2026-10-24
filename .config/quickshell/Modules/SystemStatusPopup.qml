pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// System status: a hero shape that changes form with the machine's state, two wavy load dials
// (CPU, memory) that ripple harder as load climbs, a one-minute history graph and storage bars.
BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:system_status_popup"
    panelWidth: 440
    spacing: 12

    readonly property real cpu: SystemStats.cpuPercent
    readonly property real mem: SystemStats.memPercent
    readonly property bool cpuHot: SystemStats.cpuTemp >= 80
    readonly property bool cpuWarm: SystemStats.cpuTemp >= 70
    readonly property bool critical: cpuHot || mem >= 90 || cpu >= 90
    readonly property bool busy: critical || cpuWarm || mem >= 80 || cpu >= 80 || SystemStats.swapPercent >= 85
        || SystemStats.disks.some(d => d.percent >= 85)
    readonly property int statusLevel: critical ? 2 : busy ? 1 : 0

    // [container, content, accent] colors for a severity: 0 normal, 1 warning, 2 critical
    function severity(level, normal) {
        return level >= 2 ? [Colors.error_container, Colors.on_error_container, Colors.error]
             : level === 1 ? [Colors.tertiary_container, Colors.on_tertiary_container, Colors.tertiary]
             : normal;
    }
    function levelOf(percent) {
        return percent >= 90 ? 2 : percent >= 80 ? 1 : 0;
    }
    function uptimeText(sec) {
        const d = Math.floor(sec / 86400), h = Math.floor(sec % 86400 / 3600), m = Math.floor(sec % 3600 / 60);
        return (d ? d + "d " : "") + (d || h ? h + "h " : "") + m + "m";
    }

    // ---- hero: its shape follows the status (calm cookie, sunny when busy, burst when critical) ----
    readonly property var statusShapes: ["cookie4", "flower", "boom"]
    property var heroShape: statusShapes[statusLevel]
    property var heroFrom: heroShape
    property real heroMorph: 1
    property bool heroSpring: true
    property real spin: 0
    onStatusLevelChanged: {
        heroFrom = heroShape;
        heroShape = statusShapes[statusLevel];
        heroSpring = false;
        heroMorph = 0;
        heroSpring = true;
        heroMorph = 1;
    }
    Behavior on heroMorph {
        enabled: win.heroSpring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }
    FrameAnimation {
        running: win.isOpen
        onTriggered: win.spin = (win.spin + frameTime * 14) % 360
    }

    // ---- entrance: the pieces pop in one after another ----
    property int stage: 0
    onIsOpenChanged: {
        SystemStats.detailUsers += isOpen ? 1 : -1;
        stage = 0;
        if (isOpen)
            stageTimer.restart();
    }
    Timer {
        id: stageTimer
        interval: 85
        repeat: true
        onTriggered: {
            win.stage += 1;
            if (win.stage >= 5)
                stop();
        }
    }

    IpcHandler {
        target: "systemstatus"
        function toggle(): void { win.toggle(); }
        function show(): void { win.show(); }
        function open(): void { win.show(); }
        function hide(): void { win.hide(); }
        function close(): void { win.hide(); }
    }

    // ---- header ----
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 16
        opacity: win.stage >= 1 ? 1 : 0
        Behavior on opacity { Fade { speed: "default" } }

        Item {
            implicitWidth: 68
            implicitHeight: 68
            scale: win.stage >= 1 ? 1 : 0.5
            Behavior on scale { Spring { speed: "default" } }
            MorphShape {
                anchors.fill: parent
                shape: win.heroShape
                fromShape: win.heroFrom
                morph: win.heroMorph
                spin: win.spin
                color: win.statusLevel === 2 ? Colors.error_container : win.statusLevel === 1 ? Colors.tertiary_container : Colors.primary_container
            }
            Icon {
                anchors.centerIn: parent
                name: "monitor_heart"
                size: 30
                color: win.statusLevel === 2 ? Colors.on_error_container : win.statusLevel === 1 ? Colors.on_tertiary_container : Colors.on_primary_container
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { role: "headlineSmall"; emphasized: true; text: "System status" }
            StyledText {
                Layout.fillWidth: true
                role: "bodyMedium"
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                text: SystemStats.cpuModel + (SystemStats.uptimeSec > 0 ? " · up " + win.uptimeText(SystemStats.uptimeSec) : "")
            }
        }

        // pops whenever the state changes
        Rectangle {
            id: statusPill
            property bool popSpring: true
            readonly property var c: win.statusLevel === 2 ? win.severity(2) : win.statusLevel === 1 ? win.severity(1) : [Colors.secondary_container, Colors.on_secondary_container]
            implicitHeight: 36
            implicitWidth: statusLabel.implicitWidth + 28
            radius: height / 2
            color: c[0]
            Behavior on color { ColorFade {} }
            Behavior on scale {
                enabled: statusPill.popSpring
                Spring { speed: "fast" }
            }
            StyledText {
                id: statusLabel
                anchors.centerIn: parent
                role: "labelLarge"
                emphasized: true
                color: statusPill.c[1]
                text: win.critical ? "Critical" : win.busy ? "High load" : "Optimal"
                onTextChanged: {
                    statusPill.popSpring = false;
                    statusPill.scale = 0.55;
                    statusPill.popSpring = true;
                    statusPill.scale = 1;
                }
            }
        }
    }

    // ---- load dials ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 12

        MetricDial {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            opacity: win.stage >= 2 ? 1 : 0
            scale: win.stage >= 2 ? 1 : 0.85
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            severityColors: win.severity
            waving: win.isOpen
            icon: "memory"
            badgeShape: "cookie4"
            title: "Processor"
            subtitle: SystemStats.cpuFreqMhz > 0 ? (SystemStats.cpuFreqMhz / 1000).toFixed(2) + " GHz average" : "CPU load"
            percent: win.cpu
            level: win.levelOf(win.cpu)
            details: [
                ["Temp", SystemStats.cpuTemp > 0 ? Math.round(SystemStats.cpuTemp) + " °C" : "—", win.cpuHot ? 2 : win.cpuWarm ? 1 : 0],
                ["Power", SystemStats.cpuPowerW >= 0 ? SystemStats.cpuPowerW.toFixed(1) + " W" : "—", 0]
            ]
        }
        MetricDial {
            Layout.preferredWidth: 1
            Layout.fillHeight: true
            opacity: win.stage >= 3 ? 1 : 0
            scale: win.stage >= 3 ? 1 : 0.85
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            severityColors: win.severity
            waving: win.isOpen
            icon: "memory_alt"
            badgeShape: "pentagon"
            title: "Memory"
            subtitle: SystemStats.gb(SystemStats.memUsedKb) + " of " + SystemStats.gb(SystemStats.memTotalKb) + " GB"
            percent: win.mem
            level: win.levelOf(win.mem)
            details: [
                ["Free", SystemStats.gb(SystemStats.memAvailKb) + " GB", 0],
                ["Cache", SystemStats.gb(SystemStats.memCacheKb) + " GB", 0],
                ["Swap", SystemStats.gb(SystemStats.swapUsedKb) + " GB", SystemStats.swapPercent >= 85 ? 1 : 0]
            ]
        }
    }

    // ---- last minute ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: histCol.implicitHeight + 32
        radius: Motion.shapeLarge
        color: Colors.surface_container_highest
        opacity: win.stage >= 4 ? 1 : 0
        scale: win.stage >= 4 ? 1 : 0.9
        Behavior on opacity { Fade { speed: "default" } }
        Behavior on scale { Spring { speed: "default" } }

        ColumnLayout {
            id: histCol
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12
                StyledText { Layout.fillWidth: true; role: "titleMedium"; emphasized: true; text: "Last minute" }
                Row {
                    spacing: 6
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Colors.primary }
                    StyledText { role: "labelMedium"; color: Colors.on_surface_variant; text: "CPU" }
                }
                Row {
                    spacing: 6
                    Rectangle { anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 5; color: Colors.tertiary }
                    StyledText { role: "labelMedium"; color: Colors.on_surface_variant; text: "Memory" }
                }
            }
            Sparkline {
                Layout.fillWidth: true
                Layout.preferredHeight: 84
                series: SystemStats.cpuHistory
                series2: SystemStats.memHistory
                count: SystemStats.historyLength
            }
        }
    }

    // ---- storage ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: diskCol.implicitHeight + 32
        radius: Motion.shapeLarge
        color: Colors.surface_container_highest
        opacity: win.stage >= 5 ? 1 : 0
        scale: win.stage >= 5 ? 1 : 0.9
        Behavior on opacity { Fade { speed: "default" } }
        Behavior on scale { Spring { speed: "default" } }

        ColumnLayout {
            id: diskCol
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 14

            RowLayout {
                spacing: 12
                Item {
                    implicitWidth: 44
                    implicitHeight: 44
                    MorphShape {
                        anchors.fill: parent
                        shape: "sunny"
                        fromShape: "sunny"
                        spin: -win.spin
                        color: Colors.tertiary_container
                    }
                    Icon { anchors.centerIn: parent; name: "hard_drive"; size: 22; color: Colors.on_tertiary_container }
                }
                StyledText { Layout.fillWidth: true; role: "titleMedium"; emphasized: true; text: "Storage" }
            }

            Repeater {
                model: SystemStats.disks
                delegate: ColumnLayout {
                    id: disk
                    required property var modelData
                    readonly property int level: win.levelOf(modelData.percent)
                    Layout.fillWidth: true
                    spacing: 6

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            role: "labelLarge"
                            emphasized: true
                            text: disk.modelData.mount === "/" ? "System" : disk.modelData.mount === "/home" ? "Home" : disk.modelData.mount.split("/").pop()
                        }
                        StyledText {
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            text: SystemStats.gb(disk.modelData.availKb) + " GB free of " + SystemStats.gb(disk.modelData.sizeKb)
                        }
                    }
                    LinearProgress {
                        Layout.fillWidth: true
                        thickness: 14
                        value: disk.modelData.percent / 100
                        activeColor: disk.level ? win.severity(disk.level)[2] : Colors.primary
                    }
                }
            }
        }
    }
}
