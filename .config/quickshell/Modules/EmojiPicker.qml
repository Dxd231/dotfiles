pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components

// Emoji search: a compact M3 search view that slides in from the left. With an empty query it
// lists your most-used emoji; Enter or click copies and closes.
Scope {
    id: emojiRoot

    property var copyToast
    property bool pickerOpen: false
    property var emojiList: []
    property var frequency: ({})
    property string searchQuery: ""

    readonly property var frequentList: {
        const ranked = emojiList.filter(e => frequency[normalizeEmoji(e.emoji)] > 0)
            .sort((a, b) => (frequency[normalizeEmoji(b.emoji)] || 0) - (frequency[normalizeEmoji(a.emoji)] || 0))
            .slice(0, 20);
        return ranked.length > 0 ? ranked : emojiList.slice(0, 20);
    }
    readonly property var filtered: {
        const q = searchQuery.toLowerCase();
        return q.length === 0 ? frequentList : emojiList.filter(e => e.label.toLowerCase().includes(q));
    }

    function normalizeEmoji(str) {
        return str.replace(/️/g, "");
    }

    onPickerOpenChanged: {
        if (!pickerOpen)
            return;
        if (emojiList.length === 0) {
            try {
                emojiList = JSON.parse(emojiJson.text());
            } catch (e) {
                console.warn("emoji.json parse failed:", e);
            }
        }
        searchField.text = "";
        list.currentIndex = 0;
        searchField.forceActiveFocus();
    }

    FileView {
        id: emojiJson
        path: Quickshell.shellPath("assets/emoji.json")
    }

    // Usage counts live in the state dir: a file inside the config dir would hot-reload the shell.
    FileView {
        id: freqFile
        path: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/quickshell/emoji-frequency.json"
        printErrors: false
        onLoaded: {
            try {
                emojiRoot.frequency = JSON.parse(text());
            } catch (e) {
                emojiRoot.frequency = {};
            }
        }
    }

    function copyEmoji(e) {
        if (!e)
            return;
        Quickshell.execDetached(["wl-copy", e.emoji]);
        if (copyToast)
            copyToast.showToast("Emoji copied");
        const key = normalizeEmoji(e.emoji);
        const updated = Object.assign({}, frequency);
        updated[key] = (updated[key] || 0) + 1;
        frequency = updated;
        saveTimer.restart();
        pickerOpen = false;
    }

    Timer {
        id: saveTimer
        interval: 500
        onTriggered: freqFile.setText(JSON.stringify(emojiRoot.frequency))
    }

    IpcHandler {
        target: "emojipicker"
        function toggle(): void { emojiRoot.pickerOpen = !emojiRoot.pickerOpen; }
        function show(): void { emojiRoot.pickerOpen = true; }
        function hide(): void { emojiRoot.pickerOpen = false; }
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:emoji_picker"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: emojiRoot.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        visible: emojiRoot.pickerOpen || panel.opacity > 0
        anchors { top: true; left: true }
        exclusiveZone: 0
        implicitWidth: panel.width + 40
        implicitHeight: panel.height + 40
        color: "transparent"
        mask: Region { item: panel }

        Elevation {
            anchors.fill: panel
            radius: panel.radius
            level: 3
            opacity: panel.opacity
        }

        Rectangle {
            id: panel
            y: 8
            width: 360
            height: 480
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            x: emojiRoot.pickerOpen ? 8 : -width
            opacity: emojiRoot.pickerOpen ? 1 : 0
            Behavior on x { Spring { speed: "default"; expressive: emojiRoot.pickerOpen } }
            Behavior on opacity { Fade { speed: "default" } }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12

                // search bar
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

                        Icon { name: searchField.text.length > 0 ? "search" : "mood"; color: Colors.on_surface }

                        TextInput {
                            id: searchField
                            Layout.fillWidth: true
                            color: Colors.on_surface
                            selectionColor: Colors.primary
                            selectedTextColor: Colors.on_primary
                            font.family: Typography.family
                            font.pixelSize: Typography.size("bodyLarge")
                            font.weight: Typography.weight("bodyLarge")
                            clip: true
                            onTextChanged: {
                                emojiRoot.searchQuery = text;
                                list.currentIndex = 0;
                            }
                            Keys.onDownPressed: list.currentIndex = Math.min(emojiRoot.filtered.length - 1, list.currentIndex + 1)
                            Keys.onUpPressed: list.currentIndex = Math.max(0, list.currentIndex - 1)
                            Keys.onReturnPressed: emojiRoot.copyEmoji(emojiRoot.filtered[list.currentIndex])
                            Keys.onEnterPressed: emojiRoot.copyEmoji(emojiRoot.filtered[list.currentIndex])
                            Keys.onEscapePressed: {
                                if (text.length > 0)
                                    text = "";
                                else
                                    emojiRoot.pickerOpen = false;
                            }

                            StyledText {
                                visible: searchField.text.length === 0
                                anchors.verticalCenter: parent.verticalCenter
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                text: "Search emoji"
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

                StyledText {
                    Layout.leftMargin: 8
                    role: "labelLarge"
                    color: Colors.primary
                    text: emojiRoot.searchQuery ? emojiRoot.filtered.length + " results" : "Frequently used"
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    reuseItems: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    model: emojiRoot.filtered
                    highlightFollowsCurrentItem: false
                    ScrollIntoView { view: list }
                    highlight: Rectangle {
                        width: list.width
                        height: 48
                        radius: Motion.shapeLarge
                        color: Colors.secondary_container
                        y: list.currentItem ? list.currentItem.y : 0
                        visible: list.count > 0
                        Behavior on y { Spring {} }
                    }

                    delegate: Clickable {
                        id: row
                        required property var modelData
                        required property int index
                        readonly property bool selected: index === list.currentIndex

                        width: list.width
                        height: 48
                        restRadius: Motion.shapeLarge
                        pressedRadius: Motion.shapeSmall
                        contentColor: selected ? Colors.on_secondary_container : Colors.on_surface
                        onHoveredChanged: if (hovered) list.currentIndex = index
                        onClicked: emojiRoot.copyEmoji(modelData)

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 16
                            spacing: 16
                            Text {
                                text: row.modelData.emoji
                                font.pixelSize: 24
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyLarge"
                                color: row.contentColor
                                elide: Text.ElideRight
                                text: row.modelData.label
                            }
                        }
                    }

                    StyledText {
                        anchors.centerIn: parent
                        visible: list.count === 0
                        role: "bodyLarge"
                        color: Colors.on_surface_variant
                        text: "No emoji found"
                    }
                }
            }
        }
    }
}
