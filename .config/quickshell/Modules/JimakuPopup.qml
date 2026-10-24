pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Subtitles from jimaku.cc for the video in mpv, opened from mpv with Alt+j (IPC jimakuPanel toggle).
// Shows what was fetched and why, every file Jimaku has for the episode (click one to swap, the block
// icon bans its author), and the controls to look again, fix the Jimaku entry or connect the API key.
BarPopup {
    id: win

    // same layer namespace as the calendar so Hyprland's existing layer rule styles it too
    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 440
    spacing: 14
    animateHeight: true

    // opened from mpv, not from a bar item: sit in the middle under the bar
    onIsOpenChanged: {
        if (isOpen) {
            margins.left = Math.max(0, Math.round(((screen ? screen.width : 1920) - implicitWidth) / 2));
            fixOpen = false;
            keyField.text = "";
            if (Jimaku.path !== "" && Jimaku.hasKey && Jimaku.current === null)
                Jimaku.fetch();
        }
    }

    property bool fixOpen: false

    // the badge glyph follows the state; every change pops the new one in on a spring
    readonly property string glyph: !haveFile ? "subtitles" : !Jimaku.hasKey ? "key" : busy ? "subtitles"
        : !cur ? "subtitles" : cur.state === "saved" ? "check" : cur.state === "none" ? "subtitles_off" : "error"
    property real pop: 1
    property bool popSpring: true
    Behavior on pop { enabled: win.popSpring; Spring { speed: "fast" } }
    onGlyphChanged: {
        popSpring = false;
        pop = 0.2;
        popSpring = true;
        pop = 1;
    }
    // a subtitle landing gives the badge a little hop
    Connections {
        target: Jimaku
        function onStateChanged() {
            if (Jimaku.state === "saved") {
                badge.badgeScale = 1.22;
                settle.restart();
            }
        }
    }
    Timer {
        id: settle
        interval: 140
        onTriggered: badge.badgeScale = 1
    }

    // text that changes by sliding: the old line rises out, the new one comes up under it
    component SlideText: Item {
        id: st
        property string text
        property string role: "titleSmall"
        property bool jp: false
        property color color: Colors.on_surface
        property int elide: Text.ElideRight
        property real slide: 1
        property bool slideSpring: true
        property string shownText: text
        property string oldText: ""
        implicitHeight: cur.implicitHeight
        clip: true
        Behavior on slide { enabled: st.slideSpring; Spring { speed: "default" } }
        onTextChanged: {
            if (text === shownText)
                return;
            oldText = shownText;
            shownText = text;
            slideSpring = false;
            slide = 0;
            slideSpring = true;
            slide = 1;
        }
        StyledText {
            width: parent.width
            y: -st.height * 0.6 * st.slide
            jp: st.jp
            role: st.role
            emphasized: true
            elide: st.elide
            color: st.color
            text: st.oldText
            opacity: Math.max(0, 1 - st.slide * 1.6)
        }
        StyledText {
            id: cur
            width: parent.width
            y: st.height * 0.6 * (1 - st.slide)
            jp: st.jp
            role: st.role
            emphasized: true
            elide: st.elide
            color: st.color
            text: st.shownText
            opacity: Math.min(1, st.slide * 1.6)
        }
    }

    // an mpv-only panel: focusing another window takes it down at once
    Connections {
        target: Lexicon
        function onOtherFocusedChanged() { if (Lexicon.otherFocused) win.hide(); }
    }

    IpcHandler {
        target: "jimakuPanel"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
    }

    readonly property var cur: Jimaku.current
    readonly property bool haveFile: Jimaku.path !== ""
    // read off the record itself: it can update a beat before Jimaku.searching does
    readonly property bool busy: Jimaku.searching || (cur !== null && cur.state === "searching")
    readonly property string entryName: cur && cur.entry ? (cur.entry.japanese || cur.entry.name) : ""

    readonly property string stateText: {
        if (!haveFile)
            return "Open a video in mpv";
        if (!Jimaku.hasKey)
            return "Connect Jimaku to fetch subtitles";
        if (busy)
            return "Finding subtitles…";
        if (!cur)
            return "Nothing fetched yet";
        if (cur.state === "saved")
            return "Saved · " + Jimaku.baseName(cur.saved);
        if (cur.state === "none")
            return "No usable subtitles on Jimaku" + (cur.nblocked > 0 ? " (" + cur.nblocked + " skipped)" : "");
        if (cur.state === "nokey")
            return "Jimaku needs a working API key";
        return cur.error || "Something went wrong";
    }
    readonly property bool bad: haveFile && !busy && Jimaku.hasKey && !!cur && cur.state !== "saved"

    function groupOf(name) {
        const m = String(name).match(/\[([^\]]+)\]|\(([^)]+)\)/);
        return m ? (m[1] || m[2]) : "";
    }
    function extOf(name) {
        const m = String(name).match(/\.([A-Za-z0-9]+)$/);
        return m ? m[1].toUpperCase() : "";
    }

    // ---- header ----
    Item {
        Layout.fillWidth: true
        Layout.topMargin: 4
        implicitHeight: 72
        Appear { shown: win.isOpen }

        ShapeBadge {
            id: badge
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            width: 64
            height: 64
            shapeRest: "cookie4"
            shapeActive: "gem"
            active: win.haveFile && !win.busy && !win.bad && !!win.cur && win.cur.state === "saved"
            busy: win.busy
            color: win.bad ? Colors.error_container : Colors.primary_container
            Icon {
                anchors.centerIn: parent
                size: 30
                name: win.glyph
                scale: win.pop
                rotation: (1 - win.pop) * -50
                color: win.bad ? Colors.on_error_container : Colors.on_primary_container
            }
        }
        Connections {
            target: win
            function onBusyChanged() { if (!win.busy && win.haveFile) badge.finish(!win.bad); }
        }
        ColumnLayout {
            anchors.left: badge.right
            anchors.leftMargin: 16
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 2
            SlideText {
                Layout.fillWidth: true
                jp: true
                role: "titleLarge"
                text: win.entryName !== "" ? win.entryName : (win.haveFile ? Mpv.title : "Jimaku")
            }
            SlideText {
                Layout.fillWidth: true
                role: "titleSmall"
                elide: Text.ElideMiddle
                color: win.bad ? Colors.error : Colors.on_surface_variant
                text: win.stateText
            }
        }
    }

    // ---- facts about what was saved ----
    Collapse {
        open: win.cur !== null && win.cur.state === "saved"
        Layout.fillWidth: true
        Flow {
            spacing: 6
            move: Transition { Spring { properties: "x,y"; speed: "default" } }
            ImmersionChip { visible: win.cur !== null && win.cur.ep > 0; icon: "movie"; text: "Ep " + (win.cur ? win.cur.ep : "") }
            ImmersionChip { icon: "subtitles"; text: win.cur ? win.extOf(win.cur.chosen) : "" }
            ImmersionChip {
                readonly property string cp: win.cur ? Lexicon.comprehension(win.cur.saved) : ""
                visible: cp !== ""
                icon: "translate"
                ring: win.cur ? Lexicon.comprehensionParts(win.cur.saved) : null
                text: cp
                tint: Colors.secondary_container
                ink: Colors.on_secondary_container
            }
            ImmersionChip { visible: win.cur !== null && !!win.cur.converted; icon: "sync"; text: "Converted to SRT" }
            ImmersionChip { visible: win.cur !== null && !!win.cur.cleaned; icon: "cleaning_services"; text: "Cleaned 中日 subs"; tint: Colors.tertiary_container; ink: Colors.on_tertiary_container }
        }
    }

    // ---- API key ----
    Collapse {
        open: !Jimaku.hasKey
        Layout.fillWidth: true
        ColumnLayout {
            spacing: 8
            Appear { shown: win.isOpen && !Jimaku.hasKey }
            StyledText {
                Layout.fillWidth: true
                role: "bodyMedium"
                wrapMode: Text.WordWrap
                color: Colors.on_surface_variant
                text: "Make a free account on jimaku.cc, create an API key on its account page and paste it here."
            }
            TextField {
                id: keyField
                Layout.fillWidth: true
                label: "API key"
                leadingIcon: "key"
                password: true
                onAccepted: t => { if (t.trim() !== "") Jimaku.setKey(t.trim()); }
            }
            Collapse {
                open: Jimaku.keyError !== ""
                Layout.fillWidth: true
                StyledText {
                    role: "labelLarge"
                    color: Colors.error
                    text: Jimaku.keyError
                }
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Button {
                    Layout.fillWidth: true
                    size: "s"
                    style: "tonal"
                    icon: "open_in_new"
                    text: "Open account page"
                    onClicked: Jimaku.openAccount()
                }
                Button {
                    Layout.fillWidth: true
                    size: "s"
                    icon: "check"
                    text: Jimaku.keyBusy ? "Checking…" : "Connect"
                    enabled: !Jimaku.keyBusy && keyField.text.trim() !== ""
                    onClicked: Jimaku.setKey(keyField.text.trim())
                }
            }
        }
    }

    // ---- every file Jimaku has for this episode ----
    Collapse {
        open: Jimaku.hasKey && Jimaku.candidates.length > 0
        Layout.fillWidth: true
        Flickable {
            id: listView
            implicitHeight: Math.min(list.implicitHeight, 280)
            contentHeight: list.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
                id: list
                width: listView.width
                spacing: 4
                Repeater {
                    model: Jimaku.candidates
                    delegate: Item {
                        id: slot
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 52
                        // the rows come up one after another; the dimming of a banned one lives on the row itself
                        Appear { shown: win.isOpen; delay: 40 + Math.min(slot.index, 8) * 45 }
                        Clickable {
                            id: row
                            readonly property var modelData: slot.modelData
                            readonly property bool here: win.cur !== null && modelData.name === win.cur.chosen
                            readonly property string group: win.groupOf(modelData.name)
                            readonly property string note: modelData.blocked ? String(modelData.blocked)
                                : here ? "In use" : modelData.cls === "bi" ? "中日 · the Chinese is cleaned out" : ""
                            anchors.fill: parent
                            // the row in use rounds into a pill, the others stay squircles
                            restRadius: here ? 26 : Motion.shapeMedium
                            pressedRadius: Motion.shapeSmall
                            color: here ? Colors.secondary_container : Colors.surface_container_high
                            contentColor: here ? Colors.on_secondary_container : Colors.on_surface
                            enabled: !modelData.blocked
                            opacity: modelData.blocked ? 0.55 : 1
                            onClicked: Jimaku.pick(modelData)

                            Icon {
                                id: lead
                                anchors.left: parent.left
                                anchors.leftMargin: 14
                                anchors.verticalCenter: parent.verticalCenter
                                size: 20
                                name: row.modelData.blocked ? "block" : row.here ? "check" : "subtitles"
                                color: row.contentColor
                            }
                            Column {
                                anchors.left: lead.right
                                anchors.leftMargin: 12
                                anchors.right: blockBtn.left
                                anchors.rightMargin: 4
                                anchors.verticalCenter: parent.verticalCenter
                                StyledText {
                                    width: parent.width
                                    jp: true
                                    role: "bodyMedium"
                                    emphasized: true
                                    elide: Text.ElideMiddle
                                    color: row.contentColor
                                    text: row.modelData.name
                                }
                                StyledText {
                                    visible: row.note !== ""
                                    width: parent.width
                                    role: "labelSmall"
                                    elide: Text.ElideRight
                                    color: row.modelData.blocked ? Colors.error : Qt.alpha(row.contentColor, 0.75)
                                    text: row.note
                                }
                            }
                            IconButton {
                                id: blockBtn
                                anchors.right: parent.right
                                anchors.rightMargin: 6
                                anchors.verticalCenter: parent.verticalCenter
                                size: "xs"
                                icon: "person_off"
                                // only files named [Group] can be told apart by author
                                visible: row.group !== "" && !row.modelData.blocked
                                onClicked: Jimaku.block(row.group)
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- authors you blocked ----
    Collapse {
        open: Jimaku.blacklist.length > 0
        Layout.fillWidth: true
        ColumnLayout {
            spacing: 6
            StyledText {
                role: "labelLarge"
                color: Colors.on_surface_variant
                text: "Blocked authors"
            }
            Flow {
                Layout.fillWidth: true
                spacing: 6
                Repeater {
                    model: Jimaku.blacklist
                    delegate: Chip {
                        required property string modelData
                        kind: "input"
                        text: modelData
                        trailingIcon: "close"
                        onClicked: Jimaku.unblock(modelData)
                        onTrailingClicked: Jimaku.unblock(modelData)
                    }
                }
            }
        }
    }

    // ---- actions ----
    Collapse {
        open: Jimaku.hasKey
        Layout.fillWidth: true
        RowLayout {
            spacing: 8
            Button {
                Layout.fillWidth: true
                size: "s"
                icon: "refresh"
                text: "Search again"
                enabled: win.haveFile && !win.busy
                onClicked: Jimaku.fetch()
            }
            Button {
                Layout.fillWidth: true
                size: "s"
                style: "tonal"
                icon: "edit"
                text: "Fix entry"
                enabled: win.haveFile
                onClicked: {
                    win.fixOpen = !win.fixOpen;
                    if (win.fixOpen)
                        fixField.forceActiveFocus();
                }
            }
            IconButton {
                style: "tonal"
                icon: "open_in_new"
                enabled: win.entryName !== ""
                onClicked: Jimaku.openEntry()
            }
        }
    }

    // ---- point this show at another Jimaku entry ----
    Collapse {
        open: win.fixOpen
        Layout.fillWidth: true
        ColumnLayout {
            spacing: 6
            TextField {
                id: fixField
                Layout.fillWidth: true
                label: "Search Jimaku"
                leadingIcon: "search"
                onAccepted: t => { if (t.trim() !== "") Jimaku.searchEntry(t.trim()); }
            }
            Collapse {
                open: Jimaku.entrySearching
                StyledText {
                    role: "labelLarge"
                    color: Colors.on_surface_variant
                    text: "Searching…"
                }
            }
            Repeater {
                model: Jimaku.searchResults
                delegate: Clickable {
                    id: hit
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: 48
                    restRadius: Motion.shapeMedium
                    pressedRadius: Motion.shapeSmall
                    color: Colors.surface_container_high
                    onClicked: {
                        Jimaku.pinEntry(modelData.id);
                        win.fixOpen = false;
                    }
                    Column {
                        anchors.left: parent.left
                        anchors.leftMargin: 14
                        anchors.right: parent.right
                        anchors.rightMargin: 14
                        anchors.verticalCenter: parent.verticalCenter
                        StyledText {
                            width: parent.width
                            jp: true
                            role: "bodyMedium"
                            emphasized: true
                            elide: Text.ElideRight
                            text: hit.modelData.japanese || hit.modelData.name
                        }
                        StyledText {
                            width: parent.width
                            role: "labelSmall"
                            elide: Text.ElideRight
                            color: Colors.on_surface_variant
                            text: hit.modelData.english || hit.modelData.name
                        }
                    }
                }
            }
        }
    }
}
