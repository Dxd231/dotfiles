pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.Pipewire
import Quickshell.Wayland
import qs
import qs.Components

// Mixer: output device + per-app streams as an M3 Expressive segmented list.
BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:volume_popup"
    panelWidth: 380

    // 150% boost ceiling, toggled from the bar chip (right-click); shared with the OSD
    property bool boostEnabled: false
    readonly property real maxVolume: boostEnabled ? 1.5 : 1.0

    readonly property PwNode sink: Pipewire.defaultAudioSink
    // hide streams whose app / binary / node name contains any of these (case-insensitive)
    property var blacklist: ["virtual source", "speech-dispatcher"]
    property var iconOverrides: ({
        "zalocall.exe": "../assets/zalo.svg",
        "spotify": "../assets/spotify-color-svgrepo-com.svg",
        "wine-preloader": "../assets/wine.svg"
    })

    function props(n) {
        return n && n.properties ? n.properties : ({});
    }
    function isBlacklisted(n) {
        if (!n)
            return true;
        const p = props(n);
        const hay = [p["application.name"], p["application.process.binary"], n.name, n.nickname, n.description].filter(s => s).join("|").toLowerCase();
        return blacklist.some(b => hay.includes(b));
    }
    function appName(n) {
        if (!n)
            return "";
        return props(n)["application.name"] || n.nickname || n.description || n.name || "Unknown";
    }
    function appIcon(n) {
        if (!n)
            return "";
        const p = props(n);
        for (const k of [p["application.name"], p["application.process.binary"], n.name].filter(s => s).map(s => s.toLowerCase()))
            if (iconOverrides[k])
                return iconOverrides[k];
        return Quickshell.iconPath(p["application.icon-name"] || p["application.process.binary"] || "", "audio-x-generic");
    }

    // playback streams, from what the registry already knows. Binding a node fills in its properties, so a
    // list that reads them would change under the tracker mid-bind and unbind the node inside its own
    // first info callback (a crash while a recorder's capture stream was around)
    readonly property var outStreams: Pipewire.nodes.values.filter(n => n && n.type === PwNodeType.AudioOutStream)
    readonly property var streams: outStreams.filter(n => !isBlacklisted(n))

    // bind audio params only for what is on screen
    PwObjectTracker { objects: [win.sink] }
    PwObjectTracker { objects: win.isOpen ? win.outStreams : [] }

    IpcHandler {
        target: "volumePopup"
        function toggle(): void { win.toggle(); }
    }

    // Output
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { role: "titleLarge"; text: "Sound" }
            SwapText {
                Layout.fillWidth: true
                role: "bodyMedium"
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                value: win.sink ? (win.sink.description || win.sink.name || "") : "No output device"
            }
        }
        IconButton {
            icon: "volume_off"
            style: "tonal"
            checkable: true
            checked: !!win.sink && !!win.sink.audio && win.sink.audio.muted
            onClicked: if (win.sink && win.sink.audio) win.sink.audio.muted = !win.sink.audio.muted
        }
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 12
        readonly property var audio: win.sink ? win.sink.audio : null

        Slider {
            Layout.fillWidth: true
            size: "m"
            to: win.maxVolume
            stepSize: 0.05
            value: parent.audio ? parent.audio.volume : 0
            icon: !parent.audio || parent.audio.muted ? "volume_off" : parent.audio.volume <= 0 ? "volume_mute" : parent.audio.volume < 0.5 ? "volume_down" : "volume_up"
            activeColor: parent.audio && parent.audio.muted ? Colors.outline : Colors.primary
            onMoved: v => {
                if (parent.audio)
                    parent.audio.volume = v;
            }
        }
        Item {
            Layout.preferredWidth: 40
            Layout.preferredHeight: mainPct.implicitHeight
            RollingDigits {
                id: mainPct
                anchors.right: parent.right
                pixelSize: 14
                weight: Font.Medium
                color: Colors.on_surface_variant
                text: Math.round((parent.parent.audio ? parent.parent.audio.volume : 0) * 100) + "%"
            }
        }
    }

    Collapse {
        open: win.streams.length > 0
        Layout.leftMargin: 4
        Layout.topMargin: 4
        StyledText {
            role: "labelLarge"
            color: Colors.primary
            text: "Apps"
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        spacing: 2

        Repeater {
            model: ScriptModel { values: win.streams }
            delegate: SegmentedItem {
                id: item
                required property PwNode modelData
                required property int index
                readonly property var audio: modelData ? modelData.audio : null
                readonly property bool muted: !!audio && audio.muted

                first: index === 0
                last: index === win.streams.length - 1
                Layout.fillWidth: true
                implicitHeight: itemRow.implicitHeight + 12
                Appear { delay: 60 + item.index * 50 }

                RowLayout {
                    id: itemRow
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 16
                    spacing: 12

                    // app icon; click toggles mute
                    Clickable {
                        implicitWidth: 40
                        implicitHeight: 40
                        restRadius: Motion.shapeMedium
                        pressedRadius: Motion.shapeSmall
                        color: item.muted ? Colors.error_container : "transparent"
                        contentColor: item.muted ? Colors.on_error_container : Colors.on_surface
                        onClicked: if (item.audio) item.audio.muted = !item.audio.muted

                        Image {
                            anchors.centerIn: parent
                            width: 28
                            height: 28
                            sourceSize: Qt.size(28, 28)
                            source: win.appIcon(item.modelData)
                            opacity: item.muted ? 0 : 1
                            Behavior on opacity { Fade {} }
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: "volume_off"
                            color: Colors.on_error_container
                            opacity: item.muted ? 1 : 0
                            Behavior on opacity { Fade {} }
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        RowLayout {
                            Layout.fillWidth: true
                            StyledText {
                                Layout.fillWidth: true
                                role: "titleSmall"
                                elide: Text.ElideRight
                                text: win.appName(item.modelData)
                            }
                            RollingDigits {
                                pixelSize: 12
                                weight: Font.Medium
                                color: Colors.on_surface_variant
                                text: Math.round((item.audio ? item.audio.volume : 0) * 100) + "%"
                            }
                        }
                        Slider {
                            Layout.fillWidth: true
                            size: "xs"
                            to: win.maxVolume
                            stepSize: 0.05
                            value: item.audio ? item.audio.volume : 0
                            activeColor: item.muted ? Colors.outline : Colors.primary
                            onMoved: v => {
                                if (item.audio)
                                    item.audio.volume = v;
                            }
                        }
                    }
                }
            }
        }
    }
}
