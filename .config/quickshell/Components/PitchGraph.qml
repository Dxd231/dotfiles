import QtQuick
import QtQuick.Shapes
import qs

// A Japanese pitch-accent contour: the reading's morae along the bottom, a dot over each at its pitch
// (high or low) joined by a line, and one more dot for what follows the word (a particle). `pos` is the
// downstep: 0 flat (平板), 1 high on the first mora (頭高), n on the last (尾高), anything between (中高).
// The dot before the drop is drawn in `dropColor`.
Item {
    id: graph

    property string reading
    property int pos: -1
    property color color: Colors.primary
    property color dropColor: Colors.tertiary
    property real cell: 24
    property int textSize: 15
    // false snaps size and position changes (a card that is still being placed)
    property bool animate: true

    // small kana and the long-vowel mark belong to the mora before them
    readonly property var morae: {
        const out = [];
        const glue = "ゃゅょぁぃぅぇぉゎャュョァィゥェォヮ";
        for (const ch of Array.from(reading)) {
            if (out.length > 0 && glue.indexOf(ch) >= 0)
                out[out.length - 1] += ch;
            else
                out.push(ch);
        }
        return out;
    }
    readonly property int n: morae.length
    readonly property bool known: pos >= 0 && pos <= n && n > 0

    readonly property real highY: 4
    readonly property real lowY: 16
    function isHigh(i) {
        if (pos === 0)
            return i > 0;
        if (pos === 1)
            return i === 0;
        return i > 0 && i < pos;
    }
    // the mora the pitch falls after
    readonly property int dropAt: pos > 0 ? pos - 1 : -1

    readonly property var points: {
        const p = [];
        if (!known)
            return p;
        for (let i = 0; i <= n; i++)
            p.push(Qt.point((i + 0.5) * cell, isHigh(i) ? highY : lowY));
        return p;
    }

    readonly property string patternName: !known ? "" : pos === 0 ? "平板" : pos === 1 ? "頭高" : pos === n ? "尾高" : "中高"

    property real _w: (n + (known ? 1 : 0)) * cell
    property real _h: (known ? lowY + 8 : 0) + textSize + 8
    Behavior on _w { enabled: graph.animate; Spring { speed: "fast" } }
    Behavior on _h { enabled: graph.animate; Spring { speed: "fast" } }
    implicitWidth: Math.max(0, _w)
    implicitHeight: Math.max(0, _h)

    Shape {
        opacity: graph.known ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Fade { speed: "default" } }
        anchors.fill: parent
        preferredRendererType: Shape.CurveRenderer
        ShapePath {
            strokeWidth: 2
            strokeColor: Qt.alpha(graph.color, 0.55)
            fillColor: "transparent"
            capStyle: ShapePath.RoundCap
            joinStyle: ShapePath.RoundJoin
            PathPolyline { path: graph.points }
        }
    }
    Repeater {
        model: graph.known ? graph.n + 1 : 0
        Item {
            id: dotSlot
            required property int index
            width: 7
            height: 7
            x: (index + 0.5) * graph.cell - width / 2
            y: (graph.isHigh(index) ? graph.highY : graph.lowY) - height / 2
            Behavior on y { enabled: graph.animate; Spring { speed: "fast" } }
            Appear { delay: 40 + dotSlot.index * 35; lift: 4; from: 0.4 }
            Rectangle {
                anchors.fill: parent
                radius: 3.5
                color: dotSlot.index === graph.dropAt ? graph.dropColor : graph.color
                Behavior on color { ColorFade {} }
                // the last dot is the particle: it only shows where the pitch goes next
                opacity: dotSlot.index === graph.n ? 0.45 : 1
            }
        }
    }
    Row {
        y: graph.known ? graph.lowY + 8 : 0
        Behavior on y { enabled: graph.animate; Spring { speed: "fast" } }
        Repeater {
            model: graph.morae
            StyledText {
                required property string modelData
                required property int index
                Appear { delay: index * 30; lift: 4 }
                width: graph.cell
                horizontalAlignment: Text.AlignHCenter
                jp: true
                text: modelData
                font.pixelSize: graph.textSize
                font.weight: Font.Bold
                color: Colors.on_surface
            }
        }
    }
}
