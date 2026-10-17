import QtQuick
import qs

// Keeps a ListView's current item in view with a smooth scroll. Needed by lists that draw
// their own spring highlight (highlightFollowsCurrentItem: false), which turns off
// ListView's built-in follow-the-current-item scrolling.
// Usage, inside the ListView:  ScrollIntoView { view: list }
NumberAnimation {
    id: scroller

    required property ListView view
    property real margin: 4

    target: view
    property: "contentY"
    duration: Motion.medium2
    easing.type: Easing.BezierSpline
    easing.bezierCurve: Motion.emphasizedDecelerate

    function reveal() {
        const v = view;
        const item = v ? v.currentItem : null;
        if (!item || v.height <= 0)
            return;
        const top = item.y - margin;
        const bottom = item.y + item.height + margin;
        let to = v.contentY;
        if (top < v.contentY)
            to = top;
        else if (bottom > v.contentY + v.height)
            to = bottom - v.height;
        to = Math.max(v.originY, Math.min(to, v.originY + v.contentHeight - v.height));
        if (Math.abs(to - v.contentY) < 0.5)
            return;
        stop();
        from = v.contentY;
        scroller.to = to;
        start();
    }

    readonly property Connections _follow: Connections {
        target: scroller.view
        function onCurrentIndexChanged() { Qt.callLater(scroller.reveal); }
    }
}
