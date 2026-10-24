pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Screenshot and recording picker. The focused monitor is frozen and dimmed; what is going to be
// captured stays bright in a rounded window of it. The toolbar chooses photo or video and what to
// capture: a region, a window (any window of any workspace, from the strip), a whole workspace (every
// window of it at its layout position) or the screen. The shutter morphs between the two modes.
PanelWindow {
    id: win

    readonly property bool active: Capture.phase === "selecting"
    readonly property real sw: win.screen ? win.screen.width : win.width
    readonly property real sh: win.screen ? win.screen.height : win.height
    readonly property string target: Capture.target
    readonly property bool video: Capture.mode === "video"

    // region, in logical pixels (targets; the shown box springs after them)
    property real selX: 0
    property real selY: 0
    property real selW: 0
    property real selH: 0
    property bool hasSel: false
    property bool dragging: false
    property int presetIndex: -1
    property string selWin: ""          // address of the chosen window
    property int selWs: 1               // id of the chosen workspace
    property string hoverWin: ""
    property bool helpOpen: false

    readonly property var winSel: Capture.windowByAddr(selWin)
    readonly property var wsSel: Capture.workspaceById(selWs)
    readonly property bool winOnScreen: !!winSel && winSel.onScreen
    readonly property bool strip: target === "window" || target === "workspace"
    readonly property var stripModel: target === "workspace" ? Capture.workspaces : Capture.windows

    screen: Quickshell.screens.find(s => s.name === Capture.mon.name) ?? Quickshell.screens[0]
    WlrLayershell.namespace: "quickshell:capture"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: active ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    anchors { top: true; bottom: true; left: true; right: true }
    exclusiveZone: -1
    color: "transparent"
    visible: active || scene.opacity > 0.01

    // ---- the box ----
    function clampWin(w) {
        const x = Math.max(0, w.x), y = Math.max(0, w.y);
        return Qt.rect(x, y, Math.max(8, Math.min(win.sw, w.x + w.w) - x), Math.max(8, Math.min(win.sh, w.y + w.h) - y));
    }
    readonly property rect boxTarget: target === "region" ? Qt.rect(selX, selY, selW, selH)
        : target === "window" && winOnScreen ? clampWin(winSel) : Qt.rect(0, 0, sw, sh)
    readonly property bool boxOn: active && (target === "region" ? hasSel : target === "screen" || (target === "window" && winOnScreen))
    property real dx: boxTarget.x
    property real dy: boxTarget.y
    property real dw: boxTarget.width
    property real dh: boxTarget.height
    // the corner radius springs too (square for the whole screen); a spring can undershoot zero
    property real boxRadius: target === "screen" ? 0 : 18
    Behavior on boxRadius { Spring { speed: "fast" } }
    Behavior on dx { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dy { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dw { enabled: !win.dragging; Spring { speed: "fast" } }
    Behavior on dh { enabled: !win.dragging; Spring { speed: "fast" } }

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
        if (Capture.lastRegion)
            out.push(Capture.lastRegion);
        const fw = Capture.windows.find(w => w.focused && w.onScreen);
        if (fw) {
            const r = clampWin(fw);
            out.push({ x: r.x, y: r.y, w: r.width, h: r.height });
        }
        out.push({ x: W * 0.2, y: H * 0.2, w: W * 0.6, h: H * 0.6 });
        out.push({ x: 0, y: 0, w: W, h: H });
        return out;
    }
    function cyclePreset(dir) {
        const list = presets();
        presetIndex = (presetIndex + dir + list.length) % list.length;
        const p = list[presetIndex];
        setRect(p.x, p.y, p.w, p.h);
    }
    function windowAt(x, y) {
        let best = "", area = 1e12;
        Capture.windows.forEach(w => {
            if (w.onScreen && x >= w.x && x <= w.x + w.w && y >= w.y && y <= w.y + w.h && w.w * w.h < area) {
                best = w.addr;
                area = w.w * w.h;
            }
        });
        return best;
    }
    // the strip's neighbours, wrapping
    function step(dir) {
        const list = stripModel;
        if (list.length === 0)
            return;
        const ws = target === "workspace";
        const i = list.findIndex(x => ws ? x.id === selWs : x.addr === selWin);
        const n = (i < 0 ? (dir > 0 ? -1 : 0) : i) + dir;
        const pick = list[(n + list.length) % list.length];
        if (ws)
            selWs = pick.id;
        else
            selWin = pick.addr;
    }
    function shoot() {
        if (target === "region") {
            if (hasSel)
                Capture.shoot({ target: "region", x: selX, y: selY, w: selW, h: selH });
        } else if (target === "window") {
            if (selWin !== "")
                Capture.shoot({ target: "window", addr: selWin });
        } else if (target === "workspace") {
            Capture.shoot({ target: "workspace", id: selWs });
        } else {
            Capture.shoot({ target: "screen", x: 0, y: 0, w: sw, h: sh });
        }
    }
    onActiveChanged: {
        if (!active)
            return;
        helpOpen = false;
        dragging = false;
        hoverWin = "";
        selWs = Capture.mon.visible;
        const fw = Capture.windows.find(w => w.focused && w.onScreen) || Capture.windows.find(w => w.onScreen) || Capture.windows[0];
        selWin = fw ? fw.addr : "";
        presetIndex = -1;
        if (Capture.lastRegion)
            cyclePreset(1);
        else
            setRect(sw * 0.2, sh * 0.2, sw * 0.6, sh * 0.6);
        hasSel = true;
        keys.forceActiveFocus();
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
            source: Capture.frozen !== "" && (win.active || scene.opacity > 0.01) ? "file://" + Capture.frozen : ""
            cache: false
            fillMode: Image.Stretch
        }
        Rectangle {
            anchors.fill: parent
            color: "black"
            opacity: 0.55
        }

        // windows on screen: soft tints, the hovered or chosen one is brighter (the chosen one also gets the bright box)
        Repeater {
            model: win.target === "window" ? Capture.windows : []
            delegate: Rectangle {
                id: tint
                required property var modelData
                readonly property rect r: win.clampWin(modelData)
                readonly property bool lit: win.hoverWin === modelData.addr
                opacity: (modelData.onScreen && win.selWin !== modelData.addr) ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Fade {} }
                x: r.x
                y: r.y
                width: r.width
                height: r.height
                radius: 18
                color: Qt.alpha(Colors.primary, lit ? 0.3 : 0.12)
                Behavior on color { ColorFade {} }
                scale: lit ? 1.012 : 1
                Behavior on scale { Spring { speed: "fast" } }
                Rectangle {
                    opacity: tint.lit ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    x: 12
                    y: 12
                    height: 26
                    width: Math.min(tint.width - 24, tintText.implicitWidth + 20)
                    radius: 13
                    color: Colors.primary
                    StyledText {
                        id: tintText
                        anchors.centerIn: parent
                        width: parent.width - 16
                        elide: Text.ElideRight
                        role: "labelMedium"
                        emphasized: true
                        color: Colors.on_primary
                        text: tint.modelData.cls
                    }
                }
            }
        }

        // the bright window: the same picture, clipped to the rounded box
        ClippingRectangle {
            id: box
            x: win.dx
            y: win.dy
            width: Math.max(0, win.dw)
            height: Math.max(0, win.dh)
            radius: Math.max(0, win.boxRadius)
            color: "transparent"
            opacity: win.boxOn ? 1 : 0
            Behavior on opacity { Fade {} }
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
                color: Qt.alpha(Colors.primary, 0.08)
            }
        }
        Repeater {
            model: 4
            delegate: Rectangle {
                required property int index
                width: 16
                height: 16
                radius: 8
                color: Colors.primary
                opacity: win.target === "region" ? 1 : 0
                visible: opacity > 0
                Behavior on opacity { Fade {} }
                x: win.dx + (index % 2) * win.dw - 8
                y: win.dy + Math.floor(index / 2) * win.dh - 8
                scale: win.target === "region" && win.hasSel ? (win.dragging ? 1.25 : 1) : 0
                Behavior on scale { Spring { speed: "fast" } }
            }
        }
        // what the box holds
        Rectangle {
            opacity: win.boxOn ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
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
                text: {
                    const k = Capture.mon.scale;
                    // a window is saved whole, even where it runs past the screen
                    if (win.target === "window" && win.winSel)
                        return win.winSel.cls + "  ·  " + Math.round(win.winSel.w * k) + " × " + Math.round(win.winSel.h * k);
                    const dims = Math.round(win.dw * k) + " × " + Math.round(win.dh * k);
                    return win.target === "screen" ? "Screen  ·  " + dims : dims;
                }
            }
        }

        // ---- a window that is not on screen, or a workspace: shown here instead of in the box ----
        Rectangle {
            id: windowPeek
            readonly property bool on: win.active && win.target === "window" && !!win.winSel && !win.winOnScreen
            readonly property real fit: win.winSel ? Math.min(win.sw * 0.6 / win.winSel.w, win.sh * 0.46 / win.winSel.h, 1) : 1
            readonly property real picW: win.winSel ? win.winSel.w * fit : 0
            readonly property real picH: win.winSel ? win.winSel.h * fit : 0
            width: Math.max(360, picW + 24)
            height: picH + 24 + 52
            x: (win.sw - width) / 2
            y: (win.sh * 0.42 - height / 2)
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            opacity: on ? 1 : 0
            scale: on ? 1 : 0.86
            visible: opacity > 0.02
            Behavior on opacity { Fade {} }
            Behavior on scale { Spring { speed: "default" } }
            ClippingRectangle {
                x: (parent.width - width) / 2
                y: 12
                width: windowPeek.picW
                height: windowPeek.picH
                radius: 18
                color: Colors.surface_container_lowest
                CaptureThumb {
                    id: peekThumb
                    anchors.fill: parent
                    addr: win.selWin
                }
            }
            Row {
                x: 20
                y: parent.height - 44
                spacing: 8
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "titleSmall"
                    emphasized: true
                    text: win.winSel ? win.winSel.cls : ""
                }
                Rectangle {
                    anchors.verticalCenter: parent.verticalCenter
                    height: 24
                    width: peekWs.implicitWidth + 18
                    radius: 12
                    color: Colors.secondary_container
                    StyledText {
                        id: peekWs
                        anchors.centerIn: parent
                        role: "labelMedium"
                        emphasized: true
                        color: Colors.on_secondary_container
                        text: win.winSel ? Capture.wsLabel(Capture.workspaceById(win.winSel.ws)) : ""
                    }
                }
                // it is not drawn while it is out of view, so it is scrolled in for a moment to be captured
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    opacity: !peekThumb.hasContent ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    role: "labelMedium"
                    color: Colors.on_surface_variant
                    text: win.video ? "Scrolls into view to record" : "Scrolls into view for the capture"
                }
            }
        }
        Rectangle {
            id: wsPeek
            readonly property bool on: win.active && win.target === "workspace" && !!win.wsSel
            readonly property var bounds: Capture.wsBounds(win.wsSel)
            // the map is as big as fits, and the card is as big as the map
            readonly property real availW: win.sw * 0.8 - 40
            readonly property real availH: win.sh * 0.4
            readonly property real fit: Math.min(availW / bounds.w, availH / bounds.h)
            readonly property real mapW: bounds.w * fit
            readonly property real mapH: bounds.h * fit
            width: Math.max(380, mapW + 40)
            height: mapH + 40 + 44
            x: (win.sw - width) / 2
            y: win.sh * 0.4 - height / 2
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            opacity: on ? 1 : 0
            scale: on ? 1 : 0.86
            visible: opacity > 0.02
            Behavior on opacity { Fade {} }
            Behavior on scale { Spring { speed: "default" } }
            CaptureMap {
                x: (parent.width - width) / 2
                y: 20
                width: wsPeek.mapW
                height: wsPeek.mapH
                ws: win.wsSel
                mon: Capture.mon
                thumbs: wsPeek.on
                corner: 10
                // a recording is of the monitor only: that is the part that stands out
                screenColor: win.video ? Qt.alpha(Colors.primary, 0.28) : Qt.alpha(Colors.on_surface, 0.12)
            }
            StyledText {
                x: 24
                y: parent.height - 38
                role: "titleSmall"
                emphasized: true
                text: {
                    if (!win.wsSel)
                        return "";
                    const n = win.wsSel.windows.length;
                    const head = Capture.wsLabel(win.wsSel) + "  ·  " + n + (n === 1 ? " window" : " windows");
                    if (win.video)
                        return head + "  ·  records the screen";
                    return head + "  ·  " + Math.round(wsPeek.bounds.w * Capture.mon.scale) + " × " + Math.round(wsPeek.bounds.h * Capture.mon.scale);
                }
            }
        }
    }

    // ---- mouse ----
    MouseArea {
        id: mouse
        anchors.fill: parent
        enabled: win.active
        hoverEnabled: true
        cursorShape: win.target === "region" ? Qt.CrossCursor : win.target === "window" && win.hoverWin !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        property string mode: ""
        property real px: 0
        property real py: 0
        property bool moved: false
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
        onPressed: m => {
            win.helpOpen = false;
            if (win.target === "window") {
                const hit = win.windowAt(m.x, m.y);
                if (hit !== "")
                    win.selWin = hit;
                return;
            }
            if (win.target !== "region")
                return;
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
                start = { x: m.x, y: m.y, w: 1, h: 1 };
            }
            win.presetIndex = -1;
        }
        onPositionChanged: m => {
            if (win.target === "window" && !pressed) {
                win.hoverWin = win.windowAt(m.x, m.y);
                return;
            }
            if (!pressed || win.target !== "region")
                return;
            const dx = m.x - px, dy = m.y - py;
            if (Math.abs(dx) + Math.abs(dy) > 4)
                moved = true;
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
            if (win.target !== "region")
                return;
            win.dragging = false;
            // a click or a sliver is not a selection: put the old box back
            if (win.selW < 12 || win.selH < 12)
                win.setRect(before.w >= 12 ? before.x : win.sw * 0.2, before.w >= 12 ? before.y : win.sh * 0.2,
                            before.w >= 12 ? before.w : win.sw * 0.6, before.w >= 12 ? before.h : win.sh * 0.6);
        }
        onDoubleClicked: win.shoot()
    }

    // ---- keyboard ----
    Item {
        id: keys
        anchors.fill: parent
        focus: win.active
        Keys.onPressed: e => {
            const stepPx = (e.modifiers & Qt.ControlModifier) ? 50 : (e.modifiers & Qt.ShiftModifier) ? 1 : 10;
            const resize = (e.modifiers & Qt.AltModifier) !== 0;
            e.accepted = true;
            const region = win.target === "region";
            switch (e.key) {
            case Qt.Key_Escape:
                if (win.helpOpen)
                    win.helpOpen = false;
                else
                    Capture.cancel();
                break;
            case Qt.Key_Return:
            case Qt.Key_Enter:
            case Qt.Key_Space:
                win.shoot();
                break;
            case Qt.Key_Left:
                if (!region) win.step(-1);
                else { resize ? win.setRect(win.selX, win.selY, win.selW - stepPx, win.selH) : win.setRect(win.selX - stepPx, win.selY, win.selW, win.selH); win.presetIndex = -1; }
                break;
            case Qt.Key_Right:
                if (!region) win.step(1);
                else { resize ? win.setRect(win.selX, win.selY, win.selW + stepPx, win.selH) : win.setRect(win.selX + stepPx, win.selY, win.selW, win.selH); win.presetIndex = -1; }
                break;
            case Qt.Key_Up:
                if (region) { resize ? win.setRect(win.selX, win.selY, win.selW, win.selH - stepPx) : win.setRect(win.selX, win.selY - stepPx, win.selW, win.selH); win.presetIndex = -1; }
                break;
            case Qt.Key_Down:
                if (region) { resize ? win.setRect(win.selX, win.selY, win.selW, win.selH + stepPx) : win.setRect(win.selX, win.selY + stepPx, win.selW, win.selH); win.presetIndex = -1; }
                break;
            case Qt.Key_Tab:
                region ? win.cyclePreset(1) : win.step(1);
                break;
            case Qt.Key_Backtab:
                region ? win.cyclePreset(-1) : win.step(-1);
                break;
            case Qt.Key_P:
                Capture.setMode("photo");
                break;
            case Qt.Key_V:
                Capture.setMode("video");
                break;
            case Qt.Key_1:
                Capture.setTarget("region");
                break;
            case Qt.Key_2:
                Capture.setTarget("window");
                break;
            case Qt.Key_3:
                Capture.setTarget("workspace");
                break;
            case Qt.Key_4:
                Capture.setTarget("screen");
                break;
            case Qt.Key_D:
                Capture.cycleDelay();
                break;
            case Qt.Key_C:
                Capture.setPointer(!Capture.pointer);
                break;
            case Qt.Key_A:
                Capture.cycleAudio();
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

    // ---- the strip: every window, or every workspace ----
    Item {
        id: stripBox
        readonly property real appear: win.active && win.strip ? 1 : 0
        property real shown: appear
        Behavior on shown { Spring { speed: "default" } }
        width: Math.min(win.sw - 48, Math.max(200, flick.contentWidth + 24))
        height: 140
        x: (win.sw - width) / 2
        y: toolbar.y - height - 12 + (1 - shown) * 36
        opacity: Math.max(0, Math.min(1, shown * 1.4))
        visible: opacity > 0.02

        Elevation {
            anchors.fill: stripBg
            radius: stripBg.radius
            level: 3
        }
        Rectangle {
            id: stripBg
            anchors.fill: parent
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container
        }
        Flickable {
            id: flick
            anchors.fill: parent
            anchors.margins: 8
            contentWidth: stripRow.width + 8
            contentHeight: height
            clip: true
            boundsBehavior: Flickable.StopAtBounds
            flickableDirection: Flickable.HorizontalFlick
            Behavior on contentX { enabled: !flick.dragging && !flick.flicking; Spring { speed: "default" } }
            WheelHandler {
                onWheel: e => flick.contentX = Math.max(0, Math.min(flick.contentWidth - flick.width, flick.contentX - (e.angleDelta.y + e.angleDelta.x)))
            }
            // keep the chosen card in view
            function reveal(x, w) {
                if (x < contentX)
                    contentX = Math.max(0, x - 8);
                else if (x + w > contentX + width)
                    contentX = Math.min(contentWidth - width, x + w - width + 8);
            }

            // a little room around the cards, for the selected one to swell into
            Row {
                id: stripRow
                x: 4
                y: 4
                spacing: 8
                Repeater {
                    model: win.target === "window" ? Capture.windows : []
                    delegate: Item {
                        id: wcard
                        required property var modelData
                        readonly property bool sel: win.selWin === modelData.addr
                        width: 176
                        height: 116
                        scale: sel ? 1.04 : cardHover.hovered ? 1.02 : 1
                        Behavior on scale { Spring { speed: "fast" } }
                        onSelChanged: if (sel) flick.reveal(x + 4, width)
                        HoverHandler { id: cardHover }
                        Rectangle {
                            anchors.fill: parent
                            radius: Motion.shapeLarge
                            color: wcard.sel ? Colors.primary_container : cardHover.hovered ? Colors.surface_container_highest : Colors.surface_container_high
                            Behavior on color { ColorFade {} }
                        }
                        ClippingRectangle {
                            x: 8
                            y: 8
                            width: parent.width - 16
                            height: 70
                            radius: Motion.shapeMedium
                            color: Colors.surface_container_lowest
                            CaptureThumb {
                                readonly property real f: Math.min(parent.width / wcard.modelData.w, parent.height / wcard.modelData.h)
                                anchors.centerIn: parent
                                width: wcard.modelData.w * f
                                height: wcard.modelData.h * f
                                addr: wcard.modelData.addr
                            }
                            Rectangle {
                                x: 6
                                y: 6
                                height: 20
                                width: Math.max(20, wsText.implicitWidth + 14)
                                radius: 10
                                color: wcard.modelData.ws === Capture.mon.ws ? Colors.primary : Colors.secondary_container
                                StyledText {
                                    id: wsText
                                    anchors.centerIn: parent
                                    role: "labelSmall"
                                    emphasized: true
                                    color: wcard.modelData.ws === Capture.mon.ws ? Colors.on_primary : Colors.on_secondary_container
                                    text: wcard.modelData.wsName.replace(/^special:/, "")
                                }
                            }
                        }
                        StyledText {
                            x: 12
                            y: 82
                            width: parent.width - 24
                            elide: Text.ElideRight
                            role: "labelLarge"
                            emphasized: true
                            color: wcard.sel ? Colors.on_primary_container : Colors.on_surface
                            text: wcard.modelData.cls
                        }
                        StyledText {
                            x: 12
                            y: 100
                            width: parent.width - 24
                            elide: Text.ElideRight
                            role: "labelSmall"
                            color: wcard.sel ? Colors.on_primary_container : Colors.on_surface_variant
                            text: wcard.modelData.title
                        }
                        TapHandler {
                            onTapped: win.selWin = wcard.modelData.addr
                            onDoubleTapped: win.shoot()
                        }
                    }
                }
                Repeater {
                    model: win.target === "workspace" ? Capture.workspaces : []
                    delegate: Item {
                        id: scard
                        required property var modelData
                        readonly property bool sel: win.selWs === modelData.id
                        width: 188
                        height: 116
                        scale: sel ? 1.04 : sHover.hovered ? 1.02 : 1
                        Behavior on scale { Spring { speed: "fast" } }
                        onSelChanged: if (sel) flick.reveal(x + 4, width)
                        HoverHandler { id: sHover }
                        Rectangle {
                            anchors.fill: parent
                            radius: Motion.shapeLarge
                            color: scard.sel ? Colors.primary_container : sHover.hovered ? Colors.surface_container_highest : Colors.surface_container_high
                            Behavior on color { ColorFade {} }
                        }
                        CaptureMap {
                            x: 10
                            y: 10
                            width: parent.width - 20
                            height: 64
                            ws: scard.modelData
                            mon: Capture.mon
                            corner: 3
                        }
                        StyledText {
                            x: 12
                            y: 82
                            width: parent.width - 24
                            elide: Text.ElideRight
                            role: "labelLarge"
                            emphasized: true
                            color: scard.sel ? Colors.on_primary_container : Colors.on_surface
                            text: Capture.wsLabel(scard.modelData) + (scard.modelData.active ? "  ·  here" : "")
                        }
                        StyledText {
                            x: 12
                            y: 100
                            width: parent.width - 24
                            elide: Text.ElideRight
                            role: "labelSmall"
                            color: scard.sel ? Colors.on_primary_container : Colors.on_surface_variant
                            text: scard.modelData.windows.length + (scard.modelData.windows.length === 1 ? " window" : " windows")
                        }
                        TapHandler {
                            onTapped: win.selWs = scard.modelData.id
                            onDoubleTapped: win.shoot()
                        }
                    }
                }
            }
        }

        // more cards than fit: the edges fade out instead of cutting a card in half
        Rectangle {
            x: 8
            y: 8
            width: 44
            height: parent.height - 16
            opacity: flick.contentX > 2 ? 1 : 0
            Behavior on opacity { Fade {} }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Colors.surface_container }
                GradientStop { position: 1; color: Qt.alpha(Colors.surface_container, 0) }
            }
        }
        Rectangle {
            x: parent.width - 8 - width
            y: 8
            width: 44
            height: parent.height - 16
            opacity: flick.contentX < flick.contentWidth - flick.width - 2 ? 1 : 0
            Behavior on opacity { Fade {} }
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0; color: Qt.alpha(Colors.surface_container, 0) }
                GradientStop { position: 1; color: Colors.surface_container }
            }
        }
    }

    // ---- the toolbar ----
    Elevation {
        x: toolbar.x
        y: toolbar.y
        width: toolbar.width
        height: toolbar.height
        radius: toolbar.radius
        level: 3
        opacity: toolbar.opacity
        scale: toolbar.scale
    }
    Rectangle {
        id: toolbar
        height: 72
        // exactly as wide as its content: the parts whose width changes (the audio slot, the labels of the
        // delay and audio buttons) ease on their own, and the pill follows them frame by frame
        width: toolRow.implicitWidth + 32
        radius: height / 2
        color: Colors.surface_container_high
        x: (win.sw - width) / 2
        readonly property real appear: win.active ? 1 : 0
        property real shown: appear
        Behavior on shown { Spring { speed: "default" } }
        y: win.sh - height - 28 + (1 - shown) * 50
        opacity: Math.max(0, Math.min(1, shown * 1.6))
        scale: 0.94 + 0.06 * shown
        transformOrigin: Item.Bottom

        RowLayout {
            id: toolRow
            anchors.centerIn: parent
            spacing: 14

            // photo | video
            Row {
                spacing: 2
                ConnectedButton {
                    height: 44
                    position: "first"
                    icon: "photo_camera"
                    text: "Photo"
                    selected: !win.video
                    onClicked: Capture.setMode("photo")
                }
                ConnectedButton {
                    height: 44
                    position: "last"
                    icon: "videocam"
                    text: "Video"
                    selected: win.video
                    onClicked: Capture.setMode("video")
                }
            }

            // what to capture: a pill slides between the four
            Rectangle {
                id: seg
                Layout.preferredWidth: segRow.width + 8
                Layout.preferredHeight: 48
                radius: 24
                color: Colors.surface_container_highest
                readonly property var items: [
                    { k: "region", t: "Region", i: "crop_free", w: 112 },
                    { k: "window", t: "Window", i: "web_asset", w: 114 },
                    { k: "workspace", t: "Workspace", i: "view_carousel", w: 138 },
                    { k: "screen", t: "Screen", i: "desktop_windows", w: 108 }
                ]
                readonly property int idx: Math.max(0, items.findIndex(x => x.k === win.target))
                Rectangle {
                    y: 4
                    height: 40
                    width: seg.items[seg.idx].w
                    x: 4 + seg.items.slice(0, seg.idx).reduce((a, b) => a + b.w, 0)
                    radius: 20
                    color: Colors.secondary_container
                    Behavior on x { Spring { speed: "default" } }
                    Behavior on width { Spring { speed: "default" } }
                }
                Row {
                    id: segRow
                    x: 4
                    y: 4
                    Repeater {
                        model: seg.items
                        delegate: Clickable {
                            id: segBtn
                            required property var modelData
                            width: modelData.w
                            height: 40
                            restRadius: 20
                            pressedRadius: 14
                            onClicked: Capture.setTarget(modelData.k)
                            Row {
                                anchors.centerIn: parent
                                spacing: 6
                                Icon {
                                    anchors.verticalCenter: parent.verticalCenter
                                    size: 20
                                    name: segBtn.modelData.i
                                    color: win.target === segBtn.modelData.k ? Colors.on_secondary_container : Colors.on_surface_variant
                                }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "labelLarge"
                                    emphasized: true
                                    color: win.target === segBtn.modelData.k ? Colors.on_secondary_container : Colors.on_surface_variant
                                    text: segBtn.modelData.t
                                }
                            }
                        }
                    }
                }
            }

            // pointer, delay, audio
            Row {
                spacing: 0
                IconButton {
                    anchors.verticalCenter: parent.verticalCenter
                    icon: "mouse"
                    style: "tonal"
                    size: "xs"
                    checkable: true
                    checked: Capture.pointer
                    onClicked: Capture.setPointer(!Capture.pointer)
                }
                Item { width: 6; height: 1 }
                // the label changes with the delay, so the button eases to its new width
                Button {
                    id: delayBtn
                    anchors.verticalCenter: parent.verticalCenter
                    size: "xs"
                    style: "tonal"
                    icon: "timer"
                    text: Capture.delay === 0 ? "No delay" : Capture.delay + " s"
                    property real eased: implicitWidth
                    Behavior on eased { Spring { speed: "default" } }
                    width: Math.max(0, eased)
                    onClicked: Capture.cycleDelay()
                }
                // only a recording has sound. It is an icon button, like the pointer one, so the toolbar hardly
                // grows (38 px, not 100): the slot widens a little and the button pops into it, nothing is wiped
                // in by a clip and the Photo / Video buttons stay under the pointer
                Item {
                    id: audioSlot
                    anchors.verticalCenter: parent.verticalCenter
                    height: 32
                    property real shown: win.video ? 38 : 0
                    Behavior on shown { Spring { speed: "default" } }
                    width: Math.max(0, shown)
                    IconButton {
                        id: audioBtn
                        x: 6
                        anchors.verticalCenter: parent.verticalCenter
                        icon: Capture.audio === "off" ? "volume_off" : Capture.audio === "both" ? "mic" : "volume_up"
                        style: "tonal"
                        size: "xs"
                        checkable: true
                        checked: Capture.audio !== "off"
                        opacity: win.video ? 1 : 0
                        Behavior on opacity { Fade {} }
                        scale: win.video ? 1 : 0.3
                        Behavior on scale { Spring { speed: "fast" } }
                        onClicked: Capture.cycleAudio()
                    }
                }
            }

            // the shutter: always turning. A cookie for a photo, a boom (recording) for a video; it turns
            // faster under the pointer and squeezes when pressed
            ShapeBadge {
                id: shutter
                Layout.preferredWidth: 60
                Layout.preferredHeight: 60
                shapeRest: "cookie4"
                shapeActive: "boom"
                active: win.video
                spinning: win.active
                spinSpeed: shutterArea.containsMouse ? 70 : 22
                color: win.video ? Colors.error : Colors.primary
                badgeScale: shutterArea.pressed ? 0.88 : shutterArea.containsMouse ? 1.1 : 1
                Icon {
                    anchors.centerIn: parent
                    size: 28
                    name: win.video ? "videocam" : "photo_camera"
                    color: win.video ? Colors.on_error : Colors.on_primary
                }
                MouseArea {
                    id: shutterArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: win.shoot()
                }
            }
            IconButton { icon: "close"; style: "tonal"; size: "xs"; onClicked: Capture.cancel() }
            IconButton { icon: "help"; size: "xs"; checkable: true; checked: win.helpOpen; onClicked: win.helpOpen = !win.helpOpen }
        }
    }

    // ---- tips, only when asked for ----
    Rectangle {
        id: helpCard
        readonly property var rows: [
            { keys: ["P", "V"], text: "Photo / video" },
            { keys: ["1", "2", "3", "4"], text: "Region / window / workspace / screen" },
            { keys: ["←", "→"], text: "Previous / next window or workspace" },
            { keys: ["←↑↓→"], text: "Move the region" },
            { keys: ["Alt", "arrows"], text: "Resize the region" },
            { keys: ["Tab"], text: "Next preset or item" },
            { keys: ["D"], text: "Delay" },
            { keys: ["C"], text: "Pointer in the capture" },
            { keys: ["A"], text: "Audio (video)" },
            { keys: ["Enter", "Space"], text: "Capture" },
            { keys: ["Esc"], text: "Cancel" }
        ]
        width: 340
        height: helpCol.implicitHeight + 28
        radius: Motion.shapeLarge
        color: Colors.inverse_surface
        x: Math.max(12, Math.min(win.sw - width - 12, toolbar.x + toolbar.width - width))
        y: Math.max(12, toolbar.y - 12 - stripBox.shown * (stripBox.height + 12) - height)
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
                        Layout.preferredWidth: 112
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
