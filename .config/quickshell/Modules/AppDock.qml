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
    property int itemsTick: 0      // bumped after the window model is (re)sorted, so the grouped list rebuilds

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
            dockRoot.itemsTick++

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
        dockRoot.itemsTick++
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

    // Bumped whenever the desktop-entry database changes underneath us.
    // cell.entry below only reads rawAppId/isSep, so without this, a
    // heuristicLookup() that happens to land during a filesystem rescan
    // (package update, icon-cache rebuild, etc.) and comes back null has
    // nothing to ever trigger a re-check -- the fallback icon sticks
    // permanently until that window closes and reopens. Reading this tick
    // inside cell.entry's binding gives a bad lookup a real chance to
    // self-correct the next time the index changes.
    property int desktopEntriesTick: 0

    Connections {
        target: DesktopEntries.applications
        function onObjectInsertedPost() { dockRoot.desktopEntriesTick++ }
        function onObjectRemovedPost() { dockRoot.desktopEntriesTick++ }
    }

    function normalizeAddress(addr) {
        return addr.startsWith("0x") ? addr : "0x" + addr
    }

    // ------------------------------------------------------------------ pinned apps
    //
    // Dock layout, like macOS:   [ pinned apps ] | [ open windows ] | [ special workspace ]
    //   - pinned: one icon per app, always there, stable order (right-click any icon to pin / unpin)
    //   - open windows: every window of an app that isn't pinned, sorted by workspace as before
    //   - special workspace: windows living in special:* workspaces
    // A separator is only drawn between two groups that both have something in them.
    //
    // Pins are saved as [{ id: "firefox", raw: "firefox" }]: `id` is the lower-cased window class
    // used for matching windows, `raw` is the original class used for icon lookup and launching.

    property var pinned: []

    function appKey(t) {
        return String(t?.wayland?.appId ?? "").toLowerCase()
    }

    function isSpecial(t) {
        return String(t?.workspace?.name ?? "").startsWith("special:")
    }

    function isPinned(id) {
        return dockRoot.pinned.some(p => p.id === id)
    }

    function pin(id, raw) {
        if (!id || dockRoot.isPinned(id)) return
        dockRoot.pinned = dockRoot.pinned.concat([{ id: id, raw: raw || id }])
        dockRoot.savePins()
    }

    function unpin(id) {
        dockRoot.pinned = dockRoot.pinned.filter(p => p.id !== id)
        dockRoot.savePins()
    }

    function savePins() {
        savePinsProc.payload = JSON.stringify(dockRoot.pinned)
        savePinsProc.running = false
        savePinsProc.running = true
    }

    // $XDG_STATE_HOME/quickshell/dock-pinned.json (falls back to ~/.local/state/quickshell/).
    // Plain Processes on purpose: writing next to your shell files could trigger a hot reload.
    Process {
        id: loadPinsProc
        running: true
        command: ["sh", "-c", "cat \"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell/dock-pinned.json\" 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const arr = JSON.parse(text)
                    if (Array.isArray(arr))
                        dockRoot.pinned = arr.filter(p => p && typeof p.id === "string" && p.id.length > 0)
                } catch (e) {
                    // no file yet (first run) or unreadable: start with no pins
                }
            }
        }
    }

    Process {
        id: savePinsProc
        property string payload: "[]"
        command: ["sh", "-c", "d=\"${XDG_STATE_HOME:-$HOME/.local/state}/quickshell\"; mkdir -p \"$d\" && printf %s \"$1\" > \"$d/dock-pinned.json\"", "sh", payload]
    }

    // all non-special windows of an app (used by pinned icons)
    function windowsFor(id) {
        dockRoot.itemsTick
        dockRoot.wsTick
        const out = []
        for (let i = 0; i < dockModel.count; i++) {
            const t = dockModel.get(i).toplevelRef
            if (t && !dockRoot.isSpecial(t) && dockRoot.appKey(t) === id)
                out.push(t)
        }
        return out
    }

    function buildItems() {
        dockRoot.itemsTick
        dockRoot.wsTick
        const pins = dockRoot.pinned
        const pinIds = new Set(pins.map(p => p.id))

        const left = pins.map(p => ({ key: "pin:" + p.id, kind: "pin", id: p.id, raw: p.raw }))
        const middle = []
        const right = []

        for (let i = 0; i < dockModel.count; i++) {
            const t = dockModel.get(i).toplevelRef
            if (!t) continue
            if (dockRoot.isSpecial(t))
                right.push({ key: "win:" + t.address, kind: "win", toplevel: t })
            else if (!pinIds.has(dockRoot.appKey(t)))
                middle.push({ key: "win:" + t.address, kind: "win", toplevel: t })
        }

        const out = left.slice()
        if (left.length > 0 && middle.length > 0)
            out.push({ key: "sep:1", kind: "sep" })
        for (const m of middle) out.push(m)
        if ((left.length > 0 || middle.length > 0) && right.length > 0)
            out.push({ key: "sep:2", kind: "sep" })
        for (const r of right) out.push(r)
        return out
    }

    readonly property var items: {
        dockRoot.itemsTick
        dockRoot.wsTick
        dockRoot.pinned
        return dockRoot.buildItems()
    }

    property bool hasContent: dockRoot.items.length > 0

    // ---- actions
    function focusToplevel(t) {
        if (!t) return
        const active = dockRoot.activeWorkspace
        if (t.workspace && active && t.workspace.id !== active.id)
            t.workspace.activate()
        t.wayland?.activate()
    }

    // clicking a pinned app that's already focused cycles through its windows
    function targetFor(wins) {
        if (wins.length === 0) return null
        const ai = wins.findIndex(w => w.activated)
        if (ai !== -1) return wins[(ai + 1) % wins.length]
        const active = dockRoot.activeWorkspace
        const here = active ? wins.find(w => w.workspace && w.workspace.id === active.id) : null
        return here ?? wins[0]
    }

    function closeToplevel(t) {
        if (!t) return
        Hyprland.dispatch('hl.dsp.window.close({ window = "address:' + dockRoot.normalizeAddress(t.address) + '" })')
    }

    function launchApp(raw) {
        if (!raw) return
        const e = DesktopEntries.heuristicLookup(raw)
        if (e) e.execute()
        else Quickshell.execDetached([raw])
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
            Region { item: dockInputArea }
        }

        Item {
            id: dockInputArea
            anchors.horizontalCenter: dockRect.horizontalCenter
            anchors.bottom: dockRect.bottom
            width: dockRect.width
            height: dockRect.height
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
                opacity: dockRoot.expanded || !dockRoot.hasContent ? 0.25 : 0.6

                Behavior on opacity {
                    NumberAnimation {
                        duration: 120
                        easing.type: dockRoot.expanded ? Easing.OutCirc : Easing.InCirc
                    }
                }
            }
        }

            IpcHandler {
                target: "dock"
                function toggle(): void {
                    dockRoot.expanded = !dockRoot.expanded;
                }
                function pin(appId: string): void {
                    dockRoot.pin(appId.toLowerCase(), appId);
                }
                function unpin(appId: string): void {
                    dockRoot.unpin(appId.toLowerCase());
                }
            }

        Rectangle {
            id: dockRect
            visible: dockRoot.hasContent
            anchors.horizontalCenter: parent.horizontalCenter
            color: "transparent"
            radius: 18

            y: dockRoot.expanded ? dockRoot.hoverHeadroom : realDock.height

            Behavior on y {
                NumberAnimation {
                    duration: dockRoot.expanded ? 240 : 160
                    easing.type: dockRoot.expanded ? Easing.OutBack : Easing.InCirc
                    easing.overshoot: dockRoot.expanded ? 1.1 : 1.0
                }
            }

            property real maxWidth: 1900
            width: Math.min(list.contentWidth + 32, maxWidth)
            height: dockRoot.dockHeight

            Behavior on width {
                NumberAnimation { duration: 120; easing.type: Easing.OutCirc }
            }

            HoverHandler {
                id: dockHover
                cursorShape: Qt.ArrowCursor
            }

            Rectangle {
                id: background
                anchors.fill: parent
                antialiasing: true
                color: Qt.alpha(dockRoot.theme.background, 1)
                radius: 22
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
                model: ScriptModel {
                    values: dockRoot.items
                    objectProp: "key"
                }

                add: Transition {
                    NumberAnimation { properties: "opacity"; from: 0; to: 1; duration: 160; easing.type: Easing.OutQuad }
                    NumberAnimation { properties: "scale"; from: 0.5; to: 1; duration: 220; easing.type: Easing.OutBack; easing.overshoot: 1.15 }
                }
                remove: Transition {
                    NumberAnimation { properties: "opacity"; to: 0; duration: 100; easing.type: Easing.InCirc }
                    NumberAnimation { properties: "scale"; to: 0.4; duration: 100; easing.type: Easing.InCirc }
                }
                
                move: Transition {
                    NumberAnimation { properties: "x,y"; duration: 120; easing.type: Easing.OutCirc }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: 90; easing.type: Easing.OutCirc }
                }
                displaced: Transition {
                    NumberAnimation { properties: "x,y"; duration: 120; easing.type: Easing.OutCirc }
                    NumberAnimation { properties: "opacity,scale"; to: 1; duration: 90; easing.type: Easing.OutCirc }
                }

                delegate: Item {
                    id: cell
                    required property var modelData
                    required property int index

                    readonly property bool isSep: cell.modelData.kind === "sep"
                    readonly property bool isPin: cell.modelData.kind === "pin"
                    readonly property var tl: cell.modelData.kind === "win" ? cell.modelData.toplevel : null

                    readonly property string rawAppId: cell.isPin ? String(cell.modelData.raw) : String(cell.tl?.wayland?.appId ?? "")
                    readonly property string appKey: cell.isPin ? cell.modelData.id : cell.rawAppId.toLowerCase()
                    readonly property var entry: {
                        dockRoot.desktopEntriesTick   // re-evaluate whenever the desktop-entry index changes
                        return (cell.isSep || cell.rawAppId === "") ? null : DesktopEntries.heuristicLookup(cell.rawAppId)
                    }

                    // the windows this icon stands for: one for a window icon, all of the app's for a pinned icon
                    readonly property var wins: cell.isPin ? dockRoot.windowsFor(cell.appKey) : (cell.tl ? [cell.tl] : [])
                    readonly property bool running: cell.wins.length > 0
                    readonly property bool activated: cell.wins.some(w => w.activated)
                    readonly property bool urgent: cell.wins.some(w => w.urgent)
                    readonly property bool canPin: !cell.isSep && !cell.isPin && cell.rawAppId !== "" && !dockRoot.isSpecial(cell.tl)

                    readonly property string title: {
                        if (cell.isPin) {
                            const name = cell.entry?.name ?? cell.rawAppId
                            return cell.wins.length > 1 ? name + "  \u00b7  " + cell.wins.length + " windows" : name
                        }
                        return cell.tl?.title ?? ""
                    }
                    readonly property string hint: cell.isPin ? "Right-click to unpin" : (cell.canPin ? "Right-click to pin" : "")

                    width: cell.isSep ? 8 : 48
                    height: dockRoot.dockHeight

                    property bool ghost: {
                        dockRoot.wsTick   // re-evaluate after every sort pass
                        if (!cell.running || cell.activated) return false
                        const active = dockRoot.activeWorkspace
                        if (!active) return false
                        return cell.wins.every(w => w.workspace && w.workspace.id !== active.id)
                    }

                    // Gentle, stationary magnification wave (no horizontal movement)
                    readonly property real cellCenterX: cell.x - list.contentX + cell.width / 2
                    readonly property real mouseXInList: dockHover.point.position.x - list.x
                    readonly property real dist: cellCenterX - mouseXInList
                    readonly property real influenceRange: 75
                    readonly property real ratio: Math.max(-1, Math.min(1, dist / influenceRange))

                    readonly property real factor: (!cell.isSep && dockHover.hovered && Math.abs(dist) < influenceRange)
                        ? 0.5 * (1.0 + Math.cos(ratio * Math.PI))
                        : 0.0

                    readonly property real maxScale: 1.25
                    readonly property real targetScale: cell.isSep ? 1.0 : (1.0 + (maxScale - 1.0) * factor)

                    property real currentScale: targetScale

                    Behavior on currentScale {
                        NumberAnimation {
                            duration: dockHover.hovered ? 60 : 100
                            easing.type: dockHover.hovered ? Easing.OutCirc : Easing.InCirc
                        }
                    }

                    property real urgentBounce: 1.0
                    SequentialAnimation on urgentBounce {
                        running: cell.urgent
                        loops: Animation.Infinite
                        NumberAnimation { to: 1.15; duration: 400; easing.type: Easing.InOutQuad }
                        NumberAnimation { to: 1.0; duration: 400; easing.type: Easing.InOutQuad }
                    }

                    // Hovered or slightly elevated item draws above neighbors
                    z: iconHover.hovered ? 200 : Math.round(currentScale * 100)

                    // group separator
                    Rectangle {
                        visible: cell.isSep
                        anchors.centerIn: parent
                        width: 4
                        height: 32
                        radius: 2
                        color: Qt.alpha(dockRoot.theme.on_surface_variant, 0.48)
                    }

                    Rectangle {
                        id: rect
                        visible: !cell.isSep
                        anchors.centerIn: parent
                        width: 48
                        height: 48
                        radius: 24
                        color: "transparent"

                        transformOrigin: Item.Bottom
                        scale: cell.currentScale * cell.urgentBounce
                        opacity: cell.ghost && !iconHover.hovered ? 0.6 : 1.0

                        Behavior on opacity {
                            NumberAnimation { duration: 150; easing.type: Easing.OutCirc }
                        }

                        HoverHandler { id: iconHover }

                        // Elegant M3 active/running indicators
                        Rectangle {
                            id: activePill
                            anchors.centerIn: parent
                            // M3 active indicator pill (wide) vs subtle running indicator at bottom
                            width: cell.activated ? 56 : (cell.running ? 16 : 0)
                            height: cell.activated ? 44 : (cell.running ? 4 : 0)
                            radius: cell.activated ? 22 : 2
                            
                            anchors.verticalCenterOffset: cell.activated ? 0 : 26
                            
                            color: cell.activated ? dockRoot.theme.secondary_container : dockRoot.theme.on_surface_variant
                            opacity: cell.activated ? 1.0 : (cell.running ? 0.8 : 0.0)
                            z: -1 // Behind the app icon
                            
                            Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on height { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on radius { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on anchors.verticalCenterOffset { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutQuint } }
                            Behavior on color { ColorAnimation { duration: 250 } }
                        }

                        Image {
                            id: appicon
                            anchors.centerIn: parent
                            width: 36 // Slightly scaled down inside the 48x48 rect for better margins
                            height: 36
                            sourceSize: cell.currentScale > 1.05
                                ? Qt.size(64 * Screen.devicePixelRatio, 64 * Screen.devicePixelRatio)
                                : Qt.size(48 * Screen.devicePixelRatio, 48 * Screen.devicePixelRatio)
                            smooth: true
                            fillMode: Image.PreserveAspectFit
                            antialiasing: true
                            source: cell.entry ? Quickshell.iconPath(cell.entry.icon) : "../assets/app-window-fill.svg"
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: appicon.status !== Image.Ready || !cell.entry 
                            text: (cell.rawAppId !== "" ? cell.rawAppId : (cell.tl?.title ?? "?")).slice(0, 3)
                            topPadding: 8
                            color: dockRoot.theme.on_surface
                            font.pixelSize: dockRoot.settings.fontsize
                            font.bold: true
                            font.family: dockRoot.settings.fontdefault
                            opacity: iconHover.hovered ? 0.6 : 1
                        }

                        // left click: focus (switching workspace first if needed) or launch a closed pinned app
                        TapHandler {
                            acceptedButtons: Qt.LeftButton
                            onTapped: {
                                if (cell.isPin) {
                                    if (cell.running) dockRoot.focusToplevel(dockRoot.targetFor(cell.wins))
                                    else dockRoot.launchApp(cell.rawAppId)
                                } else {
                                    dockRoot.focusToplevel(cell.tl)
                                }
                            }
                        }

                        // middle click: close
                        TapHandler {
                            acceptedButtons: Qt.MiddleButton
                            onTapped: {
                                const t = cell.isPin ? (cell.wins.find(w => w.activated) ?? cell.wins[0]) : cell.tl
                                dockRoot.closeToplevel(t)
                            }
                        }

                        // right click: pin / unpin
                        TapHandler {
                            acceptedButtons: Qt.RightButton
                            onTapped: {
                                if (cell.isPin)
                                    dockRoot.unpin(cell.appKey)
                                else if (cell.canPin)
                                    dockRoot.pin(cell.appKey, cell.rawAppId)
                            }
                        }
                    }

                    Rectangle {
                        id: tooltip
                        visible: opacity > 0
                        opacity: iconHover.hovered && !cell.isSep ? 1 : 0
                        anchors.bottom: cell.top
                        anchors.bottomMargin: 10 + Math.max(0, 40 * (cell.currentScale - 1.0) - 8)
                        anchors.horizontalCenter: cell.horizontalCenter
                        radius: 8
                        color: Qt.lighter(dockRoot.theme.background, 1.3)
                        border.width: 0
                        border.color: dockRoot.theme.outline_variant
                        width: Math.min(Math.max(tooltipText.implicitWidth, hintText.implicitWidth) + 24, 380)
                        height: tipCol.implicitHeight + 12

                        Behavior on opacity {
                            NumberAnimation {
                                duration: 90
                                easing.type: iconHover.hovered ? Easing.OutCirc : Easing.InCirc
                            }
                        }

                        Column {
                            id: tipCol
                            anchors.centerIn: parent
                            spacing: 2

                            Text {
                                id: tooltipText
                                anchors.horizontalCenter: parent.horizontalCenter
                                text: cell.title
                                color: "white"
                                font.family: dockRoot.settings.fontdefault
                                font.pixelSize: 13
                                font.weight: Font.Bold
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 380 - 24)
                            }
                            Text {
                                id: hintText
                                anchors.horizontalCenter: parent.horizontalCenter
                                visible: false
                                text: cell.hint
                                color: "white"
                                opacity: 0.55
                                font.family: dockRoot.settings.fontdefault
                                font.pixelSize: 11
                            }
                        }
                    }
                }
            }
        }
    }
}
