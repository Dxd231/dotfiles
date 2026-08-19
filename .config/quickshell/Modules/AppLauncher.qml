pragma ComponentBehavior: Bound
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import Quickshell.Widgets
import QtQuick.Effects

Item {
    id: root

    property var theme
    property var settings
    property int global_radius: 24

    property bool isOpenLauncher: false
    property string query: ""
    property int selectedIndex: 0

    FileView {
        id: pinsFile
        path: Quickshell.dataPath("app-launcher-pins.json")
        watchChanges: true
        onFileChanged: reload()
        onAdapterUpdated: writeAdapter()

        JsonAdapter {
            id: pinsAdapter
            property list<string> pinnedIds: []
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

    property var allApps: {
        const apps = [...DesktopEntries.applications.values].filter(e => e.name && !e.noDisplay);
        apps.sort((a, b) => {
            const aPinned = root.isPinned(a.id);
            const bPinned = root.isPinned(b.id);
            if (aPinned !== bPinned)
                return aPinned ? -1 : 1;
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
        implicitHeight: 550
        
        visible: root.isOpenLauncher || panelBg.opacity > 0
        MouseArea {
            anchors.fill: parent
            onClicked: root.isOpenLauncher = false
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
                    when: root.isOpenLauncher
                    PropertyChanges {
                        target: panelBg
                        y: 6
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !root.isOpenLauncher
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
                        duration: 360
                        easing.type: Easing.OutBack
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "y,opacity"
                        duration: 400
                        easing.type: Easing.InBack
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
                visible: false
                z: 0
            }

            MouseArea {
                anchors.fill: parent
                onClicked: {}
            }

            Column {
                anchors.fill: parent
                anchors.margins: 14
                spacing: 10

                // ---- search field ----
                Rectangle {
                    width: parent.width
                    height: 45
                    radius: 18
                    color: Qt.alpha(root.theme.on_background, 0.08)
                    border.width: 0
                    border.color: Qt.alpha(root.theme.source_color, 0.8)

                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        spacing: 10

                        /* Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: "\u{1F50D}"
                            font.pixelSize: 15
                            opacity: 0.5
                            color: root.theme.on_background
                        } */

                        TextInput {
                            id: searchField
                            leftPadding: 30
                            width: parent.width - 30
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.query
                            color: root.theme.on_background
                            font.pixelSize: 15
                            font.family: root.settings.fontdefault
                            /* renderType: Text.NativeRendering
                            font.hintingPreference: Font.PreferVerticalHinting */
                            clip: true

                            onTextChanged: root.query = text

                            Keys.onDownPressed: root.selectedIndex = Math.min(root.filteredApps.length - 1, root.selectedIndex + 1)
                            Keys.onUpPressed: root.selectedIndex = Math.max(0, root.selectedIndex - 1)
                            Keys.onReturnPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEnterPressed: root.launch(root.filteredApps[root.selectedIndex])
                            Keys.onEscapePressed: root.isOpenLauncher = false

                            Text {
                                visible: searchField.text.length === 0
                                leftPadding: 30
                                text: "Search Something\u2026"
                                color: root.theme.on_background
                                opacity: 0.4
                                font.pixelSize: 15
                                font.family: root.settings.fontdefault
                                /* renderType: Text.NativeRendering
                                font.hintingPreference: Font.PreferVerticalHinting */
                            }

                            Image {
                                source: "../assets/magnifying-glass-bold.svg"
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
                        }
                    }
                }

                // ---- results ----
                ListView {
                    id: resultsList
                    width: parent.width
                    height: parent.height - 52
                    clip: true
                    model: root.filteredApps
                    currentIndex: root.selectedIndex
                    highlightMoveDuration: 200
                    highlightMoveVelocity: -1
                    highlightFollowsCurrentItem: true
                    highlightResizeDuration: 0

                    // one real highlight that glides between rows, instead of
                    // each row teleport-toggling its own background color
                    highlight: Rectangle {
                        radius: root.global_radius
                        color: Qt.alpha(root.theme.source_color, 0.85)
                    }

                    delegate: Rectangle {
                        id: row
                        required property var modelData
                        required property int index
                        width: resultsList.width
                        height: 46
                        radius: root.global_radius
                        color: "transparent"

                        Row {
                            anchors.fill: parent
                            anchors.leftMargin: 10
                            anchors.rightMargin: 36
                            spacing: 12

                            IconImage {
                                anchors.verticalCenter: parent.verticalCenter
                                implicitSize: 28
                                source: Quickshell.iconPath(row.modelData.icon, true)
                            }

                            Column {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 40
                                spacing: 1

                                Text {
                                    width: parent.width
                                    text: row.modelData.name
                                    color: root.theme.on_background
                                    font.pixelSize: 16
                                    font.bold: false
                                    font.family: root.settings.fontmedium
                                    elide: Text.ElideRight
                                    /* renderType: Text.NativeRendering
                                    font.hintingPreference: Font.PreferVerticalHinting */
                                }
                                Text {
                                    width: parent.width
                                    visible: text.length > 0
                                    text: row.modelData.genericName || ""
                                    color: root.theme.on_background
                                    opacity: 0.55
                                    font.pixelSize: 13
                                    font.family: root.settings.fontdefault
                                    //renderType: Text.NativeRendering
                                    //font.hintingPreference: Font.PreferVerticalHinting
                                    elide: Text.ElideRight
                                }
                            }
                        }

                        MouseArea {
                            cursorShape: Qt.PointingHandCursor
                            anchors.fill: parent
                            onEntered: root.selectedIndex = row.index
                            hoverEnabled: true
                            onClicked: root.launch(row.modelData)
                        }

                        // pin toggle — declared last so it sits above the launch
                        // MouseArea above and intercepts its own clicks instead of
                        // also triggering a launch underneath it
                        Rectangle {
                            id: pinButton
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            height: 24
                            radius: 12
                            color: "transparent"

                            Image {
                                visible: root.isPinned(row.modelData.id) || pinHover.containsMouse 
                                anchors.centerIn: parent
                                source: "../assets/push-pin-bold.svg"
                                fillMode: Image.PreserveAspectFit
                                layer.enabled: true
                                layer.effect: MultiEffect {
                                    colorization: 1.0
                                    colorizationColor: root.isPinned(row.modelData.id) || pinHover.containsMouse ? Qt.alpha(root.theme.source_color, 0.5) : shell.theme.source_color
                                }
                            }                            
                            MouseArea {
                                id: pinHover
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.togglePin(row.modelData.id)
                            }
                        }
                    }

                    // simple empty state
                    Text {
                        anchors.centerIn: parent
                        visible: resultsList.count === 0
                        text: "No matching applications"
                        color: root.theme.on_background
                        opacity: 0.4
                        font.pixelSize: 16
                        font.family: root.settings.fontdefault
                        //renderType: Text.NativeRendering
                        //font.hintingPreference: Font.PreferVerticalHinting
                    }
                }
            }
        }
    }
}
