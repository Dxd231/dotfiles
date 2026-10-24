pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components
import qs.Services

// Every line of the episode's subtitles, with the words coloured by how well they are known, in a card on
// the right edge of the video (an item inside the subtitle overlay's window; SubOverlay slides it in).
// The current line is marked and followed; click a line to jump there, hover a word for its card. It
// never pauses playback.
Item {
    id: tr

    property bool open: false
    // "lines" (the transcript) | "words" (everything being learned)
    property string mode: "lines"
    // "all" | "new" (lines with an unknown word) | "plus" (exactly one: i+1) | "review" (nothing new, one word being learned)
    property string filter: "all"
    // order of the Words page: "here" (in this episode first) | "due" | "leech" | "recent"
    property string sort: "here"
    // the Words search: kanji, kana (either script) or romaji
    property string query: ""
    // the view keeps the current line centred until the user scrolls away
    property bool follow: true
    readonly property alias hovered: panelHover.hovered
    signal wordEnter(var tok, rect anchor, var ctx)
    signal wordLeave(var tok)
    signal wordClick(var tok, rect anchor, var ctx)

    width: 400

    // positions of the lines the filter lets through, as indices into Lexicon.transcript
    readonly property var idx: {
        const a = Lexicon.transcript;
        const out = [];
        for (let i = 0; i < a.length; i++) {
            const u = a[i].unk;
            if (filter === "all" || (filter === "new" && u > 0) || (filter === "plus" && u === 1)
                    || (filter === "review" && u === 0 && a[i].lrn === 1))
                out.push(i);
        }
        return out;
    }
    // the shown line that is playing now (or the last one before it, when the filter hides the playing one)
    readonly property int curPos: {
        const c = Lexicon.currentIndex;
        const a = idx;
        let lo = 0, hi = a.length - 1, best = -1;
        while (lo <= hi) {
            const mid = (lo + hi) >> 1;
            if (a[mid] <= c) {
                best = mid;
                lo = mid + 1;
            } else {
                hi = mid - 1;
            }
        }
        return best;
    }
    readonly property bool curExact: curPos >= 0 && idx[curPos] === Lexicon.currentIndex

    // ---- search matching ----
    function hira(t) {
        let o = "";
        for (const ch of t) {
            const c = ch.codePointAt(0);
            o += c >= 0x30a1 && c <= 0x30f6 ? String.fromCodePoint(c - 0x60) : ch;
        }
        return o;
    }
    readonly property var _kana: {
        const m = { "ya": "や", "yu": "ゆ", "yo": "よ", "wa": "わ", "wo": "を", "shi": "し", "chi": "ち", "tsu": "つ", "fu": "ふ", "ji": "じ",
                    "sha": "しゃ", "shu": "しゅ", "sho": "しょ", "she": "しぇ", "cha": "ちゃ", "chu": "ちゅ", "cho": "ちょ", "che": "ちぇ",
                    "ja": "じゃ", "ju": "じゅ", "jo": "じょ", "je": "じぇ", "tsa": "つぁ", "fa": "ふぁ", "fi": "ふぃ", "fe": "ふぇ", "fo": "ふぉ" };
        const rows = { "": "あいうえお", k: "かきくけこ", s: "さしすせそ", t: "たちつてと", n: "なにぬねの", h: "はひふへほ", m: "まみむめも",
                       r: "らりるれろ", g: "がぎぐげご", z: "ざじずぜぞ", d: "だぢづでど", b: "ばびぶべぼ", p: "ぱぴぷぺぽ" };
        const small = { a: "ゃ", u: "ゅ", o: "ょ" };
        for (const c in rows) {
            for (let i = 0; i < 5; i++)
                m[c + "aiueo"[i]] = rows[c][i];
            if (c !== "")
                for (const v in small)
                    m[c + "y" + v] = rows[c][1] + small[v];
        }
        return m;
    }
    // romaji → hiragana, forgiving: a half-typed ending ("kaz") is dropped so it still finds かざす
    function romaji(t) {
        const s = t.toLowerCase().replace(/[\s']/g, "");
        let o = "";
        for (let i = 0; i < s.length;) {
            const c = s[i];
            if (c === "-") { o += "ー"; i++; continue; }
            if (!/[a-z]/.test(c)) { o += c; i++; continue; }
            if (c === s[i + 1] && !"aiueon".includes(c)) { o += "っ"; i++; continue; }
            let hit = "";
            for (let n = 3; n >= 1 && hit === ""; n--)
                if (i + n <= s.length && _kana[s.substr(i, n)] !== undefined) {
                    hit = _kana[s.substr(i, n)];
                    i += n;
                }
            if (hit !== "") { o += hit; continue; }
            if (c === "n" && i + 1 < s.length) { o += "ん"; i++; continue; }
            i++;
        }
        return o;
    }
    function searchHit(w, q, hq, rq) {
        const rd = hira(w.reading || "");
        return w.term.toLowerCase().includes(q) || hira(w.term).includes(hq) || rd.includes(hq) || (rq !== "" && rd.includes(rq));
    }

    // the words being learned, in the chosen order; searching adds the words marked by hand
    readonly property var words: {
        const k = sort;
        const q = query.trim().toLowerCase();
        let a = Lexicon.learningList.slice();
        a.sort((x, y) => (k === "due" ? (y.due - x.due) || (y.lapses - x.lapses)
                        : k === "leech" ? (y.lapses - x.lapses) || (y.due - x.due)
                        : k === "recent" ? y.note - x.note
                        : (y.here - x.here) || (y.due - x.due) || (y.lapses - x.lapses)) || (x.term < y.term ? -1 : 1));
        if (q === "")
            return a;
        const hq = hira(q);
        const rq = /^[\x20-\x7e]+$/.test(q) ? romaji(q) : "";
        a = a.concat(Lexicon.markedList).filter(w => searchHit(w, q, hq, rq));
        const front = a.filter(w => hira(w.reading || "").startsWith(hq) || w.term.startsWith(q) || (rq !== "" && hira(w.reading || "").startsWith(rq)));
        return front.concat(a.filter(w => front.indexOf(w) < 0));
    }
    // where a word comes up next: the first line after the playing one that has it, else the first in the file
    function nextWith(term) {
        const a = Lexicon.transcript;
        const has = r => r.toks.some(t => t.k === "word" && t.term === term);
        for (let i = Lexicon.currentIndex + 1; i < a.length; i++)
            if (has(a[i]))
                return a[i];
        return a.find(has) || null;
    }

    function clock(t) {
        const s = Math.max(0, Math.floor(t + Mpv.subDelay));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    onCurPosChanged: if (follow && open && curPos >= 0) glide(curPos)
    onOpenChanged: {
        if (open) {
            follow = true;
            Qt.callLater(() => tr.jump(tr.curPos));
        }
    }
    onFilterChanged: {
        follow = true;
        Qt.callLater(() => tr.jump(tr.curPos));
    }

    function jump(pos) {
        if (pos < 0 || pos >= list.count)
            return;
        scroll.stop();
        list.cancelFlick();
        list.positionViewAtIndex(pos, ListView.Center);
    }
    function glide(pos) {
        if (pos < 0 || pos >= list.count)
            return;
        list.cancelFlick();
        const from = list.contentY;
        list.positionViewAtIndex(pos, ListView.Center);
        const to = list.contentY;
        list.contentY = from;
        if (Math.abs(to - from) < 1) {
            list.contentY = to;
            return;
        }
        scroll.stop();
        scroll.from = from;
        scroll.to = to;
        scroll.restart();
    }
    NumberAnimation {
        id: scroll
        target: list
        property: "contentY"
        duration: Motion.medium4
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecelerate
    }

    Elevation {
        anchors.fill: parent
        radius: card.radius
        level: 3
    }

    Rectangle {
        id: card
        anchors.fill: parent
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container
        clip: true

        HoverHandler { id: panelHover }

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 12

            // ---- title ----
            ColumnLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                spacing: 0
                StyledText {
                    Layout.fillWidth: true
                    jp: true
                    role: "titleMedium"
                    emphasized: true
                    elide: Text.ElideRight
                    text: Mpv.title !== "" ? Mpv.title : "Subtitles"
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "labelMedium"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    text: Lexicon.transcript.length > 0 ? Lexicon.transcript.length + " lines" : "Transcript"
                }
            }

            // ---- how much of it you know: a ring split known / learning / unknown, and three counts ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8

                Item {
                    id: ringBox
                    Layout.preferredWidth: 84
                    Layout.preferredHeight: 84
                    readonly property bool has: Lexicon.stats.pct !== undefined
                    WavyRing {
                        anchors.fill: parent
                        thickness: 7
                        amplitude: 1.6
                        waves: 11
                        gap: 22
                        waving: tr.open
                        idleDrift: 0.5
                        value: ringBox.has ? Lexicon.stats.pct / 100 : 0
                        secondValue: ringBox.has ? (Lexicon.stats.learnPct || 0) / 100 : 0
                        activeColor: Colors.primary
                        secondColor: Colors.secondary
                        trackColor: Colors.tertiary_container
                    }
                    RollingDigits {
                        anchors.centerIn: parent
                        pixelSize: 20
                        text: ringBox.has ? Math.round(Lexicon.stats.pct) + "%" : "–"
                        color: Colors.on_surface
                    }
                }

                Row {
                    id: tiles
                    Layout.fillWidth: true
                    spacing: 2
                    readonly property var items: [
                        { v: Lexicon.stats.newWords !== undefined ? String(Lexicon.stats.newWords) : "–", t: "new words", c: Colors.tertiary_container, on: Colors.on_tertiary_container },
                        { v: Lexicon.stats.plusOne !== undefined ? String(Lexicon.stats.plusOne) : "–", t: "i+1 lines", c: Colors.secondary_container, on: Colors.on_secondary_container },
                        { v: Lexicon.stats.learning !== undefined ? String(Lexicon.stats.learning) : "–", t: "learning", c: Colors.secondary_container, on: Colors.on_secondary_container }
                    ]
                    Repeater {
                        model: tiles.items
                        Rectangle {
                            id: tile
                            required property var modelData
                            required property int index
                            width: Math.max(0, (tiles.width - 4) / 3)
                            height: 64
                            topLeftRadius: index === 0 ? 24 : 6
                            bottomLeftRadius: topLeftRadius
                            topRightRadius: index === 2 ? 24 : 6
                            bottomRightRadius: topRightRadius
                            color: modelData.c
                            Column {
                                anchors.centerIn: parent
                                spacing: 0
                                RollingDigits {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    pixelSize: 22
                                    text: tile.modelData.v
                                    color: tile.modelData.on
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    role: "labelSmall"
                                    emphasized: true
                                    color: tile.modelData.on
                                    text: tile.modelData.t
                                }
                            }
                        }
                    }
                }
            }

            // ---- lines or words, and pausing on lines to review ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Row {
                    Layout.leftMargin: 2
                    spacing: 2
                    ConnectedButton {
                        position: "first"
                        text: "Lines"
                        selected: tr.mode === "lines"
                        onClicked: tr.mode = "lines"
                    }
                    ConnectedButton {
                        position: "last"
                        text: "Words"
                        selected: tr.mode === "words"
                        onClicked: {
                            tr.mode = "words";
                            Lexicon.loadLearning();
                        }
                    }
                }
                Item { Layout.fillWidth: true }
                // Alt+r: pause at the end of a line that has a word due today or a leech
                StyledText {
                    role: "labelMedium"
                    emphasized: true
                    color: Colors.on_surface_variant
                    text: "Pause to review"
                }
                Switch {
                    checked: Lexicon.reviewPause
                    showIcons: false
                    scale: 0.8
                    onToggled: Lexicon.setReviewPause(!Lexicon.reviewPause)
                }
            }

            // ---- filter (lines) / order (words) ----
            Collapse {
                open: tr.mode === "lines"
                Layout.leftMargin: 2
                Row {
                    spacing: 2
                    ConnectedButton {
                        position: "first"
                        text: "All"
                        selected: tr.filter === "all"
                        onClicked: tr.filter = "all"
                    }
                    ConnectedButton {
                        position: "middle"
                        text: "New words"
                        selected: tr.filter === "new"
                        onClicked: tr.filter = "new"
                    }
                    ConnectedButton {
                        position: "middle"
                        text: "i+1"
                        selected: tr.filter === "plus"
                        onClicked: tr.filter = "plus"
                    }
                    ConnectedButton {
                        position: "last"
                        text: "Review"
                        selected: tr.filter === "review"
                        onClicked: tr.filter = "review"
                    }
                }
            }
            Collapse {
                open: tr.mode === "words"
                Layout.leftMargin: 2
                Row {
                    spacing: 2
                    Repeater {
                        model: [{ k: "here", t: "Here" }, { k: "due", t: "Due" }, { k: "leech", t: "Leeches" }, { k: "recent", t: "Recent" }]
                        ConnectedButton {
                            required property var modelData
                            required property int index
                            position: index === 0 ? "first" : index === 3 ? "last" : "middle"
                            text: modelData.t
                            selected: tr.sort === modelData.k
                            onClicked: tr.sort = modelData.k
                        }
                    }
                }
            }

            Binding {
                target: Lexicon
                property: "panelSearch"
                value: tr.mode === "words" && Lexicon.panelOpen
            }
            Collapse {
                open: tr.mode === "words"
                Layout.fillWidth: true
                TextField {
                    id: search
                    implicitHeight: 48
                    label: "Search words"
                    leadingIcon: "search"
                    text: tr.query
                    onEdited: t => tr.query = t
                    onAccepted: t => search.input.focus = false
                    // Esc lets go of the keyboard first, then empties the field
                    Keys.onEscapePressed: {
                        if (search.input.activeFocus)
                            search.input.focus = false;
                        else
                            tr.query = "";
                    }
                    IconButton {
                        opacity: tr.query !== "" ? 1 : 0
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.right: parent.right
                        anchors.rightMargin: 4
                        size: "xs"
                        icon: "close"
                        onClicked: tr.query = ""
                    }
                }
            }

            // ---- lines ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
                    opacity: tr.mode === "lines" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    clip: true
                    spacing: 2
                    model: tr.idx.length
                    boundsBehavior: Flickable.StopAtBounds
                    onMovementStarted: tr.follow = false

                    // one tonal blob that glides from the playing line to the next
                    property real markY: 0
                    property real markH: 40
                    property bool markSet: false
                    Rectangle {
                        parent: list.contentItem
                        z: -1
                        width: list.width
                        y: list.markY
                        height: Math.max(0, list.markH)
                        radius: Math.min(height / 2, 20)
                        color: Colors.secondary_container
                        opacity: tr.curExact && list.markSet ? 1 : 0
                        Behavior on opacity { Fade { speed: "default" } }
                        Behavior on y { enabled: list.markSet; Spring {} }
                        Behavior on height { enabled: list.markSet; Spring {} }
                    }

                    delegate: Item {
                        id: line

                        required property int index
                        readonly property int ti: index < tr.idx.length ? tr.idx[index] : -1
                        readonly property var rec: ti >= 0 && ti < Lexicon.transcript.length ? Lexicon.transcript[ti] : null
                        readonly property bool cur: tr.curExact && tr.curPos === index

                        width: list.width
                        height: Math.max(48, flow.implicitHeight + 20)

                        function publish() {
                            if (!cur)
                                return;
                            list.markY = y;
                            list.markH = height;
                            list.markSet = true;
                        }
                        onCurChanged: publish()
                        onYChanged: publish()
                        onHeightChanged: publish()
                        Component.onCompleted: publish()

                        Rectangle {
                            anchors.fill: parent
                            radius: Math.min(height / 2, 20)
                            color: Colors.on_surface
                            opacity: seek.containsMouse && !line.cur ? Motion.stateHover : 0
                            Behavior on opacity { Fade {} }
                        }
                        MouseArea {
                            id: seek
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: if (line.rec) Mpv.seekTo(line.rec.start + Mpv.subDelay)
                        }

                        StyledText {
                            x: 14
                            y: 12
                            width: 36
                            role: "labelSmall"
                            emphasized: true
                            color: line.cur ? Colors.on_secondary_container : Colors.on_surface_variant
                            text: line.rec ? tr.clock(line.rec.start) : ""
                        }
                        // a line with a single unknown word is the best one to learn from
                        ShapeBadge {
                            opacity: (line.rec !== null && line.rec.unk === 1) ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            x: line.width - 26
                            y: 10
                            width: 14
                            height: 14
                            shapeRest: "star4"
                            shapeActive: "star4"
                            color: Colors.tertiary
                        }

                        // a word on this line is due today or a leech
                        Rectangle {
                            opacity: (line.rec !== null && line.rec.flag === true) ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            x: line.width - 23
                            y: 30
                            width: 8
                            height: 8
                            radius: 4
                            color: Colors.secondary
                        }

                        Flow {
                            id: flow
                            x: 54
                            y: 10
                            width: line.width - 54 - 30
                            Repeater {
                                model: line.rec ? line.rec.toks : []

                                Item {
                                    id: w

                                    required property var modelData
                                    required property int index
                                    readonly property bool isWord: modelData.k === "word"
                                    // the line around the word, and where it is in the file, for mining
                                    function ctx() {
                                        const j = line.rec ? line.rec.toks.map(t => t.s) : [];
                                        return { prefix: j.slice(0, w.index).join(""), suffix: j.slice(w.index + 1).join(""),
                                                 flat: j.join("").replace(/\s/g, ""), start: line.rec ? line.rec.start : -1,
                                                 toks: line.rec ? line.rec.toks : [], index: w.index };
                                    }
                                    readonly property string st: Lexicon.statusOf(modelData)
                                    readonly property bool marked: isWord && (st === "unknown" || st === "learning")

                                    implicitWidth: label.implicitWidth
                                    implicitHeight: label.implicitHeight + 2

                                    Rectangle {
                                        anchors.fill: parent
                                        anchors.margins: -1
                                        radius: 6
                                        color: line.cur ? Colors.on_secondary_container : Colors.on_surface
                                        opacity: wordMouse.containsMouse ? 0.14 : 0
                                        Behavior on opacity { Fade {} }
                                    }
                                    StyledText {
                                        id: label
                                        jp: true
                                        emphasized: true
                                        font.pixelSize: 17
                                        color: line.cur ? Colors.on_secondary_container : Colors.on_surface
                                        text: w.modelData.s
                                    }
                                    readonly property bool leech: st === "learning" && modelData.leech === true
                                    readonly property bool due: st === "learning" && modelData.due === true
                                    Rectangle {
                                        opacity: (w.marked && !w.leech) ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 1
                                        height: 3
                                        radius: 1.5
                                        color: w.st === "learning" ? Colors.secondary : Colors.tertiary
                                    }
                                    WavyUnderline {
                                        opacity: w.leech ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: -1
                                        thickness: 3
                                        amplitude: 1.3
                                        wavelength: 7
                                        color: Colors.secondary
                                    }
                                    Rectangle {
                                        opacity: w.due ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        x: parent.width - 2
                                        y: -2
                                        width: 5
                                        height: 5
                                        radius: 2.5
                                        color: Colors.secondary
                                    }
                                    MouseArea {
                                        id: wordMouse
                                        anchors.fill: parent
                                        enabled: w.isWord
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        function rect() {
                                            const p = w.mapToItem(null, 0, 0);
                                            return Qt.rect(p.x, p.y, w.width, w.height);
                                        }
                                        onEntered: tr.wordEnter(w.modelData, rect(), w.ctx())
                                        onExited: tr.wordLeave(w.modelData)
                                        onClicked: tr.wordClick(w.modelData, rect(), w.ctx())
                                    }
                                }
                            }
                        }
                    }
                }

                // jumps back to the playing line after the user has scrolled away
                Button {
                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.bottom: parent.bottom
                    anchors.bottomMargin: 8
                    size: "xs"
                    style: "filled"
                    icon: "my_location"
                    text: "Now"
                    readonly property bool want: tr.mode === "lines" && !tr.follow && tr.curPos >= 0
                    opacity: want ? 1 : 0
                    scale: want ? 1 : 0.8
                    visible: opacity > 0.01
                    enabled: want
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on scale { Spring { speed: "fast" } }
                    onClicked: {
                        tr.follow = true;
                        tr.glide(tr.curPos);
                    }
                }

                // nothing to list yet
                LoadingIndicator {
                    anchors.centerIn: parent
                    opacity: (tr.mode === "lines" && Lexicon.transcript.length === 0 && (Lexicon.transcriptBusy || (Lexicon.subPath() !== "" && !Lexicon.ready))) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    running: visible && tr.open
                }
                ImmersionEmpty {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    opacity: (tr.mode === "lines" && Lexicon.transcript.length === 0 && !Lexicon.transcriptBusy && !(Lexicon.subPath() !== "" && !Lexicon.ready)) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    active: visible && tr.open
                    accent: "secondary"
                    icon: "subtitles_off"
                    title: "No transcript yet"
                    text: "This needs a subtitle file next to the video. Press Alt+j to fetch one from Jimaku."
                }
                StyledText {
                    anchors.centerIn: parent
                    opacity: (tr.mode === "lines" && Lexicon.transcript.length > 0 && tr.idx.length === 0) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    color: Colors.on_surface_variant
                    text: tr.filter === "review" ? "No line with exactly one word being learned" : "No lines match this filter"
                }

                // ---- the words being learned ----
                ListView {
                    id: wlist
                    anchors.fill: parent
                    opacity: tr.mode === "words" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    clip: true
                    spacing: 2
                    model: tr.words
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: wr
                        required property var modelData
                        required property int index
                        width: wlist.width
                        height: 52
                        readonly property bool hot: wm.containsMouse || known.hovered || anki.hovered
                        // a word the user marked by hand (found by searching) carries its mark in `status`
                        readonly property bool marked: modelData.status !== undefined
                        // the same token the subtitle line would hand to the card, so it opens the same way
                        readonly property var tok: ({ s: modelData.term, k: "word", term: modelData.term, reading: modelData.reading,
                                                      key: modelData.term + "|" + modelData.reading, base: modelData.term, rank: 0, freq: 0,
                                                      status: marked ? modelData.status : "learning", due: modelData.due, leech: modelData.leech,
                                                      ivl: modelData.ivl, lapses: modelData.lapses })
                        function rect() {
                            const p = wr.mapToItem(null, 0, 0);
                            return Qt.rect(p.x, p.y, wr.width, wr.height);
                        }
                        // the next line the word is in (where the row's click seeks to): the card mines from it and offers its sentence
                        readonly property var rec: modelData.here > 0 ? tr.nextWith(modelData.term) : null
                        readonly property int at: rec ? rec.toks.findIndex(t => t.k === "word" && t.term === modelData.term) : -1
                        function cardTok() { return at >= 0 ? Object.assign({}, tok, { s: rec.toks[at].s }) : tok; }
                        function ctx() {
                            if (at < 0)
                                return { prefix: "", suffix: "", flat: modelData.term, start: -1, toks: [tok], index: 0 };
                            const j = rec.toks.map(t => t.s);
                            return { prefix: j.slice(0, at).join(""), suffix: j.slice(at + 1).join(""),
                                     flat: j.join("").replace(/\s/g, ""), start: rec.start, toks: rec.toks, index: at };
                        }

                        Rectangle {
                            anchors.fill: parent
                            radius: 20
                            color: Colors.on_surface
                            opacity: wr.hot ? Motion.stateHover : 0
                            Behavior on opacity { Fade {} }
                        }
                        MouseArea {
                            id: wm
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onEntered: tr.wordEnter(wr.cardTok(), wr.rect(), wr.ctx())
                            onExited: tr.wordLeave(wr.tok)
                            onClicked: {
                                if (wr.rec)
                                    Mpv.seekTo(wr.rec.start + Mpv.subDelay);
                                else
                                    tr.wordClick(wr.cardTok(), wr.rect(), wr.ctx());
                            }
                        }

                        // how far the card is on its way to the 21 days that make a word known
                        Rectangle {
                            opacity: wr.marked ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            radius: 15
                            color: wr.modelData.status === "known" ? Colors.primary_container
                                 : wr.modelData.status === "unknown" ? Colors.tertiary_container : Colors.surface_container_highest
                            Icon {
                                anchors.centerIn: parent
                                size: 18
                                name: wr.modelData.status === "known" ? "check" : wr.modelData.status === "unknown" ? "help" : "visibility_off"
                                color: wr.modelData.status === "known" ? Colors.on_primary_container
                                     : wr.modelData.status === "unknown" ? Colors.on_tertiary_container : Colors.on_surface_variant
                            }
                        }
                        WavyRing {
                            opacity: !wr.marked ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            x: 12
                            anchors.verticalCenter: parent.verticalCenter
                            width: 30
                            height: 30
                            thickness: 3.5
                            amplitude: 0.8
                            waves: 7
                            gap: 30
                            value: Math.min(1, wr.modelData.ivl / 21)
                            activeColor: wr.modelData.leech ? Colors.error : Colors.secondary
                            trackColor: Colors.secondary_container
                        }
                        Column {
                            x: 54
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 54 - 76
                            spacing: 0
                            Item {
                                width: parent.width
                                height: termText.implicitHeight + 3
                                StyledText {
                                    id: termText
                                    jp: true
                                    emphasized: true
                                    font.pixelSize: 17
                                    color: Colors.on_surface
                                    text: wr.modelData.term
                                }
                                WavyUnderline {
                                    opacity: wr.modelData.leech ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    x: 0
                                    anchors.bottom: parent.bottom
                                    width: termText.implicitWidth
                                    thickness: 3
                                    amplitude: 1.2
                                    wavelength: 7
                                    color: Colors.secondary
                                }
                                Rectangle {
                                    opacity: wr.modelData.due ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    x: termText.implicitWidth + 2
                                    y: 2
                                    width: 6
                                    height: 6
                                    radius: 3
                                    color: Colors.secondary
                                }
                            }
                            StyledText {
                                width: parent.width
                                role: "labelSmall"
                                color: Colors.on_surface_variant
                                elide: Text.ElideRight
                                text: {
                                    const m = wr.modelData;
                                    const bits = [];
                                    if (m.reading !== "" && m.reading !== m.term)
                                        bits.push(m.reading);
                                    if (m.here > 0)
                                        bits.push("×" + m.here + " here");
                                    if (wr.marked)
                                        bits.push("marked " + m.status);
                                    else if (m.source === "manual")
                                        bits.push("marked");
                                    else
                                        bits.push(m.ivl + " d" + (m.lapses > 0 ? " · " + m.lapses + " lapses" : ""));
                                    return bits.join(" · ");
                                }
                            }
                        }
                        Row {
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            anchors.verticalCenter: parent.verticalCenter
                            IconButton {
                                id: known
                                size: "xs"
                                icon: wr.marked ? "undo" : "check"
                                // a mark of your own is undone (back to what Anki says), a learning word is marked known
                                onClicked: Lexicon.mark(wr.tok, wr.marked ? "clear" : "known")
                            }
                            IconButton {
                                id: anki
                                size: "xs"
                                icon: "open_in_new"
                                enabled: wr.modelData.note > 0
                                onClicked: Lexicon.browseNote(wr.modelData.note)
                            }
                        }
                    }
                }
                StyledText {
                    anchors.centerIn: parent
                    opacity: (tr.mode === "words" && tr.words.length === 0) ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    color: Colors.on_surface_variant
                    text: Lexicon.learningBusy ? "Loading…" : tr.query.trim() !== "" ? "No word matches “" + tr.query.trim() + "”" : "Nothing being learned yet"
                }
            }
        }
    }
}
