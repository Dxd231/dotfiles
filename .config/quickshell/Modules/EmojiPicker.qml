pragma ComponentBehavior: Bound
import Quickshell
import QtQuick.Controls
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import QtQuick.Effects
import QtQuick.Layouts

Scope {
    id: emojiRoot

    property bool pickerOpen: false
    property var theme
    property var settings
    property var emojiList: []
    property string searchQuery: ""
    property var filtered: searchQuery.length === 0
        ? emojiRoot.frequentList
        : emojiRoot.emojiList.filter(e => e.label.toLowerCase().includes(searchQuery.toLowerCase()))

    onPickerOpenChanged: if (pickerOpen) {
        if (emojiRoot.emojiList.length === 0) {
            emojiRoot.loadEmojiJson();
        }
        searchField.text = "";
        emojiListView.currentIndex = 0;
        searchField.forceActiveFocus();
    }

    function loadEmojiJson() {
        try {
            emojiRoot.emojiList = JSON.parse(emojiJson.text());
        } catch (e) {
            console.log("emoji.json parse failed:", e);
        }
    }

    function normalizeEmoji(str) {
        return str.replace(/\uFE0F/g, "");
    }

    property var frequentList: {
        let ranked = emojiRoot.emojiList
            .filter(e => emojiRoot.frequency[emojiRoot.normalizeEmoji(e.emoji)] > 0)
            .sort((a, b) =>
                (emojiRoot.frequency[emojiRoot.normalizeEmoji(b.emoji)] || 0) -
                (emojiRoot.frequency[emojiRoot.normalizeEmoji(a.emoji)] || 0)
            )
            .slice(0, 20);

        return ranked.length > 0 ? ranked : emojiRoot.emojiList.slice(0, 20);
    }

    FileView {
        id: emojiJson
        path: Qt.resolvedUrl("../assets/emoji.json")
    }

    property var frequency: ({})

    FileView {
        id: freqFile
        path: Qt.resolvedUrl("../emoji_frequency.json")
        onLoaded: {
            try {
                emojiRoot.frequency = JSON.parse(text());
            } catch (e) {
                emojiRoot.frequency = {};
            }
        }
        onLoadFailed: error => {
            emojiRoot.frequency = {};   // file doesn't exist yet — that's fine, first run
        }
    }

    Process {
        id: copyProc
        property string char: ""
        command: ["wl-copy", char]
    }

    function copyEmoji(e) {
        copyProc.char = e.emoji;
        copyProc.running = true;

        let key = emojiRoot.normalizeEmoji(e.emoji);
        let updated = Object.assign({}, emojiRoot.frequency);
        updated[key] = (updated[key] || 0) + 1;
        emojiRoot.frequency = updated;

        saveFreqTimer.restart();
        pickerOpen = false;
    }

    Timer {
        id: saveFreqTimer
        interval: 500
        onTriggered: emojiRoot.saveFrequency()
    }

    function saveFrequency() {
        let json = JSON.stringify(emojiRoot.frequency);
        saveProc.b64 = Qt.btoa(json);   // base64-encode to sidestep shell-quoting issues with { } " chars
        saveProc.running = true;
    }

    Process {
        id: saveProc
        property string b64: ""
        command: ["sh", "-c", "echo '" + b64 + "' | base64 -d > " + Qt.resolvedUrl("../emoji_frequency.json").toString().replace("file://", "")]
    }

    IpcHandler {
        target: "emojipicker"
        function toggle(): void {
            emojiRoot.pickerOpen = !emojiRoot.pickerOpen;
        }
        function show(): void {
            emojiRoot.pickerOpen = true;
        }
        function hide(): void {
            emojiRoot.pickerOpen = false;
        }
    }

    PanelWindow {
        id: emojiPanel
        WlrLayershell.namespace: "quickshell:center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: emojiRoot.pickerOpen ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
        visible: emojiRoot.pickerOpen || panelBg.opacity > 0
        anchors {
            top: true
            left: true
        }
        margins {
            top: 6
            left: 0
            bottom: -4
        }
        implicitHeight: panelBg.height + 20
        implicitWidth: panelBg.width + 50
        color: "transparent"
        exclusionMode: ExclusionMode.Auto

        

        Item {
            anchors.fill: parent
            focus: true
            Keys.enabled: true
            Keys.onEscapePressed: {
                emojiRoot.pickerOpen = false
            }
        }

        Rectangle {
            id: panelBg
            width: 340
            height: 440
            
            radius: 18
            color: Qt.alpha(emojiRoot.theme.background, 0.8)
            border.width: 1
            border.color: Qt.alpha(emojiRoot.theme.surface_bright, 0.8)
            opacity: 0
            x: -270


            states: [
                State {
                    name: "open"
                    when: emojiRoot.pickerOpen
                    PropertyChanges {
                        target: panelBg
                        x: 16
                        opacity: 1
                    }
                },
                State {
                    name: "closed"
                    when: !emojiRoot.pickerOpen
                    PropertyChanges {
                        target: panelBg
                        x: -270
                        opacity: 0
                    }
                }
            ]

            transitions: [
                Transition {
                    from: "closed"
                    to: "open"

                    NumberAnimation {
                        properties: "x,opacity"
                        duration: 300
                        easing.type: Easing.OutBack
                        easing.overshoot: 1.5
                    }
                },
                Transition {
                    from: "open"
                    to: "closed"

                    NumberAnimation {
                        properties: "x,opacity"
                        duration: 300
                        easing.type: Easing.InBack
                        easing.overshoot: 1.5
                    }
                }
            ]
            Rectangle {
                id: searchContainer
                anchors.top: parent.top
                anchors.topMargin: 10
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.leftMargin: 10
                anchors.rightMargin: 10
                width: parent.width
                height: 40
                radius: 18
                color: Qt.alpha(emojiRoot.theme.on_background, 0.08)

                Row {
                    anchors.fill: parent
                    spacing: 10

                    TextInput {
                        id: searchField
                        leftPadding: 40
                        width: parent.width - 30
                        anchors.verticalCenter: parent.verticalCenter
                        focus: true
                        color: emojiRoot.theme.on_background
                        font.pixelSize: 15
                        font.family: emojiRoot.settings.fontdefault
                        clip: true

                        onTextChanged: emojiRoot.searchQuery = text

                        Keys.onDownPressed: {
                            emojiListView.currentIndex = Math.min(emojiRoot.filtered.length - 1, emojiListView.currentIndex + 1);
                        }
                        Keys.onUpPressed: {
                            emojiListView.currentIndex = Math.max(0, emojiListView.currentIndex - 1);
                        }
                        Keys.onReturnPressed: {
                            if (emojiRoot.filtered.length > 0)
                                emojiRoot.copyEmoji(emojiRoot.filtered[emojiListView.currentIndex]);
                        }
                        Keys.onEnterPressed: {
                            if (emojiRoot.filtered.length > 0)
                                emojiRoot.copyEmoji(emojiRoot.filtered[emojiListView.currentIndex]);
                        }
                        Keys.onEscapePressed: {
                            if (text.length > 0) {
                                text = "";
                            } else {
                                emojiRoot.pickerOpen = false;
                            }
                        }

                        Text {
                            visible: searchField.text.length === 0
                            leftPadding: 40
                            text: "Search emoji\u2026"
                            color: emojiRoot.theme.on_background
                            opacity: 0.4
                            font.pixelSize: 15
                            font.family: emojiRoot.settings.fontdefault
                        }

                        Image {
                            source: "../assets/magnifying-glass-bold.svg"
                            x: 10
                            width: 20
                            height: 20
                            sourceSize.width: 22
                            sourceSize.height: 22
                            fillMode: Image.PreserveAspectFit
                            layer.enabled: true
                            layer.effect: MultiEffect {
                                colorization: 1.0
                                colorizationColor: emojiRoot.theme.source_color
                            }
                        }
                    }
                }
            }
            ListView {
                id: emojiListView
                anchors.top: searchContainer.bottom
                width: panelBg.width - 20
                topMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                height: panelBg.height - 40
                clip: true
                reuseItems: true
                model: emojiRoot.filtered
                currentIndex: 0
                highlightMoveDuration: 200
                highlightMoveVelocity: -1
                highlightFollowsCurrentItem: true
                highlightResizeDuration: 0
                highlight: Rectangle {
                    radius: 18
                    color: Qt.alpha(emojiRoot.theme.source_color, 0.8)
                }

                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property var index
                    width: emojiListView.width
                    height: 32
                    radius: 18
                    clip: true
                    color: "transparent"

                    RowLayout {
                        anchors.fill: parent
                        anchors.margins: 6
                        spacing: 8
                        Text {
                            text: row.modelData.emoji
                            font.pixelSize: 16
                        }
                        Text {
                            Layout.fillWidth: true
                            text: row.modelData.label
                            color: row.index === emojiListView.currentIndex ? emojiRoot.theme.background : emojiRoot.theme.on_background
                            font.pixelSize: 16
                            font.family: emojiRoot.settings.fontdefault
                            elide: Text.ElideRight
                            Behavior on color {
                                ColorAnimation {
                                    easing.type: Easing.OutCirc
                                }
                            }
                        }
                    }

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onEntered: emojiListView.currentIndex = row.index
                        onClicked: emojiRoot.copyEmoji(row.modelData)
                    }
                }
            }
        }
    }
}