import QtQuick
import qs
import qs.Services

// GitHub-style habit heatmap: one column per week (Sunday on top), one cell per day. Done days are
// circles in the task's accent, shaded by how much happened that day; missed days stay rounded squares.
// A click ticks a day (or, with `selectMode` / `dayInfo`, selects it: `daySelected`, and `selectedKey`
// marks it with a soft shape that glides between days). Without a task it draws a dim sample so the
// panel isn't empty.
Item {
    id: grid

    property var task: null
    // other trackers can colour the days themselves: key -> { level: 0..4, label: "1h 12m" }.
    // The grid then ticks nothing; a click emits daySelected instead
    property var dayInfo: null
    // a click selects a day instead of ticking it (the owner ticks with tickDay); dayInfo grids always select
    property bool selectMode: false
    // the selected day, marked on the grid
    property string selectedKey: ""
    readonly property string taskId: task ? task.id : ""
    property int weeks: 17
    property real cell: 16
    property real gap: 4
    // how many weeks the window is moved back from the current one
    property int endOffset: 0
    property color accent: task ? Tasks.accentFor(task) : Colors.primary

    readonly property real labelW: 22
    readonly property real monthH: 22
    readonly property real step: cell + gap
    readonly property real gridW: weeks * step - gap
    readonly property real gridH: 7 * step - gap
    readonly property bool ghost: !task && !dayInfo

    // the day a click just changed, for pop and burst effects
    signal marked(string key, bool done)
    // right click on a day: its cell data and where it sits (in this item's coordinates)
    signal dayMenu(var cell, real x, real y, real size)
    signal daySelected(string key)

    implicitWidth: labelW + gridW
    implicitHeight: monthH + gridH + 8 + 24

    // ---- model: index = column * 7 + row ----
    function build(t, todayKey, off, count) {
        const today = Tasks.dateOf(todayKey);
        const sunday = Tasks.addDays(today, -today.getDay());
        const start = Tasks.addDays(sunday, -7 * (off + count - 1));
        const out = [];
        for (let c = 0; c < count; c++) {
            for (let r = 0; r < 7; r++) {
                const d = Tasks.addDays(start, c * 7 + r);
                const k = Tasks.keyOf(d);
                let state, level = 0, note = "", sessions = 0, count = 0, target = 1, label = "";
                if (t) {
                    note = Tasks.noteOf(t, k);
                    sessions = Tasks.sessionsOf(t, k);
                    count = Tasks.countOf(t, k);
                    target = Tasks.targetOf(t);
                }
                if (k > todayKey) {
                    state = "future";
                } else if (grid.dayInfo) {
                    const inf = grid.dayInfo(k) || ({});
                    label = inf.label || "";
                    level = inf.level || 0;
                    state = level > 0 ? "done" : k === todayKey ? "pending" : "missed";
                } else if (!t) {
                    // sample pattern for the empty state
                    const h = (c * 7 + r) * 37 % 11;
                    state = h < 5 ? "done" : "missed";
                    level = 1 + h % 4;
                } else if (Tasks.isSkipped(t, k)) {
                    state = "skipped";
                } else if (Tasks.isDone(t, k)) {
                    state = "done";
                    // shaded by how much happened: focus sessions on a plain task, the target reached for count tasks
                    level = target > 1 ? 4 : Math.min(4, 2 + sessions);
                } else if (count > 0) {
                    state = "partial";
                    level = Tasks.levelOfProgress(count / target);
                } else if (k < t.created) {
                    state = "before";
                } else if (!Tasks.isDue(t, d)) {
                    state = "off";
                } else {
                    state = k === todayKey ? "pending" : "missed";
                }
                out.push({ key: k, date: d, state: state, level: level, today: k === todayKey, col: c, row: r,
                           note: note, sessions: sessions, count: count, target: target, label: label });
            }
        }
        return out;
    }
    readonly property var cells: build(task, Tasks.todayKey, endOffset, weeks)
    readonly property int todayIndex: cells.findIndex(c => c.today)

    // month names above the column where each month starts
    readonly property var monthLabels: {
        const out = [];
        let prev = -1;
        for (let c = 0; c < weeks; c++) {
            const m = cells[c * 7].date.getMonth();
            if (m !== prev)
                out.push({ col: c, text: Qt.formatDate(cells[c * 7].date, "MMM") });
            prev = m;
        }
        // the first column's label would crowd the next one
        if (out.length > 1 && out[1].col - out[0].col < 3)
            out.shift();
        return out;
    }

    // ---- motion ----
    // entrance: cells pop in along the diagonal, driven by one progress value
    property real phase: 1
    function backOut(p) { const c1 = 2.2, c3 = c1 + 1; return 1 + c3 * Math.pow(p - 1, 3) + c1 * Math.pow(p - 1, 2); }
    NumberAnimation {
        id: phaseAnim
        target: grid
        property: "phase"
        from: 0
        to: 1
        duration: 800
    }
    function replay() { phaseAnim.restart(); }

    // tick (or undo) a day from outside the grid, with the same burst a click gives
    function tickDay(key) {
        if (!task)
            return;
        const c = cells.find(x => x.key === key);
        if (!c)
            return;
        const id = task.id;
        const was = Tasks.isDone(task, key);
        Tasks.tick(id, key);
        const now = Tasks.isDone(Tasks.byId(id), key);
        if (now && !was)
            burstAt(c.col, c.row);
        marked(key, now);
    }

    // paging or switching tasks throws the cells sideways and they spring back
    property real slide: 0
    property bool slideSpring: true
    Behavior on slide {
        enabled: grid.slideSpring
        SpringAnimation { spring: 2.6; damping: 0.2; epsilon: 0.1 }
    }
    onEndOffsetChanged: {
        slideSpring = false;
        slide = (endOffset > _prevOffset ? -1 : 1) * 44;
        slideSpring = true;
        slide = 0;
        _prevOffset = endOffset;
        replay();
    }
    property int _prevOffset: 0
    onTaskIdChanged: replay()

    // a burst of small shapes flies out of the cell that was just marked
    property real burstP: 1
    property real burstX: 0
    property real burstY: 0
    NumberAnimation {
        id: burstAnim
        target: grid
        property: "burstP"
        from: 0
        to: 1
        duration: 560
        easing.type: Easing.OutCubic
    }
    function burstAt(col, row) {
        burstX = col * step + cell / 2;
        burstY = row * step + cell / 2;
        burstAnim.restart();
    }

    // ---- hover bubble ----
    // the cell under the pointer right now (jumps around while the pointer sweeps across the grid) ...
    property int hoverIndex: -1
    // ... and the one the bubble and the swell settle on: the pointer has to rest on a cell for a
    // moment before anything reacts, and once the bubble is up it glides to the next cell without
    // closing in the gap between two cells
    property int focusIndex: -1
    property int hoverDelay: 140
    property int leaveDelay: 120
    readonly property var hoverCell: focusIndex >= 0 && focusIndex < cells.length ? cells[focusIndex] : null
    onHoverIndexChanged: {
        if (hoverIndex >= 0) {
            leaveTimer.stop();
            if (focusIndex >= 0)
                focusIndex = hoverIndex;
            else
                enterTimer.restart();
        } else {
            enterTimer.stop();
            if (focusIndex >= 0)
                leaveTimer.restart();
        }
    }
    Timer {
        id: enterTimer
        interval: grid.hoverDelay
        onTriggered: if (grid.hoverIndex >= 0) grid.focusIndex = grid.hoverIndex
    }
    Timer {
        id: leaveTimer
        interval: grid.leaveDelay
        onTriggered: grid.focusIndex = -1
    }
    function stateText(c) {
        if (grid.dayInfo)
            return c.label;
        let t;
        switch (c.state) {
        case "done": t = c.target > 1 ? c.count + " of " + c.target : "Done"; break;
        case "partial": t = c.count + " of " + c.target; break;
        case "skipped": t = "Rest day"; break;
        case "pending": t = "Due today"; break;
        case "missed": t = "Missed"; break;
        case "off": t = "Not scheduled"; break;
        default: t = "";
        }
        if (c.sessions > 0)
            t += " · " + c.sessions + (c.sessions === 1 ? " session" : " sessions");
        if (c.note)
            t += " · " + (c.note.length > 26 ? c.note.slice(0, 25) + "…" : c.note);
        return t;
    }

    // ---- weekday labels ----
    Repeater {
        model: [{ r: 1, t: "M" }, { r: 3, t: "W" }, { r: 5, t: "F" }]
        delegate: StyledText {
            required property var modelData
            x: 0
            y: grid.monthH + modelData.r * grid.step + (grid.cell - height) / 2
            role: "labelSmall"
            color: Colors.on_surface_variant
            text: modelData.t
        }
    }

    // ---- month labels ----
    Item {
        x: grid.labelW
        width: grid.gridW
        height: grid.monthH
        transform: Translate { x: grid.slide }
        Repeater {
            model: grid.monthLabels
            delegate: StyledText {
                required property var modelData
                x: modelData.col * grid.step
                anchors.verticalCenter: parent.verticalCenter
                role: "labelMedium"
                emphasized: true
                color: Colors.on_surface_variant
                text: modelData.text
                opacity: Math.min(1, grid.phase * 2)
            }
        }
    }

    // ---- the cells ----
    Item {
        id: field
        x: grid.labelW
        y: grid.monthH
        width: grid.gridW
        height: grid.gridH
        transform: Translate { x: grid.slide }

        // today: a soft burst behind its cell
        MorphShape {
            visible: grid.todayIndex >= 0
            width: grid.cell + 10
            height: grid.cell + 10
            shape: 0
            fromShape: 0
            color: Qt.alpha(grid.accent, 0.3)
            x: grid.todayIndex >= 0 ? grid.cells[grid.todayIndex].col * grid.step - 5 : 0
            y: grid.todayIndex >= 0 ? grid.cells[grid.todayIndex].row * grid.step - 5 : 0
            scale: grid.backOut(Math.min(1, grid.phase * 1.4))
            opacity: grid.ghost ? 0 : 1
        }

        // the selected day: a soft shape behind its cell. It lands on the first cell it is given, glides
        // from cell to cell while it is up, and stays where it was while it fades out
        MorphShape {
            id: pick
            readonly property int idx: grid.selectedKey === "" ? -1 : grid.cells.findIndex(c => c.key === grid.selectedKey)
            property int shownIdx: -1
            property bool glide: false
            readonly property var cellAt: shownIdx >= 0 && shownIdx < grid.cells.length ? grid.cells[shownIdx] : null
            onIdxChanged: {
                if (idx >= 0) {
                    glide = opacity > 0.05;
                    shownIdx = idx;
                }
            }
            visible: opacity > 0.02
            width: grid.cell + 12
            height: grid.cell + 12
            shape: 4
            fromShape: 4
            color: Qt.alpha(Colors.tertiary, 0.45)
            x: cellAt ? cellAt.col * grid.step - 6 : 0
            y: cellAt ? cellAt.row * grid.step - 6 : 0
            opacity: idx >= 0 ? 1 : 0
            scale: idx >= 0 ? 1 : 0.5
            Behavior on x { enabled: pick.glide; Spring { speed: "fast" } }
            Behavior on y { enabled: pick.glide; Spring { speed: "fast" } }
            Behavior on opacity { Fade {} }
            Behavior on scale { Spring { speed: "fast" } }
        }

        Repeater {
            // a cell count, not the cells: delegates stay put (and keep animating) while the data changes
            model: grid.weeks * 7
            delegate: Clickable {
                id: day
                required property int index
                readonly property var cd: grid.cells[index]

                readonly property bool isDone: cd.state === "done"
                readonly property bool showSquare: cd.state === "missed" || cd.state === "pending" || cd.state === "partial"
                readonly property bool exists: cd.state !== "future"
                // staggered along the diagonal
                readonly property real delay: (cd.col * 0.5 + cd.row) / (grid.weeks * 0.5 + 6)
                readonly property real p: Math.max(0, Math.min(1, (grid.phase - delay * 0.45) / 0.55))
                // kicked on a click: 0 -> 1 -> 0
                property real pop: 0

                x: cd.col * grid.step
                y: cd.row * grid.step
                width: grid.cell
                height: grid.cell
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                enabled: !grid.ghost && exists
                restRadius: isDone ? width / 2 : 5
                pressedRadius: isDone ? 5 : width / 2
                color: isDone ? Qt.alpha(grid.accent, [0.35, 0.55, 0.78, 1][Math.max(0, cd.level - 1)])
                    : showSquare ? (cd.today ? Colors.secondary_container : Colors.surface_container_highest)
                    : "transparent"
                contentColor: grid.accent
                // a click on a ticking grid kicks the cell hard; selecting only nudges it (and never on top of the hover swell)
                readonly property real popGain: grid.dayInfo || grid.selectMode ? 0.15 : 0.5
                scale: grid.backOut(p) * Math.max(1 + popGain * pop, grid.focusIndex === index && enabled ? 1.2 : 1)
                opacity: !exists ? 0 : (grid.ghost ? 0.32 : 1) * Math.min(1, p * 2.5)
                z: pop > 0 ? 2 : grid.focusIndex === index ? 1 : 0
                Behavior on scale { Spring { speed: "fast" } }
                Behavior on pop { Spring { speed: "fast" } }

                // days the task doesn't repeat on (or that predate it) are just a dot
                Rectangle {
                    visible: cd.state === "off" || cd.state === "before"
                    anchors.centerIn: parent
                    width: 4
                    height: 4
                    radius: 2
                    color: Colors.surface_container_highest
                }

                // count tasks: a part-way day shows how far it got
                Rectangle {
                    visible: cd.state === "partial"
                    anchors.centerIn: parent
                    width: 4 + 8 * (cd.target > 0 ? cd.count / cd.target : 0)
                    height: width
                    radius: width / 2
                    color: grid.accent
                }
                // rest day: a short dash
                Rectangle {
                    visible: cd.state === "skipped"
                    anchors.centerIn: parent
                    width: grid.cell * 0.62
                    height: 4
                    radius: 2
                    color: Colors.tertiary
                }
                // a day with a note
                Rectangle {
                    visible: cd.note !== ""
                    x: parent.width - width - 1
                    y: 1
                    width: 5
                    height: 5
                    radius: 2.5
                    color: cd.state === "done" ? Colors.on_primary : Colors.tertiary
                }

                onHoveredChanged: {
                    if (hovered)
                        grid.hoverIndex = index;
                    else if (grid.hoverIndex === index)
                        grid.hoverIndex = -1;
                }
                onClicked: mouse => {
                    if (grid.dayInfo || grid.selectMode) {
                        if (mouse.button === Qt.LeftButton) {
                            pop = 1;
                            popBack.restart();
                            grid.daySelected(cd.key);
                            return;
                        }
                        // a day tracker has no menu; a task grid goes on to its right-click menu
                        if (grid.dayInfo)
                            return;
                    }
                    if (!grid.task)
                        return;
                    if (mouse.button === Qt.RightButton) {
                        const p = day.mapToItem(grid, 0, 0);
                        grid.dayMenu(cd, p.x, p.y, day.width);
                        return;
                    }
                    const id = grid.task.id, key = cd.key, col = cd.col, row = cd.row;
                    const was = Tasks.isDone(grid.task, key);
                    Tasks.tick(id, key);
                    const now = Tasks.isDone(Tasks.byId(id), key);
                    pop = 1;
                    popBack.restart();
                    if (now && !was)
                        grid.burstAt(col, row);
                    grid.marked(key, now);
                }
                Timer {
                    id: popBack
                    interval: 120
                    onTriggered: day.pop = 0
                }
            }
        }

        // the burst: six small shapes thrown outward from the marked cell
        Repeater {
            model: 6
            delegate: MorphShape {
                required property int index
                readonly property real ang: index / 6 * Math.PI * 2 + 0.4
                readonly property real dist: 6 + 26 * grid.burstP
                width: 9
                height: 9
                shape: index % 2 === 0 ? 4 : 1
                fromShape: shape
                color: grid.accent
                x: grid.burstX + Math.cos(ang) * dist - width / 2
                y: grid.burstY + Math.sin(ang) * dist - height / 2
                scale: 1 - 0.7 * grid.burstP
                opacity: grid.burstP >= 1 ? 0 : 1 - grid.burstP * grid.burstP
                z: 3
            }
        }

        // date bubble over the hovered cell. It keeps the last cell it was on (and its words) while it fades
        // out, so it never flies off or empties as it goes; it sets itself down on a cell instantly when it
        // was hidden and glides between cells only while it is up. The container sits on the cell's centre
        // and the pill grows and shrinks around it, so one spring moves it and one spring sizes it.
        Item {
            id: bubble
            readonly property bool shown: !!grid.hoverCell && !grid.ghost && grid.hoverCell.state !== "future"
            property var lastCell: null
            property bool glide: false
            readonly property real fit: bubbleText.implicitWidth + 20
            property real wNow: fit
            // the cell's centre, kept inside the grid for the width the pill is heading for
            x: lastCell ? Math.max(fit / 2, Math.min(grid.gridW - fit / 2, lastCell.col * grid.step + grid.cell / 2)) : 0
            y: lastCell ? lastCell.row * grid.step - 28 - 6 : 0
            width: 0
            height: 28
            z: 5
            Behavior on x { enabled: bubble.glide; Spring { speed: "fast" } }
            Behavior on y { enabled: bubble.glide; Spring { speed: "fast" } }
            Behavior on wNow { enabled: bubble.glide; Spring { speed: "fast" } }

            function follow() {
                const c = grid.hoverCell;
                if (!c || grid.ghost || c.state === "future")
                    return;
                hideReset.stop();
                // coming up from hidden: land on the cell, then allow gliding
                if (pill.opacity < 0.05) {
                    glide = false;
                    lastCell = c;
                    Qt.callLater(() => { bubble.glide = true; });
                } else {
                    lastCell = c;
                }
            }
            Connections {
                target: grid
                function onHoverCellChanged() { bubble.follow(); }
            }
            onShownChanged: {
                if (shown)
                    follow();
                else
                    hideReset.restart();
            }
            // once it has faded out, the next cell is a fresh start
            Timer {
                id: hideReset
                interval: 260
                onTriggered: bubble.glide = false
            }

            Rectangle {
                id: pill
                x: -width / 2
                width: Math.max(0, bubble.wNow)
                height: 28
                radius: 14
                clip: true
                color: Colors.inverse_surface
                opacity: bubble.shown ? 1 : 0
                scale: bubble.shown ? 1 : 0.6
                transformOrigin: Item.Bottom
                Behavior on opacity { Fade {} }
                Behavior on scale { Spring { speed: "fast" } }
                StyledText {
                    id: bubbleText
                    anchors.centerIn: parent
                    role: "labelMedium"
                    emphasized: true
                    color: Colors.inverse_on_surface
                    text: bubble.lastCell ? Qt.formatDate(bubble.lastCell.date, "ddd, d MMM") + " · " + grid.stateText(bubble.lastCell) : ""
                }
            }
        }
    }

    // ---- legend ----
    Row {
        x: grid.labelW + grid.gridW - width
        y: grid.monthH + grid.gridH + 8
        height: 24
        spacing: 6
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelSmall"
            color: Colors.on_surface_variant
            text: "Less"
        }
        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            width: 12
            height: 12
            radius: 3
            color: Colors.surface_container_highest
        }
        Repeater {
            model: [0.35, 0.55, 0.78, 1]
            delegate: Rectangle {
                required property real modelData
                anchors.verticalCenter: parent.verticalCenter
                width: 12
                height: 12
                radius: 6
                color: Qt.alpha(grid.accent, modelData)
            }
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelSmall"
            color: Colors.on_surface_variant
            text: "More"
        }
    }
}
