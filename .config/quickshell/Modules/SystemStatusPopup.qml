pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:system_status_popup"
    panelWidth: 400

    readonly property real cpu: SystemStats.cpuPercent
    readonly property real mem: SystemStats.memPercent
    readonly property bool cpuHot: SystemStats.cpuTemp >= 80
    readonly property bool cpuWarm: SystemStats.cpuTemp >= 70
    readonly property bool critical: cpuHot || mem >= 90 || cpu >= 90
    readonly property bool busy: critical || cpuWarm || mem >= 80 || cpu >= 80 || SystemStats.swapPercent >= 85
        || SystemStats.disks.some(d => d.percent >= 85)

    // [container, content] colors for a severity: 0 normal, 1 warning, 2 critical
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

    onIsOpenChanged: SystemStats.detailUsers += isOpen ? 1 : -1

    IpcHandler {
        target: "systemstatus"
        function toggle(): void { win.toggle(); }
        function show(): void { win.show(); }
        function open(): void { win.show(); }
        function hide(): void { win.hide(); }
        function close(): void { win.hide(); }
    }

    // Header
    RowLayout {
        Layout.fillWidth: true
        Layout.bottomMargin: 4
        spacing: 16

        Rectangle {
            implicitWidth: 48
            implicitHeight: 48
            radius: Motion.shapeLarge
            color: Colors.primary_container
            Icon { anchors.centerIn: parent; name: "monitor_heart"; color: Colors.on_primary_container }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { role: "titleLarge"; text: "System status" }
            StyledText {
                Layout.fillWidth: true
                role: "bodyMedium"
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                text: SystemStats.cpuModel + (SystemStats.uptimeSec > 0 ? " · up " + win.uptimeText(SystemStats.uptimeSec) : "")
            }
        }

        Rectangle {
            readonly property var c: win.critical ? win.severity(2) : win.busy ? win.severity(1) : [Colors.secondary_container, Colors.on_secondary_container]
            implicitHeight: 32
            implicitWidth: statusLabel.implicitWidth + 24
            radius: Motion.shapeSmall
            color: c[0]
            Behavior on color { ColorFade {} }
            StyledText {
                id: statusLabel
                anchors.centerIn: parent
                role: "labelLarge"
                color: parent.c[1]
                text: win.critical ? "Critical" : win.busy ? "High load" : "Optimal"
            }
        }
    }

    MetricCard {
        severityColors: win.severity
        icon: "memory"
        title: "Processor"
        subtitle: SystemStats.cpuFreqMhz > 0 ? (SystemStats.cpuFreqMhz / 1000).toFixed(2) + " GHz average clock" : "CPU load"
        percent: win.cpu
        level: win.levelOf(win.cpu)
        details: [
            ["Temperature", SystemStats.cpuTemp > 0 ? Math.round(SystemStats.cpuTemp) + " °C" : "—", win.cpuHot ? 2 : win.cpuWarm ? 1 : 0],
            ["Package power", SystemStats.cpuPowerW >= 0 ? SystemStats.cpuPowerW.toFixed(1) + " W" : "—", 0],
            ["Clock", SystemStats.cpuFreqMhz > 0 ? (SystemStats.cpuFreqMhz / 1000).toFixed(2) + " GHz" : "—", 0]
        ]
    }

    MetricCard {
        severityColors: win.severity
        icon: "memory_alt"
        title: "Memory"
        subtitle: SystemStats.gb(SystemStats.memUsedKb) + " of " + SystemStats.gb(SystemStats.memTotalKb) + " GB in use"
        percent: win.mem
        level: win.levelOf(win.mem)
        details: [
            ["Available", SystemStats.gb(SystemStats.memAvailKb) + " GB", 0],
            ["Cache", SystemStats.gb(SystemStats.memCacheKb) + " GB", 0],
            ["Swap", SystemStats.gb(SystemStats.swapUsedKb) + " GB", SystemStats.swapPercent >= 85 ? 1 : 0]
        ]
    }

    // Storage
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: diskCol.implicitHeight + 32
        radius: Motion.shapeMedium
        color: Colors.surface_container_highest

        ColumnLayout {
            id: diskCol
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            RowLayout {
                spacing: 16
                Rectangle {
                    implicitWidth: 40
                    implicitHeight: 40
                    radius: Motion.shapeMedium
                    color: Colors.tertiary_container
                    Icon { anchors.centerIn: parent; name: "hard_drive"; color: Colors.on_tertiary_container }
                }
                StyledText { Layout.fillWidth: true; role: "titleMedium"; text: "Storage" }
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
                        thickness: 8
                        value: disk.modelData.percent / 100
                        activeColor: disk.level ? win.severity(disk.level)[2] : Colors.primary
                    }
                }
            }
        }
    }
}
