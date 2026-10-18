import QtQuick
import qs

// Text whose digits roll vertically when they change (old one slides out, new one in from above).
// Every digit sits in one fixed cell (the width of an "8", the colon with its own), so the string
// keeps one width as the numbers tick over.
Item {
    id: root

    property string text
    property int pixelSize: 24
    property int weight: Font.Bold
    property real letterSpacing: 0
    property color color: Colors.on_surface

    property real digitWidth: 0
    property real colonWidth: 0

    implicitWidth: row.implicitWidth
    implicitHeight: probe.implicitHeight

    Text {
        id: probe
        visible: false
        text: "8"
        font.family: Typography.family
        font.pixelSize: root.pixelSize
        font.weight: root.weight
        font.letterSpacing: root.letterSpacing
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
    onPixelSizeChanged: Qt.callLater(measure)

    Row {
        id: row
        Repeater {
            model: root.text.length
            delegate: Item {
                id: digit
                required property int index
                readonly property string target: root.text.charAt(index)
                property string shown: target
                // natural width until the cell size has been measured
                width: (target === ":" ? root.colonWidth : root.digitWidth) || current.implicitWidth
                height: root.implicitHeight
                clip: true

                onTargetChanged: {
                    if (target === shown) {
                        // back to what's on show while a roll to something else is under way: cancel
                        // it, or it would finish on the stale value
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

                Text {
                    id: current
                    x: (digit.width - width) / 2
                    text: digit.shown
                    color: root.color
                    font: probe.font
                }
                Text {
                    id: incoming
                    x: (digit.width - width) / 2
                    y: -digit.height
                    color: root.color
                    font: probe.font
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
