pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Right-click menu of the task chip: today's tasks with a check each, so a day can be ticked
// without opening the panel. Ticking keeps the menu open; the undo snackbar covers a mis-click.
BarPopup {
    id: menu

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 300
    padding: 12
    spacing: 4

    StyledText {
        Layout.leftMargin: 6
        Layout.bottomMargin: 4
        role: "titleMedium"
        emphasized: true
        text: Tasks.dueCount === 0 ? "Nothing due today" : (Tasks.dueCount - Tasks.pendingCount) + " of " + Tasks.dueCount + " done today"
    }

    Repeater {
        // a row count, not the tasks: rows keep their state while the data changes
        model: Tasks.dueToday.length
        delegate: Clickable {
            id: row
            required property int index
            readonly property var t: Tasks.dueToday[index]
            readonly property bool isDone: !!t && Tasks.isDone(t, Tasks.todayKey)

            Layout.fillWidth: true
            implicitHeight: 56
            restRadius: Motion.shapeLarge
            pressedRadius: Motion.shapeSmall
            color: row.isDone ? Colors.secondary_container : "transparent"
            contentColor: row.isDone ? Colors.on_secondary_container : Colors.on_surface
            onClicked: if (t) Tasks.toggleDone(t.id, Tasks.todayKey)

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12
                TaskAvatar {
                    Layout.preferredWidth: 36
                    Layout.preferredHeight: 36
                    task: row.t
                    done: row.isDone
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
                    StyledText {
                        role: "bodySmall"
                        color: row.isDone ? Colors.on_secondary_container : Colors.on_surface_variant
                        text: !row.t ? "" : Tasks.targetOf(row.t) > 1
                            ? Tasks.countOf(row.t, Tasks.todayKey) + " of " + Tasks.targetOf(row.t) + " today"
                            : Tasks.streak(row.t) > 0 ? Tasks.streak(row.t) + "-day streak" : "No streak yet"
                    }
                }
                // the same check as the panel: round while open, squarer once done
                IconButton {
                    icon: "check"
                    style: "filled"
                    checkable: true
                    checked: row.isDone
                    color: row.isDone ? Tasks.accentFor(row.t) : Colors.surface_container_highest
                    contentColor: row.isDone ? Tasks.onAccentFor(row.t) : Colors.on_surface_variant
                    onClicked: if (row.t) Tasks.toggleDone(row.t.id, Tasks.todayKey)
                }
            }
        }
    }
}
