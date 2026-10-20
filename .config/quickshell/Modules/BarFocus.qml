pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// Pomodoro chip, next to the date: a shape badge that follows the phase (focus / short / long break) and
// turns while the timer runs. The countdown slides open beside it while a session is running or paused
// part-way, and shuts again when the timer is idle. Click opens the focus panel.
Clickable {
    id: chip

    property var focusPopup: null

    readonly property bool showTime: Pomodoro.active
    // the label that was showing last, kept while the width springs shut
    property string lastLabel: Pomodoro.label
    onShowTimeChanged: if (showTime)
        lastLabel = Pomodoro.label
    Connections {
        target: Pomodoro
        function onLabelChanged() { if (chip.showTime) chip.lastLabel = Pomodoro.label; }
    }
    readonly property real labelW: showTime ? digits.implicitWidth + 6 : 0

    readonly property var modeShapes: ({ focus: 1, short: 5, long: 2 })
    readonly property color tile: Pomodoro.onBreak ? Colors.tertiary : Colors.primary
    readonly property color onTile: Pomodoro.onBreak ? Colors.on_tertiary : Colors.on_primary

    height: 24
    width: 4 + badge.width + labelW + (showTime ? 6 : 4)
    clip: true
    restRadius: 12
    pressedRadius: 6
    checkedRadius: Motion.shapeSmall
    checked: !!focusPopup && focusPopup.isOpen
    color: checked ? Colors.secondary_container : "transparent"
    contentColor: checked ? Colors.on_secondary_container : Colors.on_surface
    Behavior on width { Spring {} }
    scale: pressed ? 0.93 : hovered ? 1.05 : 1
    Behavior on scale { Spring { speed: "fast" } }
    onClicked: if (focusPopup) focusPopup.toggle()

    ShapeBadge {
        id: badge
        x: 4
        anchors.verticalCenter: parent.verticalCenter
        width: 20
        height: 20
        shapeRest: chip.modeShapes[Pomodoro.mode]
        shapeActive: 4
        active: chip.checked
        property real turn: Pomodoro.running ? 40 : 0
        property real turnNow: turn
        Behavior on turnNow { Spring { speed: "slow" } }
        spinSpeed: Math.max(0, turnNow)
        spinning: turn > 0 || turnNow > 0.5
        color: chip.tile
        Icon {
            anchors.centerIn: parent
            size: 12
            name: "timer"
            color: chip.onTile
        }
    }

    RollingDigits {
        id: digits
        x: 4 + badge.width + 6
        anchors.verticalCenter: parent.verticalCenter
        pixelSize: 14
        weight: Font.Medium
        letterSpacing: 0.1
        color: chip.contentColor
        text: chip.showTime ? Pomodoro.label : chip.lastLabel
        opacity: chip.showTime ? 1 : 0
        Behavior on opacity { Fade {} }
    }
}
