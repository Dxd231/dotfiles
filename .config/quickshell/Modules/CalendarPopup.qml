pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components

// Clock + an exaggerated M3 Expressive date picker: one selection shape that springs between
// days and morphs on every pick, a month name that rolls, cells that pop in along the diagonal.
BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 380

    property var today: new Date()
    property var selectedDate: new Date()
    // the month on show: set once (not bound to `today`, which ticks every second and would rebuild the grid)
    property var viewDate: { const n = new Date(); return new Date(n.getFullYear(), n.getMonth(), 1); }
    readonly property var gridCells: buildGrid(viewDate)

    readonly property int cell: 44
    readonly property int gap: 4
    readonly property int selIndex: gridCells.findIndex(c => isSameDay(c.date, selectedDate))
    readonly property int todayIndex: gridCells.findIndex(c => isSameDay(c.date, today))
    // the clock part of the popup is "away from today" when the picker has moved off it
    readonly property bool offToday: !isSameDay(selectedDate, today) || viewDate.getMonth() !== today.getMonth() || viewDate.getFullYear() !== today.getFullYear()

    // selection shape: the blob and the hero card share it; indices are MorphShape's
    readonly property var shapeCycle: [1, 5, 4, 2, 0]
    property int selShape: 1
    property int selFrom: 1
    property real selMorph: 1
    property bool selSpring: true
    property real spin: 0

    // month change: direction of travel, pop-in progress and the grid's slide offset
    property int monthDir: 1
    property real monthPhase: 1
    property real slide: 0
    property bool slideSpring: true
    property int _prevKey: viewDate.getFullYear() * 12 + viewDate.getMonth()

    function cellX(i) { return (i % 7) * (cell + gap); }
    function cellY(i) { return Math.floor(i / 7) * (cell + gap); }
    // overshooting ease for the per-cell pop
    function backOut(p) { const c1 = 2.2, c3 = c1 + 1; return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2); }

    function reset() {
        today = new Date();
        selectedDate = new Date();
        viewDate = new Date(today.getFullYear(), today.getMonth(), 1);
    }
    function shiftMonth(delta) {
        viewDate = new Date(viewDate.getFullYear(), viewDate.getMonth() + delta, 1);
    }
    function isSameDay(a, b) {
        return a.getFullYear() === b.getFullYear() && a.getMonth() === b.getMonth() && a.getDate() === b.getDate();
    }
    function relativeDay(target) {
        const t = new Date(today.getFullYear(), today.getMonth(), today.getDate());
        const d = new Date(target.getFullYear(), target.getMonth(), target.getDate());
        const n = Math.round((d - t) / 86400000);
        return n === 0 ? "Today" : n === 1 ? "Tomorrow" : n === -1 ? "Yesterday" : n > 1 ? `In ${n} days` : `${-n} days ago`;
    }
    function dayOfYear(date) {
        return Math.floor((date - new Date(date.getFullYear(), 0, 0)) / 86400000);
    }
    function weekNumber(date) {
        const d = new Date(Date.UTC(date.getFullYear(), date.getMonth(), date.getDate()));
        d.setUTCDate(d.getUTCDate() + 4 - (d.getUTCDay() || 7));
        return Math.ceil(((d - new Date(Date.UTC(d.getUTCFullYear(), 0, 1))) / 86400000 + 1) / 7);
    }
    function buildGrid(vd) {
        const year = vd.getFullYear(), month = vd.getMonth();
        const first = new Date(year, month, 1).getDay();
        const cells = [];
        for (let i = 0; i < 42; i++) {
            const d = new Date(year, month, 1 - first + i);
            cells.push({ date: d, inMonth: d.getMonth() === month });
        }
        return cells;
    }

    onIsOpenChanged: {
        if (!isOpen)
            return;
        today = new Date();
        monthDir = 1;
        monthAnim.restart();
    }

    // a new month: remember which way we went, pop the cells in and throw the grid sideways
    onViewDateChanged: {
        const key = viewDate.getFullYear() * 12 + viewDate.getMonth();
        if (key === _prevKey)
            return;
        monthDir = key > _prevKey ? 1 : -1;
        _prevKey = key;
        monthAnim.restart();
        slideSpring = false;
        slide = monthDir * 44;
        slideSpring = true;
        slide = 0;
    }
    // a new selection: next shape, snap the morph back to 0 and let it spring (and overshoot) to 1
    onSelectedDateChanged: {
        _save();
        selFrom = selShape;
        selShape = shapeCycle[(shapeCycle.indexOf(selShape) + 1) % shapeCycle.length];
        selSpring = false;
        selMorph = 0;
        selSpring = true;
        selMorph = 1;
    }
    Behavior on selMorph {
        enabled: win.selSpring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }
    Behavior on slide {
        enabled: win.slideSpring
        SpringAnimation { spring: 2.6; damping: 0.2; epsilon: 0.1 }
    }
    NumberAnimation {
        id: monthAnim
        target: win
        property: "monthPhase"
        from: 0
        to: 1
        duration: 700
    }
    FrameAnimation {
        running: win.isOpen
        onTriggered: win.spin = (win.spin + frameTime * 10) % 360
    }

    // ---- the highlighted day survives reloads and restarts ----
    // Picking today means "follow today", which stores nothing; any other day is saved and shown again
    // (on its month) next time. The Today button clears it.
    function _save() {
        adapter.selected = isSameDay(selectedDate, today) ? "" : Qt.formatDate(selectedDate, "yyyy-MM-dd");
        store.writeAdapter();
    }
    FileView {
        id: store
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/calendar.json"
        printErrors: false
        blockLoading: true

        onLoaded: {
            const parts = String(adapter.selected || "").split("-").map(Number);
            if (parts.length !== 3 || parts.some(isNaN))
                return;
            const d = new Date(parts[0], parts[1] - 1, parts[2]);
            if (isNaN(d.getTime()))
                return;
            win.selectedDate = d;
            win.viewDate = new Date(d.getFullYear(), d.getMonth(), 1);
        }

        JsonAdapter {
            id: adapter
            property string selected: ""
        }
    }

    IpcHandler {
        target: "calendar"
        function toggle(): void { win.toggle(); }
        function show(): void { win.show(); }
        function open(): void { win.show(); }
        function hide(): void { win.hide(); }
        function close(): void { win.hide(); }
    }

    Timer {
        interval: 1000
        running: win.isOpen
        repeat: true
        onTriggered: win.today = new Date()
    }

    // ---- clock ----
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Row {
                spacing: 4
                StyledText {
                    id: hhmm
                    role: "displayMedium"
                    emphasized: true
                    text: Qt.formatTime(win.today, "HH:mm")
                }
                StyledText {
                    anchors.baseline: hhmm.baseline
                    role: "titleLarge"
                    color: Colors.primary
                    text: Qt.formatTime(win.today, "ss")
                }
            }
            StyledText {
                role: "bodyMedium"
                color: Colors.on_surface_variant
                text: Qt.formatDate(win.today, "dddd, MMMM d, yyyy")
            }
        }

        // pops in only while the picker is away from today
        Button {
            text: "Today"
            icon: "today"
            style: "tonal"
            enabled: win.offToday
            opacity: win.offToday ? 1 : 0
            scale: win.offToday ? 1 : 0.4
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            onClicked: win.reset()
        }
    }

    // ---- month bar ----
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        spacing: 8

        // the month name rolls up or down depending on the direction of travel; the year stays put
        Item {
            id: monthRoll
            Layout.fillWidth: true
            implicitHeight: monthNow.implicitHeight
            readonly property string target: Qt.formatDate(win.viewDate, "MMMM")
            property string shown: target

            onTargetChanged: {
                if (target === shown)
                    return;
                monthNext.text = target;
                monthShift.restart();
            }

            Row {
                spacing: 8

                Item {
                    id: monthClip
                    height: monthRoll.height
                    clip: true
                    // wide enough for whichever name is on show, springing between widths
                    width: Math.max(monthNow.implicitWidth, monthShift.running ? monthNext.implicitWidth : 0)
                    Behavior on width { Spring { speed: "fast"; expressive: false } }

                    StyledText {
                        id: monthNow
                        role: "headlineMedium"
                        emphasized: true
                        text: monthRoll.shown
                    }
                    StyledText {
                        id: monthNext
                        role: "headlineMedium"
                        emphasized: true
                        visible: monthShift.running
                        y: win.monthDir * monthRoll.height
                    }
                }
                StyledText {
                    id: yearText
                    y: monthRoll.height - height - 2
                    role: "titleLarge"
                    color: Colors.primary
                    text: Qt.formatDate(win.viewDate, "yyyy")
                }
            }
            ParallelAnimation {
                id: monthShift
                NumberAnimation { target: monthNow; property: "y"; from: 0; to: -win.monthDir * monthRoll.height; duration: Motion.expressiveFastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                NumberAnimation { target: monthNext; property: "y"; from: win.monthDir * monthRoll.height; to: 0; duration: Motion.expressiveFastSpatialDuration; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.expressiveFastSpatial }
                onFinished: {
                    monthRoll.shown = monthNext.text;
                    monthNow.y = 0;
                }
            }
        }

        IconButton { icon: "chevron_left"; style: "tonal"; onClicked: win.shiftMonth(-1) }
        IconButton { icon: "chevron_right"; style: "tonal"; onClicked: win.shiftMonth(1) }
    }

    // ---- day grid ----
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: pickerCol.implicitHeight + 16
        radius: Motion.shapeLarge
        color: Colors.surface_container_high
        clip: true

        ColumnLayout {
            id: pickerCol
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 4

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: win.gap
                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: StyledText {
                        required property string modelData
                        width: win.cell
                        height: 32
                        horizontalAlignment: Text.AlignHCenter
                        role: "labelLarge"
                        emphasized: true
                        color: Colors.primary
                        text: modelData
                    }
                }
            }

            Item {
                Layout.alignment: Qt.AlignHCenter
                implicitWidth: 7 * win.cell + 6 * win.gap
                implicitHeight: 6 * win.cell + 5 * win.gap

                // everything in the grid is thrown sideways on a month change and springs back
                Item {
                    anchors.fill: parent
                    transform: Translate { x: win.slide }

                    // today: a soft burst under the number
                    MorphShape {
                        width: 42
                        height: 42
                        shape: "softBurst"
                        fromShape: "softBurst"
                        color: Colors.secondary_container
                        x: win.cellX(Math.max(0, win.todayIndex)) + (win.cell - width) / 2
                        y: win.cellY(Math.max(0, win.todayIndex)) + (win.cell - height) / 2
                        scale: win.todayIndex >= 0 ? win.backOut(Math.min(1, win.monthPhase * 1.4)) : 0
                    }

                    // the selection: one shape that springs to the picked day and morphs as it lands
                    MorphShape {
                        id: blob
                        width: 54
                        height: 54
                        shape: win.selShape
                        fromShape: win.selFrom
                        morph: win.selMorph
                        spin: win.spin
                        color: Colors.primary
                        property real tx: win.cellX(Math.max(0, win.selIndex)) + (win.cell - width) / 2
                        property real ty: win.cellY(Math.max(0, win.selIndex)) + (win.cell - height) / 2
                        x: tx
                        y: ty
                        Behavior on x { SpringAnimation { spring: 2.4; damping: 0.16; epsilon: 0.2 } }
                        Behavior on y { SpringAnimation { spring: 2.4; damping: 0.16; epsilon: 0.2 } }
                        scale: win.selIndex >= 0 ? 1 : 0
                        Behavior on scale { Spring { speed: "default" } }
                    }

                    Repeater {
                        model: win.gridCells
                        delegate: Clickable {
                            id: day
                            required property var modelData
                            required property int index
                            readonly property bool isToday: win.isSameDay(modelData.date, win.today)
                            readonly property bool isSelected: index === win.selIndex
                            // staggered along the diagonal, one progress value for the whole grid
                            readonly property real delay: (index % 7 + Math.floor(index / 7)) / 11
                            readonly property real p: Math.max(0, Math.min(1, (win.monthPhase - delay * 0.45) / 0.55))

                            x: win.cellX(index)
                            y: win.cellY(index)
                            width: win.cell
                            height: win.cell
                            restRadius: width / 2
                            pressedRadius: Motion.shapeMedium
                            color: "transparent"
                            contentColor: isSelected ? Colors.on_primary : isToday ? Colors.on_secondary_container : Colors.on_surface
                            scale: win.backOut(p)
                            opacity: (modelData.inMonth ? 1 : Motion.disabledContent) * Math.min(1, p * 2.5)
                            onClicked: {
                                win.selectedDate = modelData.date;
                                if (!modelData.inMonth)
                                    win.viewDate = new Date(modelData.date.getFullYear(), modelData.date.getMonth(), 1);
                            }

                            StyledText {
                                anchors.centerIn: parent
                                role: day.isSelected || day.isToday ? "titleMedium" : "bodyLarge"
                                emphasized: day.isSelected || day.isToday
                                color: day.contentColor
                                text: day.modelData.date.getDate()
                            }
                        }
                    }
                }
            }
        }
    }

    // ---- selected date ----
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 4
        Layout.rightMargin: 4
        spacing: 16

        // the day number inside a hero shape that matches the selection
        Item {
            implicitWidth: 76
            implicitHeight: 76
            MorphShape {
                anchors.fill: parent
                shape: win.selShape
                fromShape: win.selFrom
                morph: win.selMorph
                spin: -win.spin
                color: Colors.tertiary_container
            }
            StyledText {
                anchors.centerIn: parent
                role: "headlineMedium"
                emphasized: true
                color: Colors.on_tertiary_container
                text: win.selectedDate.getDate()
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2
            StyledText { role: "titleMedium"; emphasized: true; text: Qt.formatDate(win.selectedDate, "dddd") }
            StyledText { role: "bodyMedium"; text: Qt.formatDate(win.selectedDate, "MMMM d, yyyy") }
            StyledText {
                role: "labelLarge"
                color: Colors.on_surface_variant
                text: `Week ${win.weekNumber(win.selectedDate)} · Day ${win.dayOfYear(win.selectedDate)}`
            }
        }

        // pops whenever its text changes
        Rectangle {
            id: relChip
            readonly property bool isToday: win.isSameDay(win.selectedDate, win.today)
            property bool popSpring: true
            implicitHeight: 36
            implicitWidth: relLabel.implicitWidth + 28
            radius: height / 2
            color: isToday ? Colors.primary : Colors.secondary_container
            Behavior on color { ColorFade {} }
            Behavior on scale {
                enabled: relChip.popSpring
                Spring { speed: "fast" }
            }

            StyledText {
                id: relLabel
                anchors.centerIn: parent
                role: "labelLarge"
                emphasized: true
                color: relChip.isToday ? Colors.on_primary : Colors.on_secondary_container
                text: win.relativeDay(win.selectedDate)
                onTextChanged: {
                    relChip.popSpring = false;
                    relChip.scale = 0.55;
                    relChip.popSpring = true;
                    relChip.scale = 1;
                }
            }
        }
    }
}
