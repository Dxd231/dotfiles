pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Everything on screen around a capture, besides the picker: the countdown before a delayed shot or
// recording, the brackets around a region that is being recorded, and the card that says what was
// saved with the buttons to use it. None of them take keyboard focus, so a game keeps its input.
Scope {
    id: root

    readonly property var screenOf: Quickshell.screens.find(s => s.name === Capture.mon.name) ?? Quickshell.screens[0]

    // ---------------------------------------------------------------- the result
    PanelWindow {
        id: win

        readonly property var r: Capture.last
        readonly property bool wanted: Capture.cardShown && !!r
        readonly property bool failed: !!r && !!r.error
        readonly property bool video: !!r && r.kind === "video"
        screen: root.screenOf

        anchors { bottom: true; left: true; right: true }
        implicitHeight: 300
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.namespace: "quickshell:capturecard"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: wanted || card.appear > 0.01
        mask: Region { item: card }

        onWantedChanged: {
            if (wanted)
                hideTimer.restart();
            else
                hideTimer.stop();
        }
        Connections {
            target: Capture
            function onLastChanged() {
                if (Capture.last) {
                    hideTimer.restart();
                    pop.restart();
                }
            }
        }
        Timer {
            id: hideTimer
            interval: 8000
            onTriggered: {
                if (hover.hovered)
                    restart();
                else
                    Capture.dismissCard();
            }
        }
        function sizeText(b) {
            return b > 1048576 ? (b / 1048576).toFixed(1) + " MB" : Math.max(1, Math.round(b / 1024)) + " KB";
        }
        function clock(s) {
            const m = Math.floor(s / 60), h = Math.floor(m / 60);
            const p = n => (n < 10 ? "0" : "") + n;
            return h > 0 ? h + ":" + p(m % 60) + ":" + p(s % 60) : m + ":" + p(s % 60);
        }

        Elevation {
            x: card.x
            y: card.y
            width: card.width
            height: card.height
            radius: card.radius
            level: 3
            opacity: card.opacity
            scale: card.scale
            transformOrigin: Item.Bottom
        }
        Rectangle {
            id: card
            width: 580
            property real h: body.implicitHeight + 32
            Behavior on h { Spring { speed: "default" } }
            height: Math.max(0, h)
            anchors.horizontalCenter: parent.horizontalCenter
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            property real appear: win.wanted ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            y: win.height - height - 28 + (1 - appear) * 40
            opacity: Math.max(0, Math.min(1, appear * 1.6))
            scale: 0.92 + 0.08 * appear
            transformOrigin: Item.Bottom

            HoverHandler { id: hover }

            ColumnLayout {
                id: body
                x: 16
                y: 16
                width: parent.width - 32
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 14

                    // the picture swells in when a new one lands
                    ClippingRectangle {
                        id: thumb
                        property real popv: 1
                        property real w: win.r && win.r.w > 0 && win.r.h > 0 ? Math.max(72, Math.min(184, 84 * win.r.w / win.r.h)) : 120
                        Behavior on w { Spring { speed: "fast" } }
                        Layout.preferredWidth: Math.max(0, w)
                        Layout.preferredHeight: 84
                        radius: 20
                        color: win.failed ? Colors.error_container : Colors.surface_container_highest
                        scale: 0.8 + 0.2 * popv
                        SequentialAnimation {
                            id: pop
                            NumberAnimation { target: thumb; property: "popv"; to: 0; duration: 1 }
                            Spring { target: thumb; property: "popv"; to: 1; speed: "fast" }
                        }
                        Image {
                            anchors.fill: parent
                            opacity: win.failed ? 0 : 1
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            source: win.r && win.r.thumb ? "file://" + win.r.thumb : ""
                            fillMode: Image.PreserveAspectCrop
                            cache: false
                            asynchronous: true
                            sourceSize.width: 400
                        }
                        Icon {
                            anchors.centerIn: parent
                            opacity: win.failed ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            size: 28
                            name: "error"
                            color: Colors.on_error_container
                        }
                        // a recording: a play shape over the first frame
                        ShapeBadge {
                            readonly property bool on: win.video && !win.failed
                            badgeScale: on ? 1 : 0.3
                            opacity: on ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            shapeRest: "cookie9"
                            color: Qt.alpha(Colors.surface_container_high, 0.9)
                            Icon {
                                anchors.centerIn: parent
                                size: 22
                                name: "play_arrow"
                                color: Colors.on_surface
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        StyledText {
                            role: "titleMedium"
                            emphasized: true
                            text: win.failed ? (win.video ? "Recording failed" : "Capture failed") : win.video ? "Recording saved" : "Screenshot saved"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            elide: Text.ElideRight
                            text: {
                                const r = win.r;
                                if (!r)
                                    return "";
                                if (r.error)
                                    return r.error;
                                const parts = [];
                                if (r.kind === "video")
                                    parts.push(win.clock(r.seconds));
                                if (r.w > 0)
                                    parts.push(r.w + " × " + r.h);
                                parts.push(win.sizeText(r.bytes));
                                if (r.label)
                                    parts.push(r.label);
                                return parts.join("  ·  ");
                            }
                        }
                        Collapse {
                            open: !win.failed
                            Layout.fillWidth: true
                            StyledText {
                                role: "labelSmall"
                                color: Colors.on_surface_variant
                                elide: Text.ElideMiddle
                                text: win.r && win.r.path ? win.r.path.replace(/^.*\//, "") : ""
                            }
                        }
                    }
                    IconButton { icon: "close"; size: "xs"; onClicked: Capture.dismissCard() }
                }

                Collapse {
                    open: !win.failed
                    Layout.fillWidth: true
                    RowLayout {
                        spacing: 8
                        Button {
                            size: "xs"
                            style: "filled"
                            icon: "content_copy"
                            text: win.video ? "Copy file" : "Copy"
                            onClicked: Capture.copyLast()
                        }
                        Collapse {
                            horizontal: true
                            open: !win.video
                            Button {
                                size: "xs"
                                style: "tonal"
                                icon: "edit"
                                text: "Edit"
                                onClicked: {
                                    Capture.editLast();
                                    Capture.dismissCard();
                                }
                            }
                        }
                        Button {
                            size: "xs"
                            style: "tonal"
                            icon: "open_in_new"
                            text: "Open"
                            onClicked: Capture.openLast()
                        }
                        Item { Layout.fillWidth: true }
                        IconButton { icon: "folder_open"; style: "tonal"; size: "xs"; onClicked: Capture.folderLast() }
                        IconButton { icon: "delete"; style: "tonal"; size: "xs"; onClicked: Capture.deleteLast() }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- the countdown
    PanelWindow {
        id: countdown

        readonly property bool on: Capture.phase === "counting"
        screen: root.screenOf
        anchors { top: true }
        margins.top: 96
        implicitWidth: 240
        implicitHeight: 240
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.namespace: "quickshell:capturecount"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        visible: on || badge.scale > 0.02
        // a click on it calls the capture off (the window takes no keys, so there is no Esc)
        mask: Region { item: hud }

        Item {
            id: hud
            width: parent.width
            height: parent.height
            TapHandler { onTapped: Capture.cancel() }

            ShapeBadge {
                id: badge
                anchors.horizontalCenter: parent.horizontalCenter
                y: 8
                width: 156
                height: 156
                shapeRest: "softBurst"
                shapeActive: "sunny"
                active: Capture.count % 2 === 0
                color: Capture.mode === "video" ? Colors.error_container : Colors.primary_container
                scale: countdown.on ? 1 : 0
                Behavior on scale { Spring { speed: "default" } }
                RollingDigits {
                    anchors.centerIn: parent
                    pixelSize: 64
                    text: String(Math.max(0, Capture.count))
                    color: Capture.mode === "video" ? Colors.on_error_container : Colors.on_primary_container
                }
            }
            Rectangle {
                id: hint
                anchors.horizontalCenter: parent.horizontalCenter
                y: 180
                height: 28
                width: hintText.implicitWidth + 24
                radius: 14
                color: Colors.surface_container_high
                opacity: countdown.on ? 1 : 0
                Behavior on opacity { Fade {} }
                StyledText {
                    id: hintText
                    anchors.centerIn: parent
                    role: "labelMedium"
                    emphasized: true
                    color: Colors.on_surface_variant
                    text: "Click to cancel"
                }
            }
        }
    }

    // ---------------------------------------------------------------- brackets around a region being recorded
    PanelWindow {
        id: frame

        readonly property var rect: Capture.recRegion
        readonly property real sw: root.screenOf ? root.screenOf.width : 1920
        readonly property real sh: root.screenOf ? root.screenOf.height : 1080
        // only as big as the region and its brackets
        readonly property real ox: rect ? Math.max(0, rect.x - 16) : 0
        readonly property real oy: rect ? Math.max(0, rect.y - 16) : 0
        screen: root.screenOf
        anchors { top: true; left: true }
        margins.left: ox
        margins.top: oy
        implicitWidth: rect ? Math.max(1, Math.min(sw, rect.x + rect.w + 16) - ox) : 1
        implicitHeight: rect ? Math.max(1, Math.min(sh, rect.y + rect.h + 16) - oy) : 1
        exclusiveZone: -1
        color: "transparent"
        WlrLayershell.namespace: "quickshell:captureframe"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        // the brackets spring in and out toward their corners (always away from the recorded area)
        property real k: Capture.hasRegionFrame ? 1 : 0
        Behavior on k { Spring { speed: "default" } }
        visible: Capture.hasRegionFrame || k > 0.01
        mask: Region {}

        // a bracket sits just outside each corner, so nothing of it lands in the video
        Repeater {
            model: 4
            delegate: Item {
                id: corner
                required property int index
                readonly property bool atRight: index % 2 === 1
                readonly property bool atBottom: index >= 2
                readonly property real cx: frame.rect ? frame.rect.x - frame.ox + (atRight ? frame.rect.w : 0) : 0
                readonly property real cy: frame.rect ? frame.rect.y - frame.oy + (atBottom ? frame.rect.h : 0) : 0
                opacity: Capture.recPaused ? 0.4 : 1
                Behavior on opacity { Fade {} }
                transform: Scale { origin.x: corner.cx; origin.y: corner.cy; xScale: Math.max(0, frame.k); yScale: Math.max(0, frame.k) }
                SequentialAnimation on opacity {
                    running: Capture.hasRegionFrame && !Capture.recPaused
                    loops: Animation.Infinite
                    NumberAnimation { to: 0.5; duration: 900; easing.type: Easing.InOutSine }
                    NumberAnimation { to: 1; duration: 900; easing.type: Easing.InOutSine }
                }
                // along the top / bottom edge, and along the left / right edge
                Rectangle {
                    x: corner.cx + (corner.atRight ? -26 : -10)
                    y: corner.cy + (corner.atBottom ? 4 : -10)
                    width: 36
                    height: 6
                    radius: 3
                    color: Colors.error
                }
                Rectangle {
                    x: corner.cx + (corner.atRight ? 4 : -10)
                    y: corner.cy + (corner.atBottom ? -26 : -10)
                    width: 6
                    height: 36
                    radius: 3
                    color: Colors.error
                }
            }
        }
    }
}
