pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services
import "../Components/MangaLayout.js" as ML

// The manga reader: a fullscreen overlay. Two-page spreads (right to left), single pages and vertical
// scrolling, with zoom in all of them. The backend (reader/, qs-manga) hands over page file paths; this
// window lays them out, keeps the place and reports progress and reading time.
//
// Keys: ←/→ or Space turn pages (j/k, PgUp/PgDn scroll), Home/End, 1 2 3 or m pick the mode, o shifts the
// spread pairing, d flips the direction, + - 0 zoom, [ ] page width when scrolling, l library, n/p next and
// previous volume, Esc closes. Click the left/right third to turn, double-click the middle to zoom.
PanelWindow {
    id: win

    readonly property bool active: Manga.open
    property string screenName: ""

    // ---- what is open ----
    property var vol: null              // the helper's reply for the open volume
    property var pages: []
    property bool loaded: false         // the saved page was applied: later changes are the reader's
    property string mode: "spread"      // spread | single | scroll
    property bool rtl: true
    property int offset: 0
    property real widthPct: 0.5         // scroll mode: page width as a share of the screen
    property int page: 0
    property bool libOpen: false
    property bool endShown: false
    property real extractFrac: -1       // 0..1 while an archive unpacks
    property int turns: 0               // page changes since the last tick
    property double lastInput: Date.now()

    readonly property var views: ML.views(pages, mode, offset)
    readonly property int viewIndex: mode === "scroll" ? page : ML.viewOf(views, page)
    readonly property bool pageMode: mode !== "scroll"

    // ---- zoom ----
    property real zoom: 1
    property real panX: 0
    property real panY: 0
    // the zoom and pan the pages are drawn at: springs that follow the goals above (held still while dragging)
    readonly property real zoomV: zoomSpring.value
    readonly property real panXV: panXSpring.value
    readonly property real panYV: panYSpring.value
    SpringValue { id: zoomSpring; target: win.zoom; stiffness: 600; ratio: 1; epsilon: 0.0005 }
    SpringValue { id: panXSpring; target: win.panX; stiffness: 600; ratio: 1; epsilon: 0.05; instant: panDrag.active }
    SpringValue { id: panYSpring; target: win.panY; stiffness: 600; ratio: 1; epsilon: 0.05; instant: panDrag.active }

    screen: Quickshell.screens.find(s => s.name === screenName) ?? Quickshell.screens[0]
    WlrLayershell.namespace: "quickshell:manga"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: active || scene.opacity > 0.01

    onActiveChanged: {
        if (!active)
            bubbleLayer.closeAll();
        if (active) {
            const m = Hyprland.focusedMonitor;
            screenName = m ? m.name : "";
            lastInput = Date.now();
            Manga.request({ op: "prefs_get", vol: 0 }, r => {
                const p = r.prefs || {};
                if (p.mode)
                    mode = p.mode;
                if (p.rtl !== undefined)
                    rtl = p.rtl;
                if (p.widthPct)
                    widthPct = p.widthPct;
            });
            scene.forceActiveFocus();
        } else {
            flushProgress();
            // nothing is being read any more: page text goes back to the background queue
            Manga.ocrFocus(-1, 0);
            endShown = false;
        }
    }

    // ---- opening ----
    function openVolume(id) {
        libOpen = false;
        endShown = false;
        loaded = false;
        extractFrac = -1;
        Manga.request({ op: "open", vol: id }, r => {
            if (r.error)
                return;
            applyVolume(r, true);
        });
    }
    function applyVolume(r, fresh) {
        vol = r;
        pages = r.pages;
        if (r.extracting === true || r.extracted === false)
            extractFrac = Math.max(0, extractFrac);
        if (fresh) {
            offset = r.prefs && r.prefs.offset ? r.prefs.offset : 0;
            page = r.progress && !r.progress.finished ? Math.min(r.progress.page, Math.max(0, r.pages.length - 1)) : 0;
            resetZoom();
            turns = 0;
            Manga.ocrFocus(r.vol, page);
            Qt.callLater(() => { loaded = true; });
        }
    }
    function refetch() {
        if (!vol)
            return;
        Manga.request({ op: "volume", vol: vol.vol }, r => {
            if (r.error || !vol || r.vol !== vol.vol)
                return;
            applyVolume(r, false);
        });
    }
    function nextVolume() {
        if (vol && vol.next)
            openVolume(vol.next.id);
        else
            openLibrary();
    }
    function prevVolume() {
        if (vol && vol.prev)
            openVolume(vol.prev.id);
    }
    function openLibrary() {
        flushProgress();
        libOpen = true;
        endShown = false;
        Manga.refreshLibrary();
    }

    Connections {
        target: Manga
        function onCommand(name, arg) {
            win.lastInput = Date.now();
            switch (name) {
            case "open":
                if (arg >= 0)
                    win.openVolume(arg);
                else
                    win.openLibrary();
                break;
            case "next": win.next(); break;
            case "prev": win.prev(); break;
            case "mode": win.setMode(arg); break;
            case "zoom": win.setZoom(arg); break;
            case "page": win.goPage(arg); break;
            case "offset": win.toggleOffset(); break;
            case "nextVolume": win.nextVolume(); break;
            case "chrome": chrome.toggle(); break;
            }
        }
        function onExtractProgress(v, done, total) {
            if (win.vol && v === win.vol.vol) {
                win.extractFrac = total > 0 ? done / total : 0;
                refetchSoon.start();
            }
        }
        function onExtracted(v) {
            if (win.vol && v === win.vol.vol) {
                win.extractFrac = -1;
                win.refetch();
            }
        }
    }
    // pages show up as an archive unpacks
    Timer { id: refetchSoon; interval: 1500; onTriggered: win.refetch() }

    // ---- navigation ----
    function goView(v) {
        v = Math.max(0, Math.min(views.length - 1, v));
        if (views.length > 0)
            page = views[v][0];
        endShown = false;
    }
    function goPage(p) {
        p = Math.max(0, Math.min(pages.length - 1, p));
        if (mode === "scroll" && scrollLoader.item)
            scrollLoader.item.jumpTo(p, true);
        page = p;
        endShown = false;
    }
    function next() {
        if (!vol || libOpen)
            return;
        if (mode === "scroll") {
            if (scrollLoader.item)
                scrollLoader.item.scrollBy(stage.height * 0.85);
            return;
        }
        if (viewIndex < views.length - 1)
            goView(viewIndex + 1);
        else if (endShown)
            nextVolume();
        else
            endShown = true;
    }
    function prev() {
        if (!vol || libOpen)
            return;
        if (mode === "scroll") {
            if (scrollLoader.item)
                scrollLoader.item.scrollBy(-stage.height * 0.85);
            return;
        }
        if (endShown)
            endShown = false;
        else if (viewIndex > 0)
            goView(viewIndex - 1);
    }
    function setMode(m) {
        if (m !== "spread" && m !== "single" && m !== "scroll")
            return;
        if (m === mode)
            return;
        mode = m;
        resetZoom();
        endShown = false;
        savePrefs();
    }
    function toggleOffset() {
        offset = offset ? 0 : 1;
        if (vol)
            Manga.request({ op: "prefs_set", vol: vol.vol, prefs: { offset: offset } });
    }
    function savePrefs() {
        Manga.request({ op: "prefs_set", vol: 0, prefs: { mode: mode, rtl: rtl, widthPct: widthPct } });
    }

    // a mode change or a late page-size update keeps the place
    onModeChanged: {
        if (mode === "scroll")
            Qt.callLater(() => { if (scrollLoader.item) scrollLoader.item.jumpTo(page, false); });
    }

    // ---- zoom ----
    function resetZoom() {
        zoom = 1;
        panX = 0;
        panY = 0;
    }
    function clampPan() {
        panX = Math.min(0, Math.max(stage.width * (1 - zoom), panX));
        panY = Math.min(0, Math.max(stage.height * (1 - zoom), panY));
    }
    function setZoom(z, cx, cy) {
        z = Math.max(1, Math.min(5, z));
        if (cx === undefined) {
            cx = stage.width / 2;
            cy = stage.height / 2;
        }
        if (pageMode) {
            const k = z / zoom;
            panX = cx - (cx - panX) * k;
            panY = cy - (cy - panY) * k;
            zoom = z;
            if (z <= 1.001) {
                panX = 0;
                panY = 0;
            }
            clampPan();
        } else {
            zoom = z;
        }
    }
    function zoomBy(f, cx, cy) { setZoom(zoom * f, cx, cy); }

    // ---- progress and reading time ----
    function flushProgress() {
        saveSoon.stop();
        if (!vol || !loaded)
            return;
        const lastOfView = mode === "scroll" ? page : (views[viewIndex] || [page])[views[viewIndex] ? views[viewIndex].length - 1 : 0];
        const done = mode === "scroll" ? page >= pages.length - 1 : viewIndex >= views.length - 1;
        Manga.request({ op: "progress", vol: vol.vol, page: lastOfView, finished: done });
        // the text of the pages ahead is read first
        Manga.ocrFocus(vol.vol, page);
    }
    onPageChanged: {
        bubbleLayer.closeAll();
        lastInput = Date.now();
        if (loaded) {
            turns++;
            saveSoon.restart();
        }
    }
    Timer { id: saveSoon; interval: 1000; onTriggered: win.flushProgress() }
    // reading time: every 15 s while the reader is up and was touched in the last 3 minutes
    Timer {
        interval: 15000
        repeat: true
        running: win.active && win.vol !== null && !win.libOpen
        onTriggered: {
            if (Date.now() - win.lastInput > 180000)
                return;
            Manga.request({ op: "tick", vol: win.vol.vol, secs: 15, turns: win.turns });
            win.turns = 0;
        }
    }

    Binding {
        target: Manga
        property: "readerState"
        value: ({ vol: win.vol ? win.vol.vol : -1, title: win.vol ? win.vol.series + " " + win.vol.title : "", mode: win.mode, page: win.page,
                  pages: win.pages.length, views: win.views.length, viewIndex: win.viewIndex, zoom: win.zoom, offset: win.offset, rtl: win.rtl,
                  library: win.libOpen, end: win.endShown, extracting: win.extractFrac >= 0, widthPct: win.widthPct,
                  view: win.views[win.viewIndex] || [] })
    }
    Binding { target: Manga; property: "openVol"; value: win.vol ? win.vol.vol : -1 }
    Binding { target: Manga; property: "reader"; value: win }
    // the speech bubbles' words and dictionary card (the pages find it through Manga.reader)
    readonly property var bubbles: bubbleLayer
    onZoomChanged: bubbleLayer.closeAll()
    onPanXChanged: bubbleLayer.closeAll()
    onPanYChanged: bubbleLayer.closeAll()
    onLibOpenChanged: bubbleLayer.closeAll()
    function liveState() {
        return { zoomV: zoomV, panXV: panXV, panYV: panYV, viewPos: spreadLoader.item ? spreadLoader.item.viewPos : -1,
                 contentY: scrollLoader.item ? scrollLoader.item.contentY : -1 };
    }

    // ---- scene ----
    Item {
        id: scene
        anchors.fill: parent
        opacity: win.active ? 1 : 0
        Behavior on opacity { Fade { speed: "default" } }
        focus: true

        Keys.onPressed: ev => {
            win.lastInput = Date.now();
            const shift = ev.modifiers & Qt.ShiftModifier;
            const k = ev.key;
            let ok = true;
            if (k === Qt.Key_Escape) {
                if (bubbleLayer.open || bubbleLayer.popOpen)
                    bubbleLayer.closeAll();
                else if (win.zoom > 1.001)
                    win.resetZoom();
                else if (win.libOpen && win.vol)
                    win.libOpen = false;
                else
                    Manga.hide();
            } else if (ev.modifiers & Qt.AltModifier) {
                // the study keys of the subtitles, on the word under the pointer
                if (k === Qt.Key_K)
                    bubbleLayer.known();
                else if (k === Qt.Key_I)
                    bubbleLayer.ignore();
                else if (k === Qt.Key_N)
                    bubbleLayer.name();
                else if (k === Qt.Key_F)
                    Lexicon.cycleFurigana();
                else
                    ok = false;
            } else if (win.libOpen) {
                if (k === Qt.Key_Return || k === Qt.Key_Enter)
                    library.continueHero();
                else
                    ok = false;
            } else if (k === Qt.Key_Left) {
                if (win.pageMode) win.rtl ? win.next() : win.prev();
                else ok = false;
            } else if (k === Qt.Key_Right) {
                if (win.pageMode) win.rtl ? win.prev() : win.next();
                else ok = false;
            } else if (k === Qt.Key_Space || k === Qt.Key_PageDown || k === Qt.Key_Down || k === Qt.Key_J || k === Qt.Key_Return) {
                shift && k === Qt.Key_Space ? win.prev() : win.next();
            } else if (k === Qt.Key_Backspace || k === Qt.Key_PageUp || k === Qt.Key_Up || k === Qt.Key_K) {
                win.prev();
            } else if (k === Qt.Key_Home) {
                win.goPage(0);
            } else if (k === Qt.Key_End) {
                win.goPage(win.pages.length - 1);
            } else if (k === Qt.Key_1) {
                win.setMode("spread");
            } else if (k === Qt.Key_2) {
                win.setMode("single");
            } else if (k === Qt.Key_3) {
                win.setMode("scroll");
            } else if (k === Qt.Key_M) {
                win.setMode(win.mode === "spread" ? "single" : win.mode === "single" ? "scroll" : "spread");
            } else if (k === Qt.Key_O) {
                win.toggleOffset();
            } else if (k === Qt.Key_D) {
                win.rtl = !win.rtl;
                win.savePrefs();
            } else if (k === Qt.Key_Plus || k === Qt.Key_Equal) {
                win.zoomBy(1.25);
            } else if (k === Qt.Key_Minus) {
                win.zoomBy(0.8);
            } else if (k === Qt.Key_0) {
                win.resetZoom();
            } else if (k === Qt.Key_BracketLeft) {
                win.widthPct = Math.max(0.3, win.widthPct - 0.05);
                win.savePrefs();
            } else if (k === Qt.Key_BracketRight) {
                win.widthPct = Math.min(1, win.widthPct + 0.05);
                win.savePrefs();
            } else if (k === Qt.Key_L) {
                win.openLibrary();
            } else if (k === Qt.Key_N) {
                win.nextVolume();
            } else if (k === Qt.Key_P) {
                win.prevVolume();
            } else {
                ok = false;
            }
            ev.accepted = ok;
        }

        // the pointer anywhere brings the top bar and the scrubber in at the edges. It sits on the scene itself, under everything:
        // a hover handler hides the pointer from every item below it, so on the chrome it would blind the bubbles on the pages
        HoverHandler {
            id: hov
            onPointChanged: {
                const y = point.position.y;
                win.lastInput = Date.now();
                if (y < 96) { chrome.topOn = true; chrome.topTimer.stop(); } else if (chrome.topOn) chrome.topTimer.restart();
                if (y > chrome.height - 150) { chrome.botOn = true; chrome.botTimer.stop(); } else if (chrome.botOn) chrome.botTimer.restart();
            }
        }

        MangaBackdrop {
            anchors.fill: parent
            volId: win.libOpen ? library.focusVol : win.vol ? win.vol.vol : -1
            page: win.libOpen ? 0 : win.mode === "scroll" ? win.page : (win.views[win.viewIndex] || [win.page])[0]
            turn: win.libOpen ? library.focusTurn : win.viewIndex
            active: win.active
        }

        // ---- the pages ----
        Item {
            id: stage
            anchors.fill: parent
            opacity: win.libOpen ? 0 : 1
            Behavior on opacity { Fade {} }
            visible: opacity > 0.01

            Item {
                id: zoomer
                width: stage.width
                height: stage.height
                transformOrigin: Item.TopLeft
                scale: win.pageMode ? Math.max(1, win.zoomV) : 1
                x: win.pageMode ? win.panXV : 0
                y: win.pageMode ? win.panYV : 0

                Loader {
                    id: spreadLoader
                    anchors.fill: parent
                    active: win.pageMode && win.vol !== null
                    sourceComponent: MangaSpreadView {
                        pages: win.pages
                        views: win.views
                        viewIndex: win.viewIndex
                        rtl: win.rtl
                        zoom: win.zoom
                    }
                }
                Loader {
                    id: scrollLoader
                    anchors.fill: parent
                    active: !win.pageMode && win.vol !== null
                    sourceComponent: MangaScrollView {
                        pages: win.pages
                        baseWidth: Math.min(stage.width, stage.width * win.widthPct)
                        zoom: win.zoom
                        onPageSeen: p => {
                            win.page = p;
                            win.lastInput = Date.now();
                        }
                        onZoomWheel: (d, x) => win.zoomBy(d > 0 ? 1.1 : 1 / 1.1, x, 0)
                        onTapped: (x, y) => chrome.toggle()
                        // the end card appears once the bottom has been in view for a moment
                        onContentYChanged: {
                            const atEnd = contentY >= maxY() - 8 && maxY() > 0;
                            if (atEnd && !win.endShown)
                                endSoon.restart();
                            else if (!atEnd) {
                                endSoon.stop();
                                if (contentY < maxY() - 120)
                                    win.endShown = false;
                            }
                        }
                        Component.onCompleted: jumpTo(win.page, false)
                    }
                }
            }
            Timer { id: endSoon; interval: 600; onTriggered: win.endShown = true }
            Connections {
                target: scrollLoader.item
                ignoreUnknownSignals: true
                function onContentYChanged() { bubbleLayer.closeAll(); }
            }

            // page modes: pan while zoomed in, turn with the wheel, click the sides to turn
            DragHandler {
                id: panDrag
                target: null
                enabled: win.pageMode && win.zoom > 1.001
                property real sx: 0
                property real sy: 0
                onActiveChanged: if (active) { sx = win.panX; sy = win.panY; }
                onTranslationChanged: if (active) {
                    win.panX = sx + translation.x;
                    win.panY = sy + translation.y;
                    win.clampPan();
                }
            }
            WheelHandler {
                enabled: win.pageMode
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: ev => {
                    win.lastInput = Date.now();
                    if (ev.modifiers & Qt.ControlModifier) {
                        win.zoomBy(ev.angleDelta.y > 0 ? 1.15 : 1 / 1.15, point.position.x, point.position.y);
                    } else if (win.zoom > 1.001) {
                        win.panY += ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y * 0.8;
                        win.panX += ev.pixelDelta.x !== 0 ? ev.pixelDelta.x : ev.angleDelta.x * 0.8;
                        win.clampPan();
                    } else if (!wheelCool.running && ev.angleDelta.y !== 0) {
                        ev.angleDelta.y < 0 ? win.next() : win.prev();
                        wheelCool.restart();
                    }
                }
            }
            Timer { id: wheelCool; interval: 220 }
            TapHandler {
                enabled: win.pageMode && !win.libOpen
                onTapped: pt => {
                    const x = pt.position.x, w = stage.width;
                    if (win.zoom > 1.001 || (x >= w / 3 && x <= w * 2 / 3))
                        return;
                    const left = x < w / 3;
                    (left === win.rtl) ? win.next() : win.prev();
                }
                onSingleTapped: pt => {
                    const x = pt.position.x, w = stage.width;
                    if (win.zoom > 1.001 || (x >= w / 3 && x <= w * 2 / 3))
                        chrome.toggle();
                }
                onDoubleTapped: pt => {
                    const x = pt.position.x, w = stage.width;
                    if (win.zoom > 1.001)
                        win.setZoom(1);
                    else if (x >= w / 3 && x <= w * 2 / 3)
                        win.setZoom(2.5, pt.position.x, pt.position.y);
                }
            }
        }

        // ---- loading ----
        LoadingIndicator {
            anchors.centerIn: parent
            visible: !win.libOpen && win.vol === null && Manga.open
        }

        // ---- end of volume ----
        MangaEndCard {
            anchors.centerIn: parent
            shown: win.endShown && !win.libOpen && win.vol !== null
            next: win.vol ? win.vol.next : null
            nextCover: win.vol && win.vol.next ? Manga.cover(win.nextCoverPath) : ""
            seriesTitle: win.vol ? win.vol.series : ""
            onNextVolume: win.nextVolume()
            onLibrary: win.openLibrary()
        }

        // ---- the words of a bubble, and their dictionary card ----
        MangaBubbleCard {
            id: bubbleLayer
            anchors.fill: parent
            visible: !win.libOpen
        }

        // ---- chrome ----
        Item {
            id: chrome
            anchors.fill: parent
            property bool pinned: false
            property bool topOn: false
            property bool botOn: false
            function toggle() { pinned = !pinned; }
            property alias topTimer: topHide
            property alias botTimer: botHide
            Timer { id: topHide; interval: 1500; onTriggered: chrome.topOn = false }
            Timer { id: botHide; interval: 1500; onTriggered: chrome.botOn = false }

            readonly property bool showTop: (pinned || topOn) && win.vol !== null
            readonly property bool showBot: (pinned || botOn) && win.vol !== null && !win.libOpen

            Rectangle {
                id: topBar
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property bool on: chrome.showTop && !win.libOpen
                y: on ? 16 : -height - 8
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on y { Spring {} }
                Behavior on opacity { Fade {} }
                implicitWidth: bar.implicitWidth + 24
                implicitHeight: 56
                width: Math.min(implicitWidth, chrome.width - 32)
                height: implicitHeight
                radius: Motion.shapeExtraLarge
                color: Colors.surface_container

                RowLayout {
                    id: bar
                    anchors.centerIn: parent
                    spacing: 10
                    IconButton {
                        icon: "grid_view"
                        onClicked: win.openLibrary()
                    }
                    StyledText {
                        role: "titleSmall"
                        emphasized: true
                        jp: true
                        text: win.vol ? win.vol.series + "  ·  " + win.vol.title : ""
                        elide: Text.ElideRight
                        Layout.maximumWidth: 360
                    }
                    Row {
                        spacing: 2
                        ConnectedButton { position: "first"; text: "Spread"; selected: win.mode === "spread"; onClicked: win.setMode("spread") }
                        ConnectedButton { position: "middle"; text: "Page"; selected: win.mode === "single"; onClicked: win.setMode("single") }
                        ConnectedButton { position: "last"; text: "Scroll"; selected: win.mode === "scroll"; onClicked: win.setMode("scroll") }
                    }
                    Collapse {
                        horizontal: true
                        gap: 0
                        open: win.mode === "spread"
                        Chip { kind: "filter"; text: "Shift pairing"; selected: win.offset === 1; onClicked: win.toggleOffset() }
                    }
                    Chip {
                        kind: "filter"
                        text: win.rtl ? "Right to left" : "Left to right"
                        selected: win.rtl
                        onClicked: { win.rtl = !win.rtl; win.savePrefs(); }
                    }
                    Collapse {
                        horizontal: true
                        open: win.zoom > 1.01
                        Chip { text: Math.round(win.zoom * 100) + "%"; onClicked: win.resetZoom() }
                    }
                    IconButton {
                        icon: "close"
                        onClicked: Manga.hide()
                    }
                }
            }

            MangaScrubber {
                id: scrub
                anchors.horizontalCenter: parent.horizontalCenter
                readonly property bool on: chrome.showBot
                width: Math.min(chrome.width - 64, 880)
                y: on ? chrome.height - height - 24 : chrome.height + 12
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on y { Spring {} }
                Behavior on opacity { Fade {} }
                volId: win.vol ? win.vol.vol : -1
                total: win.pages.length
                page: win.mode === "scroll" ? win.page : (win.views[win.viewIndex] || [win.page])[0]
                rtl: win.rtl
                onSeek: p => win.goPage(p)
            }

            // unpacking an archive
            Rectangle {
                readonly property bool on: win.extractFrac >= 0 && !win.libOpen
                x: 24
                y: on ? chrome.height - height - 24 : chrome.height + 12
                width: label.implicitWidth + 32
                height: 40
                radius: Motion.shapeFull
                color: Colors.secondary_container
                opacity: on ? 1 : 0
                visible: opacity > 0.01
                Behavior on y { Spring {} }
                Behavior on opacity { Fade {} }
                StyledText {
                    id: label
                    anchors.centerIn: parent
                    role: "labelLarge"
                    emphasized: true
                    color: Colors.on_secondary_container
                    text: "Unpacking  " + Math.round(Math.max(0, win.extractFrac) * 100) + "%"
                }
            }
        }

        // ---- library ----
        MangaLibrary {
            id: library
            anchors.fill: parent
            shown: win.libOpen && win.active
            opacity: shown ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { Fade {} }
            onPick: (id, from, source) => {
                flyer.fly(from, source);
                win.openVolume(id);
            }
            onCloseRequested: win.vol ? win.libOpen = false : Manga.hide()
        }

        // the picked cover grows from its card to where the first page will be, then gives way to the page
        Item {
            id: flyer
            property bool on: false
            property rect from: Qt.rect(0, 0, 0, 0)
            property url src
            readonly property real aspect: fimg.implicitHeight > 0 ? fimg.implicitWidth / fimg.implicitHeight : 1 / 1.42
            readonly property real tw: stage.height * aspect
            readonly property real t: ft.value
            function fly(rect, source) {
                from = rect;
                src = source;
                on = true;
                ft.jump(0);
                ft.target = 1;
                landed.restart();
            }
            SpringValue { id: ft; stiffness: 380; ratio: 0.8; epsilon: 0.0005 }
            // gives way once the book is open and the cover has landed
            Timer {
                id: landed
                interval: 650
                onTriggered: if (win.loaded) flyer.on = false; else restart()
            }
            anchors.fill: parent
            opacity: on ? 1 : 0
            visible: opacity > 0.01
            Behavior on opacity { Fade {} }
            ClippingRectangle {
                x: flyer.from.x + ((stage.width - flyer.tw) / 2 - flyer.from.x) * flyer.t
                y: flyer.from.y + (0 - flyer.from.y) * flyer.t
                width: flyer.from.width + (flyer.tw - flyer.from.width) * flyer.t
                height: flyer.from.height + (stage.height - flyer.from.height) * flyer.t
                radius: Math.max(0, Motion.shapeMedium * (1 - flyer.t))
                color: Colors.surface_container_high
                Image {
                    id: fimg
                    anchors.fill: parent
                    source: flyer.src
                    fillMode: Image.PreserveAspectCrop
                }
            }
        }
    }

    // the cover of the next volume, from the library
    readonly property string nextCoverPath: {
        if (!vol || !vol.next)
            return "";
        for (const s of Manga.series)
            for (const v of s.volumes)
                if (v.id === vol.next.id)
                    return v.cover;
        return "";
    }
}
