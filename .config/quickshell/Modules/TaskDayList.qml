pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components
import qs.Services

// The days of a task, under its heatmap, in the style of the immersion panel's Recent list: the last two
// weeks newest first, or only the day picked on the heatmap. Each row says what the day was and has a
// round button to tick or undo it (the heatmap no longer ticks on a click, it selects).
Item {
    id: root

    property var task: null
    property var heat: null                 // the HeatmapGrid, for its cells, state text and tickDay
    property string selectedKey: ""
    // by id: the task object itself is replaced on every change, a tick included
    readonly property string taskId: task ? task.id : ""

    function dayLabel(key) {
        if (key === Tasks.todayKey)
            return "Today";
        if (key === Tasks.keyOf(Tasks.addDays(Tasks.dateOf(Tasks.todayKey), -1)))
            return "Yesterday";
        return Qt.formatDate(Tasks.dateOf(key), "ddd d MMM");
    }
    readonly property var rows: {
        const cells = heat ? heat.cells : [];
        if (selectedKey !== "") {
            const c = cells.find(x => x.key === selectedKey);
            return c && c.state !== "future" ? [c] : [];
        }
        const out = [];
        for (let i = cells.length - 1; i >= 0 && out.length < 14; i--) {
            const c = cells[i];
            // days the task doesn't repeat on, and days before it existed, are not worth a row
            if (c.state === "future" || c.state === "off" || c.state === "before")
                continue;
            out.push(c);
        }
        return out;
    }

    ListView {
        id: list
        anchors.fill: parent
        clip: true
        spacing: 2
        boundsBehavior: Flickable.StopAtBounds
        // a row count, not the rows: delegates stay put while the days underneath change
        model: root.rows.length
        Connections {
            target: root
            function onSelectedKeyChanged() { list.positionViewAtBeginning(); }
            function onTaskIdChanged() { list.positionViewAtBeginning(); }
        }

        StyledText {
            parent: list
            anchors.centerIn: parent
            visible: root.rows.length === 0
            horizontalAlignment: Text.AlignHCenter
            role: "bodyMedium"
            color: Colors.on_surface_variant
            text: root.selectedKey !== "" ? "Nothing to tick on that day." : "No days yet."
        }

        delegate: Item {
            id: row
            required property int index
            readonly property var c: root.rows[index]
            readonly property string st: c ? c.state : ""
            readonly property color accent: root.task ? Tasks.accentFor(root.task) : Colors.primary
            width: list.width
            height: 48

            // the rows come in one after the other, again whenever the day or the task changes
            Appear { id: rowIn; delay: Math.min(row.index, 6) * 40; lift: 10 }
            Connections {
                target: root
                function onSelectedKeyChanged() { rowIn.replay(); }
                function onTaskIdChanged() { rowIn.replay(); }
            }

            HoverHandler { id: hover }
            Rectangle {
                anchors.fill: parent
                radius: Motion.shapeLarge
                color: hover.hovered ? Colors.surface_container_highest : "transparent"
                Behavior on color { ColorFade {} }
            }
            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 8
                anchors.rightMargin: 8
                spacing: 12

                // what the day was: a filled circle when done, a rounded square otherwise
                Rectangle {
                    Layout.preferredWidth: 32
                    Layout.preferredHeight: 32
                    radius: row.st === "done" ? 16 : 10
                    Behavior on radius { Spring { speed: "fast" } }
                    color: row.st === "done" ? row.accent
                        : row.st === "partial" ? Qt.alpha(row.accent, 0.3)
                        : row.st === "skipped" ? Colors.tertiary_container
                        : row.st === "pending" ? Colors.secondary_container
                        : Colors.surface_container_highest
                    Behavior on color { ColorFade {} }
                    Icon {
                        anchors.centerIn: parent
                        size: 18
                        name: row.st === "done" ? "check" : row.st === "partial" ? "timelapse" : row.st === "skipped" ? "bedtime" : row.st === "pending" ? "radio_button_unchecked" : "close"
                        color: row.st === "done" ? (root.task ? Tasks.onAccentFor(root.task) : Colors.on_primary)
                            : row.st === "skipped" ? Colors.on_tertiary_container
                            : row.st === "pending" ? Colors.on_secondary_container
                            : Colors.on_surface_variant
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        Layout.fillWidth: true
                        role: "bodyLarge"
                        emphasized: true
                        elide: Text.ElideRight
                        text: row.c ? root.dayLabel(row.c.key) : ""
                    }
                    StyledText {
                        Layout.fillWidth: true
                        role: "bodySmall"
                        color: Colors.on_surface_variant
                        elide: Text.ElideRight
                        text: row.c && root.heat ? root.heat.stateText(row.c) : ""
                    }
                }
                // tick or undo that day
                IconButton {
                    icon: "check"
                    size: "xs"
                    style: row.st === "done" ? "filled" : "tonal"
                    enabled: row.st !== "future"
                    onClicked: if (row.c && root.heat) root.heat.tickDay(row.c.key)
                }
            }
        }
    }
}
