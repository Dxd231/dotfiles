pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// The shutdown screen. While Power waits for windows to close: a card on the Top layer (the apps' own save
// prompts stay usable around it) over a wallpaper tint on the Bottom layer, which lies under every window.
// Once they are all gone: a full-screen goodbye, then the command runs.
Scope {
    id: root

    readonly property int maxRows: 6
    readonly property var info: Power.labels[Power.kind] || Power.labels.poweroff
    readonly property string role: Power.kind === "poweroff" ? "error" : Power.kind === "logout" ? "tertiary" : "primary"
    readonly property color heroColor: role === "error" ? Colors.error_container : role === "tertiary" ? Colors.tertiary_container : Colors.primary_container
    readonly property color onHero: role === "error" ? Colors.on_error_container : role === "tertiary" ? Colors.on_tertiary_container : Colors.on_primary_container
    readonly property color fullColor: role === "error" ? Colors.error : role === "tertiary" ? Colors.tertiary : Colors.primary
    readonly property color onFull: role === "error" ? Colors.on_error : role === "tertiary" ? Colors.on_tertiary : Colors.on_primary
    // the same shapes the power menu gives these actions
    readonly property var heroShape: Power.kind === "poweroff" ? "softBurst" : Power.kind === "logout" ? "sunny" : "cookie9"
    readonly property bool closing: Power.phase === "closing"
    readonly property bool leaving: Power.phase === "leaving"

    property real spin: 0
    FrameAnimation {
        running: Power.closing
        onTriggered: root.spin = (root.spin + frameTime * (root.leaving ? 40 : 14)) % 360
    }

    // rows: the windows being closed, kept a moment after they vanish so each can tick off and collapse
    property var rows: []
    function _describe(t) {
        const de = DesktopEntries.byId(t.appId) ?? DesktopEntries.byId(t.appId + ".desktop") ?? DesktopEntries.heuristicLookup(t.appId);
        return {
            t: t,
            gone: false,
            name: de ? de.name : (t.appId || t.title || "Window"),
            title: t.title || "",
            icon: de && de.icon ? Quickshell.iconPath(de.icon, true) : ""
        };
    }
    function sync() {
        if (!Power.closing) {
            rows = [];
            return;
        }
        const live = Power.remaining;
        const next = rows.map(r => live.includes(r.t) ? r : Object.assign({}, r, { gone: true }));
        for (const t of live) {
            if (!next.some(r => r.t === t))
                next.push(_describe(t));
        }
        rows = next;
        prune.restart();
    }
    Timer {
        id: prune
        interval: 900
        onTriggered: root.rows = root.rows.filter(r => !r.gone)
    }
    Connections {
        target: Power
        function onRemainingChanged() { root.sync(); }
        function onPhaseChanged() {
            // arriving from the power menu: carry on turning from where its hero stopped
            if (Power.phase === "closing") {
                root.spin = Power.handoffSpin;
                Power.handoffSpin = 0;
            }
            root.sync();
        }
        function onStuckChanged() { if (Power.stuck) wobble.restart(); }
    }

    // the hero gives a short jolt when a window starts waiting for the user
    property real wob: 1
    SequentialAnimation {
        id: wobble
        NumberAnimation { target: root; property: "wob"; to: 1.14; duration: 100; easing.type: Easing.OutQuad }
        NumberAnimation { target: root; property: "wob"; to: 1; duration: 600; easing.type: Easing.OutElastic }
    }

    // ---- wallpaper tint, under all windows ----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "quickshell:closing_tint"
            WlrLayershell.layer: WlrLayer.Bottom
            exclusiveZone: -1
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.closing || tint.opacity > 0
            color: "transparent"
            mask: Region {}
            Rectangle {
                id: tint
                anchors.fill: parent
                color: Qt.alpha(Colors.scrim, 0.55)
                opacity: root.closing ? 1 : 0
                Behavior on opacity { Fade { speed: "slow" } }
            }
        }
    }

    // ---- the card ----
    PanelWindow {
        id: cardWindow
        WlrLayershell.namespace: "quickshell:closing_apps"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: root.closing ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusiveZone: 0
        visible: root.closing || card.opacity > 0
        implicitWidth: card.width + 48
        implicitHeight: card.height + 48
        color: "transparent"

        Item {
            anchors.fill: parent
            focus: root.closing
            Keys.onEscapePressed: Power.cancel()
        }

        Elevation {
            anchors.fill: card
            radius: card.radius
            level: 3
            opacity: card.opacity
            scale: card.scale
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: 440
            height: col.implicitHeight + 48
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            opacity: root.closing ? 1 : 0
            // under the goodbye bloom it swells a little instead of shrinking away
            scale: root.closing ? 1 : root.leaving ? 1.06 : 0.9
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            Behavior on height { Spring { speed: "default" } }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 24
                spacing: 6

                // hero: the action's own shape, turning, holding its icon
                Item {
                    Layout.alignment: Qt.AlignHCenter
                    implicitWidth: 132
                    implicitHeight: 132
                    // the power menu's hero hands over at this size, so it only settles a touch
                    scale: (root.closing ? 1 : 1.08) * root.wob
                    Behavior on scale { Spring { speed: "default" } }
                    MorphShape {
                        anchors.fill: parent
                        shape: root.heroShape
                        fromShape: root.heroShape
                        morph: 1
                        spin: root.spin
                        color: root.heroColor
                    }
                    Icon {
                        anchors.centerIn: parent
                        name: root.info.icon
                        size: 52
                        color: root.onHero
                    }
                }

                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 10
                    role: "displaySmall"
                    emphasized: true
                    color: Colors.on_surface
                    text: root.info.title
                    Appear { shown: root.closing; delay: 60 }
                }
                // the line cross-fades (and lifts a little) when its words change
                StyledText {
                    id: reasonText
                    readonly property string wanted: Power.stuck ? "Answer the window that came forward" : Power.reason
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    wrapMode: Text.Wrap
                    role: "bodyLarge"
                    color: Colors.on_surface_variant
                    text: wanted
                    transform: Translate { y: (1 - reasonText.opacity) * 6 }
                    onWantedChanged: if (root.closing) swap.restart()
                    // changes made while the card was away must not leave the old words showing
                    Connections {
                        target: root
                        function onClosingChanged() { if (root.closing) reasonText.text = reasonText.wanted; }
                    }
                    SequentialAnimation {
                        id: swap
                        NumberAnimation { target: reasonText; property: "opacity"; to: 0; duration: 100; easing.type: Easing.InQuad }
                        ScriptAction { script: reasonText.text = reasonText.wanted }
                        NumberAnimation { target: reasonText; property: "opacity"; to: 1; duration: 240; easing.type: Easing.OutQuad }
                    }
                }

                WavyProgress {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    Layout.bottomMargin: 6
                    value: Power.progress
                    waving: root.closing
                    activeColor: root.fullColor
                    trackColor: Colors.surface_container_highest
                    Appear { shown: root.closing; delay: 110; lift: 6 }
                }

                // the windows still being asked
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    Appear { visible: false; shown: root.closing; delay: 150; lift: 10 }
                    Repeater {
                        model: ScriptModel { values: root.rows.slice(0, root.maxRows); objectProp: "t" }
                        delegate: Item {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            // 1 -> 0 once the window is gone: the row ticks off, then collapses
                            property real alive: modelData.gone ? 0 : 1
                            Behavior on alive { Spring { speed: "default" } }
                            implicitHeight: Math.max(0, 44 * alive)
                            opacity: Math.max(0, Math.min(1, alive * 2 - 0.3))
                            clip: true

                            RowLayout {
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                height: 44
                                spacing: 12
                                Item {
                                    Layout.preferredWidth: 28
                                    Layout.preferredHeight: 28
                                    Image {
                                        anchors.fill: parent
                                        opacity: row.modelData.icon !== "" && !row.modelData.gone ? 1 : 0
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        source: row.modelData.icon
                                        sourceSize: Qt.size(56, 56)
                                        fillMode: Image.PreserveAspectFit
                                        asynchronous: true
                                    }
                                    Icon {
                                        anchors.centerIn: parent
                                        opacity: row.modelData.icon === "" || row.modelData.gone ? 1 : 0
                                        scale: row.modelData.gone ? 1 : 0.9
                                        visible: opacity > 0
                                        Behavior on opacity { Fade {} }
                                        Behavior on scale { Spring { speed: "fast" } }
                                        name: row.modelData.gone ? "check_circle" : "web_asset"
                                        size: 24
                                        color: row.modelData.gone ? root.fullColor : Colors.on_surface_variant
                                    }
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        role: "bodyLarge"
                                        color: Colors.on_surface
                                        elide: Text.ElideRight
                                        text: row.modelData.name
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        visible: row.modelData.title !== "" && row.modelData.title !== row.modelData.name
                                        role: "bodySmall"
                                        color: Colors.on_surface_variant
                                        elide: Text.ElideRight
                                        text: row.modelData.title
                                    }
                                }
                                // still open well after being asked: it is waiting on its user
                                Rectangle {
                                    readonly property bool on: Power.stuck && !row.modelData.gone
                                    visible: opacity > 0
                                    opacity: on ? 1 : 0
                                    scale: on ? 1 : 0.6
                                    Behavior on opacity { Fade { speed: "default" } }
                                    Behavior on scale { Spring { speed: "default" } }
                                    implicitWidth: waitLabel.implicitWidth + 20
                                    implicitHeight: 26
                                    radius: 13
                                    color: Colors.secondary_container
                                    StyledText {
                                        id: waitLabel
                                        anchors.centerIn: parent
                                        role: "labelMedium"
                                        color: Colors.on_secondary_container
                                        text: "Waiting for you"
                                    }
                                }
                            }
                        }
                    }
                    Collapse {
                        open: root.rows.length > root.maxRows
                        Layout.topMargin: 4
                        StyledText {
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            text: "+" + Math.max(0, root.rows.length - root.maxRows) + " more"
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 14
                    spacing: 8
                    Appear { visible: false; shown: root.closing; delay: 190; lift: 8 }
                    Item { Layout.fillWidth: true }
                    Button {
                        style: "text"
                        text: "Cancel"
                        onClicked: Power.cancel()
                    }
                    Button {
                        text: root.info.word + " now"
                        color: root.fullColor
                        contentColor: root.onFull
                        onClicked: Power.force()
                    }
                }
            }
        }
    }

    // ---- goodbye: nothing is open any more, so this may cover everything ----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: bye
            required property var modelData
            screen: modelData
            WlrLayershell.namespace: "quickshell:closing_goodbye"
            WlrLayershell.layer: WlrLayer.Overlay
            exclusiveZone: -1
            anchors { top: true; bottom: true; left: true; right: true }
            visible: root.leaving || reveal > 0
            color: "transparent"

            // the goodbye blooms out of the screen centre, where the card's hero was, in the hero's colour
            // and settles to the surface colour
            property real reveal: root.leaving ? 1 : 0
            Behavior on reveal {
                NumberAnimation {
                    duration: Motion.durationSlowSpatial
                    easing.type: Easing.BezierSpline
                    easing.bezierCurve: Motion.emphasizedDecelerate
                }
            }

            Item {
                id: veil
                anchors.fill: parent
                clip: true

                Rectangle {
                    anchors.centerIn: parent
                    width: bye.reveal * Math.hypot(veil.width, veil.height)
                    height: width
                    radius: width / 2
                    color: root.leaving ? Colors.surface : root.heroColor
                    Behavior on color { ColorFade {} }
                }

                MouseArea {
                    anchors.fill: parent
                    enabled: root.leaving
                    onClicked: Power.cancel()
                }

                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 18
                    opacity: root.leaving ? 1 : 0
                    Behavior on opacity { Fade { speed: "default" } }
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 120
                        implicitHeight: 120
                        scale: root.leaving ? 1 : 1.1
                        Behavior on scale { Spring { speed: "default" } }
                        MorphShape {
                            anchors.fill: parent
                            shape: root.heroShape
                            fromShape: root.heroShape
                            morph: 1
                            spin: root.spin
                            color: root.heroColor
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: root.info.icon
                            size: 48
                            color: root.onHero
                        }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        role: "headlineMedium"
                        emphasized: true
                        color: Colors.on_surface
                        text: root.info.title + "…"
                        Appear { shown: root.leaving; delay: 180; lift: 12 }
                    }
                }
            }
        }
    }
}
