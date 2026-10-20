pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Power dialog. A hero shape in the selected action's colour springs (and overshoots) into that
// action's own Expressive shape as the selection moves; below it each idle button is its own
// slowly turning silhouette, and the selected one expands into a labelled pill.
// Keys: ←/→ or h/l to move, Enter/Space to run, 1–6 direct.
Scope {
    id: root

    property var lockScreen: null
    property bool menuVisible: false
    property int selectedIndex: 0

    // hero morph: the shape it came from, the one it is going to, and how far along (0..1)
    property int heroFrom: 0
    property int heroTo: 2
    property real heroMorph: 1
    property bool heroSpring: true
    property real heroSpin: 0

    function open() { menuVisible = true; }
    function close() { menuVisible = false; }
    function toggle() { menuVisible = !menuVisible; }
    function lock() {
        if (lockScreen)
            lockScreen.lock();
        else
            Quickshell.execDetached(["qs", "ipc", "call", "lockscreen", "lock"]);
    }
    // choosing log out / restart / shut down: the other buttons fly out, the chosen one folds back into its
    // shape, which shrinks to the closing card's hero size and keeps turning; then the card takes over
    property bool launching: false
    // the dialog surface; it lags the menu a moment on close so its parts are seen leaving first
    property bool dialogUp: false
    property real launchFade: launching ? 0 : 1
    Behavior on launchFade { Fade {} }

    function run(i) {
        if (launching)
            return;
        if (i >= 3) {
            selectedIndex = i;
            launching = true;
            dialogUp = false;
            launchTimer.index = i;
            launchTimer.restart();
            return;
        }
        actions[i].run();
        close();
    }
    Timer {
        id: launchTimer
        property int index: 0
        interval: 300
        onTriggered: {
            Power.handoffSpin = root.heroSpin;
            root.actions[index].run();
            root.close();
        }
    }
    Timer {
        id: dialogDown
        interval: 140
        onTriggered: root.dialogUp = false
    }

    onMenuVisibleChanged: {
        if (!menuVisible) {
            if (!launching)
                dialogDown.restart();
            return;
        }
        launching = false;
        dialogDown.stop();
        dialogUp = true;
        selectedIndex = 0;
        // open on the first action's shape, no morph
        heroSpring = false;
        heroFrom = heroTo = actions[0].shape;
        heroMorph = 1;
        heroSpring = true;
    }
    // a new selection: snap the morph to 0, then let it spring to 1; the low damping overshoots to
    // about 1.3 and wobbles back, so the shape visibly stretches past its target
    onSelectedIndexChanged: {
        heroFrom = heroTo;
        heroTo = actions[selectedIndex].shape;
        heroSpring = false;
        heroMorph = 0;
        heroSpring = true;
        heroMorph = 1;
    }
    Behavior on heroMorph {
        enabled: root.heroSpring
        SpringAnimation { spring: 3.2; damping: 0.16; epsilon: 0.001 }
    }
    FrameAnimation {
        running: root.menuVisible || root.dialogUp
        onTriggered: root.heroSpin = (root.heroSpin + frameTime * (root.launching ? 90 : 14)) % 360
    }

    IpcHandler {
        target: "powermenu"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
        function select(index: int): void { root.selectedIndex = Math.max(0, Math.min(root.actions.length - 1, index)); }
    }

    // lock first, then act once the lock surface is up
    Timer {
        id: afterLock
        property var command: []
        interval: 1000
        onTriggered: Quickshell.execDetached(command)
    }
    function lockThen(command) {
        lock();
        afterLock.command = command;
        afterLock.restart();
    }

    readonly property string restartDesc: {
        if (!Power.rebootPending)
            return "Restart the computer";
        const p = Power.pendingPackages;
        if (p.length === 0)
            return "Updated drivers are waiting for a reboot";
        return "Updates are waiting: " + p.slice(0, 3).join(", ") + (p.length > 3 ? "…" : "");
    }

    // role: "primary" | "tertiary" | "attention" | "error"; shape indices are MorphShape's
    readonly property var actions: [
        { icon: "lock", label: "Lock", desc: "Lock the screen", role: "primary", shape: 2, run: () => root.lock() },
        { icon: "monitor", label: "Screen off", desc: "Lock, then turn the display off", role: "primary", shape: 6, run: () => root.lockThen(["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\" })"]) },
        { icon: "bedtime", label: "Suspend", desc: "Lock, then sleep until you wake it", role: "primary", shape: 5, run: () => root.lockThen(["systemctl", "suspend"]) },
        { icon: "logout", label: "Log out", desc: "End this session", role: "tertiary", shape: 4, run: () => Power.run("logout") },
        { icon: "restart_alt", label: "Restart", desc: root.restartDesc, role: Power.rebootPending ? "attention" : "tertiary", shape: 1, run: () => Power.run("reboot") },
        { icon: "power_settings_new", label: "Shut down", desc: "Power off completely", role: "error", shape: 0, run: () => Power.run("poweroff") }
    ]

    // colour roles: the hero and idle buttons use the container; the selected button the full colour
    function container(role) { return role === "attention" ? Colors.primary_container : role === "error" ? Colors.error_container : role === "tertiary" ? Colors.tertiary_container : Colors.secondary_container; }
    function onContainer(role) { return role === "attention" ? Colors.on_primary_container : role === "error" ? Colors.on_error_container : role === "tertiary" ? Colors.on_tertiary_container : Colors.on_secondary_container; }
    function full(role) { return role === "attention" ? Colors.primary : role === "error" ? Colors.error : role === "tertiary" ? Colors.tertiary : Colors.primary; }
    function onFull(role) { return role === "attention" ? Colors.on_primary : role === "error" ? Colors.on_error : role === "tertiary" ? Colors.on_tertiary : Colors.on_primary; }

    readonly property var current: actions[selectedIndex]

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: root.menuVisible || scrim.opacity > 0 || dialog.opacity > 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.menuVisible ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:powermenu"
            exclusiveZone: -1
            anchors { top: true; bottom: true; left: true; right: true }
            color: "transparent"

            Item {
                anchors.fill: parent
                focus: root.menuVisible
                Keys.onPressed: event => {
                    const n = root.actions.length;
                    if (root.launching)
                        event.accepted = true;
                    else if (event.key === Qt.Key_Escape)
                        root.close();
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_H)
                        root.selectedIndex = (root.selectedIndex - 1 + n) % n;
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_L || event.key === Qt.Key_Tab)
                        root.selectedIndex = (root.selectedIndex + 1) % n;
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space)
                        root.run(root.selectedIndex);
                    else if (event.key >= Qt.Key_1 && event.key < Qt.Key_1 + n)
                        root.run(event.key - Qt.Key_1);
                    else
                        return;
                    event.accepted = true;
                }
            }

            Rectangle {
                id: scrim
                anchors.fill: parent
                color: Qt.alpha(Colors.scrim, 0.32)
                opacity: root.menuVisible ? 1 : 0
                Behavior on opacity { Fade { speed: "default" } }
                MouseArea {
                    anchors.fill: parent
                    enabled: root.menuVisible
                    onClicked: root.close()
                }
            }

            Elevation {
                anchors.fill: dialog
                radius: dialog.radius
                level: 3
                opacity: dialog.opacity
                scale: dialog.scale
            }

            Rectangle {
                id: dialog
                anchors.centerIn: parent
                width: 640
                height: content.implicitHeight + 64
                radius: Motion.shapeExtraLarge
                color: Colors.surface_container_high
                opacity: root.dialogUp ? 1 : 0
                scale: root.dialogUp ? 1 : 0.9
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on scale { Spring { speed: "default" } }

                // swallow clicks so they don't reach the scrim
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: content
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 8

                    // ---- hero ----
                    Item {
                        Layout.alignment: Qt.AlignHCenter
                        implicitWidth: 240
                        implicitHeight: 240
                        scale: root.launching ? 0.55 : root.menuVisible ? 1 : 0.4
                        Behavior on scale { Spring { speed: "default" } }

                        MorphShape {
                            id: hero
                            anchors.fill: parent
                            shape: root.heroTo
                            fromShape: root.heroFrom
                            morph: root.heroMorph
                            spin: root.heroSpin
                            color: root.container(root.current.role)
                            Behavior on color { ColorFade {} }
                        }
                        Icon {
                            anchors.centerIn: parent
                            name: root.current.icon
                            size: 88
                            color: root.onContainer(root.current.role)
                            // pops in with the morph's overshoot
                            scale: 0.5 + 0.5 * root.heroMorph
                            rotation: (1 - Math.min(1, root.heroMorph)) * -25
                            Behavior on color { ColorFade {} }
                        }
                    }

                    // ---- what it does ----
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 8
                        role: "displaySmall"
                        emphasized: true
                        text: root.current.label
                        opacity: Math.min(1, 0.15 + root.heroMorph * 1.2) * root.launchFade
                        scale: 0.85 + 0.15 * Math.min(1.1, root.heroMorph)
                        transform: Translate { y: (1 - Math.min(1, root.heroMorph)) * 24 }
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 16
                        role: "bodyLarge"
                        color: Colors.on_surface_variant
                        text: root.current.desc
                        opacity: Math.min(1, 0.15 + root.heroMorph * 1.2) * root.launchFade
                    }

                    // ---- button group: idle buttons are their own turning silhouettes; the selected one expands ----
                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Repeater {
                            model: root.actions
                            delegate: Item {
                                id: btn
                                required property var modelData
                                required property int index
                                // while launching, the chosen button folds back into its shape
                                readonly property bool selected: index === root.selectedIndex && !root.launching
                                property bool shown: false

                                width: selected ? row.implicitWidth + 44 : 64
                                height: 64
                                Behavior on width { Spring { speed: "default" } }

                                // staggered entrance: rises, and turns in from a tilt
                                opacity: shown ? 1 : 0
                                Behavior on opacity { Fade { speed: "default" } }
                                transform: [
                                    Translate {
                                        y: btn.shown ? 0 : 48
                                        Behavior on y { Spring { speed: "default" } }
                                    },
                                    Rotation {
                                        origin.x: 32
                                        origin.y: 32
                                        angle: btn.shown ? 0 : -20
                                        Behavior on angle { Spring { speed: "default" } }
                                    }
                                ]
                                Timer {
                                    interval: 120 + btn.index * 45
                                    running: root.menuVisible
                                    onTriggered: btn.shown = true
                                }
                                // leaving: the buttons go in reverse order, last first; launching: all but the chosen one
                                Timer {
                                    id: out
                                    interval: (root.actions.length - 1 - btn.index) * 30
                                    onTriggered: btn.shown = false
                                }
                                Connections {
                                    target: root
                                    function onMenuVisibleChanged() { if (!root.menuVisible) out.restart(); }
                                    function onLaunchingChanged() { if (root.launching && btn.index !== root.selectedIndex) out.restart(); }
                                }

                                // idle: this action's own silhouette, slowly turning (grows on hover, squashes on press)
                                MorphShape {
                                    anchors.centerIn: parent
                                    width: 64
                                    height: 64
                                    shape: btn.modelData.shape
                                    fromShape: btn.modelData.shape
                                    spin: (btn.index % 2 ? -1 : 1) * root.heroSpin * 2.5
                                    color: root.container(btn.modelData.role)
                                    opacity: btn.selected ? 0 : 1
                                    scale: btn.selected ? 0.3 : (mouse.pressed ? 0.88 : mouse.containsMouse ? 1.14 : 1)
                                    Behavior on opacity { Fade { speed: "default" } }
                                    Behavior on scale { Spring { speed: "fast" } }
                                }
                                // selected: the full-colour pill
                                Rectangle {
                                    anchors.fill: parent
                                    radius: height / 2
                                    color: root.full(btn.modelData.role)
                                    opacity: btn.selected ? 1 : 0
                                    scale: btn.selected ? 1 : 0.5
                                    Behavior on opacity { Fade { speed: "default" } }
                                    Behavior on scale { Spring { speed: "default" } }
                                    Behavior on color { ColorFade {} }
                                }

                                Row {
                                    id: row
                                    anchors.centerIn: parent
                                    spacing: 8
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        name: btn.modelData.icon
                                        size: 28
                                        color: btn.selected ? root.onFull(btn.modelData.role) : root.onContainer(btn.modelData.role)
                                        Behavior on color { ColorFade {} }
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: opacity > 0
                                        opacity: btn.selected ? 1 : 0
                                        Behavior on opacity { Fade {} }
                                        role: "titleMedium"
                                        emphasized: true
                                        color: root.onFull(btn.modelData.role)
                                        text: btn.modelData.label
                                    }
                                }

                                MouseArea {
                                    id: mouse
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.run(btn.index)
                                    onContainsMouseChanged: if (containsMouse && !root.launching) root.selectedIndex = btn.index
                                }
                            }
                        }
                    }

                    // ---- keys ----
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.topMargin: 16
                        role: "labelMedium"
                        color: Colors.on_surface_variant
                        opacity: root.launchFade
                        text: "←  →  choose    ·    Enter  confirm    ·    1–6  jump    ·    Esc  close"
                    }
                }
            }
        }
    }
}
