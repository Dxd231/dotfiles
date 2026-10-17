pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Top bar: a full-width floating toolbar (surface-container, full corners, level 3)
// holding XS (32px) items with 4px spacing.
PanelWindow {
    id: bar

    property var player: null
    property var notifications: null
    property var calendarPopup: null
    property var systemStatusPopup: null
    property var volumePopup: null
    property var albumPopup: null
    property var powerMenu: null

    readonly property alias volumeModule: volume
    readonly property alias statsChip: stats
    readonly property alias clockChip: clock

    WlrLayershell.namespace: "quickshell:thebar"
    WlrLayershell.layer: WlrLayer.Top
    anchors { top: true; left: true; right: true }
    implicitHeight: 8 + 48 + 16
    exclusiveZone: 8 + 48
    color: "transparent"
    mask: Region { item: container }

    IdleInhibitor {
        window: bar
        enabled: IdleInhibit.active
    }

    Elevation {
        anchors.fill: container
        radius: container.radius
        level: 3
    }

    Rectangle {
        id: container
        anchors { top: parent.top; left: parent.left; right: parent.right; topMargin: 8; leftMargin: 8; rightMargin: 8 }
        height: 48
        radius: height / 2
        color: Colors.surface_container

        // ---- leading ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            x: 8
            spacing: 4

            BarChip {
                id: notifButton
                readonly property var n: bar.notifications
                implicitWidth: 32
                checked: !!n && n.centerOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (!n)
                        return;
                    if (mouse.button === Qt.RightButton)
                        n.dnd = !n.dnd;
                    else
                        n.toggleCenter();
                }

                Icon {
                    id: bell
                    anchors.centerIn: parent
                    size: 20
                    name: notifButton.n && notifButton.n.dnd ? "notifications_paused" : notifButton.n && notifButton.n.hasNotifications ? "notifications_unread" : "notifications"
                    filled: notifButton.checked
                    color: notifButton.n && notifButton.n.dnd && !notifButton.checked ? Colors.tertiary : notifButton.contentColor
                }
                Badge {
                    visible: !!notifButton.n && notifButton.n.unread > 0 && !notifButton.n.dnd
                    text: notifButton.n ? (notifButton.n.unread > 99 ? "99+" : String(notifButton.n.unread)) : ""
                    x: bell.x + bell.width - 8
                    y: bell.y - 6
                }
            }

            Workspaces {}
        }

        // ---- center ----
        Row {
            anchors.centerIn: parent
            spacing: 4

            MprisModule {
                player: bar.player
                albumPopup: bar.albumPopup
            }
            BarClock {
                id: clock
                popup: bar.calendarPopup
            }
        }

        // ---- trailing ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 8
            spacing: 4
            layoutDirection: Qt.LeftToRight

            // CPU + memory
            BarChip {
                id: stats
                property bool memAbsolute: false
                readonly property int cpuLevel: SystemStats.cpuPercent >= 90 ? 2 : SystemStats.cpuPercent >= 80 ? 1 : 0
                readonly property int memLevel: SystemStats.memPercent >= 90 ? 2 : SystemStats.memPercent >= 80 ? 1 : 0
                checked: !!bar.systemStatusPopup && bar.systemStatusPopup.isOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                implicitWidth: statsRow.implicitWidth + 4 + 12
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton)
                        memAbsolute = !memAbsolute;
                    else if (bar.systemStatusPopup)
                        bar.systemStatusPopup.toggle();
                }

                Row {
                    id: statsRow
                    x: 4
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 8

                    StatBadge { icon: "memory"; level: stats.cpuLevel; tile: Colors.primary_container; glyph: Colors.on_primary_container }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(implicitWidth, 32)
                        role: "labelLarge"
                        color: stats.cpuLevel === 2 ? Colors.error : stats.contentColor
                        text: Math.round(SystemStats.cpuPercent) + "%"
                    }
                    StatBadge { icon: "memory_alt"; level: stats.memLevel; tile: Colors.tertiary_container; glyph: Colors.on_tertiary_container }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.max(implicitWidth, 32)
                        role: "labelLarge"
                        color: stats.memLevel === 2 ? Colors.error : stats.contentColor
                        text: stats.memAbsolute ? SystemStats.gb(SystemStats.memUsedKb) + " GB" : Math.round(SystemStats.memPercent) + "%"
                    }
                }
            }

            VolumeModule {
                id: volume
                popup: bar.volumePopup
            }

            // keep-awake: click cycles 5/15/30/60 min, indefinite, off
            BarChip {
                id: inhibitChip
                checked: IdleInhibit.active
                implicitWidth: IdleInhibit.timed ? inhibitRow.implicitWidth + 24 : 32
                clip: true
                Behavior on implicitWidth { Spring {} }
                onClicked: IdleInhibit.advanceMode()

                Row {
                    id: inhibitRow
                    anchors.verticalCenter: parent.verticalCenter
                    x: IdleInhibit.timed ? 12 : 6
                    spacing: 6
                    Behavior on x { Spring {} }

                    Icon {
                        anchors.verticalCenter: parent.verticalCenter
                        size: 20
                        name: IdleInhibit.active ? "coffee" : "bedtime"
                        filled: IdleInhibit.active
                        color: inhibitChip.contentColor
                    }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        visible: IdleInhibit.timed
                        role: "labelLarge"
                        color: inhibitChip.contentColor
                        text: IdleInhibit.remainingText
                    }
                }
            }

            SystemTrayModule {
                barWindow: bar
            }

            BarChip {
                implicitWidth: 32
                danger: true
                checked: !!bar.powerMenu && bar.powerMenu.menuVisible
                onClicked: if (bar.powerMenu) bar.powerMenu.toggle()
                Icon {
                    anchors.centerIn: parent
                    size: 20
                    name: "power_settings_new"
                    color: parent.contentColor
                }
            }
        }
    }

    // 24px leading badge whose shape follows its chip (circle → rounded square when selected)
    component StatBadge: Rectangle {
        property string icon
        property int level
        property color tile
        property color glyph
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        radius: stats.pressed ? 6 : stats.checked ? Motion.shapeSmall : 12
        color: level === 2 ? Colors.error_container : level === 1 ? Colors.tertiary : tile
        Behavior on radius { Spring {} }
        Behavior on color { ColorFade {} }
        Icon {
            anchors.centerIn: parent
            size: 16
            name: parent.icon
            color: parent.level === 2 ? Colors.on_error_container : parent.level === 1 ? Colors.on_tertiary : parent.glyph
        }
    }
}
