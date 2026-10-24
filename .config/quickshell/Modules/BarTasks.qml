pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// Bar chip for the task panel. It only talks about what is still to do today: one task left takes
// the task's name, several show how many are left, and once they are all ticked it is only the
// badge (the label slides shut). A shape badge leads: it morphs to the
// sunny shape (and spins) while the panel is open or everything is done, and rings when a
// reminder fires.
BarChip {
    id: chip

    property var popup: null
    // right-click menu (today's tasks with a check each)
    property var quickMenu: null

    // what is still to do today; done tasks leave the chip
    readonly property var pending: Tasks.dueToday.filter(t => !Tasks.isDone(t, Tasks.todayKey))
    readonly property bool single: pending.length === 1
    readonly property bool many: pending.length >= 2
    readonly property var only: single ? pending[0] : null
    // the label that was showing last, kept while the width springs shut
    property string lastName: ""
    property bool showName: !many
    onOnlyChanged: if (only) {
        lastName = only.name;
        showName = true;
    }
    onManyChanged: if (many)
        showName = false
    Component.onCompleted: if (only)
        lastName = only.name
    // every task due today is done
    readonly property bool allDone: Tasks.dueCount > 0 && Tasks.pendingCount === 0
    readonly property real labelW: single ? Math.min(nameText.implicitWidth, 110) + 6
        : many ? count.implicitWidth + 8 : 0

    checked: !!popup && popup.isOpen
    implicitWidth: 4 + badge.width + labelW + 4
    clip: true
    Behavior on implicitWidth { Spring {} }
    acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
    // left opens the panel, middle opens it on the next task still to do, right ticks today without
    // opening anything (a single task is ticked outright, several get a small menu)
    onClicked: mouse => {
        if (mouse.button === Qt.RightButton) {
            if (Tasks.count === 1 && Tasks.dueCount === 1)
                Tasks.toggleDone(Tasks.active[0].id, Tasks.todayKey);
            else if (Tasks.count > 0 && quickMenu)
                quickMenu.toggle();
            else if (popup)
                popup.toggle();
        } else if (mouse.button === Qt.MiddleButton) {
            if (popup)
                popup.openPending();
        } else if (popup) {
            popup.toggle();
        }
    }

    // a reminder went off: swing and pop
    Connections {
        target: Tasks
        function onFired() { ring.restart(); }
    }
    ParallelAnimation {
        id: ring
        SequentialAnimation {
            NumberAnimation { target: badge; property: "rotation"; to: 24; duration: 70; easing.type: Easing.OutQuad }
            NumberAnimation { target: badge; property: "rotation"; to: -20; duration: 110; easing.type: Easing.InOutQuad }
            NumberAnimation { target: badge; property: "rotation"; to: 14; duration: 100; easing.type: Easing.InOutQuad }
            NumberAnimation { target: badge; property: "rotation"; to: -8; duration: 90; easing.type: Easing.InOutQuad }
            NumberAnimation { target: badge; property: "rotation"; to: 0; duration: 90; easing.type: Easing.InOutQuad }
        }
        SequentialAnimation {
            NumberAnimation { target: badge; property: "badgeScale"; to: 1.3; duration: 70 }
            PauseAnimation { duration: 260 }
            NumberAnimation { target: badge; property: "badgeScale"; to: 1; duration: 200; easing.type: Easing.OutBack }
        }
    }

    ShapeBadge {
        id: badge
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        shapeRest: chip.only ? Tasks.shapeFor(chip.only) : "cookie9"
        shapeActive: "sunny"
        active: chip.checked || chip.allDone
        spinning: active && chip.visible
        color: chip.allDone ? Colors.tertiary : chip.checked ? Colors.primary : (chip.only ? Tasks.containerFor(chip.only) : Colors.primary_container)

        // the glyph: a checklist, a check once everything is done, or the single task's letter
        Icon {
            anchors.centerIn: parent
            size: 16
            name: chip.allDone ? "check" : "checklist"
            color: chip.allDone ? Colors.on_tertiary : chip.checked ? Colors.on_primary : Colors.on_primary_container
            opacity: chip.single && !chip.allDone ? 0 : 1
            Behavior on opacity { Fade {} }
        }
        Text {
            anchors.centerIn: parent
            text: chip.only && chip.only.name ? chip.only.name.charAt(0).toUpperCase() : ""
            color: chip.checked ? Colors.on_primary : chip.only ? Tasks.onContainerFor(chip.only) : Colors.on_primary_container
            font.family: Typography.family
            font.pixelSize: 13
            font.weight: Font.Bold
            opacity: chip.single && !chip.allDone ? 1 : 0
            Behavior on opacity { Fade {} }
        }
    }

    // one task left: its name; several: how many are left
    Item {
        x: 4 + badge.width
        anchors.verticalCenter: parent.verticalCenter
        width: chip.labelW
        height: 20
        clip: true
        Behavior on width { Spring {} }

        StyledText {
            id: nameText
            x: 6
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(implicitWidth, 110)
            opacity: chip.showName ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            role: "labelLarge"
            elide: Text.ElideRight
            color: chip.contentColor
            text: chip.only ? chip.only.name : chip.lastName
        }
        RollingDigits {
            id: count
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            opacity: chip.showName ? 0 : 1
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            pixelSize: 14
            weight: Font.Bold
            color: chip.contentColor
            text: String(Tasks.pendingCount)
        }
    }
}
