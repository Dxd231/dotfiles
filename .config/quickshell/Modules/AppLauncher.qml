pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import QtQuick.Effects

Item {
    id: root

    property var theme
    property var settings
    property int global_radius: 50

    property bool isOpenLauncher: false
    property string query: ""
    property int selectedIndex: 0
    // last real mouse position (scene coords); used so hover only selects when the mouse actually moves
    property real lastMouseX: -1
    property real lastMouseY: -1

    onIsOpenLauncherChanged: {
        if (isOpenLauncher) {
            closeAnim.stop();
            openAnim.restart();
            searchField.forceActiveFocus();
        } else {
            openAnim.stop();
            closeAnim.restart();
        }
    }   

    FileView {
        id: pinsFile
        path: Quickshell.dataPath("app-launcher-pins.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: pinsAdapter
            property list<string> pinnedIds: []
            property var launchCounts: ({})
        }
    }

    function isPinned(id) {
        return pinsAdapter.pinnedIds.indexOf(id) !== -1;
    }
    function togglePin(id) {
        const list = pinsAdapter.pinnedIds.slice();
        const idx = list.indexOf(id);
        if (idx === -1)
            list.push(id);
        else
            list.splice(idx, 1);
        pinsAdapter.pinnedIds = list;
    }
    function launchCount(id) {
        return pinsAdapter.launchCounts[id] || 0;
    }
    function recordLaunch(id) {
        const counts = Object.assign({}, pinsAdapter.launchCounts);
        counts[id] = (counts[id] || 0) + 1;
        pinsAdapter.launchCounts = counts;
    }

    property var allApps: {
        const apps = [...DesktopEntries.applications.values].filter(e => e.name && !e.noDisplay);

            apps.sort((a, b) => {
            const aPinned = root.isPinned(a.id);
            const bPinned = root.isPinned(b.id);
            if (aPinned !== bPinned)
                return aPinned ? -1 : 1;

            const aCount = root.launchCount(a.id);
            const bCount = root.launchCount(b.id);
            if (aCount !== bCount)
                return bCount - aCount;

            return a.name.localeCompare(b.name);
        });
        return apps;
    }

    property var filteredApps: {
        const q = root.query.trim().toLowerCase();
        if (q === "")
            return root.allApps;
        return root.allApps.filter(e => {
            if ((e.name || "").toLowerCase().includes(q))
                return true;
            if ((e.genericName || "").toLowerCase().includes(q))
                return true;
            if ((e.comment || "").toLowerCase().includes(q))
                return true;
            for (const kw of (e.keywords || [])) {
                if ((kw || "").toLowerCase().includes(q))
                    return true;
            }
            return false;
        });
    }

    onQueryChanged: root.selectedIndex = 0
    onFilteredAppsChanged: if (root.selectedIndex >= root.filteredApps.length)
        root.selectedIndex = Math.max(0, root.filteredApps.length - 1)

    function launch(entry) {
        if (!entry)
            return;
        root.recordLaunch(entry.id);
        entry.execute();
        root.query = "";
        root.isOpenLauncher = false;
        root.query = ""
        root.selectedIndex = 0
    }

    IpcHandler {
        target: "launcher"

        function toggle(): void {
            root.isOpenLauncher = !root.isOpenLauncher;
            root.query = ""
            root.selectedIndex = 0
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
        visible: root.isOpenLauncher || animatingClosed

        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenLauncher = false
        }

        Rectangle {
            id: panelBg
            width: 640
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
                NumberAnimation {
                    target: panelBg
                    property: "opacity"
                    to: 1.0
                    duration: 180
                    easing.type: Easing.OutQuad
                }
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

                // ---- search field ----
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

                            Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                            Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            Keys.onReturnPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEnterPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEscapePressed: root.isOpenLauncher = false

                            Text {
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                text: "Search applications\u2026"
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

                // ---- results ----
                ListView {
                    id: resultsList
                    width: parent.width
                    height: content.height - searchContainer.height - separator.height - content.spacing * 2
                    focus: true
                    clip: true
                    reuseItems: true
                    model: root.filteredApps
                    currentIndex: root.selectedIndex
                    highlightMoveDuration: 140
                    highlightMoveVelocity: -1
                    snapMode: ListView.SnapToItem
                    highlightFollowsCurrentItem: true
                    highlightResizeDuration: 0

                    highlight: Rectangle {
                        radius: 14
                        color: Qt.alpha(root.theme.primary, 0.85)
                        border.width: 0
                    }

                    delegate: Item {
                        id: rowItem
                        required property var modelData
                        required property int index
                        width: resultsList.width
                        height: 52

                        readonly property bool isCurrent: rowItem.index === root.selectedIndex

                        Rectangle {
                            anchors.fill: parent
                            radius: 14
                            color: rowHover.containsMouse && !rowItem.isCurrent
                                ? Qt.alpha(root.theme.on_background, 0.06)
                                : "transparent"

                            Behavior on color {
                                ColorAnimation { duration: 120 }
                            }
                        }

                        MouseArea {
                            id: rowHover
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onPositionChanged: mouse => {
                                const p = mapToItem(null, mouse.x, mouse.y);
                                if (p.x === root.lastMouseX && p.y === root.lastMouseY)
                                    return;
                                root.lastMouseX = p.x;
                                root.lastMouseY = p.y;
                                root.selectedIndex = rowItem.index;
                            }
                            onClicked: root.launch(rowItem.modelData)
                        }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 10
                            spacing: 12

                            Rectangle {
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 36
                                Layout.preferredHeight: 36
                                radius: 10
                                color: rowItem.isCurrent
                                    ? Qt.alpha(root.theme.background, 0.22)
                                    : Qt.alpha(root.theme.on_background, 0.06)

                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 26
                                    source: Quickshell.iconPath(rowItem.modelData.icon, true)
                                }
                            }

                            ColumnLayout {
                                Layout.fillWidth: true
                                Layout.alignment: Qt.AlignVCenter
                                spacing: 2

                                Text {
                                    Layout.fillWidth: true
                                    text: rowItem.modelData.name
                                    color: rowItem.isCurrent ? root.theme.background : root.theme.on_background
                                    font.pixelSize: 17
                                    font.family: root.settings.fontmedium
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        ColorAnimation { duration: 120 }
                                    }
                                }

                                Text {
                                    Layout.fillWidth: true
                                    visible: text.length > 0
                                    text: rowItem.modelData.genericName || rowItem.modelData.comment || ""
                                    color: rowItem.isCurrent ? Qt.alpha(root.theme.background, 0.72) : Qt.alpha(root.theme.on_background, 0.55)
                                    font.pixelSize: 13
                                    font.family: root.settings.fontdefault
                                    elide: Text.ElideRight

                                    Behavior on color {
                                        ColorAnimation { duration: 120 }
                                    }
                                }
                            }

                            Item {
                                id: pinButton
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 28
                                visible: root.isPinned(rowItem.modelData.id) || rowHover.containsMouse

                                Rectangle {
                                    anchors.fill: parent
                                    radius: 8
                                    color: pinHover.containsMouse
                                        ? (rowItem.isCurrent ? Qt.alpha(root.theme.background, 0.2) : Qt.alpha(root.theme.on_background, 0.1))
                                        : "transparent"

                                    Image {
                                        anchors.centerIn: parent
                                        source: root.isPinned(rowItem.modelData.id)
                                            ? "../assets/push-pin-fill.svg"
                                            : "../assets/push-pin-bold.svg"
                                        sourceSize.width: 17
                                        sourceSize.height: 17
                                        fillMode: Image.PreserveAspectFit
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            colorization: 1.0
                                            colorizationColor: rowItem.isCurrent
                                                ? root.theme.background
                                                : (root.isPinned(rowItem.modelData.id) ? root.theme.primary : Qt.alpha(root.theme.on_background, 0.5))
                                        }
                                    }
                                }

                                MouseArea {
                                    id: pinHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.togglePin(rowItem.modelData.id)
                                }
                            }
                        }
                    }

                    // simple empty state
                    ColumnLayout {
                        anchors.centerIn: parent
                        visible: resultsList.count === 0
                        spacing: 8

                        Image {
                            Layout.alignment: Qt.AlignHCenter
                            source: "../assets/magnifying-glass-bold.svg"
                            Layout.preferredWidth: 30
                            Layout.preferredHeight: 30
                            sourceSize.width: 30
                            sourceSize.height: 30
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: Qt.alpha(root.theme.on_background, 0.3)
                            }
                        }

                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            text: "No matching applications"
                            color: root.theme.on_background
                            opacity: 0.5
                            font.pixelSize: 16
                            font.family: root.settings.fontdefault
                        }
                    }
                }
            }
        }
    }
}
