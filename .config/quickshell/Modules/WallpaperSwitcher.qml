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
    property int cardWidth: 400
    property int cardHeight: 225

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
        var safePath = path.replace(/'/g, "'\\''");

        // fire wallpaper change immediately, don't wait on color extraction
        var cmd =
            "awww img '" + safePath + "' --transition-type grow --transition-fps 100 --transition-duration 1 >/dev/null 2>&1 & " +
            "tmp=$(mktemp --suffix=.png); " +
            "magick '" + safePath + "' -resize 128x128 \"$tmp\" 2>/dev/null && " +
            "matugen image \"$tmp\" --prefer " + root.colorPreference + " >/dev/null 2>&1; " +
            "rm -f \"$tmp\" &";

        applyProc.command = ["sh", "-c", cmd];
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
        anchors.bottom: true
        exclusiveZone: 0
        color: "transparent"
        margins.top: 0
        margins.left: 0
        margins.right: 0
        implicitHeight: root.cardHeight + 100
        visible: root.isOpen || panelBg.opacity > 0

        

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpen = false
        }

        Rectangle {
            id: panelBg
            width: 1920
            height: 280
            x: 0
            radius: 18
            border.width: 0
            border.color: root.theme.surface_bright
            color: Qt.alpha(root.theme.background, 0.8)
            clip: true
            y: 0

            states: [
                State {
                    name: "open"
                    when: root.isOpen
                    PropertyChanges {
                        target: panelBg
                        y: 35
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !root.isOpen
                    PropertyChanges {
                        target: panelBg
                        y: 1950
                        opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "open"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 320
                        easing.type: Easing.OutCirc
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 260
                        easing.type: Easing.InCirc
                    }
                }
            ]

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
                anchors.leftMargin: 50
                anchors.rightMargin: 50
                orientation: ListView.Horizontal
                model: wallpaperModel
                spacing: 40
                focus: root.isOpen
                highlightFollowsCurrentItem: true
                highlightMoveDuration: 200
                highlightMoveVelocity: 0.5
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
                    readonly property bool isCentered: index === coverflow.currentIndex 
                    anchors.verticalCenter: parent.verticalCenter

                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: 18
                        color: "transparent"
                        border.width: card.isCentered ? 4 : 0
                        border.color: card.isCentered ? (root.colorPreference === "darkness" ? root.theme.source_color : root.theme.on_background) : root.theme.surface_bright

                        Behavior on border.color {
                            ColorAnimation {
                                duration: 300
                                easing.type: Easing.OutBack
                            }
                        }
                        Image {
                            id: wallpaper_image
                            anchors.fill: parent
                            source: "file://" + card.path
                            sourceSize.width: 400
                            sourceSize.height: 225
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
