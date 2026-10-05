pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

Item {
    id: root

    property var theme
    property var settings
    property var copyToast
    property int global_radius: 8

    property bool isOpenClipB: false
    property string query: ""
    onIsOpenClipBChanged: {
        if (isOpenClipB) {
            closeAnim.stop();
            openAnim.restart();
            searchField.forceActiveFocus();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }
    property var entries: []          
    property var knownClipboardIds: ({})
    property bool hasClipboardBaseline: false
    property var selectedEntry: null
    property int selectedIndex: 0
    property string previewMode: "none" 
    property string previewText: ""
    property string previewImagePath: ""

    property var filteredEntries: {
        const q = root.query.trim().toLowerCase();
        if (q === "")
            return root.entries;
        return root.entries.filter(e => e.preview.toLowerCase().includes(q));
    }

    // How long the selection has to stay put before we actually decode/preview it.
    // Prevents spamming `cliphist decode` processes when scrolling/arrow-keying fast.
    property int selectionDebounceMs: 120

    onQueryChanged: root.selectedIndex = 0
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
                const ids = text.split("\n")
                    .map(line => root.parseLine(line))
                    .filter(entry => entry !== null)
                    .map(entry => entry.id);

                if (root.hasClipboardBaseline && ids.length > 0 && !root.knownClipboardIds[ids[0]]) {
                    if (root.copyToast)
                        root.copyToast.showToast("Copied to clipboard");
                }

                const known = Object.assign({}, root.knownClipboardIds);
                ids.forEach(id => known[id] = true);
                root.knownClipboardIds = known;
                root.hasClipboardBaseline = true;
            }
        }
    }

    Timer {
        interval: 500
        running: true
        repeat: true
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
        anchors.top: true
        anchors.left: true
        anchors.right: true
        exclusiveZone: 0
        color: "transparent"
        margins.top: 0
        margins.left: 0
        margins.right: 0
        implicitHeight: 1000
        property bool animatingClosed: false
        visible: root.isOpenClipB || animatingClosed

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenClipB = false
        }

        Rectangle {
            id: panelBg
            width: 660
            height: 440
            anchors.horizontalCenter: parent.horizontalCenter
            y: 250
            radius: 18
            border.width: 0
            color: Qt.lighter(root.theme.background, 1.15)
            clip: true
            transformOrigin: Item.Top
            scale: 0.90
            opacity: 0
            transform: Translate {
                id: dropTrans
                y: -18
            }

            ParallelAnimation {
                id: closeAnim

                onStarted: panelWindow.animatingClosed = true
                onStopped: panelWindow.animatingClosed = false

                NumberAnimation { target: content; property: "opacity"; to: 0; duration: 120; easing.type: Easing.InQuad }
                NumberAnimation { target: panelBg; property: "scale"; to: 0.90; duration: 180; easing.type: Easing.InCirc }
                NumberAnimation { target: dropTrans; property: "y"; to: -18; duration: 180; easing.type: Easing.InCirc }
                NumberAnimation { target: panelBg; property: "opacity"; to: 0; duration: 160; easing.type: Easing.InQuad }
            }

            ParallelAnimation {
                id: openAnim
                NumberAnimation { target: panelBg; property: "opacity"; to: 1.0; duration: 180; easing.type: Easing.OutQuad }
                NumberAnimation {
                    target: panelBg
                    property: "scale"
                    to: 1.0
                    duration: 240
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.12
                }
                NumberAnimation {
                    target: dropTrans
                    property: "y"
                    to: 0
                    duration: 240
                    easing.type: Easing.OutBack
                    easing.overshoot: 1.12
                }
                NumberAnimation {
                    target: content
                    property: "opacity"
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutQuad
                }
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                id: content
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10
                opacity: 0

                // Search field
                Rectangle {
                    id: searchContainer
                    width: parent.width
                    height: 46
                    radius: 14
                    color: Qt.alpha(root.theme.on_background, 0.06)
                    border.width: 0

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 12
                        spacing: 10

                        Image {
                            id: searchIcon
                            Layout.alignment: Qt.AlignVCenter
                            source: "../assets/magnifying-glass-bold.svg"
                            Layout.preferredWidth: 20
                            Layout.preferredHeight: 20
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: root.theme.primary
                            }
                        }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            text: root.query
                            color: root.theme.on_background
                            font.pixelSize: 17
                            font.family: root.settings.fontdefault
                            clip: true

                            onTextChanged: root.query = text

                            Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredEntries.length - 1, root.selectedIndex + 1)
                            Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            Keys.onReturnPressed: root.copySelected()
                            Keys.onEnterPressed: root.copySelected()
                            Keys.onEscapePressed: root.isOpenClipB = false

                            Text {
                                visible: parent.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search clipboard history\u2026"
                                color: root.theme.on_background
                                opacity: 0.4
                                font.pixelSize: 17
                                font.family: root.settings.fontdefault
                            }
                        }

                        Item {
                            id: clearBtn
                            Layout.alignment: Qt.AlignVCenter
                            Layout.preferredWidth: 26
                            Layout.preferredHeight: 26
                            visible: searchField.text.length > 0

                            Rectangle {
                                anchors.fill: parent
                                radius: 8
                                color: clearHover.containsMouse ? Qt.alpha(root.theme.on_background, 0.12) : "transparent"

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u2715"
                                    font.pixelSize: 14
                                    font.family: root.settings.fontdefault
                                    color: clearHover.containsMouse ? root.theme.primary : root.theme.on_background
                                    opacity: clearHover.containsMouse ? 1.0 : 0.6
                                }
                            }

                            MouseArea {
                                id: clearHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    searchField.text = "";
                                    root.query = "";
                                    searchField.forceActiveFocus();
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: separator
                    height: 1
                    width: parent.width
                    color: Qt.alpha(root.theme.on_background, 0.08)
                }

                // Body: list (left) + preview (right)
                RowLayout {
                    width: parent.width
                    height: content.height - searchContainer.height - separator.height - content.spacing * 2
                    spacing: 10

                    // Left list container
                    Rectangle {
                        Layout.preferredWidth: 250
                        Layout.fillHeight: true
                        radius: 14
                        color: Qt.alpha(root.theme.on_background, 0.04)
                        border.width: 0
                        clip: true

                        ListView {
                            id: entryList
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4
                            clip: true
                            reuseItems: true
                            model: root.filteredEntries
                            currentIndex: root.selectedIndex
                            highlightMoveDuration: 140
                            highlightMoveVelocity: -1
                            highlightFollowsCurrentItem: true
                            highlightResizeDuration: 0

                            highlight: Rectangle {
                                radius: 12
                                color: Qt.alpha(root.theme.primary, 0.85)
                                border.width: 0
                            }

                            delegate: Item {
                                id: entryRow
                                required property var modelData
                                required property int index
                                width: entryList.width
                                height: 52
                                readonly property bool isSelected: entryRow.index === root.selectedIndex

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 12
                                    color: hoverArea.containsMouse && !entryRow.isSelected
                                        ? Qt.alpha(root.theme.on_background, 0.06)
                                        : "transparent"

                                    Behavior on color {
                                        ColorAnimation { duration: 120 }
                                    }
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedIndex = entryRow.index
                                    onDoubleClicked: root.copySelected()
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 10

                                    Rectangle {
                                        Layout.alignment: Qt.AlignVCenter
                                        Layout.preferredWidth: 32
                                        Layout.preferredHeight: 32
                                        radius: 8
                                        color: entryRow.isSelected
                                            ? Qt.alpha(root.theme.background, 0.22)
                                            : Qt.alpha(root.theme.on_background, 0.06)

                                        Image {
                                            anchors.centerIn: parent
                                            source: entryRow.modelData.isImage ? "../assets/image.svg" : "../assets/text.svg"
                                            width: 18
                                            height: 18
                                            sourceSize.width: 20
                                            sourceSize.height: 20
                                            fillMode: Image.PreserveAspectFit
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                colorization: 1.0
                                                colorizationColor: entryRow.isSelected ? root.theme.background : root.theme.primary
                                            }
                                        }
                                    }

                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        Layout.alignment: Qt.AlignVCenter
                                        spacing: 1

                                        Text {
                                            Layout.fillWidth: true
                                            text: entryRow.modelData.isImage ? "Image" : entryRow.modelData.preview
                                            color: entryRow.isSelected ? root.theme.background : root.theme.on_background
                                            font.pixelSize: 16
                                            font.family: root.settings.fontmedium
                                            elide: Text.ElideRight
                                            maximumLineCount: 1

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }
                                        }

                                        Text {
                                            Layout.fillWidth: true
                                            text: entryRow.modelData.isImage ? entryRow.modelData.ext.toUpperCase() : "Text"
                                            color: entryRow.isSelected ? Qt.alpha(root.theme.background, 0.72) : Qt.alpha(root.theme.on_background, 0.55)
                                            font.pixelSize: 13
                                            font.family: root.settings.fontdefault

                                            Behavior on color {
                                                ColorAnimation { duration: 120 }
                                            }
                                        }
                                    }
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: entryList.count === 0
                                text: "No clipboard history"
                                color: root.theme.on_background
                                opacity: 0.4
                                font.pixelSize: 15
                                font.family: root.settings.fontdefault
                            }
                        }
                    }

                    // Right preview container
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        radius: 14
                        color: Qt.alpha(root.theme.on_background, 0.04)
                        border.width: 0
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: root.previewMode === "none"
                            text: "Select an item to preview"
                            color: root.theme.on_background
                            opacity: 0.4
                            font.pixelSize: 15
                            font.family: root.settings.fontdefault
                        }

                        Flickable {
                            id: previewFlick
                            anchors.fill: parent
                            anchors.margins: 14
                            anchors.bottomMargin: 52
                            anchors.rightMargin: 16
                            visible: root.previewMode === "text"
                            contentWidth: width
                            contentHeight: previewTextLabel.implicitHeight
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            TextEdit {
                                id: previewTextLabel
                                width: parent.width
                                text: root.previewText
                                color: root.theme.on_background
                                font.pixelSize: 16
                                font.family: root.settings.fontdefault
                                wrapMode: Text.Wrap
                                readOnly: true
                                selectByMouse: true
                                selectionColor: root.theme.primary
                                selectedTextColor: root.theme.background
                                persistentSelection: true
                            }
                        }

                        // Scroll bar
                        Rectangle {
                            visible: root.previewMode === "text" && previewFlick.contentHeight > previewFlick.height
                            anchors.top: previewFlick.top
                            anchors.right: parent.right
                            anchors.rightMargin: 4
                            width: 3
                            radius: 2
                            color: Qt.alpha(root.theme.on_background, 0.1)
                            height: previewFlick.height

                            property real handleHeight: Math.max(20, previewFlick.height * (previewFlick.height / previewFlick.contentHeight))
                            property real handleY: (previewFlick.contentY / Math.max(1, previewFlick.contentHeight - previewFlick.height)) * (previewFlick.height - handleHeight)

                            Rectangle {
                                width: parent.width
                                radius: 2
                                color: Qt.alpha(root.theme.primary, 0.7)
                                y: parent.handleY
                                height: parent.handleHeight
                            }
                        }

                        Image {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.margins: 14
                            anchors.bottomMargin: 52
                            visible: root.previewMode === "image" && root.previewImagePath !== ""
                            source: root.previewImagePath ? ("file://" + root.previewImagePath) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        // Action bar
                        Row {
                            visible: root.previewMode !== "none"
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 10
                            spacing: 8

                            Rectangle {
                                width: deleteRow.implicitWidth + 22
                                height: 32
                                radius: 10
                                color: deleteArea.containsMouse ? Qt.alpha(root.theme.error, 0.25) : Qt.alpha(root.theme.on_background, 0.06)
                                border.width: 0

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    id: deleteRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: "../assets/trash-simple-bold.svg"
                                        sourceSize.width: 15
                                        sourceSize.height: 15
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.theme.error
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Delete"
                                        color: root.theme.error
                                        font.pixelSize: 13
                                        font.family: root.settings.fontmedium
                                    }
                                }

                                MouseArea {
                                    id: deleteArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.deleteSelected()
                                }
                            }

                            Rectangle {
                                width: copyRow.implicitWidth + 22
                                height: 32
                                radius: 10
                                color: copyArea.containsMouse ? Qt.lighter(root.theme.primary, 1.1) : root.theme.primary
                                border.width: 0

                                Behavior on color { ColorAnimation { duration: 120 } }

                                Row {
                                    id: copyRow
                                    anchors.centerIn: parent
                                    spacing: 6

                                    Image {
                                        anchors.verticalCenter: parent.verticalCenter
                                        source: "../assets/check-fat-fill.svg"
                                        sourceSize.width: 14
                                        sourceSize.height: 14
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: root.theme.background
                                        }
                                    }

                                    Text {
                                        anchors.verticalCenter: parent.verticalCenter
                                        text: "Copy"
                                        color: root.theme.background
                                        font.pixelSize: 13
                                        font.family: root.settings.fontmedium
                                    }
                                }

                                MouseArea {
                                    id: copyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
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
