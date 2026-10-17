pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components

// Clock + M3 docked date picker.
BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 360

    property var today: new Date()
    property var selectedDate: new Date()
    property var viewDate: new Date(today.getFullYear(), today.getMonth(), 1)
    readonly property var gridCells: buildGrid(viewDate)

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

    onIsOpenChanged: if (isOpen) today = new Date()

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

    // Clock
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        spacing: 16

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            Row {
                spacing: 2
                StyledText {
                    id: hhmm
                    role: "displaySmall"
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

        Button {
            text: "Today"
            icon: "today"
            style: "tonal"
            onClicked: win.reset()
        }
    }

    // Date picker
    Rectangle {
        Layout.fillWidth: true
        implicitHeight: pickerCol.implicitHeight + 16
        radius: Motion.shapeLarge
        color: Colors.surface_container_high

        ColumnLayout {
            id: pickerCol
            x: 8
            y: 8
            width: parent.width - 16
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 4
                spacing: 0

                StyledText {
                    Layout.fillWidth: true
                    Layout.leftMargin: 16
                    role: "titleSmall"
                    color: Colors.on_surface_variant
                    text: Qt.formatDate(win.viewDate, "MMMM yyyy")
                }
                IconButton { icon: "chevron_left"; onClicked: win.shiftMonth(-1) }
                IconButton { icon: "chevron_right"; onClicked: win.shiftMonth(1) }
            }

            GridLayout {
                Layout.alignment: Qt.AlignHCenter
                columns: 7
                columnSpacing: 4
                rowSpacing: 0

                Repeater {
                    model: ["S", "M", "T", "W", "T", "F", "S"]
                    delegate: StyledText {
                        required property string modelData
                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        horizontalAlignment: Text.AlignHCenter
                        role: "bodyLarge"
                        text: modelData
                    }
                }

                Repeater {
                    model: win.gridCells
                    delegate: Clickable {
                        id: cell
                        required property var modelData
                        readonly property bool isToday: win.isSameDay(modelData.date, win.today)
                        readonly property bool isSelected: win.isSameDay(modelData.date, win.selectedDate)

                        Layout.preferredWidth: 40
                        Layout.preferredHeight: 40
                        // today: tonal fill (instead of the spec's outline ring); selected: primary
                        color: isSelected ? Colors.primary : isToday ? Colors.secondary_container : "transparent"
                        contentColor: isSelected ? Colors.on_primary : isToday ? Colors.on_secondary_container : Colors.on_surface
                        opacity: modelData.inMonth ? 1 : Motion.disabledContent
                        onClicked: {
                            win.selectedDate = modelData.date;
                            if (!modelData.inMonth)
                                win.viewDate = new Date(modelData.date.getFullYear(), modelData.date.getMonth(), 1);
                        }

                        StyledText {
                            anchors.centerIn: parent
                            role: "bodyLarge"
                            color: cell.contentColor
                            text: cell.modelData.date.getDate()
                        }
                    }
                }
            }
        }
    }

    // Selected date
    RowLayout {
        Layout.fillWidth: true
        Layout.leftMargin: 8
        Layout.rightMargin: 4
        spacing: 16

        Icon { name: "event"; color: Colors.on_surface_variant }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText { role: "titleSmall"; text: Qt.formatDate(win.selectedDate, "dddd, MMMM d") }
            StyledText {
                role: "bodyMedium"
                color: Colors.on_surface_variant
                text: `Week ${win.weekNumber(win.selectedDate)} · Day ${win.dayOfYear(win.selectedDate)}`
            }
        }
        Rectangle {
            readonly property bool isToday: win.isSameDay(win.selectedDate, win.today)
            implicitHeight: 32
            implicitWidth: relLabel.implicitWidth + 24
            radius: Motion.shapeSmall
            color: isToday ? Colors.secondary_container : Colors.surface_container_highest
            StyledText {
                id: relLabel
                anchors.centerIn: parent
                role: "labelLarge"
                color: parent.isToday ? Colors.on_secondary_container : Colors.on_surface_variant
                text: win.relativeDay(win.selectedDate)
            }
        }
    }
}
