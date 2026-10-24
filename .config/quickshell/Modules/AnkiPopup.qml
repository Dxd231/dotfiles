pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Io
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Mining panel: how many cards have been mined today against the daily goal (a wavy ring that takes a
// second lap past it), the streak of goal-met days, a heatmap of cards per day, the latest words, and
// the review queue. The numbers come from the Anki singleton, which asks AnkiConnect.
BarPopup {
    id: win

    WlrLayershell.namespace: "quickshell:calendar_popup"
    panelWidth: 360
    spacing: 16

    // ---- entrance: sections rise in one after another each time the panel opens ----
    property int stage: 0
    onIsOpenChanged: {
        if (isOpen) {
            Anki.refresh();
            stageTimer.restart();
        } else {
            stageTimer.stop();
            stage = 0;
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

    readonly property real frac: Anki.minedToday / Math.max(1, Anki.todayGoal)
    readonly property string caption: {
        if (!Anki.fresh && !Anki.online)
            return "Open Anki to count your cards";
        if (Anki.overGoal)
            return "+" + (Anki.minedToday - Anki.todayGoal) + " over, keep going";
        if (Anki.goalMet)
            return "Goal met";
        if (Anki.minedToday === 0)
            return "Mine your first card today";
        if (Anki.toGo === 1)
            return "One more to go";
        return Anki.toGo + " to go";
    }

    // the day picked on the heatmap, for the busy / rest picker
    property string pickedDay: ""
    // the newest day that reached the goal: the only one the heatmap draws as a spinning star
    readonly property string lastGoalDay: {
        let best = "";
        for (const k in Anki.days)
            if (Anki.days[k] >= Anki.goalOn(k) && k > best)
                best = k;
        return best;
    }
    readonly property var dayCache: {
        Anki.days;
        Anki.goal;
        DayMarks.marks;
        lastGoalDay;
        return ({});
    }
    function dayInfo(key) {
        const cache = dayCache;
        return cache[key] || (cache[key] = dayInfoOf(key));
    }
    function dayInfoOf(key) {
        const n = Anki.days[key] || 0;
        if (n === 0)
            return { level: 0, label: "Nothing mined" };
        const r = n / Math.max(1, Anki.goalOn(key));
        return { level: r >= 1 ? 4 : r >= 0.6 ? 3 : r >= 0.3 ? 2 : 1, label: n + (n === 1 ? " card" : " cards") + " mined", star: key === lastGoalDay };
    }
    function when(w) {
        const k = w.day;
        if (k === Anki.todayKey)
            return "Today";
        return Qt.formatDate(Tasks.dateOf(k), "ddd d MMM");
    }

    // ---- the ring ----
    Item {
        id: ringBox
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 200
        Layout.preferredHeight: 200
        property real appear: win.stage >= 1 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.75 + 0.25 * appear

        WavyRing {
            anchors.fill: parent
            value: Math.min(1, win.frac) * ringBox.appear
            waving: Anki.online && win.isOpen
            idleDrift: 1.2
            quicken: true
            pace: win.frac
            overdrive: Anki.overGoal
            overValue: Math.min(1, win.frac - 1)
            overColor: Colors.tertiary
            activeColor: Anki.goalMet ? Colors.tertiary : Colors.primary
            trackColor: Anki.goalMet ? Colors.tertiary_container : Colors.secondary_container
        }
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 0
            RowLayout {
                Layout.alignment: Qt.AlignHCenter
                spacing: 2
                RollingDigits {
                    Layout.alignment: Qt.AlignBottom
                    pixelSize: 56
                    color: Colors.on_surface
                    text: String(Anki.minedToday)
                }
                StyledText {
                    Layout.alignment: Qt.AlignBottom
                    Layout.bottomMargin: 6
                    role: "titleMedium"
                    emphasized: true
                    color: Colors.on_surface_variant
                    text: "/" + Anki.todayGoal
                }
            }
            StyledText {
                Layout.alignment: Qt.AlignHCenter
                Layout.maximumWidth: 130
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.WordWrap
                role: "labelLarge"
                emphasized: true
                color: Anki.goalMet ? Colors.tertiary : Colors.on_surface_variant
                text: win.caption
            }
        }
    }

    // ---- streak and best ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 3
        property real appear: win.stage >= 2 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.9 + 0.1 * appear

        Repeater {
            model: [
                { icon: "local_fire_department", label: "Streak", value: Anki.streak, shape: "flower", first: true },
                { icon: "bolt", label: "Best", value: Anki.best, shape: "star4", first: false }
            ]
            delegate: Rectangle {
                id: tile
                required property var modelData
                Layout.fillWidth: true
                Layout.preferredHeight: 64
                color: Colors.surface_container_high
                topLeftRadius: modelData.first ? 20 : 4
                bottomLeftRadius: modelData.first ? 20 : 4
                topRightRadius: modelData.first ? 4 : 20
                bottomRightRadius: modelData.first ? 4 : 20

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 12
                    anchors.rightMargin: 12
                    spacing: 10
                    ShapeBadge {
                        Layout.preferredWidth: 36
                        Layout.preferredHeight: 36
                        shapeRest: tile.modelData.shape
                        shapeActive: tile.modelData.shape
                        color: tile.modelData.first && Anki.streak > 0 ? Colors.tertiary_container : Colors.primary_container
                        Icon {
                            anchors.centerIn: parent
                            size: 20
                            name: tile.modelData.icon
                            color: tile.modelData.first && Anki.streak > 0 ? Colors.on_tertiary_container : Colors.on_primary_container
                        }
                    }
                    ColumnLayout {
                        spacing: 0
                        RollingDigits {
                            pixelSize: 22
                            color: Colors.on_surface
                            text: String(tile.modelData.value)
                        }
                        StyledText {
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            text: tile.modelData.label + (tile.modelData.value === 1 ? " day" : " days")
                        }
                    }
                }
            }
        }
    }

    // ---- cards per day ----
    DayMarkPicker {
        Layout.fillWidth: true
        key: win.pickedDay !== "" ? win.pickedDay : Anki.todayKey
    }
    HeatmapGrid {
        id: heat
        Layout.alignment: Qt.AlignHCenter
        weeks: 15
        dayInfo: win.dayInfo
        selectedKey: win.pickedDay
        onDaySelected: key => win.pickedDay = win.pickedDay === key ? "" : key
        property real appear: win.stage >= 3 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))
    }

    // ---- latest words ----
    Collapse {
        open: Anki.words.length > 0
        Layout.fillWidth: true
        ColumnLayout {
            spacing: 3
            property real appear: win.stage >= 4 ? 1 : 0
            Behavior on appear { Spring { speed: "default" } }
            opacity: Math.max(0, Math.min(1, appear * 1.6))

            StyledText {
                Layout.leftMargin: 4
                Layout.bottomMargin: 2
                role: "labelLarge"
                emphasized: true
                color: Colors.on_surface_variant
                text: "Latest words"
            }
            Repeater {
                model: Anki.words.slice(0, 5)
                delegate: Rectangle {
                    id: row
                    required property var modelData
                    required property int index
                    readonly property int last: Math.min(5, Anki.words.length) - 1
                    Layout.fillWidth: true
                    Layout.preferredHeight: 52
                    color: Colors.surface_container_high
                    topLeftRadius: index === 0 ? 20 : 4
                    topRightRadius: index === 0 ? 20 : 4
                    bottomLeftRadius: index === last ? 20 : 4
                    bottomRightRadius: index === last ? 20 : 4

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 8
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                jp: true
                                role: "titleMedium"
                                emphasized: true
                                elide: Text.ElideRight
                                text: row.modelData.expression + (row.modelData.reading && row.modelData.reading !== row.modelData.expression ? "  " + row.modelData.reading : "")
                            }
                            StyledText {
                                Layout.fillWidth: true
                                jp: true
                                role: "bodySmall"
                                color: Colors.on_surface_variant
                                elide: Text.ElideRight
                                text: row.modelData.sentence
                            }
                        }
                        StyledText {
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            text: win.when(row.modelData)
                        }
                    }
                }
            }
        }
    }

    // ---- reviews and the goal ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 8
        property real appear: win.stage >= 5 ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, appear * 1.6))

        Button {
            Layout.fillWidth: true
            icon: "play_arrow"
            style: Anki.online ? "tonal" : "filled"
            size: "m"
            text: !Anki.online ? "Open Anki" : Anki.due > 0 ? "Review " + Anki.due + " due" : "Nothing due"
            onClicked: Anki.review()
        }
        IconButton {
            icon: "remove"
            style: "tonal"
            size: "m"
            enabled: Anki.goal > 1
            onClicked: Anki.setGoal(Anki.goal - 1)
        }
        IconButton {
            icon: "add"
            style: "tonal"
            size: "m"
            onClicked: Anki.setGoal(Anki.goal + 1)
        }
    }

    IpcHandler {
        target: "ankipanel"
        function toggle(): void { win.toggle(); }
        function open(): void { win.show(); }
        function close(): void { win.hide(); }
    }
}
