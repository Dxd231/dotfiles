pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects

Item {
    

    id: root

    property var theme
    property var settings
    property int global_radius: 8

    property bool isOpenClipB: false
    property string query: ""
    property var entries: []          
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

    onQueryChanged: root.selectedIndex = 0
    onFilteredEntriesChanged: {
        if (root.selectedIndex >= root.filteredEntries.length)
            root.selectedIndex = Math.max(0, root.filteredEntries.length - 1);
        if (root.filteredEntries.length > 0)
            root.selectEntry(root.filteredEntries[root.selectedIndex]);
        else {
            root.selectedEntry = null;
            root.previewMode = "none";
        }
    }
    onSelectedIndexChanged: {
        if (root.filteredEntries.length > 0 && root.selectedIndex >= 0)
            root.selectEntry(root.filteredEntries[root.selectedIndex]);
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

    function selectEntry(entry) {
        root.selectedEntry = entry;
        if (entry.isImage) {
            root.previewMode = "image";
            root.previewImagePath = "";  
            const path = "/tmp/qs-clip-" + entry.id + "." + entry.ext;
            decodeToFileProc.command = ["sh", "-c", "cliphist decode > '" + path + "'"];
            decodeToFileProc.pendingPath = path;
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
        id: decodeToTextProc
        command: ["cliphist", "decode"]
        stdout: StdioCollector {
            onStreamFinished: root.previewText = text
        }
    }

    Process {
        id: decodeToFileProc
        property string pendingPath: ""
        command: ["true"]
        onExited: root.previewImagePath = decodeToFileProc.pendingPath
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
        implicitHeight: 550
        visible: root.isOpenClipB || panelBg.opacity > 0

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenClipB = false
        }

        Rectangle {
            id: panelBg
            width: 630
            height: 450
            x: 1920 / 2 - width / 2
            radius: 18
            border.width: 1
            border.color: root.theme.surface_bright
            color: Qt.alpha(root.theme.background, 0.8)
            clip: true
            opacity: 0
            y: -270

            states: [
                State {
                    name: "open"
                    when: root.isOpenClipB
                    PropertyChanges {
                        target: panelBg
                        y: 6
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !root.isOpenClipB
                    PropertyChanges {
                        target: panelBg
                        y: -270
                        opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "open"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 260
                        easing.type: Easing.OutCirc
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 260
                        easing.type: Easing.InCirc
                    }
                }
            ]
            
            Image {
                source: "../assets/yukari.png"
                sourceSize.width: 400
                sourceSize.height: 400
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.verticalCenter: parent.verticalCenter
                fillMode: Image.PreserveAspectFit
                opacity: 0.1
                z: 0
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // ---- search bar, styled like AppLauncher's ----
                Item {
                    width: parent.width
                    height: 42

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        height: 42
                        radius: 18
                        color: Qt.alpha(root.theme.on_background, 0.08)
                        border.width: 0
                        border.color: searchField.activeFocus ? root.theme.source_color : Qt.alpha(root.theme.surface_bright, 0.6)

                        Behavior on border.color {
                            ColorAnimation { duration: 120 }
                        }

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 14
                            anchors.rightMargin: 14
                            spacing: 10

                            Image {
                                source: "../assets/magnifying-glass-bold.svg"
                                anchors.verticalCenter: parent.verticalCenter
                                width: 20
                                height: 20
                                sourceSize.width: 22
                                sourceSize.height: 22
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.theme.source_color
                                } 
                            }

                            TextInput {
                                id: searchField
                                width: parent.width - 30
                                anchors.verticalCenter: parent.verticalCenter
                                text: root.query
                                color: root.theme.on_background
                                font.pixelSize: 15
                                font.family: root.settings.fontdefault
                                //renderType: Text.NativeRendering
                                //font.hintingPreference: Font.PreferFullHinting
                                clip: true

                                onTextChanged: root.query = text

                                Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredEntries.length - 1, root.selectedIndex + 1)
                                Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                                Keys.onReturnPressed: root.copySelected()
                                Keys.onEnterPressed: root.copySelected()
                                Keys.onEscapePressed: root.isOpenClipB = false

                                Text {
                                    visible: parent.text.length === 0
                                    text: "Search clipboard history\u2026"
                                    color: root.theme.on_background
                                    opacity: 0.4
                                    font.pixelSize: 15
                                    font.family: root.settings.fontdefault
                                    //renderType: Text.NativeRendering
                                    //font.hintingPreference: Font.PreferFullHinting
                                }
                            }
                        }
                    }
                }

                // ---- body: list (left) + preview (right) ----
                Row {
                    width: parent.width
                    height: parent.height - 44
                    spacing: 14

                    // left: list
                    Rectangle {
                        width: 240
                        height: parent.height
                        radius: root.global_radius
                        color: Qt.alpha(root.theme.background, 0.05)
                        border.width: 0
                        border.color: Qt.alpha(root.theme.surface_bright, 0.5)
                        clip: true

                        ListView {
                            id: entryList
                            anchors.fill: parent
                            anchors.margins: 6
                            spacing: 4
                            clip: true
                            model: root.filteredEntries
                            currentIndex: root.selectedIndex
                            highlightMoveDuration: 150
                            highlightMoveVelocity: -1
                            highlightFollowsCurrentItem: true
                            highlightResizeDuration: 0

                            highlight: Rectangle {
                                radius: root.global_radius
                                color: Qt.alpha(root.theme.source_color, 0.5)
                            }

                            delegate: Rectangle {
                                id: entryRow
                                required property var modelData
                                required property int index
                                width: entryList.width
                                height: 48
                                radius: root.global_radius
                                property bool isSelected: index === root.selectedIndex
                                color: "transparent"

                                Row {
                                    anchors.fill: parent
                                    anchors.leftMargin: 8
                                    anchors.rightMargin: 8
                                    spacing: 10

                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: 32
                                        height: 32
                                        radius: 8
                                        color: entryRow.isSelected ? Qt.alpha(root.theme.background, 0.2) : Qt.alpha(root.theme.on_background, 0.08)

                                        Image {
                                            anchors.centerIn: parent
                                            source: entryRow.modelData.isImage ? "../assets/image.svg" : "../assets/text.svg"
                                            width: 20
                                            height: 20
                                            sourceSize.width: 22
                                            sourceSize.height: 22
                                            fillMode: Image.PreserveAspectFit
                                            layer.enabled: true
                                            layer.effect: MultiEffect {
                                                colorization: 1.0
                                                colorizationColor: entryRow.isSelected ? root.theme.on_background : root.theme.source_color 
                                            } 
                                        }
                                    }

                                    Column {
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: parent.width - 50
                                        spacing: 1

                                        Text {
                                            width: parent.width
                                            text: entryRow.modelData.isImage ? "Image" : entryRow.modelData.preview
                                            color: entryRow.isSelected ? root.theme.background : root.theme.on_background
                                            font.pixelSize: 16
                                            font.bold: false
                                            font.family: root.settings.fontmedium
                                            //renderType: Text.NativeRendering
                                            //font.hintingPreference: Font.PreferFullHinting
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            width: parent.width
                                            text: entryRow.modelData.isImage ? entryRow.modelData.ext.toUpperCase() : "Text"
                                            color: entryRow.isSelected ? Qt.alpha(root.theme.background, 0.7) : root.theme.on_background
                                            opacity: entryRow.isSelected ? 1.0 : 0.55
                                            //renderType: Text.NativeRendering
                                            //font.hintingPreference: Font.PreferFullHinting
                                            font.pixelSize: 13
                                            font.family: root.settings.fontdefault
                                        }
                                    }
                                }

                                MouseArea {
                                    id: hoverArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.selectedIndex = entryRow.index
                                }
                            }

                            Text {
                                anchors.centerIn: parent
                                visible: entryList.count === 0
                                text: "No clipboard history"
                                color: root.theme.on_background
                                opacity: 0.4
                                font.pixelSize: 12
                                font.family: root.settings.fontdefault
                                //renderType: Text.NativeRendering
                                //font.hintingPreference: Font.PreferFullHinting
                            }
                        }
                    }

                    // right: big preview
                    Rectangle {
                        width: parent.width - 254
                        height: parent.height
                        radius: root.global_radius
                        color: Qt.alpha(root.theme.background, 0.05)
                        border.width: 0
                        border.color: Qt.alpha(root.theme.surface_bright, 0.5)
                        clip: true

                        Text {
                            anchors.centerIn: parent
                            visible: root.previewMode === "none"
                            text: "Select an item to preview"
                            color: root.theme.on_background
                            opacity: 0.4
                            font.pixelSize: 13
                            font.family: root.settings.fontdefault
                        }

                        Flickable {
                            id: previewFlick
                            anchors.fill: parent
                            anchors.margins: 14
                            anchors.bottomMargin: 54
                            anchors.rightMargin: 20
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
                                //renderType: TextEdit.NativeRendering
                                wrapMode: Text.Wrap
                                readOnly: true
                                selectByMouse: true
                                selectionColor: root.theme.source_color
                                persistentSelection: true
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: root.previewMode === "text" && root.previewText === ""
                            text: ""
                            color: root.theme.on_background
                            opacity: 0.35
                            font.pixelSize: 12
                            font.family: root.settings.fontdefault
                        }

                        //scroll bar
                        Rectangle {
                            visible: root.previewMode === "text" && previewFlick.contentHeight > previewFlick.height
                            anchors.top: previewFlick.top
                            anchors.right: parent.right
                            anchors.rightMargin: 6
                            width: 4
                            radius: 2
                            color: Qt.alpha(root.theme.on_background, 0.2)
                            height: previewFlick.height

                            property real handleHeight: Math.max(24, previewFlick.height * (previewFlick.height / previewFlick.contentHeight))
                            property real handleY: (previewFlick.contentY / Math.max(1, previewFlick.contentHeight - previewFlick.height)) * (previewFlick.height - handleHeight)

                            Rectangle {
                                width: parent.width
                                radius: 2
                                color: Qt.alpha(root.theme.source_color, 0.5)
                                y: parent.handleY
                                height: parent.handleHeight
                            }
                        }

                        Image {
                            anchors.top: parent.top
                            anchors.horizontalCenter: parent.horizontalCenter
                            anchors.bottom: parent.bottom
                            anchors.margins: 14
                            anchors.bottomMargin: 54
                            visible: root.previewMode === "image" && root.previewImagePath !== ""
                            source: root.previewImagePath ? ("file://" + root.previewImagePath) : ""
                            fillMode: Image.PreserveAspectFit
                            asynchronous: true
                        }

                        // action bar
                        Row {
                            visible: root.previewMode !== "none"
                            anchors.bottom: parent.bottom
                            anchors.right: parent.right
                            anchors.margins: 12
                            spacing: 8

                            Rectangle {
                                width: deleteLabel.implicitWidth + 22
                                height: 30
                                radius: root.global_radius
                                color: Qt.alpha(root.theme.background, deleteArea.containsMouse ? 0.14 : 0.07)
                                border.width: 0
                                border.color: root.theme.surface_bright

                                Text {
                                    id: deleteLabel
                                    anchors.centerIn: parent
                                    text: "Delete"
                                    color: root.theme.on_background
                                    font.pixelSize: 12
                                    font.family: root.settings.fontdefault
                                    font.underline: deleteArea.containsMouse ? true : false
                                }
                                MouseArea {
                                    id: deleteArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.deleteSelected();
                                    }
                                }
                            }

                            /* Rectangle {
                                width: copyLabel.implicitWidth + 22
                                height: 30
                                radius: root.global_radius
                                color: Qt.alpha(root.theme.source_color, copyArea.containsMouse ? 0.8 : 1)
                                border.width: 1
                                border.color: root.theme.source_color

                                Text {
                                    id: copyLabel
                                    anchors.centerIn: parent
                                    text: "Copy"
                                    color: root.theme.on_background
                                    font.pixelSize: 12
                                    font.bold: true
                                    font.family: root.settings.fontdefault
                                }
                                MouseArea {
                                    id: copyArea
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.copySelected()
                                }
                            } */
                        }
                    }
                }
            }
        }
    }
}
