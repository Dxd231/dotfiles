pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.Components
import qs.Services

// The dictionary card for a subtitle word: headword with its reading and pitch contour, how common it is,
// how it was inflected, a status control and the glossaries from Yomitan. It is an item inside the subtitle
// overlay's window (SubOverlay places it above the word, or beside the transcript), not a window of its own.
//
// The header shows at once from the token; only the body waits for the dictionary. `h` is the height the
// card is springing to, so whatever places the card follows it as the content arrives.
Item {
    id: pop

    // the word: { s, term, reading, status, key }; a snapshot, so a pinned card keeps its word
    property var tok: null
    // the line the word came from (see SubOverlay.popCtx), for mining
    property var ctx: null
    property bool shown: false
    property bool pinned: false
    // growing downward from the word (the card was flipped below it)
    property bool below: false
    // the most the glossary may take before it scrolls
    property real maxBodyH: 360
    readonly property alias hovered: hover.hovered
    signal pinToggled()
    signal picked(string status)
    signal closeRequested()
    // the entry choice changed: the line is cut again, the card should follow the word to its new token
    signal retargetRequested(string surface)

    // "loading" | "ready" | "offline" | "none"
    property string phase: "loading"
    property var def: null
    property bool allDicts: false
    readonly property string status: Lexicon.statusOf(tok)
    readonly property string term: def ? def.term : (tok ? tok.term || tok.s : "")
    readonly property string reading: def ? def.reading : (tok ? tok.reading || "" : "")
    // a person's name (unidic), or a word the dictionary has nothing for: no status to set, nothing to mine
    readonly property bool isName: status === "name"
    // the OCR card's lookups: just the dictionary, no marks, mining, cutting or entry picks
    property bool lookupOnly: false
    // false where there is no subtitle line to mine from (the manga reader, for now): the mine row and its span editor stay hidden
    property bool canMine: true
    readonly property bool plain: lookupOnly || status === "name" || status === "none"
    readonly property bool hasKanji: /[㐀-鿿]/.test(term)
    readonly property var sections: def ? def.sections : []
    readonly property var shownSections: allDicts ? sections : sections.slice(0, 2)

    // ---- kanji: a click on a character of the headword shows its entry in place of the glossary ----
    property string kanjiChar: ""
    readonly property bool inKanji: kanjiChar !== ""
    signal kanjiOpened()
    // 0 = the word page, 1 = the kanji page: the whole card slides from one to the other
    property real kt: inKanji ? 1 : 0
    Behavior on kt { Spring { speed: "default"; expressive: false } }
    function openKanji(ch) {
        kanjiChar = ch;
        kanjiOpened();
    }

    property bool settled: false
    // a fresh show: the header, then the meanings, then the status picker come in one after another (3 = all in)
    property int stage: 3
    property bool _fresh: false
    Timer {
        id: stageTimer
        interval: 90
        repeat: true
        onTriggered: {
            pop.stage += 1;
            if (pop.stage >= 3)
                stop();
        }
    }
    // until it has settled the card lays out at once: sections snap open instead of easing, so it never grows after it shows
    readonly property bool still: !settled
    // the card keeps the word page's height: the kanji page fills it and scrolls
    readonly property real cardH: col.implicitHeight + 40
    // the card is sized for its content before it shows and does not animate afterwards, except when the
    // user expands the glossary
    property bool grow: false
    property real h: cardH
    Behavior on h { enabled: pop.grow || pop.settled; Spring { speed: "default" } }

    width: 380
    height: Math.max(0, h)

    // Qt draws list items 40 px in; a card reads better with plain bullet lines
    function tidy(html) {
        return html.split("\u2063|\u2063").join('<font color="' + Colors.outline + '">&nbsp;|&nbsp;</font>')
                   .replace(/<\/?(ul|ol)>/g, "").replace(/<li>/g, "• ").replace(/<\/li>/g, "<br>")
                   .replace(/(<br>\s*){2,}/g, "<br>").replace(/^(<br>\s*)+|(<br>\s*)+$/g, "");
    }

    function load(quiet) {
        const t = tok;
        if (!t)
            return;
        if (!quiet) {
            phase = "loading";
            def = null;
            allDicts = false;
        }
        Lexicon.define(t, r => {
            if (t !== pop.tok)
                return;
            if (r.error) {
                if (!quiet)
                    pop.phase = r.error === "yomitan-offline" ? "offline" : "none";
                return;
            }
            pop.def = r;
            pop.phase = "ready";
            if (pop.fadeOnDef) {
                pop.fadeOnDef = false;
                swap.restart();
            }
        });
    }
    // ---- the cut editor: the word and its neighbours letter by letter, a click on a gap toggles a cut ----
    property bool cutting: false
    property bool choosing: false
    readonly property var alts: def && def.alts ? def.alts : []
    property var cutLetters: []
    property var cutTokOf: []
    property var cutOrig: []
    property var cutOn: []
    property int cutFrom: 0
    property int cutTo: 0
    function startCut() {
        const ts = ctx && ctx.toks ? ctx.toks : [tok];
        const i = ctx && ctx.toks ? ctx.index : 0;
        const a = i > 0 && ts[i - 1].k !== "punct" ? i - 1 : i;
        const b = i < ts.length - 1 && ts[i + 1].k !== "punct" ? i + 1 : i;
        const letters = [], tokOf = [];
        let from = 0, to = 0;
        for (let j = a; j <= b; j++) {
            if (j === i)
                from = letters.length;
            for (const ch of Array.from(ts[j].s)) {
                letters.push(ch);
                tokOf.push(j - a);
            }
            if (j === i)
                to = letters.length;
        }
        const orig = [];
        for (let k = 0; k < letters.length - 1; k++)
            orig.push(tokOf[k] !== tokOf[k + 1]);
        cutLetters = letters;
        cutTokOf = tokOf;
        cutOrig = orig;
        cutOn = orig.slice();
        cutFrom = from;
        cutTo = to;
        cutting = true;
    }
    function toggleCut(k) {
        const o = cutOn.slice();
        o[k] = !o[k];
        cutOn = o;
    }
    readonly property bool cutChanged: cutOn.some((v, k) => v !== cutOrig[k])
    // only the tokens whose edges moved are re-cut; the rule is the text of that run and the pieces it becomes
    function saveCut() {
        let lo = -1, hi = -1;
        for (let k = 0; k < cutOn.length; k++) {
            if (cutOn[k] === cutOrig[k])
                continue;
            lo = lo < 0 ? cutTokOf[k] : Math.min(lo, cutTokOf[k]);
            hi = Math.max(hi, cutTokOf[k + 1]);
        }
        if (lo < 0) {
            cutting = false;
            return;
        }
        const first = cutTokOf.indexOf(lo), last = cutTokOf.lastIndexOf(hi);
        const parts = [];
        let cur = "";
        for (let k = first; k <= last; k++) {
            cur += cutLetters[k];
            if (k === last || cutOn[k]) {
                parts.push(cur);
                cur = "";
            }
        }
        Lexicon.setCut(cutLetters.slice(first, last + 1).join(""), parts, r => {
            pop.cutting = false;
            pop.closeRequested();
        });
    }

    // another meaning of the same word was chosen: the old entry stays up until the new one is in, then the
    // content fades in and the card eases to its new height instead of flashing the spinner
    property bool switching: false
    property bool fadeOnDef: false
    // ---- the sentence span (see spanBox) ----
    property var spanInfo: null
    property int spanA: 0
    property int spanB: 0
    // Mine was clicked and the sentence is up for a last look: Confirm adds the card
    property bool armed: false
    function loadSpan() {
        spanInfo = null;
        const t = tok, c = ctx;
        if (!t || !c)
            return;
        Lexicon.spanOf(t, c, r => {
            if (t !== pop.tok || c !== pop.ctx || !r)
                return;
            const mine = Lexicon.mineSpan[Lexicon.spanKey(t, c)];
            pop.spanA = mine ? Math.max(r.lines[0].i, Math.min(r.line, mine[0])) : r.auto[0];
            pop.spanB = mine ? Math.min(r.lines[r.lines.length - 1].i, Math.max(r.line, mine[1])) : r.auto[1];
            pop.spanInfo = r;
        });
    }
    function setSpan(a, b) {
        spanA = a;
        spanB = b;
        Lexicon.setSpan(tok, ctx, [a, b]);
    }
    onCtxChanged: {
        armed = false;
        Qt.callLater(loadSpan);
    }

    onTokChanged: {
        armed = false;
        Qt.callLater(loadSpan);
        cutting = false;
        kanjiChar = "";
        if (switching) {
            // the list of meanings stays open: shutting it here shrank the card, then the new entry resized it
            // again, which read as a jitter
            switching = false;
            fadeOnDef = true;
            grow = true;
            growOff.restart();
            load(true);
            return;
        }
        choosing = false;
        settled = false;
        settleTimer.restart();
        settleCap.restart();
        load(false);
        swap.restart();
    }
    onShownChanged: {
        if (shown) {
            // a fresh show stays unseen until the size has stopped changing, like a word swap
            swapIn.stop();
            stageTimer.stop();
            stage = 0;
            _fresh = true;
            dim = 0;
            _swapHeld = true;
            settled = false;
            settleTimer.restart();
            settleCap.restart();
        } else {
            swapFade.stop();
            swapIn.stop();
            settleCap.stop();
            _swapHeld = false;
            dim = 1;
            switching = false;
            fadeOnDef = false;
            settled = false;
            settleTimer.stop();
            stageTimer.stop();
            stage = 3;
            _fresh = false;
        }
    }
    Timer {
        id: growOff
        interval: 600
        onTriggered: pop.grow = false
    }
    Timer {
        id: settleTimer
        interval: 160
        onTriggered: pop.settled = true
    }
    // LibreWolf opened (or closed) since the card came up: ask again without flashing the spinner
    Timer {
        interval: 2500
        repeat: true
        running: pop.shown && pop.phase === "offline"
        onTriggered: pop.load(true)
    }
    // the content eases in again when the card moves to another word
    NumberAnimation {
        id: swap
        target: col
        property: "opacity"
        from: 0.25
        to: 1
        duration: Motion.medium1
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecelerate
    }

    // another word took the card: it fades out, takes the word while unseen (so the resize and move never show),
    // then fades back in
    property real dim: 1
    property var _applySwap: null
    function swapTo(apply) {
        _applySwap = apply;
        swapFade.restart();
    }
    // it stays unseen until the new word's card has stopped changing size, then fades in
    property bool _swapHeld: false
    SequentialAnimation {
        id: swapFade
        NumberAnimation { target: pop; property: "dim"; to: 0; duration: Motion.short2; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccelerate }
        ScriptAction {
            script: {
                pop.settled = false;
                pop._swapHeld = true;
                if (pop._applySwap)
                    pop._applySwap();
            }
        }
    }
    NumberAnimation {
        id: swapIn
        target: pop
        property: "dim"
        to: 1
        duration: Motion.short4
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.standardDecelerate
    }
    onSettledChanged: {
        if (settled && _swapHeld) {
            _swapHeld = false;
            swapIn.restart();
            if (_fresh) {
                _fresh = false;
                stage = 1;
                stageTimer.restart();
            }
        }
    }
    // the size is still moving: settling waits for it to stop, but not for ever
    onCardHChanged: if (!settled && shown) settleTimer.restart()
    Timer {
        id: settleCap
        interval: 450
        onTriggered: pop.settled = true
    }

    HoverHandler { id: hover }

    opacity: 0
    visible: shown || opacity > 0
    states: State {
        name: "open"
        when: pop.shown
        PropertyChanges { pop.opacity: 1 }
    }
    transitions: [
        Transition {
            to: "open"
            NumberAnimation { property: "opacity"; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardDecelerate }
        },
        Transition {
            from: "open"
            NumberAnimation { property: "opacity"; duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccelerate }
        }
    ]

    Elevation {
        anchors.fill: parent
        radius: card.radius
        level: 3
        opacity: pop.dim
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_high
        opacity: pop.dim
        clip: true

        ColumnLayout {
            id: col
            x: 20 - 32 * Math.min(1, pop.kt)
            y: 20
            width: card.width - 40
            spacing: 12
            opacity: Math.max(0, 1 - pop.kt * 1.6)
            visible: pop.kt < 0.99

            // ---- headword ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                opacity: pop.stage >= 1 ? 1 : 0
                Behavior on opacity { Fade {} }
                transform: Translate { y: pop.stage >= 1 ? 0 : 8; Behavior on y { Spring { speed: "default" } } }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        opacity: (pop.hasKanji && pop.reading !== "") ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        jp: true
                        role: "labelLarge"
                        emphasized: true
                        color: Colors.on_surface_variant
                        text: pop.reading
                    }
                    // a character at a time, so a kanji can be clicked for its own entry
                    Flow {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: Array.from(pop.term)
                            Rectangle {
                                id: glyph

                                required property string modelData
                                readonly property bool isKanji: /[㐀-鿿々]/.test(modelData)
                                readonly property bool current: isKanji && pop.kanjiChar === modelData
                                width: gl.implicitWidth + 4
                                height: gl.implicitHeight + 2
                                radius: 10
                                color: current ? Colors.secondary_container : (isKanji && glyphHover.hovered ? Colors.surface_container_highest : "transparent")
                                Behavior on color { ColorFade {} }
                                StyledText {
                                    id: gl
                                    anchors.centerIn: parent
                                    jp: true
                                    emphasized: true
                                    font.pixelSize: pop.term.length > 7 ? 26 : 34
                                    color: glyph.current ? Colors.on_secondary_container : Colors.on_surface
                                    text: glyph.modelData
                                }
                                HoverHandler {
                                    id: glyphHover
                                    enabled: glyph.isKanji
                                    cursorShape: Qt.PointingHandCursor
                                }
                                TapHandler {
                                    enabled: glyph.isKanji
                                    onTapped: {
                                        if (glyph.current)
                                            pop.kanjiChar = "";
                                        else
                                            pop.openKanji(glyph.modelData);
                                    }
                                }
                            }
                        }
                    }
                }
                IconButton {
                    Layout.alignment: Qt.AlignTop
                    size: "xs"
                    icon: "push_pin"
                    checkable: true
                    checked: pop.pinned
                    iconFilled: pop.pinned
                    onClicked: pop.pinToggled()
                }
            }

            // ---- pitch ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "ready" && pop.def !== null && pop.def.pitch.length > 0 && pop.reading !== ""
                Layout.fillWidth: true
                RowLayout {
                    spacing: 12
                    PitchGraph {
                        id: graph
                        animate: !pop.still
                        reading: pop.reading
                        pos: pop.def && pop.def.pitch.length > 0 ? pop.def.pitch[0] : -1
                        cell: 28
                        textSize: 16
                        Layout.maximumWidth: col.width - 70
                    }
                    InfoPill {
                        animate: !pop.still
                        visible: text !== ""
                        jp: true
                        text: graph.patternName
                        container: Colors.primary_container
                        content: Colors.on_primary_container
                    }
                    Item { Layout.fillWidth: true }
                }
            }

            // ---- how common, how inflected ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "ready" && pop.def !== null && (pop.def.freq > 0 || pop.def.uk === true || pop.def.chain.length > 0 || pop.def.auto)
                Layout.fillWidth: true
                Flow {
                    spacing: 6
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: pop.def !== null && pop.def.freq > 0
                        InfoPill {
                            animate: !pop.still
                            text: "#" + (pop.def ? pop.def.freq.toLocaleString(Qt.locale(), "f", 0) : "")
                            container: pop.def && pop.def.freq < 5000 ? Colors.primary_container : pop.def && pop.def.freq < 20000 ? Colors.secondary_container : Colors.surface_container_highest
                            content: pop.def && pop.def.freq < 5000 ? Colors.on_primary_container : pop.def && pop.def.freq < 20000 ? Colors.on_secondary_container : Colors.on_surface_variant
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: pop.def !== null && pop.def.uk === true
                        InfoPill {
                            animate: !pop.still
                            // Yomitan's "uk" tag: usually written in kana alone
                            text: "kana"
                            container: pop.def && pop.def.freq > 0 && pop.def.freq < 5000 ? Colors.primary_container : pop.def && pop.def.freq > 0 && pop.def.freq < 20000 ? Colors.secondary_container : Colors.surface_container_highest
                            content: pop.def && pop.def.freq > 0 && pop.def.freq < 5000 ? Colors.on_primary_container : pop.def && pop.def.freq > 0 && pop.def.freq < 20000 ? Colors.on_secondary_container : Colors.on_surface_variant
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: pop.def !== null && pop.def.auto === true && pop.status === "known"
                        InfoPill {
                            animate: !pop.still
                            // known only because it is a common word, not because of a card or a mark
                            text: "Common word"
                            container: Colors.primary_container
                            content: Colors.on_primary_container
                        }
                    }
                    Repeater {
                        model: pop.def ? pop.def.chain : []
                        InfoPill {
                            animate: !pop.still
                            required property string modelData
                            text: modelData
                            container: Colors.tertiary_container
                            content: Colors.on_tertiary_container
                        }
                    }
                }
            }

            // ---- the card behind a word being learned ----
            Flow {
                id: cardFacts
                Layout.fillWidth: true
                spacing: 6
                readonly property var t: pop.tok
                readonly property bool shown: !pop.cutting && !pop.plain && pop.status === "learning" && t !== null && t.ivl !== undefined
                visible: shown
                InfoPill {
                    animate: !pop.still
                    visible: cardFacts.shown && cardFacts.t.due === true
                    text: "Due today"
                    container: Colors.secondary
                    content: Colors.on_secondary
                }
                InfoPill {
                    animate: !pop.still
                    visible: cardFacts.shown && cardFacts.t.leech === true
                    text: "Leech · " + (cardFacts.t ? cardFacts.t.lapses : 0) + " lapses"
                    container: Colors.error_container
                    content: Colors.on_error_container
                }
                InfoPill {
                    animate: !pop.still
                    visible: cardFacts.shown
                    text: "Interval " + (cardFacts.t ? cardFacts.t.ivl : 0) + " / 21 d"
                    container: Colors.secondary_container
                    content: Colors.on_secondary_container
                }
            }

            // ---- status ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && !pop.plain
                Layout.fillWidth: true
                WordStatus {
                    opacity: pop.stage >= 3 ? 1 : 0
                    Behavior on opacity { Fade {} }
                    transform: Translate { y: pop.stage >= 3 ? 0 : 8; Behavior on y { Spring { speed: "default" } } }
                    animate: !pop.still
                    current: pop.status
                    onPicked: s => pop.picked(s)
                }
            }

            // ---- mine ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && !pop.plain && pop.canMine && pop.phase === "ready"
                Layout.fillWidth: true
                RowLayout {
                    id: mineRow

                    readonly property string st: pop.tok ? (Lexicon.mineState[pop.tok.term] || "") : ""
                    readonly property bool busy: st === "adding" || st === "finishing"
                    readonly property int lines: pop.tok ? (Lexicon.mineLines[pop.tok.term] || 1) : 1
                    spacing: 8

                    Button {
                        animate: !pop.still
                        Layout.fillWidth: true
                        style: (mineRow.st === "" && !pop.armed) || mineRow.st.startsWith("error") ? "filled" : "tonal"
                        icon: mineRow.st === "" && pop.armed ? "close" : mineRow.st === "" || mineRow.busy ? "add_card" : mineRow.st.startsWith("error") ? "refresh" : "check"
                        enabled: !mineRow.busy
                        text: mineRow.st === "adding" ? "Adding…" : mineRow.st === "finishing" ? "Adding audio and picture…"
                            : mineRow.st === "done" ? (mineRow.lines > 1 ? "Mined · " + mineRow.lines + " lines" : "Mined") : mineRow.st === "partial" ? "Added, no sentence audio"
                            : mineRow.st === "dup" ? "Already in Anki"
                            : mineRow.st === "error:yomitan-offline" ? "Open LibreWolf, then retry"
                            : mineRow.st.startsWith("error") ? "Couldn't add, retry" : pop.armed ? "Cancel" : "Mine"
                        onClicked: {
                            if (mineRow.st === "")
                                pop.armed = !pop.armed;
                            else if (mineRow.st.startsWith("error"))
                                Lexicon.mine(pop.tok, pop.ctx);
                            else
                                Lexicon.browse(pop.tok);
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: mineRow.st === "dup"
                        Button {
                            animate: !pop.still
                            style: "text"
                            text: "Replace card"
                            onClicked: Lexicon.mine(pop.tok, pop.ctx, true)
                        }
                    }
                }
            }

            // ---- the lines the sentence takes: shown once mined, adjustable afterwards (re-captures the card) ----
            ColumnLayout {
                id: spanBox

                readonly property var info: pop.spanInfo
                readonly property int line: info ? info.line : 0
                readonly property int selA: info ? pop.spanA : 0
                readonly property int selB: info ? pop.spanB : 0
                readonly property int lo: info ? info.lines[0].i : 0
                readonly property int hi: info ? info.lines[info.lines.length - 1].i : 0
                readonly property bool open: info !== null && !pop.cutting && !pop.plain && pop.canMine && pop.phase === "ready" && (mineRow.st !== "" || pop.armed)
                property real reveal: open ? 1 : 0
                Behavior on reveal { enabled: !pop.still; Spring { speed: "default"; expressive: false } }
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight * Math.max(0, reveal)
                Layout.topMargin: -12 * (1 - Math.min(1, Math.max(0, reveal)))
                visible: open || reveal > 0.01
                opacity: Math.min(1, Math.max(0, reveal))
                clip: true
                spacing: 4

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        text: "Sentence"
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        font.bold: true
                    }
                    Item { Layout.fillWidth: true }
                    StyledText {
                        text: "before"
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                    }
                    IconButton {
                        size: "xs"
                        icon: "remove"
                        enabled: spanBox.selA < spanBox.line
                        onClicked: pop.setSpan(spanBox.selA + 1, spanBox.selB)
                    }
                    IconButton {
                        size: "xs"
                        icon: "add"
                        enabled: spanBox.selA > spanBox.lo
                        onClicked: pop.setSpan(spanBox.selA - 1, spanBox.selB)
                    }
                    StyledText {
                        text: "after"
                        color: Colors.on_surface_variant
                        font.pixelSize: 12
                        Layout.leftMargin: 6
                    }
                    IconButton {
                        size: "xs"
                        icon: "remove"
                        enabled: spanBox.selB > spanBox.line
                        onClicked: pop.setSpan(spanBox.selA, spanBox.selB - 1)
                    }
                    IconButton {
                        size: "xs"
                        icon: "add"
                        enabled: spanBox.selB < spanBox.hi
                        onClicked: pop.setSpan(spanBox.selA, spanBox.selB + 1)
                    }
                }
                // every neighbouring cue is kept and springs in or out as the span grows or shrinks, so a line
                // that was already there doesn't replay; lines before the word slide down into place, lines after rise
                Repeater {
                    model: spanBox.info ? spanBox.info.lines : []
                    StyledText {
                        id: ln
                        required property var modelData
                        readonly property bool inSpan: modelData.i >= spanBox.selA && modelData.i <= spanBox.selB
                        property real r: inSpan ? 1 : 0
                        Behavior on r { enabled: !pop.still; Spring { speed: "default"; expressive: false } }
                        Layout.fillWidth: true
                        Layout.preferredHeight: implicitHeight * Math.max(0, r)
                        visible: r > 0.01
                        opacity: Math.min(1, Math.max(0, r))
                        clip: true
                        text: modelData.text
                        wrapMode: Text.Wrap
                        color: modelData.i === spanBox.line ? Colors.on_surface : Colors.on_surface_variant
                        font.pixelSize: 14
                        font.bold: modelData.i === spanBox.line
                        transform: Translate { y: (1 - ln.r) * (ln.modelData.i < spanBox.line ? -10 : 10) }
                    }
                }
                Collapse {
                    animate: !pop.still
                    open: mineRow.st === ""
                    Layout.fillWidth: true
                    Button {
                        icon: "check"
                        text: "Confirm"
                        onClicked: {
                            pop.armed = false;
                            Lexicon.mine(pop.tok, pop.ctx);
                        }
                    }
                }
            }

            // ---- name / cut ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && (!pop.lookupOnly || pop.phase === "ready")
                Layout.fillWidth: true
                Flow {
                    spacing: 6
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: pop.isName && !pop.lookupOnly
                        InfoPill {
                            animate: !pop.still
                            text: "Name"
                            container: Colors.secondary_container
                            content: Colors.on_secondary_container
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: !pop.lookupOnly
                        Button {
                            style: "text"
                            size: "xs"
                            icon: "badge"
                            text: pop.isName ? "Not a name" : "Name"
                            onClicked: {
                                Lexicon.setName(pop.tok, pop.isName ? 0 : 1);
                                pop.closeRequested();
                            }
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: !pop.lookupOnly
                        Button {
                            style: "text"
                            size: "xs"
                            icon: "content_cut"
                            text: "Fix cut"
                            onClicked: pop.startCut()
                        }
                    }
                    Collapse {
                        animate: !pop.still
                        horizontal: true
                        open: !pop.lookupOnly && pop.phase === "ready" && pop.alts.length > 1
                        Button {
                            style: pop.choosing ? "tonal" : "text"
                            size: "xs"
                            icon: "translate"
                            text: pop.alts.length + " meanings"
                            onClicked: pop.choosing = !pop.choosing
                        }
                    }
                    Button {
                        style: "text"
                        size: "xs"
                        icon: "menu_book"
                        text: "Jisho"
                        onClicked: Lexicon.lookupOnline(pop.tok)
                    }
                }
            }

            // ---- other dictionary entries for the same spelling ----
            ColumnLayout {
                id: altList

                readonly property bool open: !pop.cutting && pop.choosing && pop.alts.length > 1
                // opens and shuts by height and fade; the card follows the height frame by frame
                property real reveal: open ? 1 : 0
                Behavior on reveal { enabled: !pop.still; Spring { speed: "default"; expressive: false } }
                Layout.fillWidth: true
                Layout.preferredHeight: implicitHeight * Math.max(0, reveal)
                Layout.topMargin: -12 * (1 - Math.min(1, Math.max(0, reveal)))
                visible: open || reveal > 0.01
                opacity: Math.min(1, Math.max(0, reveal))
                clip: true
                spacing: 4
                Repeater {
                    model: pop.alts
                    Button {
                        id: alt

                        required property var modelData
                        readonly property bool current: modelData.term === pop.term && modelData.reading === pop.reading
                        Layout.fillWidth: true
                        style: current ? "tonal" : "text"
                        size: "xs"
                        text: modelData.term + (modelData.reading !== modelData.term ? "  " + modelData.reading : "") + (modelData.chain.length > 0 ? "  ·  " + modelData.chain.join(" ← ") : "")
                        onClicked: {
                            pop.switching = true;
                            pop.retargetRequested(pop.tok.s);
                            Lexicon.setPick(pop.tok, alt.modelData.term, alt.modelData.reading);
                        }
                    }
                }
                Button {
                    style: "text"
                    size: "xs"
                    icon: "refresh"
                    text: "Back to automatic"
                    onClicked: {
                        pop.switching = true;
                        pop.retargetRequested(pop.tok.s);
                        Lexicon.setPick(pop.tok, "", "");
                    }
                }
            }

            Collapse {
                animate: !pop.still
                open: pop.cutting
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 10
                    StyledText {
                        Layout.fillWidth: true
                        wrapMode: Text.WordWrap
                        role: "labelMedium"
                        color: Colors.on_surface_variant
                        text: "Click between letters to cut or join"
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: 0
                        Repeater {
                            model: pop.cutLetters
                            Row {
                                id: cell

                                required property string modelData
                                required property int index
                                readonly property bool inWord: index >= pop.cutFrom && index < pop.cutTo
                                readonly property bool last: index === pop.cutLetters.length - 1
                                StyledText {
                                    jp: true
                                    emphasized: cell.inWord
                                    font.pixelSize: 26
                                    color: cell.inWord ? Colors.primary : Colors.on_surface_variant
                                    text: cell.modelData
                                }
                                Item {
                                    visible: !cell.last
                                    width: 16
                                    height: 34
                                    readonly property bool on: pop.cutOn[cell.index] === true
                                    Rectangle {
                                        anchors.centerIn: parent
                                        width: 3
                                        height: parent.on ? 30 : gap.containsMouse ? 22 : 8
                                        radius: 1.5
                                        color: parent.on ? Colors.tertiary : Colors.outline_variant
                                        opacity: parent.on || gap.containsMouse ? 1 : 0.45
                                        Behavior on height { Spring { speed: "fast" } }
                                    }
                                    MouseArea {
                                        id: gap
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: pop.toggleCut(cell.index)
                                    }
                                }
                            }
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 8
                        Item { Layout.fillWidth: true }
                        Button {
                            style: "text"
                            text: "Cancel"
                            onClicked: pop.cutting = false
                        }
                        Button {
                            style: "filled"
                            enabled: pop.cutChanged
                            text: "Save cut"
                            onClicked: pop.saveCut()
                        }
                    }
                }
            }

            // ---- body ----
            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "loading"
                Layout.fillWidth: true
                Item {
                    implicitHeight: 72
                    LoadingIndicator {
                        anchors.centerIn: parent
                        running: pop.shown && pop.phase === "loading"
                    }
                }
            }

            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "offline"
                Layout.fillWidth: true
                ColumnLayout {
                    spacing: 10
                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "cloud_off"
                        size: 36
                        color: Colors.on_surface_variant
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        role: "titleSmall"
                        emphasized: true
                        text: "Open LibreWolf for definitions"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignHCenter
                        wrapMode: Text.WordWrap
                        color: Colors.on_surface_variant
                        text: "Dictionaries come from the Yomitan extension, which runs inside the browser."
                    }
                    Button {
                        Layout.alignment: Qt.AlignHCenter
                        style: "tonal"
                        icon: "open_in_new"
                        text: "Open LibreWolf"
                        onClicked: Quickshell.execDetached(["librewolf"])
                    }
                }
            }

            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "none"
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    color: Colors.on_surface_variant
                    text: "No dictionary entry for this word"
                }
            }

            Collapse {
                animate: !pop.still
                open: !pop.cutting && pop.phase === "ready" && pop.sections.length > 0
                Layout.fillWidth: true
                Item {
                    id: bodyWrap
                    opacity: pop.stage >= 2 ? 1 : 0
                    Behavior on opacity { Fade {} }
                    transform: Translate { y: pop.stage >= 2 ? 0 : 8; Behavior on y { Spring { speed: "default" } } }
                    implicitHeight: Math.min(sectionList.implicitHeight, pop.maxBodyH)

                    Flickable {
                        id: flick
                        anchors.fill: parent
                        contentWidth: width
                        contentHeight: sectionList.implicitHeight
                        clip: true
                        boundsBehavior: Flickable.StopAtBounds

                        Column {
                            id: sectionList
                            width: flick.width
                            spacing: 2

                            Repeater {
                                model: pop.shownSections

                                Rectangle {
                                    id: sec

                                    required property var modelData
                                    required property int index
                                    readonly property bool isFirst: index === 0
                                    readonly property bool isLast: index === pop.shownSections.length - 1 && (pop.allDicts || pop.sections.length <= 2)

                                    width: sectionList.width
                                    height: inner.implicitHeight + 24
                                    topLeftRadius: isFirst ? 20 : 4
                                    topRightRadius: topLeftRadius
                                    bottomLeftRadius: isLast ? 20 : 4
                                    bottomRightRadius: bottomLeftRadius
                                    color: Colors.surface_container_highest

                                    ColumnLayout {
                                        id: inner
                                        x: 16
                                        y: 12
                                        width: sec.width - 32
                                        spacing: 4
                                        StyledText {
                                            Layout.fillWidth: true
                                            role: "labelMedium"
                                            emphasized: true
                                            color: Colors.primary
                                            elide: Text.ElideRight
                                            text: sec.modelData.dict
                                        }
                                        Collapse {
                                            animate: !pop.still
                                            open: sec.modelData.tags.length > 0
                                            Layout.fillWidth: true
                                            Flow {
                                                spacing: 4
                                                Repeater {
                                                    model: sec.modelData.tags.slice(0, 5)
                                                    InfoPill {
                                                        animate: !pop.still
                                                        required property string modelData
                                                        text: modelData
                                                        container: Colors.secondary_container
                                                        content: Colors.on_secondary_container
                                                    }
                                                }
                                            }
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            jp: true
                                            wrapMode: Text.Wrap
                                            textFormat: Text.RichText
                                            text: pop.tidy(sec.modelData.html)
                                        }
                                    }
                                }
                            }

                            Button {
                                opacity: (!pop.allDicts && pop.sections.length > 2) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                style: "text"
                                size: "xs"
                                text: (pop.sections.length - 2) + " more " + (pop.sections.length - 2 === 1 ? "dictionary" : "dictionaries")
                                onClicked: {
                                    pop.grow = true;
                                    pop.allDicts = true;
                                    growOff.restart();
                                }
                            }
                        }
                    }

                    // a thin thumb while the glossary scrolls
                    Rectangle {
                        x: parent.width - width - 2
                        y: flick.visibleArea.yPosition * parent.height
                        width: 4
                        height: Math.max(16, flick.visibleArea.heightRatio * parent.height)
                        radius: 2
                        color: Colors.on_surface_variant
                        opacity: flick.moving && flick.visibleArea.heightRatio < 1 ? 0.5 : 0
                        Behavior on opacity { Fade { speed: "default" } }
                    }
                }
            }
        }

        // the kanji's own page: takes the whole card, Back slides the word page in again
        KanjiView {
            id: kview
            x: 20 + 32 * (1 - Math.min(1, pop.kt))
            y: 20
            width: card.width - 40
            height: card.height - 40
            opacity: Math.max(0, pop.kt * 1.6 - 0.6)
            visible: pop.kt > 0.01
            shown: pop.inKanji
            ch: pop.kanjiChar
            onCloseRequested: pop.kanjiChar = ""
        }
    }
}
