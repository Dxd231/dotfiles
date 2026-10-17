pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import qs
import qs.Components

// Time (primary pill with rolling digits) + date.
BarChip {
    id: clock

    property var popup: null

    checked: popup && popup.isOpen
    implicitWidth: content.implicitWidth + 4 + 12
    onClicked: if (popup) popup.toggle()

    SystemClock {
        id: sysClock
        precision: SystemClock.Minutes
    }
    readonly property string time: Qt.formatDateTime(sysClock.date, "HH:mm")

    Row {
        id: content
        anchors.verticalCenter: parent.verticalCenter
        x: 4
        spacing: 8

        Rectangle {
            id: timePill
            anchors.verticalCenter: parent.verticalCenter
            height: 24
            width: digits.implicitWidth + 20
            radius: clock.pressed ? 6 : clock.checked ? Motion.shapeSmall : 12
            color: Colors.primary
            Behavior on radius { Spring {} }
            Behavior on width { Spring {} }

            Row {
                id: digits
                anchors.centerIn: parent
                Repeater {
                    model: clock.time.length
                    delegate: Item {
                        id: digit
                        required property int index
                        readonly property string target: clock.time.charAt(index)
                        property string shown: target
                        width: current.implicitWidth
                        height: current.implicitHeight
                        clip: true

                        // old digit rolls down and out while the new one rolls in from above
                        onTargetChanged: {
                            if (target === shown)
                                return;
                            incoming.text = target;
                            roll.restart();
                        }

                        StyledText {
                            id: current
                            role: "titleSmall"
                            emphasized: true
                            color: Colors.on_primary
                            text: digit.shown
                        }
                        StyledText {
                            id: incoming
                            role: "titleSmall"
                            emphasized: true
                            color: Colors.on_primary
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

        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelLarge"
            color: clock.contentColor
            text: Qt.formatDateTime(sysClock.date, "ddd, d MMM")
        }
    }
}
