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
            root.refreshWallpapers();
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

                const m = (parts[0] || "").match(/currently displaying: image: (.+)/);
                if (m)
                    root.currentWallpaper = m[1].trim();

                const listing = (parts[1] || "").trim();
                const lines = listing.length > 0 ? listing.split("\n") : [];

                // land on the active wallpaper if we know it, otherwise stay where we were
                let target = -1;
                for (let i = 0; i < lines.length; i++) {
                    if (root.samePath(lines[i], root.currentWallpaper)) {
                        target = i;
                        break;
                    }
                }
                if (target < 0)
                    target = Math.max(0, Math.min(root.currentIndex, lines.length - 1));

                // only rebuild the carousel if the folder actually changed
                if (listing !== root._listing) {
                    root._listing = listing;
                    wallpaperModel.clear();
                    for (let j = 0; j < lines.length; j++)
                        wallpaperModel.append({
                            "path": lines[j]
                        });
                }

                root.wallpapersLoadedOnce = true;
                Qt.callLater(function () {
                    coverflow.currentIndex = target;
                    coverflow.positionViewAtIndex(target, ListView.Center);
                });
            }
        }
    }

    Process {
        id: applyProc
        command: ["true"]
    }

    function refreshWallpapers() {
        listProc.running = false;
        listProc.running = true;
    }

    function applyWallpaper(path, index) {
        root.currentWallpaper = path;
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
                    duration: root.isOpen ? 340 : 220
                    easing.type: root.isOpen ? Easing.OutCubic : Easing.InCubic
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
                    highlightMoveDuration: 220
                    highlightMoveVelocity: -1
                    highlightRangeMode: ListView.StrictlyEnforceRange
                    preferredHighlightBegin: (width - root.cardWidth) / 2
                    preferredHighlightEnd: (width + root.cardWidth) / 2

                    onCurrentIndexChanged: {
                        if (currentIndex >= 0)
                            root.currentIndex = currentIndex;
                    }

                    Keys.onPressed: event => {
                        switch (event.key) {
                        case Qt.Key_Left:
                            root.step(-1, event.isAutoRepeat);
                            break;
                        case Qt.Key_Right:
                            root.step(1, event.isAutoRepeat);
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
                            if (!event.isAutoRepeat && wallpaperModel.count > 0)
                                root.applyWallpaper(root.selectedPath, root.currentIndex);
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
                                source: "file://" + card.path
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

                        MouseArea {
                            anchors.fill: parent
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                if (card.index === root.currentIndex)
                                    root.applyWallpaper(card.path, card.index);
                                else
                                    coverflow.currentIndex = card.index;
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
                            text: root.selectedName
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
                                "k": "\u2190  \u2192",
                                "t": "Browse"
                            },
                            {
                                "k": "Enter",
                                "t": "Apply"
                            },
                            {
                                "k": "X",
                                "t": "Colors: " + (root.colorPreference === "darkness" ? "darkness" : "lightness")
                            },
                            {
                                "k": "Esc",
                                "t": "Close"
                            }
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
