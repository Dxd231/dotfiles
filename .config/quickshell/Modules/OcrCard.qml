pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// What an OCR run is doing and found: a card at the bottom of the screen with the crop, the text
// (already on the clipboard and sent to the Texthooker UI), buttons to read the same crop with the
// other engine, and the last few results to copy again. It never takes keyboard focus, so a game
// keeps its input; it hides itself after a while unless the pointer is on it.
PanelWindow {
    id: win

    readonly property bool wanted: Ocr.phase === "warming" || Ocr.phase === "running" || Ocr.phase === "done" || Ocr.phase === "error"
    readonly property bool historyOpen: Ocr.historyOpen
    property bool copied: false

    anchors { bottom: true; left: true; right: true }
    // room for the dictionary card above the text
    implicitHeight: 900
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "quickshell:ocrcard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: wanted || card.appear > 0.01
    mask: Region {
        item: card
        Region { item: popMask }
    }

    // ---- dictionary lookups: the text is cut into words; resting on one opens its Yomitan card ----
    // opens ~150 ms after the pointer rests on a word, closes 500 ms after it leaves both word and card;
    // a click on a word (or the pin) keeps the card until a click elsewhere on the card
    property var toks: []
    property var hoverTok: null
    property var popTok: null
    property bool popOpen: false
    property bool popPinned: false
    property var _cand: null
    property var _pending: null
    property rect popAnchor: Qt.rect(0, 0, 0, 0)
    readonly property var lit: popOpen ? popTok : hoverTok

    property string _tokText: ""
    function retoken() {
        const text = Ocr.phase === "done" && Ocr.result ? Ocr.result.text : "";
        if (text === _tokText)
            return;
        _tokText = text;
        closeWord();
        toks = [];
        hoverTok = null;
        hoverEntry = null;
        if (text === "")
            return;
        Lexicon.segmentText(text, rows => {
            if (!Ocr.result || Ocr.result.text !== text)
                return;
            const out = [];
            let pos = 0;
            for (const row of rows) {
                for (const t of row) {
                    const i = text.indexOf(t.s, pos);
                    if (i < 0)
                        continue;
                    pos = i + t.s.length;
                    if (t.k === "word" && t.sound !== true)
                        out.push({ tok: t, a: i, b: pos });
                }
            }
            win.toks = out;
        });
    }
    function tokenAt(pos) {
        for (const e of toks) {
            if (pos >= e.a && pos < e.b)
                return e;
        }
        return null;
    }
    // the word under a point of the text box, if the point is on its glyphs
    function probe(p) {
        let hit = null;
        if (p && toks.length > 0) {
            let i = textEdit.positionAt(p.x, p.y);
            const r = textEdit.positionToRectangle(i);
            if (p.x < r.x)
                i--;
            const c = textEdit.positionToRectangle(Math.max(0, i));
            if (p.y >= c.y && p.y < c.y + c.height)
                hit = tokenAt(i);
        }
        if (hit === hoverEntry || (hit && hoverEntry && hit.a === hoverEntry.a))
            return;
        hoverEntry = hit;
        hoverTok = hit ? hit.tok : null;
        if (hit) {
            closeTimer.stop();
            if (!popPinned) {
                _cand = hit;
                openTimer.interval = popOpen ? 0 : 150;
                openTimer.restart();
            }
        } else {
            openTimer.stop();
            if (!popPinned && popOpen)
                closeTimer.restart();
        }
    }
    property var hoverEntry: null
    function showWord(e) {
        _pending = e;
        capTimer.restart();
        Lexicon.define(e.tok, () => {
            if (win._pending === e)
                win._commit(e);
        });
    }
    function _commit(e) {
        capTimer.stop();
        _pending = null;
        const r = textEdit.positionToRectangle(e.a);
        const m = textEdit.mapToItem(win.contentItem, r.x, r.y);
        popAnchor = Qt.rect(m.x, m.y, 0, r.height);
        popTok = e.tok;
        popOpen = true;
    }
    function closeWord() {
        capTimer.stop();
        openTimer.stop();
        closeTimer.stop();
        _pending = null;
        _cand = null;
        popOpen = false;
        popPinned = false;
    }
    Timer {
        id: openTimer
        onTriggered: if (win._cand) win.showWord(win._cand)
    }
    Timer {
        id: closeTimer
        interval: 500
        onTriggered: if (!popup.hovered) win.closeWord()
    }
    Timer {
        id: capTimer
        interval: 450
        onTriggered: if (win._pending) win._commit(win._pending)
    }
    Connections {
        target: Ocr
        function onResultChanged() { win.retoken(); }
        function onPhaseChanged() { win.retoken(); }
    }

    onWantedChanged: {
        copied = false;
        if (wanted) {
            hideTimer.restart();
        } else {
            hideTimer.stop();
            Ocr.historyOpen = false;
        }
    }
    Connections {
        target: Ocr
        function onPhaseChanged() {
            win.copied = false;
            if (Ocr.phase === "done" || Ocr.phase === "error")
                hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 12000
        onTriggered: {
            if (hover.hovered || win.historyOpen || win.popOpen)
                restart();
            else
                Ocr.dismiss();
        }
    }

    Elevation {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        level: 3
        opacity: card.opacity
        scale: card.scale
        transformOrigin: Item.Bottom
    }

    Rectangle {
        id: card
        width: 580
        property real h: body.implicitHeight + 32
        Behavior on h { Spring { speed: "default" } }
        height: Math.max(0, h)
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_high
        property real appear: win.wanted ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        y: win.height - height - 28 + (1 - appear) * 40
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.92 + 0.08 * appear
        transformOrigin: Item.Bottom

        HoverHandler { id: hover }
        TapHandler { onTapped: if (win.popPinned) win.closeWord() }

        ColumnLayout {
            id: body
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            // ---- header: crop, engine, status, close ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ClippingRectangle {
                    id: thumb
                    // as wide as the crop is, so a tall strip isn't cut to a sliver
                    property real w: thumb.rect ? Math.max(40, Math.min(168, 56 * thumb.rect[2] / Math.max(1, thumb.rect[3]))) : 96
                    Behavior on w { Spring { speed: "fast" } }
                    Layout.preferredWidth: Math.max(0, w)
                    Layout.preferredHeight: 56
                    radius: 14
                    color: Colors.surface_container_highest
                    readonly property var rect: Ocr.current ? Ocr.current.rect : null
                    Image {
                        anchors.fill: parent
                        opacity: thumb.rect ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        source: !!thumb.rect && Ocr.current ? "file://" + Ocr.current.path : ""
                        sourceClipRect: thumb.rect ? Qt.rect(thumb.rect[0], thumb.rect[1], thumb.rect[2], thumb.rect[3]) : Qt.rect(0, 0, 0, 0)
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        asynchronous: true
                    }
                    LoadingIndicator {
                        anchors.centerIn: parent
                        width: 40
                        height: 40
                        opacity: Ocr.phase === "warming" || Ocr.phase === "running" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        running: visible
                    }
                    Icon {
                        anchors.centerIn: parent
                        size: 24
                        opacity: !thumb.rect && Ocr.phase !== "warming" && Ocr.phase !== "running" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        name: Ocr.phase === "error" ? "error" : "crop_free"
                        color: Colors.on_surface_variant
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        role: "titleMedium"
                        emphasized: true
                        text: Ocr.phase === "warming" ? "Loading " + Ocr.engineLabel(Ocr.current ? Ocr.current.engine : "paddle") + "…"
                            : Ocr.phase === "running" ? "Reading…"
                            : Ocr.phase === "error" ? "Could not read"
                            : Ocr.result && Ocr.result.text === "" ? "No text found" : "Copied"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        role: "bodySmall"
                        color: Colors.on_surface_variant
                        elide: Text.ElideRight
                        text: {
                            if (Ocr.phase === "warming")
                                return "The first read after a while takes a few seconds";
                            if (Ocr.phase === "running" || Ocr.phase === "error")
                                return Ocr.phase === "error" ? Ocr.errorText : "";
                            if (!Ocr.result)
                                return "";
                            const dev = Ocr.result.engine === "manga" ? Ocr.mangaDevice : Ocr.paddleDevice;
                            return Ocr.engineLabel(Ocr.result.engine) + "  ·  " + Ocr.result.ms + " ms" + (dev ? "  ·  " + dev.toUpperCase() : "")
                                + (Ocr.hookerSent && Ocr.result.text !== "" ? "  ·  sent to texthooker" : "");
                        }
                    }
                }
                IconButton { icon: "close"; size: "xs"; onClicked: Ocr.dismiss() }
            }

            // ---- the text ----
            Collapse {
                open: Ocr.phase === "done" && !!Ocr.result && Ocr.result.text !== ""
                Layout.fillWidth: true
                Rectangle {
                    // whole lines only (at most four), so a line is never cut in half at the edge
                    implicitHeight: Math.max(64, Math.min(textEdit.contentHeight, 4 * textEdit.contentHeight / Math.max(1, textEdit.lineCount)) + 24)
                    radius: Motion.shapeLarge
                    color: Colors.surface_container
                    clip: true
                    Flickable {
                        id: textFlick
                        anchors.fill: parent
                        anchors.margins: 12
                        // the text wraps at the box's width and only scrolls vertically
                        contentWidth: width
                        contentHeight: textEdit.contentHeight
                        boundsBehavior: Flickable.StopAtBounds
                        flickableDirection: Flickable.VerticalFlick
                        clip: true
                        FontMetrics { id: fm; font: textEdit.font }
                        // the word under the pointer (or the open card) gets a tonal chip behind it
                        Repeater {
                            model: win.lit ? textEdit.litRects(win.lit) : []
                            Rectangle {
                                required property var modelData
                                x: modelData.x - 2
                                y: modelData.y
                                width: modelData.w + 4
                                height: modelData.h
                                radius: 8
                                color: win.popOpen ? Colors.secondary_container : Colors.surface_container_highest
                            }
                        }
                        TextEdit {
                            id: textEdit
                            // the rectangles a token covers: one per line it spans
                            function litRects(tok) {
                                const e = win.toks.find(t => t.tok === tok);
                                if (!e)
                                    return [];
                                const out = [];
                                for (let i = e.a; i < e.b; i++) {
                                    const r = positionToRectangle(i);
                                    const w = fm.advanceWidth(text.charAt(i));
                                    const last = out[out.length - 1];
                                    if (last && Math.abs(last.y - r.y) < 2)
                                        last.w = r.x + w - last.x;
                                    else
                                        out.push({ x: r.x, y: r.y, w: w, h: r.height });
                                }
                                return out;
                            }
                            width: textFlick.width
                            readOnly: true
                            selectByMouse: true
                            wrapMode: TextEdit.Wrap
                            color: Colors.on_surface
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.on_primary
                            font.family: Typography.familyJp
                            font.pixelSize: 22
                            font.weight: Font.Bold
                            text: Ocr.result ? Ocr.result.text : ""
                            HoverHandler {
                                onPointChanged: win.probe(point.position)
                                onHoveredChanged: if (!hovered) win.probe(null)
                            }
                            TapHandler {
                                onTapped: {
                                    if (win.hoverEntry) {
                                        win.popPinned = true;
                                        if (!win.popOpen || win.popTok !== win.hoverEntry.tok)
                                            win.showWord(win.hoverEntry);
                                    } else {
                                        win.closeWord();
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Collapse {
                open: Ocr.phase === "error"
                Layout.fillWidth: true
                Rectangle {
                    implicitHeight: errText.implicitHeight + 24
                    radius: Motion.shapeLarge
                    color: Colors.error_container
                    StyledText {
                        id: errText
                        anchors.fill: parent
                        anchors.margins: 12
                        role: "bodyMedium"
                        color: Colors.on_error_container
                        wrapMode: Text.WordWrap
                        text: Ocr.errorText
                    }
                }
            }

            // ---- re-read with the other engine, copy again, history ----
            Collapse {
                open: Ocr.phase === "done" || Ocr.phase === "error"
                Layout.fillWidth: true
                RowLayout {
                    spacing: 8
                    Chip {
                        kind: "filter"
                        text: "Manga"
                        selected: Ocr.current ? Ocr.current.engine === "manga" : false
                        enabled: !!Ocr.current && !Ocr.busy
                        onClicked: Ocr.rerun("manga")
                    }
                    Chip {
                        kind: "filter"
                        text: "General"
                        selected: Ocr.current ? Ocr.current.engine === "paddle" : false
                        enabled: !!Ocr.current && !Ocr.busy
                        onClicked: Ocr.rerun("paddle")
                    }
                    Item { Layout.fillWidth: true }
                    IconButton {
                        icon: "history"
                        style: "tonal"
                        size: "xs"
                        checkable: true
                        checked: win.historyOpen
                        enabled: Ocr.history.length > 0
                        onClicked: Ocr.historyOpen = !Ocr.historyOpen
                    }
                    Collapse {
                        horizontal: true
                        open: Ocr.phase === "done" && !!Ocr.result && Ocr.result.text !== ""
                        Button {
                            size: "xs"
                            style: "tonal"
                            icon: win.copied ? "check" : "content_copy"
                            text: win.copied ? "Copied" : "Copy"
                            onClicked: {
                                Ocr.copyText(Ocr.result.text);
                                win.copied = true;
                            }
                        }
                    }
                }
            }

            // ---- the last few results ----
            // the wrapper animates its height and clips, so rows can't spill out of the card while it
            // opens or closes; the card follows because its height is the layout's
            Item {
                id: historyWrap
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(0, historyWrap.shown)
                // a spring can undershoot zero, and a negative preferred height means "use the content's"
                property real shown: win.historyOpen ? historyList.implicitHeight : 0
                Behavior on shown { Spring { speed: "default" } }
                visible: historyWrap.shown > 0.5 || win.historyOpen
                clip: true
                opacity: win.historyOpen ? 1 : 0
                Behavior on opacity { Fade {} }
            ColumnLayout {
                id: historyList
                width: parent.width
                spacing: 2
                Repeater {
                    model: Math.min(5, Ocr.history.length)
                    delegate: Item {
                        id: hrow
                        required property int index
                        readonly property var h: Ocr.history[index]
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        HoverHandler { id: rowHover }
                        Rectangle {
                            anchors.fill: parent
                            radius: Motion.shapeMedium
                            color: rowHover.hovered ? Colors.surface_container_highest : "transparent"
                            Behavior on color { ColorFade {} }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            StyledText {
                                Layout.fillWidth: true
                                jp: true
                                role: "bodyLarge"
                                emphasized: true
                                elide: Text.ElideRight
                                text: hrow.h ? hrow.h.text.replace(/\n/g, " ") : ""
                            }
                            StyledText {
                                role: "labelSmall"
                                color: Colors.on_surface_variant
                                text: hrow.h ? (hrow.h.engine === "manga" ? "manga" : "general") + " · " + Qt.formatTime(new Date(hrow.h.ts), "HH:mm") : ""
                            }
                            Icon {
                                size: 18
                                name: "content_copy"
                                color: Colors.on_surface_variant
                                opacity: rowHover.hovered ? 1 : 0
                                Behavior on opacity { Fade {} }
                            }
                        }
                        TapHandler {
                            onTapped: {
                                if (hrow.h) {
                                    Ocr.copyText(hrow.h.text);
                                    if (Ocr.toast)
                                        Ocr.toast.showToast("Copied again");
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }

    // what the pointer can reach of the dictionary card
    Item {
        id: popMask
        x: popup.x
        y: popup.y
        width: popup.visible ? popup.width : 0
        height: popup.visible ? popup.height : 0
    }
    WordPopup {
        id: popup

        readonly property rect a: win.popAnchor
        readonly property real roomAbove: a.y - 20
        readonly property real roomBelow: win.height - (a.y + a.height) - 20
        // a card that cannot fit above the word goes below it
        readonly property bool flip: roomAbove < 300 && roomBelow > roomAbove

        lookupOnly: true
        tok: win.popTok
        ctx: null
        shown: win.popOpen
        pinned: win.popPinned
        below: flip
        width: 380
        maxBodyH: Math.max(120, Math.min(420, (flip ? roomBelow : roomAbove) - 260))
        x: Math.max(12, Math.min(a.x - width / 2, win.width - width - 12))
        y: flip ? a.y + a.height + 8 : a.y - height - 8

        onHoveredChanged: {
            if (hovered)
                closeTimer.stop();
            else if (!win.popPinned && win.popOpen)
                closeTimer.restart();
        }
        onPinToggled: {
            if (win.popPinned)
                win.closeWord();
            else
                win.popPinned = true;
        }
        onKanjiOpened: win.popPinned = true
        onCloseRequested: win.closeWord()
    }
}
