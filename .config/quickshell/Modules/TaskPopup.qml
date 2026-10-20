pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Task panel opened from the bar chip. Left: your daily tasks (tick today with the check, hold the
// avatar to reorder) and a form to create or edit one. Right: the selected task's streak stats and
// a GitHub-style heatmap; click a day to tick it, right-click for a note, a count or a rest day.
BarPopup {
    id: win

    // the snackbar that offers Undo (shell.qml)
    property var copyToast: null

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 824
    spacing: 0

    // ---- state ----
    property string selectedId: ""
    readonly property var task: Tasks.byId(selectedId)
    readonly property bool doneToday: !!task && Tasks.isDone(task, Tasks.todayKey)
    property bool viewArchived: false
    readonly property var shownList: viewArchived ? Tasks.archivedList : Tasks.active
    property string page: "list"          // list | form
    property string editingId: ""
    // the form is the only page while there are no tasks
    readonly property bool showForm: page === "form" || (Tasks.count === 0 && !viewArchived)
    property real pageP: showForm ? 1 : 0
    // snaps while the panel is opening, so it never starts on the page it was left on
    Behavior on pageP { enabled: win.stage > 0; Spring { speed: "default" } }
    // heatmap window: how many 4-week steps back from the current week
    property int back: 0
    // the day picked on the heatmap: the list under it shows only that day
    property string dayPick: ""
    property bool confirmDelete: false
    // the row being dragged to a new place, by task id (rows are index-based)
    property string dragId: ""

    // form fields
    property var formDays: [true, true, true, true, true, true, true]
    property bool formRemind: false
    property var formReminds: []
    property int formSel: 0
    property int formTarget: 1
    property bool formNudge: true
    property bool formPomodoro: false
    readonly property bool formValid: nameField.text.trim().length > 0 && formDays.some(d => d)
    readonly property string selTime: formSel >= 0 && formSel < formReminds.length ? formReminds[formSel] : "08:00"
    readonly property int selHour: Number(selTime.split(":")[0])
    readonly property int selMinute: Number(selTime.split(":")[1])

    // day popover (right-click a heatmap day)
    // tips card, opened from the help button by the heatmap
    property bool helpOpen: false
    property real helpX: 0
    property real helpY: 0
    property bool dayOpen: false
    property string dayKey: ""
    property real dayX: 0
    property real dayY: 0
    property real daySize: 16
    readonly property bool dayCount: !!task && Tasks.targetOf(task) > 1

    // entrance
    property int stage: 0
    // right-hand content swaps with a springy slide when another task is picked
    property real swapP: 1
    property bool swapSpring: true
    Behavior on swapP { enabled: win.swapSpring; Spring { speed: "default" } }

    // ---- selection ----
    function ensureSelection() {
        if (!shownList.some(t => t.id === selectedId))
            selectedId = shownList.length > 0 ? shownList[0].id : "";
    }
    function selectBy(delta) {
        const i = shownList.findIndex(t => t.id === selectedId);
        const j = Math.max(0, Math.min(shownList.length - 1, (i < 0 ? 0 : i + delta)));
        if (shownList[j])
            selectedId = shownList[j].id;
    }
    onSelectedIdChanged: {
        confirmDelete = false;
        dayPick = "";
        back = 0;
        helpOpen = false;
        closeDay();
        swapSpring = false;
        swapP = 0;
        swapSpring = true;
        swapP = 1;
    }
    onViewArchivedChanged: ensureSelection()
    Connections {
        target: Tasks
        function onListChanged() { win.ensureSelection(); }
        function onUndoable(message) {
            if (win.copyToast)
                win.copyToast.showToast(message, "Undo", () => Tasks.undo());
        }
    }
    Component.onCompleted: ensureSelection()

    onIsOpenChanged: {
        if (isOpen) {
            viewArchived = false;
            ensureSelection();
            page = "list";
            stageTimer.restart();
            if (Tasks.count === 0)
                openNew();
        } else {
            stageTimer.stop();
            stage = 0;
            confirmDelete = false;
            helpOpen = false;
            dayPick = "";
            closeDay();
        }
    }
    Timer {
        id: stageTimer
        interval: 70
        repeat: true
        onTriggered: {
            if (win.stage < 6)
                win.stage++;
            else
                stop();
        }
    }
    Timer {
        id: confirmTimer
        interval: 3000
        running: win.confirmDelete
        onTriggered: win.confirmDelete = false
    }

    // ---- form ----
    function pad(n) { return String(n).padStart(2, "0"); }
    function resetForm() {
        editingId = "";
        nameField.text = "";
        formDays = [true, true, true, true, true, true, true];
        formRemind = false;
        formReminds = [];
        formSel = 0;
        formTarget = 1;
        formNudge = true;
        formPomodoro = false;
    }
    function openNew() {
        resetForm();
        page = "form";
        Qt.callLater(() => nameField.forceActiveFocus());
    }
    function openEdit(t) {
        if (!t)
            return;
        resetForm();
        editingId = t.id;
        nameField.text = t.name;
        formDays = [0, 1, 2, 3, 4, 5, 6].map(d => t.days.indexOf(d) >= 0);
        formReminds = Tasks.remindsOf(t).slice();
        formRemind = formReminds.length > 0;
        formTarget = Tasks.targetOf(t);
        formNudge = !!t.nudge;
        formPomodoro = !!t.pomodoro;
        page = "form";
        Qt.callLater(() => nameField.forceActiveFocus());
    }
    function saveForm() {
        if (!formValid)
            return;
        const days = [0, 1, 2, 3, 4, 5, 6].filter(d => formDays[d]);
        const reminds = formRemind ? formReminds.slice().sort() : [];
        if (editingId) {
            Tasks.updateTask(editingId, { name: nameField.text.trim(), days: days, reminds: reminds, nudge: formNudge, target: formTarget, pomodoro: formPomodoro });
        } else {
            viewArchived = false;
            selectedId = Tasks.addTask(nameField.text, days, reminds, formNudge, formTarget, formPomodoro);
        }
        page = "list";
    }
    function setDays(arr) { formDays = [0, 1, 2, 3, 4, 5, 6].map(d => arr.indexOf(d) >= 0); }
    function sameDays(arr) { return [0, 1, 2, 3, 4, 5, 6].every(d => formDays[d] === (arr.indexOf(d) >= 0)); }
    function setSelTime(h, m) {
        const arr = formReminds.slice();
        arr[formSel] = pad((h + 24) % 24) + ":" + pad((m + 60) % 60);
        formReminds = arr;
    }
    function addTime() {
        const last = formReminds.length > 0 ? formReminds[formReminds.length - 1] : "07:00";
        const h = (Number(last.split(":")[0]) + 4) % 24;
        formReminds = formReminds.concat([pad(h) + ":" + last.split(":")[1]]);
        formSel = formReminds.length - 1;
    }
    function removeTime(i) {
        formReminds = formReminds.filter((_, k) => k !== i);
        formSel = Math.max(0, Math.min(formSel, formReminds.length - 1));
        if (formReminds.length === 0)
            formRemind = false;
    }
    function toggleRemind() {
        formRemind = !formRemind;
        if (formRemind && formReminds.length === 0) {
            formReminds = ["08:00"];
            formSel = 0;
        }
    }

    // ---- day popover ----
    function toggleHelp() {
        closeDay();
        if (helpOpen) {
            helpOpen = false;
            return;
        }
        const p = helpBtn.mapToItem(card, 0, 0);
        helpX = p.x + helpBtn.width;
        helpY = p.y + helpBtn.height;
        helpOpen = true;
    }
    function openDay(cell, x, y, size) {
        if (!task)
            return;
        helpOpen = false;
        const p = heat.mapToItem(card, x, y);
        dayKey = cell.key;
        dayX = p.x;
        dayY = p.y;
        daySize = size;
        dayNote.text = Tasks.noteOf(task, cell.key);
        dayOpen = true;
        dayFocus.restart();
    }
    // the note field can only take focus once the popover has started to show
    Timer {
        id: dayFocus
        interval: 70
        onTriggered: dayNote.forceActiveFocus()
    }
    function saveDay() {
        if (task && dayKey && dayNote.text.trim() !== Tasks.noteOf(task, dayKey))
            Tasks.setNote(task.id, dayKey, dayNote.text);
    }
    function closeDay() {
        if (dayOpen)
            saveDay();
        dayOpen = false;
    }

    // ---- milestone celebration (7 / 30 / 100 day streaks) ----
    property real partyP: 1
    NumberAnimation {
        id: partyAnim
        target: win
        property: "partyP"
        from: 0
        to: 1
        duration: 900
        easing.type: Easing.OutCubic
    }
    function markToday() {
        if (!task)
            return;
        const id = task.id, wasDone = doneToday;
        Tasks.toggleDone(id, Tasks.todayKey);
        const t = Tasks.byId(id);
        if (!wasDone && Tasks.isDone(t, Tasks.todayKey) && [7, 30, 100].indexOf(Tasks.streak(t)) >= 0)
            partyAnim.restart();
    }
    // open on the next task still to do today (middle-click on the bar chip)
    function openPending() {
        const t = Tasks.dueToday.find(x => !Tasks.isDone(x, Tasks.todayKey)) || Tasks.active[0];
        if (t)
            selectedId = t.id;
        show();
    }
    function armDelete() {
        if (!task)
            return;
        if (!confirmDelete) {
            confirmDelete = true;
            return;
        }
        confirmDelete = false;
        Tasks.removeTask(task.id);
    }

    // ---- keyboard (list page, nothing being typed) ----
    readonly property bool keysOn: isOpen && !showForm && !dayOpen
    onKeysOnChanged: {
        if (keysOn)
            panel.forceActiveFocus();
    }
    Shortcut { sequence: "Up"; enabled: win.keysOn; onActivated: win.selectBy(-1) }
    Shortcut { sequence: "Down"; enabled: win.keysOn; onActivated: win.selectBy(1) }
    Shortcut { sequence: "Shift+Up"; enabled: win.keysOn && !win.viewArchived; onActivated: Tasks.move(win.selectedId, -1) }
    Shortcut { sequence: "Shift+Down"; enabled: win.keysOn && !win.viewArchived; onActivated: Tasks.move(win.selectedId, 1) }
    Shortcut { sequence: "Space"; enabled: win.keysOn && !win.viewArchived; onActivated: win.markToday() }
    Shortcut { sequence: "N"; enabled: win.keysOn; onActivated: win.openNew() }
    Shortcut { sequence: "E"; enabled: win.keysOn; onActivated: win.openEdit(win.task) }
    Shortcut { sequence: "A"; enabled: win.keysOn && !!win.task; onActivated: Tasks.archive(win.task.id, !win.task.archived) }
    Shortcut { sequence: "Delete"; enabled: win.keysOn; onActivated: win.armDelete() }
    Shortcut { sequence: "Left"; enabled: win.keysOn; onActivated: win.back += 1 }
    Shortcut { sequence: "Right"; enabled: win.keysOn && win.back > 0; onActivated: win.back -= 1 }
    // Escape steps back one level before the panel closes
    Shortcut {
        sequence: "Escape"
        enabled: win.isOpen && (win.dayOpen || win.helpOpen || (win.page === "form" && Tasks.count > 0))
        onActivated: {
            if (win.helpOpen)
                win.helpOpen = false;
            else if (win.dayOpen)
                win.closeDay();
            else
                win.page = "list";
        }
    }

    // ---- IPC (also how the panel is driven from scripts) ----
    IpcHandler {
        target: "tasks"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
        function add(name: string, time: string): string {
            return Tasks.addTask(name, [0, 1, 2, 3, 4, 5, 6], time ? [time] : [], false, 1);
        }
        function done(name: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.setDone(t.id, Tasks.todayKey, true);
        }
        function mark(name: string, date: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.tick(t.id, date, false);
        }
        function count(name: string, target: int): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.updateTask(t.id, { target: Math.max(1, target) });
        }
        function skip(name: string, date: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.setSkip(t.id, date, !Tasks.isSkipped(t, date));
        }
        function note(name: string, date: string, text: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.setNote(t.id, date, text);
        }
        function archive(name: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.archive(t.id, !t.archived);
        }
        function move(name: string, delta: int): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.move(t.id, delta);
        }
        function link(name: string): void {
            const t = Tasks.byName(name);
            Pomodoro.setTask(t && t.pomodoro ? t.id : "");
        }
        // show or hide the tips card
        function help(): void {
            win.show();
            win.toggleHelp();
        }
        function undo(): void { Tasks.undo(); }
        function recap(): void { Tasks.sendRecap(); }
        function remove(name: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.removeTask(t.id);
        }
        function fire(name: string): void {
            const t = Tasks.byName(name);
            if (t)
                Tasks.fire(t.id, "remind");
        }
        // open the panel on the new-task form / on a task's edit form
        function compose(): void {
            win.show();
            win.openNew();
        }
        function edit(name: string): void {
            const t = Tasks.byName(name);
            if (!t)
                return;
            win.selectedId = t.id;
            win.show();
            win.openEdit(t);
        }
        // open the panel with a task selected
        function select(name: string): void {
            const t = Tasks.byName(name);
            if (!t)
                return;
            win.viewArchived = !!t.archived;
            win.selectedId = t.id;
            win.show();
        }
    }

    RowLayout {
        Layout.fillWidth: true
        Layout.preferredHeight: 640
        spacing: 16

        // ======================= left: list / form =======================
        Item {
            id: left
            Layout.preferredWidth: 320
            Layout.fillHeight: true

            MouseArea {
                anchors.fill: parent
                enabled: win.dayOpen || win.helpOpen
                visible: enabled
                z: 9
                onClicked: {
                    win.helpOpen = false;
                    win.closeDay();
                }
            }

            // ---- list page ----
            ColumnLayout {
                id: listPage
                anchors.fill: parent
                spacing: 12
                opacity: Math.max(0, Math.min(1, 1 - win.pageP * 1.6))
                visible: opacity > 0.02
                transform: Translate { x: -win.pageP * 50 }

                RowLayout {
                    id: listHeader
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    property real appear: win.stage >= 1 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    transform: Translate { y: (1 - listHeader.appear) * 12 }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            role: "headlineSmall"
                            emphasized: true
                            text: win.viewArchived ? "Archived" : "Tasks"
                        }
                        StyledText {
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            text: win.viewArchived
                                ? (Tasks.archivedList.length === 0 ? "Nothing archived" : Tasks.archivedList.length + " hidden")
                                : Tasks.dueCount === 0
                                    ? (Tasks.count === 0 ? "Build a streak" : "Nothing due today")
                                    : (Tasks.dueCount - Tasks.pendingCount) + " of " + Tasks.dueCount + " done today"
                        }
                    }
                    Button {
                        icon: "add"
                        text: "New"
                        style: "tonal"
                        onClicked: win.openNew()
                    }
                }

                LinearProgress {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    Layout.rightMargin: 4
                    thickness: 8
                    value: Tasks.dueCount > 0 ? (Tasks.dueCount - Tasks.pendingCount) / Tasks.dueCount : 0
                    activeColor: Tasks.pendingCount === 0 && Tasks.dueCount > 0 ? Colors.tertiary : Colors.primary
                    Behavior on activeColor { ColorFade {} }
                    opacity: listHeader.opacity
                }

                ListView {
                    id: list
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    clip: true
                    spacing: 2
                    boundsBehavior: Flickable.StopAtBounds
                    // a row count, not the tasks: rows stay put (and keep their animations) while
                    // the data underneath them changes
                    model: win.shownList.length
                    readonly property real rowH: 68
                    readonly property int selIndex: win.shownList.findIndex(t => t.id === win.selectedId)

                    // selected row: its two edges ride separate springs, so it stretches toward the
                    // row it moves to (parented to the content item so it scrolls with the rows)
                    Rectangle {
                        id: blob
                        parent: list.contentItem
                        readonly property real topT: Math.max(0, list.selIndex) * (list.rowH + 2)
                        property real topE: topT
                        property real bottomE: topT + list.rowH
                        property bool movingDown: true
                        property real lastTop: topT
                        onTopTChanged: {
                            movingDown = topT > lastTop;
                            lastTop = topT;
                            topE = topT;
                            bottomE = topT + list.rowH;
                        }
                        Behavior on topE { Spring { speed: blob.movingDown ? "default" : "fast" } }
                        Behavior on bottomE { Spring { speed: blob.movingDown ? "fast" : "default" } }
                        z: -1
                        y: topE
                        width: list.width
                        height: Math.max(8, bottomE - topE)
                        radius: Motion.shapeLarge
                        color: Colors.secondary_container
                        visible: list.selIndex >= 0
                        opacity: Math.max(0, Math.min(1, win.stage / 3))
                    }

                    // nothing archived
                    StyledText {
                        parent: list
                        anchors.centerIn: parent
                        visible: win.viewArchived && Tasks.archivedList.length === 0
                        role: "bodyMedium"
                        color: Colors.on_surface_variant
                        text: "Archived tasks keep their history\nand come back with one click."
                        horizontalAlignment: Text.AlignHCenter
                    }

                    delegate: Clickable {
                        id: row
                        required property int index
                        readonly property var t: win.shownList[index]
                        readonly property bool selected: !!t && t.id === win.selectedId
                        readonly property bool isDone: !!t && Tasks.isDone(t, Tasks.todayKey)
                        readonly property bool dragging: !!t && t.id === win.dragId
                        readonly property int streak: t ? Tasks.streak(t) : 0

                        // rises in when the panel opens; rows made later (a new task) rise in on their own
                        property bool born: false
                        readonly property bool shownNow: born || win.stage >= Math.min(index, 4) + 2
                        property real appear: shownNow ? 1 : 0
                        Behavior on appear { Spring { speed: "default" } }
                        Component.onCompleted: if (win.stage >= 6) bornTimer.start()
                        Timer {
                            id: bornTimer
                            interval: 60
                            onTriggered: row.born = true
                        }
                        Connections {
                            target: win
                            function onStageChanged() { if (win.stage === 0) row.born = false; }
                        }
                        opacity: Math.max(0, Math.min(1, appear * 1.6))
                        scale: (0.94 + 0.06 * appear) * (dragging ? 1.04 : 1)
                        Behavior on scale { Spring { speed: "fast" } }
                        z: dragging ? 3 : 0
                        transform: Translate { y: (1 - row.appear) * 16 }

                        width: list.width
                        height: list.rowH
                        restRadius: Motion.shapeLarge
                        pressedRadius: Motion.shapeSmall
                        contentColor: selected ? Colors.on_secondary_container : Colors.on_surface
                        onClicked: if (t) win.selectedId = t.id

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 12

                            // hold the avatar to pick the row up, then drag it up or down
                            Item {
                                Layout.preferredWidth: 44
                                Layout.preferredHeight: 44
                                TaskAvatar {
                                    anchors.fill: parent
                                    task: row.t
                                    done: row.isDone
                                    badgeScale: row.dragging ? 1.12 : 1
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    enabled: !win.viewArchived
                                    pressAndHoldInterval: 320
                                    cursorShape: row.dragging ? Qt.ClosedHandCursor : Qt.PointingHandCursor
                                    onClicked: if (row.t) win.selectedId = row.t.id
                                    onPressAndHold: {
                                        if (!row.t)
                                            return;
                                        win.dragId = row.t.id;
                                        win.selectedId = row.t.id;
                                    }
                                    onPositionChanged: mouse => {
                                        if (!row.dragging)
                                            return;
                                        const y = mapToItem(list.contentItem, mouse.x, mouse.y).y;
                                        const to = Math.max(0, Math.min(win.shownList.length - 1, Math.floor(y / (list.rowH + 2))));
                                        const from = win.shownList.findIndex(t => t.id === win.dragId);
                                        if (from >= 0 && to !== from)
                                            Tasks.move(win.dragId, to > from ? 1 : -1);
                                    }
                                    onReleased: win.dragId = ""
                                    onCanceled: win.dragId = ""
                                }
                            }
                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                StyledText {
                                    Layout.fillWidth: true
                                    role: "bodyLarge"
                                    emphasized: true
                                    color: row.contentColor
                                    elide: Text.ElideRight
                                    text: row.t ? row.t.name : ""
                                }
                                Row {
                                    spacing: 4
                                    Icon {
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 14
                                        name: "local_fire_department"
                                        color: row.streak > 0 ? Colors.tertiary : Colors.on_surface_variant
                                    }
                                    StyledText {
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "bodyMedium"
                                        color: row.selected ? Colors.on_secondary_container : Colors.on_surface_variant
                                        text: row.t && Tasks.targetOf(row.t) > 1 && !row.isDone
                                            ? Tasks.countOf(row.t, Tasks.todayKey) + "/" + Tasks.targetOf(row.t) + " today"
                                            : row.streak > 0 ? row.streak + (row.streak === 1 ? " day" : " days") : "No streak"
                                    }
                                    Icon {
                                        visible: !!row.t && Tasks.remindsOf(row.t).length > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        size: 14
                                        name: "schedule"
                                        color: row.selected ? Colors.on_secondary_container : Colors.on_surface_variant
                                    }
                                    StyledText {
                                        visible: !!row.t && Tasks.remindsOf(row.t).length > 0
                                        anchors.verticalCenter: parent.verticalCenter
                                        role: "bodyMedium"
                                        color: row.selected ? Colors.on_secondary_container : Colors.on_surface_variant
                                        text: row.t && Tasks.remindsOf(row.t).length > 0 ? Tasks.remindsOf(row.t)[0] + (Tasks.remindsOf(row.t).length > 1 ? " +" + (Tasks.remindsOf(row.t).length - 1) : "") : ""
                                    }
                                }
                            }
                            // today's check: round while open, squarer once done (checkable shape morph)
                            IconButton {
                                visible: !win.viewArchived
                                icon: "check"
                                style: "filled"
                                checkable: true
                                checked: row.isDone
                                color: row.isDone ? Tasks.accentFor(row.t) : Colors.surface_container_highest
                                contentColor: row.isDone ? Tasks.onAccentFor(row.t) : Colors.on_surface_variant
                                onClicked: if (row.t) Tasks.toggleDone(row.t.id, Tasks.todayKey)
                            }
                            IconButton {
                                visible: win.viewArchived
                                icon: "unarchive"
                                style: "tonal"
                                onClicked: if (row.t) Tasks.archive(row.t.id, false)
                            }
                        }
                    }
                }

                // footer: archive switch, weekly recap, shortcut hint
                RowLayout {
                    id: listFooter
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    spacing: 8
                    Chip {
                        visible: Tasks.archivedList.length > 0 || win.viewArchived
                        kind: "filter"
                        icon: "inventory_2"
                        text: win.viewArchived ? "Back to tasks" : "Archived (" + Tasks.archivedList.length + ")"
                        selected: win.viewArchived
                        onClicked: win.viewArchived = !win.viewArchived
                    }
                    Item { Layout.fillWidth: true }
                    Icon {
                        size: 18
                        name: "notifications_active"
                        color: Tasks.weeklyRecap ? Colors.primary : Colors.on_surface_variant
                    }
                    StyledText {
                        role: "labelMedium"
                        color: Colors.on_surface_variant
                        text: "Sunday recap"
                    }
                    Switch {
                        showIcons: false
                        checked: Tasks.weeklyRecap
                        onToggled: Tasks.setWeeklyRecap(!Tasks.weeklyRecap)
                    }
                }
            }

            // ---- form page ----
            ColumnLayout {
                id: formPage
                anchors.fill: parent
                spacing: 10
                opacity: Math.max(0, Math.min(1, win.pageP * 1.6 - 0.6))
                visible: win.showForm || opacity > 0.02
                transform: Translate { x: (1 - win.pageP) * 50 }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    IconButton {
                        visible: Tasks.count > 0
                        icon: "arrow_back"
                        style: "tonal"
                        onClicked: win.page = "list"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: Tasks.count > 0 ? 0 : 4
                        role: "headlineSmall"
                        emphasized: true
                        text: win.editingId ? "Edit task" : (Tasks.count === 0 ? "Your first task" : "New task")
                    }
                }

                TextField {
                    id: nameField
                    Layout.fillWidth: true
                    label: "Task name"
                    leadingIcon: "checklist"
                    onAccepted: win.saveForm()
                }

                // repeat
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    StyledText {
                        Layout.fillWidth: true
                        role: "labelLarge"
                        color: Colors.on_surface_variant
                        text: "Repeat"
                    }
                    Chip {
                        kind: "filter"
                        text: "Every day"
                        selected: win.sameDays([0, 1, 2, 3, 4, 5, 6])
                        onClicked: win.setDays([0, 1, 2, 3, 4, 5, 6])
                    }
                    Chip {
                        kind: "filter"
                        text: "Weekdays"
                        selected: win.sameDays([1, 2, 3, 4, 5])
                        onClicked: win.setDays([1, 2, 3, 4, 5])
                    }
                }
                Row {
                    Layout.alignment: Qt.AlignHCenter
                    spacing: 6
                    Repeater {
                        model: ["S", "M", "T", "W", "T", "F", "S"]
                        delegate: Clickable {
                            id: dayBtn
                            required property string modelData
                            required property int index
                            readonly property bool on: win.formDays[index]
                            width: 38
                            height: 38
                            checked: on
                            restRadius: 19
                            checkedRadius: 12
                            pressedRadius: 8
                            color: on ? Colors.primary : Colors.surface_container_highest
                            contentColor: on ? Colors.on_primary : Colors.on_surface_variant
                            scale: pressed ? 0.9 : hovered ? 1.06 : 1
                            Behavior on scale { Spring { speed: "fast" } }
                            onClicked: win.formDays = win.formDays.map((d, i) => i === index ? !d : d)
                            StyledText {
                                anchors.centerIn: parent
                                role: "labelLarge"
                                emphasized: true
                                color: dayBtn.contentColor
                                text: dayBtn.modelData
                            }
                        }
                    }
                }

                // how many times a day it counts as done
                RowLayout {
                    Layout.fillWidth: true
                    Layout.leftMargin: 4
                    spacing: 8
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            role: "labelLarge"
                            color: Colors.on_surface_variant
                            text: "Daily target"
                        }
                        StyledText {
                            role: "labelSmall"
                            color: Colors.on_surface_variant
                            text: win.formTarget === 1 ? "Just tick it" : "Tap a day to count up to " + win.formTarget
                        }
                    }
                    IconButton { icon: "remove"; style: "tonal"; size: "xs"; enabled: win.formTarget > 1; onClicked: win.formTarget -= 1 }
                    RollingDigits {
                        Layout.preferredWidth: implicitWidth + 6
                        pixelSize: 24
                        text: String(win.formTarget)
                    }
                    IconButton { icon: "add"; style: "tonal"; size: "xs"; enabled: win.formTarget < 99; onClicked: win.formTarget += 1 }
                }

                // reminders: any number of times a day
                Rectangle {
                    Layout.fillWidth: true
                    implicitHeight: remindCol.implicitHeight + 24
                    Behavior on implicitHeight { Spring { speed: "default" } }
                    radius: Motion.shapeLarge
                    color: Colors.surface_container_high
                    clip: true

                    ColumnLayout {
                        id: remindCol
                        x: 12
                        y: 12
                        width: parent.width - 24
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Icon {
                                name: win.formRemind ? "notifications_active" : "alarm"
                                color: win.formRemind ? Colors.primary : Colors.on_surface_variant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyLarge"
                                emphasized: true
                                text: "Remind me"
                            }
                            Switch {
                                checked: win.formRemind
                                onToggled: win.toggleRemind()
                            }
                        }

                        // time chips: pick one to edit it with the stepper below, or add another
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            visible: opacity > 0.02
                            opacity: win.formRemind ? 1 : 0
                            Layout.preferredHeight: win.formRemind ? implicitHeight : 0
                            Behavior on opacity { Fade {} }
                            Behavior on Layout.preferredHeight { Spring { speed: "default" } }
                            Repeater {
                                model: win.formReminds
                                delegate: Chip {
                                    required property string modelData
                                    required property int index
                                    kind: "input"
                                    text: modelData
                                    selected: index === win.formSel
                                    trailingIcon: "close"
                                    onClicked: win.formSel = index
                                    onTrailingClicked: win.removeTime(index)
                                }
                            }
                            Chip {
                                kind: "assist"
                                icon: "add"
                                text: "Add time"
                                visible: win.formReminds.length < 4
                                onClicked: win.addTime()
                            }
                        }

                        Row {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 6
                            visible: opacity > 0.02
                            opacity: win.formRemind && win.formReminds.length > 0 ? 1 : 0
                            Layout.preferredHeight: win.formRemind && win.formReminds.length > 0 ? 44 : 0
                            Behavior on opacity { Fade {} }
                            Behavior on Layout.preferredHeight { Spring { speed: "default" } }

                            IconButton { icon: "remove"; style: "tonal"; size: "xs"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.setSelTime(win.selHour - 1, win.selMinute) }
                            RollingDigits {
                                anchors.verticalCenter: parent.verticalCenter
                                pixelSize: 28
                                text: win.pad(win.selHour)
                            }
                            IconButton { icon: "add"; style: "tonal"; size: "xs"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.setSelTime(win.selHour + 1, win.selMinute) }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "headlineSmall"
                                emphasized: true
                                text: ":"
                            }
                            IconButton { icon: "remove"; style: "tonal"; size: "xs"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.setSelTime(win.selHour, win.selMinute - 5) }
                            RollingDigits {
                                anchors.verticalCenter: parent.verticalCenter
                                pixelSize: 28
                                text: win.pad(win.selMinute)
                            }
                            IconButton { icon: "add"; style: "tonal"; size: "xs"; anchors.verticalCenter: parent.verticalCenter; onClicked: win.setSelTime(win.selHour, win.selMinute + 5) }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Icon {
                                name: "local_fire_department"
                                color: win.formNudge ? Colors.tertiary : Colors.on_surface_variant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyMedium"
                                wrapMode: Text.WordWrap
                                text: "Nudge at 9 PM if my streak is at risk"
                            }
                            Switch {
                                checked: win.formNudge
                                onToggled: win.formNudge = !win.formNudge
                            }
                        }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 12
                            Icon {
                                name: "timer"
                                color: win.formPomodoro ? Colors.tertiary : Colors.on_surface_variant
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyMedium"
                                wrapMode: Text.WordWrap
                                text: "Use with the focus timer"
                            }
                            Switch {
                                checked: win.formPomodoro
                                onToggled: win.formPomodoro = !win.formPomodoro
                            }
                        }
                    }
                }

                Item { Layout.fillHeight: true }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Button {
                        visible: Tasks.count > 0
                        style: "text"
                        text: "Cancel"
                        onClicked: win.page = "list"
                    }
                    Button {
                        icon: "check"
                        text: win.editingId ? "Save" : "Add task"
                        enabled: win.formValid
                        onClicked: win.saveForm()
                    }
                }
            }
        }

        // ======================= right: stats + heatmap =======================
        Rectangle {
            id: card
            Layout.fillWidth: true
            Layout.fillHeight: true
            radius: Motion.shapeLarge
            color: Colors.surface_container_high
            clip: true

            // nothing yet: a dim sample heatmap and a hint
            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 16
                spacing: 16
                visible: !win.task
                opacity: win.task ? 0 : 1
                Behavior on opacity { Fade {} }

                Item { Layout.fillHeight: true }
                ShapeBadge {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.preferredWidth: 88
                    Layout.preferredHeight: 88
                    shapeRest: 1
                    spinning: !win.task && win.isOpen
                    color: Colors.tertiary_container
                    Icon { anchors.centerIn: parent; size: 36; name: "local_fire_department"; color: Colors.on_tertiary_container }
                }
                StyledText {
                    Layout.alignment: Qt.AlignHCenter
                    role: "titleMedium"
                    emphasized: true
                    text: "Your streaks will show up here"
                }
                HeatmapGrid {
                    Layout.alignment: Qt.AlignHCenter
                    weeks: 20
                    task: null
                }
                Item { Layout.fillHeight: true }
            }

            // the selected task
            ColumnLayout {
                id: detail
                anchors.fill: parent
                anchors.margins: 16
                spacing: 12
                visible: !!win.task
                opacity: !win.task ? 0 : Math.max(0, Math.min(1, win.swapP * 1.6))
                transform: Translate { y: (1 - win.swapP) * 22 }

                // header
                RowLayout {
                    id: detailHeader
                    Layout.fillWidth: true
                    spacing: 12
                    property real appear: win.stage >= 1 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))

                    Item {
                        Layout.preferredWidth: 56
                        Layout.preferredHeight: 56
                        TaskAvatar {
                            id: bigAvatar
                            anchors.fill: parent
                            task: win.task
                            done: win.doneToday
                            // swells while a milestone celebration plays
                            badgeScale: 1 + 0.25 * Math.sin(win.partyP * Math.PI)
                        }
                        // milestone burst
                        Repeater {
                            model: 10
                            delegate: MorphShape {
                                required property int index
                                readonly property real ang: index / 10 * Math.PI * 2
                                readonly property real dist: 30 + 46 * win.partyP
                                width: 10
                                height: 10
                                shape: index % 3 === 0 ? 4 : index % 3 === 1 ? 1 : 5
                                fromShape: shape
                                color: index % 2 === 0 ? Colors.tertiary : Colors.primary
                                x: 28 + Math.cos(ang) * dist - 5
                                y: 28 + Math.sin(ang) * dist - 5
                                scale: win.partyP >= 1 ? 0 : 1 - 0.6 * win.partyP
                                opacity: win.partyP >= 1 ? 0 : 1 - win.partyP * win.partyP
                                z: 5
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            role: "titleLarge"
                            emphasized: true
                            elide: Text.ElideRight
                            text: win.task ? win.task.name : ""
                        }
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            elide: Text.ElideRight
                            text: {
                                if (!win.task)
                                    return "";
                                let s = Tasks.daysLabel(win.task);
                                if (Tasks.targetOf(win.task) > 1)
                                    s += " · " + Tasks.targetOf(win.task) + " a day";
                                const r = Tasks.remindsOf(win.task);
                                if (r.length > 0)
                                    s += " · " + r.join(", ");
                                const n = Tasks.sessionsOf(win.task, Tasks.todayKey);
                                if (n > 0)
                                    s += " · " + n + (n === 1 ? " session" : " sessions") + " today";
                                return s;
                            }
                        }
                    }
                    IconButton {
                        icon: "edit"
                        style: "tonal"
                        onClicked: win.openEdit(win.task)
                    }
                    IconButton {
                        icon: win.task && win.task.archived ? "unarchive" : "inventory_2"
                        style: "tonal"
                        onClicked: if (win.task) Tasks.archive(win.task.id, !win.task.archived)
                    }
                    // delete asks twice: the button widens into a red "Delete" for three seconds
                    Button {
                        icon: "delete"
                        text: win.confirmDelete ? "Delete" : ""
                        style: "tonal"
                        color: win.confirmDelete ? Colors.error : Colors.secondary_container
                        contentColor: win.confirmDelete ? Colors.on_error : Colors.on_secondary_container
                        Behavior on implicitWidth { Spring {} }
                        onClicked: win.armDelete()
                    }
                }

                // stats
                RowLayout {
                    id: statsRow
                    Layout.fillWidth: true
                    spacing: 8
                    property real appear: win.stage >= 2 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    transform: Translate { y: (1 - statsRow.appear) * 14 }

                    Repeater {
                        model: win.task ? [
                            { icon: "local_fire_department", label: "Streak", value: Tasks.streak(win.task), suffix: " d", tone: 0 },
                            { icon: "star", label: "Best", value: Tasks.bestStreak(win.task), suffix: " d", tone: 1 },
                            { icon: "trending_up", label: "30 days", value: Tasks.rate30(win.task), suffix: "%", tone: 2 }
                        ] : []
                        delegate: Rectangle {
                            id: tile
                            required property var modelData
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            implicitHeight: 64
                            radius: Motion.shapeLarge
                            color: Colors.surface_container_highest

                            Row {
                                anchors.centerIn: parent
                                spacing: 10
                                ShapeBadge {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: 32
                                    height: 32
                                    shapeRest: tile.modelData.tone === 0 ? 4 : tile.modelData.tone === 1 ? 5 : 1
                                    spinning: tile.modelData.tone === 0 && tile.modelData.value > 0 && win.isOpen
                                    color: tile.modelData.tone === 0 ? Colors.tertiary_container : tile.modelData.tone === 1 ? Colors.primary_container : Colors.secondary_container
                                    Icon {
                                        anchors.centerIn: parent
                                        size: 18
                                        name: tile.modelData.icon
                                        color: tile.modelData.tone === 0 ? Colors.on_tertiary_container : tile.modelData.tone === 1 ? Colors.on_primary_container : Colors.on_secondary_container
                                    }
                                }
                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: 0
                                    Row {
                                        RollingDigits {
                                            pixelSize: 22
                                            text: String(tile.modelData.value)
                                        }
                                        StyledText {
                                            anchors.bottom: parent.bottom
                                            anchors.bottomMargin: 2
                                            role: "labelLarge"
                                            color: Colors.on_surface_variant
                                            text: tile.modelData.suffix
                                        }
                                    }
                                    StyledText {
                                        role: "labelMedium"
                                        color: Colors.on_surface_variant
                                        text: tile.modelData.label
                                    }
                                }
                            }
                        }
                    }
                }

                // heatmap window controls
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        Layout.leftMargin: 4
                        role: "titleMedium"
                        emphasized: true
                        text: heat.cells.length > 0
                            ? Qt.formatDate(heat.cells[0].date, "MMM yyyy") + "  –  " + Qt.formatDate(heat.cells[heat.cells.length - 1].date, "MMM yyyy")
                            : ""
                    }
                    // the day picked on the heatmap, as on the immersion panel
                    Chip {
                        id: dayChip
                        visible: win.dayPick !== ""
                        kind: "input"
                        icon: "check"
                        trailingIcon: "close"
                        text: win.dayPick !== "" ? Qt.formatDate(Tasks.dateOf(win.dayPick), "ddd d MMM") : ""
                        onTrailingClicked: win.dayPick = ""
                        onClicked: win.dayPick = ""
                        Appear { shown: dayChip.visible; lift: 0; from: 0.7 }
                    }
                    IconButton { icon: "chevron_left"; style: "tonal"; size: "xs"; onClicked: win.back += 1 }
                    IconButton { icon: "chevron_right"; style: "tonal"; size: "xs"; enabled: win.back > 0; onClicked: win.back -= 1 }
                    IconButton {
                        id: helpBtn
                        icon: "help"
                        size: "xs"
                        checkable: true
                        checked: win.helpOpen
                        onClicked: win.toggleHelp()
                    }
                }

                DayMarkPicker {
                    Layout.fillWidth: true
                    key: win.dayPick !== "" ? win.dayPick : Tasks.todayKey
                }

                HeatmapGrid {
                    id: heat
                    Layout.alignment: Qt.AlignHCenter
                    weeks: 20
                    task: win.task
                    endOffset: win.back * 4
                    // a click selects the day (the list under it ticks); right-click keeps its note / count / rest menu
                    selectMode: true
                    selectedKey: win.dayPick
                    onDaySelected: key => win.dayPick = win.dayPick === key ? "" : key
                    onDayMenu: (cell, x, y, size) => win.openDay(cell, x, y, size)
                    // the entrance wave plays as the panel finishes opening
                    Connections {
                        target: win
                        function onStageChanged() { if (win.stage === 3) heat.replay(); }
                    }
                    opacity: win.stage >= 3 ? 1 : 0
                }

                // the days, newest first, or the one picked above; each can be ticked here
                TaskDayList {
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumHeight: 0
                    task: win.task
                    heat: heat
                    selectedKey: win.dayPick
                    opacity: win.stage >= 3 ? 1 : 0
                }

                Button {
                    id: markBtn
                    visible: !!win.task && !win.task.archived
                    Layout.fillWidth: true
                    size: "m"
                    style: win.doneToday ? "tonal" : "filled"
                    icon: win.doneToday ? "check" : "add_task"
                    text: !win.task ? "" : win.doneToday ? (Tasks.targetOf(win.task) > 1 ? "Done · " + Tasks.countOf(win.task, Tasks.todayKey) + " of " + Tasks.targetOf(win.task) : "Done today")
                        : Tasks.targetOf(win.task) > 1 ? "Add one · " + Tasks.countOf(win.task, Tasks.todayKey) + " of " + Tasks.targetOf(win.task) : "Mark today done"
                    color: win.doneToday ? Colors.secondary_container : Tasks.accentFor(win.task)
                    contentColor: win.doneToday ? Colors.on_secondary_container : Tasks.onAccentFor(win.task)
                    property real appear: win.stage >= 4 ? 1 : 0
                    Behavior on appear { Spring { speed: "default" } }
                    opacity: Math.max(0, Math.min(1, appear * 1.6))
                    scale: 0.9 + 0.1 * appear
                    onClicked: win.markToday()
                }
            }

            // ---- day popover: note, count and rest day for one heatmap day ----
            MouseArea {
                anchors.fill: parent
                enabled: win.dayOpen || win.helpOpen || (win.page === "form" && Tasks.count > 0)
                visible: enabled
                z: 9
                onClicked: {
                    if (win.helpOpen)
                        win.helpOpen = false;
                    else if (win.dayOpen)
                        win.closeDay();
                    else
                        win.page = "list";
                }
            }

            // ---- tips: only shown when asked for, so the panel stays clean ----
            Rectangle {
                id: helpCard
                readonly property var sections: [
                    { title: "Heatmap", icon: "grid_view", cols: 1, rows: [
                        { keys: ["Click"], text: "Pick a day, tick it in the list" },
                        { keys: ["Right-click"], text: "Note, count or rest day" },
                        { keys: ["Busy / Rest"], text: "Half goal or pause, for every tracker" }
                    ] },
                    { title: "Keyboard", icon: "keyboard", cols: 2, rows: [
                        { keys: ["↑", "↓"], text: "Select" },
                        { keys: ["Space"], text: "Tick today" },
                        { keys: ["N"], text: "New" },
                        { keys: ["E"], text: "Edit" },
                        { keys: ["A"], text: "Archive" },
                        { keys: ["Del"], text: "Remove" },
                        { keys: ["←", "→"], text: "Page" },
                        { keys: ["Esc"], text: "Close" }
                    ] },
                    { title: "Reorder", icon: "swap_vert", cols: 1, rows: [
                        { keys: ["Hold"], text: "Drag an avatar" },
                        { keys: ["Shift", "↑", "↓"], text: "Move selected" }
                    ] }
                ]
                z: 10
                width: 320
                height: helpCol.implicitHeight + 32
                radius: Motion.shapeLarge
                color: Colors.inverse_surface
                x: Math.max(8, Math.min(card.width - width - 8, win.helpX - width))
                y: Math.max(8, Math.min(win.helpY + 8, card.height - height - 8))
                transformOrigin: Item.TopRight
                opacity: win.helpOpen ? 1 : 0
                scale: win.helpOpen ? 1 : 0.6
                visible: opacity > 0.02
                Behavior on opacity { Fade {} }
                Behavior on scale { Spring { speed: "fast" } }

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: helpCol
                    x: 16
                    y: 16
                    width: parent.width - 32
                    spacing: 14

                    Repeater {
                        model: helpCard.sections
                        delegate: ColumnLayout {
                            id: sec
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 8

                            RowLayout {
                                spacing: 8
                                Icon { size: 18; name: sec.modelData.icon; color: Colors.inverse_primary }
                                StyledText {
                                    role: "labelLarge"
                                    emphasized: true
                                    color: Colors.inverse_primary
                                    text: sec.modelData.title
                                }
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                columns: sec.modelData.cols
                                columnSpacing: 16
                                rowSpacing: 6

                                Repeater {
                                    model: sec.modelData.rows
                                    delegate: RowLayout {
                                        id: tip
                                        required property var modelData
                                        Layout.fillWidth: true
                                        Layout.preferredWidth: 1
                                        spacing: 8

                                        // fixed-width key column so the labels line up
                                        Item {
                                            Layout.preferredWidth: sec.modelData.cols === 2 ? 60 : 92
                                            Layout.preferredHeight: 22
                                            Row {
                                                spacing: 4
                                                Repeater {
                                                    model: tip.modelData.keys
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
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            role: "bodySmall"
                                            color: Colors.inverse_on_surface
                                            elide: Text.ElideRight
                                            text: tip.modelData.text
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Rectangle {
                id: dayPop
                readonly property real pw: 252
                readonly property real ph: dayCol.implicitHeight + 24
                z: 10
                width: pw
                height: ph
                radius: Motion.shapeLarge
                color: Colors.surface_container_highest
                x: Math.max(8, Math.min(card.width - pw - 8, win.dayX + win.daySize / 2 - pw / 2))
                y: win.dayY + win.daySize + 10 + ph > card.height - 8 ? win.dayY - ph - 10 : win.dayY + win.daySize + 10
                transformOrigin: Item.Center
                opacity: win.dayOpen ? 1 : 0
                scale: win.dayOpen ? 1 : 0.6
                visible: win.dayOpen || opacity > 0.02
                Behavior on opacity { Fade {} }
                Behavior on scale { Spring {} }

                MouseArea { anchors.fill: parent }

                ColumnLayout {
                    id: dayCol
                    x: 12
                    y: 12
                    width: parent.width - 24
                    spacing: 8

                    RowLayout {
                        Layout.fillWidth: true
                        StyledText {
                            Layout.fillWidth: true
                            role: "titleMedium"
                            emphasized: true
                            text: win.dayKey ? Qt.formatDate(Tasks.dateOf(win.dayKey), "ddd, d MMM") : ""
                        }
                        IconButton { icon: "close"; size: "xs"; onClicked: win.closeDay() }
                    }

                    TextField {
                        id: dayNote
                        Layout.fillWidth: true
                        label: "Note"
                        leadingIcon: "edit_note"
                        onAccepted: win.closeDay()
                    }

                    // count tasks: step the day's count
                    RowLayout {
                        Layout.fillWidth: true
                        visible: win.dayCount
                        spacing: 8
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodyMedium"
                            text: "Count"
                        }
                        IconButton {
                            icon: "remove"
                            style: "tonal"
                            size: "xs"
                            enabled: !!win.task && Tasks.countOf(win.task, win.dayKey) > 0
                            onClicked: Tasks.setCount(win.task.id, win.dayKey, Tasks.countOf(win.task, win.dayKey) - 1)
                        }
                        RollingDigits {
                            Layout.preferredWidth: implicitWidth + 4
                            pixelSize: 18
                            text: win.task ? String(Tasks.countOf(win.task, win.dayKey)) : "0"
                        }
                        StyledText {
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            text: win.task ? "of " + Tasks.targetOf(win.task) : ""
                        }
                        IconButton {
                            icon: "add"
                            style: "tonal"
                            size: "xs"
                            onClicked: Tasks.setCount(win.task.id, win.dayKey, Tasks.countOf(win.task, win.dayKey) + 1)
                        }
                    }

                    // a rest day keeps the streak alive (a couple per month)
                    RowLayout {
                        Layout.fillWidth: true
                        spacing: 10
                        Icon {
                            name: "ac_unit"
                            color: win.task && Tasks.isSkipped(win.task, win.dayKey) ? Colors.tertiary : Colors.on_surface_variant
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                role: "bodyMedium"
                                emphasized: true
                                text: "Rest day"
                            }
                            StyledText {
                                role: "labelSmall"
                                color: Colors.on_surface_variant
                                text: win.task ? Tasks.freezesLeft(win.task, win.dayKey) + " of " + Tasks.freezesPerMonth + " left this month" : ""
                            }
                        }
                        Switch {
                            showIcons: false
                            enabled: !!win.task && win.dayOpen && Tasks.canSkip(win.task, win.dayKey)
                            checked: !!win.task && Tasks.isSkipped(win.task, win.dayKey)
                            onToggled: Tasks.setSkip(win.task.id, win.dayKey, !Tasks.isSkipped(win.task, win.dayKey))
                        }
                    }

                    RowLayout {
                        Layout.fillWidth: true
                        Button {
                            style: "text"
                            text: "Clear day"
                            onClicked: {
                                Tasks.clearDay(win.task.id, win.dayKey);
                                dayNote.text = "";
                                win.dayOpen = false;
                            }
                        }
                        Item { Layout.fillWidth: true }
                        Button {
                            style: "tonal"
                            text: "Done"
                            onClicked: win.closeDay()
                        }
                    }
                }
            }
        }
    }
}
