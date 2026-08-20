pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import QtQuick.Effects
import Quickshell
import Quickshell.Io

Scope {
    id: root
    property var theme
    property var settings
    property bool menuVisible: false

    function open()   { menuVisible = true }
    function close()  { menuVisible = false }
    function toggle() { menuVisible = !menuVisible }

    IpcHandler {
        target: "powermenu"
        function open(): void   { root.open() }
        function close(): void  { root.close() }
        function toggle(): void { root.toggle() }
    }

    Process { id: suspendProc;     command: ["systemctl", "suspend"] }
    Process { id: logoutProc;   command: ["hyprshutdown"] }
    Process { id: rebootProc;   command: ["sh", "-c", "hyprshutdown --post-cmd 'systemctl reboot'"] }
    Process { id: shutdownProc; command: ["sh", "-c", "hyprshutdown --post-cmd 'systemctl poweroff'"] }

    property var actions: [
        { icon: "../assets/moon.svg",           label: "Suspend",     run: () => suspendProc.running = true }, 
        { icon: "../assets/arrow-u-up-right-fill.svg",      label: "Logout",   run: () => logoutProc.running = true },
        { icon: "../assets/arrow-clockwise-fill.svg",       label: "Reboot",   run: () => rebootProc.running = true },
        { icon: "../assets/power-fill.svg",                 label: "Shutdown", run: () => shutdownProc.running = true }
    ]

    Variants {
        model: Quickshell.screens
        PanelWindow {
            property var modelData
            screen: modelData
            visible: root.menuVisible || panelBg.opacity > 0
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "quickshell:powermenu"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: 0
            anchors { top: true; left: true; right: true }
            margins.top: 32
            color: "transparent"
            implicitHeight: 1000

            MouseArea {
                anchors.fill: parent
                onClicked: root.close()

                Rectangle {
                    id: panelBg
                    width: buttonrow.width + 20
                    height: 180
                    x: 1920 / 2 - width / 2
                    radius: 18
                    color: Qt.alpha(root.theme.background, 0.8)
                    border.width: 1
                    border.color: root.theme.surface_bright

                    MouseArea {
                        anchors.fill: parent
                        onClicked: {}
                    }

                    states: [
                        State {
                            name: "open"
                            when: root.menuVisible
                            PropertyChanges {
                                target: panelBg
                                y: 8
                                opacity: 1
                            }
                        },
                        State {
                            name: "closed"
                            when: !root.menuVisible
                            PropertyChanges {
                                target: panelBg
                                y: -270
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
                                easing.type: Easing.OutCirc
                            }
                        },
                        Transition {
                            from: "open"
                            to: "closed"

                            NumberAnimation {
                                properties: "y,opacity"
                                duration: 400
                                easing.type: Easing.InCirc
                            }
                        }
                    ]

                    RowLayout {
                        id: buttonrow
                        anchors.centerIn: parent
                        spacing: 20

                        Repeater {
                            model: root.actions

                            Rectangle {
                                id: buttons
                                required property var modelData
                                width: 140; height: 140; radius: 18
                                border.color: hover.containsMouse ? root.theme.source_color : "transparent"
                                border.width: 2
                                color: "transparent"

                                Behavior on border.color {
                                    ColorAnimation {
                                        duration: 200
                                        easing.type: Easing.InOutCirc
                                    }
                                }
                                Column {
                                    anchors.centerIn: parent
                                    spacing: 4

                                    Image {
                                        id: icon
                                        source: buttons.modelData.icon
                                        sourceSize.width: hover.containsMouse ? 65 : 50
                                        sourceSize.height: hover.containsMouse ? 65 : 50
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        visible: false

                                        Behavior on sourceSize.width {
                                            NumberAnimation {
                                                duration: 200
                                                easing.type: Easing.OutCirc
                                            }
                                        }

                                        Behavior on sourceSize.height {
                                            NumberAnimation {
                                                duration: 200
                                                easing.type: Easing.OutCirc
                                            }
                                        }
                                    }

                                    MultiEffect {
                                        source: icon
                                        width: icon.sourceSize.width
                                        height: icon.sourceSize.height
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        colorization: 1.0
                                        colorizationColor: root.theme.source_color
                                    }

                                    Text {
                                        text: buttons.modelData.label
                                        font.pixelSize: 16
                                        font.family: root.settings.fontmedium
                                        color: root.theme.on_background
                                        anchors.horizontalCenter: parent.horizontalCenter
                                    }
                                }

                                MouseArea {
                                    id: hover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: {
                                        buttons.modelData.run()
                                        root.close()
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}