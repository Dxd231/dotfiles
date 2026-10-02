pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// Month calendar. Owns all of its own state, so shell.qml doesn't need to know about it.
Rectangle {
    id: cal

    property var theme
    property var settings

    property var today: new Date()
    property var viewDate: new Date(new Date().getFullYear(), new Date().getMonth(), 1)
    property var highlightedDays: []
    readonly property var gridCells: cal.buildGrid(cal.viewDate)

    implicitHeight: calendarCol.implicitHeight + 24
    radius: 18
    color: "transparent"

    function reset() {
        cal.today = new Date();
        cal.viewDate = new Date(cal.today.getFullYear(), cal.today.getMonth(), 1);
    }
    function dateKey(d) {
        return d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate();
    }
    function isHighlighted(d) {
        return cal.highlightedDays.indexOf(cal.dateKey(d)) !== -1;
    }
    function isToday(d) {
        const t = cal.today;
        return d.getFullYear() === t.getFullYear() && d.getMonth() === t.getMonth() && d.getDate() === t.getDate();
    }
    function toggleDay(d) {
        const key = cal.dateKey(d);
        const arr = cal.highlightedDays.slice();
        const idx = arr.indexOf(key);
        if (idx === -1)
            arr.push(key);
        else
            arr.splice(idx, 1);
        cal.highlightedDays = arr;
    }
    function shiftMonth(delta) {
        cal.viewDate = new Date(cal.viewDate.getFullYear(), cal.viewDate.getMonth() + delta, 1);
    }
    function buildGrid(vd) {
        const year = vd.getFullYear();
        const month = vd.getMonth();
        const startWeekday = new Date(year, month, 1).getDay();
        const daysInMonth = new Date(year, month + 1, 0).getDate();
        const cells = [];
        for (let i = startWeekday; i > 0; i--)
            cells.push({
                "date": new Date(year, month, 1 - i),
                "inMonth": false
            });
        for (let d = 1; d <= daysInMonth; d++)
            cells.push({
                "date": new Date(year, month, d),
                "inMonth": true
            });
        let next = 1;
        while (cells.length < 42) {
            cells.push({
                "date": new Date(year, month + 1, next),
                "inMonth": false
            });
            next++;
        }
        return cells;
    }

    ColumnLayout {
        id: calendarCol
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true

            Text {
                text: "\u2039"
                color: cal.theme.on_background
                font.pixelSize: 16
                font.bold: true
                font.family: cal.settings.fontdefault
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cal.shiftMonth(-1)
                }
            }
            Text {
                Layout.fillWidth: true
                horizontalAlignment: Text.AlignHCenter
                text: Qt.formatDate(cal.viewDate, "MMMM yyyy")
                color: cal.theme.on_background
                font.pixelSize: 13
                font.bold: true
                font.family: cal.settings.fontdefault
                // click the title to jump back to the current month
                MouseArea {
                    anchors.fill: parent
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cal.reset()
                }
            }
            Text {
                text: "\u203A"
                color: cal.theme.on_background
                font.pixelSize: 16
                font.bold: true
                font.family: cal.settings.fontdefault
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: cal.shiftMonth(1)
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 0

            Repeater {
                model: ["S", "M", "T", "W", "T", "F", "S"]
                delegate: Text {
                    required property string modelData
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    text: modelData
                    color: cal.theme.on_background
                    opacity: 0.5
                    font.pixelSize: 10
                    font.family: cal.settings.fontdefault
                    font.bold: true
                }
            }
        }

        GridLayout {
            Layout.fillWidth: true
            columns: 7
            rowSpacing: 3
            columnSpacing: 3

            Repeater {
                model: cal.gridCells

                delegate: Rectangle {
                    id: dayCell
                    required property var modelData
                    readonly property bool selected: cal.isHighlighted(dayCell.modelData.date)
                    readonly property bool isTodayCell: cal.isToday(dayCell.modelData.date)

                    Layout.fillWidth: true
                    Layout.preferredHeight: 26
                    radius: 13
                    opacity: dayCell.modelData.inMonth ? 1.0 : 0.35
                    color: dayCell.selected && !dayCell.isTodayCell ? cal.theme.primary : "transparent"

                    Behavior on color {
                        ColorAnimation {
                            duration: 120
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: dayCell.modelData.date.getDate()
                        color: dayCell.selected && !dayCell.isTodayCell ? cal.theme.on_primary : (dayCell.isTodayCell ? cal.theme.primary : cal.theme.on_background)
                        font.pixelSize: dayCell.isTodayCell ? 20 : 11
                        font.bold: true
                        font.family: cal.settings.fontdefault
                    }

                    MouseArea {
                        anchors.fill: parent
                        enabled: dayCell.modelData.inMonth
                        cursorShape: Qt.PointingHandCursor
                        onClicked: cal.toggleDay(dayCell.modelData.date)
                    }
                }
            }
        }
    }
}
