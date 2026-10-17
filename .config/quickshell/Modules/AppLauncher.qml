pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components

// App launcher as an M3 search view: search bar and results list.
// Ranking favours frequently launched apps; right-click (or the pin button) pins to the dock.
Item {
    id: root

    property var dock: null

    property bool isOpenLauncher: false
    property string query: ""
    property int selectedIndex: 0
    // last real pointer position (scene coords): hover only selects when the pointer actually moves
    property real lastMouseX: -1
    property real lastMouseY: -1

    function extractList(prop) {
        if (!prop) return [];
        if (Array.isArray(prop)) return prop;
        const res = [];
        try {
            const len = prop.length || 0;
            for (let i = 0; i < len; i++) {
                if (prop[i] !== undefined && prop[i] !== null)
                    res.push(String(prop[i]));
            }
        } catch (e) {}
        return res;
    }

    function resetLauncher() {
        root.query = "";
        root.selectedIndex = 0;
        searchField.text = "";
    }

    onIsOpenLauncherChanged: {
        if (isOpenLauncher)
            searchField.forceActiveFocus();
        else
            root.resetLauncher();
    }

    FileView {
        id: stateFile
        path: Quickshell.dataPath("app-launcher-pins.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: stateAdapter
            property var launchCounts: ({})
        }
    }

    function launchCount(id) {
        return stateAdapter.launchCounts[id] || 0;
    }
    function recordLaunch(id) {
        const counts = Object.assign({}, stateAdapter.launchCounts);
        counts[id] = (counts[id] || 0) + 1;
        stateAdapter.launchCounts = counts;
    }

    function toggleDockPin(entry) {
        if (!entry || !entry.id) return;
        const rawId = entry.id;
        const cleanId = rawId.replace(/\.desktop$/, "").toLowerCase();
        const bareRaw = rawId.replace(/\.desktop$/, "");
        if (root.dock) {
            if (root.dock.isPinned(cleanId)) {
                root.dock.unpin(cleanId);
            } else {
                root.dock.pin(cleanId, bareRaw);
            }
        } else {
            Quickshell.execDetached(["qs", "ipc", "call", "dock", "pin", cleanId]);
        }
    }

    property var allApps: {
        const apps = [...DesktopEntries.applications.values].filter(e => e.name && !e.noDisplay);

        apps.sort((a, b) => {
            const aCount = root.launchCount(a.id);
            const bCount = root.launchCount(b.id);
            if (aCount !== bCount)
                return bCount - aCount;

            return a.name.localeCompare(b.name);
        });
        return apps;
    }

    function fuzzyScore(pattern, text) {
        const pLen = pattern.length;
        const tLen = text.length;
        if (pLen > tLen || pLen < 3) return 0;
        let pIdx = 0;
        let score = 0;
        let consecutive = 0;
        let firstMatch = -1;
        let lastMatch = -1;
        for (let tIdx = 0; tIdx < tLen; tIdx++) {
            if (pIdx < pLen && text[tIdx] === pattern[pIdx]) {
                if (firstMatch === -1) firstMatch = tIdx;
                lastMatch = tIdx;
                pIdx++;
                consecutive++;
                score += 15 + consecutive * 10;
                if (tIdx === 0 || !/[a-zA-Z0-9]/.test(text[tIdx - 1])) {
                    score += 30;
                }
            } else {
                consecutive = 0;
            }
        }
        if (pIdx === pLen) {
            const span = lastMatch - firstMatch + 1;
            if (span > pLen * 2.2) return 0;
            score -= span * 3;
            score -= firstMatch * 2;
            return Math.max(1, score);
        }
        return 0;
    }

    function scoreApp(app, query) {
        if (!query) return 0;

        const tokens = query.split(/\s+/).filter(t => t.length > 0);
        if (tokens.length === 0) return 0;

        const name = (app.name || "").toLowerCase();
        const appId = (app.id || "").toLowerCase().replace(/\.desktop$/i, "");
        const execBin = (app.exec || "").toLowerCase().split(/\s+/)[0].replace(/^.*\//, "");
        const generic = (app.genericName || "").toLowerCase();
        const comment = (app.comment || "").toLowerCase();
        const keywords = root.extractList(app.keywords);
        const categories = root.extractList(app.categories);

        const nameWords = name.split(/[\s\-_/]+/).filter(w => w.length > 0);
        const genWords = generic.split(/[\s\-_/]+/).filter(w => w.length > 0);
        const comWords = comment.split(/[\s\-_/]+/).filter(w => w.length > 0);

        let totalScore = 0;

        for (let i = 0; i < tokens.length; i++) {
            const token = tokens[i];
            let tokenScore = 0;

            if (name === token) {
                tokenScore = 10000;
            } else if (appId === token || execBin === token) {
                tokenScore = 9000;
            } else if (name.startsWith(token)) {
                tokenScore = 8000 - Math.min(500, (name.length - token.length) * 10);
            } else if (nameWords.some(w => w.startsWith(token))) {
                tokenScore = 7200;
            } else if (appId.startsWith(token) || execBin.startsWith(token)) {
                tokenScore = 6500;
            } else if (nameWords.map(w => w[0]).join("").startsWith(token)) {
                tokenScore = 6000;
            } else if (name.includes(token)) {
                tokenScore = 5200 - name.indexOf(token) * 15;
            } else if (execBin.includes(token) || appId.includes(token)) {
                tokenScore = 4600;
            } else if (generic.startsWith(token) || genWords.some(w => w.startsWith(token))) {
                tokenScore = 4000;
            } else if (keywords.some(kw => (kw || "").toLowerCase() === token)) {
                tokenScore = 3600;
            } else if (keywords.some(kw => (kw || "").toLowerCase().startsWith(token))) {
                tokenScore = 3200;
            } else if (categories.some(cat => (cat || "").toLowerCase().startsWith(token))) {
                tokenScore = 2800;
            } else if (comWords.some(w => w.startsWith(token))) {
                tokenScore = 2500;
            } else if (keywords.some(kw => (kw || "").toLowerCase().includes(token))) {
                tokenScore = 2200;
            } else if (generic.includes(token)) {
                tokenScore = 1900;
            } else if (comment.includes(token)) {
                tokenScore = 1600;
            } else if (categories.some(cat => (cat || "").toLowerCase().includes(token))) {
                tokenScore = 1400;
            } else if (token.length >= 3) {
                const f = root.fuzzyScore(token, name);
                if (f > 0) {
                    tokenScore = 1000 + Math.min(500, f);
                }
            }

            if (tokenScore === 0) return 0;
            totalScore += tokenScore;
        }

        const count = root.launchCount(app.id);
        if (count > 0) {
            totalScore += Math.min(300, Math.round(Math.log1p(count) * 60));
        }

        return totalScore;
    }

    property var filteredApps: {
        const q = root.query.trim().toLowerCase();
        let pool = root.allApps;
        if (q === "")
            return pool;

        const results = [];
        for (let i = 0; i < pool.length; i++) {
            const app = pool[i];
            const score = root.scoreApp(app, q);
            if (score > 0) {
                results.push({ app: app, score: score });
            }
        }

        results.sort((a, b) => {
            if (b.score !== a.score)
                return b.score - a.score;
            return a.app.name.localeCompare(b.app.name);
        });

        return results.map(r => r.app);
    }

    onQueryChanged: root.selectedIndex = 0
    onFilteredAppsChanged: if (root.selectedIndex >= root.filteredApps.length)
        root.selectedIndex = Math.max(0, root.filteredApps.length - 1)

    function launch(entry) {
        if (!entry)
            return;
        root.recordLaunch(entry.id);
        entry.execute();
        root.isOpenLauncher = false;
        root.resetLauncher();
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.isOpenLauncher = !root.isOpenLauncher;
            if (root.isOpenLauncher)
                searchField.forceActiveFocus();
        }
        function open(): void {
            root.isOpenLauncher = true;
            searchField.forceActiveFocus();
        }
        function close(): void {
            root.isOpenLauncher = false;
        }
    }

    PanelWindow {
        id: panelWindow
        WlrLayershell.namespace: "quickshell:applauncher"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.isOpenLauncher ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        color: "transparent"
        visible: root.isOpenLauncher || panel.opacity > 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenLauncher = false
        }

        Elevation {
            anchors.fill: panel
            radius: panel.radius
            level: 3
            opacity: panel.opacity
            scale: panel.scale
            transformOrigin: Item.Top
        }

        // M3 search view (docked): surface-container-high, 28px corners
        Rectangle {
            id: panel
            width: 640
            height: 560
            anchors.horizontalCenter: parent.horizontalCenter
            y: 200
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            transformOrigin: Item.Top
            opacity: root.isOpenLauncher ? 1 : 0
            scale: root.isOpenLauncher ? 1 : 0.92
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }

            // swallow clicks so they don't close the launcher
            MouseArea { anchors.fill: parent }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---- search bar ----
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: 56
                    radius: height / 2
                    color: Colors.surface_container_highest

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 4
                        spacing: 16

                        Icon { name: "search"; color: Colors.on_surface }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            text: root.query
                            color: Colors.on_surface
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.on_primary
                            font.family: Typography.family
                            font.pixelSize: Typography.size("bodyLarge")
                            font.weight: Typography.weight("bodyLarge")
                            clip: true
                            onTextChanged: root.query = text

                            Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                            Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            Keys.onReturnPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEnterPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEscapePressed: root.isOpenLauncher = false

                            StyledText {
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                text: "Search apps"
                            }
                        }

                        IconButton {
                            icon: "close"
                            opacity: searchField.text.length > 0 ? 1 : 0
                            enabled: opacity > 0
                            Behavior on opacity { Fade {} }
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                    }
                }

                // ---- results ----
                ListView {
                    id: resultsList
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    reuseItems: true
                    spacing: 2
                    model: root.filteredApps
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: false
                    ScrollIntoView { view: resultsList }
                    boundsBehavior: Flickable.StopAtBounds

                    // selected row: secondary container with the expressive 16px list shape,
                    // springing between rows
                    highlight: Rectangle {
                        width: resultsList.width
                        height: 64
                        radius: Motion.shapeLarge
                        color: Colors.secondary_container
                        y: resultsList.currentItem ? resultsList.currentItem.y : 0
                        visible: resultsList.count > 0
                        Behavior on y { Spring {} }
                    }

                    delegate: Clickable {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool current: index === root.selectedIndex
                        readonly property string dockId: modelData.id.replace(/\.desktop$/, "").toLowerCase()
                        readonly property bool pinned: root.dock ? root.dock.isPinned(dockId) : false

                        width: resultsList.width
                        height: 64
                        restRadius: hovered ? Motion.shapeMedium : Motion.shapeExtraSmall
                        pressedRadius: Motion.shapeLarge
                        contentColor: current ? Colors.on_secondary_container : Colors.on_surface
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onClicked: mouse => mouse.button === Qt.RightButton ? root.toggleDockPin(modelData) : root.launch(modelData)

                        // hover only selects when the pointer actually moved (not when the list scrolls under it)
                        Connections {
                            target: row.mouseArea
                            function onPositionChanged(mouse) {
                                const p = row.mapToItem(null, mouse.x, mouse.y);
                                if (p.x === root.lastMouseX && p.y === root.lastMouseY)
                                    return;
                                root.lastMouseX = p.x;
                                root.lastMouseY = p.y;
                                root.selectedIndex = row.index;
                            }
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 16
                            anchors.rightMargin: 8
                            spacing: 16

                            IconImage {
                                implicitSize: 40
                                source: Quickshell.iconPath(row.modelData.icon, true)
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "bodyLarge"
                                    color: row.contentColor
                                    elide: Text.ElideRight
                                    text: row.modelData.name
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    role: "bodyMedium"
                                    color: row.current ? Colors.on_secondary_container : Colors.on_surface_variant
                                    elide: Text.ElideRight
                                    text: row.modelData.genericName || row.modelData.comment || ""
                                }
                            }
                            // pin to dock: outlined glyph when unpinned, filled when pinned
                            IconButton {
                                icon: "keep"
                                checkable: true
                                checked: row.pinned
                                opacity: row.pinned || row.hovered || hovered ? 1 : 0
                                Behavior on opacity { Fade {} }
                                onClicked: root.toggleDockPin(row.modelData)
                            }
                        }
                    }

                    // empty state
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: resultsList.count === 0
                        spacing: 12
                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 72
                            implicitHeight: 72
                            radius: Motion.shapeExtraLarge
                            color: Colors.secondary_container
                            Icon { anchors.centerIn: parent; size: 32; name: "search_off"; color: Colors.on_secondary_container }
                        }
                        StyledText {
                            Layout.alignment: Qt.AlignHCenter
                            role: "titleMedium"
                            text: "No matching apps"
                        }
                    }
                }
            }
        }
    }
}
