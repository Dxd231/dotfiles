pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Focus timer panel: a row showing the current phase (it can't be clicked, breaks are earned by
// finishing a focus session), a wavy progress dial with the countdown, and play / reset / skip
// controls (skip only ends a break). The timer itself lives in the Pomodoro singleton.
BarPopup {
    id: win

    // same layer namespace as the calendar so Hyprland's existing layer rule styles it too
    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 340
    spacing: 20

    readonly property color accent: Pomodoro.onBreak ? Colors.tertiary : Colors.primary
    readonly property color onAccent: Pomodoro.onBreak ? Colors.on_tertiary : Colors.on_primary
    readonly property color accentContainer: Pomodoro.onBreak ? Colors.tertiary_container : Colors.primary_container
    readonly property color onAccentContainer: Pomodoro.onBreak ? Colors.on_tertiary_container : Colors.on_primary_container

    // ---- entrance: sections rise in one after another each time the panel opens ----
    property int stage: 0
    onIsOpenChanged: {
        if (isOpen)
            stageTimer.restart();
        else {
            stageTimer.stop();
            stage = 0;
        }
    }
    Timer {
        id: stageTimer
        interval: 70
        repeat: true
        onTriggered: {
            if (win.stage < 6)
                win.stage++;
            else
                stop();
        }
    }

    // ---- dial shape: every mode has its own, and it morphs (with overshoot) when the mode changes ----
    readonly property var modeShapes: ({ focus: 1, short: 5, long: 2 })
    property int dialFrom: 1
    property int dialTo: 1
    property real dialMorph: 1
    property bool dialSpring: true
    property int dialTurns: 0
    property real dialSpin: 0
    // springs kicked by events (mode change, start / pause) and the slow swell while running
    property real kick: 0
    property real breath: 0
    property real runF: Pomodoro.running ? 1 : 0
    Behavior on dialMorph {
        enabled: win.dialSpring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }
    Behavior on kick { Spring { speed: "fast" } }
    Behavior on runF { Spring { speed: "default" } }

    Component.onCompleted: {
        dialTo = modeShapes[Pomodoro.mode];
        dialFrom = dialTo;
    }
    Connections {
        target: Pomodoro
        function onModeChanged() {
            win.dialFrom = win.dialTo;
            win.dialTo = win.modeShapes[Pomodoro.mode];
            win.dialTurns += 1;
            win.dialSpring = false;
            win.dialMorph = 0;
            win.dialSpring = true;
            win.dialMorph = 1;
            win.pulse();
        }
        function onRunningChanged() {
            win.pulse();
            win.playSpring = false;
            win.playRot = -90;
            win.playScale = 0.4;
            win.playSpring = true;
            win.playRot = 0;
            win.playScale = 1;
        }
    }
    function pulse() {
        kick = 1;
        kickBack.restart();
    }
    Timer {
        id: kickBack
        interval: 110
        onTriggered: win.kick = 0
    }
    FrameAnimation {
        running: Pomodoro.running && win.isOpen
        onTriggered: win.dialSpin = (win.dialSpin + frameTime * 14) % 360
    }
    SequentialAnimation {
        running: Pomodoro.running && win.isOpen
        loops: Animation.Infinite
        NumberAnimation { target: win; property: "breath"; to: 1; duration: 1800; easing.type: Easing.InOutSine }
        NumberAnimation { target: win; property: "breath"; to: 0; duration: 1800; easing.type: Easing.InOutSine }
    }

    // play / pause glyph: turns and pops in on every toggle
    property real playRot: 0
    property real playScale: 1
    property bool playSpring: true
    Behavior on playRot { enabled: win.playSpring; Spring { speed: "default" } }
    Behavior on playScale { enabled: win.playSpring; Spring { speed: "default" } }

    IpcHandler {
        target: "focus"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
        function start(): void { Pomodoro.start(); }
        function pause(): void { Pomodoro.pause(); }
        function toggleTimer(): void { Pomodoro.toggle(); }
        function skip(): void { Pomodoro.skip(); }
        function reset(): void { Pomodoro.reset(); }
    }

    Shortcut {
        sequence: "Space"
        enabled: win.isOpen
        onActivated: Pomodoro.toggle()
    }

    // ---- mode ----
    Row {
        id: modeRow
        Layout.alignment: Qt.AlignHCenter
        Layout.topMargin: 4
        spacing: 2
        property real appear: win.stage >= 1 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.9 + 0.1 * appear
        transform: Translate { y: (1 - modeRow.appear) * 14 }

        Repeater {
            model: [
                { mode: "focus", text: "Focus", position: "first" },
                { mode: "short", text: "Short break", position: "middle" },
                { mode: "long", text: "Long break", position: "last" }
            ]
            // a segment pops when it becomes the selected one
            delegate: ConnectedButton {
                id: mb
                required property var modelData
                property real pop: 0
                position: modelData.position
                text: modelData.text
                selected: Pomodoro.mode === modelData.mode
                scale: (pressed ? 0.94 : 1) + 0.07 * pop
                Behavior on scale { Spring { speed: "fast" } }
                onSelectedChanged: if (selected) {
                    pop = 1;
                    modePopBack.restart();
                }
                Timer {
                    id: modePopBack
                    interval: 110
                    onTriggered: mb.pop = 0
                }
                enabled: false
            }
        }
    }

    // ---- dial ----
    Item {
        id: dial
        Layout.alignment: Qt.AlignHCenter
        implicitWidth: 232
        implicitHeight: 232
        property real appear: win.stage >= 2 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.75 + 0.25 * appear

        WavyRing {
            anchors.fill: parent
            value: Pomodoro.fraction
            waving: Pomodoro.running && win.isOpen
            activeColor: win.accent
        }
        // the mode's shape sits inside the ring: it turns and swells while running, and
        // springs to the next shape when the mode changes
        Item {
            anchors.centerIn: parent
            width: 178
            height: 178
            scale: 1 + 0.03 * win.breath * win.runF + 0.1 * win.kick
            MorphShape {
                anchors.fill: parent
                shape: win.dialTo
                fromShape: win.dialFrom
                morph: win.dialMorph
                spin: win.dialSpin + win.dialTurns * 90
                color: win.accentContainer
                Behavior on color { ColorFade {} }
            }
        }
        Column {
            anchors.centerIn: parent
            spacing: 0
            RollingDigits {
                anchors.horizontalCenter: parent.horizontalCenter
                pixelSize: Typography.size("displayMedium")
                text: Pomodoro.label
                color: win.onAccentContainer
                Behavior on color { ColorFade {} }
            }
            StyledText {
                anchors.horizontalCenter: parent.horizontalCenter
                role: "titleSmall"
                emphasized: true
                color: win.onAccentContainer
                text: Pomodoro.modeLabel
                Behavior on color { ColorFade {} }
            }
        }
    }

    // ---- controls ----
    RowLayout {
        Layout.alignment: Qt.AlignHCenter
        spacing: 8

        IconButton {
            id: resetBtn
            icon: "replay"
            style: "tonal"
            size: "m"
            property real appear: win.stage >= 3 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            scale: (0.5 + 0.5 * appear) * (pressed ? 0.92 : 1)
            Behavior on scale { Spring { speed: "fast" } }
            onClicked: Pomodoro.reset()
        }
        // pill while paused, squarer while running (checkable shape morph)
        IconButton {
            id: playBtn
            size: "l"
            widthMode: "wide"
            style: "filled"
            checkable: true
            checked: Pomodoro.running
            icon: Pomodoro.running ? "pause" : "play_arrow"
            iconSize: 40
            iconRotation: win.playRot
            iconScale: win.playScale
            color: win.accent
            contentColor: win.onAccent
            property real appear: win.stage >= 3 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            scale: (0.5 + 0.5 * appear) * (pressed ? 0.95 : 1)
            Behavior on scale { Spring { speed: "fast" } }
            onClicked: Pomodoro.toggle()
        }
        IconButton {
            id: skipBtn
            icon: "skip_next"
            style: "tonal"
            size: "m"
            property real appear: win.stage >= 4 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            scale: (0.5 + 0.5 * appear) * (pressed ? 0.92 : 1)
            Behavior on scale { Spring { speed: "fast" } }
            enabled: Pomodoro.onBreak
            onClicked: Pomodoro.skip()
        }
    }

    // ---- session dots ----
    RowLayout {
        id: dotsRow
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: 4
        spacing: 12
        property real appear: win.stage >= 5 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        transform: Translate { y: (1 - dotsRow.appear) * 10 }

        Row {
            spacing: 6
            Repeater {
                model: Pomodoro.longBreakEvery
                delegate: Rectangle {
                    id: dot
                    required property int index
                    readonly property bool done: index < Pomodoro.doneInSet
                    readonly property bool current: Pomodoro.mode === "focus" && index === Pomodoro.doneInSet
                    // a finished session's dot pops
                    property real pop: 0
                    onDoneChanged: if (done) {
                        pop = 1;
                        popBack.restart();
                    }
                    Timer {
                        id: popBack
                        interval: 120
                        onTriggered: dot.pop = 0
                    }
                    anchors.verticalCenter: parent.verticalCenter
                    width: current ? 24 : 10
                    height: 10
                    radius: 5
                    scale: 1 + 0.7 * pop + (current ? 0.12 * win.breath * win.runF : 0)
                    color: done || current ? win.accent : Colors.secondary_container
                    opacity: done || current ? 1 : 0.8
                    Behavior on width { Spring {} }
                    Behavior on scale { Spring { speed: "fast" } }
                    Behavior on color { ColorFade {} }
                }
            }
        }
        StyledText {
            role: "labelLarge"
            color: Colors.on_surface_variant
            text: Pomodoro.mode === "long" ? "Set complete" : "Session " + (Pomodoro.doneInSet + 1) + " of " + Pomodoro.longBreakEvery
        }
    }

    // ---- linked task: a full cycle of focus sessions counts for it ----
    Chip {
        id: linkChip
        readonly property var linked: Tasks.byId(Pomodoro.taskId)
        Layout.alignment: Qt.AlignHCenter
        Layout.bottomMargin: 4
        visible: Tasks.focusable.length > 0
        kind: "filter"
        icon: "checklist"
        text: linked ? "Counts for " + linked.name : "Link a task"
        selected: !!linked
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        property real appear: win.stage >= 6 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: (0.8 + 0.2 * appear) * (pressed ? 0.95 : 1)
        Behavior on scale { Spring { speed: "fast" } }
        // click steps through the active tasks and back to none; right-click unlinks
        onClicked: mouse => {
            const ids = [""].concat(Tasks.focusable.map(t => t.id));
            if (mouse.button === Qt.RightButton)
                Pomodoro.setTask("");
            else
                Pomodoro.setTask(ids[(ids.indexOf(Pomodoro.taskId) + 1) % ids.length]);
        }
    }
}
