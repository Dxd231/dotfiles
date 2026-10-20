pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.Components
import qs.Services

// Time pill (rolling digits) + date + pomodoro chip. The time opens the quick alarm panel (and rings
// while an alarm goes off), the date opens the calendar, the chip opens the focus timer.
Rectangle {
    id: clock

    property var calendarPopup: null
    property var focusPopup: null
    property var alarmPopup: null

    // anchors for the popups that open from each part
    readonly property Item timeAnchor: timePill
    readonly property Item dateAnchor: dateButton
    readonly property Item focusAnchor: focusChip

    implicitHeight: 32
    height: 32
    implicitWidth: content.implicitWidth + 4 + 4
    radius: 16
    color: Colors.surface_container_high

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }
    readonly property string time: Qt.formatDateTime(sysClock.date, "HH:mm")
    readonly property string shownText: time

    // Every digit gets one fixed cell (the width of an "8", a typical digit; the colon has its own), so
    // the pill keeps one width as the numbers change instead of nudging the whole bar group each tick.
    // Narrow digits like "1" sit centred in their cell, and the wider "0" fits within its side bearings.
    property real digitWidth: 0
    property real colonWidth: 0
    StyledText {
        id: probe
        visible: false
        role: "titleSmall"
        emphasized: true
    }
    TextMetrics {
        id: metrics
        font: probe.font
    }
    function measure() {
        metrics.text = "8";
        digitWidth = metrics.advanceWidth;
        metrics.text = ":";
        colonWidth = metrics.advanceWidth;
    }
    Component.onCompleted: Qt.callLater(measure)
    Connections {
        target: probe
        function onFontChanged() { clock.measure(); }
    }

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        x: 4
        spacing: 4

        Clickable {
            id: timePill
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: pillRow.implicitWidth + 20
            restRadius: 12
            pressedRadius: 6
            checkedRadius: Motion.shapeSmall
            checked: !!clock.alarmPopup && clock.alarmPopup.isOpen
            color: Alarm.ringing ? Colors.error : Colors.primary
            contentColor: Alarm.ringing ? Colors.on_error : Colors.on_primary
            Behavior on width { Spring {} }
            scale: pressed ? 0.93 : hovered ? 1.05 : 1
            Behavior on scale { Spring { speed: "fast" } }
            onClicked: {
                if (Alarm.ringing)
                    Alarm.stop();
                else if (clock.alarmPopup)
                    clock.alarmPopup.toggle();
            }

            // shakes while an alarm rings
            SequentialAnimation on rotation {
                running: Alarm.ringing
                loops: Animation.Infinite
                alwaysRunToEnd: true
                NumberAnimation { to: 6; duration: 70; easing.type: Easing.InOutQuad }
                NumberAnimation { to: -6; duration: 140; easing.type: Easing.InOutQuad }
                NumberAnimation { to: 0; duration: 70; easing.type: Easing.InOutQuad }
                PauseAnimation { duration: 400 }
            }

            Row {
                id: pillRow
                anchors.centerIn: parent
                spacing: 4

                Icon {
                    visible: Alarm.active || Alarm.ringing
                    anchors.verticalCenter: parent.verticalCenter
                    name: "alarm"
                    size: 16
                    color: timePill.contentColor
                }

                Row {
                    id: digits
                    anchors.verticalCenter: parent.verticalCenter
                    Repeater {
                        model: clock.shownText.length
                        delegate: Item {
                            id: digit
                            required property int index
                            readonly property string target: clock.shownText.charAt(index)
                            property string shown: target
                            // natural width until the cell size has been measured
                            width: (target === ":" ? clock.colonWidth : clock.digitWidth) || current.implicitWidth
                            height: current.implicitHeight
                            clip: true

                            // old digit rolls down and out while the new one rolls in from above
                            onTargetChanged: {
                                if (target === shown) {
                                    // back to what's on show mid-roll: cancel it, or it finishes on the stale digit
                                    if (roll.running) {
                                        roll.stop();
                                        current.y = 0;
                                        incoming.y = -digit.height;
                                    }
                                    return;
                                }
                                incoming.text = target;
                                roll.restart();
                            }

                            StyledText {
                                id: current
                                x: (digit.width - width) / 2
                                role: "titleSmall"
                                emphasized: true
                                color: timePill.contentColor
                                text: digit.shown
                            }
                            StyledText {
                                id: incoming
                                x: (digit.width - width) / 2
                                role: "titleSmall"
                                emphasized: true
                                color: timePill.contentColor
                                y: -height
                            }
                            ParallelAnimation {
                                id: roll
                                NumberAnimation { target: current; property: "y"; from: 0; to: digit.height; duration: Motion.expressiveFastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                                NumberAnimation { target: incoming; property: "y"; from: -digit.height; to: 0; duration: Motion.expressiveFastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                                onFinished: {
                                    digit.shown = incoming.text;
                                    current.y = 0;
                                    incoming.y = -digit.height;
                                }
                            }
                        }
                    }
                }
            }
        }

        Clickable {
            id: dateButton
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: dateText.implicitWidth + 20
            restRadius: 12
            pressedRadius: 6
            checkedRadius: Motion.shapeSmall
            checked: !!clock.calendarPopup && clock.calendarPopup.isOpen
            color: checked ? Colors.secondary_container : "transparent"
            contentColor: checked ? Colors.on_secondary_container : Colors.on_surface
            scale: pressed ? 0.93 : hovered ? 1.05 : 1
            Behavior on scale { Spring { speed: "fast" } }
            onClicked: if (clock.calendarPopup) clock.calendarPopup.toggle()

            StyledText {
                id: dateText
                anchors.centerIn: parent
                role: "labelLarge"
                color: dateButton.contentColor
                text: Qt.formatDateTime(sysClock.date, "ddd, d MMM")
            }
        }

        BarFocus {
            id: focusChip
            anchors.verticalCenter: parent.verticalCenter
            focusPopup: clock.focusPopup
        }
    }
}
