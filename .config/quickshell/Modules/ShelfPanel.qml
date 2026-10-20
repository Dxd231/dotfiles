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
    property string filter: "all" // all | video (shown as Anime) | book | manga
    readonly property bool hovering: edgeHover.hovered || panelHover.hovered

    // overlays inside the panel: "" | "fix" (pick another AniList entry) | "connect"
    property string sheet: ""
    property var target: null     // the series being fixed or acted on
    property string menu: ""      // "" | "card" | "account"
    // a show with several seasons/movies opens as its own shelf of parts
    property string showKey: ""
    readonly property var show: showKey === "" ? null : (Immersion.seriesList.find(s => s.key === showKey) || null)
    property real menuX: 0
    property real menuY: 0
    onMenuChanged: if (menu === "" && open && !hovering) leaveTimer.restart()
    onSheetChanged: if (sheet === "" && open && !hovering) leaveTimer.restart()
    property string pinKey: ""
    property bool targetPinned: false
    onOpenChanged: {
        if (open) {
            Immersion.rescanCovers();
        } else {
            sheet = "";
            menu = "";
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
    function openFix(s) {
        target = s;
        menu = "";
        sheet = "fix";
        AniList.search(searchTerm(s));
    }

    readonly property var items: Immersion.seriesList.filter(s => filter === "all" || kindOf(s) === filter)
    readonly property var shown: show ? show.parts : items
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
        else
            Quickshell.execDetached(["librewolf", "--new-window", k === "book" ? (s.url || "https://reader.ttsu.app/") : (s.url || "http://localhost:5000/")]);
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
    Timer { id: dwellTimer; interval: 200; onTriggered: if (root.hovering) root.open = true }
    Timer { id: leaveTimer; interval: 1200; onTriggered: if (!root.hovering && root.menu === "" && root.sheet === "") root.open = false }

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
        visible: root.open || panel.opacity > 0
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
        }

        Rectangle {
            id: panel
            y: 0
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
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    IconButton {
                        visible: root.show !== null
                        icon: "arrow_back"
                        onClicked: root.showKey = ""
                    }
                    StyledText {
                        Layout.leftMargin: 4
                        Layout.fillWidth: true
                        jp: root.show !== null
                        role: root.show ? "titleLarge" : "headlineSmall"
                        emphasized: true
                        text: root.show ? root.showTitle : "Shelf"
                        elide: Text.ElideRight
                        color: Colors.on_surface
                    }
                    Button {
                        id: account
                        visible: root.show === null
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

                Row {
                    visible: root.show === null
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

                GridView {
                    id: grid
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
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
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: m => {
                                if (m.button === Qt.RightButton) {
                                    const p = tile.mapToItem(panel, m.x, m.y);
                                    root.target = root.partOf(cell.modelData);
                                    root.pinKey = root.show ? "" : cell.modelData.key;
                                    root.targetPinned = !!cell.modelData.pinned;
                                    root.menuX = Math.min(p.x, panel.width - 188);
                                    root.menuY = Math.min(p.y, panel.height - 150);
                                    root.menu = "card";
                                } else if (m.button === Qt.LeftButton) {
                                    if (cell.modelData.partCount > 1)
                                        root.showKey = cell.modelData.key;
                                    else
                                        root.launch(cell.modelData);
                                }
                            }

                            Appear {
                                shown: root.open
                                delay: Math.min(cell.index, 8) * 30
                            }

                            ColumnLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 6

                                ClippingRectangle {
                                    id: art
                                    Layout.fillWidth: true
                                    Layout.fillHeight: true
                                    radius: Motion.shapeMedium
                                    color: Colors.secondary_container

                                    Image {
                                        id: coverImg
                                        anchors.fill: parent
                                        visible: status === Image.Ready
                                        source: cell.modelData.cover ? "file://" + cell.modelData.cover : ""
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 240
                                    }
                                    ShapeBadge {
                                        anchors { top: parent.top; right: parent.right; margins: 6 }
                                        width: 28
                                        height: 28
                                        visible: !!cell.modelData.pinned
                                        z: 2
                                        shapeRest: 7
                                        shapeActive: 4
                                        active: tile.hovered
                                        spinning: tile.hovered
                                        color: Colors.tertiary_container
                                    }
                                    ShapeBadge {
                                        anchors.centerIn: parent
                                        width: 56
                                        height: 56
                                        visible: !cell.modelData.cover || coverImg.status === Image.Error
                                        shapeRest: 5
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

                                WavyProgress {
                                    Layout.fillWidth: true
                                    Layout.preferredHeight: 8
                                    visible: cell.modelData.progress !== null && cell.modelData.progress !== undefined
                                    value: cell.modelData.progress || 0
                                    thickness: 4
                                    amplitude: 1.5
                                    wavelength: 16
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
                        visible: root.shown.length === 0
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
            Rectangle {
                id: menuCard
                visible: root.menu !== ""
                x: root.menuX
                y: root.menuY
                width: 180
                height: menuCol.implicitHeight + 16
                radius: Motion.shapeLarge
                color: Colors.surface_container_highest

                Column {
                    id: menuCol
                    anchors.fill: parent
                    anchors.margins: 8
                    spacing: 2
                    Repeater {
                        model: root.menu === "card" ? [
                            { id: "pin", text: root.targetPinned ? "Unpin" : "Pin", icon: "push_pin", on: root.pinKey !== "" },
                            { id: "open", text: "Open on AniList", icon: "open_in_new", on: !!AniList.entryFor(root.target ? root.target.key : "", root.target ? root.target.season : 1) && root.kindOf(root.target) === "video" },
                            { id: "fix", text: "Fix match…", icon: "edit", on: root.kindOf(root.target) === "video" },
                            { id: "unlink", text: "Unlink", icon: "link_off", on: root.kindOf(root.target) === "video" }
                        ] : root.menu === "account" ? [
                            { id: "sync", text: "Sync now", icon: "sync", on: true },
                            { id: "out", text: "Disconnect", icon: "logout", on: true }
                        ] : []
                        Button {
                            required property var modelData
                            width: menuCol.width
                            size: "xs"
                            style: "text"
                            enabled: modelData.on
                            text: modelData.text
                            icon: modelData.icon
                            onClicked: {
                                const t = root.target;
                                root.menu = "";
                                if (modelData.id === "pin")
                                    Immersion.togglePin(root.pinKey);
                                else if (modelData.id === "open")
                                    AniList.openEntry(t.key, t.season);
                                else if (modelData.id === "fix")
                                    root.openFix(t);
                                else if (modelData.id === "unlink")
                                    AniList.pin(t.key, t.season, null, root.searchTerm(t));
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
                            text: root.sheet === "fix" ? "Pick the right anime" : "Connect AniList"
                            color: Colors.on_surface
                        }
                    }

                    // fix match
                    TextField {
                        Layout.fillWidth: true
                        visible: root.sheet === "fix"
                        label: "Search AniList"
                        leadingIcon: "search"
                        text: root.target ? root.searchTerm(root.target) : ""
                        onAccepted: t => AniList.search(t)
                    }
                    ListView {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        visible: root.sheet === "fix"
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
                                AniList.pin(root.target.key, root.target.season, hit.modelData.id, root.searchTerm(root.target));
                                root.sheet = "";
                            }
                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: 8
                                spacing: 10
                                ClippingRectangle {
                                    Layout.fillHeight: true
                                    Layout.preferredWidth: 46
                                    radius: Motion.shapeSmall
                                    color: Colors.secondary_container
                                    Image {
                                        anchors.fill: parent
                                        source: hit.modelData.cover
                                        fillMode: Image.PreserveAspectCrop
                                        asynchronous: true
                                        sourceSize.width: 120
                                    }
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
                                        text: [hit.modelData.year, hit.modelData.format, hit.modelData.episodes ? hit.modelData.episodes + " eps" : ""].filter(x => x).join("  ·  ")
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
                        visible: root.sheet === "connect"
                        role: "bodyMedium"
                        wrapMode: Text.Wrap
                        color: Colors.on_surface_variant
                        text: "Create a client at anilist.co/settings/developer with the redirect URL https://anilist.co/api/v2/oauth/pin, paste its ID, authorize, then paste the token AniList shows you."
                    }
                    TextField {
                        id: clientField
                        Layout.fillWidth: true
                        visible: root.sheet === "connect"
                        label: "Client ID"
                        leadingIcon: "key"
                        text: AniList.clientId
                        onAccepted: t => AniList.saveClient(t)
                    }
                    Button {
                        visible: root.sheet === "connect"
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
                        visible: root.sheet === "connect"
                        label: "Token"
                        leadingIcon: "lock"
                        password: true
                        onAccepted: t => AniList.login(t.trim(), clientField.text.trim())
                    }
                    StyledText {
                        visible: root.sheet === "connect" && AniList.loginFailed
                        role: "labelMedium"
                        text: "AniList didn't accept that token"
                        color: Colors.error
                    }
                    Button {
                        visible: root.sheet === "connect"
                        icon: "check"
                        text: "Connect"
                        enabled: tokenField.text.trim() !== ""
                        onClicked: AniList.login(tokenField.text.trim(), clientField.text.trim())
                    }
                    Item { Layout.fillHeight: true; visible: root.sheet === "connect" }
                }
            }
        }
    }
}
