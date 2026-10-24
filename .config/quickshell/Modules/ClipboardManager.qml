pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Clipboard history (cliphist) as an M3 search view: list + preview, copy / delete.
// Also shows the "Copied" snackbar whenever something new lands on the clipboard.
Item {
    id: root

    property var copyToast

    property bool isOpenClipB: false
    property string query: ""
    // row wave on open: `stage` counts up and each row rises in when it passes its index
    property int stage: 0
    property bool dirty: false
    // copy / delete / clear-all in flight (rows play a short motion before the real command runs)
    property bool copying: false
    property var removingIds: ({})
    readonly property bool removingAny: Object.keys(removingIds).length > 0
    // entries queued for the next `cliphist delete` (captured at click time, not at fire time)
    property var pendingDeletes: []
    property bool wiping: false
    // selection to restore once a delete has refreshed the list
    property int keepIndex: -1
    onIsOpenClipBChanged: {
        if (isOpenClipB) {
            dirty = true;
            copyClose.stop();
            searchField.forceActiveFocus();
            stageTimer.restart();
        }
    }
    Timer {
        id: stageTimer
        interval: 35
        repeat: true
        onTriggered: {
            if (root.stage < 10)
                root.stage++;
            else
                stop();
        }
    }
    Timer {
        id: copyClose
        interval: 150
        onTriggered: root.isOpenClipB = false
    }
    Timer {
        id: deleteGo
        interval: 220
        onTriggered: {
            if (root.pendingDeletes.length === 0)
                return;
            // never kill a delete in flight: wait for it, then send the whole batch
            if (deleteProc.running) {
                restart();
                return;
            }
            const batch = root.pendingDeletes;
            root.pendingDeletes = [];
            // lines go in as argv (no stdin race); ids of the batch follow "--" so their decoded previews go too
            const raws = batch.map(e => e.raw);
            const ids = batch.map(e => e.id);
            deleteProc.command = ["sh", "-c", "n=$1; shift; i=0; while [ $i -lt $n ]; do printf '%s\\n' \"$1\"; shift; i=$((i+1)); done | cliphist delete; for id in \"$@\"; do rm -f -- /tmp/qs-clip-$id.*; done", "sh", String(raws.length)].concat(raws, ids);
            deleteProc.running = true;
        }
    }
    Timer {
        id: wipeGo
        interval: 380
        onTriggered: wipeProc.running = true
    }
    property var entries: []          
    property var knownClipboardIds: ({})
    property bool hasClipboardBaseline: false
    property var selectedEntry: null
    property int selectedIndex: 0
    property int _prevSelectedIndex: 0
    property int _lastRecordedIndex: 0
    property real lastMouseX: -1
    property real lastMouseY: -1
    property string previewMode: "none" 
    property string previewText: ""
    property string previewImagePath: ""
    onPreviewTextChanged: if (previewText !== "") previewHolder.kick()
    onPreviewImagePathChanged: if (previewImagePath !== "") previewHolder.kick()

    FileView {
        id: timestampsFile
        path: Quickshell.dataPath("clipboard-timestamps.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: timestampsAdapter
            property var timestamps: ({})
        }
    }

    readonly property var imageTimestamps: (timestampsAdapter && timestampsAdapter.timestamps) ? timestampsAdapter.timestamps : ({})

    function formatImageDate(id) {
        const ts = (root.imageTimestamps && root.imageTimestamps[id]) ? root.imageTimestamps[id] : null;
        if (!ts)
            return Qt.formatDateTime(new Date(), "MMM d, HH:mm");
        const d = new Date(ts);
        if (isNaN(d.getTime()))
            return Qt.formatDateTime(new Date(), "MMM d, HH:mm");
        const now = new Date();
        if (d.getFullYear() === now.getFullYear()) {
            return Qt.formatDateTime(d, "MMM d, HH:mm");
        }
        return Qt.formatDateTime(d, "MMM d, yyyy, HH:mm");
    }

    property var filteredEntries: {
        const q = root.query.trim().toLowerCase();
        if (q === "")
            return root.entries;
        return root.entries.filter(e => {
            if (e.preview.toLowerCase().includes(q))
                return true;
            if (e.isImage) {
                if ("image".includes(q) || e.ext.toLowerCase().includes(q))
                    return true;
                const dStr = root.formatImageDate(e.id).toLowerCase();
                if (dStr.includes(q))
                    return true;
            }
            return false;
        });
    }

    // How long the selection has to stay put before we actually decode/preview it.
    // Prevents spamming `cliphist decode` processes when scrolling/arrow-keying fast.
    property int selectionDebounceMs: 120

    onQueryChanged: {
        root.selectedIndex = 0;
        root._prevSelectedIndex = 0;
        root._lastRecordedIndex = 0;
    }
    onFilteredEntriesChanged: {
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = Math.max(0, root.filteredEntries.length - 1);
        if (root.filteredEntries.length > 0)
            root.queueSelectEntry(root.filteredEntries[root.selectedIndex]);
        else {
            selectionDebounceTimer.stop();
            root.selectedEntry = null;
            root.previewMode = "none";
        }
    }
    onSelectedIndexChanged: {
        root._prevSelectedIndex = root._lastRecordedIndex;
        root._lastRecordedIndex = root.selectedIndex;
        if (root.filteredEntries.length > 0 && root.selectedIndex >= 0)
            root.queueSelectEntry(root.filteredEntries[root.selectedIndex]);
    }

    // Debounced entry point: call this instead of selectEntry() directly from
    // anything that can fire rapidly (keyboard nav, scroll, filtering).
    function queueSelectEntry(entry) {
        selectionDebounceTimer.pendingEntry = entry;
        selectionDebounceTimer.restart();
    }

    Timer {
        id: selectionDebounceTimer
        interval: root.selectionDebounceMs
        repeat: false
        property var pendingEntry: null
        onTriggered: {
            if (pendingEntry)
                root.selectEntry(pendingEntry);
        }
    }

    function parseLine(line) {
        const tabIdx = line.indexOf("\t");
        if (tabIdx === -1)
            return null;
        const id = line.substring(0, tabIdx);
        const preview = line.substring(tabIdx + 1);
        const m = preview.match(/binary.*?\b(jpg|jpeg|png|bmp)\b/i);
        return {
            "id": id,
            "preview": preview,
            "raw": line,
            "isImage": !!m,
            "ext": m ? m[1].toLowerCase() : ""
        };
    }

    function refreshList(keep) {
        if (keep) {
            root.keepIndex = root.selectedIndex;
        } else {
            root.selectedIndex = 0;
            root._prevSelectedIndex = 0;
            root._lastRecordedIndex = 0;
        }
        listProc.running = false;
        listProc.running = true;
    }

    function pollClipboardHistory() {
        clipboardWatchProc.running = false;
        clipboardWatchProc.running = true;
    }

    property int _decodeToken: 0 

    function selectEntry(entry) {
        root.selectedEntry = entry;
        if (entry.isImage) {
            root.previewMode = "image";
            root.previewImagePath = "";  
            const path = "/tmp/qs-clip-" + entry.id + "." + entry.ext;

            root._decodeToken += 1;
            const myToken = root._decodeToken;


            function onDone() {
                decodeToFileProc.exited.disconnect(onDone);
                // Only the most recent request is allowed to update the UI.
                // If a newer selection has started since this one began,
                // this exit belongs to a run we already killed — ignore it.
                if (myToken === root._decodeToken) {
                    root.previewImagePath = path;
                }
            }
            decodeToFileProc.exited.connect(onDone);

            decodeToFileProc.command = ["sh", "-c", "cliphist decode > '" + path + "'"];
            decodeToFileProc.stdinEnabled = true;
            decodeToFileProc.running = false;
            decodeToFileProc.running = true;
            imageWriteTimer.callback = () => {
                decodeToFileProc.write(entry.raw + "\n");
                decodeToFileProc.stdinEnabled = false; 
            };
            imageWriteTimer.restart();
        } else {
            root.previewMode = "text";
            root.previewText = "";
            decodeToTextProc.stdinEnabled = true;
            decodeToTextProc.running = false;
            decodeToTextProc.running = true;
            textWriteTimer.callback = () => {
                decodeToTextProc.write(entry.raw + "\n");
                decodeToTextProc.stdinEnabled = false;
            };
            textWriteTimer.restart();
        }
    }

    function copySelected() {
        if (!root.selectedEntry)
            return;
        const entry = root.selectedEntry;
        copyProc.stdinEnabled = true;
        copyProc.running = false;
        copyProc.running = true;
        copyWriteTimer.callback = () => {
            copyProc.write(entry.raw + "\n");
            copyProc.stdinEnabled = false;
            // the row pulses and the panel squashes before it folds away
            root.copying = true;
            panel.squish = 1;
            copyClose.restart();
        };
        copyWriteTimer.restart();
    }

    function deleteSelected() {
        if (!root.selectedEntry)
            return;
        const entry = root.selectedEntry;
        if (entry.isImage && timestampsAdapter.timestamps && timestampsAdapter.timestamps[entry.id]) {
            const cur = Object.assign({}, timestampsAdapter.timestamps);
            delete cur[entry.id];
            timestampsAdapter.timestamps = cur;
        }
        // the row collapses first, then the entry is really deleted
        if (root.removingIds[entry.id])
            return;
        const rem = Object.assign({}, root.removingIds);
        rem[entry.id] = true;
        root.removingIds = rem;
        root.pendingDeletes = root.pendingDeletes.concat([entry]);
        deleteGo.restart();
    }

    function wipeAll() {
        root.wiping = true;
        wipeGo.restart();
    }


    Timer {
        id: textWriteTimer
        interval: 30
        property var callback: null
        onTriggered: if (callback)
            callback()
    }
    Timer {
        id: imageWriteTimer
        interval: 30
        property var callback: null
        onTriggered: if (callback)
            callback()
    }
    Timer {
        id: copyWriteTimer
        interval: 30
        property var callback: null
        onTriggered: if (callback)
            callback()
    }

    Process {
        id: listProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const lines = text.split("\n").filter(l => l.length > 0);
                root.entries = lines.map(root.parseLine).filter(e => e !== null);
                // keep rows of a delete still in flight collapsed; forget the ones that are really gone
                if (root.removingAny && !deleteProc.running && root.pendingDeletes.length === 0)
                    root.removingIds = ({});
                if (root.keepIndex >= 0) {
                    root.selectedIndex = Math.max(0, Math.min(root.keepIndex, root.entries.length - 1));
                    root.keepIndex = -1;
                }
            }
        }
    }

    Process {
        id: clipboardWatchProc
        command: ["cliphist", "list"]
        stdout: StdioCollector {
            onStreamFinished: {
                const parsed = text.split("\n")
                    .map(line => root.parseLine(line))
                    .filter(entry => entry !== null);
                const ids = parsed.map(entry => entry.id);

                if (root.hasClipboardBaseline && ids.length > 0 && !root.knownClipboardIds[ids[0]]) {
                    // a screenshot's own card says so already
                    if (root.copyToast && Date.now() - Capture.lastCopy > 2500)
                        root.copyToast.showToast("Copied to clipboard");
                    if (root.isOpenClipB)
                        root.refreshList();
                }

                const known = Object.assign({}, root.knownClipboardIds);
                ids.forEach(id => known[id] = true);
                root.knownClipboardIds = known;
                root.hasClipboardBaseline = true;

                const cur = Object.assign({}, timestampsAdapter.timestamps || {});
                let changed = false;
                const now = Date.now();
                for (let i = 0; i < parsed.length; i++) {
                    const e = parsed[i];
                    if (e.isImage && !cur[e.id]) {
                        cur[e.id] = now;
                        changed = true;
                    }
                }
                if (changed) {
                    timestampsAdapter.timestamps = cur;
                }
            }
        }
    }

    // Event-driven: one long-running watcher prints a line per clipboard change, and the
    // history is listed once per change (after cliphist's own store has landed).
    Process {
        running: true
        // an orphan (quickshell gone) hits a closed pipe on the next change and takes its wl-paste with it
        command: ["sh", "-c", "trap '' PIPE; exec wl-paste --watch sh -c 'echo changed || kill $PPID'"]
        stdout: SplitParser {
            onRead: clipboardSettle.restart()
        }
    }
    Timer {
        id: clipboardSettle
        interval: 250
        onTriggered: root.pollClipboardHistory()
    }

    Component.onCompleted: root.pollClipboardHistory()

    Process {
        id: decodeToTextProc
        command: ["cliphist", "decode"]
        stdout: StdioCollector {
            onStreamFinished: root.previewText = text
        }
    }

    Process {
        id: decodeToFileProc
        command: ["true"]
    }

    Process {
        id: copyProc
        command: ["sh", "-c", "cliphist decode | wl-copy"]
    }

    Process {
        id: deleteProc
        command: ["cliphist", "delete"]
        onExited: {
            root.refreshList(true);
        }
    }

    Process {
        id: wipeProc
        command: ["sh", "-c", "cliphist wipe; rm -f -- /tmp/qs-clip-*"]
        onExited: {
            timestampsAdapter.timestamps = {};
            root.wiping = false;
            root.refreshList();
            root.selectedEntry = null;
            root.previewMode = "none";
        }
    }

    IpcHandler {
        target: "clipboard"

        function toggle(): void {
            root.isOpenClipB = !root.isOpenClipB;
            if (root.isOpenClipB) {
                root.refreshList();
                searchField.forceActiveFocus();
            }
        }
        function open(): void {
            root.isOpenClipB = true;
            root.refreshList();
            searchField.forceActiveFocus();
        }
        function close(): void {
            root.isOpenClipB = false;
        }
    }

    Shortcut { sequence: "Escape"; enabled: root.isOpenClipB; onActivated: root.isOpenClipB = false }

    PanelWindow {
        id: panelWindow
        WlrLayershell.namespace: "quickshell:clipboardmanager"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: root.isOpenClipB ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        anchors { top: true; bottom: true; left: true; right: true }
        exclusiveZone: -1
        color: "transparent"
        visible: root.isOpenClipB || panel.openP > 0.01

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenClipB = false
        }

        Elevation {
            anchors.fill: panel
            radius: panel.radius
            level: 3
            opacity: panel.opacity
            scale: panel.scale
            transformOrigin: Item.Top
        }

        // Unfolds from the search pill like the app launcher: full corners settle to 28px while
        // the history opens beneath it.
        ClippingRectangle {
            id: panel
            // tall enough for exactly `listRows` history rows (56px + 2px gaps) so none is cut off:
            // 16 margin + 56 search + 12 gap + 8 list padding + rows + 16 margin
            readonly property int listRows: 7
            readonly property real pillH: 88
            readonly property real fullH: 16 + 56 + 12 + 8 + listRows * 56 + (listRows - 1) * 2 + 16
            property real openP: root.isOpenClipB ? 1 : 0
            // 0 -> 1 on copy: a small squash before the fold
            property real squish: 0
            Behavior on openP { Spring { speed: root.isOpenClipB ? "default" : "fast" } }
            Behavior on squish { Spring { speed: "fast" } }
            onOpenPChanged: {
                if (root.dirty && !root.isOpenClipB && openP < 0.02) {
                    root.dirty = false;
                    stageTimer.stop();
                    root.stage = 0;
                    root.copying = false;
                    root.wiping = false;
                    squish = 0;
                    root.selectedIndex = 0;
                    scroller.stop();
                    entryList.positionViewAtBeginning();
                }
            }

            width: 720
            height: Math.max(pillH, pillH + (fullH - pillH) * openP)
            anchors.horizontalCenter: parent.horizontalCenter
            y: 240
            radius: Math.min(height / 2, Motion.shapeExtraLarge + 20 * (1 - Math.max(0, Math.min(1, openP))))
            color: Colors.surface_container_high
            transformOrigin: Item.Top
            opacity: Math.max(0, Math.min(1, openP * 3))
            scale: (0.9 + 0.1 * Math.min(openP, 1.04)) * (1 - 0.05 * squish)

            MouseArea { anchors.fill: parent }

            Item {
                id: content
                width: panel.width
                height: panel.fullH

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
                        anchors.leftMargin: 8
                        anchors.rightMargin: 8
                        spacing: 12

                        ShapeBadge {
                            id: searchBadge
                            Layout.preferredWidth: 40
                            Layout.preferredHeight: 40
                            shapeRest: "cookie4"
                            shapeActive: "sunny"
                            active: searchField.text.length > 0
                            spinning: active && panel.openP > 0.5
                            color: active ? Colors.primary : Colors.secondary_container
                            Icon {
                                anchors.centerIn: parent
                                name: searchBadge.active ? "search" : "content_paste"
                                color: searchBadge.active ? Colors.on_primary : Colors.on_secondary_container
                            }
                        }

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
                            Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredEntries.length - 1, root.selectedIndex + 1)
                            Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            Keys.onReturnPressed: root.copySelected()
                            Keys.onEnterPressed: root.copySelected()
                            Keys.onEscapePressed: root.isOpenClipB = false

                            StyledText {
                                opacity: searchField.text.length === 0 ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                anchors.verticalCenter: parent.verticalCenter
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                text: "Search clipboard history"
                            }
                        }

                        Collapse {
                            horizontal: true
                            open: searchField.text.length > 0
                            IconButton {
                                icon: "close"
                                onClicked: {
                                    searchField.text = "";
                                    searchField.forceActiveFocus();
                                }
                            }
                        }
                        Collapse {
                            horizontal: true
                            open: root.entries.length > 0
                            Button {
                                style: "text"
                                icon: "delete_sweep"
                                text: "Clear all"
                                onClicked: root.wipeAll()
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    spacing: 8

                    // ---- history list ----
                    Rectangle {
                        Layout.preferredWidth: 280
                        Layout.fillHeight: true
                        radius: Motion.shapeLarge
                        color: Colors.surface_container

                        ListView {
                            id: entryList
                            anchors.fill: parent
                            anchors.margins: 4
                            spacing: 2
                            clip: true
                            reuseItems: true
                            boundsBehavior: Flickable.StopAtBounds
                            model: root.filteredEntries
                            // kept in step by hand: a model reset makes the ListView fall back to row 0, which a plain
                            // binding would not undo
                            currentIndex: root.selectedIndex
                            onCountChanged: Qt.callLater(() => { if (entryList.currentIndex !== root.selectedIndex) entryList.currentIndex = root.selectedIndex; })
                            Connections {
                                target: root
                                function onSelectedIndexChanged() { entryList.currentIndex = root.selectedIndex; }
                            }
                            highlightFollowsCurrentItem: false
                            ScrollIntoView { id: scroller; view: entryList }

                            // wheel / flick scrolling leaves the selected row behind, so once the list settles
                            // the selection moves to the row under the pointer (or the nearest visible one)
                            HoverHandler { id: listHover }
                            onContentYChanged: if (!scroller.running) keepInView.restart()
                            Timer {
                                id: keepInView
                                interval: 90
                                onTriggered: {
                                    const it = entryList.currentItem;
                                    if (scroller.running || entryList.count === 0 || root.removingAny)
                                        return;
                                    const top = entryList.contentY, bottom = top + entryList.height;
                                    // a pooled (scrolled-out) selected row has no item: judge by its index instead
                                    const above = it ? it.y < top : root.selectedIndex < entryList.indexAt(entryList.width / 2, top + 2);
                                    if (it && it.y + it.height > top + 4 && it.y < bottom - 4)
                                        return;
                                    const y = listHover.hovered ? listHover.point.position.y : (above ? 8 : entryList.height - 8);
                                    const idx = entryList.indexAt(entryList.width / 2, top + Math.max(2, Math.min(entryList.height - 2, y)));
                                    if (idx >= 0)
                                        root.selectedIndex = idx;
                                }
                            }

                            // selected row: the two edges ride separate springs so the blob stretches
                            // toward the row it moves to and snaps back behind it
                            Rectangle {
                                id: blob
                                // in the content item so it scrolls with the rows (children of a ListView
                                // otherwise sit in the viewport)
                                parent: entryList.contentItem
                                readonly property real topT: entryList.currentItem ? entryList.currentItem.y : topE
                                readonly property real bottomT: entryList.currentItem ? entryList.currentItem.y + entryList.currentItem.height : bottomE
                                property real topE: 0
                                property real bottomE: 56
                                property real lastTop: 0
                                property bool movingDown: true
                                function sync() {
                                    if (!entryList.currentItem)
                                        return;
                                    movingDown = topT > lastTop;
                                    lastTop = topT;
                                    topE = topT;
                                    bottomE = bottomT;
                                }
                                onTopTChanged: sync()
                                onBottomTChanged: sync()
                                Behavior on topE { Spring { speed: blob.movingDown ? "default" : "fast" } }
                                Behavior on bottomE { Spring { speed: blob.movingDown ? "fast" : "default" } }

                                z: -1
                                x: 0
                                y: topE
                                width: entryList.width
                                height: Math.max(8, bottomE - topE)
                                radius: Motion.shapeMedium
                                color: Colors.secondary_container
                                visible: entryList.count > 0
                                opacity: Math.max(0, Math.min(1, root.stage / 4))
                            }

                            delegate: Clickable {
                                id: entryRow
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.selectedIndex
                                // collapsing: this row was deleted, or Clear all is sweeping through
                                property bool collapsed: false
                                readonly property bool removing: collapsed || !!root.removingIds[modelData.id]

                                // rows rise in one after another when the panel opens
                                readonly property bool shownNow: index >= 8 || root.stage > index
                                property real appear: shownNow ? 1 : 0
                                Behavior on appear { Spring { speed: "default" } }
                                // pulse on copy
                                property real pulse: root.copying && selected ? 1 : 0
                                Behavior on pulse { Spring { speed: "fast" } }
                                // 1 -> 0 as the row collapses
                                property real alive: removing ? 0 : 1
                                Behavior on alive { Spring { speed: "default" } }
                                ListView.onReused: collapsed = false
                                Connections {
                                    target: root
                                    function onWipingChanged() {
                                        if (!root.wiping) {
                                            entryRow.collapsed = false;
                                            wipeStep.stop();
                                        } else {
                                            wipeStep.interval = Math.min(entryRow.index, 8) * 30;
                                            wipeStep.restart();
                                        }
                                    }
                                }
                                Timer {
                                    id: wipeStep
                                    onTriggered: entryRow.collapsed = true
                                }

                                width: entryList.width
                                height: Math.max(0, 56 * entryRow.alive)
                                opacity: Math.max(0, Math.min(1, appear * 1.6)) * Math.max(0, Math.min(1, alive * 2 - 0.4))
                                scale: (0.94 + 0.06 * appear) * (1 + 0.05 * pulse) * (0.85 + 0.15 * Math.max(0, alive))
                                transform: Translate { y: (1 - entryRow.appear) * 16 }
                                restRadius: Motion.shapeMedium
                                pressedRadius: Motion.shapeSmall
                                contentColor: selected ? Colors.on_secondary_container : Colors.on_surface
                                onClicked: root.selectedIndex = index

                                Connections {
                                    target: entryRow.mouseArea
                                    function onDoubleClicked() { root.copySelected(); }
                                    function onPositionChanged(mouse) {
                                        if (root.removingAny)
                                            return;
                                        const p = entryRow.mapToItem(null, mouse.x, mouse.y);
                                        if (p.x === root.lastMouseX && p.y === root.lastMouseY)
                                            return;
                                        root.lastMouseX = p.x;
                                        root.lastMouseY = p.y;
                                        root.selectedIndex = entryRow.index;
                                    }
                                }

                                RowLayout {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.verticalCenter: parent.verticalCenter
                                    height: 56
                                    anchors.leftMargin: 10
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    // text is a cookie, an image is a four-sided cookie; the selected one
                                    // becomes a sunny and turns
                                    ShapeBadge {
                                        Layout.preferredWidth: 38
                                        Layout.preferredHeight: 38
                                        shapeRest: entryRow.modelData.isImage ? "cookie4" : "cookie9"
                                        shapeActive: "sunny"
                                        active: entryRow.selected
                                        spinning: entryRow.selected && entryRow.visible
                                        color: entryRow.selected ? Colors.primary : Colors.surface_container_highest
                                        Icon {
                                            anchors.centerIn: parent
                                            name: entryRow.modelData.isImage ? "image" : "notes"
                                            size: 20
                                            color: entryRow.selected ? Colors.on_primary : Colors.on_surface_variant
                                        }
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            Layout.fillWidth: true
                                            role: "bodyLarge"
                                            color: entryRow.contentColor
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                            text: entryRow.modelData.isImage ? root.formatImageDate(entryRow.modelData.id) : entryRow.modelData.preview
                                        }
                                        StyledText {
                                            role: "bodySmall"
                                            color: entryRow.selected ? Colors.on_secondary_container : Colors.on_surface_variant
                                            text: entryRow.modelData.isImage ? entryRow.modelData.ext.toUpperCase() + " image" : "Text"
                                        }
                                    }
                                }
                            }
                        }

                        // empty list: a turning shape that pops in
                        ColumnLayout {
                            id: emptyList
                            readonly property bool shown: entryList.count === 0
                            anchors.centerIn: parent
                            visible: opacity > 0.02
                            opacity: shown ? 1 : 0
                            scale: shown ? 1 : 0.6
                            spacing: 12
                            Behavior on opacity { Fade {} }
                            Behavior on scale { Spring {} }
                            ShapeBadge {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 88
                                shapeRest: root.query ? "softBurst" : "cookie9"
                                spinning: emptyList.shown && emptyList.visible
                                color: Colors.secondary_container
                                Icon {
                                    anchors.centerIn: parent
                                    size: 36
                                    name: root.query ? "search_off" : "content_paste"
                                    color: Colors.on_secondary_container
                                }
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                role: "titleMedium"
                                color: Colors.on_surface_variant
                                text: root.query ? "No matches" : "Clipboard is empty"
                            }
                        }
                    }

                    // ---- preview ----
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: Motion.shapeLarge
                        color: Colors.surface_container
                        clip: true

                        // nothing selected yet
                        ColumnLayout {
                            id: noPreview
                            readonly property bool shown: root.previewMode === "none"
                            anchors.centerIn: parent
                            visible: opacity > 0.02
                            opacity: shown ? 1 : 0
                            scale: shown ? 1 : 0.7
                            spacing: 12
                            Behavior on opacity { Fade {} }
                            Behavior on scale { Spring {} }
                            ShapeBadge {
                                Layout.alignment: Qt.AlignHCenter
                                Layout.preferredWidth: 88
                                Layout.preferredHeight: 88
                                shapeRest: "pentagon"
                                spinning: noPreview.shown && noPreview.visible
                                color: Colors.secondary_container
                                Icon { anchors.centerIn: parent; size: 36; name: "content_paste"; color: Colors.on_secondary_container }
                            }
                            StyledText {
                                Layout.alignment: Qt.AlignHCenter
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                text: "Select an item to preview"
                            }
                        }

                        // the preview slides in from the side the selection moved from and springs to rest
                        Item {
                            id: previewHolder
                            anchors.fill: parent
                            // 0 -> 1 on a spring: slide, fade and the image's corner reveal
                            property real reveal: 1
                            property bool snap: false
                            property int dir: 1
                            Behavior on reveal { enabled: !previewHolder.snap; Spring { speed: "default" } }
                            function kick() {
                                dir = root.selectedIndex < root._prevSelectedIndex ? -1 : 1;
                                snap = true;
                                reveal = 0;
                                snap = false;
                                reveal = 1;
                            }
                            opacity: Math.max(0, Math.min(1, reveal * 2.2))
                            transform: Translate { y: (1 - previewHolder.reveal) * 30 * previewHolder.dir }

                        Flickable {
                            id: previewFlick
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.bottomMargin: 72
                            opacity: root.previewMode === "text" ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            contentWidth: width
                            contentHeight: previewText.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: previewText
                                width: parent.width
                                text: root.previewText
                                color: Colors.on_surface
                                font.family: Typography.family
                                font.pixelSize: Typography.size("bodyLarge")
                                font.weight: Typography.weight("bodyLarge")
                                wrapMode: Text.Wrap
                                readOnly: true
                                selectByMouse: true
                                selectionColor: Colors.primary
                                selectedTextColor: Colors.on_primary
                            }
                        }

                        Item {
                            id: imageArea
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.bottomMargin: 72
                            opacity: root.previewMode === "image" && root.previewImagePath !== "" ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }

                            Image {
                                id: probe
                                visible: false
                                source: root.previewImagePath ? "file://" + root.previewImagePath : ""
                                asynchronous: true
                                readonly property real ratio: implicitHeight > 0 ? implicitWidth / implicitHeight : 1
                            }
                            ClippingRectangle {
                                anchors.centerIn: parent
                                readonly property real fitW: Math.min(imageArea.width, imageArea.height * probe.ratio, Math.max(1, probe.implicitWidth))
                                width: fitW
                                height: fitW / probe.ratio
                                // the image arrives as a big rounded blob and settles into its shape
                                radius: Math.max(Motion.shapeMedium, Motion.shapeExtraExtraLarge - (Motion.shapeExtraExtraLarge - Motion.shapeMedium) * previewHolder.reveal)
                                scale: 0.88 + 0.12 * previewHolder.reveal
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: probe.source
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }
                        }
                        }

                        Row {
                            id: actions
                            readonly property bool shown: root.previewMode !== "none"
                            property bool copyShown: false
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 16
                            spacing: 8
                            onShownChanged: {
                                if (shown)
                                    copyPop.restart();
                                else {
                                    copyPop.stop();
                                    copyShown = false;
                                }
                            }
                            Timer {
                                id: copyPop
                                interval: 70
                                onTriggered: actions.copyShown = true
                            }
                            Item {
                                width: deleteBtn.width
                                height: deleteBtn.height
                                opacity: actions.shown ? 1 : 0
                                scale: actions.shown ? 1 : 0.5
                                enabled: actions.shown
                                Behavior on opacity { Fade {} }
                                Behavior on scale { Spring {} }
                                Button {
                                    id: deleteBtn
                                    style: "tonal"
                                    icon: "delete"
                                    text: "Delete"
                                    color: Colors.error_container
                                    contentColor: Colors.on_error_container
                                    onClicked: root.deleteSelected()
                                }
                            }
                            Item {
                                width: copyBtn.width
                                height: copyBtn.height
                                opacity: actions.copyShown ? 1 : 0
                                scale: actions.copyShown ? 1 : 0.5
                                enabled: actions.copyShown
                                Behavior on opacity { Fade {} }
                                Behavior on scale { Spring {} }
                                Button {
                                    id: copyBtn
                                    icon: "content_copy"
                                    text: "Copy"
                                    onClicked: root.copySelected()
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
