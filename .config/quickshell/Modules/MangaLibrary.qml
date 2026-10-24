pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Pick what to read: a hero that continues where you were, then one row of covers per series. The
// backdrop behind it (the reader's) follows the cover under the pointer through focusVol / focusTurn.
Item {
    id: lib

    property bool shown: false
    // the volume whose cover the backdrop should show, and a counter that moves when it changes
    property int focusVol: -1
    property int focusTurn: 0
    signal pick(int vol, rect from, string source)
    signal closeRequested()

    readonly property var series: Manga.series
    readonly property var latest: Manga.latest
    // the hero: the volume read last, otherwise the first one of the first series
    readonly property var hero: {
        if (latest)
            return { series: latest.series, vol: latest.vol, resume: true };
        if (series.length > 0 && series[0].volumes.length > 0)
            return { series: series[0], vol: series[0].volumes[0], resume: false };
        return null;
    }
    property int hoverVol: -1
    onHoverVolChanged: if (hoverVol >= 0) { focusVol = hoverVol; focusTurn += 1; }
    onHeroChanged: if (hoverVol < 0 && hero) focusVol = hero.vol.id
    onShownChanged: if (shown && hero) { hoverVol = -1; focusVol = hero.vol.id; }

    function pct(v) { return v.finished ? 1 : v.started && v.pages > 0 ? Math.min(1, (v.max + 1) / v.pages) : 0; }
    function seriesPct(s) {
        let total = 0, read = 0;
        for (const v of s.volumes) {
            total += v.pages;
            read += v.finished ? v.pages : v.started ? v.max + 1 : 0;
        }
        return total > 0 ? read / total : 0;
    }
    // the first volume not started that comes after the last finished one
    function nextId(s) {
        let last = -1;
        s.volumes.forEach((v, i) => { if (v.finished || v.started) last = i; });
        for (let i = last + 1; i < s.volumes.length; i++)
            if (!s.volumes[i].started)
                return s.volumes[i].id;
        return -1;
    }
    function startIndex(s) {
        const i = s.volumes.findIndex(v => v.started && !v.finished);
        if (i >= 0)
            return i;
        const n = nextId(s);
        return Math.max(0, s.volumes.findIndex(v => v.id === n));
    }

    MouseArea { anchors.fill: parent }

    ColumnLayout {
        id: col
        anchors.fill: parent
        anchors.margins: 40
        anchors.topMargin: 56
        spacing: 20

        // ---- top bar ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            StyledText {
                role: "displaySmall"
                emphasized: true
                jp: true
                text: "Manga"
                Layout.fillWidth: true
            }
            InfoPill {
                implicitHeight: 32
                implicitWidth: statsLabel.implicitWidth + 28
                text: ""
                container: Colors.secondary_container
                StyledText {
                    id: statsLabel
                    anchors.centerIn: parent
                    role: "labelLarge"
                    emphasized: true
                    color: Colors.on_secondary_container
                    text: "Today " + Manga.fmtTime(Manga.stats.today.secs) + "   ·   Week " + Manga.fmtTime(Manga.stats.week.secs)
                }
            }
            IconButton {
                icon: "refresh"
                onClicked: Manga.request({ op: "rescan" })
            }
            IconButton {
                icon: "close"
                onClicked: lib.closeRequested()
            }
        }

        // ---- hero, and beside it how the page text reading is going ----
        RowLayout {
            id: heroLine
            Layout.fillWidth: true
            // one height for the hero and the card (the hero's cover is sized from it, so it must not come from the layout)
            readonly property real lineH: Math.max(140, Math.min(200, col.height * 0.17), ocrCard.implicitHeight)
            Layout.preferredHeight: lineH
            spacing: 16

        Rectangle {
            id: heroBox
            Layout.preferredHeight: heroLine.lineH
            Layout.preferredWidth: Math.min(col.width, heroRow.implicitWidth + 40)
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container
            visible: lib.hero !== null
            Appear { shown: lib.shown; from: 0.97 }

            RowLayout {
                id: heroRow
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 20
                spacing: 24
                // square, so the cookie is round
                ShapeMask {
                    id: heroCover
                    Layout.preferredWidth: heroBox.height - 28
                    Layout.preferredHeight: heroBox.height - 28
                    Layout.alignment: Qt.AlignVCenter
                    rotation: heroHover.hovered ? 0 : -3
                    Behavior on rotation { Spring { speed: "default" } }
                    source: lib.hero ? Manga.cover(lib.hero.vol.cover) : ""
                    shape: "cookie9"
                    activeShape: "sunny"
                    active: heroHover.hovered
                    HoverHandler { id: heroHover }
                    TapHandler { onTapped: lib.continueHero() }
                }
                ColumnLayout {
                    Layout.alignment: Qt.AlignVCenter
                    Layout.maximumWidth: 520
                    spacing: 8
                    StyledText {
                        role: "headlineMedium"
                        emphasized: true
                        jp: true
                        Layout.fillWidth: true
                        elide: Text.ElideRight
                        text: lib.hero ? lib.hero.series.title : ""
                    }
                    StyledText {
                        role: "titleMedium"
                        color: Colors.on_surface_variant
                        text: !lib.hero ? "" : lib.hero.vol.finished ? lib.hero.vol.title + "  ·  Read" : lib.hero.vol.started ? lib.hero.vol.title + "  ·  Page " + (lib.hero.vol.page + 1) + " of " + lib.hero.vol.pages : lib.hero.vol.title + "  ·  " + lib.hero.vol.pages + " pages"
                    }
                    WavyProgress {
                        Layout.preferredWidth: 240
                        Layout.preferredHeight: 14
                        value: lib.hero ? lib.pct(lib.hero.vol) : 0
                        waving: lib.shown
                        visible: lib.hero ? lib.hero.vol.started : false
                    }
                    RowLayout {
                        spacing: 12
                        Button {
                            text: lib.hero && lib.hero.resume ? "Continue" : "Start"
                            icon: "play_arrow"
                            onClicked: lib.continueHero()
                        }
                        InfoPill {
                            visible: lib.hero ? Manga.seriesWeek(lib.hero.series.id) > 0 : false
                            text: lib.hero ? Manga.fmtTime(Manga.seriesWeek(lib.hero.series.id)) + " this week" : ""
                        }
                    }
                }
            }
        }

        MangaOcrCard {
            id: ocrCard
            Layout.preferredHeight: heroLine.lineH
            Layout.preferredWidth: Math.max(300, Math.min(560, col.width - (heroBox.visible ? heroBox.Layout.preferredWidth : 0) - 16))
            shown: lib.shown
            delay: 80
        }
        }

        // ---- series rows ----
        Item {
            id: rowsArea
            Layout.fillWidth: true
            Layout.fillHeight: true

        Flickable {
            id: rowsView
            width: parent.width
            // whole rows only: the strip left under them holds the "more below" pill
            readonly property int fitRows: Math.max(1, Math.floor((rowsArea.height - 44 + 8) / rowPitch))
            height: Math.min(contentHeight, fitRows * rowPitch - 8)
            clip: true
            contentHeight: rowsCol.height
            boundsBehavior: Flickable.StopAtBounds
            interactive: false
            function maxY() { return Math.max(0, contentHeight - height); }
            SpringValue {
                id: sy
                stiffness: 300
                epsilon: 0.3
                onValueChanged: rowsView.contentY = value
            }
            // the wheel scrolls the page; sideways (or shift) scrolls a row
            WheelHandler {
                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                onWheel: ev => {
                    if (!sy.moving)
                        sy.jump(rowsView.contentY);
                    const d = ev.pixelDelta.y !== 0 ? ev.pixelDelta.y : ev.angleDelta.y;
                    if (d === 0)
                        return;
                    sy.target = rowsView.snapY((sy.moving ? sy.target : rowsView.contentY) - Math.sign(d) * rowsView.rowPitch);
                }
            }
            // drag to scroll, with a fling on letting go
            DragHandler {
                id: vdrag
                target: null
                xAxis.enabled: false
                property real startY: 0
                onActiveChanged: {
                    if (active) {
                        startY = rowsView.contentY;
                        sy.jump(startY);
                    } else {
                        const vy = centroid.velocity.y;
                        const fast = Math.abs(vy) > 300;
                        const goal = rowsView.snapY(rowsView.contentY - (fast ? vy * 0.35 : 0));
                        sy.fling(goal, fast ? -vy : 0);
                    }
                }
                onTranslationChanged: if (active) sy.jump(Math.max(0, Math.min(rowsView.maxY(), startY - translation.y)))
            }
            HoverHandler { cursorShape: vdrag.active || rowsView.hdragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor }
            property bool hdragging: false

            readonly property int headerH: 36
            readonly property int rowPad: 46   // the volume title under a cover, and the gaps
            // the cover height that lets every row fit the space (an in-progress card is 10% bigger)
            // medium big covers; when the rows don't fit the column scrolls
            // whole cards only: perRow of them fill the row exactly, and scrolling snaps to a card
            readonly property int gap: 14
            readonly property int perRow: Math.max(6, Math.min(12, Math.round(width / 215)))
            readonly property real cardW: (width - (perRow - 1) * gap) / perRow
            readonly property real pitch: cardW + gap
            readonly property real coverW: cardW - 16
            readonly property real coverH: coverW * 1.42
            // every row is the same height, so the column rests on a row top (or on the very end)
            readonly property real rowPitch: headerH + coverH + rowPad + 8
            function snapY(y) {
                const k = Math.round(y / rowPitch) * rowPitch;
                return Math.max(0, Math.min(maxY(), Math.abs(y - maxY()) < Math.abs(y - k) ? maxY() : k));
            }

            Column {
                id: rowsCol
                width: rowsView.width
                spacing: 8
                Repeater {
                    model: lib.series
                    delegate: Item {
                        id: row
                        required property var modelData
                        required property int index
                        width: rowsCol.width
                        height: rowsView.headerH + rowsView.coverH + rowsView.rowPad
                        readonly property int nextVol: lib.nextId(modelData)
                        Appear { shown: lib.shown; delay: 120 + Math.min(row.index, 6) * 60; lift: 14 }

                        RowLayout {
                            id: rowHead
                            width: parent.width
                            height: rowsView.headerH
                            spacing: 12
                            StyledText {
                                role: "titleLarge"
                                emphasized: true
                                jp: true
                                text: row.modelData.title
                                elide: Text.ElideRight
                                Layout.maximumWidth: parent.width * 0.6
                            }
                            StyledText {
                                role: "labelLarge"
                                emphasized: true
                                color: Colors.on_surface_variant
                                text: Math.round(lib.seriesPct(row.modelData) * 100) + "% read"
                            }
                            InfoPill {
                                visible: Manga.seriesWeek(row.modelData.id) > 0
                                text: Manga.fmtTime(Manga.seriesWeek(row.modelData.id)) + " this week"
                            }
                            Item { Layout.fillWidth: true }
                        }

                        ListView {
                            id: strip
                            anchors.top: rowHead.bottom
                            anchors.left: parent.left
                            anchors.bottom: parent.bottom
                            width: Math.min(parent.width, rowsView.perRow * rowsView.pitch - rowsView.gap)
                            orientation: ListView.Horizontal
                            spacing: rowsView.gap
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: row.modelData.volumes
                            interactive: false
                            // sideways (or shift) wheel scrolls it, on a spring
                            SpringValue {
                                id: sx
                                stiffness: 300
                                epsilon: 0.3
                                onValueChanged: strip.contentX = value
                            }
                            // a horizontal ListView's content can start left of 0 (originX), so every stop is measured from it
                            function minX() { return originX; }
                            function maxX() { return originX + Math.max(0, contentWidth - width); }
                            function snap(x) { return Math.max(minX(), Math.min(maxX(), minX() + Math.round((x - minX()) / rowsView.pitch) * rowsView.pitch)); }
                            WheelHandler {
                                acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                                acceptedModifiers: Qt.NoModifier | Qt.ShiftModifier
                                onWheel: ev => {
                                    const sideways = ev.angleDelta.x !== 0 || ev.pixelDelta.x !== 0 || (ev.modifiers & Qt.ShiftModifier);
                                    if (!sideways) {
                                        ev.accepted = false;
                                        return;
                                    }
                                    if (!sx.moving)
                                        sx.jump(strip.contentX);
                                    const raw = ev.angleDelta.x !== 0 ? ev.angleDelta.x : ev.angleDelta.y;
                                    sx.target = strip.snap((sx.moving ? sx.target : strip.contentX) - Math.sign(raw) * rowsView.pitch * 3);
                                }
                            }
                            // drag to scroll, with a fling on letting go
                            DragHandler {
                                id: hdrag
                                target: null
                                yAxis.enabled: false
                                property real startX: 0
                                onActiveChanged: {
                                    rowsView.hdragging = active;
                                    if (active) {
                                        startX = strip.contentX;
                                        sx.jump(startX);
                                    } else {
                                        const vx = centroid.velocity.x;
                                        const fast = Math.abs(vx) > 300;
                                        const goal = strip.snap(strip.contentX - (fast ? vx * 0.35 : 0));
                                        sx.fling(goal, fast ? -vx : 0);
                                    }
                                }
                                onTranslationChanged: if (active) sx.jump(Math.max(strip.minX(), Math.min(strip.maxX(), startX - translation.x)))
                            }
                            Component.onCompleted: {
                                const x = Math.max(minX(), Math.min(maxX(), minX() + lib.startIndex(row.modelData) * rowsView.pitch));
                                sx.jump(x);
                                contentX = x;
                            }
                            // card size or count changed under us (first layout, a rescan): land on a whole card again
                            onContentWidthChanged: if (!sx.moving) sx.jump(snap(contentX))
                            Connections {
                                target: rowsView
                                function onPitchChanged() { if (!sx.moving) sx.jump(strip.snap(strip.contentX)); }
                            }

                            delegate: Clickable {
                                id: vc
                                required property var modelData
                                required property int index
                                readonly property bool fin: modelData.finished
                                readonly property bool prog: modelData.started && !modelData.finished
                                readonly property bool isNext: modelData.id === row.nextVol
                                                                width: rowsView.cardW
                                height: strip.height
                                restRadius: Motion.shapeLarge
                                color: prog ? Colors.secondary_container : Colors.surface_container
                                onHoveredChanged: {
                                    if (hovered)
                                        lib.hoverVol = modelData.id;
                                    else if (lib.hoverVol === modelData.id)
                                        lib.hoverVol = -1;
                                }
                                onClicked: {
                                    const p = cover.mapToItem(lib, 0, 0);
                                    lib.pick(modelData.id, Qt.rect(p.x, p.y, cover.width, cover.height), coverImg.source);
                                }
                                Appear { shown: lib.shown; delay: 160 + Math.min(row.index, 6) * 60 + Math.min(vc.index, 10) * 25; lift: 10 }

                                ClippingRectangle {
                                    id: cover
                                    x: 8
                                    y: 8
                                    width: rowsView.coverW
                                    height: rowsView.coverH
                                    radius: vc.hovered ? Motion.shapeLarge : Motion.shapeMedium
                                    Behavior on radius { Spring { speed: "fast" } }
                                    color: Colors.surface_container_high
                                    opacity: vc.fin ? 0.55 : 1
                                    Behavior on opacity { Fade {} }
                                    scale: vc.hovered ? 1.04 : 1
                                    Behavior on scale { Spring { speed: "fast" } }
                                    Image {
                                        id: coverImg
                                        anchors.fill: parent
                                        source: Manga.cover(vc.modelData.cover)
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                    }
                                    // reading progress along the bottom of the cover
                                    Rectangle {
                                        anchors.left: parent.left
                                        anchors.bottom: parent.bottom
                                        height: 6
                                        width: parent.width * lib.pct(vc.modelData)
                                        visible: vc.prog
                                        color: Colors.primary
                                        Behavior on width { Spring { speed: "default" } }
                                    }
                                }
                                StyledText {
                                    anchors.left: cover.left
                                    anchors.right: cover.right
                                    anchors.top: cover.bottom
                                    anchors.topMargin: 6
                                    role: "labelLarge"
                                    emphasized: true
                                    jp: true
                                    elide: Text.ElideRight
                                    color: vc.prog ? Colors.on_secondary_container : Colors.on_surface
                                    text: vc.modelData.title
                                }
                                // finished
                                ShapeBadge {
                                    anchors { top: cover.top; right: cover.right; margins: 6 }
                                    width: 28
                                    height: 28
                                    z: 2
                                    badgeScale: vc.fin ? 1 : 0
                                    visible: badgeScale > 0.02
                                    shapeRest: "cookie9"
                                    shapeActive: "sunny"
                                    color: Colors.tertiary_container
                                    Icon {
                                        anchors.centerIn: parent
                                        name: "check"
                                        size: 18
                                        color: Colors.on_tertiary_container
                                    }
                                }
                                // in progress
                                WavyRing {
                                    anchors { top: cover.top; right: cover.right; margins: 6 }
                                    width: 34
                                    height: 34
                                    z: 2
                                    thickness: 4
                                    amplitude: 1.2
                                    waves: 8
                                    gap: 20
                                    value: lib.pct(vc.modelData)
                                    waving: lib.shown && vc.prog
                                    opacity: vc.prog ? 1 : 0
                                    visible: opacity > 0.01
                                    Behavior on opacity { Fade {} }
                                }
                                // the volume to read next
                                ShapeBadge {
                                    anchors { top: cover.top; left: cover.left; margins: 6 }
                                    width: 40
                                    height: 40
                                    z: 2
                                    badgeScale: vc.isNext ? 1 : 0
                                    visible: badgeScale > 0.02
                                    spinning: vc.isNext && lib.shown
                                    shapeRest: "softBurst"
                                    shapeActive: "sunny"
                                    color: Colors.primary
                                    StyledText {
                                        anchors.centerIn: parent
                                        role: "labelSmall"
                                        emphasized: true
                                        color: Colors.on_primary
                                        text: "NEXT"
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        // "more below": the rows are whole, so say there are more
        Clickable {
            id: more
            readonly property int rowCount: lib.series.length
            readonly property bool atEnd: rowsView.contentY >= rowsView.maxY() - 1
            readonly property int below: Math.max(0, rowCount - rowsView.fitRows - Math.round(rowsView.contentY / rowsView.rowPitch))
            readonly property bool wanted: rowsView.contentHeight > rowsView.height + 1
            anchors.horizontalCenter: parent.horizontalCenter
            y: rowsView.height + (rowsArea.height - rowsView.height - height) / 2
            implicitWidth: moreRow.implicitWidth + 36
            implicitHeight: 36
            restRadius: Motion.shapeLarge
            color: Colors.surface_container_high
            contentColor: Colors.on_surface
            opacity: wanted ? 1 : 0
            scale: wanted ? 1 : 0.8
            visible: opacity > 0.01
            Behavior on opacity { Fade {} }
            Behavior on scale { Spring {} }
            onClicked: sy.target = rowsView.snapY(atEnd ? 0 : (sy.moving ? sy.target : rowsView.contentY) + rowsView.rowPitch)
            Row {
                id: moreRow
                anchors.centerIn: parent
                spacing: 8
                Icon {
                    id: moreIcon
                    anchors.verticalCenter: parent.verticalCenter
                    name: "expand_more"
                    size: 20
                    color: more.contentColor
                    kick: false
                    rotation: more.atEnd ? 180 : 0
                    Behavior on rotation { Spring {} }
                    transform: Translate { id: bob; y: 0 }
                    SequentialAnimation {
                        running: more.visible && !more.atEnd
                        loops: Animation.Infinite
                        NumberAnimation { target: bob; property: "y"; to: 3; duration: 800; easing.type: Easing.InOutSine }
                        NumberAnimation { target: bob; property: "y"; to: 0; duration: 800; easing.type: Easing.InOutSine }
                    }
                }
                SwapText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "labelLarge"
                    emphasized: true
                    color: more.contentColor
                    value: more.atEnd ? "Back to top" : more.below + " more"
                }
            }
        }
        }
    }

    // nothing to show yet
    ColumnLayout {
        anchors.centerIn: parent
        spacing: 12
        visible: lib.series.length === 0
        LoadingIndicator {
            Layout.alignment: Qt.AlignHCenter
            visible: Manga.ready && !Manga.libraryLoaded
        }
        StyledText {
            Layout.alignment: Qt.AlignHCenter
            role: "titleMedium"
            color: Colors.on_surface_variant
            text: Manga.missing ? "The manga helper is not installed: run reader/install.sh" : Manga.libraryLoaded ? "No manga found in the library folders" : "Reading the library"
        }
    }

    // Enter continues
    function continueHero() {
        if (hero)
            pick(hero.vol.id, Qt.rect(heroCover.mapToItem(lib, 0, 0).x, heroCover.mapToItem(lib, 0, 0).y, heroCover.width, heroCover.height), heroCover.source);
    }
}
