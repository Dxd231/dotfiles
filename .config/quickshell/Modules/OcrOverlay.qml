pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Region picker for OCR. The focused monitor is frozen (the picture is what gets read), dimmed, and a
// rounded window of it stays bright where you select. Works with the mouse, and entirely from the
// keyboard for fullscreen games: arrows move the box, Alt+arrows resize it, Tab cycles presets
// (last region, dialogue strip, right-hand column, whole screen), Enter reads, R repeats the last
// region at once. The tips sit behind the "?" button.
PanelWindow {
    id: win

    readonly property bool active: Ocr.phase === "selecting"
    // the window has no size yet the moment it is shown, the screen always does
    readonly property real sw: win.screen ? win.screen.width : win.width
    readonly property real sh: win.screen ? win.screen.height : win.height
    // the selection, in logical pixels (targets; the shown box springs after them)
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property bool hasSel: false
    property string choice: "auto"       // auto | manga | paddle
    property bool helpOpen: false
    property bool dragging: false
    property int presetIndex: -1
    // dialogue-box awareness: a box the user hasn't moved yet may still jump to a detected block
    property bool touched: false
    property bool blocksOn: true
    property bool wantDialogue: false
    property int hoverBlock: -1
    property int blockIndex: -1
    readonly property real imgScale: frozenImg.sourceSize.width > 0 && win.width > 0 ? frozenImg.sourceSize.width / win.width : 1
    readonly property string autoEngine: Ocr.pick(selW, selH)
    readonly property string engineNow: choice === "auto" ? autoEngine : choice

    screen: Quickshell.screens.find(s => s.name === Ocr.monitor) ?? Quickshell.screens[0]
    WlrLayershell.namespace: "quickshell:ocr"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: active || scene.opacity > 0.01

    // ---- the box ----
    function setRect(x, y, w, h) {
        w = Math.max(24, Math.min(win.sw, w));
        h = Math.max(24, Math.min(win.sh, h));
        selX = Math.max(0, Math.min(win.sw - w, x));
        selY = Math.max(0, Math.min(win.sh - h, y));
        selW = w;
        selH = h;
        hasSel = true;
    }
    function presets() {
        const W = win.sw, H = win.sh;
        const out = [];
        const mine = Ocr.windowRegion ? Ocr.windowRegion : Ocr.lastRegion;
        if (mine)
            out.push(mine);
        out.push({ x: W * 0.1, y: H * 0.66, w: W * 0.8, h: H * 0.27 });   // dialogue strip
        out.push({ x: W * 0.58, y: H * 0.06, w: W * 0.36, h: H * 0.88 });  // a column of vertical text
        out.push({ x: 0, y: 0, w: W, h: H });                               // everything
        return out;
    }
    function blockAt(x, y) {
        let best = -1, area = 1e12;
        Ocr.blocks.forEach((b, i) => {
            if (x >= b.x && x <= b.x + b.w && y >= b.y && y <= b.y + b.h && b.w * b.h < area) {
                best = i;
                area = b.w * b.h;
            }
        });
        return best;
    }
    function selectBlock(i) {
        const b = Ocr.blocks[i];
        if (!b)
            return;
        blockIndex = i;
        presetIndex = -1;
        touched = true;
        setRect(b.x, b.y, b.w, b.h);
    }
    function dialogueIndex() { return Ocr.blocks.findIndex(b => b.dialogue); }
    // D: the detected dialogue box (asking for detection first if it has not run)
    function jumpDialogue() {
        const i = dialogueIndex();
        if (i >= 0) {
            selectBlock(i);
        } else if (Ocr.detecting) {
            wantDialogue = true;
        } else if (Ocr.blocks.length === 0) {
            wantDialogue = true;
            Ocr.detect();
        }
    }
    function stepBlock(dir) {
        if (Ocr.blocks.length === 0) {
            if (!Ocr.detecting)
                Ocr.detect();
            return;
        }
        const n = Ocr.blocks.length;
        selectBlock(((blockIndex < 0 ? (dir > 0 ? -1 : 0) : blockIndex) + dir + n) % n);
    }
    Connections {
        target: Ocr
        function onBlocksChanged() {
            win.hoverBlock = -1;
            win.blockIndex = -1;
            if (!win.active || Ocr.blocks.length === 0)
                return;
            const i = win.dialogueIndex();
            // an untouched box with nothing remembered for this window snaps to the dialogue box
            if (i >= 0 && (win.wantDialogue || (!win.touched && !Ocr.windowRegion)))
                win.selectBlock(i);
            win.wantDialogue = false;
        }
    }
    function cyclePreset(dir) {
        const list = presets();
        presetIndex = (presetIndex + dir + list.length) % list.length;
        const p = list[presetIndex];
        setRect(p.x, p.y, p.w, p.h);
    }
    function confirm() {
        if (!hasSel)
            return;
        Ocr.confirm({ x: selX, y: selY, w: selW, h: selH }, imgScale, choice);
    }
    onActiveChanged: {
        if (active) {
            choice = "auto";
            helpOpen = false;
            dragging = false;
            touched = false;
            blocksOn = true;
            wantDialogue = false;
            hoverBlock = -1;
            blockIndex = -1;
            presetIndex = -1;
            cyclePreset(1);
            keys.forceActiveFocus();
        }
    }

    // ---- the picture ----
    Item {
        id: scene
        anchors.fill: parent
        opacity: win.active ? 1 : 0
        Behavior on opacity { Fade { speed: "fast" } }

        Image {
            id: frozenImg
            anchors.fill: parent
            source: Ocr.frozen !== "" && (win.active || scene.opacity > 0.01) ? "file://" + Ocr.frozen : ""
            cache: false
            fillMode: Image.Stretch
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.55
        }

        // detected text blocks: soft tints (no outlines); the hovered or chosen one is brighter
        Repeater {
            model: win.blocksOn ? Ocr.blocks.length : 0
            delegate: Rectangle {
                id: blk
                required property int index
                readonly property var b: Ocr.blocks[index]
                readonly property bool lit: win.hoverBlock === index || win.blockIndex === index
                x: b ? b.x : 0
                y: b ? b.y : 0
                width: b ? b.w : 0
                height: b ? b.h : 0
                radius: 10
                color: Qt.alpha(Colors.primary, lit ? 0.3 : 0.14)
                Behavior on color { ColorFade {} }
                scale: lit ? 1.015 : 1
                Behavior on scale { Spring { speed: "fast" } }
                Rectangle {
                    visible: !!blk.b && blk.b.dialogue
                    x: 8
                    y: -height / 2
                    height: 22
                    width: dlgText.implicitWidth + 18
                    radius: 11
                    color: Colors.primary
                    StyledText {
                        id: dlgText
                        anchors.centerIn: parent
                        role: "labelMedium"
                        emphasized: true
                        color: Colors.on_primary
                        text: "Dialogue"
                    }
                }
            }
        }

        // the bright window: the same picture, clipped to the rounded selection
        ClippingRectangle {
            id: box
            x: win.dx
            y: win.dy
            width: win.dw
            height: win.dh
            radius: 18
            color: "transparent"
            visible: win.hasSel
            Image {
                x: -box.x
                y: -box.y
                width: win.sw
                height: win.sh
                source: frozenImg.source
                cache: false
                fillMode: Image.Stretch
            }
            Rectangle {
                anchors.fill: parent
                color: Qt.alpha(Colors.primary, 0.1)
            }
        }
        // corner dots
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                width: 16
                height: 16
                radius: 8
                color: Colors.primary
                visible: win.hasSel
                x: win.dx + (index % 2) * win.dw - 8
                y: win.dy + Math.floor(index / 2) * win.dh - 8
                scale: win.hasSel ? (win.dragging ? 1.25 : 1) : 0
                Behavior on scale { Spring { speed: "fast" } }
            }
        }
        // size readout
        Rectangle {
            visible: win.hasSel
            x: win.dx + 10
            y: Math.max(8, win.dy - height - 8)
            height: 26
            width: sizeText.implicitWidth + 24
            radius: 13
            color: Colors.surface_container_high
            StyledText {
                id: sizeText
                anchors.centerIn: parent
                role: "labelMedium"
                emphasized: true
                text: Math.round(win.selW * win.imgScale) + " × " + Math.round(win.selH * win.imgScale) + "  ·  " + (win.engineNow === "manga" ? "Manga" : "General")
            }
        }
    }

    // the shown box follows the target on a spring, except while the mouse is dragging it
    property real dx: selX
    property real dy: selY
    property real dw: selW
    property real dh: selH
    Behavior on dx { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dy { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dw { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dh { enabled: !win.dragging; Spring { speed: "fast" } }

    // ---- mouse: drag a new box, move it, or pull a corner ----
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: win.active
        hoverEnabled: true
        cursorShape: Qt.CrossCursor
        property string mode: ""
        property real px: 0
        property real py: 0
        property var start: ({ x: 0, y: 0, w: 0, h: 0 })
        property var before: ({ x: 0, y: 0, w: 0, h: 0 })

        function corner(x, y) {
            const cs = [[win.selX, win.selY], [win.selX + win.selW, win.selY], [win.selX, win.selY + win.selH], [win.selX + win.selW, win.selY + win.selH]];
            for (let i = 0; i < 4; i++) {
                if (Math.hypot(x - cs[i][0], y - cs[i][1]) <= 18)
                    return i;
            }
            return -1;
        }
        property bool moved: false
        onPressed: m => {
            win.helpOpen = false;
            moved = false;
            win.dragging = true;
            px = m.x;
            py = m.y;
            before = { x: win.selX, y: win.selY, w: win.selW, h: win.selH };
            const c = win.hasSel ? corner(m.x, m.y) : -1;
            if (c >= 0) {
                mode = "c" + c;
                start = before;
            } else if (win.hasSel && m.x >= win.selX && m.x <= win.selX + win.selW && m.y >= win.selY && m.y <= win.selY + win.selH) {
                mode = "move";
                start = before;
            } else {
                mode = "new";
                win.selX = m.x;
                win.selY = m.y;
                win.selW = 1;
                win.selH = 1;
                win.hasSel = true;
                start = { x: m.x, y: m.y, w: 1, h: 1 };
            }
            win.presetIndex = -1;
        }
        onPositionChanged: m => {
            if (!pressed) {
                win.hoverBlock = win.blocksOn ? win.blockAt(m.x, m.y) : -1;
                return;
            }
            const dx = m.x - px, dy = m.y - py;
            if (Math.abs(dx) + Math.abs(dy) > 4)
                moved = true;
            win.touched = true;
            if (mode === "move") {
                win.setRect(start.x + dx, start.y + dy, start.w, start.h);
            } else if (mode === "new") {
                win.selX = Math.max(0, Math.min(px, m.x));
                win.selY = Math.max(0, Math.min(py, m.y));
                win.selW = Math.min(win.sw, Math.max(px, m.x)) - win.selX;
                win.selH = Math.min(win.sh, Math.max(py, m.y)) - win.selY;
            } else if (mode.charAt(0) === "c") {
                const c = Number(mode.charAt(1));
                const left = c % 2 === 0, top = c < 2;
                const fixedX = left ? start.x + start.w : start.x;
                const fixedY = top ? start.y + start.h : start.y;
                const nx = Math.max(0, Math.min(win.sw, (left ? start.x : start.x + start.w) + dx));
                const ny = Math.max(0, Math.min(win.sh, (top ? start.y : start.y + start.h) + dy));
                win.selX = Math.min(nx, fixedX);
                win.selY = Math.min(ny, fixedY);
                win.selW = Math.abs(nx - fixedX);
                win.selH = Math.abs(ny - fixedY);
            }
        }
        onReleased: m => {
            win.dragging = false;
            // a plain click on a detected block takes the whole block
            if (!moved && win.blocksOn) {
                const i = win.blockAt(m.x, m.y);
                if (i >= 0) {
                    win.setRect(before.w >= 12 ? before.x : win.sw * 0.1, before.w >= 12 ? before.y : win.sh * 0.66,
                                before.w >= 12 ? before.w : win.sw * 0.8, before.w >= 12 ? before.h : win.sh * 0.27);
                    win.selectBlock(i);
                    return;
                }
            }
            // a click or a sliver is not a selection: put the old box back
            if (win.selW < 12 || win.selH < 12)
                win.setRect(before.w >= 12 ? before.x : win.sw * 0.1, before.w >= 12 ? before.y : win.sh * 0.66,
                            before.w >= 12 ? before.w : win.sw * 0.8, before.w >= 12 ? before.h : win.sh * 0.27);
        }
        onDoubleClicked: win.confirm()
    }

    // ---- keyboard ----
    Item {
        id: keys
        anchors.fill: parent
        focus: win.active
        Keys.onPressed: e => {
            const step = (e.modifiers & Qt.ControlModifier) ? 50 : (e.modifiers & Qt.ShiftModifier) ? 1 : 10;
            const resize = (e.modifiers & Qt.AltModifier) !== 0;
            e.accepted = true;
            if (e.key === Qt.Key_Left || e.key === Qt.Key_Right || e.key === Qt.Key_Up || e.key === Qt.Key_Down || e.key === Qt.Key_Tab || e.key === Qt.Key_Backtab)
                win.touched = true;
            switch (e.key) {
            case Qt.Key_Escape:
                if (win.helpOpen)
                    win.helpOpen = false;
                else
                    Ocr.cancel();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
                win.confirm();
                break;
            case Qt.Key_Left:
                resize ? win.setRect(win.selX, win.selY, win.selW - step, win.selH) : win.setRect(win.selX - step, win.selY, win.selW, win.selH);
                win.presetIndex = -1;
                break;
            case Qt.Key_Right:
                resize ? win.setRect(win.selX, win.selY, win.selW + step, win.selH) : win.setRect(win.selX + step, win.selY, win.selW, win.selH);
                win.presetIndex = -1;
                break;
            case Qt.Key_Up:
                resize ? win.setRect(win.selX, win.selY, win.selW, win.selH - step) : win.setRect(win.selX, win.selY - step, win.selW, win.selH);
                win.presetIndex = -1;
                break;
            case Qt.Key_Down:
                resize ? win.setRect(win.selX, win.selY, win.selW, win.selH + step) : win.setRect(win.selX, win.selY + step, win.selW, win.selH);
                win.presetIndex = -1;
                break;
            case Qt.Key_Tab:
                win.cyclePreset(1);
                break;
            case Qt.Key_Backtab:
                win.cyclePreset(-1);
                break;
            case Qt.Key_M:
                win.choice = "manga";
                break;
            case Qt.Key_G:
                win.choice = "paddle";
                break;
            case Qt.Key_A:
                win.choice = "auto";
                break;
            case Qt.Key_R:
                if (Ocr.lastRegion) {
                    win.setRect(Ocr.lastRegion.x, Ocr.lastRegion.y, Ocr.lastRegion.w, Ocr.lastRegion.h);
                    win.confirm();
                }
                break;
            case Qt.Key_D:
                win.jumpDialogue();
                break;
            case Qt.Key_BracketLeft:
                win.stepBlock(-1);
                break;
            case Qt.Key_BracketRight:
                win.stepBlock(1);
                break;
            case Qt.Key_B:
                win.blocksOn = !win.blocksOn;
                if (win.blocksOn && Ocr.blocks.length === 0 && !Ocr.detecting)
                    Ocr.detect();
                break;
            case Qt.Key_H:
            case Qt.Key_Question:
                win.helpOpen = !win.helpOpen;
                break;
            default:
                e.accepted = false;
            }
        }
    }

    // ---- the pill: engine, read, cancel, help ----
    Rectangle {
        id: pill
        visible: win.hasSel
        opacity: win.active ? 1 : 0
        Behavior on opacity { Fade {} }
        height: 56
        width: pillRow.implicitWidth + 24
        radius: 28
        color: Colors.surface_container_high
        readonly property real below: win.dy + win.dh + 14
        x: Math.max(12, Math.min(win.sw - width - 12, win.dx + win.dw / 2 - width / 2))
        y: below + height > win.sh - 12 ? Math.max(12, win.dy - height - 14) : below
        Behavior on x { enabled: !win.dragging; Spring { speed: "fast" } }
        Behavior on y { enabled: !win.dragging; Spring { speed: "fast" } }

        RowLayout {
            id: pillRow
            anchors.centerIn: parent
            spacing: 8

            // engine: Auto / Manga / General, with a pill that slides between them. Each segment is as
            // wide as its label needs
            Rectangle {
                id: seg
                Layout.preferredWidth: segRow.width + 6
                Layout.preferredHeight: 36
                radius: 18
                color: Colors.surface_container_highest
                readonly property var items: [{ k: "auto", t: "Auto", w: 72 }, { k: "manga", t: "Manga", w: 88 }, { k: "paddle", t: "General", w: 100 }]
                readonly property int idx: win.choice === "manga" ? 1 : win.choice === "paddle" ? 2 : 0

                Rectangle {
                    y: 3
                    height: 30
                    width: seg.items[seg.idx].w
                    x: 3 + (seg.idx > 0 ? seg.items[0].w : 0) + (seg.idx > 1 ? seg.items[1].w : 0)
                    radius: 15
                    color: Colors.secondary_container
                    Behavior on x { Spring { speed: "default" } }
                    Behavior on width { Spring { speed: "default" } }
                }
                Row {
                    id: segRow
                    x: 3
                    y: 3
                    Repeater {
                        model: seg.items
                        delegate: Clickable {
                            id: segBtn
                            required property var modelData
                            width: modelData.w
                            height: 30
                            restRadius: 15
                            pressedRadius: 10
                            onClicked: win.choice = modelData.k
                            StyledText {
                                anchors.centerIn: parent
                                role: "labelLarge"
                                emphasized: true
                                color: win.choice === segBtn.modelData.k ? Colors.on_secondary_container : Colors.on_surface_variant
                                text: segBtn.modelData.t
                            }
                        }
                    }
                }
            }
            // finding the text blocks
            LoadingIndicator {
                Layout.preferredWidth: 28
                Layout.preferredHeight: 28
                visible: Ocr.detecting
                running: visible
            }
            IconButton { icon: "check"; style: "filled"; size: "s"; onClicked: win.confirm() }
            IconButton { icon: "close"; style: "tonal"; size: "s"; onClicked: Ocr.cancel() }
            IconButton { icon: "help"; size: "xs"; checkable: true; checked: win.helpOpen; onClicked: win.helpOpen = !win.helpOpen }
        }
    }

    // ---- tips, only when asked for ----
    Rectangle {
        id: helpCard
        readonly property var rows: [
            { keys: ["←", "↑", "↓", "→"], text: "Move the box" },
            { keys: ["Shift"], text: "1 px steps" },
            { keys: ["Ctrl"], text: "50 px steps" },
            { keys: ["Alt", "arrows"], text: "Resize the box" },
            { keys: ["Tab"], text: "Next preset" },
            { keys: ["Enter"], text: "Read" },
            { keys: ["R"], text: "Same region again" },
            { keys: ["D"], text: "Dialogue box" },
            { keys: ["[", "]"], text: "Previous / next block" },
            { keys: ["B"], text: "Show / hide blocks" },
            { keys: ["A", "M", "G"], text: "Auto / manga / general" },
            { keys: ["Esc"], text: "Cancel" }
        ]
        width: 292
        height: helpCol.implicitHeight + 28
        radius: Motion.shapeLarge
        color: Colors.inverse_surface
        x: Math.max(12, Math.min(win.sw - width - 12, pill.x + pill.width - width))
        y: Math.max(12, pill.y - height - 10)
        transformOrigin: Item.BottomRight
        opacity: win.helpOpen && win.active ? 1 : 0
        scale: win.helpOpen && win.active ? 1 : 0.6
        visible: opacity > 0.02
        Behavior on opacity { Fade {} }
        Behavior on scale { Spring { speed: "fast" } }

        ColumnLayout {
            id: helpCol
            x: 16
            y: 14
            width: parent.width - 32
            spacing: 6
            Repeater {
                model: helpCard.rows
                delegate: RowLayout {
                    id: hrow
                    required property var modelData
                    Layout.fillWidth: true
                    spacing: 8
                    Row {
                        Layout.preferredWidth: 108
                        spacing: 4
                        Repeater {
                            model: hrow.modelData.keys
                            delegate: Rectangle {
                                id: cap
                                required property string modelData
                                width: capText.implicitWidth + 12
                                height: 22
                                radius: Motion.shapeSmall
                                color: Qt.alpha(Colors.inverse_on_surface, 0.14)
                                StyledText {
                                    id: capText
                                    anchors.centerIn: parent
                                    role: "labelMedium"
                                    emphasized: true
                                    color: Colors.inverse_on_surface
                                    text: cap.modelData
                                }
                            }
                        }
                    }
                    StyledText {
                        Layout.fillWidth: true
                        role: "bodySmall"
                        color: Colors.inverse_on_surface
                        elide: Text.ElideRight
                        text: hrow.modelData.text
                    }
                }
            }
        }
    }
}
