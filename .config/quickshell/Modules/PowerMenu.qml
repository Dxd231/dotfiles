pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components

// Power dialog: M3 basic dialog (scrim, surface-container-high, 28px corners, hero icon)
// with large square icon buttons. Keys: ←/→ or h/l to move, Enter/Space to run, 1–6 direct.
Scope {
    id: root

    property var lockScreen: null
    property bool menuVisible: false
    property int selectedIndex: 0

    function open() { menuVisible = true; }
    function close() { menuVisible = false; }
    function toggle() { menuVisible = !menuVisible; }
    function lock() {
        if (lockScreen)
            lockScreen.lock();
        else
            Quickshell.execDetached(["qs", "ipc", "call", "lockscreen", "lock"]);
    }
    function run(i) {
        actions[i].run();
        close();
    }

    onMenuVisibleChanged: if (menuVisible) selectedIndex = 0

    IpcHandler {
        target: "powermenu"
        function open(): void { root.open(); }
        function close(): void { root.close(); }
        function toggle(): void { root.toggle(); }
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

    // role: "primary" | "tertiary" | "error"
    readonly property var actions: [
        { icon: "lock", label: "Lock", role: "primary", run: () => root.lock() },
        { icon: "monitor", label: "Screen off", role: "primary", run: () => root.lockThen(["hyprctl", "dispatch", "hl.dsp.dpms({ action = \"off\" })"]) },
        { icon: "bedtime", label: "Suspend", role: "primary", run: () => root.lockThen(["systemctl", "suspend"]) },
        { icon: "logout", label: "Log out", role: "tertiary", run: () => Quickshell.execDetached(["hyprshutdown"]) },
        { icon: "restart_alt", label: "Restart", role: "tertiary", run: () => Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl reboot"]) },
        { icon: "power_settings_new", label: "Shut down", role: "error", run: () => Quickshell.execDetached(["hyprshutdown", "--post-cmd", "systemctl poweroff"]) }
    ]

    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: panelWindow
            required property var modelData
            screen: modelData
            visible: root.menuVisible || scrim.opacity > 0
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
                    if (event.key === Qt.Key_Escape)
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
                width: content.implicitWidth + 48
                height: content.implicitHeight + 48
                radius: Motion.shapeExtraLarge
                color: Colors.surface_container_high
                opacity: root.menuVisible ? 1 : 0
                scale: root.menuVisible ? 1 : 0.9
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on scale { Spring { speed: "default" } }

                // swallow clicks so they don't reach the scrim
                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: content
                    anchors.centerIn: parent
                    spacing: 16

                    Icon {
                        Layout.alignment: Qt.AlignHCenter
                        name: "settings_power"
                        color: Colors.secondary
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        role: "headlineSmall"
                        text: "Power"
                    }
                    StyledText {
                        Layout.alignment: Qt.AlignHCenter
                        Layout.bottomMargin: 8
                        role: "bodyMedium"
                        color: Colors.on_surface_variant
                        text: "Choose an action, or press 1–6"
                    }

                    Row {
                        Layout.alignment: Qt.AlignHCenter
                        spacing: 12

                        Repeater {
                            model: root.actions
                            delegate: Column {
                                id: action
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.selectedIndex
                                spacing: 8

                                // selection (keyboard or hover) morphs the square to a circle and
                                // switches from the container role to the full-strength role
                                IconButton {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    readonly property string role: action.modelData.role
                                    size: "l"
                                    square: true
                                    restRadius: action.selected ? height / 2 : Motion.shapeExtraLarge
                                    icon: action.modelData.icon
                                    color: role === "error" ? (action.selected ? Colors.error : Colors.error_container)
                                         : role === "tertiary" ? (action.selected ? Colors.tertiary : Colors.tertiary_container)
                                         : (action.selected ? Colors.primary : Colors.secondary_container)
                                    contentColor: role === "error" ? (action.selected ? Colors.on_error : Colors.on_error_container)
                                         : role === "tertiary" ? (action.selected ? Colors.on_tertiary : Colors.on_tertiary_container)
                                         : (action.selected ? Colors.on_primary : Colors.on_secondary_container)
                                    onClicked: root.run(action.index)
                                    onHoveredChanged: if (hovered) root.selectedIndex = action.index
                                }
                                StyledText {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    role: "labelLarge"
                                    color: action.selected ? Colors.on_surface : Colors.on_surface_variant
                                    text: action.modelData.label
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
