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
    property string fontdefault: "Space Grotesk"
    property int global_radius: 24

    property string wallpaperDir: "$HOME/Pictures/Wallpapers"
    property int cardWidth: 800
    property int cardHeight: 450

    property bool isOpen: false
    property string currentWallpaper: ""
    property int currentIndex: 0
    property bool wallpapersLoadedOnce: false  
    property string colorPreference: "darkness"   

    function toggleColorPreference() {
        root.colorPreference = root.colorPreference === "darkness" ? "lightness" : "darkness";
    }

    ListModel {
        id: wallpaperModel
    }

    Process {
        id: listProc
        command: ["sh", "-c", "find " + root.wallpaperDir + " -maxdepth 1 -type f \\( -iname '*.jpg' -o -iname '*.jpeg' -o -iname '*.png' -o -iname '*.webp' \\) | sort"]

        stdout: StdioCollector {
            onStreamFinished: {
                wallpaperModel.clear();
                const lines = text.trim().split("\n").filter(function (l) {
                    return l.length > 0;
                });

                var targetIndex;
                if (!root.wallpapersLoadedOnce) {
                    targetIndex = 0;
                    for (var i = 0; i < lines.length; i++) {
                        if (lines[i] === root.currentWallpaper)
                            targetIndex = i;
                    }
                } else {
                    targetIndex = 0;
                }

                for (var j = 0; j < lines.length; j++) {
                    wallpaperModel.append({
                        "path": lines[j]
                    });
                }

                root.wallpapersLoadedOnce = true;
                root.currentIndex = targetIndex;

                Qt.callLater(function () {
                    coverflow.currentIndex = targetIndex;
                    coverflow.positionViewAtIndex(targetIndex, ListView.Center);
                });
            }
        }
        onExited: (code) => { root.isOpen = !root.isOpen }
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

        // Escaping single quotes in path safely
        var safePath = path.replace(/'/g, "'\\''");

        var cmd = "(" +
                "awww img '" + safePath + "' --transition-type grow --transition-fps 60 --transition-duration 1 & " +
                "matugen image '" + safePath + "' --prefer " + root.colorPreference +
                ") >/dev/null 2>&1 &";

        applyProc.command = ["sh", "-c", cmd];
        applyProc.running = false;
        applyProc.running = true;
    }

    IpcHandler {
        target: "wallpaper"

        function toggle(): void {
            root.refreshWallpapers();
            if (root.isOpen) {
                coverflow.forceActiveFocus();
            }
        }
        function open(): void {
            root.isOpen = true
            root.refreshWallpapers();
            coverflow.forceActiveFocus();
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
        anchors.left: true
        anchors.right: true
        exclusiveZone: 0
        color: "transparent"
        margins.bottom: 28
        margins.left: 0
        margins.right: 0
        implicitHeight: root.cardHeight + 70
        visible: root.isOpen

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpen = false
        }

        Rectangle {
            id: panelBg
            anchors.fill: parent
            radius: 18
            border.width: 0
            border.color: root.theme.surface_bright
            color: Qt.alpha(root.theme.background, 0)
            clip: true

            // swallow clicks on the panel itself so they don't hit the backdrop MouseArea
            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 18
                spacing: 2

                Text {
                    anchors.right: parent.right
                    text: root.currentWallpaper ? root.currentWallpaper.split("/").pop() : ""
                    color: root.theme.surface_bright
                    font.pixelSize: 12
                    font.family: root.fontdefault
                }
            }

            ListView {
                id: coverflow
                anchors.fill: parent
                anchors.topMargin: 44
                anchors.bottomMargin: 10
                orientation: ListView.Horizontal
                model: wallpaperModel
                spacing: 1
                focus: root.isOpen
                highlightRangeMode: ListView.StrictlyEnforceRange
                preferredHighlightBegin: width / 2 - root.cardWidth / 2 
                preferredHighlightEnd: width / 2 + root.cardWidth / 2
                highlightMoveDuration: 200
                onCurrentIndexChanged: root.currentIndex = currentIndex

                Keys.onLeftPressed: currentIndex = Math.max(0, currentIndex - 1)
                Keys.onRightPressed: currentIndex = Math.min(count - 1, currentIndex + 1)
                Keys.onReturnPressed: if (model.count > 0)
                    root.applyWallpaper(model.get(currentIndex).path, currentIndex)
                Keys.onEscapePressed: { root.isOpen = false; }
                Keys.onPressed: event => {
                    if (event.key === Qt.Key_X) {
                        root.toggleColorPreference();
                        event.accepted = true;
                    }
                }

                delegate: Item {
                    id: card
                    required property string path
                    required property int index
                    width: root.cardWidth
                    height: root.cardHeight

                    readonly property real centerOffset: x - coverflow.contentX + width / 2 - coverflow.width / 2 
                    readonly property real absOffset: Math.abs(centerOffset)
                    readonly property bool isCentered: index === coverflow.currentIndex && absOffset < 4

                    anchors.verticalCenter: parent.verticalCenter
                    scale: Math.max(0.72, 1 - absOffset / 620) 
                    opacity: Math.max(0.35, 1 - absOffset / 480)
                    z: -absOffset

                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: root.global_radius
                        color: "black"
                        border.width: card.isCentered ? 3 : 2
                        border.color: card.isCentered ? (root.colorPreference === "darkness" ? root.theme.source_color : root.theme.on_background) : root.theme.surface_bright

                        Image {
                            anchors.fill: parent
                            source: "file://" + card.path
                            sourceSize.width: 800
                            sourceSize.height: 450
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    MouseArea {
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: frame
                        onClicked: {
                            if (card.isCentered)
                                root.applyWallpaper(card.path, card.index);
                            else
                                coverflow.currentIndex = card.index;
                        }
                    }
                }
            }
        }
    }
}
