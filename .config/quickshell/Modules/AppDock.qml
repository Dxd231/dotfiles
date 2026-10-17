pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components

// Dock as an M3 Expressive floating toolbar with the launcher as its paired filled button.
// Layout: [launcher] [pinned apps] [other open apps] [special-workspace windows].
// Left click focuses/cycles/launches, middle click closes, right click pins/unpins.
Scope {
    id: dockRoot

    property var launcher: null

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
        const live = Hyprland.toplevels.values.filter(t => dockRoot.isGenuineWindow(t))
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
                if (t.workspaceChanged) t.workspaceChanged.connect(() => sortDebounce.restart())
                if (t.titleChanged) t.titleChanged.connect(() => sortDebounce.restart())
                if (t.lastIpcObjectChanged) t.lastIpcObjectChanged.connect(() => sortDebounce.restart())
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
                    || event.name === "closewindow"
                    || event.name.startsWith("windowtitle")
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
    property var gameLauncherMap: ({})

    Process {
        id: loadGameMapProc
        running: true
        command: ["python3", Qt.resolvedUrl("../scripts/scan_games.py").toString().replace(/^file:\/\//, "")]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    const obj = JSON.parse(text)
                    if (obj && typeof obj === "object") {
                        dockRoot.gameLauncherMap = obj
                        dockRoot.desktopEntriesTick++
                    }
                } catch (e) {}
            }
        }
    }

    // A desktop-entry rescan emits one signal per entry; coalesce them into a single
    // index bump and a single game-map rescan.
    Timer {
        id: entriesChanged
        interval: 1500
        onTriggered: {
            dockRoot.desktopEntriesTick++
            loadGameMapProc.running = false
            loadGameMapProc.running = true
        }
    }
    Connections {
        target: DesktopEntries.applications
        function onObjectInsertedPost() { entriesChanged.restart() }
        function onObjectRemovedPost() { entriesChanged.restart() }
    }

    function normalizeAddress(addr) {
        return addr.startsWith("0x") ? addr : "0x" + addr
    }

    // Desktop-entry matching and icon resolution scan every desktop entry and run from many
    // bindings per window, so results are memoized until the entry index changes. The store
    // is mutated in place (never reassigned) so reading it creates no binding dependencies.
    readonly property var _memo: ({ tick: -1, size: 0, map: {} })
    function memo(kind, key, compute) {
        const m = dockRoot._memo
        if (m.tick !== dockRoot.desktopEntriesTick || m.size > 2000) {
            m.map = {}
            m.size = 0
            m.tick = dockRoot.desktopEntriesTick
        }
        const k = kind + "\u0001" + key
        if (k in m.map) return m.map[k]
        const v = compute()
        m.map[k] = v
        m.size++
        return v
    }

    function windowTitleOf(t) {
        return t ? String(t.title || t.lastIpcObject?.title || t.lastIpcObject?.initialTitle || "") : ""
    }

    function matchDesktopEntry(rawAppId, windowTitle, t) {
        const title = windowTitle || dockRoot.windowTitleOf(t)
        return dockRoot.memo("de", String(rawAppId || "") + "\u0001" + title, () => dockRoot._matchDesktopEntry(rawAppId, title, t))
    }

    function _matchDesktopEntry(rawAppId, windowTitle, t) {
        if (!rawAppId && !windowTitle) return null

        const raw = String(rawAppId || "").trim()
        const rawLower = raw.toLowerCase()
        const cleanRaw = raw.replace(/\.(exe|bin|x86_64|x86|x64|elf)$/i, "").trim()
        const cleanRawLower = cleanRaw.toLowerCase()
        const wTitle = String(windowTitle || (t ? (t.title || t.lastIpcObject?.title || t.lastIpcObject?.initialTitle) : "") || "").trim()

        // 1. Check pre-scanned gameLauncherMap (Lutris games, Steam manifests, custom .exe desktop files)
        const map = dockRoot.gameLauncherMap || {}
        const mapped = map[rawLower] || map[cleanRawLower + ".exe"] || map[cleanRawLower] || (wTitle ? map[wTitle.toLowerCase()] : null)
        if (mapped && mapped.desktopId) {
            const de = DesktopEntries.byId(mapped.desktopId) ?? DesktopEntries.byId(mapped.desktopId + ".desktop") ?? DesktopEntries.heuristicLookup(mapped.desktopId)
            if (de) return de
        }

        // 2. Direct DesktopEntry lookup
        let de = DesktopEntries.byId(raw) ?? DesktopEntries.byId(raw + ".desktop") ?? DesktopEntries.heuristicLookup(raw)
        if (de) return de
        if (cleanRaw && cleanRaw !== raw) {
            de = DesktopEntries.byId(cleanRaw) ?? DesktopEntries.byId(cleanRaw + ".desktop") ?? DesktopEntries.heuristicLookup(cleanRaw)
            if (de) return de
        }

        // 3. Steam App ID matching: steam_app_123456
        const steamMatch = raw.match(/^steam_app_(\d+)$/i)
        if (steamMatch) {
            const sid = steamMatch[1]
            de = DesktopEntries.byId("steam_app_" + sid) ?? DesktopEntries.byId("steam_app_" + sid + ".desktop") ?? DesktopEntries.heuristicLookup("steam_app_" + sid)
            if (de) return de

            const allApps = DesktopEntries.applications.values
            for (const app of allApps) {
                if (app && app.exec && (app.exec.includes("rungameid/" + sid) || app.exec.includes("rungameid%2F" + sid) || app.exec.includes(sid))) {
                    return app
                }
            }
        }

        // 4. Scan DesktopEntries for title / name / exec / icon matches
        const norm = s => String(s || "").toLowerCase().replace(/[\s\-_:～~!?()\[\]'"+.,/\\|]+/g, "")
        const normWTitle = norm(wTitle)
        const normClean = norm(cleanRaw)

        const allApps = DesktopEntries.applications.values
        let bestMatch = null
        let bestScore = 0

        for (const app of allApps) {
            if (!app || !app.name) continue
            const appId = String(app.id || "").toLowerCase()
            const appName = String(app.name || "")
            const normName = norm(appName)
            const appExec = String(app.exec || "").toLowerCase()
            const appIcon = String(app.icon || "").toLowerCase()

            // A) Exact normalized name match with window title
            if (normWTitle.length >= 3 && normWTitle === normName) {
                return app
            }

            // B) Executable match in desktop Exec line
            if (cleanRawLower.length >= 3 && (appExec.includes(cleanRawLower + ".exe") || appExec.includes("/" + cleanRawLower))) {
                return app
            }

            // C) Lutris slug / icon matching:
            if (normClean.length >= 3) {
                if (appId.includes("lutris." + normClean) || appIcon === "lutris_" + normClean || normName === normClean) {
                    return app
                }
            }

            // D) Prefix / Substring title matches
            if (normWTitle.length >= 4 && normName.length >= 4) {
                if (normWTitle.startsWith(normName) || normName.startsWith(normWTitle)) {
                    const score = Math.min(normWTitle.length, normName.length)
                    if (score > bestScore) {
                        bestScore = score
                        bestMatch = app
                    }
                }
            }
        }

        if (bestMatch && bestScore >= 4) return bestMatch

        // 5. Word-token overlap matching for titles with subtitles or numerals (e.g. "BUNNY GARDEN 2" vs "Bunny Garden II")
        if (normWTitle.length >= 4) {
            const tokenize = s => s.toLowerCase().replace(/\b(ii)\b/g, "2").replace(/\b(iii)\b/g, "3").replace(/\b(iv)\b/g, "4").replace(/[^a-z0-9]/g, " ").split(/\s+/).filter(w => w.length >= 2)
            const wTokens = new Set(tokenize(wTitle))
            if (wTokens.size > 0) {
                let maxOverlap = 0
                let tokenMatch = null
                for (const app of allApps) {
                    if (!app || !app.name) continue
                    const appTokens = tokenize(app.name)
                    let overlap = 0
                    for (const tok of appTokens) {
                        if (wTokens.has(tok)) overlap++
                    }
                    if (overlap >= 2 && overlap > maxOverlap) {
                        maxOverlap = overlap
                        tokenMatch = app
                    }
                }
                if (tokenMatch && maxOverlap >= 2) return tokenMatch
            }
        }

        return null
    }

    function iconForApp(rawAppId, t, windowTitle) {
        if (!rawAppId || rawAppId === "") return ""
        dockRoot.desktopEntriesTick
        const title = windowTitle || dockRoot.windowTitleOf(t)
        return dockRoot.memo("icon", String(rawAppId) + "\u0001" + title, () => dockRoot._iconForApp(rawAppId, t, title))
    }

    function _iconForApp(rawAppId, t, windowTitle) {

        function resolveIcon(iconName) {
            if (!iconName || typeof iconName !== "string" || iconName === "") return ""
            if (iconName.startsWith("/") || iconName.startsWith("file://")) {
                return iconName
            }
            return Quickshell.iconPath(iconName, true) || ""
        }

        const raw = String(rawAppId).trim()
        const rawLower = raw.toLowerCase()
        const title = windowTitle || (t ? (t.title || t.lastIpcObject?.title || t.lastIpcObject?.initialTitle) : "")

        // 1. Check pre-scanned game map directly
        const map = dockRoot.gameLauncherMap || {}
        const cleanRaw = raw.replace(/\.(exe|bin|x86_64|x86|x64|elf)$/i, "").trim()
        const cleanRawLower = cleanRaw.toLowerCase()
        const mapped = map[rawLower] || map[cleanRawLower + ".exe"] || map[cleanRawLower] || (title ? map[String(title).toLowerCase().trim()] : null)
        if (mapped && mapped.icon) {
            const p = resolveIcon(mapped.icon)
            if (p !== "") return p
        }

        // 2. Try matching a DesktopEntry
        const de = dockRoot.matchDesktopEntry(raw, title, t)
        if (de && de.icon) {
            const p = resolveIcon(de.icon)
            if (p !== "") return p
        }

        // 3. Direct icon name lookups
        let p = resolveIcon(raw)
        if (p !== "") return p
        p = resolveIcon(rawLower)
        if (p !== "") return p

        // 4. Steam App ID icon lookups: steam_app_123456 -> steam_icon_123456
        const steamMatch = raw.match(/^steam_app_(\d+)$/i)
        if (steamMatch) {
            const sid = steamMatch[1]
            p = resolveIcon("steam_icon_" + sid)
            if (p !== "") return p
            p = resolveIcon("steam")
            if (p !== "") return p
        }

        // 5. Clean .exe / binary extensions
        if (cleanRaw && cleanRaw !== raw) {
            p = resolveIcon(cleanRaw) || resolveIcon(cleanRawLower)
            if (p !== "") return p
            p = resolveIcon("lutris_" + cleanRawLower)
            if (p !== "") return p
        }

        // 6. Reverse-DNS segments (e.g. org.gnome.Nautilus -> Nautilus)
        const parts = raw.split(".")
        if (parts.length > 1) {
            const last = parts[parts.length - 1]
            p = resolveIcon(last) || resolveIcon(last.toLowerCase())
            if (p !== "") return p
        }

        // 7. Fallback for genuine game windows running under Wine/Proton/Lutris:
        // Ensures game windows never get discarded by isGenuineWindow()
        if (rawLower.endsWith(".exe") || rawLower === "wine") {
            p = resolveIcon("lutris") || resolveIcon("net.lutris.Lutris") || resolveIcon("wine")
            if (p !== "") return p
        }

        return ""
    }

    function hasProperIcon(rawAppId, t, windowTitle) {
        return dockRoot.iconForApp(rawAppId, t, windowTitle) !== ""
    }

    function isGenuineWindow(t) {
        if (!t) return false

        // 1. Must be in a valid workspace (1-8 or special:*)
        const workspaceId = Number(t.workspace?.id)
        const workspaceName = String(t.workspace?.name ?? "")
        const inValidWorkspace = (workspaceId >= 1 && workspaceId <= 8)
            || workspaceName.startsWith("special:")
        if (!inValidWorkspace) return false

        // 2. Hyprland IPC client data
        const ipc = t.lastIpcObject || {}

        // 3. Mapping & visibility in compositor
        if (ipc.mapped === false) return false
        if (ipc.hidden === true) return false

        // 4. Geometry / Size: Filter out 0x0, 1x1, or tiny helper dummy windows
        if (Array.isArray(ipc.size)) {
            const w = Number(ipc.size[0])
            const h = Number(ipc.size[1])
            if (!isNaN(w) && !isNaN(h) && (w <= 1 || h <= 1)) return false
        }

        // 5. Wayland parent / transient hierarchy
        // Child surfaces/dialogs attached to a parent window belong to that parent
        if (t.wayland && t.wayland.parent != null) return false

        // 6. Application class / ID
        const rawAppId = String(t.wayland?.appId || ipc.class || ipc.initialClass || "").trim()
        if (!rawAppId) return false

        const lowerAppId = rawAppId.toLowerCase()
        const ignoredAppIds = [
            "xwaylandvideobridge",
            "steamwebhelper",
            "hyprland-share-picker"
        ]
        if (ignoredAppIds.includes(lowerAppId)) return false

        // 7. Window title validation
        // Genuine windows must have a non-empty title.
        // Stray windows, dropdowns, popup menus, and tooltips have empty titles.
        const title = String(t.title || t.wayland?.title || ipc.title || "").trim()
        const initialTitle = String(ipc.initialTitle || "").trim()
        const effectiveTitle = title || initialTitle

        if (!effectiveTitle) return false

        const lowerTitle = effectiveTitle.toLowerCase()

        // Steam notification toasts are transient notification popups, not genuine windows
        if (lowerTitle.startsWith("notificationtoasts")) return false

        // Generic popup/menu titles
        if (lowerTitle === "menu" || lowerTitle === "popup" || lowerTitle === "dropdown") return false

        // Desktop overlay scripts
        if (lowerTitle === "ilgwg_desktop_gremlins.py") return false

        // 8. Proper icon existence check
        if (!dockRoot.hasProperIcon(rawAppId, t, effectiveTitle)) return false

        return true
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
        if (!t) return ""
        const raw = String(t.wayland?.appId || t.lastIpcObject?.class || "").trim()
        const title = String(t.title || t.lastIpcObject?.title || t.lastIpcObject?.initialTitle || "").trim()

        // Match against known DesktopEntries (Steam / Lutris / Proton / native)
        const de = dockRoot.matchDesktopEntry(raw, title, t)
        if (de && de.id) {
            return String(de.id).toLowerCase().replace(/\.desktop$/, "")
        }

        // Check pre-scanned game map
        const rawLower = raw.toLowerCase()
        const cleanRaw = raw.replace(/\.(exe|bin|x86_64|x86|x64|elf)$/i, "").trim()
        const cleanRawLower = cleanRaw.toLowerCase()
        const map = dockRoot.gameLauncherMap || {}
        const mapped = map[rawLower] || map[cleanRawLower + ".exe"] || map[cleanRawLower] || (title ? map[title.toLowerCase().trim()] : null)
        if (mapped && mapped.desktopId) {
            return String(mapped.desktopId).toLowerCase().replace(/\.desktop$/, "")
        }

        return (cleanRaw || raw).toLowerCase()
    }

    function isSpecial(t) {
        return String(t?.workspace?.name ?? "").startsWith("special:")
    }

    function isPinned(id) {
        if (!id) return false
        const clean = String(id).toLowerCase().replace(/\.desktop$/, "")
        return dockRoot.pinned.some(p => {
            const pClean = String(p.id || "").toLowerCase().replace(/\.desktop$/, "")
            return pClean === clean || p.id === id
        })
    }

    function pin(id, raw) {
        if (!id) return
        const clean = String(id).toLowerCase().replace(/\.desktop$/, "")
        if (dockRoot.isPinned(clean)) return
        const rawClean = raw ? String(raw).replace(/\.desktop$/, "") : clean
        if (!dockRoot.hasProperIcon(rawClean) && !dockRoot.hasProperIcon(raw || id)) return
        dockRoot.pinned = dockRoot.pinned.concat([{ id: clean, raw: rawClean }])
        dockRoot.savePins()
    }

    function unpin(id) {
        if (!id) return
        const clean = String(id).toLowerCase().replace(/\.desktop$/, "")
        dockRoot.pinned = dockRoot.pinned.filter(p => {
            const pClean = String(p.id || "").toLowerCase().replace(/\.desktop$/, "")
            return pClean !== clean && p.id !== id
        })
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
            if (t && !dockRoot.isSpecial(t) && dockRoot.isGenuineWindow(t) && dockRoot.appKey(t) === id)
                out.push(t)
        }
        return out
    }

    function buildItems() {
        dockRoot.itemsTick
        dockRoot.wsTick
        dockRoot.desktopEntriesTick
        const pins = dockRoot.pinned
        const pinIds = new Set(pins.map(p => p.id))

        const left = []
        for (let i = 0; i < pins.length; i++) {
            const p = pins[i]
            if (dockRoot.hasProperIcon(p.raw || p.id)) {
                left.push({ key: "pin:" + p.id, kind: "pin", id: p.id, raw: p.raw })
            }
        }

        const unpinnedMap = new Map()
        const unpinnedKeys = []
        const right = []

        for (let i = 0; i < dockModel.count; i++) {
            const t = dockModel.get(i).toplevelRef
            if (!t || !dockRoot.isGenuineWindow(t)) continue
            const rawId = String(t.wayland?.appId || t.lastIpcObject?.class || "")
            const effectiveTitle = String(t.title || t.lastIpcObject?.title || t.lastIpcObject?.initialTitle || "").trim()
            if (!dockRoot.hasProperIcon(rawId, t, effectiveTitle)) continue

            if (dockRoot.isSpecial(t)) {
                right.push({ key: "win:" + t.address, kind: "win", toplevel: t })
            } else {
                const key = dockRoot.appKey(t)
                if (!pinIds.has(key)) {
                    if (unpinnedMap.has(key)) {
                        unpinnedMap.get(key).wins.push(t)
                    } else {
                        const item = {
                            key: "app:" + key,
                            kind: "app",
                            id: key,
                            raw: rawId,
                            toplevel: t,
                            wins: [t]
                        }
                        unpinnedMap.set(key, item)
                        unpinnedKeys.push(key)
                    }
                }
            }
        }

        const middle = unpinnedKeys.map(k => unpinnedMap.get(k))

        const out = []
        // App Launcher anchor at far left
        out.push({ key: "launcher", kind: "launcher" })

        for (const p of left) out.push(p)

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
        dockRoot.desktopEntriesTick
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

    function launchApp(raw, id) {
        if (!raw && !id) return
        const targets = [raw, id].filter(x => !!x)
        for (const t of targets) {
            const clean = String(t).replace(/\.desktop$/, "")
            const e = DesktopEntries.byId(t) ?? DesktopEntries.byId(clean + ".desktop") ?? DesktopEntries.heuristicLookup(clean) ?? DesktopEntries.heuristicLookup(t)
            if (e) {
                e.execute()
                return
            }
        }
        if (raw) Quickshell.execDetached([String(raw).replace(/\.desktop$/, "")])
    }

    function toggleLauncher() {
        if (dockRoot.launcher) {
            dockRoot.launcher.isOpenLauncher = !dockRoot.launcher.isOpenLauncher
        } else {
            Quickshell.execDetached(["qs", "ipc", "launcher", "toggle"])
        }
    }

    property real lastPinOpenTime: 0
    property int lastPinOpenIndex: -1
    property double lastAppPinActionTime: 0

    function openPin(index) {
        let pinIdx = 0
        if (typeof index === "number") {
            pinIdx = index - 1
        } else if (typeof index === "string" && index.toLowerCase() === "n") {
            pinIdx = 0
        } else {
            pinIdx = parseInt(index, 10) - 1
        }
        const pins = dockRoot.pinned.filter(p => p && dockRoot.hasProperIcon(p.raw || p.id))
        if (isNaN(pinIdx) || pinIdx < 0 || pinIdx >= pins.length) return

        const now = Date.now()
        if (now - dockRoot.lastPinOpenTime < 250 && dockRoot.lastPinOpenIndex === pinIdx) {
            return
        }
        dockRoot.lastPinOpenTime = now
        dockRoot.lastPinOpenIndex = pinIdx

        const p = pins[pinIdx]
        if (!p) return

        dockPreview.close()
        const wins = dockRoot.windowsFor(p.id)
        if (wins.length === 0) {
            dockRoot.launchApp(p.raw, p.id)
        } else {
            dockRoot.focusToplevel(dockRoot.targetFor(wins))
        }
    }

    property real dockHeight: 64
    property real bottomMargin: 8
    property real hoverHeadroom: 56 // room above the toolbar for tooltips; input is limited by the mask, not this
    property real hoverRegionHeight: 2
    property bool dockPinned: false
    property bool hoverToReveal: true

    readonly property bool hasActiveWorkspaceWindows: {
        dockRoot.wsTick
        if (!dockRoot.activeWorkspace) return false
        for (let i = 0; i < dockModel.count; i++) {
            const item = dockModel.get(i)
            const t = item.toplevelRef
            if (t && t.workspace && t.workspace.id === dockRoot.activeWorkspace.id) {
                return true
            }
        }
        return false
    }

    readonly property bool hasActiveWindow: hasActiveWorkspaceWindows && (ToplevelManager.activeToplevel?.activated ?? false)

    onHasActiveWindowChanged: {
        if (!hasActiveWindow) {
            dockKeyHandler.forceActiveFocus()
        }
    }

    readonly property bool isHovered: (dockMouseArea && dockMouseArea.containsMouse) || (dockHover && dockHover.hovered)

    readonly property bool shouldReveal: dockRoot.dockPinned
        || (dockRoot.hoverToReveal && dockRoot.isHovered)
        || dockPreview.isOpen
        || (dockRoot.launcher && dockRoot.launcher.isOpenLauncher)
        || !dockRoot.hasActiveWindow

    property bool expanded: shouldReveal

    onShouldRevealChanged: {
        if (!shouldReveal) dockPreview.close()
    }

    DockPreview {
        id: dockPreview
        dockRoot: dockRoot
    }

    PanelWindow {
        id: realDock
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.namespace: "quickshell:dock"
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand
        implicitHeight: dockRoot.dockHeight + dockRoot.bottomMargin + dockRoot.hoverHeadroom
        exclusiveZone: dockRoot.dockPinned ? dockRoot.dockHeight + dockRoot.bottomMargin : 0
        color: "transparent"
        anchors { bottom: true; left: true; right: true }
        mask: Region { item: dockMouseArea }

        IpcHandler {
            target: "dock"
            function toggle(): void { dockRoot.dockPinned = !dockRoot.dockPinned; }
            function pin(appId: string): void { dockRoot.pin(appId.toLowerCase(), appId); }
            function unpin(appId: string): void { dockRoot.unpin(appId.toLowerCase()); }
            function openPin(index: int): void { dockRoot.openPin(index); }
        }

        Item {
            id: dockKeyHandler
            anchors.fill: parent
            focus: true
            Keys.onPressed: event => {
                if (!(event.modifiers & Qt.AltModifier))
                    return;
                const n = event.key >= Qt.Key_1 && event.key <= Qt.Key_9 ? event.key - Qt.Key_1 + 1 : event.key === Qt.Key_0 ? 10 : event.key === Qt.Key_N ? 1 : -1;
                if (n > 0) {
                    dockRoot.openPin(n);
                    event.accepted = true;
                }
            }
        }

        // Alt+1…9, Alt+0, Alt+N open pinned apps while the desktop is focused
        Repeater {
            model: ["1", "2", "3", "4", "5", "6", "7", "8", "9", "0", "N"]
            delegate: Item {
                required property string modelData
                Shortcut {
                    sequence: "Alt+" + parent.modelData
                    enabled: !dockRoot.hasActiveWindow || dockKeyHandler.activeFocus
                    onActivated: dockRoot.openPin(parent.modelData === "0" ? 10 : parent.modelData === "N" ? 1 : Number(parent.modelData))
                }
            }
        }

        MouseArea {
            id: dockMouseArea
            // Only as tall as the toolbar plus its margin: this item is the window's input
            // mask, so anything taller would block clicks on the windows above the dock.
            height: dockRoot.dockHeight + dockRoot.bottomMargin
            width: Math.max(toolbar.width + 48, 360)
            anchors.horizontalCenter: parent.horizontalCenter
            // slides down out of the window when hidden, leaving a thin hover strip
            y: realDock.implicitHeight - height + (dockRoot.shouldReveal ? 0 : dockRoot.hoverToReveal ? height - dockRoot.hoverRegionHeight : height + 1)
            Behavior on y { Spring { speed: "default"; expressive: dockRoot.shouldReveal } }
            hoverEnabled: true
            onPressed: mouse => {
                dockKeyHandler.forceActiveFocus();
                mouse.accepted = false;
            }

            Elevation {
                anchors.fill: toolbar
                radius: toolbar.radius
                level: 3
                visible: toolbar.visible
            }

            // M3 Expressive floating toolbar: 64px, full corners, surface-container
            Rectangle {
                id: toolbar
                visible: dockRoot.hasContent
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: dockRoot.bottomMargin
                width: Math.min(list.contentWidth + 16, 1880)
                height: dockRoot.dockHeight
                radius: height / 2
                color: Colors.surface_container
                Behavior on width { Spring { speed: "default" } }

                HoverHandler { id: dockHover }

                // right-click on empty toolbar space toggles pinning the dock open
                TapHandler {
                    acceptedButtons: Qt.RightButton
                    onTapped: point => {
                        if (Date.now() - dockRoot.lastAppPinActionTime < 300)
                            return;
                        const p = toolbar.mapToItem(list, point.position.x, point.position.y);
                        if (!list.itemAt(p.x + list.contentX, p.y + list.contentY))
                            dockRoot.dockPinned = !dockRoot.dockPinned;
                    }
                }

                ListView {
                    id: list
                    anchors.centerIn: parent
                    width: Math.min(contentWidth, toolbar.width - 16)
                    height: parent.height
                    orientation: ListView.Horizontal
                    spacing: 4
                    interactive: contentWidth > width
                    boundsBehavior: Flickable.StopAtBounds
                    model: ScriptModel {
                        values: dockRoot.items
                        objectProp: "key"
                        comparisonMode: ObjectComparison.Identity
                    }
                    move: Transition { Spring { properties: "x"; speed: "default" } }
                    displaced: Transition { Spring { properties: "x"; speed: "default" } }
                    add: Transition {
                        Spring { property: "scale"; from: 0.5; to: 1; speed: "default" }
                        Fade { property: "opacity"; from: 0; to: 1 }
                    }

                    delegate: Item {
                        id: cell
                        required property var modelData
                        required property int index

                        readonly property bool isLauncher: modelData.kind === "launcher"
                        readonly property bool isSep: modelData.kind === "sep"
                        readonly property bool isPin: modelData.kind === "pin"
                        readonly property bool isApp: modelData.kind === "app"
                        readonly property bool isWin: modelData.kind === "win"
                        readonly property var tl: isWin || isApp ? modelData.toplevel : null

                        readonly property string rawAppId: {
                            if (isLauncher) return "";
                            if (isPin || isApp) return String(modelData.raw || modelData.id || "");
                            return String(tl?.wayland?.appId || tl?.lastIpcObject?.class || "");
                        }
                        readonly property string appKey: {
                            if (isLauncher) return "";
                            if (isPin || isApp) return String(modelData.id || "").toLowerCase();
                            return tl ? dockRoot.appKey(tl) : rawAppId.toLowerCase();
                        }
                        readonly property string iconSource: {
                            if (isLauncher || isSep) return "";
                            if (isPin) return dockRoot.iconForApp(modelData.raw || appKey);
                            return dockRoot.iconForApp(rawAppId, tl, tl?.title);
                        }
                        readonly property bool hasIcon: isLauncher || isSep || iconSource !== ""
                        readonly property var entry: {
                            dockRoot.desktopEntriesTick;
                            if (isLauncher || isSep) return null;
                            if (isPin) {
                                const raw = modelData.raw || appKey;
                                return DesktopEntries.byId(raw) ?? DesktopEntries.byId(raw + ".desktop") ?? DesktopEntries.byId(appKey) ?? DesktopEntries.byId(appKey + ".desktop") ?? DesktopEntries.heuristicLookup(raw) ?? DesktopEntries.heuristicLookup(appKey);
                            }
                            return dockRoot.matchDesktopEntry(rawAppId, tl?.title, tl);
                        }

                        // windows this icon stands for (all of the app's windows for pinned / grouped apps)
                        readonly property var wins: isPin || isApp ? dockRoot.windowsFor(appKey) : (tl ? [tl] : [])
                        readonly property bool running: wins.length > 0
                        readonly property bool activated: wins.some(w => w.activated)
                        readonly property bool urgent: wins.some(w => w.urgent)
                        readonly property bool canPin: !isSep && !isPin && !isLauncher && rawAppId !== "" && !dockRoot.isSpecial(tl) && hasIcon
                        readonly property var activeWin: wins.find(w => w.activated) ?? null
                        readonly property string appName: {
                            if (isLauncher) return "Apps";
                            const name = entry?.name;
                            if (name) return name;
                            const clean = rawAppId.replace(/\.(exe|bin|x86_64|x86|x64|elf)$/i, "");
                            return clean ? clean.charAt(0).toUpperCase() + clean.slice(1) : "Application";
                        }
                        readonly property string title: activated && activeWin && activeWin.title ? activeWin.title : appName
                        // every window on another workspace: shown dimmed
                        readonly property bool ghost: {
                            dockRoot.wsTick;
                            if (isLauncher || !running || activated) return false;
                            const active = dockRoot.activeWorkspace;
                            return !!active && wins.every(w => w.workspace && w.workspace.id !== active.id);
                        }

                        // groups are separated by space, not a rule
                        width: isSep ? 12 : visible ? 56 : 0
                        height: list.height
                        visible: isLauncher || isSep || (hasIcon && (isPin || isApp || dockRoot.isGenuineWindow(tl)))

                        // launcher: the toolbar's paired filled button; square while the launcher is open
                        IconButton {
                            visible: cell.isLauncher
                            anchors.centerIn: parent
                            size: "m"
                            style: "filled"
                            icon: "apps"
                            checkable: true
                            checked: !!dockRoot.launcher && dockRoot.launcher.isOpenLauncher
                            // filled toggle would drop to surface-container when unchecked; keep primary
                            color: Colors.primary
                            contentColor: Colors.on_primary
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton) {
                                    dockRoot.lastAppPinActionTime = Date.now();
                                    dockRoot.dockPinned = !dockRoot.dockPinned;
                                } else {
                                    dockPreview.close();
                                    dockRoot.toggleLauncher();
                                }
                            }
                        }

                        // app: focused app sits in a secondary-container (selected) shape
                        Clickable {
                            id: appButton
                            visible: !cell.isLauncher && !cell.isSep
                            anchors.centerIn: parent
                            width: 56
                            height: 56
                            restRadius: cell.activated ? Motion.shapeLarge : height / 2
                            pressedRadius: Motion.shapeMedium
                            color: cell.activated ? Colors.secondary_container : "transparent"
                            contentColor: cell.activated ? Colors.on_secondary_container : Colors.on_surface
                            opacity: cell.ghost && !hovered ? 0.6 : 1
                            Behavior on opacity { Fade {} }
                            acceptedButtons: Qt.LeftButton | Qt.MiddleButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.MiddleButton) {
                                    dockRoot.closeToplevel(cell.isWin ? cell.tl : (cell.activeWin ?? cell.wins[0]));
                                } else if (mouse.button === Qt.RightButton) {
                                    dockRoot.lastAppPinActionTime = Date.now();
                                    if (cell.isPin)
                                        dockRoot.unpin(cell.appKey);
                                    else if (cell.canPin || cell.isApp)
                                        dockRoot.pin(cell.appKey, cell.entry?.id ? String(cell.entry.id).replace(/\.desktop$/, "") : cell.rawAppId);
                                } else if (cell.isPin && !cell.running) {
                                    dockPreview.close();
                                    dockRoot.launchApp(cell.rawAppId, cell.appKey);
                                } else if ((cell.isPin || cell.isApp) && cell.wins.length > 1) {
                                    dockPreview.toggleFor(cell);
                                } else {
                                    dockPreview.close();
                                    dockRoot.focusToplevel(cell.isWin ? cell.tl : cell.wins[0]);
                                }
                            }

                            // hover: the icon grows and lifts on an overshooting spring; press squishes it toward its base
                            property real iconScale: pressed ? 0.88 : hovered ? 1.12 : 1
                            property real lift: hovered && !pressed ? -4 : 0
                            Behavior on iconScale { Spring { speed: "fast" } }
                            Behavior on lift { Spring { speed: "fast" } }

                            // urgent: gentle spring bounce + error badge
                            property real bounce: 0
                            SequentialAnimation on bounce {
                                running: cell.urgent
                                loops: Animation.Infinite
                                onRunningChanged: if (!running) appButton.bounce = 0
                                NumberAnimation { to: -6; duration: Motion.expressiveFastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                                NumberAnimation { to: 0; duration: Motion.expressiveDefaultSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveDefaultSpatial }
                                PauseAnimation { duration: 600 }
                            }

                            Image {
                                id: appIcon
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: appButton.bounce + appButton.lift
                                width: 40
                                height: 40
                                scale: appButton.iconScale
                                transformOrigin: Item.Bottom
                                sourceSize: Qt.size(80, 80)
                                fillMode: Image.PreserveAspectFit
                                source: cell.iconSource

                                // child of the icon so it grows and lifts with it
                                Badge {
                                    visible: cell.urgent
                                    x: appIcon.width - 6
                                    y: -2
                                }
                            }

                            // running indicators: one dot per window (max 3); hidden when focused
                            Row {
                                anchors.horizontalCenter: parent.horizontalCenter
                                anchors.bottom: parent.bottom
                                anchors.bottomMargin: 2
                                spacing: 3
                                opacity: cell.running && !cell.activated ? 1 : 0
                                Behavior on opacity { Fade {} }
                                Repeater {
                                    model: Math.min(cell.wins.length, 3)
                                    delegate: Rectangle {
                                        width: 4
                                        height: 4
                                        radius: 2
                                        color: Colors.on_surface_variant
                                    }
                                }
                            }

                            // M3 plain tooltip
                            Rectangle {
                                readonly property bool shown: appButton.hovered && !(dockPreview.isOpen && dockPreview.targetAppKey === cell.appKey)
                                anchors.bottom: parent.top
                                anchors.bottomMargin: 12
                                anchors.horizontalCenter: parent.horizontalCenter
                                width: Math.min(tipText.implicitWidth + 16, 360)
                                height: Math.max(24, tipText.implicitHeight + 8)
                                radius: Motion.shapeExtraSmall
                                color: Colors.inverse_surface
                                opacity: shown ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                StyledText {
                                    id: tipText
                                    anchors.centerIn: parent
                                    width: Math.min(implicitWidth, 344)
                                    role: "bodySmall"
                                    color: Colors.inverse_on_surface
                                    elide: Text.ElideRight
                                    text: cell.title
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
