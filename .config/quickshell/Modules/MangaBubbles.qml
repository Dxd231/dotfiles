import QtQuick
import qs
import qs.Components
import qs.Services

// The speech bubbles of one page, found by the text recognition. Invisible until the pointer is over one,
// then a soft fill; the reader's bubble layer is told which bubble it is and where, to show its words.
// It fills the page, so a box in page pixels maps by plain scaling and follows zoom, pan and the page turn.
Item {
    id: root

    property int vol: -1
    property int idx: -1
    property var blocks: []
    property real ow: 1
    property real oh: 1

    function load() {
        Manga.request({ op: "ocr", vol: root.vol, idx: root.idx }, r => {
            if (r && r.blocks && r.w > 0) {
                root.ow = r.w;
                root.oh = r.h;
                root.blocks = r.blocks.filter(b => b.text && b.text.trim() !== "");
            }
        });
    }
    Component.onCompleted: load()
    Connections {
        target: Manga
        function onEvent(e) {
            if (e.event === "ocr" && e.vol === root.vol && e.idx === root.idx)
                root.load();
        }
    }

    Repeater {
        model: root.blocks

        Item {
            id: b

            required property var modelData
            required property int index
            readonly property string key: root.vol + "|" + root.idx + "|" + index
            readonly property real pad: 4
            readonly property real sx: root.width / root.ow
            readonly property real sy: root.height / root.oh
            x: modelData.box[0] * sx - pad
            y: modelData.box[1] * sy - pad
            width: (modelData.box[2] - modelData.box[0]) * sx + pad * 2
            height: (modelData.box[3] - modelData.box[1]) * sy + pad * 2

            Rectangle {
                anchors.fill: parent
                radius: Motion.shapeMedium
                color: Colors.surface_container_highest
                opacity: hover.hovered ? 0.4 : 0
                visible: opacity > 0.01
                Behavior on opacity { Fade {} }
            }
            HoverHandler {
                id: hover
                onHoveredChanged: {
                    const layer = Manga.reader ? Manga.reader.bubbles : null;
                    if (!layer)
                        return;
                    if (hovered) {
                        const p = b.mapToItem(null, 0, 0);
                        const q = b.mapToItem(null, b.width, b.height);
                        layer.enter(b.key, b.modelData.text, Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y));
                    } else
                        layer.leave(b.key);
                }
            }
        }
    }
}
