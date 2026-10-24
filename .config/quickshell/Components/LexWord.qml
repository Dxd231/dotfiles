import QtQuick
import qs
import qs.Services

// One word of a segmented line, drawn the way the subtitles draw it: a straight underline for an unknown
// (tertiary) or learning (secondary) word, a wavy one for a leech, a dot when it is due, readings above it
// (Alt+f). Hovering lifts a pill behind it. It only reports the pointer; the owner decides what opens.
Item {
    id: word

    property var tok: null              // { s, k, status, ruby, due, leech, key }
    property real fontPx: 26
    property string family: Typography.familyJp
    property bool bold: true
    property color color: Colors.on_surface
    property color pill: Qt.alpha(Colors.on_surface, 0.16)
    // the word an open card belongs to keeps its pill
    property bool active: false
    // false: punctuation and the like, drawn plain
    readonly property bool isWord: tok !== null && tok.k === "word"
    readonly property string status: tok ? Lexicon.statusOf(tok) : "unknown"
    readonly property bool marked: isWord && (status === "unknown" || status === "learning")
    readonly property bool leech: status === "learning" && tok !== null && tok.leech === true
    readonly property bool due: status === "learning" && tok !== null && tok.due === true
    readonly property string furi: Lexicon.furigana
    readonly property real rubyH: furi !== "off" ? fontPx * 0.66 : 0
    readonly property bool hasRuby: tok !== null && tok.ruby !== undefined && (furi === "all" || (furi === "unknown" && marked))
    readonly property real ulH: Math.max(3, Math.round(fontPx * 0.075))
    readonly property bool hovered: hover.hovered

    signal pointerIn(rect where)
    signal pointerOut()
    signal clicked(rect where)

    function whereRect() {
        const p = word.mapToItem(null, 0, 0);
        const q = word.mapToItem(null, word.width, word.height);
        return Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y);
    }

    implicitWidth: label.implicitWidth
    implicitHeight: label.implicitHeight + rubyH

    Rectangle {
        anchors.fill: parent
        anchors.margins: -word.fontPx * 0.04
        radius: word.fontPx * 0.18
        color: word.pill
        opacity: (hover.hovered || word.active) && word.isWord ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 90 } }
    }
    Row {
        visible: word.hasRuby
        y: 0
        Repeater {
            model: word.hasRuby ? word.tok.ruby : []

            Item {
                id: seg

                required property var modelData
                width: base.implicitWidth
                height: 1
                Text {
                    id: base
                    visible: false
                    text: seg.modelData[0]
                    font: label.font
                }
                Text {
                    visible: seg.modelData[1] !== ""
                    anchors.horizontalCenter: parent.horizontalCenter
                    y: 0
                    text: seg.modelData[1]
                    color: word.color
                    font.family: word.family
                    font.bold: word.bold
                    font.pixelSize: word.fontPx * 0.55
                }
            }
        }
    }
    Text {
        id: label
        y: word.rubyH
        text: word.tok ? word.tok.s : ""
        color: word.color
        font.family: word.family
        font.bold: word.bold
        font.pixelSize: word.fontPx
    }
    Rectangle {
        opacity: word.marked && !word.leech ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Fade {} }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -word.fontPx * 0.02
        anchors.leftMargin: word.fontPx * 0.04
        anchors.rightMargin: word.fontPx * 0.04
        height: word.ulH
        radius: height / 2
        color: word.status === "learning" ? Colors.secondary : Colors.tertiary
        Behavior on color { ColorFade {} }
    }
    WavyUnderline {
        opacity: word.leech ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Fade {} }
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.bottomMargin: -word.fontPx * 0.02 - amplitude
        anchors.leftMargin: word.fontPx * 0.04
        anchors.rightMargin: word.fontPx * 0.04
        thickness: word.ulH
        amplitude: word.ulH * 0.5
        wavelength: word.fontPx * 0.32
        color: Colors.secondary
    }
    Rectangle {
        opacity: word.due ? 1 : 0
        scale: word.due ? 1 : 0.3
        visible: opacity > 0
        Behavior on opacity { Fade {} }
        Behavior on scale { Spring { speed: "fast" } }
        x: parent.width - width * 0.6
        y: word.rubyH - height * 0.3
        width: Math.max(6, Math.round(word.fontPx * 0.13))
        height: width
        radius: width / 2
        color: Colors.secondary
    }
    HoverHandler {
        id: hover
        enabled: word.isWord
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: hovered ? word.pointerIn(word.whereRect()) : word.pointerOut()
    }
    TapHandler {
        enabled: word.isWord
        // an exclusive grab on press accepts the point, so the page under the card never sees the click
        gesturePolicy: TapHandler.WithinBounds
        onTapped: word.clicked(word.whereRect())
    }
}
