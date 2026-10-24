pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// Bar chip for the immersion panel: a badge, a title for the
// media being followed (the pinned source, else the one you are in: Anime, Book or Manga; the work's
// own name while it is live), and today's time.
//
// Nudges, none of them loud: until something is logged today the badge morphs slowly through a few
// shapes; in the evening (when a task streak would be nudged too) with a streak on the line and the goal
// not met, it turns red and counts the minutes still needed. The badge turns tertiary once the goal is
// met and races past it. Scrolling the chip changes the pin: auto, Anime, Book, Manga.
BarChip {
    id: chip

    property var popup: null

    readonly property bool live: (Immersion.liveOn && Immersion.liveCounted) || Immersion.readingNow
    readonly property real mins: Immersion.todayMinutes

    // ---- title ----
    readonly property string kind: Immersion.pane !== "" ? Immersion.pane : Immersion.context
    readonly property string typeLabel: kind === "mpv" ? "Anime" : kind === "ttu" ? "Book" : kind === "kavita" ? "Manga" : ""
    // the work itself, only while that source is live
    readonly property string liveTitle: {
        if (kind === "mpv")
            return Immersion.liveOn && Immersion.liveCounted && Immersion.liveInfo ? Immersion.liveInfo.name : "";
        if (kind === "ttu")
            return Immersion.ttuNow ? Immersion.ttuTitle : "";
        if (kind === "kavita")
            return Immersion.kavitaNow ? Immersion.kavitaWork : "";
        return "";
    }
    readonly property string title: liveTitle !== "" ? liveTitle : typeLabel
    readonly property bool pinned: Immersion.pane !== ""
    readonly property real titleW: title === "" ? 0 : Math.min(140, probe.implicitWidth)
    readonly property real titleBlockW: title === "" ? 0 : (pinned ? 16 : 0) + titleW + 8

    // ---- nudges ----
    property bool ready: false
    Timer {
        interval: 4000
        running: true
        onTriggered: chip.ready = true
    }
    property int nowMin: new Date().getHours() * 60 + new Date().getMinutes()
    Timer {
        interval: 30000
        repeat: true
        running: true
        onTriggered: chip.nowMin = new Date().getHours() * 60 + new Date().getMinutes()
    }
    // a streak is on the line: it is evening and the goal isn't met yet
    readonly property bool atRisk: ready && Immersion.streak > 0 && !Immersion.goalMet && !DayMarks.isMarked(Tasks.todayKey) && nowMin >= Tasks.nudgeMinute
    readonly property bool nudge: ready && !atRisk && !live && mins < 1

    // ---- time ----
    readonly property real shownMins: atRisk ? Math.max(0, Math.ceil(Immersion.todayGoal - mins)) : mins
    readonly property bool hours: shownMins >= 60
    // "42" + m, or "1:05" + h; "-18" + m when a streak needs the minutes
    readonly property string digits: (atRisk ? "-" : "") + (hours ? Math.floor(shownMins / 60) + ":" + Immersion.pad(Math.floor(shownMins % 60)) : String(Math.floor(shownMins)))
    readonly property real labelW: digitsView.implicitWidth + unit.implicitWidth + 12

    checked: !!popup && popup.isOpen
    implicitWidth: 2 + badge.width + titleBlockW + labelW + 4
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

    // scrolling steps the pin through auto, Anime, Book and Manga
    wheelEnabled: true
    property real wheelSum: 0
    onScrolled: w => {
        wheelSum += w.angleDelta.y;
        if (Math.abs(wheelSum) < 120)
            return;
        const dir = wheelSum > 0 ? -1 : 1;
        wheelSum = 0;
        const order = ["", "mpv", "ttu", "kavita"];
        const at = Math.max(0, order.indexOf(Immersion.pane));
        Immersion.setPane(order[(at + dir + order.length) % order.length]);
        badge.badgeScale = 1.18;
        kickReset.restart();
    }
    Timer {
        id: kickReset
        interval: 140
        onTriggered: badge.badgeScale = 1
    }

    GoalBadge {
        id: badge
        x: 1
        anchors.verticalCenter: parent.verticalCenter
        ring: false
        nudging: chip.nudge
        shapeRest: "cookie4"
        shapeActive: Immersion.overdrive ? "softBurst" : Immersion.goalMet ? "flower" : "sunny"
        active: chip.checked || chip.live
        // past the goal the badge races
        spinning: (chip.live || Immersion.overdrive) && chip.visible
        spinSpeed: Immersion.overdrive ? 80 : 22
        color: chip.atRisk ? Colors.error_container : Immersion.goalMet ? Colors.tertiary : chip.nudge ? Colors.tertiary_container : chip.checked ? Colors.primary : Colors.primary_container

        Icon {
            anchors.centerIn: parent
            size: 16
            name: chip.atRisk ? "hourglass_bottom" : Immersion.overdrive ? "bolt" : Immersion.goalMet ? "check" : chip.kind === "kavita" ? "menu_book" : chip.kind === "ttu" ? "auto_stories" : "headphones"
            color: chip.atRisk ? Colors.on_error_container : Immersion.goalMet ? Colors.on_tertiary : chip.nudge ? Colors.on_tertiary_container : chip.checked ? Colors.on_primary : Colors.on_primary_container
        }
    }

    // ---- title: pin glyph and the media type, or the work while it is live ----
    StyledText {
        id: probe
        visible: false
        jp: true
        role: "labelLarge"
        emphasized: true
        text: chip.title
    }
    Item {
        x: 2 + badge.width + 4
        anchors.verticalCenter: parent.verticalCenter
        property real _w: chip.titleBlockW
        Behavior on _w { Spring {} }
        width: Math.max(0, _w)
        height: 20
        clip: true
        opacity: chip.title !== "" ? 1 : 0
        Behavior on opacity { Fade {} }

        Icon {
            id: pin
            opacity: chip.pinned ? 0.7 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            name: "keep"
            color: chip.contentColor
        }
        Marquee {
            x: chip.pinned ? 16 : 0
            Behavior on x { Spring {} }
            anchors.verticalCenter: parent.verticalCenter
            width: chip.titleW
            centered: false
            jp: true
            role: "labelLarge"
            emphasized: true
            color: chip.contentColor
            running: chip.visible && chip.title !== ""
            text: chip.title
        }
    }

    // ---- today's time ----
    Item {
        x: 2 + badge.width + chip.titleBlockW
        anchors.verticalCenter: parent.verticalCenter
        width: chip.labelW
        height: 20
        clip: true
        Behavior on x { Spring {} }

        Row {
            x: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 1
            RollingDigits {
                id: digitsView
                anchors.verticalCenter: parent.verticalCenter
                pixelSize: 14
                weight: Font.Bold
                color: chip.atRisk ? Colors.error : chip.contentColor
                text: chip.digits
            }
            StyledText {
                id: unit
                anchors.verticalCenter: parent.verticalCenter
                role: "labelLarge"
                color: chip.atRisk ? Colors.error : chip.contentColor
                text: chip.hours ? "" : "m"
            }
        }
    }
}
