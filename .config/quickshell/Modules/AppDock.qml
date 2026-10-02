pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts

Scope {
    id: dockRoot

    property var theme
    property var settings

    property var activeWorkspace: Hyprland.workspaces.values.find(w => w.active)

    property int wsTick: 0

    ListModel {
        id: dockModel
    }

    property bool hasWindows: dockModel.count > 0

    function indexOfAddress(address) {
        for (let i = 0; i < dockModel.count; i++) {
            if (dockModel.get(i).address === address) return i
        }
        return -1
    }

    function getWorkspaceId(t) {
        if (!t || !t.workspace) return 9999
        const id = Number(t.workspace.id)
        if (isNaN(id)) return 9999
        return id > 0 ? id : 10000 + Math.abs(id)
    }

    function sortModelByWorkspace() {
        dockRoot.wsTick++
        if (dockModel.count <= 1) return

        let items = []
        for (let i = 0; i < dockModel.count; i++) {
            const item = dockModel.get(i)
            items.push({
                address: item.address,
                toplevelRef: item.toplevelRef,
                wsId: dockRoot.getWorkspaceId(item.toplevelRef),
                origIndex: i
            })
        }

        items.sort((a, b) => {
            if (a.wsId !== b.wsId) return a.wsId - b.wsId
            return a.origIndex - b.origIndex
        })

        let changed = false
        for (let i = 0; i < items.length; i++) {
            if (dockModel.get(i).address !== items[i].address) {
                changed = true
                break
            }
        }
        if (!changed) return

        for (let i = 0; i < items.length; i++) {
            const targetAddr = items[i].address
            const currentIdx = dockRoot.indexOfAddress(targetAddr)
            if (currentIdx !== i && currentIdx !== -1) {
                dockModel.move(currentIdx, i, 1)
            }
        }
    }

    function hasUnresolvedWorkspace() {
        for (let i = 0; i < dockModel.count; i++) {
            if (!dockModel.get(i).toplevelRef?.workspace) return true
        }
        return false
    }

    property int sortRetries: 0

    Timer {
        id: sortDebounce
        interval: 60
        onTriggered: {
            // openwindow can arrive before Quickshell has attached the new
            // toplevel's workspace. Reconcile again after that state settles.
            dockRoot.syncModel()
            dockRoot.sortModelByWorkspace()

            if (dockRoot.hasUnresolvedWorkspace() && dockRoot.sortRetries < 3) {
                dockRoot.sortRetries++
                Hyprland.refreshToplevels()
                sortDebounce.restart()
            } else {
                dockRoot.sortRetries = 0
            }
        }
    }

    property int startupSyncAttempts: 0

    Timer {
        id: startupSync
        interval: 200
        repeat: true
        onTriggered: {
            Hyprland.refreshToplevels()
            dockRoot.syncModel()
            dockRoot.startupSyncAttempts++
            if (dockRoot.hasWindows || dockRoot.startupSyncAttempts >= 10)
                stop()
        }
    }

    function syncModel() {
        const live = Hyprland.toplevels.values.filter(t => {
            const workspaceId = Number(t.workspace?.id)
            const workspaceName = String(t.workspace?.name ?? "")
            return (workspaceId >= 1 && workspaceId <= 8)
                || workspaceName.startsWith("special:")
        })
        const liveAddrs = new Set(live.map(t => t.address))

        for (let i = dockModel.count - 1; i >= 0; i--) {
            if (!liveAddrs.has(dockModel.get(i).address)) {
                dockModel.remove(i)
            }
        }

        let added = false
        for (const t of live) {
            if (dockRoot.indexOfAddress(t.address) === -1) {
                dockModel.append({ address: t.address, toplevelRef: t })
                t.workspaceChanged.connect(() => sortDebounce.restart())
                added = true
            }
        }

        dockRoot.sortModelByWorkspace()
        if (added) sortDebounce.restart()
    }

    Connections {
        target: Hyprland.toplevels
        function onObjectInsertedPost() { dockRoot.syncModel() }
        function onObjectRemovedPost() { dockRoot.syncModel() }
    }

    Connections {
        target: Hyprland
        function onRawEvent(event) {
            if (event.name === "openwindow"
                    || event.name.startsWith("movewindow")
                    || event.name.startsWith("movetoworkspace")) {
                // debounced: at event time Quickshell's copy of the window's
                // workspace may not have caught up yet
                sortDebounce.restart()
            }
        }
    }

    Component.onCompleted: {
        dockRoot.syncModel()
        startupSync.start()
    }

    function normalizeAddress(addr) {
        return addr.startsWith("0x") ? addr : "0x" + addr
    }

    property real dockHeight: 56
    property real bottomMargin: 6
    property real pillZone: 8      
    property real hoverHeadroom: 64  
    property bool expanded: true

    PanelWindow {
        id: realDock
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"

        implicitHeight: dockRoot.dockHeight + dockRoot.bottomMargin + dockRoot.hoverHeadroom

        exclusiveZone: dockRoot.expanded
            ? dockRoot.dockHeight
            : dockRoot.pillZone
        
        Behavior on exclusiveZone {
            NumberAnimation { duration: 100; easing.type: Easing.OutCirc }
        }

        color: "transparent"

        anchors {
            bottom: true
            left: true
            right: true
        }

        mask: Region {
            item: pillArea
            Region { item: dockRect }
        }

        Item {
            id: pillArea
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: parent.bottom
            width: 160
            height: dockRoot.pillZone

            TapHandler {
                onTapped: dockRoot.expanded = !dockRoot.expanded
            }

            Rectangle {
                id: gestureBar
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 6
                width: 120
                height: 4
                radius: 2
                color: dockRoot.theme.background
                opacity: dockRoot.expanded || !dockRoot.hasWindows ? 0.25 : 0.6

                Behavior on opacity {
                    NumberAnimation { duration: 150 }
                }
            }
        }

            IpcHandler {
                target: "dock"
                function toggle(): void {
                    dockRoot.expanded = !dockRoot.expanded;
                }
            }

        Rectangle {
            id: dockRect
            visible: dockRoot.hasWindows
            anchors.horizontalCenter: parent.horizontalCenter
            color: "transparent"
            radius: 18

            y: dockRoot.expanded ? dockRoot.hoverHeadroom : realDock.height

            Behavior on y {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.2
                }
            }

            property real maxWidth: 1900
            width: Math.min(list.contentWidth + 32, maxWidth)
            height: dockRoot.dockHeight

            Behavior on width {
                NumberAnimation { duration: 150; easing.type: Easing.OutCubic }
            }

            Rectangle {
                id: background
                anchors.fill: parent
                antialiasing: true
                color: Qt.alpha(dockRoot.theme.background, 1)
                radius: 25
                border.width: 1
                border.color: dockRoot.theme.outline_variant
            }

            ListView {
                id: list
                anchors.centerIn: parent
                width: Math.min(contentWidth, parent.maxWidth - 32)
                height: dockRoot.dockHeight
                orientation: ListView.Horizontal
                spacing: 14
                interactive: contentWidth > width
                clip: false
                boundsBehavior: Flickable.StopAtBounds
                model: dockModel

                add: Transition {
                    NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: 180 }
                    NumberAnimation { properties: "scale"; from: 0.4; to: 1; duration: 180; easing.type: Easing.OutBack }
                }
                remove: Transition {
                    NumberAnimation { properties: "opacity"; to: 0; duration: 150 }
                    NumberAnimation { properties: "scale"; to: 0.4; duration: 150 }
                }
                
                move: Transition {
                    NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: 120 }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 180; easing.type: Easing.OutCubic }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: 120 }
                }

                delegate: Item {
                    id: cell
                    required property var toplevelRef
                    required property string address
                    required property int index

                    width: 40
                    height: dockRoot.dockHeight

                    property bool ghost: {
                        dockRoot.wsTick   // re-evaluate after every sort pass
                        if (cell.toplevelRef.activated) return false
                        const ws = cell.toplevelRef.workspace
                        const active = dockRoot.activeWorkspace
                        if (!ws || !active) return false
                        return ws.id !== active.id
                    }

                    // hovered item draws above its neighbors
                    z: iconHover.hovered ? 1 : 0

                    Rectangle {
                        id: rect
                        anchors.verticalCenter: parent.verticalCenter
                        width: 40
                        height: 40
                        radius: 16
                        color: "transparent"

                        transformOrigin: Item.Bottom
                        scale: iconHover.hovered ? 1.35 : 1
                        opacity: cell.ghost && !iconHover.hovered ? 0.5 : 1.0

                        Behavior on scale {
                            NumberAnimation { duration: 120; easing.type: Easing.OutCirc }
                        }
                        Behavior on opacity {
                            NumberAnimation { duration: 150 }
                        }

                        SequentialAnimation {
                            running: cell.toplevelRef.urgent
                            loops: Animation.Infinite
                            NumberAnimation { target: rect; property: "scale"; to: 1.15; duration: 400; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: rect; property: "scale"; to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
                        }

                        HoverHandler { id: iconHover }

                        Image {
                            id: appicon
                            anchors.centerIn: parent
                            width: 40
                            height: 40
                            sourceSize: iconHover.hovered
                                ? Qt.size(80 * Screen.devicePixelRatio, 80 * Screen.devicePixelRatio)
                                : Qt.size(48 * Screen.devicePixelRatio, 48 * Screen.devicePixelRatio)
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            antialiasing: true
                            source: {
                                const appId = cell.toplevelRef.wayland?.appId ?? ""
                                const entry = DesktopEntries.heuristicLookup(appId)
                                return entry ? Quickshell.iconPath(entry.icon) : ""
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appicon.status !== Image.Ready
                            text: (cell.toplevelRef.wayland?.appId ?? cell.toplevelRef.title ?? "?").slice(0, 3)
                            color: "white"
                            font.pixelSize: dockRoot.settings.fontsize
                        }

                        Rectangle {
                            id: focusDot
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.bottomMargin: -5

                            width: cell.toplevelRef.activated ? 16 : 4
                            height: 3
                            radius: 2
                            color: cell.toplevelRef.activated ? dockRoot.theme.primary : shell.ghost ? dockRoot.theme.outline_variant : dockRoot.theme.on_background
                            opacity: cell.toplevelRef.activated ? 1.0 : 0.5

                            Behavior on width { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }

                        // left click focuses (switching workspace first for ghost
                        // icons), middle click closes
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: {
                                if (cell.ghost && cell.toplevelRef.workspace) {
                                    cell.toplevelRef.workspace.activate()
                                }
                                cell.toplevelRef.wayland?.activate()
                            }
                        }

                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + dockRoot.normalizeAddress(cell.address) + '" })')
                        }
                    }

                    Rectangle {
                        id: tooltip
                        visible: opacity > 0
                        opacity: iconHover.hovered ? 1 : 0
                        anchors.bottom: cell.top
                        anchors.bottomMargin: 10
                        anchors.horizontalCenter: cell.horizontalCenter
                        radius: 8
                        color: dockRoot.theme.background
                        border.width: 1
                        border.color: dockRoot.theme.outline_variant
                        width: Math.min(tooltipText.implicitWidth + 24, 380)
                        height: tooltipText.implicitHeight + 12

                        Behavior on opacity { NumberAnimation { duration: 120 } }

                        Text {
                            id: tooltipText
                            anchors.centerIn: parent
                            text: cell.toplevelRef.title ?? ""
                            color: "white"
                            font.family: dockRoot.settings.fontdefault
                            font.pixelSize: 13
                            font.weight: Font.Medium
                            elide: Text.ElideRight
                            width: Math.min(implicitWidth, 380 - 24)
                        }
                    }
                }
            }
        }
    }
}
