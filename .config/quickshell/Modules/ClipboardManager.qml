pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components

// Clipboard history (cliphist) as an M3 search view: list + preview, copy / delete.
// Also shows the "Copied" snackbar whenever something new lands on the clipboard.
Item {
    id: root

    property var copyToast

    property bool isOpenClipB: false
    property string query: ""
    onIsOpenClipBChanged: if (isOpenClipB) searchField.forceActiveFocus()
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

    function refreshList() {
        root.selectedIndex = 0;
        root._prevSelectedIndex = 0;
        root._lastRecordedIndex = 0;
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
            root.isOpenClipB = false;
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
        deleteProc.stdinEnabled = true;
        deleteProc.running = false;
        deleteProc.running = true;
        deleteWriteTimer.callback = () => {
            deleteProc.write(entry.raw + "\n");
            deleteProc.stdinEnabled = false;
        };
        deleteWriteTimer.restart();
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
    Timer {
        id: deleteWriteTimer
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
                    if (root.copyToast)
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
        command: ["wl-paste", "--watch", "echo", "changed"]
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
            root.refreshList();
            root.selectedEntry = null;
            root.previewMode = "none";
        }
    }

    Process {
        id: wipeProc
        command: ["cliphist", "wipe"]
        onExited: {
            timestampsAdapter.timestamps = {};
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
        visible: root.isOpenClipB || panel.opacity > 0

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

        Rectangle {
            id: panel
            width: 720
            height: 480
            anchors.horizontalCenter: parent.horizontalCenter
            y: 240
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            transformOrigin: Item.Top
            opacity: root.isOpenClipB ? 1 : 0
            scale: root.isOpenClipB ? 1 : 0.92
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }

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
                        anchors.rightMargin: 8
                        spacing: 16

                        Icon { name: searchField.text.length > 0 ? "search" : "content_paste"; color: Colors.on_surface }

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
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                text: "Search clipboard history"
                            }
                        }

                        IconButton {
                            visible: searchField.text.length > 0
                            icon: "close"
                            onClicked: {
                                searchField.text = "";
                                searchField.forceActiveFocus();
                            }
                        }
                        Button {
                            visible: root.entries.length > 0
                            style: "text"
                            icon: "delete_sweep"
                            text: "Clear all"
                            onClicked: wipeProc.running = true
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
                            currentIndex: root.selectedIndex
                            highlightFollowsCurrentItem: false
                            ScrollIntoView { view: entryList }
                            highlight: Rectangle {
                                width: entryList.width
                                height: 56
                                radius: Motion.shapeMedium
                                color: Colors.secondary_container
                                y: entryList.currentItem ? entryList.currentItem.y : 0
                                visible: entryList.count > 0
                                Behavior on y { Spring {} }
                            }

                            delegate: Clickable {
                                id: entryRow
                                required property var modelData
                                required property int index
                                readonly property bool selected: index === root.selectedIndex

                                width: entryList.width
                                height: 56
                                restRadius: Motion.shapeMedium
                                pressedRadius: Motion.shapeSmall
                                contentColor: selected ? Colors.on_secondary_container : Colors.on_surface
                                onClicked: root.selectedIndex = index

                                Connections {
                                    target: entryRow.mouseArea
                                    function onDoubleClicked() { root.copySelected(); }
                                    function onPositionChanged(mouse) {
                                        const p = entryRow.mapToItem(null, mouse.x, mouse.y);
                                        if (p.x === root.lastMouseX && p.y === root.lastMouseY)
                                            return;
                                        root.lastMouseX = p.x;
                                        root.lastMouseY = p.y;
                                        root.selectedIndex = entryRow.index;
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 12
                                    anchors.rightMargin: 12
                                    spacing: 12
                                    Icon {
                                        name: entryRow.modelData.isImage ? "image" : "notes"
                                        size: 20
                                        color: entryRow.selected ? Colors.on_secondary_container : Colors.on_surface_variant
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

                            StyledText {
                                anchors.centerIn: parent
                                visible: entryList.count === 0
                                role: "bodyLarge"
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

                        StyledText {
                            anchors.centerIn: parent
                            visible: root.previewMode === "none"
                            role: "bodyLarge"
                            color: Colors.on_surface_variant
                            text: "Select an item to preview"
                        }

                        Flickable {
                            id: previewFlick
                            anchors.fill: parent
                            anchors.margins: 16
                            anchors.bottomMargin: 72
                            visible: root.previewMode === "text"
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
                            visible: root.previewMode === "image" && root.previewImagePath !== ""

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
                                radius: Motion.shapeMedium
                                color: "transparent"
                                Image {
                                    anchors.fill: parent
                                    source: probe.source
                                    fillMode: Image.PreserveAspectFit
                                    asynchronous: true
                                }
                            }
                        }

                        Row {
                            visible: root.previewMode !== "none"
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            anchors.margins: 16
                            spacing: 8
                            Button {
                                style: "tonal"
                                icon: "delete"
                                text: "Delete"
                                color: Colors.error_container
                                contentColor: Colors.on_error_container
                                onClicked: root.deleteSelected()
                            }
                            Button {
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
