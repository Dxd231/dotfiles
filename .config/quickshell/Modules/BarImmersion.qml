pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// Bar chip for the immersion panel. Just a headphones badge until something has been logged today;
// then today's time rolls in beside it. The badge turns (and morphs to the sunny shape) while mpv
// is playing something that counts, and goes tertiary once the daily goal is met.
BarChip {
    id: chip

    property var popup: null

    readonly property bool live: (Immersion.liveOn && Immersion.liveCounted) || Immersion.readingNow
    readonly property real mins: Immersion.todayMinutes
    readonly property bool shown: mins >= 1
    readonly property bool hours: mins >= 60
    // "42" + m, or "1:05" + h
    readonly property string digits: hours ? Math.floor(mins / 60) + ":" + Immersion.pad(Math.floor(mins % 60)) : String(Math.floor(mins))
    readonly property real labelW: shown ? digitsView.implicitWidth + unit.implicitWidth + 12 : 0

    checked: !!popup && popup.isOpen
    implicitWidth: 4 + badge.width + labelW + 4
    clip: true
    Behavior on implicitWidth { Spring {} }
    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
    // left opens the panel, middle goes straight to logging reading
    onClicked: mouse => {
        if (!popup)
            return;
        if (mouse.button === Qt.MiddleButton)
            popup.openReading();
        else
            popup.toggle();
    }

    ShapeBadge {
        id: badge
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 24
        height: 24
        shapeRest: 5
        shapeActive: 4
        active: chip.checked || chip.live
        // past the goal the badge races
        spinning: (chip.live || Immersion.overdrive) && chip.visible
        spinSpeed: Immersion.overdrive ? 80 : 22
        color: Immersion.goalMet ? Colors.tertiary : chip.checked ? Colors.primary : Colors.primary_container

        Icon {
            anchors.centerIn: parent
            size: 16
            name: Immersion.overdrive ? "bolt" : Immersion.goalMet ? "check" : Immersion.context === "kavita" ? "menu_book" : Immersion.context === "ttu" ? "auto_stories" : "headphones"
            color: Immersion.goalMet ? Colors.on_tertiary : chip.checked ? Colors.on_primary : Colors.on_primary_container
        }
    }

    // today's time
    Item {
        x: 4 + badge.width
        anchors.verticalCenter: parent.verticalCenter
        width: chip.labelW
        height: 20
        clip: true
        Behavior on width { Spring {} }
        opacity: chip.shown ? 1 : 0
        Behavior on opacity { Fade {} }

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
                text: chip.digits
            }
            StyledText {
                id: unit
                anchors.verticalCenter: parent.verticalCenter
                role: "labelLarge"
                color: chip.contentColor
                text: chip.hours ? "" : "m"
            }
        }
    }
}
