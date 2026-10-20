pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Quick alarm panel, opened from the time pill: a big readout (the countdown, or "No alarm"), one-tap
// countdown presets, and a time of day to ring at. One alarm at a time (the Alarm singleton). While it
// rings the setters give way to Stop / Snooze.
BarPopup {
    id: win

    // same layer namespace as the calendar so Hyprland's existing layer rule styles it too
    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 340
    spacing: 16

    // time of day being picked
    property int pickHour: 7
    property int pickMinute: 0

    onIsOpenChanged: if (isOpen) {
        const n = new Date();
        pickHour = (n.getHours() + 1) % 24;
        pickMinute = 0;
    }

    readonly property color accent: Alarm.ringing ? Colors.error : Colors.primary
    readonly property color onAccent: Alarm.ringing ? Colors.on_error : Colors.on_primary
    readonly property color accentContainer: Alarm.ringing ? Colors.error_container : Colors.primary_container
    readonly property color onAccentContainer: Alarm.ringing ? Colors.on_error_container : Colors.on_primary_container

    IpcHandler {
        target: "alarm"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
        function inMinutes(minutes: int): void { Alarm.setIn(minutes); }
        function at(time: string): void { Alarm.setAt(time); }
        function stop(): void { Alarm.stop(); }
        function cancel(): void { Alarm.cancel(); }
    }

    // ---- readout ----
    Item {
        id: head
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 96

        Appear { shown: win.isOpen }

        ShapeBadge {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 80
            height: 80
            shapeRest: 1
            shapeActive: 4
            active: Alarm.active || Alarm.ringing
            spinning: Alarm.active || Alarm.ringing
            spinSpeed: Alarm.ringing ? 90 : 14
            color: win.accentContainer
            // shakes while it rings
            SequentialAnimation on rotation {
                running: Alarm.ringing && win.isOpen
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 10; duration: 80; easing.type: Easing.InOutQuad }
                NumberAnimation { to: -10; duration: 160; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0; duration: 80; easing.type: Easing.InOutQuad }
                PauseAnimation { duration: 500 }
            }
            Icon {
                anchors.centerIn: parent
                size: 36
                name: "alarm"
                color: win.onAccentContainer
            }
        }

        Column {
            anchors.left: badge.right
            anchors.leftMargin: 20
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2

            RollingDigits {
                visible: Alarm.active
                pixelSize: Typography.size("displaySmall")
                text: Alarm.label
                color: Colors.on_surface
            }
            StyledText {
                visible: !Alarm.active
                role: "displaySmall"
                emphasized: true
                color: Alarm.ringing ? Colors.error : Colors.on_surface_variant
                text: Alarm.ringing ? "Time's up" : "No alarm"
            }
            StyledText {
                role: "titleSmall"
                emphasized: true
                color: Colors.on_surface_variant
                text: Alarm.ringing ? (Alarm.kind === "clock" ? "Set for " + Alarm.atLabel : "Timer finished")
                    : Alarm.active ? "Rings at " + Alarm.atLabel : "Pick a time below"
            }
        }
    }

    // ---- ringing: stop / snooze ----
    RowLayout {
        visible: Alarm.ringing
        Layout.fillWidth: true
        spacing: 8
        Button {
            Layout.fillWidth: true
            size: "m"
            text: "Stop"
            icon: "close"
            color: Colors.error
            contentColor: Colors.on_error
            onClicked: Alarm.stop()
        }
        Button {
            Layout.fillWidth: true
            size: "m"
            style: "tonal"
            text: "+5 min"
            icon: "timer"
            onClicked: Alarm.snooze(5)
        }
    }

    // ---- countdown presets ----
    ColumnLayout {
        visible: !Alarm.ringing
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            role: "labelLarge"
            color: Colors.on_surface_variant
            text: "In"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [5, 10, 15, 30, 60]
                delegate: Button {
                    id: preset
                    required property int modelData
                    required property int index
                    Layout.fillWidth: true
                    size: "xs"
                    style: "tonal"
                    text: modelData >= 60 ? "1h" : String(modelData)
                    // lit while the running countdown was started from this preset
                    onClicked: Alarm.setIn(modelData)
                    Appear { shown: win.isOpen; delay: 60 + preset.index * 35 }
                }
            }
        }
        RowLayout {
            visible: Alarm.active
            Layout.fillWidth: true
            spacing: 6
            Button {
                Layout.fillWidth: true
                size: "xs"
                style: "tonal"
                text: "−1 min"
                onClicked: Alarm.add(-1)
            }
            Button {
                Layout.fillWidth: true
                size: "xs"
                style: "tonal"
                text: "+1 min"
                onClicked: Alarm.add(1)
            }
            Button {
                Layout.fillWidth: true
                size: "xs"
                style: "tonal"
                text: "+5 min"
                onClicked: Alarm.add(5)
            }
        }
    }

    // ---- time of day ----
    ColumnLayout {
        visible: !Alarm.ringing
        Layout.fillWidth: true
        spacing: 8

        StyledText {
            role: "labelLarge"
            color: Colors.on_surface_variant
            text: "At"
        }
        RowLayout {
            Layout.fillWidth: true
            spacing: 8

            Stepper {
                Layout.fillWidth: true
                value: win.pickHour
                onStep: d => win.pickHour = (win.pickHour + d + 24) % 24
            }
            StyledText {
                role: "headlineSmall"
                emphasized: true
                color: Colors.on_surface_variant
                text: ":"
            }
            Stepper {
                Layout.fillWidth: true
                value: win.pickMinute
                onStep: d => win.pickMinute = (win.pickMinute + d * 5 + 60) % 60
            }
            Button {
                size: "m"
                icon: "check"
                text: "Set"
                onClicked: Alarm.setAt(String(win.pickHour).padStart(2, "0") + ":" + String(win.pickMinute).padStart(2, "0"))
            }
        }
    }

    Button {
        visible: Alarm.active
        Layout.fillWidth: true
        size: "s"
        style: "text"
        text: "Cancel alarm"
        icon: "close"
        onClicked: Alarm.cancel()
    }

    // a number with a step up / down: scroll or click the buttons
    component Stepper: Rectangle {
        id: st
        property int value: 0
        signal step(int dir)

        implicitHeight: 56
        radius: Motion.shapeLarge
        color: Colors.surface_container_highest

        MouseArea {
            anchors.fill: parent
            onWheel: w => st.step(w.angleDelta.y > 0 ? 1 : -1)
        }
        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 4
            anchors.rightMargin: 4
            spacing: 0
            IconButton {
                icon: "remove"
                size: "xs"
                onClicked: st.step(-1)
            }
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
                RollingDigits {
                    anchors.centerIn: parent
                    pixelSize: Typography.size("headlineSmall")
                    text: String(st.value).padStart(2, "0")
                    color: Colors.on_surface
                }
            }
            IconButton {
                icon: "add"
                size: "xs"
                onClicked: st.step(1)
            }
        }
    }
}
