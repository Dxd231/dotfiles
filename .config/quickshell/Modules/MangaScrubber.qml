pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components
import qs.Services

// The page slider along the bottom: right to left for right-to-left books, with a page preview above the
// handle while it is held.
Rectangle {
    id: sb

    property int volId: -1
    property int total: 0
    property int page: 0
    property bool rtl: true
    property var bookmarks: []
    property int furthest: 0
    signal seek(int page)

    // the page under the handle while it is dragged
    property int _hover: page
    property string _thumb: ""
    readonly property bool dragging: slider.pressed

    implicitHeight: 64
    radius: Motion.shapeExtraLarge
    color: Colors.surface_container

    // right to left books run the slider backwards: it is mirrored, so the read part fills from the right
    function _value(p) { return p; }
    function _page(v) { return Math.round(v); }

    Timer {
        id: thumbSoon
        interval: 90
        onTriggered: {
            const want = sb._hover;
            Manga.request({ op: "thumb", vol: sb.volId, i: want, w: 200 }, r => {
                if (r.path && sb._hover === want)
                    sb._thumb = "file://" + r.path;
            });
        }
    }
    on_HoverChanged: if (dragging) thumbSoon.restart()
    onDraggingChanged: if (dragging) { _hover = page; thumbSoon.restart(); }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 24
        anchors.rightMargin: 24
        spacing: 16
        StyledText {
            role: "labelLarge"
            emphasized: true
            text: (sb.rtl ? sb.total : 1) + ""
            color: Colors.on_surface_variant
            Layout.minimumWidth: 28
        }
        Slider {
            id: slider
            Layout.fillWidth: true
            from: 0
            to: Math.max(1, sb.total - 1)
            value: sb._value(sb.page)
            transform: Scale { origin.x: slider.width / 2; xScale: sb.rtl ? -1 : 1 }
            onMoved: v => {
                const p = sb._page(v);
                sb._hover = p;
                sb.seek(p);
            }
        }
        StyledText {
            role: "labelLarge"
            emphasized: true
            text: (sb.rtl ? 1 : sb.total) + ""
            color: Colors.on_surface_variant
            horizontalAlignment: Text.AlignRight
            Layout.minimumWidth: 28
        }
    }

    function _x(p) {
        const f = p / Math.max(1, sb.total - 1);
        return slider.x + 24 + slider.width * (sb.rtl ? 1 - f : f);
    }

    // bookmark ticks above the track; a click goes to the page
    Repeater {
        model: sb.bookmarks
        delegate: Rectangle {
            id: tick
            required property int modelData
            width: 6
            height: 12
            radius: Motion.shapeFull
            color: Colors.primary
            x: sb._x(modelData) - width / 2
            y: 6
            scale: 0
            Component.onCompleted: scale = 1
            Behavior on scale { Spring {} }
            Behavior on x { Spring { speed: "fast" } }
            MouseArea {
                anchors.centerIn: parent
                width: 20
                height: 24
                cursorShape: Qt.PointingHandCursor
                onClicked: sb.seek(tick.modelData)
            }
        }
    }
    // how far this volume has been read
    Rectangle {
        visible: sb.furthest > 0
        width: 6
        height: 6
        radius: Motion.shapeFull
        color: Colors.tertiary
        x: sb._x(sb.furthest) - width / 2
        y: sb.height - 12
        Behavior on x { Spring { speed: "fast" } }
    }

    // page preview
    Rectangle {
        id: preview
        readonly property real cx: slider.x + 24 + slider.width * (sb.rtl ? 1 - sb._hover / Math.max(1, sb.total - 1) : sb._hover / Math.max(1, sb.total - 1))
        width: 200
        height: img.status === Image.Ready ? Math.min(300, img.implicitHeight * 200 / Math.max(1, img.implicitWidth)) : 120
        x: Math.max(0, Math.min(sb.width - width, cx - width / 2))
        y: -height - 12
        radius: Motion.shapeMedium
        color: Colors.surface_container_high
        opacity: sb.dragging && sb._thumb !== "" ? 1 : 0
        visible: opacity > 0.01
        scale: sb.dragging ? 1 : 0.9
        Behavior on opacity { Fade {} }
        Behavior on scale { Spring {} }
        Behavior on height { Spring { speed: "fast" } }
        Image {
            id: img
            anchors.fill: parent
            source: sb._thumb
            fillMode: Image.PreserveAspectFit
            asynchronous: true
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 6
            role: "labelLarge"
            emphasized: true
            text: (sb._hover + 1) + " / " + sb.total
            color: Colors.on_surface
        }
    }
}
