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
    property var focusPopup: null
    property var tasksPopup: null
    property var tasksQuickMenu: null
    property var immersionPopup: null
    property var systemStatusPopup: null
    property var volumePopup: null
    property var albumPopup: null
    property var powerMenu: null

    readonly property alias volumeModule: volume
    readonly property alias statsChip: stats
    readonly property alias clockChip: clock
    readonly property alias tasksChip: tasksChip
    readonly property alias immersionChip: immersionChip
    // the time and date parts of the clock anchor different popups
    readonly property Item clockTimeAnchor: clock.timeAnchor
    readonly property Item clockDateAnchor: clock.dateAnchor

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

                // rings and pops its badge when a notification arrives
                readonly property int unreadCount: n ? n.unread : 0
                property int lastUnread: 0
                property real badgePop: 1
                onUnreadCountChanged: {
                    if (unreadCount > lastUnread && n && !n.dnd)
                        ring.restart();
                    lastUnread = unreadCount;
                }
                ParallelAnimation {
                    id: ring
                    SequentialAnimation {
                        NumberAnimation { target: bell; property: "rotation"; to: 22; duration: 70; easing.type: Easing.OutQuad }
                        NumberAnimation { target: bell; property: "rotation"; to: -18; duration: 110; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: bell; property: "rotation"; to: 13; duration: 100; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: bell; property: "rotation"; to: -8; duration: 90; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: bell; property: "rotation"; to: 4; duration: 80; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: bell; property: "rotation"; to: 0; duration: 80; easing.type: Easing.InOutQuad }
                    }
                    SequentialAnimation {
                        NumberAnimation { target: notifButton; property: "badgePop"; to: 0.3; duration: 1 }
                        Spring { target: notifButton; property: "badgePop"; to: 1; speed: "fast" }
                    }
                }

                Icon {
                    id: bell
                    anchors.centerIn: parent
                    transformOrigin: Item.Top
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
                    scale: notifButton.badgePop
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
                calendarPopup: bar.calendarPopup
                focusPopup: bar.focusPopup
            }
            BarTasks {
                id: tasksChip
                anchors.verticalCenter: parent.verticalCenter
                popup: bar.tasksPopup
                quickMenu: bar.tasksQuickMenu
            }
            BarImmersion {
                id: immersionChip
                anchors.verticalCenter: parent.verticalCenter
                popup: bar.immersionPopup
            }
        }

        // ---- trailing ----
        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.right: parent.right
            anchors.rightMargin: 8
            spacing: 4
            layoutDirection: Qt.LeftToRight

            BarRecording {}

            // CPU + memory
            BarChip {
                id: stats
                property bool memAbsolute: false
                readonly property int cpuLevel: SystemStats.cpuPercent >= 90 ? 2 : SystemStats.cpuPercent >= 80 ? 1 : 0
                readonly property int memLevel: SystemStats.memPercent >= 90 ? 2 : SystemStats.memPercent >= 80 ? 1 : 0
                checked: !!bar.systemStatusPopup && bar.systemStatusPopup.isOpen
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                implicitWidth: statsRow.implicitWidth + 4 + 12
                clip: true
                Behavior on implicitWidth { Spring {} }
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

                    StatBadge { icon: "memory"; level: stats.cpuLevel; tile: Colors.primary_container; glyph: Colors.on_primary_container; shapeRest: 5 }
                    PercentText { value: SystemStats.cpuPercent; level: stats.cpuLevel }
                    StatBadge { icon: "memory_alt"; level: stats.memLevel; tile: Colors.tertiary_container; glyph: Colors.on_tertiary_container; shapeRest: 2 }
                    Item {
                        anchors.verticalCenter: parent.verticalCenter
                        width: stats.memAbsolute ? gbText.implicitWidth : memPercent.implicitWidth
                        height: 20
                        Behavior on width { Spring {} }
                        StyledText {
                            id: gbText
                            anchors.verticalCenter: parent.verticalCenter
                            visible: stats.memAbsolute
                            role: "labelLarge"
                            color: stats.memLevel === 2 ? Colors.error : stats.contentColor
                            text: SystemStats.gb(SystemStats.memUsedKb) + " GB"
                        }
                        PercentText {
                            id: memPercent
                            visible: !stats.memAbsolute
                            value: SystemStats.memPercent
                            level: stats.memLevel
                        }
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

            // power: a filled error-tinted shape rather than a bare ring glyph, which read as an outline
            BarChip {
                id: powerChip
                implicitWidth: 32
                danger: true
                checked: !!bar.powerMenu && bar.powerMenu.menuVisible
                onClicked: if (bar.powerMenu) bar.powerMenu.toggle()
                ShapeBadge {
                    anchors.centerIn: parent
                    width: 24
                    height: 24
                    shapeRest: 7
                    shapeActive: 4
                    active: powerChip.hovered || powerChip.checked
                    spinning: powerChip.checked && powerChip.visible
                    color: Colors.error
                    Icon {
                        anchors.centerIn: parent
                        size: 13
                        name: "power_settings_new"
                        color: Colors.on_error
                    }
                }
            }
        }
    }

    // 24px leading badge: a turning shape that morphs to the sunny shape while its chip is selected
    component StatBadge: ShapeBadge {
        id: sb
        property string icon
        property int level
        property color tile
        property color glyph
        anchors.verticalCenter: parent.verticalCenter
        shapeActive: 4
        active: stats.checked
        // turns while the popup is open, and while usage is high (faster the higher it is). The speed eases
        // up and down on a spring, and the frame animation only runs while there is some left to turn
        property real turn: Math.max(stats.checked ? 22 : 0, level === 2 ? 130 : level === 1 ? 60 : 0)
        property real turnNow: turn
        Behavior on turnNow { Spring { speed: "slow" } }
        spinSpeed: Math.max(0, turnNow)
        spinning: turn > 0 || turnNow > 0.5
        badgeScale: stats.pressed ? 0.85 : 1
        color: level === 2 ? Colors.error_container : level === 1 ? Colors.tertiary : tile
        Icon {
            anchors.centerIn: parent
            size: 16
            name: sb.icon
            color: sb.level === 2 ? Colors.on_error_container : sb.level === 1 ? Colors.on_tertiary : sb.glyph
        }
    }

    // a percentage whose digits roll over like the clock's
    component PercentText: Row {
        property real value
        property int level
        anchors.verticalCenter: parent.verticalCenter
        RollingDigits {
            anchors.verticalCenter: parent.verticalCenter
            pixelSize: 14
            weight: Font.Medium
            letterSpacing: 0.1
            color: level === 2 ? Colors.error : stats.contentColor
            text: String(Math.round(value))
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelLarge"
            color: level === 2 ? Colors.error : stats.contentColor
            text: "%"
        }
    }
}
