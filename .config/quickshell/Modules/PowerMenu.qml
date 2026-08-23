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

    property int selectedIndex: 0          

    onMenuVisibleChanged: {
        if (menuVisible) 
            selectedIndex = 0
    }

    IpcHandler {
        target: "powermenu"
        function open(): void   { root.open() }
        function close(): void  { root.close() }
        function toggle(): void { root.toggle() }
    }

    Timer {
        id: dpmsTimer
        interval: 400          // 300–600 ms usually works well
        repeat: false
        onTriggered: {
            Quickshell.execDetached([
                "hyprctl", "dispatch",
                'hl.dsp.dpms({ action = "off" })'
            ])
        }
    }

    property var actions: [
        { icon: "../assets/monitor.svg",                    label: "DPMS",     run: () => dpmsTimer.start() },
        { icon: "../assets/moon.svg",                       label: "Suspend",  run: () => Quickshell.execDetached(["systemctl", "suspend"]) }, 
        { icon: "../assets/arrow-u-up-right-fill.svg",      label: "Logout",   run: () => Quickshell.execDetached(["hyprshutdown"]) },
        { icon: "../assets/arrow-clockwise-fill.svg",       label: "Reboot",   run: () => Quickshell.execDetached(["sh", "-c", "hyprshutdown --post-cmd 'systemctl reboot'"]) },
        { icon: "../assets/power-fill.svg",                 label: "Shutdown", run: () => Quickshell.execDetached(["sh", "-c", "hyprshutdown --post-cmd 'systemctl poweroff'"]) }
    ]

    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: panelWindow
            property var modelData
            screen: modelData
            visible: root.menuVisible || panelBg.opacity > 0       
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: root.menuVisible
                ? WlrKeyboardFocus.OnDemand
                : WlrKeyboardFocus.None
            WlrLayershell.namespace: "quickshell:powermenu"
            exclusiveZone: 0
            anchors { top: true; left: true; right: true }
            margins.top: 0
            color: "transparent"
            implicitHeight: 1080

            Item {
                id: keyHandler
                anchors.fill: parent
                focus: root.menuVisible
                Keys.enabled: root.menuVisible

                Keys.onPressed: event => {
                    if (event.key === Qt.Key_Escape) {
                        root.close()
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Left || event.key === Qt.Key_H) {
                        root.selectedIndex = (root.selectedIndex - 1 + root.actions.length) % root.actions.length
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Right || event.key === Qt.Key_L) {
                        root.selectedIndex = (root.selectedIndex + 1) % root.actions.length
                        event.accepted = true
                    }
                    else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
                        root.actions[root.selectedIndex].run()
                        root.close()
                        event.accepted = true
                    }
                    else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_4) {
                        const idx = event.key - Qt.Key_1
                        if (idx < root.actions.length) {
                            root.selectedIndex = idx
                            root.actions[idx].run()
                            root.close()
                        }
                        event.accepted = true
                    }
                }
            }

            MouseArea {
                anchors.fill: parent
                enabled: root.menuVisible
                onClicked: root.close()
            }

            Rectangle {
                id: panelBg
                anchors.horizontalCenter: parent.horizontalCenter
                width: 60
                height: 40
                y: -100
                opacity: 0
                radius: 18
                color: Qt.alpha(root.theme.background, 0.8)
                border.width: 1
                border.color: root.theme.surface_bright
                clip: true
                transformOrigin: Item.Top

                states: [
                    State {
                        name: "open"
                        when: root.menuVisible
                        PropertyChanges {
                            target: panelBg
                            y: 6
                            width: buttonrow.implicitWidth + 40
                            height: 180
                            opacity: 1
                        }
                        PropertyChanges {
                            target: buttonrow
                            opacity: 1
                        }
                    },
                    State {
                        name: "closed"
                        when: !root.menuVisible
                        PropertyChanges {
                            target: panelBg
                            y: -100
                            width: 60
                            height: 40
                            opacity: 0
                        }
                        PropertyChanges {
                            target: buttonrow
                            opacity: 0
                        }
                    }
                ]

                transitions: [
                    Transition {
                        from: "closed"
                        to: "open"

                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation {
                                    target: panelBg
                                    property: "y"
                                    duration: 120
                                    easing.type: Easing.OutCirc
                                }
                                NumberAnimation {
                                    target: panelBg
                                    property: "opacity"
                                    duration: 100
                                }
                            }

                            ParallelAnimation {
                                NumberAnimation {
                                    target: panelBg
                                    property: "width"
                                    duration: 380
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.5
                                }
                                NumberAnimation {
                                    target: panelBg
                                    property: "height"
                                    duration: 380
                                    easing.type: Easing.OutBack
                                    easing.overshoot: 1.5
                                }
                                NumberAnimation {
                                    target: buttonrow
                                    property: "opacity"
                                    duration: 200
                                }
                            }
                        }
                    },
                    Transition {
                        from: "open"
                        to: "closed"

                        SequentialAnimation {
                            ParallelAnimation {
                                NumberAnimation {
                                    target: buttonrow
                                    property: "opacity"
                                    duration: 150
                                    easing.type: Easing.OutQuad
                                }
                                NumberAnimation {
                                    target: panelBg
                                    property: "width"
                                    duration: 240
                                    easing.type: Easing.InBack
                                    easing.overshoot: 1.2
                                }
                                NumberAnimation {
                                    target: panelBg
                                    property: "height"
                                    duration: 240
                                    easing.type: Easing.InBack
                                    easing.overshoot: 1.2
                                }
                            }

                            ParallelAnimation {
                                NumberAnimation {
                                    target: panelBg
                                    property: "y"
                                    duration: 180
                                    easing.type: Easing.InCirc
                                }
                                NumberAnimation {
                                    target: panelBg
                                    property: "opacity"
                                    duration: 180
                                }
                            }
                        }
                    }
                ]

                RowLayout {
                    id: buttonrow
                    anchors.centerIn: parent
                    spacing: 20
                    opacity: 0

                    Repeater {
                        model: root.actions

                        Rectangle {
                            id: buttons
                            required property var modelData
                            required property int index
                            width: 140; height: 140; radius: 18

                            readonly property bool isSelected: index === root.selectedIndex || hover.containsMouse

                            Behavior on scale {
                                NumberAnimation { duration: 180; easing.type: Easing.OutCirc }
                            }

                            border.color: isSelected ? root.theme.source_color : "transparent"
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
                                    sourceSize.width: hover.containsMouse || buttons.isSelected ? 65 : 50
                                    sourceSize.height: hover.containsMouse || buttons.isSelected ? 65 : 50
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
                                enabled: root.menuVisible
                                onClicked: {
                                    buttons.modelData.run()
                                    root.close()
                                }
                                onEntered: root.selectedIndex = buttons.index
                            }
                        }
                    }
                }
            }
        }
    }
}

