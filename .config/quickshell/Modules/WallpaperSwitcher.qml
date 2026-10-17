pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components

// Wallpaper picker: a full-screen hero carousel over ~/Pictures/Wallpapers plus a random
// online slot, with matugen color mode / preference controls. Applying a wallpaper re-themes
// the whole shell (matugen writes colors.json, which Colors.qml watches).
Item {
    id: root


    property string wallpaperDir: "$HOME/Pictures/Wallpapers"
    property int cardWidth: 500
    property int cardHeight: 281

    // ---- look & feel knobs ----
    property real scrimOpacity: 0.6      // dimming behind the carousel (0 = none)
    property real centerScale: 1.05      // size of the selected card
    property real sideScale: 0.8         // size of every other card
    property real navRepeatMs: 90        // min time between steps while a key / the wheel is held

    property bool isOpen: false
    property string currentWallpaper: ""
    property int currentIndex: 0
    property bool wallpapersLoadedOnce: false
    property string colorMode: "dark"                 // "dark" | "light"
    property string schemeType: "scheme-content"
    property real contrast: 0.2                       // -1 .. 1
    property string colorPreference: "lightness"      // matugen --prefer: "lightness" | "darkness"

    property string _listing: ""                      // last file list, so reopening doesn't rebuild the carousel
    property double _lastNav: 0
    property bool snapNav: false                      // true for a moment when we jump (not slide) to the current wallpaper

    property bool previewFetching: false
    property string previewThumbUrl: ""   // remote URL shown directly in the card, nothing downloaded yet
    property string previewFileUrl: ""    // the full-res URL confirmDownload() will save -- same post as the thumb
    property string previewId: ""
    property string previewTags: ""       // file-name-safe tags of the previewed post, may be empty
    property bool fetchInProgress: false  // true only during the actual confirmDownload save

    // Fetches metadata for a high-quality, widescreen desktop wallpaper and points
    // the card at its remote thumbnail. Called whenever the panel opens, and again
    // on demand (right-click the card) to reroll without committing to a download.
    function fetchPreview() {
        if (root.previewFetching) return;
        root.previewFetching = true;

        const scriptPath = Qt.resolvedUrl("../scripts/fetch_wallpaper.py").toString().replace(/^file:\/\//, "");
        previewProc.command = ["python3", scriptPath];
        previewProc.running = false;
        previewProc.running = true;
    }

    Process {
        id: previewProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewFetching = false;
                const parts = text.trim().split("\t");
                if (parts.length < 3 || parts.slice(0, 3).some(p => p === "" || p === "null")) {
                    // left the old preview (if any) in place rather than blanking
                    // it out on a transient failure
                    return;
                }
                root.previewThumbUrl = parts[0];
                root.previewFileUrl = parts[1];
                root.previewId = parts[2];
                root.previewTags = parts[3] ?? "";
            }
        }
    }

    property var pendingDownloadCmd: []

    function executeDownload(cmd) {
        fetchProc.command = cmd;
        fetchProc.running = false;
        fetchProc.running = true;
    }

    Timer {
        id: downloadDelayTimer
        interval: Motion.short4 + 50
        repeat: false
        onTriggered: {
            if (root.pendingDownloadCmd.length > 0) {
                const cmd = root.pendingDownloadCmd;
                root.pendingDownloadCmd = [];
                root.executeDownload(cmd);
            }
        }
    }

    // Downloads the exact post currently shown as the preview -- deliberately
    // does not re-query the API, so what you confirm is what you saw.
    function confirmDownload() {
        if (root.fetchInProgress) return;
        if (root.previewFileUrl === "") {
            root.fetchPreview();
            return;
        }
        root.fetchInProgress = true;

        // url / dir / name go in as positional args rather than into the shell string; the post id keeps names unique
        const base = "konachan-" + root.previewId + (root.previewTags !== "" ? " " + root.previewTags : "");
        const cmd = ["sh", "-c",
            'ext="${1##*.}"; mkdir -p "$2" && out="$2/$3.$ext" && curl -sLf -A "Mozilla/5.0" -o "$out" "$1" && echo "$out"',
            "sh", root.previewFileUrl, root.wallpaperDir.replace("$HOME", Quickshell.env("HOME")), base];

        root.previewThumbUrl = "";
        root.previewFileUrl = "";
        root.previewId = "";
        root.previewTags = "";

        if (root.isOpen || stage.openT > 0.001) {
            root.pendingDownloadCmd = cmd;
            root.isOpen = false;
            downloadDelayTimer.restart();
        } else {
            root.executeDownload(cmd);
        }
    }

    Process {
        id: fetchProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.fetchInProgress = false;
                const savedPath = text.trim();
                if (savedPath === "") {
                    // curl failed -- network down, the post vanished between
                    // preview and confirm, etc. Surface this however you want;
                    // at minimum don't silently pretend it worked.
                    return;
                }
                // Immediately apply wallpaper and color scheme
                root.applyWallpaper(savedPath, 0);

                // clear so the next time the panel opens, fetchPreview() rolls
                // a fresh one instead of showing the just-downloaded post again
                root.previewThumbUrl = "";
                root.previewFileUrl = "";
                root.previewId = "";
                root.previewTags = "";
                root.isOpen = false;   // next open's refreshWallpapers() picks up the new file
            }
        }
    }

    Timer {
        id: snapTimer
        interval: 150
        onTriggered: root.snapNav = false
    }


    readonly property string selectedPath: (wallpaperModel.count > 0 && root.currentIndex >= 0 && root.currentIndex < wallpaperModel.count) ? wallpaperModel.get(root.currentIndex).path : ""
    readonly property string selectedName: root.selectedPath.split("/").pop().replace(/\.[^.]+$/, "")
    readonly property bool isSelectedFetch: (wallpaperModel.count > 0 && root.currentIndex >= 0 && root.currentIndex < wallpaperModel.count) ? (wallpaperModel.get(root.currentIndex).isFetch === true) : false

    function toggleColorMode() {
        root.setColorMode(root.colorMode === "dark" ? "light" : "dark");
    }

    function setColorMode(mode) {
        if (mode !== "dark" && mode !== "light")
            return;
        root.colorMode = mode;
        root.saveColorMode(mode);
        root.applyColorMode();
    }

    function applyColorMode() {
        const wp = root.currentWallpaper !== "" ? root.currentWallpaper : root.selectedPath;
        if (!wp)
            return;
        var safePath = wp.replace(/'/g, "'\\''");
        var matugenCmd = "(matugen image '" + safePath + "' -m " + root.colorMode + " --type " + root.schemeType + " --contrast " + root.contrast + " --prefer " + root.colorPreference + "; ~/.config/matugen/post-hook-scripts/cursor_matugen.sh) >/dev/null 2>&1 &";
        applyProc.command = ["sh", "-c", matugenCmd];
        applyProc.running = false;
        applyProc.running = true;
    }

    function toggleColorPreference() {
        root.setColorPreference(root.colorPreference === "darkness" ? "lightness" : "darkness");
    }

    function setColorPreference(pref) {
        if (pref !== "darkness" && pref !== "lightness")
            return;
        root.colorPreference = pref;
        root.saveColorPreference(pref);
        root.applyColorMode();
    }



    // awww may report just the file name or the full path, so accept either
    function samePath(p, cur) {
        if (cur === "")
            return false;
        if (p === cur)
            return true;
        return cur.indexOf("/") === -1 && p.split("/").pop() === cur;
    }

    function indexOfPath(path) {
        for (let i = 0; i < wallpaperModel.count; i++) {
            if (root.samePath(wallpaperModel.get(i).path, path))
                return i;
        }
        return -1;
    }

    // jump the carousel to an index without the slide animation (used when opening)
    function focusIndex(i, instant) {
        if (i < 0 || i >= wallpaperModel.count)
            return;
        if (instant) {
            root.snapNav = true;
            snapTimer.restart();
        }
        coverflow.currentIndex = i;
        coverflow.positionViewAtIndex(i, ListView.Center);
    }

    function focusCurrent(instant) {
        root.focusIndex(root.indexOfPath(root.currentWallpaper), instant);
    }

    // remember the active wallpaper across restarts: $XDG_STATE_HOME/quickshell/current-wallpaper
    function saveCurrent(path) {
        saveCurrentProc.payload = path;
        saveCurrentProc.running = false;
        saveCurrentProc.running = true;
    }

    function step(delta, throttled) {
        if (coverflow.count === 0)
            return;
        const now = Date.now();
        if (throttled && now - root._lastNav < root.navRepeatMs)
            return;
        root._lastNav = now;
        coverflow.currentIndex = Math.max(0, Math.min(coverflow.count - 1, coverflow.currentIndex + delta));
    }

    onIsOpenChanged: {
        if (root.isOpen) {
            root.focusCurrent(true);     // cached list: already on the active wallpaper before anything is visible
            root.refreshWallpapers();
            root.fetchPreview();
            Qt.callLater(() => coverflow.forceActiveFocus());
        }
    }

    ListModel {
        id: wallpaperModel
    }

    // One process does both jobs so there's no race: ask awww what's active, then list the folder.
    Process {
        id: listProc
        command: ["sh", "-c", "awww query 2>/dev/null; echo @@@; find " + root.wallpaperDir + " -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]

        stdout: StdioCollector {
            onStreamFinished: {
                const parts = text.split(/^@@@$/m);

                const listing = (parts[1] || "").trim();
                const lines = listing.length > 0 ? listing.split("\n") : [];

                // what awww says is active, but only if it's one of the files in the folder, so a
                // path it reports in some other form can't wipe out the remembered wallpaper
                const m = (parts[0] || "").match(/currently displaying: image: (.+)/);
                if (m) {
                    const reported = m[1].trim();
                    const hit = lines.find(l => root.samePath(l, reported));
                    if (hit && hit !== root.currentWallpaper) {
                        root.currentWallpaper = hit;
                        root.saveCurrent(hit);
                    }
                }

                // land on the active wallpaper if we know it, otherwise stay where we were
                let target = -1;
                for (let i = 0; i < lines.length; i++) {
                    if (root.samePath(lines[i], root.currentWallpaper)) {
                        target = i + 1;
                        break;
                    }
                }
                if (target < 0)
                    target = Math.max(0, Math.min(root.currentIndex, lines.length - 1));

                // only rebuild the carousel if the folder actually changed
                if (listing !== root._listing) {
                    root._listing = listing;
                    wallpaperModel.clear();
                    wallpaperModel.append({ "path": "", "isFetch": true })
                    for (let j = 0; j < lines.length; j++)
                        wallpaperModel.append({ "path": lines[j], "isFetch": false 
                    })
                }

                root.wallpapersLoadedOnce = true;
                Qt.callLater(function () {
                    root.focusIndex(target, true);
                });
            }
        }
    }

    Process {
        id: applyProc
        command: ["true"]
    }

    Process {
        id: loadCurrentProc
        running: true
        command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/current-wallpaper\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const p = text.trim();
                if (p !== "" && root.currentWallpaper === "") {
                    root.currentWallpaper = p;
                    root.focusCurrent(true);
                }
            }
        }
    }

    Process {
        id: saveCurrentProc
        property string payload: ""
        command: ["sh", "-c", "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/current-wallpaper\"", "sh", payload]
    }

    Process {
        id: loadColorModeProc
        running: true
        command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/color-mode\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim();
                if (m === "dark" || m === "light") {
                    root.colorMode = m;
                }
            }
        }
    }

    Process {
        id: saveColorModeProc
        property string payload: ""
        command: ["sh", "-c", "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/color-mode\"", "sh", payload]
    }

    function saveColorMode(mode) {
        saveColorModeProc.payload = mode;
        saveColorModeProc.running = false;
        saveColorModeProc.running = true;
    }

    Process {
        id: loadColorPrefProc
        running: true
        command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/color-preference\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                const m = text.trim();
                if (m === "darkness" || m === "lightness") {
                    root.colorPreference = m;
                }
            }
        }
    }

    Process {
        id: saveColorPrefProc
        property string payload: ""
        command: ["sh", "-c", "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/color-preference\"", "sh", payload]
    }

    function saveColorPreference(pref) {
        saveColorPrefProc.payload = pref;
        saveColorPrefProc.running = false;
        saveColorPrefProc.running = true;
    }



    function refreshWallpapers() {
        listProc.running = false;
        listProc.running = true;
    }

    property string pendingApplyPath: ""

    function executeApply(path) {
        root.currentWallpaper = path;
        root.saveCurrent(path);
        var safePath = path.replace(/'/g, "'\\''");

        var matugenCmd = "(matugen image '" + safePath + "' -m " + root.colorMode + " --type " + root.schemeType + " --contrast " + root.contrast + " --prefer " + root.colorPreference + "; ~/.config/matugen/post-hook-scripts/cursor_matugen.sh) >/dev/null 2>&1 &";

        var cmd = "awww img '" + safePath + "' --transition-type random --transition-fps 100 --transition-duration 2 >/dev/null 2>&1 & " + matugenCmd;

        applyProc.command = ["sh", "-c", cmd];
        applyProc.running = false;
        applyProc.running = true;
    }

    Timer {
        id: applyDelayTimer
        interval: Motion.short4 + 50
        repeat: false
        onTriggered: {
            if (root.pendingApplyPath !== "") {
                const p = root.pendingApplyPath;
                root.pendingApplyPath = "";
                root.executeApply(p);
            }
        }
    }

    function applyWallpaper(path, index) {
        if (!path) return;
        root.currentWallpaper = path;
        if (root.isOpen || stage.openT > 0.001) {
            root.pendingApplyPath = path;
            root.isOpen = false;
            applyDelayTimer.restart();
        } else {
            root.executeApply(path);
        }
    }

    // Enter / Apply chip: download the random slot, or apply the selected file
    function applySelected() {
        if (wallpaperModel.count === 0)
            return;
        if (wallpaperModel.get(coverflow.currentIndex).isFetch)
            root.confirmDownload();
        else
            root.applyWallpaper(root.selectedPath, root.currentIndex);
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            root.isOpen = !root.isOpen;
        }
        function open(): void {
            root.isOpen = true;
        }
        function close(): void {
            root.isOpen = false;
        }
        function toggleMode(): void {
            root.toggleColorMode();
        }
        function setMode(mode: string): void {
            root.setColorMode(mode);
        }
        function togglePreference(): void {
            root.toggleColorPreference();
        }
        function setPreference(pref: string): void {
            root.setColorPreference(pref);
        }
    }

    PanelWindow {
        id: panelWindow
        WlrLayershell.namespace: "quickshell:wallpaperswitcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.isOpen || stage.openT > 0.001

        Item {
            id: stage
            anchors.fill: parent

            // 0 = closed, 1 = open; everything below derives from this one value
            property real openT: root.isOpen ? 1 : 0
            Behavior on openT {
                NumberAnimation {
                    duration: root.isOpen ? Motion.expressiveDefaultSpatialDuration : Motion.short4
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: root.isOpen ? Motion.expressiveDefaultSpatial : Motion.emphasizedAccelerate
                }
            }

            // run a pending apply / download once the close animation has finished
            onOpenTChanged: {
                if (root.isOpen || openT > 0.001)
                    return;
                if (root.pendingApplyPath !== "") {
                    applyDelayTimer.stop();
                    const p = root.pendingApplyPath;
                    root.pendingApplyPath = "";
                    root.executeApply(p);
                }
                if (root.pendingDownloadCmd.length > 0) {
                    downloadDelayTimer.stop();
                    const cmd = root.pendingDownloadCmd;
                    root.pendingDownloadCmd = [];
                    root.executeDownload(cmd);
                }
            }

            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colors.scrim, root.scrimOpacity)
                opacity: stage.openT
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.isOpen = false
            }

            // ---- header ----
            RowLayout {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.topMargin: 32 - (1 - stage.openT) * 16
                anchors.leftMargin: 40
                anchors.rightMargin: 40
                spacing: 16
                opacity: stage.openT

                Rectangle {
                    implicitWidth: 48
                    implicitHeight: 48
                    radius: Motion.shapeLarge
                    color: Colors.primary_container
                    Icon { anchors.centerIn: parent; name: "wallpaper"; color: Colors.on_primary_container }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    // fillWidth on the children lets the column take up the row's spare width,
                    // which keeps the title beside the icon and the close button at the edge
                    StyledText { Layout.fillWidth: true; role: "headlineSmall"; color: "white"; elide: Text.ElideRight; text: "Wallpaper & style" }
                    StyledText { Layout.fillWidth: true; role: "bodyMedium"; color: Qt.alpha("white", 0.8); elide: Text.ElideRight; text: "Colors follow your wallpaper" }
                }
                IconButton {
                    icon: "close"
                    style: "tonal"
                    size: "m"
                    onClicked: root.isOpen = false
                }
            }

            // ---- carousel (M3 hero carousel: 28px item corners) ----
            Item {
                id: carousel
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.verticalCenterOffset: -40 + (1 - stage.openT) * 36
                height: root.cardHeight + 60
                opacity: stage.openT

                ListView {
                    id: coverflow
                    anchors.fill: parent
                    orientation: ListView.Horizontal
                    reuseItems: false
                    model: wallpaperModel
                    spacing: 40
                    focus: root.isOpen
                    cacheBuffer: (root.cardWidth + 40) * 4
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: root.snapNav ? 0 : Motion.expressiveFastSpatialDuration
                    highlightMoveVelocity: -1
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - root.cardWidth) / 2
                    preferredHighlightEnd: (width + root.cardWidth) / 2

                    onCurrentIndexChanged: if (currentIndex >= 0) root.currentIndex = currentIndex
                    // the layer-shell window can get its real width a moment after it opens
                    onWidthChanged: if (root.isOpen && width > 0) root.focusCurrent(true)

                    Keys.onPressed: event => {
                        if (!root.isOpen)
                            return;
                        switch (event.key) {
                        case Qt.Key_Left: root.step(-1, event.isAutoRepeat); break;
                        case Qt.Key_Right: root.step(1, event.isAutoRepeat); break;
                        case Qt.Key_Down: if (root.isSelectedFetch) root.fetchPreview(); break;
                        case Qt.Key_PageUp: root.step(-5, event.isAutoRepeat); break;
                        case Qt.Key_PageDown: root.step(5, event.isAutoRepeat); break;
                        case Qt.Key_Home: root.step(-coverflow.count, false); break;
                        case Qt.Key_End: root.step(coverflow.count, false); break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (!event.isAutoRepeat)
                                root.applySelected();
                            break;
                        case Qt.Key_D:
                        case Qt.Key_M:
                            if (!event.isAutoRepeat) root.toggleColorMode();
                            break;
                        case Qt.Key_X:
                            if (!event.isAutoRepeat) root.toggleColorPreference();
                            break;
                        case Qt.Key_Escape: root.isOpen = false; break;
                        default: return;
                        }
                        event.accepted = true;
                    }

                    Timer {
                        id: wheelResetTimer
                        interval: 150
                        onTriggered: wheelH.accum = 0
                    }
                    WheelHandler {
                        id: wheelH
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        property int accum: 0
                        onWheel: event => {
                            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                            if (d === 0)
                                return;
                            wheelH.accum += d;
                            wheelResetTimer.restart();
                            if (Math.abs(wheelH.accum) >= 60) {
                                root.step(wheelH.accum > 0 ? -1 : 1, false);
                                wheelH.accum = 0;
                            }
                        }
                    }

                    delegate: Item {
                        id: card
                        required property bool isFetch
                        required property string path
                        required property int index

                        width: root.cardWidth
                        height: root.cardHeight
                        y: (coverflow.height - height) / 2

                        // continuous distance from centre so size/fade/spacing follow the slide
                        readonly property real dist: (x + width / 2 - coverflow.contentX - coverflow.width / 2) / (width + coverflow.spacing)
                        readonly property real a: Math.abs(dist)
                        readonly property real fall: Math.min(1, a)
                        readonly property bool isCurrent: root.samePath(path, root.currentWallpaper)
                        // pull side cards in so the visible gap stays constant as they shrink
                        readonly property real pull: root.cardWidth * (a <= 1 ? (1 - (root.centerScale + root.sideScale) / 2) * a : (1 - (root.centerScale + root.sideScale) / 2) + (1 - root.sideScale) * (a - 1))

                        z: 100 - Math.round(a * 10)
                        scale: root.centerScale - (root.centerScale - root.sideScale) * fall
                        opacity: 1 - 0.45 * fall - 0.35 * Math.min(1, Math.max(0, a - 1))
                        transform: Translate { x: card.dist > 0 ? -card.pull : card.pull }

                        Elevation {
                            anchors.fill: frame
                            radius: frame.radius
                            level: card.a < 0.5 ? 3 : 1
                        }

                        ClippingRectangle {
                            id: frame
                            anchors.fill: parent
                            radius: Motion.shapeExtraLarge
                            color: Colors.surface_container_high

                            Image {
                                anchors.fill: parent
                                visible: !card.isFetch
                                source: card.isFetch ? "" : "file://" + card.path
                                sourceSize: Qt.size(Math.round(root.cardWidth * 1.25), Math.round(root.cardHeight * 1.25))
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { Fade { speed: "slow" } }
                            }
                            // random slot: remote thumbnail once a preview has loaded
                            Image {
                                anchors.fill: parent
                                visible: card.isFetch && root.previewThumbUrl !== ""
                                source: card.isFetch ? root.previewThumbUrl : ""
                                sourceSize: Qt.size(Math.round(root.cardWidth * 1.25), Math.round(root.cardHeight * 1.25))
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity { Fade { speed: "slow" } }
                            }

                            Column {
                                anchors.centerIn: parent
                                visible: card.isFetch && root.previewThumbUrl === ""
                                spacing: 16
                                LoadingIndicator {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    contained: true
                                    running: visible && root.previewFetching
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    role: "titleMedium"
                                    text: root.previewFetching ? "Finding a wallpaper…" : "Random wallpaper"
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    role: "bodyMedium"
                                    color: Colors.on_surface_variant
                                    text: root.previewFetching ? "From Konachan" : "Click to download · right-click for another"
                                }
                            }

                            StateLayer {
                                pressed: cardMa.pressed
                                tint: Colors.on_surface
                                radius: frame.radius
                            }

                            // downloading overlay
                            Rectangle {
                                anchors.fill: parent
                                visible: card.isFetch && root.fetchInProgress
                                color: Qt.alpha(Colors.surface_container_high, 0.85)
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 16
                                    LoadingIndicator {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        contained: true
                                        running: parent.parent.visible
                                    }
                                    StyledText {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        role: "titleSmall"
                                        text: "Applying wallpaper…"
                                    }
                                }
                            }
                        }

                        // active wallpaper label
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 16
                            height: 32
                            width: activeRow.implicitWidth + 24
                            radius: Motion.shapeSmall
                            color: Colors.primary
                            opacity: card.isCurrent ? 1 : 0
                            scale: card.isCurrent ? 1 : 0.7
                            transformOrigin: Item.TopLeft
                            Behavior on opacity { Fade {} }
                            Behavior on scale { Spring {} }
                            Row {
                                id: activeRow
                                anchors.centerIn: parent
                                spacing: 8
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "check"; size: 18; color: Colors.on_primary }
                                StyledText { anchors.verticalCenter: parent.verticalCenter; role: "labelLarge"; color: Colors.on_primary; text: "Current" }
                            }
                        }

                        // remote post id
                        Rectangle {
                            anchors.right: parent.right
                            anchors.top: parent.top
                            anchors.margins: 16
                            visible: card.isFetch && root.previewThumbUrl !== ""
                            height: 32
                            width: onlineRow.implicitWidth + 24
                            radius: Motion.shapeSmall
                            color: Colors.surface_container_highest
                            Row {
                                id: onlineRow
                                anchors.centerIn: parent
                                spacing: 8
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "public"; size: 18; color: Colors.primary }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "labelLarge"
                                    color: Colors.on_surface_variant
                                    text: root.previewId !== "" ? "#" + root.previewId : "Random"
                                }
                            }
                        }

                        MouseArea {
                            id: cardMa
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (!root.isOpen)
                                    return;
                                if (card.isFetch && mouse.button === Qt.RightButton)
                                    root.fetchPreview();
                                else if (card.index !== root.currentIndex)
                                    coverflow.currentIndex = card.index;
                                else if (card.isFetch)
                                    root.confirmDownload();
                                else
                                    root.applyWallpaper(card.path, card.index);
                            }
                        }
                    }
                }

                StyledText {
                    anchors.centerIn: parent
                    visible: wallpaperModel.count === 0
                    role: "titleMedium"
                    color: "white"
                    text: "No wallpapers found in " + root.wallpaperDir.replace("$HOME", "~")
                }
            }

            // ---- controls ----
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: carousel.bottom
                anchors.topMargin: 8 + (1 - stage.openT) * 20
                spacing: 16
                opacity: stage.openT

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: wallpaperModel.count > 0
                    spacing: 16

                    // source-color preference (matugen --prefer)
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        ConnectedButton {
                            position: "first"
                            implicitHeight: 40
                            icon: "light_mode"
                            text: "Lightness"
                            selected: root.colorPreference === "lightness"
                            onClicked: root.setColorPreference("lightness")
                        }
                        ConnectedButton {
                            position: "last"
                            implicitHeight: 40
                            icon: "contrast"
                            text: "Darkness"
                            selected: root.colorPreference === "darkness"
                            onClicked: root.setColorPreference("darkness")
                        }
                    }

                    // name + position
                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        height: 48
                        width: nameRow.implicitWidth + 32
                        radius: height / 2
                        color: Colors.surface_container_high
                        Behavior on width {
                            enabled: !root.snapNav
                            Spring {}
                        }
                        Row {
                            id: nameRow
                            anchors.centerIn: parent
                            spacing: 12
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "image"; size: 20; color: Colors.primary }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                width: Math.min(implicitWidth, 440)
                                role: "titleSmall"
                                elide: Text.ElideRight
                                text: root.currentIndex === 0 ? "Random online" : root.selectedName
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 28
                                width: countText.implicitWidth + 16
                                radius: Motion.shapeSmall
                                color: Colors.secondary_container
                                StyledText {
                                    id: countText
                                    anchors.centerIn: parent
                                    role: "labelMedium"
                                    color: Colors.on_secondary_container
                                    text: (root.currentIndex + 1) + " / " + wallpaperModel.count
                                }
                            }
                        }
                    }

                    // color mode
                    Row {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 2
                        ConnectedButton {
                            position: "first"
                            implicitHeight: 40
                            icon: "dark_mode"
                            text: "Dark"
                            selected: root.colorMode === "dark"
                            onClicked: root.setColorMode("dark")
                        }
                        ConnectedButton {
                            position: "last"
                            implicitHeight: 40
                            icon: "light_mode"
                            text: "Light"
                            selected: root.colorMode === "light"
                            onClicked: root.setColorMode("light")
                        }
                    }
                }

                // keyboard hints as assist chips
                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 8
                    Chip { icon: "keyboard_return"; text: "Apply · Enter"; onClicked: root.applySelected() }
                    Chip { icon: "dark_mode"; text: "Mode · D"; onClicked: root.toggleColorMode() }
                    Chip { icon: "palette"; text: "Prefer · X"; onClicked: root.toggleColorPreference() }
                    Chip { visible: root.isSelectedFetch; icon: "shuffle"; text: "Another · ↓"; onClicked: root.fetchPreview() }
                    Chip { icon: "close"; text: "Close · Esc"; onClicked: root.isOpen = false }
                }
            }
        }
    }
}
