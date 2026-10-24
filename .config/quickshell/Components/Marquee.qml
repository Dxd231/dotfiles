import QtQuick
import qs

// Single-line text that scrolls back and forth when it overflows; centred (or left-aligned)
// when it fits. Set `running` false to park it while hidden.
Item {
    id: marquee

    property string text
    property string role: "bodyMedium"
    property bool emphasized: false
    property bool jp: false
    property color color: Colors.on_surface
    property bool centered: true
    property bool running: true
    readonly property real overflow: Math.max(0, label.implicitWidth - width)
    readonly property bool scrolling: overflow > 8

    implicitHeight: label.implicitHeight
    clip: true

    StyledText {
        id: label
        text: marquee.text
        role: marquee.role
        emphasized: marquee.emphasized
        jp: marquee.jp
        color: marquee.color
        x: marquee.scrolling || !marquee.centered ? 0 : (marquee.width - implicitWidth) / 2
        onTextChanged: {
            scroll.stop();
            // stop() drops the binding on `running`; without this a changed title never scrolls again
            scroll.running = Qt.binding(() => marquee.scrolling && marquee.running);
            x = Qt.binding(() => marquee.scrolling || !marquee.centered ? 0 : (marquee.width - implicitWidth) / 2);
        }
    }

    SequentialAnimation {
        id: scroll
        loops: Animation.Infinite
        running: marquee.scrolling && marquee.running
        onRunningChanged: if (!running) label.x = 0
        PauseAnimation { duration: 1800 }
        NumberAnimation { target: label; property: "x"; to: -marquee.overflow; duration: Math.max(2000, marquee.overflow * 32) }
        PauseAnimation { duration: 1400 }
        NumberAnimation { target: label; property: "x"; to: 0; duration: Motion.medium4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasized }
        PauseAnimation { duration: 500 }
    }
}
