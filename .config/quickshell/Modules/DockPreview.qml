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

    // ---- entrance: the header and then each row pop in, one after another ----
    property int stage: 0
    property real spin: 0
    onVisibleChanged: if (!visible) { stage = 0; _winW = _targetW; _winH = _targetH; }
    onIsOpenChanged: {
        if (isOpen) {
            stage = 0;
            stageTimer.restart();
        }
    }
    Timer {
        id: stageTimer
        interval: 45
        repeat: true
        onTriggered: {
            win.stage += 1;
            if (win.stage >= win.windows.length + 2)
                stop();
        }
    }
    FrameAnimation {
        running: win.isOpen
        onTriggered: win.spin = (win.spin + frameTime * 12) % 360
    }

    readonly property var wsKanji: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五"]

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
    // the window is sized to where the menu is going and never shrinks while it is up: resizing a layer
    // surface on every frame of the menu's spring would make the whole thing shake
    readonly property real _targetW: Math.max(300, Math.min(420, col.implicitWidth + 16))
    readonly property real _targetH: col.implicitHeight + 16
    property real _winW: _targetW
    property real _winH: _targetH
    on_TargetWChanged: if (_targetW > _winW || !visible) _winW = _targetW
    on_TargetHChanged: if (_targetH > _winH || !visible) _winH = _targetH
    implicitWidth: _winW + 32
    implicitHeight: _winH + 24
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
        transform: Translate { y: (1 - menu.openP) * 24 }
    }

    // M3 Expressive menu: surface-container-low, 28px corners, 8px group padding; it springs up out of
    // the dock icon, then its rows follow
    Rectangle {
        id: menu
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 4
        property real _w: win._targetW
        property real _h: win._targetH
        // the first size (while it is hidden) is taken as it is; after that it springs
        Behavior on _w { enabled: win.isOpen; Spring { speed: "default" } }
        Behavior on _h { enabled: win.isOpen; Spring { speed: "default" } }
        width: Math.max(0, _w)
        height: Math.max(0, _h)
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_low
        transformOrigin: Item.Bottom
        property real openP: win.isOpen ? 1 : 0
        Behavior on openP { Spring { speed: "default" } }
        opacity: win.isOpen ? 1 : 0
        scale: 0.6 + 0.4 * openP
        transform: Translate { y: (1 - menu.openP) * 24 }
        Behavior on opacity { Fade { speed: "default" } }

        Column {
            id: col
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 2

            // header: the app in a turning shape, its name, and a rolling window count
            RowLayout {
                id: headerRow
                width: parent.width
                height: 60
                spacing: 12
                property real appear: win.stage >= 1 ? 1 : 0
                Behavior on appear { Spring {} }
                opacity: Math.max(0, Math.min(1, appear * 1.6))
                transform: Translate { y: (1 - headerRow.appear) * 14 }

                Item {
                    Layout.leftMargin: 6
                    Layout.preferredWidth: 44
                    Layout.preferredHeight: 44
                    scale: 0.5 + 0.5 * headerRow.appear
                    MorphShape {
                        anchors.fill: parent
                        shape: "cookie9"
                        fromShape: "cookie9"
                        spin: win.spin
                        color: Colors.primary_container
                    }
                    Image {
                        anchors.centerIn: parent
                        width: 26
                        height: 26
                        sourceSize: Qt.size(52, 52)
                        fillMode: Image.PreserveAspectFit
                        source: win.targetAppIcon
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "titleMedium"
                    emphasized: true
                    elide: Text.ElideRight
                    text: win.targetAppName
                }
                Rectangle {
                    Layout.rightMargin: 6
                    implicitHeight: 30
                    implicitWidth: countRow.implicitWidth + 24
                    radius: height / 2
                    color: Colors.secondary_container
                    Row {
                        id: countRow
                        anchors.centerIn: parent
                        spacing: 5
                        RollingDigits {
                            anchors.verticalCenter: parent.verticalCenter
                            pixelSize: 15
                            color: Colors.on_secondary_container
                            text: String(win.windows.length)
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "labelMedium"
                            color: Colors.on_secondary_container
                            text: win.windows.length === 1 ? "window" : "windows"
                        }
                    }
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
                        if (n.startsWith("special:")) return "S";
                        return win.wsKanji[Number(n) - 1] || n;
                    }

                    width: col.width
                    height: 48
                    property real appear: win.stage >= index + 2 ? 1 : 0
                    Behavior on appear { Spring {} }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    scale: 0.92 + 0.08 * appear
                    transform: Translate { y: (1 - item.appear) * 14 }
                    // segmented-menu item shape; the focused window matches the dock's focused-app highlight (secondary container)
                    restRadius: active ? Motion.shapeMedium : Motion.shapeExtraSmall
                    property real _bl: lastItem && !active ? Motion.shapeMedium : radius
                    Behavior on _bl { Spring {} }
                    bottomLeftRadius: Math.max(0, _bl)
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

                        // workspace number, as kanji
                        Item {
                            opacity: item.wsLabel !== "" ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            implicitWidth: 32
                            implicitHeight: 32
                            Text {
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                text: item.wsLabel
                                font.family: Typography.familyJp
                                font.pixelSize: item.wsLabel.length > 1 ? 11 : 15
                                font.weight: Font.Bold
                                color: item.active ? Colors.on_secondary_container : Colors.on_surface
                                Behavior on color { ColorFade {} }
                            }
                        }
                        Badge {
                            opacity: !!item.modelData && item.modelData.urgent ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                        }
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
