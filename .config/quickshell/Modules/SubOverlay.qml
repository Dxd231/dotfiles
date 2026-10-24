pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// The subtitle line of a fullscreen mpv, redrawn by the shell so its words can be hovered: unknown
// words are underlined in the tertiary colour, words being learned in the secondary one, known ones
// stay plain. mpv's own line is scaled away meanwhile (Lexicon.onOverlayOnChanged). One window per
// screen, shown only on mpv's monitor; the rest of the surface is click-through.
Scope {
    id: root

    // name of the monitor mpv is on
    property string mpvMonitor: ""

    // ---- the word card ----
    // opens ~120 ms after the pointer rests on a word (swapping to another line word after 380 ms), closes 600 ms
    // after it leaves both the word and the card; words under the card are ignored while it is hovered; a click pins it. Words of the live line pause playback while the
    // card is up, words of the transcript do not.
    property var popTok: null
    property string popFrom: ""
    property rect popAnchor: Qt.rect(0, 0, 0, 0)
    // the line the word came from, for mining: { prefix, suffix, flat, start (file time; -1 for the live line) }
    property var popCtx: null
    property bool popOpen: false
    property bool popPinned: false
    property var _cand: null
    property bool popHovered: false
    // after another meaning is chosen the line is cut again; the card follows its word to the new token
    property string _retarget: ""
    Connections {
        target: Lexicon
        function onRowsChanged() {
            const sf = root._retarget;
            if (sf === "" || !root.popOpen)
                return;
            root._retarget = "";
            const old = root.popCtx;
            for (const row of Lexicon.rows) {
                const i = row.findIndex(t => t.k === "word" && t.s === sf);
                if (i < 0)
                    continue;
                const j = row.map(t => t.s);
                const c = { prefix: j.slice(0, i).join(""), suffix: j.slice(i + 1).join(""), flat: old ? old.flat : "",
                            start: old ? old.start : -1, toks: row, index: i };
                root.popCtx = c;
                root.popTok = row[i];
                Lexicon.focusTok = row[i];
                Lexicon.focusCtx = c;
                return;
            }
            root.closeWord();
        }
    }

    // the card appears only once its dictionary entry is in, so it is placed for its final size and never
    // resizes or moves afterwards; a slow lookup gives up waiting after 450 ms and shows its spinner
    property var _pending: null
    function showWord(c) {
        _pending = c;
        capTimer.restart();
        if (c.from === "line")
            Lexicon.holdPause();
        else
            Lexicon.releasePause();
        Lexicon.define(c.tok, () => {
            if (root._pending === c)
                root._commit(c);
        });
    }
    // where the word is now: a word of the live line moves when ModernX lifts the line, so it is asked again
    function _anchorOf(c) {
        try {
            return c.fn ? c.fn() : c.anchor;
        } catch (e) {
            return c.anchor;
        }
    }
    property var popAnchorFn: null
    property var _swapC: null
    property bool _swapClaimed: false
    signal swapRequested(var apply)
    function _commit(c) {
        capTimer.stop();
        _pending = null;
        // the card is already up over another word: it fades out, changes unseen and fades back in
        if (popOpen && popTok && popTok.key !== c.tok.key) {
            _swapC = c;
            _swapClaimed = false;
            const apply = () => {
                if (root._swapC === c) {
                    root._swapC = null;
                    root._apply(c);
                }
            };
            swapRequested(apply);
            // no screen is showing the card: nothing to fade
            if (!_swapClaimed)
                apply();
            return;
        }
        _apply(c);
    }
    function _apply(c) {
        popTok = c.tok;
        popFrom = c.from;
        popAnchorFn = c.fn || null;
        popAnchor = _anchorOf(c);
        popCtx = c.ctx;
        Lexicon.recheck(c.tok);
        Lexicon.focusTok = c.tok;
        Lexicon.focusCtx = c.ctx;
        popOpen = true;
    }
    Timer {
        id: capTimer
        interval: 450
        onTriggered: if (root._pending) root._commit(root._pending)
    }
    function closeWord() {
        capTimer.stop();
        _pending = null;
        openTimer.stop();
        closeTimer.stop();
        _cand = null;
        _swapC = null;
        popOpen = false;
        popPinned = false;
        Lexicon.focusTok = null;
        Lexicon.releasePause();
    }
    // the word under the pointer: a leave that arrives after the next word was entered is stale
    property var _hoverTok: null
    function wordEnter(tok, from, anchor, ctx, fn) {
        _hoverTok = tok;
        // the pointer is on the card (it sits just above the line): words it brushes on the way must not steal it
        if (popHovered && popOpen && from === "line")
            return;
        if (!popOpen) {
            Lexicon.focusTok = tok;
            Lexicon.focusCtx = ctx;
        }
        if (popPinned)
            return;
        closeTimer.stop();
        const c = { tok: tok, from: from, anchor: anchor, ctx: ctx, fn: fn };
        // a card is already up over the line: a word the pointer merely crosses on its way to the card (the upper
        // line when the card belongs to the lower one) must not steal it, so switching waits for a real dwell
        // the transcript is a dense list the pointer sweeps across, so its words wait a little longer
        const same = popOpen && popTok && popTok.key === tok.key;
        openTimer.interval = same ? 0 : from === "panel" ? 300 : popOpen ? 380 : 120;
        _cand = c;
        openTimer.restart();
    }
    function wordLeave(tok) {
        if (_hoverTok && tok && _hoverTok.key !== tok.key)
            return;
        _hoverTok = null;
        openTimer.stop();
        _cand = null;
        if (!popOpen && !_pending)
            Lexicon.focusTok = null;
        if (popOpen && !popPinned) {
            if (!popHovered)
                closeTimer.restart();
        } else if (_pending && !popOpen)
            closeWord();
    }
    function wordClick(tok, from, anchor, ctx, fn) {
        if (popOpen && popPinned && popTok === tok) {
            closeWord();
            return;
        }
        openTimer.stop();
        closeTimer.stop();
        showWord({ tok: tok, from: from, anchor: anchor, ctx: ctx, fn: fn });
        popPinned = true;
    }
    Timer {
        id: openTimer
        interval: 120
        onTriggered: {
            // the line is still rising (or falling) with the OSC: wait until it has settled, then open at the word's new place
            if (root.lineMoving) {
                restart();
                return;
            }
            if (root._cand) {
                root.showWord(root._cand);
                root._cand = null;
            }
        }
    }
    Timer {
        id: closeTimer
        interval: 600
        onTriggered: if (!root.popHovered) root.closeWord()
    }
    // ModernX lifts mpv's subtitles (sub-pos) while its controls are up, and the line follows at once. It drops
    // back only once the pointer is off the line and the card, after a pause, so the line can be reached.
    property real effPos: Mpv.subPos
    // true while the line is travelling to a new height; the card waits for it and then follows it
    property bool lineMoving: false
    onEffPosChanged: {
        lineMoving = true;
        settleTimer.restart();
    }
    Timer {
        id: settleTimer
        interval: 450
        onTriggered: {
            root.lineMoving = false;
            if (root.popOpen && root.popFrom === "line" && root.popAnchorFn) {
                try { root.popAnchor = root.popAnchorFn(); } catch (e) {}
            }
        }
    }
    property bool lineHover: false
    readonly property bool lineHeld: lineHover || popOpen || _pending !== null || _cand !== null
    function settlePos() {
        if (!lineHeld)
            effPos = Mpv.subPos;
    }
    onLineHeldChanged: if (!lineHeld) retractTimer.restart()
    Connections {
        target: Mpv
        function onSubPosChanged() {
            if (Mpv.subPos <= root.effPos)
                root.effPos = Mpv.subPos;
            else
                retractTimer.restart();
        }
    }
    Timer {
        id: retractTimer
        interval: 700
        onTriggered: root.settlePos()
    }
    // the line moved on under an unpinned card, or the overlay went away (tabbed out, left fullscreen)
    Connections {
        target: Mpv
        function onSubRawChanged() { 
            const from = root._pending ? root._pending.from : root.popFrom;
            if ((root.popOpen || root._pending) && !root.popPinned && from === "line")
                root.closeWord();
        }
    }
    Connections {
        target: Lexicon
        function onOverlayOnChanged() { if (!Lexicon.overlayOn) root.closeWord(); }
    }

    function findMonitor() {
        Hyprland.refreshToplevels();
        const mine = x => x.lastIpcObject && x.lastIpcObject.class === "mpv";
        const t = Hyprland.toplevels.values.find(x => mine(x) && x.lastIpcObject.pid === Mpv.pid)
                  || Hyprland.toplevels.values.find(mine);
        const id = t ? t.lastIpcObject.monitor : -1;
        const m = Hyprland.monitors.values.find(x => x.id === id) || Hyprland.focusedMonitor;
        mpvMonitor = m ? m.name : "";
    }
    Timer {
        interval: 1000
        repeat: true
        triggeredOnStart: true
        running: Lexicon.overlayOn
        onTriggered: root.findMonitor()
    }

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: win

            required property var modelData
            screen: modelData

            // the picture inside the screen: mpv reports its window in physical pixels, with the black bars as margins
            readonly property var osd: Mpv.osdDims
            readonly property real ratio: osd.w > 0 ? width / osd.w : 1
            readonly property real vx: osd.ml * ratio
            readonly property real vy: osd.mt * ratio
            readonly property real vw: width - (osd.ml + osd.mr) * ratio
            readonly property real vh: height - (osd.mt + osd.mb) * ratio
            // mpv sizes subtitles in "scaled pixels" of a 720 px tall picture, and libass takes that size as the
            // line height (ascent + descent), so the em is that height divided by the font's own ratio
            readonly property real unit: vh / 720
            readonly property real lineH: Mpv.subFontSize * Mpv.subScale * unit
            readonly property string family: Mpv.subFont !== "" ? Mpv.subFont : Typography.familyJp
            readonly property real fontPx: Math.max(8, lineH * 100 / Math.max(1, metrics.height))
            readonly property real borderPx: Mpv.subBorder * Mpv.subScale * unit
            // where mpv puts the line's bottom edge: sub-pos from the top of the picture, minus sub-margin-y
            readonly property real bottomY: vy + vh - (100 - root.effPos) / 100 * vh - Mpv.subMarginY * unit

            FontMetrics {
                id: metrics
                font.family: win.family
                font.bold: Mpv.subBold
                font.pixelSize: 100
            }

            readonly property bool here: Lexicon.overlayOn && (root.mpvMonitor === "" || root.mpvMonitor === modelData.name)
            readonly property bool lineReady: Lexicon.rowsFor === Mpv.subRaw
            // until the helper has answered, the line is drawn plain so it never flickers away
            readonly property var plainRows: Mpv.subRaw.split("\n").map(l => [{ s: l.trim(), k: "func" }])
            readonly property var shown: lineReady ? Lexicon.rows : plainRows

            // the transcript panel (right edge) pushes the line to the left of it
            readonly property bool panelOn: Lexicon.panelOpen && here
            property real rightEdge: panelOn ? width - panel.width - 20 : vx + vw
            Behavior on rightEdge { Spring { speed: "default"; expressive: win.panelOn } }

            // resting on the right screen edge opens the panel; leaving it (and the card) closes it again
            readonly property bool hovering: zoneHover.hovered || panel.hovered || (popup.hovered && root.popFrom === "panel")
            onHoveringChanged: {
                if (!here)
                    return;
                if (hovering) {
                    leaveTimer.stop();
                    if (!Lexicon.panelOpen)
                        dwellTimer.restart();
                } else {
                    dwellTimer.stop();
                    if (Lexicon.panelOpen && !Lexicon.panelPinned)
                        leaveTimer.restart();
                }
            }
            Timer {
                id: dwellTimer
                interval: 200
                onTriggered: if (win.hovering && win.here) Lexicon.panelOpen = true
            }
            Timer {
                id: leaveTimer
                interval: 1200
                onTriggered: {
                    if (win.hovering || Lexicon.panelPinned)
                        return;
                    if (root.popOpen && root.popFrom === "panel") {
                        restart();
                        return;
                    }
                    Lexicon.panelOpen = false;
                }
            }

            anchors { top: true; bottom: true; left: true; right: true }
            exclusiveZone: -1
            color: "transparent"
            WlrLayershell.namespace: "quickshell:subs"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: Lexicon.panelSearch ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            visible: here
            // only what is drawn takes the pointer; a part that is away has no size, so mpv gets every click
            mask: Region {
                item: box
                Region { item: popupHit }
                Region { item: zone }
                Region { item: outside }
            }
            // while a card is pinned, a click anywhere else lets go of it (that click does not reach mpv)
            MouseArea {
                id: outside
                width: root.popOpen && root.popPinned && win.here ? win.width : 0
                height: root.popOpen && root.popPinned && win.here ? win.height : 0
                onPressed: m => {
                    const p = mapToItem(popup, m.x, m.y);
                    const inCard = p.x >= 0 && p.y >= 0 && p.x <= popup.width && p.y <= popup.height;
                    const inPanel = win.panelOn && m.x >= panel.x;
                    if (!inCard && !inPanel)
                        root.closeWord();
                }
            }
            Item {
                id: popupHit
                x: popup.x
                y: popup.y
                width: popup.visible ? popup.width : 0
                height: popup.visible ? popup.height : 0
            }
            // the right edge: a thin strip to rest on while the panel is shut, the panel and its margin once open
            Item {
                id: zone
                x: win.panelOn ? Math.min(panel.x, win.width - 4) : win.width - 4
                width: win.here ? Math.max(0, win.width - x) : 0
                height: win.here ? win.height : 0
                HoverHandler { id: zoneHover }
            }

            Item {
                id: box

                readonly property real pad: win.fontPx * 0.35
                width: lines.width * lines.scale + pad * 2
                height: lines.height + pad * 2
                x: win.vx + (win.rightEdge - win.vx - width) / 2
                y: win.bottomY - height + pad
                Behavior on y { Spring { speed: "default" } }
                // the top of the drawn text (a long line is shrunk from its bottom), which the card sits on
                readonly property real textTop: y + height - pad - lines.height * lines.scale
                opacity: Mpv.subLive ? 1 : 0
                HoverHandler { onHoveredChanged: root.lineHover = hovered }
                Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }

                Column {
                    id: lines

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: box.pad
                    spacing: 0
                    // a line wider than the room it has shrinks to fit
                    scale: implicitWidth > 0 ? Math.min(1, (win.rightEdge - win.vx) * 0.94 / implicitWidth) : 1
                    transformOrigin: Item.Bottom

                    Repeater {
                        model: win.shown

                        Row {
                            id: row

                            required property var modelData
                            anchors.horizontalCenter: parent.horizontalCenter

                            Repeater {
                                model: row.modelData

                                Item {
                                    id: word

                                    required property var modelData
                                    required property int index
                                    readonly property bool isWord: modelData.k === "word"
                                    readonly property string status: Lexicon.statusOf(modelData)
                                    function ctx() {
                                        const ts = row.modelData;
                                        const j = ts.map(t => t.s);
                                        return { prefix: j.slice(0, word.index).join(""), suffix: j.slice(word.index + 1).join(""),
                                                 flat: Mpv.subRaw.replace(/\s/g, ""), start: Mpv.subStart - Mpv.subDelay,
                                                 toks: ts, index: word.index };
                                    }
                                    // the word the open card belongs to keeps its pill
                                    readonly property bool active: root.popOpen && root.popFrom === "line" && root.popTok !== null && root.popTok.key === modelData.key
                                    function anchorRect() {
                                        const p = word.mapToItem(null, 0, 0);
                                        const q = word.mapToItem(null, word.width, word.height);
                                        return Qt.rect(p.x, p.y, q.x - p.x, q.y - p.y);
                                    }
                                    readonly property bool marked: isWord && (status === "unknown" || status === "learning")

                                    // readings (Alt+f): room is kept over every word while they are on, so the line never jumps
                                    readonly property string furi: Lexicon.furigana
                                    readonly property real rubyH: furi !== "off" ? win.fontPx * 0.66 : 0
                                    readonly property bool hasRuby: modelData.ruby !== undefined && (furi === "all" || (furi === "unknown" && marked))

                                    implicitWidth: label.implicitWidth
                                    implicitHeight: label.implicitHeight + rubyH

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -win.fontPx * 0.04
                                        radius: win.fontPx * 0.18
                                        color: Qt.rgba(1, 1, 1, 0.18)
                                        opacity: (hover.hovered || word.active) && word.isWord ? 1 : 0
                                        Behavior on opacity { NumberAnimation { duration: 90 } }
                                    }
                                    // mpv's shadow, then its outline (a ring of copies, as Qt's own outline is one pixel)
                                    Text {
                                        visible: Mpv.subShadowOffset > 0
                                        x: Mpv.subShadowOffset * Mpv.subScale * win.unit
                                        y: x + word.rubyH
                                        text: label.text
                                        color: Mpv.subShadowColor
                                        font: label.font
                                    }
                                    Repeater {
                                        model: win.borderPx > 0.3 ? 16 : 0

                                        Text {
                                            required property int index
                                            x: Math.cos(index * Math.PI / 8) * win.borderPx
                                            y: Math.sin(index * Math.PI / 8) * win.borderPx + word.rubyH
                                            text: label.text
                                            color: Mpv.subBorderColor
                                            font: label.font
                                        }
                                    }
                                    Row {
                                        visible: word.hasRuby
                                        y: 0
                                        Repeater {
                                            model: word.hasRuby ? word.modelData.ruby : []

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
                                                    color: Mpv.subColor
                                                    style: win.borderPx > 0.3 ? Text.Outline : Text.Normal
                                                    styleColor: Mpv.subBorderColor
                                                    font.family: win.family
                                                    font.bold: Mpv.subBold
                                                    font.pixelSize: win.fontPx * 0.55
                                                }
                                            }
                                        }
                                    }
                                    Text {
                                        id: label
                                        y: word.rubyH
                                        text: word.modelData.s
                                        color: Mpv.subColor
                                        font.family: win.family
                                        font.bold: Mpv.subBold
                                        font.pixelSize: win.fontPx
                                        font.letterSpacing: Mpv.subSpacing * win.unit
                                    }
                                    // a leech (many lapses) gets a wavy underline, any other marked word a straight one
                                    readonly property bool leech: status === "learning" && modelData.leech === true
                                    readonly property bool due: status === "learning" && modelData.due === true
                                    readonly property real ulH: Math.max(3, Math.round(win.fontPx * 0.075))
                                    Rectangle {
                                        opacity: word.marked && !word.leech ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -win.fontPx * 0.02
                                        anchors.leftMargin: win.fontPx * 0.04
                                        anchors.rightMargin: win.fontPx * 0.04
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
                                        anchors.bottomMargin: -win.fontPx * 0.02 - amplitude
                                        anchors.leftMargin: win.fontPx * 0.04
                                        anchors.rightMargin: win.fontPx * 0.04
                                        thickness: word.ulH
                                        amplitude: word.ulH * 0.5
                                        wavelength: win.fontPx * 0.32
                                        color: Colors.secondary
                                    }
                                    // due today: a dot at the top right, clear of the readings
                                    Rectangle {
                                        opacity: word.due ? 1 : 0
                                        scale: word.due ? 1 : 0.3
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        Behavior on scale { Spring { speed: "fast" } }
                                        x: parent.width - width * 0.6
                                        y: word.rubyH - height * 0.3
                                        width: Math.max(6, Math.round(win.fontPx * 0.13))
                                        height: width
                                        radius: width / 2
                                        color: Colors.secondary
                                    }
                                    HoverHandler {
                                        id: hover
                                        enabled: word.isWord
                                        cursorShape: Qt.PointingHandCursor
                                        onHoveredChanged: {
                                            if (hovered)
                                                root.wordEnter(word.modelData, "line", word.anchorRect(), word.ctx(), word.anchorRect);
                                            else
                                                root.wordLeave(word.modelData);
                                        }
                                    }
                                    TapHandler {
                                        enabled: word.isWord
                                        onTapped: root.wordClick(word.modelData, "line", word.anchorRect(), word.ctx(), word.anchorRect)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            SubTranscript {
                id: panel
                open: win.panelOn
                x: open ? win.width - width - 8 : win.width + 32
                y: 8
                height: win.height - 16
                visible: win.here && (open || opacity > 0.01)
                opacity: open ? 1 : 0
                Behavior on x { Spring { speed: "default"; expressive: panel.open } }
                Behavior on opacity { Fade { speed: "default" } }
                onWordEnter: (tok, a, c) => root.wordEnter(tok, "panel", a, c)
                onWordLeave: tok => root.wordLeave(tok)
                onWordClick: (tok, a, c) => root.wordClick(tok, "panel", a, c)
            }

            WordPopup {
                id: popup

                Connections {
                    target: root
                    function onSwapRequested(apply) {
                        if (!popup.visible)
                            return;
                        root._swapClaimed = true;
                        popup.swapTo(apply);
                    }
                }

                readonly property rect a: root.popAnchor
                readonly property bool fromPanel: root.popFrom === "panel"
                // line words: the card always sits on top of the whole subtitle block, whichever line the word is on
                readonly property real roomAbove: box.textTop - win.vy - 20

                tok: root.popTok
                ctx: root.popCtx
                onKanjiOpened: root.popPinned = true
                shown: root.popOpen && win.here
                pinned: root.popPinned
                below: false
                width: Math.min(380, Math.max(240, win.vw - 32))
                maxBodyH: Math.max(120, Math.min(420, (fromPanel ? win.height - 24 : roomAbove) - 260))
                x: fromPanel ? Math.max(12, panel.x - width - 12)
                             : Math.max(win.vx + 12, Math.min(a.x + a.width / 2 - width / 2, win.vx + win.vw - width - 12))
                y: fromPanel ? Math.max(12, Math.min(a.y + a.height / 2 - height / 2, win.height - height - 12))
                             : Math.max(win.vy + 12, box.textTop - height - 12)

                onPinToggled: {
                    if (root.popPinned)
                        root.closeWord();
                    else
                        root.popPinned = true;
                }
                onPicked: s => Lexicon.mark(popup.tok, s)
                onCloseRequested: root.closeWord()
                onRetargetRequested: surface => {
                    if (root.popFrom === "line")
                        root._retarget = surface;
                    else
                        root.closeWord();
                }
                onHoveredChanged: {
                    root.popHovered = hovered;
                    if (hovered) {
                        openTimer.stop();
                        root._cand = null;
                        closeTimer.stop();
                    } else if (root.popOpen && !root.popPinned)
                        closeTimer.restart();
                }
            }
        }
    }
}
