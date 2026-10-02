pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pipewire
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

PanelWindow {
    id: win

    required property var theme
    required property var settings

    // the bar icon this popup hangs under, and whether it's hovered
    property Item anchorItem: null
    property bool iconHovered: false

    // boost lives on the bar icon (VolumeModule); read it dynamically so
    // there's no separate property to keep in sync
    readonly property real maxVolume: (anchorItem && anchorItem.maxVolume) ? anchorItem.maxVolume : 1.0

    // ---- audio ----
    readonly property PwNode sink: Pipewire.defaultAudioSink

    function props(n) {
        return (n && n.properties) ? n.properties : ({});
    }

    // hide streams whose app name / binary / node name contains any of these
    // (case-insensitive substring match)
    property var blacklist: ["virtual source", "speech-dispatcher"]

    function isBlacklisted(n) {
        const p = win.props(n);
        const haystack = [p["application.name"], p["application.process.binary"], n.name, n.nickname, n.description].filter(s => s).join("|").toLowerCase();
        return win.blacklist.some(b => haystack.includes(b.toLowerCase()));
    }

    readonly property var streams: Pipewire.nodes.values.filter(n => n.isStream && n.audio && !String(win.props(n)["media.class"]).includes("Input") && !win.isBlacklisted(n))

    PwObjectTracker {
        objects: [win.sink]
    }
    PwObjectTracker {
        objects: Pipewire.nodes.values
    }

    function appName(n) {
        return win.props(n)["application.name"] || n.nickname || n.description || n.name || "Unknown";
    }
    property var iconOverrides: ({
        "zalocall.exe": "../assets/zalo.svg",
        "spotify": "../assets/spotify-color-svgrepo-com.svg",
        "wine-preloader": "../assets/wine.svg",
        //"librewolf": "../assets/librewolf.svg"
    })

    function appIcon(n) {
        const p = win.props(n);
        const keys = [p["application.name"], p["application.process.binary"], n.name].filter(s => s).map(s => s.toLowerCase());

        for (const k of keys) {
            if (win.iconOverrides[k])
                return win.iconOverrides[k];
        }

        const guess = p["application.icon-name"] || p["application.process.binary"] || "";
        return Quickshell.iconPath(guess, "audio-x-generic");
    }

    readonly property real masterVol: sink && sink.audio ? sink.audio.volume : 0
    readonly property bool masterMuted: sink && sink.audio ? sink.audio.muted : false
    readonly property string masterIcon: masterMuted ? "../assets/speaker-simple-x-fill.svg" : masterVol <= 0 ? "../assets/speaker-simple-none-fill.svg" : masterVol < 0.5 ? "../assets/speaker-low-fill.svg" : "../assets/speaker-high-fill.svg"

    // ---- open/close state (hover with ~100ms intent delay) ----
    property bool isOpen: false
    property bool animatingClosed: false
    property bool dragging: false          // keep open while dragging a slider
    readonly property int gap: 10

    readonly property bool wantOpen: iconHovered || popupHover.hovered || dragging
    onWantOpenChanged: hoverTimer.restart()

    Timer {
        id: hoverTimer
        // 100ms before opening; a bit longer before closing so the mouse can
        // cross the gap between the bar icon and the panel
        interval: win.wantOpen ? 300 : 600
        onTriggered: win.isOpen = win.wantOpen
    }

    function reposition() {
        if (!anchorItem)
            return;
        const p = anchorItem.mapToItem(null, anchorItem.width / 2, 0);
        const sw = win.screen ? win.screen.width : 1920;
        margins.left = Math.max(8, Math.min(sw - implicitWidth - 8, Math.round(p.x - implicitWidth / 2)));
    }

    onIsOpenChanged: {
        if (isOpen) {
            reposition();
            closeAnim.stop();
            openAnim.restart();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }

    // ---- window ----
    WlrLayershell.namespace: "quickshell:volume_popup"
    WlrLayershell.layer: WlrLayer.Overlay
    visible: isOpen || animatingClosed
    color: "transparent"
    exclusiveZone: 0
    anchors {
        top: true
        left: true
    }
    implicitWidth: panel.width
    implicitHeight: panel.y + panel.height

    // one row: icon (click = mute) | title | percent, then a slider
    component VolumeRow: ColumnLayout {
        id: row
        required property PwNode node
        property string title: ""
        property string subtitle: ""
        property string iconSource: ""
        property bool tint: false

        readonly property real vol: node && node.audio ? node.audio.volume : 0
        readonly property bool muted: node && node.audio ? node.audio.muted : false
        spacing: 6

        // absolute volume (0..maxVolume)
        function setVolume(v) {
            if (node && node.audio)
                node.audio.volume = Math.max(0, Math.min(win.maxVolume, v));
        }
        // slider position as a 0..1 fraction of the current ceiling
        function setFraction(f) {
            setVolume(f * win.maxVolume);
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 10

            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 22

                Image {
                    anchors.fill: parent
                    source: row.iconSource
                    sourceSize.width: 44
                    sourceSize.height: 44
                    fillMode: Image.PreserveAspectFit
                    opacity: row.muted ? 0.35 : 1
                    layer.enabled: row.tint
                    layer.effect: MultiEffect {
                        colorization: 1.0
                        colorizationColor: win.theme.primary
                    }
                }
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: if (row.node && row.node.audio)
                        row.node.audio.muted = !row.node.audio.muted
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0

                Text {
                    Layout.fillWidth: true
                    text: row.title
                    elide: Text.ElideRight
                    color: win.theme.on_background
                    opacity: 0.85
                    font.pixelSize: 14
                    font.bold: true
                    font.family: win.settings.fontdefault
                }
                Text {
                    Layout.fillWidth: true
                    visible: text !== ""
                    text: row.subtitle
                    elide: Text.ElideRight
                    color: win.theme.on_background
                    opacity: 0.5
                    font.pixelSize: 12
                    font.bold: true
                    font.family: win.settings.fontdefault
                }
            }

            Text {
                Layout.preferredWidth: 36
                horizontalAlignment: Text.AlignRight
                text: Math.round(row.vol * 100) + "%"
                color: win.theme.on_background
                opacity: 0.8
                font.pixelSize: 14
                font.bold: true
                font.family: win.settings.fontdefault
            }
        }

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 18

            Rectangle {
                id: track
                width: parent.width
                height: 6
                radius: 3
                anchors.verticalCenter: parent.verticalCenter
                color: Qt.alpha(win.theme.on_background, 0.15)

                Rectangle {
                    height: parent.height
                    radius: parent.radius
                    width: track.width * Math.min(1, row.vol / win.maxVolume)
                    color: win.theme.primary
                    opacity: row.muted ? 0.35 : 1
                    Behavior on width {
                        enabled: !area.pressed
                        NumberAnimation {
                            duration: 120
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }

            MouseArea {
                id: area
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onPressed: mouse => row.setFraction(mouse.x / width)
                onPositionChanged: mouse => {
                    if (pressed)
                        row.setFraction(mouse.x / width);
                }
                onPressedChanged: win.dragging = pressed
                onWheel: event => {
                    row.setVolume(row.vol + (event.angleDelta.y > 0 ? 0.05 : -0.05));
                    event.accepted = true;
                }
            }
        }
    }

    Item {
        anchors.fill: parent

        HoverHandler {
            id: popupHover
        }

        Rectangle {
            id: panel
            anchors.horizontalCenter: parent.horizontalCenter
            y: win.gap
            width: 300
            height: content.implicitHeight + 32
            scale: 0.1
            border.width: 1
            border.color: Qt.alpha(win.theme.primary, 0.1)
            color: Qt.alpha(win.theme.background, 1)
            radius: 20
            clip: true

            // same grow-from-the-top trick as the MPRIS popup
            transform: Scale {
                origin.x: panel.width / 2
                origin.y: 0
                yScale: panel.scale
                xScale: 1
            }

            SequentialAnimation {
                id: closeAnim
                onStarted: win.animatingClosed = true
                onStopped: win.animatingClosed = false

                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 0
                    duration: 100
                }
                NumberAnimation {
                    target: panel
                    property: "scale"
                    to: 0.1
                    duration: 200
                    easing.type: Easing.InCirc
                }
            }

            SequentialAnimation {
                id: openAnim
                NumberAnimation {
                    target: panel
                    property: "scale"
                    to: 1
                    duration: 200
                    easing.type: Easing.OutCirc
                }
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 1
                    duration: 100
                }
            }

            ColumnLayout {
                id: content
                anchors {
                    left: parent.left
                    right: parent.right
                    top: parent.top
                    margins: 16
                }
                spacing: 14
                opacity: 0

                // overall / default output
                VolumeRow {
                    Layout.fillWidth: true
                    node: win.sink
                    title: "Master"
                    subtitle: win.sink ? (win.sink.description || win.sink.name || "") : ""
                    iconSource: win.masterIcon
                    tint: true
                }

                Rectangle {
                    Layout.fillWidth: true
                    height: 1
                    color: Qt.alpha(win.theme.on_background, 0.1)
                }

                // one slider per app
                Repeater {
                    model: ScriptModel {
                        values: win.streams
                    }
                    delegate: VolumeRow {
                        required property var modelData
                        Layout.fillWidth: true
                        node: modelData
                        title: win.appName(modelData)
                        iconSource: win.appIcon(modelData)
                        tint: false
                    }
                }

                Text {
                    Layout.alignment: Qt.AlignHCenter
                    visible: win.streams.length === 0
                    text: "No apps are playing audio"
                    color: win.theme.on_background
                    opacity: 0.5
                    font.pixelSize: 13
                    font.family: win.settings.fontdefault
                }
            }
        }
    }
}
