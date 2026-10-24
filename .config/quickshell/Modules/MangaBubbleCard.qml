pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services

// What the pointer finds on a page: over a bubble, a card beside it holds the bubble's text cut into words;
// over a word, the dictionary card. It fills the reader and only draws its two cards, so the pages under it
// keep the pointer. The pages call enter/leave; the reader calls closeAll when the view moves.
Item {
    id: root

    // ---- the bubble ----
    property var shownCur: null          // { key, text, rect } of the bubble the card is for
    property var rows: []                // its words: [[token]]
    property bool open: false
    property int bubbleN: 0
    readonly property int unknown: {
        let n = 0;
        for (const row of rows)
            for (const t of row)
                if (t.k === "word" && Lexicon.statusOf(t) === "unknown")
                    n++;
        return n;
    }
    property string _hover: ""
    property var _cand: null
    property var _seg: ({})              // key -> rows, so a bubble seen again is instant
    readonly property bool cardHovered: cardHover.hovered

    function enter(key, text, rect) {
        if (Manga.reader && Manga.reader.libOpen)
            return;
        _hover = key;
        closeTimer.stop();
        if (open && shownCur && shownCur.key === key) {
            _cand = null;
            openTimer.stop();
            return;
        }
        _cand = { key: key, text: text, rect: rect };
        openTimer.interval = open ? 160 : 120;
        openTimer.restart();
    }
    function leave(key) {
        if (_hover !== key)
            return;
        _hover = "";
        openTimer.stop();
        _cand = null;
        if (open)
            closeTimer.restart();
    }
    function closeAll() {
        openTimer.stop();
        closeTimer.stop();
        _cand = null;
        _hover = "";
        closeWord();
        open = false;
    }
    Timer {
        id: openTimer
        interval: 120
        onTriggered: {
            const c = root._cand;
            root._cand = null;
            if (!c)
                return;
            const have = root._seg[c.key];
            if (have)
                root._commit(c, have);
            else
                Lexicon.segmentText(c.text, rows => {
                    root._seg[c.key] = rows;
                    // the pointer may have moved on while the words were cut
                    if (root._hover === c.key)
                        root._commit(c, rows);
                });
        }
    }
    Timer {
        id: closeTimer
        interval: 500
        onTriggered: {
            if (root.cardHovered || root.popOpen || root._whover !== null || root._hover !== "")
                return;
            root.open = false;
        }
    }
    function _commit(c, rows) {
        const apply = () => {
            root.bubbleN++;
            root.shownCur = c;
            root.rows = rows;
            root.open = true;
        };
        if (open && shownCur && shownCur.key !== c.key) {
            closeWord(true);
            swap.apply = apply;
            swap.restart();
        } else {
            swap.apply = null;
            apply();
        }
    }
    SequentialAnimation {
        id: swap
        property var apply: null
        NumberAnimation { target: content; property: "opacity"; to: 0; duration: 80 }
        ScriptAction { script: if (swap.apply) swap.apply() }
        NumberAnimation { target: content; property: "opacity"; to: 1; duration: 120 }
    }

    // ---- the word ----
    property var popTok: null
    property rect popAnchor: Qt.rect(0, 0, 0, 0)
    property var popCtx: null
    property bool popOpen: false
    property bool popPinned: false
    property var _whover: null
    property var _wcand: null
    property var _pending: null

    function wordEnter(tok, rect, ctx) {
        _whover = tok;
        closeTimer.stop();
        if (!popOpen) {
            Lexicon.focusTok = tok;
            Lexicon.focusCtx = ctx;
        }
        if (popPinned)
            return;
        wordClose.stop();
        if (popOpen && popTok && popTok.key === tok.key) {
            _wcand = null;
            wordOpen.stop();
            return;
        }
        _wcand = { tok: tok, rect: rect, ctx: ctx };
        wordOpen.interval = popOpen ? 300 : 250;
        wordOpen.restart();
    }
    function wordLeave(tok) {
        if (_whover && tok && _whover.key !== tok.key)
            return;
        _whover = null;
        wordOpen.stop();
        _wcand = null;
        if (!popOpen && !_pending)
            Lexicon.focusTok = null;
        if (popOpen && !popPinned) {
            if (!popup.hovered)
                wordClose.restart();
        } else if (!popOpen)
            closeTimer.restart();
    }
    function wordClick(tok, rect, ctx) {
        if (popOpen && popPinned && popTok && popTok.key === tok.key) {
            closeWord();
            return;
        }
        wordOpen.stop();
        wordClose.stop();
        _show({ tok: tok, rect: rect, ctx: ctx });
        popPinned = true;
    }
    function closeWord(keepCard) {
        capTimer.stop();
        wordOpen.stop();
        wordClose.stop();
        _pending = null;
        _wcand = null;
        popOpen = false;
        popPinned = false;
        Lexicon.focusTok = null;
        if (open && keepCard !== true)
            closeTimer.restart();
    }
    // the card appears once its entry is in, so it is placed for its final size
    function _show(c) {
        _pending = c;
        capTimer.restart();
        Lexicon.define(c.tok, () => {
            if (root._pending === c)
                root._apply(c);
        });
    }
    function _apply(c) {
        capTimer.stop();
        _pending = null;
        const go = () => {
            root.popTok = c.tok;
            root.popAnchor = c.rect;
            root.popCtx = c.ctx;
            Lexicon.recheck(c.tok);
            Lexicon.focusTok = c.tok;
            Lexicon.focusCtx = c.ctx;
            root.popOpen = true;
        };
        // another word: the card goes and comes back, so it is placed again for its new entry
        if (popOpen && popTok && popTok.key !== c.tok.key && popup.visible)
            popup.swapTo(go);
        else
            go();
    }
    Timer {
        id: wordOpen
        interval: 120
        onTriggered: if (root._wcand) { const c = root._wcand; root._wcand = null; root._show(c); }
    }
    Timer {
        id: wordClose
        interval: 500
        onTriggered: if (!popup.hovered) root.closeWord()
    }
    Timer {
        id: capTimer
        interval: 450
        onTriggered: if (root._pending) root._apply(root._pending)
    }

    // keys of the study set (Alt+k, Alt+i, Alt+n, Alt+f), on the word under the pointer
    function known() { if (Lexicon.focusTok) Lexicon.mark(Lexicon.focusTok, "known"); }
    function ignore() { if (Lexicon.focusTok) Lexicon.mark(Lexicon.focusTok, "ignored"); }
    function name() { if (Lexicon.focusTok) Lexicon.setName(Lexicon.focusTok, Lexicon.focusTok.status === "name" ? 0 : 1); }

    // ---- the card beside the bubble ----
    Rectangle {
        id: card
        readonly property var r: root.shownCur ? root.shownCur.rect : Qt.rect(0, 0, 0, 0)
        readonly property real fontPx: 26
        readonly property real textLen: root.shownCur ? root.shownCur.text.length : 0
        width: Math.round(Math.max(280, Math.min(460, textLen * fontPx * 1.05 + 40)))
        height: content.implicitHeight + 44
        readonly property real roomRight: root.width - (r.x + r.width) - 16
        readonly property real roomLeft: r.x - 16
        readonly property bool onRight: roomRight >= width + 12 || roomRight >= roomLeft
        readonly property bool fits: Math.max(roomRight, roomLeft) >= width + 12
        // beside the bubble on the roomier side; when neither side has room, above or below it
        readonly property real tx: fits ? (onRight ? r.x + r.width + 12 : r.x - width - 12) : r.x + r.width / 2 - width / 2
        readonly property real ty: fits ? r.y + r.height / 2 - height / 2 : (r.y > root.height / 2 ? r.y - height - 12 : r.y + r.height + 12)
        property bool placed: false
        x: Math.max(16, Math.min(root.width - width - 16, tx))
        y: Math.max(16, Math.min(root.height - height - 16, ty))
        Behavior on x { enabled: card.placed; Spring { speed: "default" } }
        Behavior on y { enabled: card.placed; Spring { speed: "default" } }
        Behavior on width { enabled: card.placed; Spring { speed: "default" } }
        radius: Motion.shapeLarge
        color: Colors.surface_container
        visible: opacity > 0.01
        opacity: root.open ? 1 : 0
        Behavior on opacity { Fade {} }
        scale: root.open ? 1 : 0.94
        Behavior on scale { Spring { speed: "fast" } }
        // the first placement after it was hidden jumps; moves between bubbles glide
        Connections {
            target: root
            function onOpenChanged() { if (!root.open) card.placed = false; else Qt.callLater(() => card.placed = true); }
        }
        // the card keeps every click: a press that reaches the page under it would turn the page
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
        }
        ShapeBadge {
            x: -14
            y: -14
            width: 42
            height: 42
            shapeRest: "cookie9"
            shapeActive: "sunny"
            active: root.bubbleN % 2 === 1
            color: Colors.tertiary_container
            badgeScale: root.open ? 1 : 0
            RollingDigits {
                anchors.centerIn: parent
                visible: root.unknown > 0
                text: root.unknown.toString()
                pixelSize: 20
                color: Colors.on_tertiary_container
            }
            Icon {
                anchors.centerIn: parent
                visible: root.unknown === 0
                name: "check"
                size: 22
                color: Colors.on_tertiary_container
            }
        }
        HoverHandler {
            id: cardHover
            onHoveredChanged: {
                if (hovered)
                    closeTimer.stop();
                else if (root.open && !root.popOpen)
                    closeTimer.restart();
            }
        }
        Column {
            id: content
            x: 18
            y: 26
            width: card.width - 36
            spacing: 6
            Repeater {
                model: root.rows

                Flow {
                    id: line

                    required property var modelData
                    width: content.width
                    spacing: 0
                    Repeater {
                        model: line.modelData

                        LexWord {
                            id: lw

                            required property var modelData
                            required property int index
                            tok: modelData
                            fontPx: card.fontPx
                            active: root.popOpen && root.popTok !== null && root.popTok.key === modelData.key
                            function ctx() {
                                const j = line.modelData.map(t => t.s);
                                return { prefix: j.slice(0, index).join(""), suffix: j.slice(index + 1).join(""),
                                         flat: root.shownCur ? root.shownCur.text : "", start: -1, toks: line.modelData, index: index };
                            }
                            onPointerIn: where => root.wordEnter(modelData, where, ctx())
                            onPointerOut: root.wordLeave(modelData)
                            onClicked: where => root.wordClick(modelData, where, ctx())
                        }
                    }
                }
            }
        }
    }
    // ---- the dictionary card ----
    MouseArea {
        x: popup.x
        y: popup.y
        width: popup.visible ? popup.width : 0
        height: popup.visible ? popup.height : 0
        acceptedButtons: Qt.AllButtons
    }
    WordPopup {
        id: popup

        readonly property rect a: root.popAnchor
        readonly property real roomAbove: a.y - 20
        readonly property real roomBelow: root.height - (a.y + a.height) - 20
        readonly property bool flip: roomAbove < 300 && roomBelow > roomAbove

        canMine: false
        tok: root.popTok
        ctx: root.popCtx
        shown: root.popOpen
        pinned: root.popPinned
        below: flip
        width: 380
        maxBodyH: Math.max(120, Math.min(420, (flip ? roomBelow : roomAbove) - 260))
        x: Math.max(12, Math.min(a.x - width / 2 + a.width / 2, root.width - width - 12))
        y: flip ? a.y + a.height + 8 : a.y - height - 8

        onHoveredChanged: {
            if (hovered) {
                wordClose.stop();
                closeTimer.stop();
            } else if (!root.popPinned && root.popOpen)
                wordClose.restart();
        }
        onPinToggled: {
            if (root.popPinned)
                root.closeWord();
            else
                root.popPinned = true;
        }
        onKanjiOpened: root.popPinned = true
        onCloseRequested: root.closeWord()
        // another entry was chosen: the line is cut again; the simplest honest answer is to close
        onRetargetRequested: root.closeWord()
    }
}
