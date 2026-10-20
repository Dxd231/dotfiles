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
    // "all" | "new" (lines with an unknown word) | "plus" (exactly one: i+1)
    property string filter: "all"
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
            if (filter === "all" || (filter === "new" && u > 0) || (filter === "plus" && u === 1))
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

            // ---- how much of it you know ----
            Row {
                id: tiles
                Layout.fillWidth: true
                spacing: 2
                readonly property var items: [
                    { v: Lexicon.stats.pct !== undefined ? Math.round(Lexicon.stats.pct) + "%" : "–", t: "known", c: Colors.primary_container, on: Colors.on_primary_container },
                    { v: Lexicon.stats.newWords !== undefined ? String(Lexicon.stats.newWords) : "–", t: "new words", c: Colors.tertiary_container, on: Colors.on_tertiary_container },
                    { v: Lexicon.stats.plusOne !== undefined ? String(Lexicon.stats.plusOne) : "–", t: "i+1 lines", c: Colors.secondary_container, on: Colors.on_secondary_container }
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
                                pixelSize: 24
                                text: tile.modelData.v
                                color: tile.modelData.on
                            }
                            StyledText {
                                anchors.horizontalCenter: parent.horizontalCenter
                                role: "labelMedium"
                                emphasized: true
                                color: tile.modelData.on
                                text: tile.modelData.t
                            }
                        }
                    }
                }
            }

            // ---- filter ----
            Row {
                Layout.leftMargin: 2
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
                    position: "last"
                    text: "i+1"
                    selected: tr.filter === "plus"
                    onClicked: tr.filter = "plus"
                }
            }

            // ---- lines ----
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true

                ListView {
                    id: list
                    anchors.fill: parent
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
                            visible: line.rec !== null && line.rec.unk === 1
                            x: line.width - 26
                            y: 10
                            width: 14
                            height: 14
                            shapeRest: 7
                            shapeActive: 7
                            color: Colors.tertiary
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
                                    Rectangle {
                                        visible: w.marked
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        anchors.bottomMargin: 1
                                        height: 3
                                        radius: 1.5
                                        color: w.st === "learning" ? Colors.secondary : Colors.tertiary
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
                    readonly property bool want: !tr.follow && tr.curPos >= 0
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
                    visible: Lexicon.transcript.length === 0 && (Lexicon.transcriptBusy || (Lexicon.subPath() !== "" && !Lexicon.ready))
                    running: visible && tr.open
                }
                ImmersionEmpty {
                    anchors.centerIn: parent
                    width: parent.width - 32
                    visible: Lexicon.transcript.length === 0 && !Lexicon.transcriptBusy && !(Lexicon.subPath() !== "" && !Lexicon.ready)
                    active: visible && tr.open
                    accent: "secondary"
                    icon: "subtitles_off"
                    title: "No transcript yet"
                    text: "This needs a subtitle file next to the video. Press Alt+j to fetch one from Jimaku."
                }
                StyledText {
                    anchors.centerIn: parent
                    visible: Lexicon.transcript.length > 0 && tr.idx.length === 0
                    color: Colors.on_surface_variant
                    text: "No lines match this filter"
                }
            }
        }
    }
}
