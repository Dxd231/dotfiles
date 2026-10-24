pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Media shelf: a card on the right edge that opens when the pointer rests on the upper half of the
// right screen edge and closes a moment after it leaves. Lists everything the immersion tracker has seen (videos, books, manga).
Scope {
    id: root

    property bool open: false
    // cards built after the opening stagger (by scrolling) appear at rest
    property bool cardsSettled: false
    function _restage() {
        cardsSettled = false;
        settleTimer.restart();
    }
    onFilterChanged: _restage()
    onShowKeyChanged: _restage()
    Timer { id: settleTimer; interval: 600; onTriggered: root.cardsSettled = true }
    property bool pinned: false   // stays open when the pointer leaves
    property string filter: "all" // all | video (shown as Anime) | book | manga
    readonly property bool hovering: edgeHover.hovered || panelHover.hovered

    // overlays inside the panel: "" | "fix" (pick another AniList entry) | "connect"
    property string sheet: ""
    // the sheet that was last up: its contents stay while the card fades out, instead of emptying first
    property string lastSheet: ""
    property var target: null     // the series being fixed or acted on
    property string menu: ""      // "" | "card" | "account"
    // a show with several seasons/movies opens as its own shelf of parts
    property string showKey: ""
    readonly property var show: showKey === "" ? null : (Immersion.shelfList.find(s => s.key === showKey) || null)
    property real menuX: 0
    property real menuY: 0
    // the menu keeps its entries while the exit animation plays
    property string menuShown: ""
    onMenuChanged: {
        if (menu !== "")
            menuShown = menu;
        else if (open && !hovering)
            leaveTimer.restart();
    }
    onSheetChanged: {
        if (sheet !== "")
            lastSheet = sheet;
        else if (open && !hovering)
            leaveTimer.restart();
    }
    property string pinKey: ""
    property bool targetPinned: false
    // the card the menu was opened on, for "Remove from shelf"
    property var menuItem: null
    onOpenChanged: {
        if (open) {
            _restage();
            Immersion.rescanCovers();
        } else {
            sheet = "";
            menu = "";
            pinned = false;
        }
    }
    Connections {
        target: AniList
        function onConnectedChanged() {
            if (AniList.connected && root.sheet === "connect")
                root.sheet = "";
        }
    }
    // what a card stands for when it is acted on: a show card acts on the part it displays
    function partOf(s) {
        return s.parts ? (s.parts.find(p => p.key === s.matchKey && p.season === s.season) || s) : s;
    }
    function searchTerm(s) {
        return s.showName ? (s.partKind === "season" ? s.showName : s.showName + " " + s.name) : s.name;
    }
    // manga cards are matched by their reader series key, as "manga:<key>"
    function isManga(s) { return !!s && kindOf(s) === "manga"; }
    function alKey(s) { return isManga(s) ? AniList.mangaKey(String(s.key).replace(/^kavitaw:/, "")) : (s ? s.key : ""); }
    function alSeason(s) { return isManga(s) ? 1 : (s ? s.season : 1); }
    function alType(s) { return isManga(s) ? "MANGA" : "ANIME"; }
    function openFix(s) {
        target = s;
        menu = "";
        sheet = "fix";
        AniList.search(searchTerm(s), alType(s));
    }

    readonly property var items: Immersion.shelfList.filter(s => (filter === "all" || kindOf(s) === filter) && Immersion.onShelf(s.key, s.last))
    // inside a show, pinned parts lead (newest pin first); the rest keep their season/volume order
    readonly property var shown: show ? show.parts.filter(p => Immersion.onShelf(Immersion.partId(p), p.last)).map((p, i) => ({ p: p, i: i, r: Immersion.pins.indexOf(Immersion.partId(p)) }))
        .sort((a, b) => (b.r >= 0 ? 1 : 0) - (a.r >= 0 ? 1 : 0) || (a.r >= 0 ? a.r - b.r : a.i - b.i)).map(x => x.p) : items
    readonly property string showTitle: {
        if (!show)
            return "";
        if (show.kind !== "video")
            return show.name;
        const lead = show.parts.find(p => p.partKind === "season") || show.parts[0];
        return lead.title || show.name;
    }
    function partLabel(s) {
        return s.partKind === "season" ? "S" + s.season : s.partKind === "ova" ? "OVA" : s.partKind === "sp" ? "Specials" : "Movie";
    }
    function kindOf(s) { return s.kind === "book" ? "book" : s.kind === "manga" ? "manga" : "video"; }
    function detailOf(s) {
        const k = kindOf(s);
        const t = Immersion.fmt(s.minutes);
        if (k === "video") {
            const bits = [];
            const multi = s.partCount > 1;
            if (multi || (root.show && s.partKind !== "movie"))
                bits.push(partLabel(s));
            if (s.partKind === "movie")
                bits.push(multi ? "" : t, multi ? "" : "movie");
            else if (s.total > 0)
                bits.push("E" + s.watchedEp + " / " + s.total);
            else if (!multi)
                bits.push(s.episodes + (s.episodes === 1 ? " episode" : " episodes"));
            bits.push(multi ? s.partCount + " parts" : t);
            return bits.filter(x => x !== "").join("  ·  ");
        }
        const multi = s.partCount > 1;
        const bits = [multi ? s.partName : (root.show ? s.name : ""), t];
        if (multi)
            bits.push(s.partCount + " volumes");
        else if (k === "manga" && s.pages)
            bits.push(s.pages + (s.pages === 1 ? " page" : " pages"));
        else if (s.chars)
            bits.push(Math.round(s.chars).toLocaleString(Qt.locale(), "f", 0) + " chars");
        return bits.filter(x => x !== "").join("  ·  ");
    }
    function launch(s) {
        const k = kindOf(s);
        if (k === "video")
            Mpv.resume(s.path);
        else if (k === "manga")
            Manga.show(s.mangaVol !== undefined ? s.mangaVol : -1);
        else
            Quickshell.execDetached(["firefoxpwa", "site", "launch", k === "book" ? "01M5F7S7MNGA0WFV86QGD8QGH2" : "01M5F5Z39BPG6NBAW4YSZQFAB8"].concat(s.url ? ["--url", s.url] : []));
        if (!pinned)
            open = false;
    }

    onHoveringChanged: {
        if (hovering) {
            leaveTimer.stop();
            if (!open)
                dwellTimer.restart();
        } else {
            dwellTimer.stop();
            if (open)
                leaveTimer.restart();
        }
    }
    // a short rest in the corner opens it, so a pointer passing through doesn't
    Timer { id: dwellTimer; interval: 400; onTriggered: if (root.hovering) root.open = true }
    Timer { id: leaveTimer; interval: 1200; onTriggered: if (!root.hovering && !root.pinned && root.menu === "" && root.sheet === "") root.open = false }

    IpcHandler {
        target: "shelf"
        function toggle(): void { root.open = !root.open; }
        function show(): void { root.open = true; }
        function hide(): void { root.open = false; }
        function filter(kind: string): void { root.filter = kind; }
        // open the shelf of a show's seasons and movies ("" goes back)
        function parts(key: string): void { root.showKey = key; }
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:shelf_edge"
        // the right edge belongs to the subtitle transcript while the interactive subtitles are up
        visible: !Lexicon.overlayOn
        WlrLayershell.layer: WlrLayer.Overlay
        anchors { top: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: 2
        implicitHeight: screen ? Math.round(screen.height / 2) : 400
        color: "transparent"

        HoverHandler { id: edgeHover }
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:shelf"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.sheet !== "" ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        // stays mapped while closed (the panel hides instead): remapping the surface cost a ~80 ms frame
        // right as the slide-in started
        anchors { top: true; right: true; bottom: true }
        margins.top: 64
        exclusionMode: ExclusionMode.Ignore
        implicitWidth: panel.width + 40
        color: "transparent"
        mask: Region { item: panel }

        Elevation {
            x: panel.x
            y: panel.y
            width: panel.width
            height: panel.height
            radius: panel.radius
            level: 3
            opacity: panel.opacity
            visible: panel.visible
        }

        Rectangle {
            id: panel
            y: 0
            visible: root.open || opacity > 0
            width: 380
            height: parent.height - 8
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container
            x: root.open ? parent.width - width - 8 : parent.width
            opacity: root.open ? 1 : 0
            Behavior on x { Spring { speed: "default"; expressive: root.open } }
            Behavior on opacity { Fade { speed: "default" } }

            HoverHandler { id: panelHover }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 0

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Collapse {
                        id: backCollapse
                        horizontal: true
                        open: root.show !== null
                        IconButton {
                            icon: "arrow_back"
                            onClicked: root.showKey = ""
                        }
                    }
                    SwapText {
                        // the type style changes with the words, at the hidden point of the swap, not before
                        property bool sub: false
                        Layout.leftMargin: 4 + 5 * backCollapse._r
                        Layout.rightMargin: 0
                        Layout.fillWidth: true
                        jp: sub
                        role: sub ? "titleLarge" : "headlineSmall"
                        emphasized: true
                        value: root.show ? root.showTitle : "Shelf"
                        onTextChanged: sub = root.show !== null
                        elide: Text.ElideRight
                        color: Colors.on_surface
                    }
                    Collapse {
                        horizontal: true
                        gap: 5
                        open: root.show === null
                        IconButton {
                            icon: "push_pin"
                            checkable: true
                            checked: root.pinned
                            onClicked: root.pinned = !root.pinned
                        }
                    }
                    Collapse {
                        horizontal: true
                        gap: 5
                        open: root.show === null
                        Button {
                            id: account
                            size: "xs"
                            style: "tonal"
                            icon: "sync"
                            text: AniList.connected ? AniList.viewer.name : "AniList"
                            highlighted: root.menu === "account"
                            onClicked: {
                                if (!AniList.connected) {
                                    root.sheet = "connect";
                                    return;
                                }
                                const p = account.mapToItem(panel, 0, account.height + 4);
                                root.menuX = Math.min(p.x, panel.width - 188);
                                root.menuY = p.y;
                                root.menu = "account";
                            }
                        }
                    }
                }

                Collapse {
                    open: root.show === null
                    gap: 12
                    Row {
                        spacing: 2
                        Repeater {
                            model: [
                                { id: "all", text: "All", icon: "apps" },
                                { id: "video", text: "Anime", icon: "movie" },
                                { id: "book", text: "Book", icon: "menu_book" },
                                { id: "manga", text: "Manga", icon: "auto_stories" }
                            ]
                            ConnectedButton {
                                required property var modelData
                                required property int index
                                height: 36
                                text: modelData.text
                                icon: modelData.icon
                                position: index === 0 ? "first" : index === 3 ? "last" : "middle"
                                selected: root.filter === modelData.id
                                onClicked: root.filter = modelData.id
                            }
                        }
                    }
                }

                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.topMargin: 12
                    Layout.fillHeight: true
                    clip: true
                    cacheBuffer: height
                    cellWidth: width / 2
                    // three full rows always fit the opened shelf; the cover absorbs the height
                    cellHeight: Math.floor(height / 3)
                    model: root.shown
                    boundsBehavior: Flickable.StopAtBounds

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight

                        Clickable {
                            id: tile
                            anchors.fill: parent
                            anchors.margins: 4
                            restRadius: Motion.shapeLarge
                            pressedRadius: Motion.shapeMedium
                            color: Colors.surface_container_high
                            contentColor: Colors.on_surface
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onClicked: m => {
                                if (m.button === Qt.RightButton) {
                                    const p = tile.mapToItem(panel, m.x, m.y);
                                    root.target = root.partOf(cell.modelData);
                                    root.pinKey = root.show ? Immersion.partId(cell.modelData) : cell.modelData.key;
                                    root.targetPinned = !!cell.modelData.pinned;
                                    root.menuItem = cell.modelData;
                                    root.menuX = Math.min(p.x, panel.width - 188);
                                    root.menuY = Math.min(p.y, panel.height - 186);
                                    root.menu = "card";
                                } else if (m.button === Qt.MiddleButton) {
                                    // straight to the part the card shows
                                    root.launch(cell.modelData.face || cell.modelData);
                                } else if (m.button === Qt.LeftButton) {
                                    if (cell.modelData.partCount > 1)
                                        root.showKey = cell.modelData.key;
                                    else
                                        root.launch(cell.modelData);
                                }
                            }

                            Appear {
                                shown: root.open
                                instant: root.cardsSettled
                                delay: Math.min(cell.index, 8) * 30
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 6

                                Item {
                                    id: art
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true

                                    // one step below the card's corners, so they nest
                                    ClippingRectangle {
                                        anchors.fill: parent
                                        radius: tile.pressed ? Motion.shapeSmall : Motion.shapeMedium
                                        Behavior on radius { Spring {} }
                                        color: "transparent"
                                        Image {
                                            id: coverImg
                                            anchors.fill: parent
                                            source: cell.modelData.cover ? "file://" + cell.modelData.cover : ""
                                            sourceSize.width: 240
                                            fillMode: Image.PreserveAspectCrop
                                            asynchronous: true
                                            opacity: status === Image.Ready ? 1 : 0
                                            Behavior on opacity { Fade {} }
                                        }
                                    }
                                    ShapeBadge {
                                        anchors { top: parent.top; right: parent.right; margins: 6 }
                                        width: 28
                                        height: 28
                                        badgeScale: cell.modelData.pinned ? 1 : 0
                                        visible: badgeScale > 0.02
                                        z: 2
                                        shapeRest: "star4"
                                        shapeActive: "sunny"
                                        active: tile.hovered
                                        spinning: tile.hovered
                                        color: Colors.tertiary_container
                                    }
                                    ShapeBadge {
                                        anchors.centerIn: parent
                                        width: 56
                                        height: 56
                                        opacity: !cell.modelData.cover || coverImg.status === Image.Error ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        shapeRest: root.kindOf(cell.modelData) === "video" ? "clover4" : root.kindOf(cell.modelData) === "manga" ? "pentagon" : "cookie4"
                                        spinning: root.open && tile.hovered
                                        color: Colors.primary_container
                                        Icon {
                                            anchors.centerIn: parent
                                            name: root.kindOf(cell.modelData) === "video" ? "movie" : "menu_book"
                                            size: 26
                                            color: Colors.on_primary_container
                                        }
                                    }
                                }

                                Collapse {
                                    open: cell.modelData.progress !== null && cell.modelData.progress !== undefined
                                    Layout.fillWidth: true
                                    WavyProgress {
                                        implicitHeight: 8
                                        value: cell.modelData.progress || 0
                                        thickness: 4
                                        amplitude: 1.5
                                        wavelength: 16
                                    }
                                }

                                StyledText {
                                    Layout.fillWidth: true
                                    jp: true
                                    role: "titleSmall"
                                    emphasized: true
                                    text: cell.modelData.title || cell.modelData.name
                                    color: Colors.on_surface
                                    maximumLineCount: 2
                                    wrapMode: Text.Wrap
                                    elide: Text.ElideRight
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "labelSmall"
                                    text: root.detailOf(cell.modelData)
                                    color: Colors.on_surface_variant
                                    elide: Text.ElideRight
                                }
                            }
                        }
                    }

                    ColumnLayout {
                        anchors.centerIn: parent
                        opacity: root.shown.length === 0 ? 1 : 0
                        scale: root.shown.length === 0 ? 1 : 0.9
                        visible: opacity > 0
                        Behavior on opacity { Fade { speed: "default" } }
                        Behavior on scale { Spring { speed: "default" } }
                        spacing: 8
                        Icon {
                            Layout.alignment: Qt.AlignHCenter
                            name: "menu_book"
                            size: 40
                            color: Colors.on_surface_variant
                        }
                        StyledText {
                            role: "bodyMedium"
                            text: "Nothing watched or read yet"
                            color: Colors.on_surface_variant
                        }
                    }
                }
            }

            // ---- menu (card / account) ----
            MouseArea {
                anchors.fill: parent
                visible: root.menu !== ""
                acceptedButtons: Qt.AllButtons
                onClicked: root.menu = ""
            }
            Elevation {
                anchors.fill: menuCard
                radius: menuCard.radius
                level: 2
                visible: menuCard.visible
                opacity: menuCard.opacity
                scale: menuCard.scale
                transformOrigin: menuCard.transformOrigin
            }
            Rectangle {
                id: menuCard
                visible: root.menu !== "" || opacity > 0
                x: root.menuX
                y: root.menuY
                Behavior on x { Spring { speed: "fast" } }
                Behavior on y { Spring { speed: "fast" } }
                width: 180
                height: menuCol.implicitHeight + 16
                radius: Motion.shapeLarge
                color: Colors.surface_container_highest
                transformOrigin: Item.TopLeft
                opacity: 0
                scale: 0.9

                states: State {
                    name: "open"
                    when: root.menu !== ""
                    PropertyChanges { menuCard.opacity: 1; menuCard.scale: 1 }
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

                Column {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2
                    Repeater {
                        model: root.menuShown === "card" ? [
                            { id: "pin", text: root.targetPinned ? "Unpin" : "Pin", icon: "push_pin", on: root.pinKey !== "" },
                            { id: "open", text: "Open on AniList", icon: "open_in_new", on: !!AniList.entryFor(root.alKey(root.target), root.alSeason(root.target)) && root.kindOf(root.target) !== "book" },
                            { id: "fix", text: "Fix match…", icon: "edit", on: root.kindOf(root.target) !== "book" },
                            { id: "unlink", text: "Unlink", icon: "link_off", on: root.kindOf(root.target) !== "book" },
                            { id: "remove", text: "Remove from shelf", icon: "delete", on: root.pinKey !== "" }
                        ] : root.menuShown === "account" ? [
                            { id: "sync", text: "Sync now", icon: "sync", on: true },
                            { id: "out", text: "Disconnect", icon: "logout", on: true }
                        ] : []
                        Button {
                            required property var modelData
                            required property int index
                            width: menuCol.width
                            size: "xs"
                            style: "text"
                            enabled: modelData.on
                            text: modelData.text
                            icon: modelData.icon
                            Appear {
                                shown: root.menu !== ""
                                delay: index * 18
                                lift: 6
                                from: 0.96
                            }
                            onClicked: {
                                const t = root.target;
                                root.menu = "";
                                if (modelData.id === "pin")
                                    Immersion.togglePin(root.pinKey);
                                else if (modelData.id === "open")
                                    AniList.openEntry(root.alKey(t), root.alSeason(t));
                                else if (modelData.id === "fix")
                                    root.openFix(t);
                                else if (modelData.id === "unlink")
                                    AniList.pin(root.alKey(t), root.alSeason(t), null, root.searchTerm(t), root.alType(t));
                                else if (modelData.id === "remove") {
                                    const c = root.menuItem;
                                    const part = root.kindOf(c) === "video" ? root.partLabel(c) : c.name;
                                    Immersion.removeFromShelf(root.pinKey, c.last, root.show ? root.showTitle + " " + part : (c.title || c.name));
                                }
                                else if (modelData.id === "sync")
                                    AniList.syncProgress();
                                else
                                    AniList.logout();
                            }
                        }
                    }
                }
            }

            // ---- sheets ----
            Rectangle {
                id: sheetCard
                anchors.fill: parent
                radius: panel.radius
                color: Colors.surface_container
                visible: opacity > 0
                opacity: root.sheet !== "" ? 1 : 0
                Behavior on opacity { Fade { speed: "default" } }
                MouseArea { anchors.fill: parent }   // swallow clicks meant for the grid below

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 12

                    RowLayout {
                        Layout.fillWidth: true
                        IconButton {
                            icon: "arrow_back"
                            onClicked: root.sheet = ""
                        }
                        StyledText {
                            Layout.fillWidth: true
                            role: "titleLarge"
                            emphasized: true
                            text: root.lastSheet === "fix" ? (root.isManga(root.target) ? "Pick the right manga" : "Pick the right anime") : "Connect AniList"
                            color: Colors.on_surface
                        }
                    }

                    // fix match
                    TextField {
                        Layout.fillWidth: true
                        visible: root.lastSheet === "fix"
                        label: "Search AniList"
                        leadingIcon: "search"
                        text: root.target ? root.searchTerm(root.target) : ""
                        onAccepted: t => AniList.search(t, root.alType(root.target))
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.lastSheet === "fix"
                        clip: true
                        spacing: 6
                        model: AniList.searchResults
                        boundsBehavior: Flickable.StopAtBounds
                        delegate: Clickable {
                            id: hit
                            required property var modelData
                            width: ListView.view.width
                            height: 84
                            restRadius: Motion.shapeLarge
                            pressedRadius: Motion.shapeMedium
                            color: Colors.surface_container_high
                            contentColor: Colors.on_surface
                            onClicked: {
                                AniList.pin(root.alKey(root.target), root.alSeason(root.target), hit.modelData.id, root.searchTerm(root.target), root.alType(root.target));
                                root.sheet = "";
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10
                                ShapeMask {
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 46
                                    source: hit.modelData.cover
                                    sourceWidth: 120
                                    shape: "cookie4"
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 2
                                    StyledText {
                                        Layout.fillWidth: true
                                        jp: true
                                        role: "titleSmall"
                                        emphasized: true
                                        text: hit.modelData.native || hit.modelData.romaji
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        role: "labelSmall"
                                        text: hit.modelData.romaji
                                        color: Colors.on_surface_variant
                                        elide: Text.ElideRight
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        role: "labelSmall"
                                        text: [hit.modelData.year, hit.modelData.format, hit.modelData.episodes ? hit.modelData.episodes + " eps" : "", hit.modelData.volumes ? hit.modelData.volumes + " vols" : ""].filter(x => x).join("  ·  ")
                                        color: Colors.on_surface_variant
                                        elide: Text.ElideRight
                                    }
                                }
                            }
                        }
                        StyledText {
                            anchors.centerIn: parent
                            visible: parent.count === 0
                            role: "bodyMedium"
                            text: AniList.searching ? "Searching…" : "No results"
                            color: Colors.on_surface_variant
                        }
                    }

                    // connect
                    StyledText {
                        Layout.fillWidth: true
                        visible: root.lastSheet === "connect"
                        role: "bodyMedium"
                        wrapMode: Text.Wrap
                        color: Colors.on_surface_variant
                        text: "Create a client at anilist.co/settings/developer with the redirect URL https://anilist.co/api/v2/oauth/pin, paste its ID, authorize, then paste the token AniList shows you."
                    }
                    TextField {
                        id: clientField
                        Layout.fillWidth: true
                        visible: root.lastSheet === "connect"
                        label: "Client ID"
                        leadingIcon: "key"
                        text: AniList.clientId
                        onAccepted: t => AniList.saveClient(t)
                    }
                    Button {
                        visible: root.lastSheet === "connect"
                        style: "tonal"
                        icon: "open_in_new"
                        text: "Authorize on AniList"
                        enabled: clientField.text.trim() !== ""
                        onClicked: {
                            AniList.saveClient(clientField.text.trim());
                            Quickshell.execDetached(["librewolf", "--new-window", AniList.authUrl(clientField.text.trim())]);
                        }
                    }
                    TextField {
                        id: tokenField
                        Layout.fillWidth: true
                        visible: root.lastSheet === "connect"
                        label: "Token"
                        leadingIcon: "lock"
                        password: true
                        onAccepted: t => AniList.login(t.trim(), clientField.text.trim())
                    }
                    StyledText {
                        visible: root.lastSheet === "connect" && AniList.loginFailed
                        role: "labelMedium"
                        text: "AniList didn't accept that token"
                        color: Colors.error
                    }
                    Button {
                        visible: root.lastSheet === "connect"
                        icon: "check"
                        text: "Connect"
                        enabled: tokenField.text.trim() !== ""
                        onClicked: AniList.login(tokenField.text.trim(), clientField.text.trim())
                    }
                    Item { Layout.fillHeight: true; visible: root.lastSheet === "connect" }
                }
            }
        }
    }
}
