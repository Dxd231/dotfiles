pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import qs
import qs.Components
import qs.Services

// Behind the pages: a blurred wash of the page being read, and big M3 Expressive shapes that drift and
// morph to the next shape on every turn.
Item {
    id: bd

    property int volId: -1
    property int page: 0
    property int turn: 0
    property bool active: true

    readonly property var order: ["cookie9", "sunny", "softBurst", "pentagon", "cookie4", "oval", "star4"]
    property int _turn: 0
    property bool _useB: false
    property string _srcA: ""
    property string _srcB: ""

    // the wash follows the page, a moment after it settles
    Timer {
        id: soon
        interval: 150
        onTriggered: {
            const want = bd.page, vol = bd.volId;
            Manga.request({ op: "thumb", vol: vol, i: want, w: 200 }, r => {
                if (!r.path || bd.page !== want || bd.volId !== vol)
                    return;
                const src = "file://" + r.path;
                if (bd._useB) bd._srcA = src; else bd._srcB = src;
                bd._useB = !bd._useB;
            });
        }
    }
    onPageChanged: soon.restart()
    onVolIdChanged: if (volId >= 0) soon.restart()
    Component.onCompleted: if (volId >= 0) soon.restart()

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container_lowest
    }

    // shapes
    Repeater {
        model: [
            { size: 0.62, fx: 0.06, fy: 0.12, color: "p", dur: 23000, spin: 80000, off: 0 },
            { size: 0.46, fx: 0.94, fy: 0.86, color: "t", dur: 29000, spin: 65000, off: 3 },
            { size: 0.34, fx: 0.9, fy: 0.1, color: "s", dur: 19000, spin: 95000, off: 5 }
        ]
        delegate: Item {
            id: sh
            required property var modelData
            readonly property real d: Math.min(bd.width, bd.height) * modelData.size
            width: d
            height: d
            x: bd.width * modelData.fx - d / 2 + wx
            y: bd.height * modelData.fy - d / 2 + wy
            property real wx: 0
            property real wy: 0
            opacity: bd.active ? 0.5 : 0
            Behavior on opacity { Fade {} }

            property var _from: bd.order[modelData.off % bd.order.length]
            property var _to: _from
            property real _morph: 1
            property bool _spring: true
            property real _spin: 0
            property int _seen: 0
            Connections {
                target: bd
                function onTurnChanged() {
                    const dir = bd.turn >= sh._seen ? 1 : -1;
                    sh._seen = bd.turn;
                    const at = bd.order.indexOf(sh._to);
                    sh._from = sh._to;
                    sh._to = bd.order[(at + dir + bd.order.length) % bd.order.length];
                    sh._spring = false;
                    sh._morph = 0;
                    sh._spring = true;
                    sh._morph = 1;
                }
            }
            Behavior on _morph {
                enabled: sh._spring
                SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
            }
            NumberAnimation on _spin { from: 0; to: 360; duration: sh.modelData.spin; loops: Animation.Infinite; running: bd.active && bd.visible }
            SequentialAnimation on wx {
                loops: Animation.Infinite
                running: bd.active && bd.visible
                NumberAnimation { to: sh.d * 0.08; duration: sh.modelData.dur; easing.type: Easing.InOutSine }
                NumberAnimation { to: -sh.d * 0.08; duration: sh.modelData.dur; easing.type: Easing.InOutSine }
            }
            SequentialAnimation on wy {
                loops: Animation.Infinite
                running: bd.active && bd.visible
                NumberAnimation { to: -sh.d * 0.06; duration: sh.modelData.dur * 1.3; easing.type: Easing.InOutSine }
                NumberAnimation { to: sh.d * 0.06; duration: sh.modelData.dur * 1.3; easing.type: Easing.InOutSine }
            }
            MorphShape {
                anchors.fill: parent
                shape: sh._to
                fromShape: sh._from
                morph: sh._morph
                spin: sh._spin
                color: sh.modelData.color === "p" ? Colors.primary_container : sh.modelData.color === "t" ? Colors.tertiary_container : Colors.secondary_container
            }
        }
    }

    // the blurred page wash
    Item {
        id: wash
        anchors.fill: parent
        opacity: 0.4
        layer.enabled: true
        layer.effect: MultiEffect {
            blurEnabled: true
            blur: 1
            blurMax: 64
            saturation: 0.2
        }
        Image {
            id: imgA
            anchors.centerIn: parent
            width: parent.width * 1.15
            height: parent.height * 1.15
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: bd._srcA
            opacity: bd._useB ? 0 : 1
            Behavior on opacity { Fade {} }
        }
        Image {
            id: imgB
            anchors.centerIn: parent
            width: parent.width * 1.15
            height: parent.height * 1.15
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            source: bd._srcB
            opacity: bd._useB ? 1 : 0
            Behavior on opacity { Fade {} }
        }
    }
}
