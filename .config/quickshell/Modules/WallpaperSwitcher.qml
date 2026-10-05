pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Quickshell.Widgets

Item {
    id: root

    property var theme
    property var theme2
    property var settings
    property string fontdefault: "Space Grotesk"
    property int global_radius: 18

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
    property string schemeType: "scheme-tonal-spot"
    property real contrast: 0.1                       // -1 .. 1
    property string colorPreference: "lightness"      // matugen --prefer: "lightness" | "darkness"

    property string _listing: ""                      // last file list, so reopening doesn't rebuild the carousel
    property double _lastNav: 0
    property bool snapNav: false                      // true for a moment when we jump (not slide) to the current wallpaper

    readonly property string boorusApi: "https://konachan.net/post.json?tags=order:random+rating:safe+width:%3E=1920+height:%3E=1080&limit=1"

    property bool previewFetching: false
    property string previewThumbUrl: ""   // remote URL shown directly in the card, nothing downloaded yet
    property string previewFileUrl: ""    // the full-res URL confirmDownload() will save -- same post as the thumb
    property string previewId: ""
    property bool fetchInProgress: false  // true only during the actual confirmDownload save

    // Fetches metadata for one random post and points the card at its remote
    // thumbnail -- no local download happens here. Called whenever the panel
    // opens, and again on demand (right-click the card) to reroll without
    // committing to a download.
    function fetchPreview() {
        if (root.previewFetching) return;
        root.previewFetching = true;

        const cmd = 'json=$(curl -sf -A "Mozilla/5.0" "' + root.boorusApi + '") && ' +
            'echo "$json" | jq -r "[.[0].sample_url, .[0].file_url, (.[0].id|tostring)] | join(\\"\\u0009\\")"';

        previewProc.command = ["sh", "-c", cmd];
        previewProc.running = false;
        previewProc.running = true;
    }

    Process {
        id: previewProc
        stdout: StdioCollector {
            onStreamFinished: {
                root.previewFetching = false;
                const parts = text.trim().split("\t");
                if (parts.length !== 3 || parts.some(p => p === "" || p === "null")) {
                    // left the old preview (if any) in place rather than blanking
                    // it out on a transient failure
                    return;
                }
                root.previewThumbUrl = parts[0];
                root.previewFileUrl = parts[1];
                root.previewId = parts[2];
            }
        }
    }

    // Downloads the exact post currently shown as the preview -- deliberately
    // does not re-query the API, so what you confirm is what you saw.
    function confirmDownload() {
        if (root.fetchInProgress || root.previewFileUrl === "") return;
        root.fetchInProgress = true;

        const cmd = 'url="' + root.previewFileUrl + '" && ' +
            'ext="${url##*.}" && ' +
            'mkdir -p "' + root.wallpaperDir + '" && ' +
            'out="' + root.wallpaperDir + '/konachan-' + root.previewId + '-$(date +%s).${ext}" && ' +
            'curl -sLf -A "Mozilla/5.0" -o "$out" "$url" && echo "$out"';

        fetchProc.command = ["sh", "-c", cmd];
        fetchProc.running = false;
        fetchProc.running = true;
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
                // clear so the next time the panel opens, fetchPreview() rolls
                // a fresh one instead of showing the just-downloaded post again
                root.previewThumbUrl = "";
                root.previewFileUrl = "";
                root.previewId = "";
                root.isOpen = false;   // next open's refreshWallpapers() picks up the new file
            }
        }
    }

    Timer {
        id: snapTimer
        interval: 150
        onTriggered: root.snapNav = false
    }

    readonly property color pillColor: Qt.lighter(Qt.alpha(root.theme.background, 1), 1.8)
    readonly property color capColor: Qt.alpha(root.theme.on_background, 0.14)

    readonly property string selectedPath: (wallpaperModel.count > 0 && root.currentIndex >= 0 && root.currentIndex < wallpaperModel.count) ? wallpaperModel.get(root.currentIndex).path : ""
    readonly property string selectedName: root.selectedPath.split("/").pop().replace(/\.[^.]+$/, "")

    function toggleColorPreference() {
        root.colorPreference = root.colorPreference === "darkness" ? "lightness" : "darkness";
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

    function refreshWallpapers() {
        listProc.running = false;
        listProc.running = true;
    }

    function applyWallpaper(path, index) {
        root.currentWallpaper = path;
        root.saveCurrent(path);
        var safePath = path.replace(/'/g, "'\\''");

        var matugenCmd = "matugen image '" + safePath + "'" + " -m " + root.colorMode + " --type " + root.schemeType + " --contrast " + root.contrast + " --prefer " + root.colorPreference + " >/dev/null 2>&1 &";

        var cmd = "awww img '" + safePath + "' --transition-type random --transition-fps 100 --transition-duration 2 >/dev/null 2>&1 & " + matugenCmd;

        applyProc.command = ["sh", "-c", cmd];
        applyProc.running = true;
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
    }

    PanelWindow {
        id: panelWindow
        WlrLayershell.namespace: "quickshell:wallpaperswitcher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.isOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        visible: root.isOpen || stage.openT > 0.001

        Item {
            id: stage
            anchors.fill: parent

            // 0 = closed, 1 = open. Everything below derives from this one value.
            property real openT: root.isOpen ? 1 : 0
            Behavior on openT {
                NumberAnimation {
                    duration: root.isOpen ? 280 : 180
                    easing.type: root.isOpen ? Easing.OutCirc : Easing.InCirc
                }
            }

            // dim the screen; clicking anywhere outside the carousel closes it
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(root.theme.background, root.scrimOpacity)
                opacity: stage.openT
            }
            MouseArea {
                anchors.fill: parent
                onClicked: root.isOpen = false
            }

            // ------------------------------------------------------------ carousel
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
                    reuseItems: true
                    model: wallpaperModel
                    spacing: 40
                    focus: root.isOpen
                    cacheBuffer: (root.cardWidth + 40) * 4      // keep neighbours decoded so nothing pops in
                    highlightFollowsCurrentItem: true
                    highlightMoveDuration: root.snapNav ? 0 : 220
                    highlightMoveVelocity: -1
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - root.cardWidth) / 2
                    preferredHighlightEnd: (width + root.cardWidth) / 2

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0)
                            root.currentIndex = currentIndex;
                    }

                    // the layer-shell window can get its real width a moment after it opens
                    onWidthChanged: {
                        if (root.isOpen && width > 0)
                            root.focusCurrent(true);
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Left:
                            root.step(-1, event.isAutoRepeat);
                            break;
                        case Qt.Key_Right:
                            root.step(1, event.isAutoRepeat);
                            break;
                        case Qt.Key_Down:
                            root.fetchPreview();
                            break;
                        case Qt.Key_PageUp:
                            root.step(-5, event.isAutoRepeat);
                            break;
                        case Qt.Key_PageDown:
                            root.step(5, event.isAutoRepeat);
                            break;
                        case Qt.Key_Home:
                            root.step(-coverflow.count, false);
                            break;
                        case Qt.Key_End:
                            root.step(coverflow.count, false);
                            break;
                        case Qt.Key_Return:
                        case Qt.Key_Enter:
                            if (!event.isAutoRepeat && wallpaperModel.count > 0) {
                                if (wallpaperModel.get(coverflow.currentIndex).isFetch)
                                    root.confirmDownload();
                                else
                                    root.applyWallpaper(root.selectedPath, root.currentIndex);
                            }
                            break;
                        case Qt.Key_X:
                            if (!event.isAutoRepeat)
                                root.toggleColorPreference();
                            break;
                        case Qt.Key_Escape:
                            root.isOpen = false;
                            break;
                        default:
                            return;
                        }
                        event.accepted = true;
                    }

                    WheelHandler {
                        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
                        onWheel: event => {
                            const d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.angleDelta.x;
                            if (d !== 0)
                                root.step(d > 0 ? -1 : 1, true);
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

                        // Position relative to the centre, measured continuously (not just "is it selected"),
                        // so size / fade / spacing all animate smoothly while the list slides.
                        readonly property real dist: (card.x + card.width / 2 - coverflow.contentX - coverflow.width / 2) / (card.width + coverflow.spacing)
                        readonly property real a: Math.abs(card.dist)
                        readonly property real fall: Math.min(1, card.a)
                        readonly property bool isCurrent: root.samePath(card.path, root.currentWallpaper)

                        // pull side cards in so the visible gap stays the same as they shrink
                        readonly property real pull: root.cardWidth * (card.a <= 1 ? (1 - (root.centerScale + root.sideScale) / 2) * card.a : (1 - (root.centerScale + root.sideScale) / 2) + (1 - root.sideScale) * (card.a - 1))

                        z: 100 - Math.round(card.a * 10)
                        scale: root.centerScale - (root.centerScale - root.sideScale) * card.fall
                        opacity: 1 - 0.45 * card.fall - 0.35 * Math.min(1, Math.max(0, card.a - 1))
                        transform: Translate {
                            x: card.dist > 0 ? -card.pull : card.pull
                        }

                        ClippingRectangle {
                            id: frame
                            anchors.fill: parent
                            radius: root.global_radius
                            color: Qt.alpha(root.theme.on_background, 0.08)   // placeholder while the image decodes

                            Image {
                                anchors.fill: parent
                                visible: !card.isFetch
                                source: card.isFetch ? "" : "file://" + card.path
                                sourceSize.width: Math.round(root.cardWidth * 1.25)
                                sourceSize.height: Math.round(root.cardHeight * 1.25)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 250
                                    }
                                }
                            }

                            // fetch slot: remote thumbnail once a preview has loaded,
                            // placeholder text otherwise
                            Image {
                                anchors.fill: parent
                                visible: card.isFetch && root.previewThumbUrl !== ""
                                source: card.isFetch ? root.previewThumbUrl : ""
                                sourceSize.width: Math.round(root.cardWidth * 1.25)
                                sourceSize.height: Math.round(root.cardHeight * 1.25)
                                fillMode: Image.PreserveAspectCrop
                                asynchronous: true
                                opacity: status === Image.Ready ? 1 : 0
                                Behavior on opacity {
                                    NumberAnimation {
                                        duration: 250
                                    }
                                }
                            }

                            Column {
                                anchors.centerIn: parent
                                visible: card.isFetch && root.previewThumbUrl === ""
                                spacing: 10

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: "\u21bb"
                                    color: Qt.alpha(root.theme.on_background, 0.7)
                                    font.pixelSize: 32
                                }
                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    text: root.previewFetching ? "Loading preview\u2026" : "Random wallpaper"
                                    color: Qt.alpha(root.theme.on_background, 0.7)
                                    font.pixelSize: 14
                                    font.family: root.settings.fontdefault
                                }
                            }
                        }

                        // marks the wallpaper that's active right now
                        Rectangle {
                            anchors.left: parent.left
                            anchors.top: parent.top
                            anchors.margins: 14
                            height: 26
                            width: badgeText.implicitWidth + 22
                            radius: 13
                            color: root.theme.primary
                            opacity: card.isCurrent ? 1 : 0
                            scale: card.isCurrent ? 1 : 0.6
                            transformOrigin: Item.TopLeft
                            Behavior on opacity {
                                NumberAnimation {
                                    duration: 200
                                }
                            }
                            Behavior on scale {
                                NumberAnimation {
                                    duration: 260
                                    easing.type: Easing.OutBack
                                }
                            }
                            Text {
                                id: badgeText
                                anchors.centerIn: parent
                                text: "\u2713  Current"
                                color: root.theme.on_primary
                                font.pixelSize: 12
                                font.bold: true
                                font.family: root.settings.fontdefault
                            }
                        }

                        Item {
                            id: key
                            anchors.fill: parent
                            Keys.enabled: root.isOpen
                            focus: root.isOpen

                            
                        }

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (card.isFetch && mouse.button === Qt.RightButton) {
                                    root.fetchPreview();   // reroll without downloading
                                    return;
                                }
                                if (card.isFetch) {
                                    if (card.index === root.currentIndex)
                                        root.confirmDownload();
                                    else
                                        coverflow.currentIndex = card.index;
                                } else if (card.index === root.currentIndex) {
                                    root.applyWallpaper(card.path, card.index);
                                } else {
                                    coverflow.currentIndex = card.index;
                                }
                            }
                        }
                    }
                }

                Text {
                    anchors.centerIn: parent
                    visible: wallpaperModel.count === 0
                    text: "No wallpapers found in " + root.wallpaperDir.replace("$HOME", "~")
                    color: Qt.alpha(root.theme.on_background, 0.7)
                    font.pixelSize: 18
                    font.family: root.settings.fontdefault
                }
            }

            // ------------------------------------------------------------ name + hints
            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: carousel.bottom
                anchors.topMargin: 8 + (1 - stage.openT) * 20
                spacing: 18
                opacity: stage.openT

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: wallpaperModel.count > 0
                    height: 44
                    width: nameRow.implicitWidth + 44
                    radius: 22
                    color: root.pillColor

                    Row {
                        id: nameRow
                        anchors.centerIn: parent
                        spacing: 12

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.currentIndex === 0 ? "Random" : root.selectedName
                            width: Math.min(implicitWidth, 560)
                            elide: Text.ElideRight
                            color: root.theme.on_background
                            font.pixelSize: 17
                            font.bold: true
                            font.family: root.settings.fontdefault
                        }
                        Rectangle {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 4
                            height: 4
                            radius: 2
                            color: Qt.alpha(root.theme.on_background, 0.35)
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: (root.currentIndex + 1) + " / " + wallpaperModel.count
                            color: Qt.alpha(root.theme.on_background, 0.6)
                            font.pixelSize: 14
                            font.family: root.settings.fontdefault
                        }
                    }
                }

                Row {
                    anchors.horizontalCenter: parent.horizontalCenter
                    spacing: 26

                    Repeater {
                        model: [
                            {
                                "k": "X",
                                "t": "Colors: " + (root.colorPreference === "darkness" ? "Darkness" : "Lightness")
                            },
                        ]

                        delegate: Row {
                            id: hint
                            required property var modelData
                            spacing: 8

                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                height: 22
                                width: Math.max(22, capText.implicitWidth + 16)
                                radius: 6
                                color: root.capColor
                                Text {
                                    id: capText
                                    anchors.centerIn: parent
                                    text: hint.modelData.k
                                    color: root.theme.on_background
                                    font.pixelSize: 11
                                    font.bold: true
                                    font.family: root.settings.fontdefault
                                }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: hint.modelData.t
                                color: Qt.alpha(root.theme.on_background, 0.65)
                                font.pixelSize: 14
                                font.family: root.settings.fontmedium
                            }
                        }
                    }
                }
            }
        }
    }
}
