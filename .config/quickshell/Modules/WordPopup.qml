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

    // "loading" | "ready" | "offline" | "none"
    property string phase: "loading"
    property var def: null
    property bool allDicts: false
    readonly property string status: Lexicon.statusOf(tok)
    readonly property string term: def ? def.term : (tok ? tok.term || tok.s : "")
    readonly property string reading: def ? def.reading : (tok ? tok.reading || "" : "")
    // a person's name (unidic), or a word the dictionary has nothing for: no status to set, nothing to mine
    readonly property bool isName: status === "name"
    readonly property bool plain: status === "name" || status === "none"
    readonly property bool hasKanji: /[㐀-鿿]/.test(term)
    readonly property var sections: def ? def.sections : []
    readonly property var shownSections: allDicts ? sections : sections.slice(0, 2)

    property bool settled: false
    readonly property real cardH: col.implicitHeight + 40
    // the card is sized for its content before it shows and does not animate afterwards, except when the
    // user expands the glossary
    property bool grow: false
    property real h: cardH
    Behavior on h { enabled: pop.grow; Spring { speed: "default" } }

    width: 380
    height: Math.max(0, h)

    // Qt draws list items 40 px in; a card reads better with plain bullet lines
    function tidy(html) {
        return html.replace(/<\/?(ul|ol)>/g, "").replace(/<li>/g, "• ").replace(/<\/li>/g, "<br>")
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
        });
    }
    // ---- the cut editor: the word and its neighbours letter by letter, a click on a gap toggles a cut ----
    property bool cutting: false
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

    onTokChanged: {
        cutting = false;
        load(false);
        swap.restart();
    }
    onShownChanged: {
        if (shown) {
            settleTimer.restart();
        } else {
            settled = false;
            settleTimer.stop();
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

    HoverHandler { id: hover }

    opacity: 0
    scale: 0.92
    transformOrigin: below ? Item.Top : Item.Bottom
    visible: shown || opacity > 0
    states: State {
        name: "open"
        when: pop.shown
        PropertyChanges { pop.opacity: 1; pop.scale: 1 }
    }
    transitions: [
        Transition {
            to: "open"
            Spring { property: "scale"; speed: "default" }
            Fade { property: "opacity"; speed: "default" }
        },
        Transition {
            from: "open"
            NumberAnimation { property: "scale"; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
            NumberAnimation { property: "opacity"; duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccelerate }
        }
    ]

    Elevation {
        anchors.fill: parent
        radius: card.radius
        level: 3
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_high
        clip: true

        ColumnLayout {
            id: col
            x: 20
            y: 20
            width: card.width - 40
            spacing: 12

            // ---- headword ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.alignment: Qt.AlignLeft
                        visible: pop.hasKanji && pop.reading !== ""
                        jp: true
                        role: "labelLarge"
                        emphasized: true
                        color: Colors.on_surface_variant
                        text: pop.reading
                    }
                    StyledText {
                        Layout.fillWidth: true
                        jp: true
                        emphasized: true
                        font.pixelSize: pop.term.length > 7 ? 26 : 34
                        elide: Text.ElideRight
                        text: pop.term
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
            RowLayout {
                Layout.fillWidth: true
                visible: !pop.cutting && pop.phase === "ready" && pop.def !== null && pop.def.pitch.length > 0 && pop.reading !== ""
                spacing: 12
                PitchGraph {
                    id: graph
                    reading: pop.reading
                    pos: pop.def && pop.def.pitch.length > 0 ? pop.def.pitch[0] : -1
                    cell: 28
                    textSize: 16
                    Layout.maximumWidth: col.width - 70
                }
                InfoPill {
                    visible: text !== ""
                    jp: true
                    text: graph.patternName
                    container: Colors.primary_container
                    content: Colors.on_primary_container
                }
                Item { Layout.fillWidth: true }
            }

            // ---- how common, how inflected ----
            Flow {
                Layout.fillWidth: true
                spacing: 6
                visible: !pop.cutting && pop.phase === "ready" && pop.def !== null && (pop.def.freq > 0 || pop.def.chain.length > 0 || pop.def.auto)
                InfoPill {
                    visible: pop.def !== null && pop.def.freq > 0
                    text: "#" + (pop.def ? pop.def.freq.toLocaleString(Qt.locale(), "f", 0) : "")
                    container: pop.def && pop.def.freq < 5000 ? Colors.primary_container : pop.def && pop.def.freq < 20000 ? Colors.secondary_container : Colors.surface_container_highest
                    content: pop.def && pop.def.freq < 5000 ? Colors.on_primary_container : pop.def && pop.def.freq < 20000 ? Colors.on_secondary_container : Colors.on_surface_variant
                }
                InfoPill {
                    // known only because it is a common word, not because of a card or a mark
                    visible: pop.def !== null && pop.def.auto === true && pop.status === "known"
                    text: "Common word"
                    container: Colors.primary_container
                    content: Colors.on_primary_container
                }
                Repeater {
                    model: pop.def ? pop.def.chain : []
                    InfoPill {
                        required property string modelData
                        text: modelData
                        container: Colors.tertiary_container
                        content: Colors.on_tertiary_container
                    }
                }
            }

            // ---- status ----
            WordStatus {
                visible: !pop.cutting && !pop.plain
                Layout.fillWidth: true
                current: pop.status
                onPicked: s => pop.picked(s)
            }

            // ---- mine ----
            RowLayout {
                id: mineRow

                readonly property string st: pop.tok ? (Lexicon.mineState[pop.tok.term] || "") : ""
                readonly property bool busy: st === "adding" || st === "finishing"
                readonly property int lines: pop.tok ? (Lexicon.mineLines[pop.tok.term] || 1) : 1
                Layout.fillWidth: true
                visible: !pop.cutting && !pop.plain && pop.phase === "ready"
                spacing: 8

                Button {
                    Layout.fillWidth: true
                    style: mineRow.st === "" || mineRow.st.startsWith("error") ? "filled" : "tonal"
                    icon: mineRow.st === "" || mineRow.busy ? "add_card" : mineRow.st.startsWith("error") ? "refresh" : "check"
                    enabled: !mineRow.busy && mineRow.st !== "partial"
                    text: mineRow.st === "adding" ? "Adding…" : mineRow.st === "finishing" ? "Adding audio and picture…"
                        : mineRow.st === "done" ? (mineRow.lines > 1 ? "Mined · " + mineRow.lines + " lines" : "Mined") : mineRow.st === "partial" ? "Added, no sentence audio"
                        : mineRow.st === "dup" ? "Already in Anki"
                        : mineRow.st === "error:yomitan-offline" ? "Open LibreWolf, then retry"
                        : mineRow.st.startsWith("error") ? "Couldn't add, retry" : "Mine"
                    onClicked: {
                        if (mineRow.st === "" || mineRow.st.startsWith("error"))
                            Lexicon.mine(pop.tok, pop.ctx);
                    }
                }
                Button {
                    visible: mineRow.st === "dup"
                    style: "text"
                    text: "Add anyway"
                    onClicked: Lexicon.mine(pop.tok, pop.ctx, true)
                }
            }

            // ---- name / cut ----
            Flow {
                Layout.fillWidth: true
                visible: !pop.cutting
                spacing: 6
                InfoPill {
                    visible: pop.isName
                    text: "Name"
                    container: Colors.secondary_container
                    content: Colors.on_secondary_container
                }
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
                Button {
                    style: "text"
                    size: "xs"
                    icon: "content_cut"
                    text: "Fix cut"
                    onClicked: pop.startCut()
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: pop.cutting
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

            // ---- body ----
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 72
                visible: !pop.cutting && pop.phase === "loading"
                LoadingIndicator {
                    anchors.centerIn: parent
                    running: pop.shown && pop.phase === "loading"
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                visible: !pop.cutting && pop.phase === "offline"
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

            StyledText {
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                visible: !pop.cutting && pop.phase === "none"
                horizontalAlignment: Text.AlignHCenter
                color: Colors.on_surface_variant
                text: "No dictionary entry for this word"
            }

            Item {
                id: bodyWrap
                Layout.fillWidth: true
                Layout.preferredHeight: Math.min(sectionList.implicitHeight, pop.maxBodyH)
                visible: !pop.cutting && pop.phase === "ready" && pop.sections.length > 0

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
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: sec.modelData.tags.length > 0
                                        role: "labelSmall"
                                        color: Colors.on_surface_variant
                                        elide: Text.ElideRight
                                        text: sec.modelData.tags.slice(0, 5).join("  ·  ")
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
                            visible: !pop.allDicts && pop.sections.length > 2
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
}
