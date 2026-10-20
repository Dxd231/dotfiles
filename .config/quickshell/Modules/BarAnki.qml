pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// Bar chip for the mining panel: a cards badge and "3/10", the cards mined today against the daily goal.
// The badge turns tertiary (a check) once the goal is met and races past it. While something is being
// watched or read and nothing has been mined for a while, the badge perks up, and until the first card
// of the day the badge morphs slowly through a few shapes. When Anki
// is closed the last known count stays, faded.
BarChip {
    id: chip

    property var popup: null

    // immersing, and no card mined for a quarter of an hour
    readonly property bool nudge: ((Immersion.liveOn && Immersion.liveCounted) || Immersion.readingNow) && !Anki.goalMet && Anki.minutesSinceMined > 15
    readonly property real labelW: digitsView.implicitWidth + unit.implicitWidth + 12

    checked: !!popup && popup.isOpen
    implicitWidth: 2 + badge.width + labelW + 4
    clip: true
    Behavior on implicitWidth { Spring {} }
    opacity: Anki.online || Anki.minedToday > 0 ? 1 : 0.6
    Behavior on opacity { Fade {} }
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    // left opens the panel, middle goes straight to the review screen
    onClicked: mouse => {
        if (mouse.button === Qt.MiddleButton)
            Anki.review();
        else if (popup)
            popup.toggle();
    }

    GoalBadge {
        id: badge
        x: 1
        anchors.verticalCenter: parent.verticalCenter
        ring: false
        // nothing mined yet today
        nudging: Anki.fresh && Anki.minedToday === 0
        shapeRest: 1
        shapeActive: 7
        active: chip.checked || chip.nudge
        spinning: Anki.overGoal && chip.visible
        spinSpeed: 80
        color: Anki.goalMet ? Colors.tertiary : badge.nudging ? Colors.tertiary_container : chip.checked ? Colors.primary : Colors.primary_container

        Icon {
            anchors.centerIn: parent
            size: 16
            name: Anki.overGoal ? "bolt" : Anki.goalMet ? "check" : "style"
            color: Anki.goalMet ? Colors.on_tertiary : badge.nudging ? Colors.on_tertiary_container : chip.checked ? Colors.on_primary : Colors.on_primary_container
        }
    }

    Item {
        x: 2 + badge.width
        anchors.verticalCenter: parent.verticalCenter
        width: chip.labelW
        height: 20
        clip: true

        Row {
            x: 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            RollingDigits {
                id: digitsView
                anchors.verticalCenter: parent.verticalCenter
                pixelSize: 14
                weight: Font.Bold
                color: chip.contentColor
                text: String(Anki.minedToday)
            }
            StyledText {
                id: unit
                anchors.verticalCenter: parent.verticalCenter
                role: "labelLarge"
                color: chip.contentColor
                opacity: 0.7
                text: "/" + Anki.todayGoal
            }
        }
    }
}
