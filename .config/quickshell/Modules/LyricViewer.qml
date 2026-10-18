pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import qs
import qs.Components

Item {
    id: root

    property var player: null
    property bool hasPlayer: player !== null && player !== undefined
    readonly property bool isPlaying: hasPlayer && player && player.playbackState === MprisPlaybackState.Playing

    property real currentPlayPosition: (hasPlayer && player) ? player.position : 0
    property real lastMprisPos: 0
    property real lastMprisTime: 0

    property var lines: []
    readonly property bool hasLyrics: lines && lines.length > 0
    property string source: ""
    property bool synced: true
    property bool loading: false
    property string currentTrackKey: ""
    // what the running fetch was started for; its answer is dropped if the track has moved on
    property string fetchTitle: ""
    property string fetchArtist: ""
    property int activeIndex: -1
    // true for a moment after new lyrics arrive, so their lines animate in
    property bool entering: false
    onLinesChanged: {
        entering = lines && lines.length > 0;
        enterTimer.restart();
    }
    Timer {
        id: enterTimer
        interval: 900
        onTriggered: root.entering = false
    }
    property bool userScrolling: false
    property real timingOffset: 0.0

    signal lyricsDetected(bool detected)

    readonly property real fadeAmount: 0.16

    clip: true

    // Process to run the Spicetify lyrics fetcher (LRCLIB + NetEase)
    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                let found = false;
                try {
                    const data = JSON.parse(text);
                    // a killed or superseded fetch can still deliver its output after a newer one started
                    if (data && (data.title !== root.fetchTitle || data.artist !== root.fetchArtist))
                        return;
                    root.loading = false;
                    if (data && data.success && data.lines && data.lines.length > 0) {
                        const filtered = data.lines.filter(l => l && l.text && !root.isCreditLine(l.text, l.time));
                        root.lines = root.addInterludeDots(filtered);
                        root.source = data.source || "LRCLIB";
                        root.synced = data.synced !== false;
                        found = root.lines.length > 0;
                    } else {
                        root.lines = [];
                        root.source = "";
                    }
                } catch (e) {
                    // empty output: the process was stopped for a newer fetch (which keeps the pane as it is)
                    // or it crashed
                    if (fetchProc.running)
                        return;
                    root.loading = false;
                    root.lines = [];
                    root.source = "";
                }
                root.updateActiveIndex();
                root.lyricsDetected(found);
            }
        }
    }

    function isCreditLine(text, time) {
        if (!text) return true;
        const t = text.trim();
        // CJK role words and "<role> by" are credits even without a colon; bare English words need one.
        const re = /^(?:(?:作?[词詞曲]|编[曲劇]|編[曲劇]|制作|製作|監[制製]|和声|コーラス|录音|録音|混音|ミキシング|マスタリング|演唱|歌手|歌|唄|演奏|吉他|ギター|贝斯|ベース|鼓|ドラム|键盘|キーボード|钢琴|ピアノ|弦乐|ストリングス|歌[词詞][提製制]供?|字幕|翻[译譯])(?:\s*[:：・･·]|\s)|(?:Written|Produced|Arranged|Composed|Lyrics|Music|Vocals?|Mixed|Mastered|Recorded|Performed|Translated)\s+by\b|(?:Written|Produced|Arranged|Composed|Lyrics|Music|Vocals?|Mixed|Mastered|Recorded|Performed|Guitar|Bass|Drums|Piano|Keyboard|Strings|Artist|Title|Album|Track|LRC|Translated|Offset|Source|Credit)\s*[:：])/i;
        if (re.test(t)) return true;
        if (/^(?:[〜～~—\s]*)(?:終わり|おわり|オワリ|the\s+end|fin|end)(?:[〜～~—\s]*)$/i.test(t)) return true;
        if (root.player && root.player.trackTitle) {
            const stripped = t.replace(/^[「『【《"'\s]+|[」』】》"'\s]+$/g, "").toLowerCase();
            const cleanTitle = root.player.trackTitle.replace(/[\(\[～~].*?[\)\]～~]/g, "").trim().toLowerCase();
            // A bare line equal to the title is only a title card at the very start; later it's the chorus.
            const wrapped = stripped !== t.toLowerCase();
            if (stripped.length > 0 && cleanTitle.length > 0 && (stripped === cleanTitle || stripped === root.player.trackTitle.toLowerCase())
                    && (wrapped || (time !== undefined && time >= 0 && time < 3.0))) {
                return true;
            }
        }
        return false;
    }

    function addInterludeDots(linesList) {
        if (!linesList || linesList.length < 2) return linesList;
        const result = [];
        const minGap = 5.0;

        if (linesList[0].time >= minGap) {
            result.push({ "time": 1.0, "text": "• • •", "endTime": linesList[0].time });
        }

        for (let i = 0; i < linesList.length; i++) {
            result.push(linesList[i]);
            if (i + 1 < linesList.length) {
                const cur = linesList[i];
                const nxt = linesList[i + 1];
                let endT = cur.endTime;
                if (endT === undefined || endT <= cur.time) {
                    const txtLen = cur.text ? cur.text.length : 0;
                    endT = cur.time + Math.min(5.0, Math.max(2.0, txtLen * 0.28 + 0.6));
                }
                const gap = nxt.time - endT;
                if (gap >= minGap) {
                    const dotTime = Math.round((endT + 0.4) * 100) / 100;
                    result.push({ "time": dotTime, "text": "• • •", "endTime": nxt.time });
                }
            }
        }
        return result;
    }

    function isNonVocal(title, artist, album) {
        const full = `${title || ""} ${album || ""}`;
        const re = /\b(?:instrumental|off[\s\-_]*vocals?|backing[\s\-_]*tracks?|karaoke|without[\s\-_]*vocals?|no[\s\-_]*vocals?|minus[\s\-_]*one|インスト|オフボーカル|オフヴォーカル|伴奏|純音楽|纯音乐)\b|[\(\[【（].*?\b(?:inst|inst\.|piano|acoustic|guitar|violin|orchestra|orchestral|music[\s\-_]*box|bgm|ost|solo|インスト|オフボーカル|オフヴォーカル|カラオケ|伴奏|純音楽|纯音乐|ピアノ|オルゴール)\b.*?[\)\]】）]|(?:[-–—~～]\s*).*(?:inst|inst\.|instrumental|off[\s\-_]*vocals?|karaoke|piano|超絶(?:PIANO|piano|ピアノ)|インスト|オフボーカル|オフヴォーカル|カラオケ|伴奏|純音楽|纯音乐|ピアノ)/i;
        return re.test(full);
    }

    function fetchLyrics(force) {
        if (!root.hasPlayer || !root.player || !root.player.trackTitle) {
            root.lines = [];
            root.source = "";
            root.loading = false;
            root.lyricsDetected(false);
            return;
        }

        const title = root.player.trackTitle || "";
        const artist = root.player.trackArtist || "";
        const album = root.player.trackAlbum || "";
        const dur = root.player.length ? String(root.player.length) : "0";

        // Abort immediately for non-vocal tracks
        if (root.isNonVocal(title, artist, album)) {
            root.lines = [];
            root.source = "";
            root.loading = false;
            root.lyricsDetected(false);
            return;
        }

        root.loading = true;
        root.lines = [];
        root.fetchTitle = title;
        root.fetchArtist = artist;

        const scriptPath = Qt.resolvedUrl("../scripts/fetch_lyrics.py").toString().replace(/^file:\/\//, "");
        fetchProc.command = ["python3", scriptPath, title, artist, album, dur];
        fetchProc.running = false;
        fetchProc.running = true;
    }

    function checkTrackChanged() {
        if (!root.hasPlayer || !root.player) {
            root.currentTrackKey = "";
            root.lines = [];
            root.timingOffset = 0.0;
            root.loading = false;
            root.lyricsDetected(false);
            return;
        }
        // Players can briefly report empty metadata while seeking (e.g. when syncing to a
        // lyric line). That is not a track change, so keep the current lyrics and pane.
        if (!root.player.trackTitle)
            return;

        const key = `${root.player.trackTitle}\0${root.player.trackArtist || ""}`;
        if (key !== root.currentTrackKey) {
            root.currentTrackKey = key;
            root.timingOffset = 0.0;
            root.lines = [];
            root.lastMprisPos = (root.hasPlayer && root.player) ? (root.player.position || 0) : 0;
            root.lastMprisTime = Date.now();
            root.currentPlayPosition = root.lastMprisPos;
            root.fetchLyrics(false);
        }
    }

    function updateActiveIndex() {
        if (!root.lines || root.lines.length === 0 || !root.hasPlayer || !root.player || !root.synced) {
            root.activeIndex = -1;
            return;
        }

        const cur = (root.currentPlayPosition || (root.player.position || 0)) + root.timingOffset;
        let found = -1;
        for (let i = 0; i < root.lines.length; i++) {
            if (root.lines[i].time <= cur) {
                found = i;
            } else {
                break;
            }
        }

        if (found !== root.activeIndex) {
            const wasActive = root.activeIndex >= 0;
            root.activeIndex = found;
            if (found >= 0 && !root.userScrolling) {
                lyricListView.currentIndex = found;
                root.scrollToIndexSmoothly(found);
            } else if (found === -1 && wasActive && !root.userScrolling) {
                lyricListView.currentIndex = 0;
                root.scrollToIndexSmoothly(0);
            }
        }
    }

    NumberAnimation {
        id: smoothLyricScroll
        target: lyricListView
        property: "contentY"
        duration: Motion.medium4
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecelerate
    }

    function scrollToIndexSmoothly(idx) {
        if (idx < 0 || !root.lines || idx >= root.lines.length) return;
        lyricListView.cancelFlick();

        const startY = lyricListView.contentY;
        lyricListView.positionViewAtIndex(idx, ListView.Center);
        const targetY = lyricListView.contentY;
        lyricListView.contentY = startY;

        if (Math.abs(targetY - startY) < 1) {
            lyricListView.contentY = targetY;
            return;
        }

        smoothLyricScroll.stop();
        smoothLyricScroll.from = startY;
        smoothLyricScroll.to = targetY;
        smoothLyricScroll.restart();
    }

    onPlayerChanged: checkTrackChanged()
    onHasPlayerChanged: checkTrackChanged()

    Connections {
        target: root.player
        // title, artist and album arrive one after another: wait for them to settle so a track change
        // starts one fetch with the final metadata, not one with a half-updated artist
        function onTrackTitleChanged() { trackSettle.restart(); }
        function onTrackArtistChanged() { trackSettle.restart(); }
        function onPositionChanged() {
            if (root.hasPlayer && root.player) {
                const newPos = root.player.position || 0;
                const now = Date.now();
                if (root.lastMprisTime > 0) {
                    const elapsed = (now - root.lastMprisTime) / 1000.0;
                    const expectedPos = root.lastMprisPos + elapsed;
                    // If user seeked or skipped (>0.4s difference), re-anchor immediately
                    if (Math.abs(newPos - expectedPos) > 0.4) {
                        root.lastMprisPos = newPos;
                        root.lastMprisTime = now;
                        root.currentPlayPosition = newPos;
                    } else {
                        // Smoothly adjust anchor to prevent DBus jitter snapping backwards
                        root.lastMprisPos = expectedPos + (newPos - expectedPos) * 0.15;
                        root.lastMprisTime = now;
                    }
                } else {
                    root.lastMprisPos = newPos;
                    root.lastMprisTime = now;
                    root.currentPlayPosition = newPos;
                }
            }
            root.updateActiveIndex();
        }
        function onPlaybackStateChanged() {
            if (root.hasPlayer && root.player) {
                root.lastMprisPos = root.player.position || 0;
                root.lastMprisTime = Date.now();
                root.currentPlayPosition = root.lastMprisPos;
            }
            root.updateActiveIndex();
        }
    }

    Timer {
        id: trackSettle
        interval: 250
        onTriggered: root.checkTrackChanged()
    }

    Timer {
        id: lyricProgressTimer
        interval: 40
        running: root.isPlaying && root.synced && root.hasLyrics
        repeat: true
        property real lastPokeTime: 0
        onTriggered: {
            const now = Date.now();
            if (root.lastMprisTime > 0) {
                const elapsed = (now - root.lastMprisTime) / 1000.0;
                root.currentPlayPosition = root.lastMprisPos + elapsed;
            } else if (root.hasPlayer && root.player) {
                root.currentPlayPosition = root.player.position || 0;
            }

            // Detect if track reached the end or looped back
            let trackLen = (root.player && root.player.length) ? root.player.length : 0;
            if (trackLen > 10000) trackLen /= 1000000.0;
            const reachedEnd = trackLen > 0 && root.currentPlayPosition >= trackLen;

            // Periodically ping MPRIS every 300ms (or immediately at track end) to stay aligned with player
            if (reachedEnd || (now - lastPokeTime > 300)) {
                lastPokeTime = now;
                if (root.hasPlayer && root.player && root.player.positionChanged) {
                    root.player.positionChanged();
                }
            }

            root.updateActiveIndex();
        }
    }

    Component.onCompleted: checkTrackChanged()

    // Resume auto-scroll timer after user drags/scrolls
    Timer {
        id: scrollResumeTimer
        interval: 3000
        repeat: false
        onTriggered: {
            root.userScrolling = false;
            if (root.activeIndex >= 0) {
                lyricListView.currentIndex = root.activeIndex;
                root.scrollToIndexSmoothly(root.activeIndex);
            }
        }
    }

    // ---- header: timing offset + retime buttons ----
    RowLayout {
        id: header
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.margins: 16
        height: 32
        z: 10
        spacing: 8

        // input chip showing the current offset; trailing ✕ resets it
        Chip {
            readonly property bool hasOffset: Math.abs(root.timingOffset) >= 0.05
            kind: "input"
            selected: true
            icon: "schedule"
            trailingIcon: "close"
            text: (root.timingOffset > 0 ? "+" : "") + root.timingOffset.toFixed(1) + "s"
            opacity: hasOffset ? 1 : 0
            scale: hasOffset ? 1 : 0.8
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            Behavior on scale { Spring {} }
            onClicked: reset()
            onTrailingClicked: reset()
            function reset() {
                root.timingOffset = 0;
                root.updateActiveIndex();
            }
        }

        Item { Layout.fillWidth: true }

        // connected button group: earlier / later
        Row {
            visible: root.synced && root.lines.length > 0
            spacing: 2
            ConnectedButton { position: "first"; icon: "remove"; text: "0.5s"; onClicked: { root.timingOffset -= 0.5; root.updateActiveIndex(); } }
            ConnectedButton { position: "last"; icon: "add"; text: "0.5s"; onClicked: { root.timingOffset += 0.5; root.updateActiveIndex(); } }
        }
    }

    // ---- lyric lines, faded at the top and bottom edges ----
    Item {
        id: listWrapper
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        clip: true

        readonly property real fadeAmount: 0.12

        opacity: !root.loading && root.lines.length > 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Fade { speed: "default" } }

        layer.enabled: true
        layer.effect: MultiEffect {
            maskEnabled: true
            maskSpreadAtMin: 1.0
            maskThresholdMin: 0.5
            maskSource: fadeMask
        }

        Rectangle {
            id: fadeMask
            layer.enabled: true
            visible: false
            width: Math.max(1, listWrapper.width)
            height: Math.max(1, listWrapper.height)
            gradient: Gradient {
                GradientStop { position: 0.0; color: "transparent" }
                GradientStop { position: listWrapper.fadeAmount; color: "black" }
                GradientStop { position: 1.0 - listWrapper.fadeAmount; color: "black" }
                GradientStop { position: 1.0; color: "transparent" }
            }
        }

        ListView {
            id: lyricListView
            anchors.fill: parent
            clip: true
            spacing: 8
            model: root.lines
            highlightRangeMode: ListView.NoHighlightRange
            boundsBehavior: Flickable.DragOverBounds

            // geometry of the current line, published by its delegate; the marker springs to it
            property real markY: 0
            property real markH: 40
            property bool markSet: false

            // one tonal blob that glides (and stretches, with overshoot) from line to line
            Rectangle {
                parent: lyricListView.contentItem
                z: -1
                x: 0
                width: lyricListView.width
                y: lyricListView.markY + 2
                height: Math.max(0, lyricListView.markH - 4)
                radius: Math.min(height / 2, 28)
                color: Qt.alpha(Colors.secondary_container, 0.88)
                opacity: root.activeIndex >= 0 && lyricListView.markSet ? 1 : 0
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on y { enabled: lyricListView.markSet; Spring {} }
                Behavior on height { enabled: lyricListView.markSet; Spring {} }
            }

            // spacers let the first/last line reach the vertical centre
            header: Item { width: lyricListView.width; height: Math.max(0, Math.round(lyricListView.height / 2 - 24)) }
            footer: Item { width: lyricListView.width; height: Math.max(0, Math.round(lyricListView.height / 2 - 24)) }

            onMovingChanged: {
                if (moving) {
                    root.userScrolling = true;
                    scrollResumeTimer.restart();
                }
            }

            delegate: Item {
                id: lineDelegate
                required property var modelData
                required property int index
                readonly property bool isCurrent: index === root.activeIndex
                readonly property bool isPast: root.activeIndex >= 0 && index < root.activeIndex
                readonly property bool isDots: !modelData || !modelData.text || modelData.text === "• • •"

                width: lyricListView.width
                height: isDots ? 56 : Math.max(40, lyricText.implicitHeight + 14)

                function publish() {
                    if (!isCurrent)
                        return;
                    lyricListView.markY = y;
                    lyricListView.markH = height;
                    lyricListView.markSet = true;
                }
                onIsCurrentChanged: publish()
                onYChanged: publish()
                onHeightChanged: publish()

                // lines rise into place one after another when a song's lyrics first appear
                property real appear: 1
                transform: Translate { y: (1 - lineDelegate.appear) * 26 }
                SequentialAnimation {
                    id: enterAnim
                    PauseAnimation { duration: Math.min(Math.abs(lineDelegate.index - Math.max(0, root.activeIndex)), 7) * 55 }
                    Spring { target: lineDelegate; property: "appear"; to: 1; speed: "default" }
                }
                Component.onCompleted: {
                    publish();
                    if (root.entering) {
                        appear = 0;
                        enterAnim.start();
                    }
                }

                // the current line is set in headlineMedium; others scale down from it
                StyledText {
                    id: lyricText
                    visible: !lineDelegate.isDots
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.leftMargin: 18
                    anchors.rightMargin: 18
                    anchors.verticalCenter: parent.verticalCenter
                    transformOrigin: Item.Left
                    // landing on a line bounces: the fast spring overshoots
                    scale: lineDelegate.isCurrent ? 1 : lineMouse.containsMouse ? 0.82 : 0.75
                    Behavior on scale { Spring { speed: lineDelegate.isCurrent ? "fast" : "default" } }
                    role: "headlineMedium"
                    emphasized: lineDelegate.isCurrent
                    jp: true
                    wrapMode: Text.WordWrap
                    text: lineDelegate.isDots ? "" : lineDelegate.modelData.text
                    color: lineDelegate.isCurrent ? Colors.on_secondary_container : Colors.on_surface
                    opacity: (lineDelegate.isCurrent ? 1 : lineMouse.containsMouse ? 0.85 : lineDelegate.isPast ? 0.38 : 0.6) * Math.max(0, Math.min(1, lineDelegate.appear * 1.6))
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on color { ColorFade { speed: "default" } }
                }

                // an instrumental gap: three dots that bounce in turn while it is the current line
                Row {
                    visible: lineDelegate.isDots
                    anchors.left: parent.left
                    anchors.leftMargin: 22
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 10
                    Repeater {
                        model: 3
                        delegate: Rectangle {
                            id: dot
                            required property int index
                            width: 12
                            height: 12
                            radius: 6
                            color: lineDelegate.isCurrent ? Colors.on_secondary_container : Colors.on_surface
                            opacity: lineDelegate.isCurrent ? 1 : 0.4
                            scale: lineDelegate.isCurrent ? 1 : 0.7
                            Behavior on opacity { Fade { speed: "default" } }
                            Behavior on color { ColorFade { speed: "default" } }
                            transform: Translate { id: hop }
                            SequentialAnimation {
                                running: lineDelegate.isCurrent && root.isPlaying
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) hop.y = 0
                                PauseAnimation { duration: dot.index * 160 }
                                NumberAnimation { target: hop; property: "y"; to: -9; duration: 180; easing.type: Easing.OutQuad }
                                NumberAnimation { target: hop; property: "y"; to: 0; duration: 220; easing.type: Easing.OutBounce }
                                PauseAnimation { duration: (2 - dot.index) * 160 + 200 }
                            }
                        }
                    }
                }

                MouseArea {
                    id: lineMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (!root.player || lineDelegate.modelData.time < 0)
                            return;
                        const target = Math.max(0, lineDelegate.modelData.time - root.timingOffset);
                        root.player.position = target;
                        root.lastMprisPos = target;
                        root.lastMprisTime = Date.now();
                        root.currentPlayPosition = target;
                        root.userScrolling = false;
                        root.updateActiveIndex();
                        root.scrollToIndexSmoothly(lineDelegate.index);
                    }
                }
            }
        }
    }

    // ---- "back to current line" button, shown after manual scrolling ----
    Item {
        readonly property bool shouldShow: root.userScrolling && root.activeIndex >= 0
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 16
        width: syncButton.width
        height: syncButton.height
        z: 20
        opacity: shouldShow ? 1 : 0
        scale: shouldShow ? 1 : 0.85
        visible: opacity > 0.01
        Behavior on opacity { Fade {} }
        Behavior on scale { Spring {} }

        Elevation { anchors.fill: syncButton; radius: syncButton.radius; level: 3 }
        Button {
            id: syncButton
            icon: "sync"
            text: "Sync"
            onClicked: {
                root.userScrolling = false;
                scrollResumeTimer.stop();
                if (root.activeIndex >= 0) {
                    lyricListView.currentIndex = root.activeIndex;
                    root.scrollToIndexSmoothly(root.activeIndex);
                }
            }
        }
    }

    // ---- loading / empty states ----
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        opacity: root.loading ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Fade { speed: "default" } }

        LoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: root.loading
            contained: true
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            role: "bodyMedium"
            color: Colors.on_surface_variant
            text: "Loading lyrics…"
        }
    }

    ColumnLayout {
        anchors.centerIn: parent
        spacing: 8
        opacity: !root.loading && root.lines.length === 0 ? 1 : 0
        visible: opacity > 0.01
        Behavior on opacity { Fade { speed: "default" } }

        Icon {
            Layout.alignment: Qt.AlignHCenter
            name: "lyrics"
            size: 32
            color: Colors.outline
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            role: "bodyMedium"
            color: Colors.on_surface_variant
            text: "No lyrics found"
        }
    }
}
