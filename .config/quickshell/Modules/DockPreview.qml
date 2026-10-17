pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Wayland
import qs
import qs.Components

// Window chooser for a dock app with several windows, styled as an M3 Expressive menu.
PanelWindow {
    id: win

    required property var dockRoot

    property bool isOpen: false
    property bool animatingClosed: false
    property Item targetAnchor: null
    property string targetAppKey: ""
    property string targetRawAppId: ""
    property string targetAppName: ""
    property string targetAppIcon: ""
    property var windows: []

    property real lastClosedAt: 0
    property string lastClosedKey: ""

    function getWsId(w) {
        if (!w || !w.workspace) return 9999
        const id = Number(w.workspace.id)
        if (isNaN(id)) return 9999
        return id > 0 ? id : 10000 + Math.abs(id)
    }

    function sortedWindows(wins) {
        if (!wins || wins.length <= 1) return wins ? wins.slice() : []
        const copy = wins.slice()
        copy.sort((a, b) => getWsId(a) - getWsId(b))
        return copy
    }

    function toggleFor(cell) {
        const now = Date.now()
        if ((isOpen && targetAppKey === cell.appKey) || (now - lastClosedAt < 300 && lastClosedKey === cell.appKey)) {
            close()
            return
        }
        targetAnchor = cell
        targetAppKey = cell.appKey
        targetRawAppId = cell.rawAppId
        targetAppName = cell.appName
        targetAppIcon = cell.iconSource
        windows = sortedWindows(cell.wins)
        reposition()
        isOpen = true
    }

    function close() {
        if (isOpen) {
            lastClosedAt = Date.now()
            lastClosedKey = targetAppKey
            isOpen = false
        }
    }

    function selectWindow(w) {
        close()
        dockRoot.focusToplevel(w)
    }

    function closeWindow(w) {
        if (!w) return
        dockRoot.closeToplevel(w)
        windows = sortedWindows(windows.filter(item => item !== w && item.address !== w.address))
        if (windows.length <= 1) {
            close()
        } else {
            reposition()
        }
    }

    function reposition() {
        if (!targetAnchor) return
        const p = targetAnchor.mapToItem(null, targetAnchor.width / 2, 0)
        const sw = win.screen ? win.screen.width : 1920
        margins.left = Math.max(8, Math.min(sw - implicitWidth - 8, Math.round(p.x - implicitWidth / 2)))
    }

    Connections {
        target: win.dockRoot
        function onItemsTickChanged() {
            if (!win.isOpen || win.targetAppKey === "")
                return
            const updated = win.dockRoot.windowsFor(win.targetAppKey)
            if (updated.length <= 1) {
                win.close()
            } else {
                win.windows = win.sortedWindows(updated)
                win.reposition()
            }
        }
    }

    WlrLayershell.namespace: "quickshell:dock_preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: isOpen || menu.opacity > 0
    exclusionMode: ExclusionMode.Ignore // position from the screen edge, not above the pinned dock's reserved space
    color: "transparent"
    anchors { bottom: true; left: true }
    margins.bottom: dockRoot.dockHeight + dockRoot.bottomMargin
    implicitWidth: menu.width + 32
    implicitHeight: menu.height + 24
    mask: Region { item: menu }

    HyprlandFocusGrab {
        windows: [win]
        active: win.visible && win.isOpen
        onCleared: win.close()
    }

    Item {
        anchors.fill: parent
        focus: win.isOpen
        Keys.onEscapePressed: win.close()
    }

    Elevation {
        anchors.fill: menu
        radius: menu.radius
        level: 2
        opacity: menu.opacity
        scale: menu.scale
        transformOrigin: Item.Bottom
    }

    // M3 Expressive menu: surface-container-low, 16px corners, 4px group padding
    Rectangle {
        id: menu
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        width: Math.max(280, Math.min(400, col.implicitWidth + 8))
        height: col.implicitHeight + 8
        radius: Motion.shapeLarge
        color: Colors.surface_container_low
        transformOrigin: Item.Bottom
        opacity: win.isOpen ? 1 : 0
        scale: win.isOpen ? 1 : 0.9
        Behavior on opacity { Fade { speed: "default" } }
        Behavior on scale { Spring { speed: "default" } }

        Column {
            id: col
            x: 4
            y: 4
            width: parent.width - 8
            spacing: 2

            // header
            RowLayout {
                width: parent.width
                height: 48
                spacing: 12
                Image {
                    Layout.leftMargin: 12
                    Layout.preferredWidth: 24
                    Layout.preferredHeight: 24
                    sourceSize: Qt.size(48, 48)
                    fillMode: Image.PreserveAspectFit
                    source: win.targetAppIcon
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "titleSmall"
                    elide: Text.ElideRight
                    text: win.targetAppName
                }
                StyledText {
                    Layout.rightMargin: 12
                    role: "labelMedium"
                    color: Colors.on_surface_variant
                    text: win.windows.length + " windows"
                }
            }

            Repeater {
                model: win.windows
                delegate: Clickable {
                    id: item
                    required property var modelData
                    required property int index
                    readonly property bool active: !!modelData && !!modelData.activated
                    readonly property bool lastItem: index === win.windows.length - 1
                    readonly property string wsLabel: {
                        if (!modelData || !modelData.workspace)
                            return "";
                        const n = String(modelData.workspace.name || modelData.workspace.id || "");
                        return n.startsWith("special:") ? "S" : n;
                    }

                    width: col.width
                    height: 48
                    // segmented-menu item shape; the focused window matches the dock's focused-app highlight (secondary container)
                    restRadius: active ? Motion.shapeMedium : Motion.shapeExtraSmall
                    bottomLeftRadius: lastItem && !active ? Motion.shapeMedium : radius
                    bottomRightRadius: bottomLeftRadius
                    color: active ? Colors.secondary_container : "transparent"
                    contentColor: active ? Colors.on_secondary_container : Colors.on_surface
                    acceptedButtons: Qt.LeftButton | Qt.MiddleButton
                    onClicked: mouse => mouse.button === Qt.MiddleButton ? win.closeWindow(modelData) : win.selectWindow(modelData)

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 4
                        spacing: 12

                        // workspace number
                        Rectangle {
                            visible: item.wsLabel !== ""
                            implicitWidth: Math.max(24, wsText.implicitWidth + 12)
                            implicitHeight: 24
                            radius: Motion.shapeSmall
                            color: item.active ? Colors.secondary : Colors.secondary_container
                            StyledText {
                                id: wsText
                                anchors.centerIn: parent
                                role: "labelMedium"
                                color: item.active ? Colors.on_secondary : Colors.on_secondary_container
                                text: item.wsLabel
                            }
                        }
                        Badge { visible: !!item.modelData && item.modelData.urgent }
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodyLarge"
                            color: item.contentColor
                            elide: Text.ElideRight
                            text: item.modelData ? (item.modelData.title || item.modelData.lastIpcObject?.title || win.targetAppName) : ""
                        }
                        IconButton {
                            size: "xs"
                            icon: "close"
                            opacity: item.hovered || hovered ? 1 : 0
                            Behavior on opacity { Fade {} }
                            onClicked: win.closeWindow(item.modelData)
                        }
                    }
                }
            }
        }
    }
}
