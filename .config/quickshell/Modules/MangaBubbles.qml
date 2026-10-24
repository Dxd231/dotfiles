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
    property string path: ""             // the page's picture, for the card's panel
    readonly property bool showHidden: Manga.reader ? Manga.reader.showHidden : false
    onShowHiddenChanged: load()

    function load() {
        Manga.request({ op: "ocr", vol: root.vol, idx: root.idx, hidden: root.showHidden }, r => {
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
            readonly property string key: root.vol + "|" + root.idx + "|" + modelData.i
            readonly property bool hiddenByUser: modelData.hidden === true
            // what the card needs to know about this bubble and its page
            function meta() {
                return { vol: root.vol, idx: root.idx, i: modelData.i, order: modelData.order, block: modelData,
                         edited: modelData.edited === true, ocr: modelData.ocr || modelData.text, hidden: hiddenByUser,
                         blocks: root.blocks, w: root.ow, h: root.oh, path: root.path };
            }
            function rectIn() {
                const p = b.mapToItem(null, 0, 0);
                const q = b.mapToItem(null, b.width, b.height);
                return Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y);
            }
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
                color: b.hiddenByUser ? Colors.error_container : Colors.surface_container_highest
                opacity: hover.hovered ? 0.4 : b.hiddenByUser ? 0.22 : 0
                visible: opacity > 0.01
                Behavior on opacity { Fade {} }
            }
            HoverHandler {
                id: hover
                onHoveredChanged: {
                    const layer = Manga.reader ? Manga.reader.bubbles : null;
                    if (!layer)
                        return;
                    if (hovered)
                        layer.enter(b.key, b.modelData.text, b.rectIn(), b.meta());
                    else
                        layer.leave(b.key);
                }
            }
            // right-click: the card turns into the text editor
            TapHandler {
                acceptedButtons: Qt.RightButton
                gesturePolicy: TapHandler.WithinBounds
                onTapped: {
                    const layer = Manga.reader ? Manga.reader.bubbles : null;
                    if (layer)
                        layer.edit(b.key, b.modelData.text, b.rectIn(), b.meta());
                }
            }
        }
    }
}
