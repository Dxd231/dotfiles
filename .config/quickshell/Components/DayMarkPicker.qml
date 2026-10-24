import QtQuick
import QtQuick.Layouts
import qs
import qs.Services

// Busy / Rest for one day, shared by every tracker: busy halves the day's goal, rest only pauses the
// streak. Click the active one again to clear it.
RowLayout {
    id: picker

    // the day it acts on (yyyy-MM-dd)
    property string key: Tasks.todayKey
    readonly property string mark: DayMarks.markOf(key)

    spacing: 8

    Row {
        spacing: 2
        ConnectedButton {
            position: "first"
            icon: "work"
            text: "Busy"
            selected: picker.mark === "busy"
            onClicked: DayMarks.setMark(picker.key, "busy")
        }
        ConnectedButton {
            position: "last"
            icon: "bedtime"
            text: "Rest"
            selected: picker.mark === "rest"
            enabled: DayMarks.canMark(picker.key, "rest")
            opacity: enabled ? 1 : 0.5
            Behavior on opacity { Fade {} }
            onClicked: DayMarks.setMark(picker.key, "rest")
        }
    }
    StyledText {
        Layout.fillWidth: true
        role: "labelSmall"
        color: Colors.on_surface_variant
        elide: Text.ElideRight
        text: (picker.key === Tasks.todayKey ? "Today" : Qt.formatDate(Tasks.dateOf(picker.key), "ddd d MMM"))
            + " · " + (picker.mark === "busy" ? "half goal" : picker.mark === "rest" ? "streak paused" : DayMarks.restsLeft(picker.key) + " of " + DayMarks.restsPerMonth + " rests left")
    }
}
