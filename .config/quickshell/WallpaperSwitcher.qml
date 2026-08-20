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
                    coverflow.positionViewAtIndex(targetIndex, ListView.Contain);
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
        anchors.top: true
        exclusiveZone: 0
        color: "transparent"
        margins.bottom: 0
        margins.left: 0
        margins.right: 0
        implicitHeight: root.cardHeight + 32
        visible: root.isOpen || panelBg.opacity > 0

        

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpen = false
        }

        Rectangle {
            id: panelBg
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.margins: 8
            height: root.cardHeight + 16
            radius: 18
            border.width: 0
            border.color: root.theme.surface_bright
            color: Qt.alpha(root.theme.background, 0)
            clip: true
            y: -height

            states: [
                State {
                    name: "open"
                    when: root.isOpen
                    PropertyChanges {
                        target: panelBg
                        y: 8
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !root.isOpen
                    PropertyChanges {
                        target: panelBg
                        y: -panelBg.height
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
                        duration: 360
                        easing.type: Easing.OutBack
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 400
                        easing.type: Easing.InBack
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
                anchors.margins: 8
                orientation: ListView.Horizontal
                model: wallpaperModel
                spacing: 8
                clip: true
                focus: root.isOpen
                boundsBehavior: Flickable.StopAtBounds
                flickDeceleration: 1500
                maximumFlickVelocity: 2500
                onCurrentIndexChanged: {
                    root.currentIndex = currentIndex;
                    positionViewAtIndex(currentIndex, ListView.Contain);
                }

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

                    readonly property bool isSelected: index === coverflow.currentIndex

                    anchors.verticalCenter: parent.verticalCenter

                    ClippingRectangle {
                        id: frame
                        anchors.fill: parent
                        radius: 0
                        color: "black"
                        border.width: card.isSelected ? 3 : 2
                        border.color: card.isSelected ? (root.colorPreference === "darkness" ? root.theme.source_color : root.theme.on_background) : root.theme.surface_bright

                        Image {
                            id: wallpaper_image
                            anchors.fill: parent
                            source: "file://" + card.path
                            sourceSize.width: root.cardWidth
                            sourceSize.height: root.cardHeight
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    MouseArea {
                        cursorShape: Qt.PointingHandCursor
                        anchors.fill: frame
                        onClicked: {
                            if (card.isSelected)
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
