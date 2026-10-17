pragma ComponentBehavior: Bound
import QtQuick
import Quickshell.Hyprland
import qs
import qs.Components

// Workspace track with an M3 Expressive active indicator.
Rectangle {
    id: ws

    readonly property var kanji: ["一", "二", "三", "四", "五", "六", "七", "八", "九", "十", "十一", "十二", "十三", "十四", "十五"]
    readonly property int slot: 28
    readonly property int spacing: 4
    readonly property int pad: 2

    // refreshed on window events so occupancy (lastIpcObject) stays current
    property int _refresh: 0
    readonly property var byId: {
        _refresh;
        const map = {};
        for (const w of Hyprland.workspaces.values)
            map[w.id] = w;
        return map;
    }
    readonly property int count: {
        let max = 10;
        for (const id in byId)
            if (id > max && id <= 15)
                max = Number(id);
        return max;
    }
    readonly property int activeIndex: Hyprland.focusedWorkspace && Hyprland.focusedWorkspace.id >= 1 && Hyprland.focusedWorkspace.id <= count ? Hyprland.focusedWorkspace.id - 1 : -1

    function activate(id) {
        const w = byId[id];
        if (w)
            w.activate();
        else
            Hyprland.dispatch("hl.dsp.focus({ workspace = " + id + " })");
    }

    implicitHeight: 32
    implicitWidth: pad * 2 + count * slot + (count - 1) * spacing
    radius: 16
    color: Colors.surface_container_high

    // ---- active indicator: edges on different springs so it stretches toward the target ----
    readonly property real targetX: pad + Math.max(0, activeIndex) * (slot + spacing)
    property real leftEdge: targetX
    property real rightEdge: targetX + slot
    property bool movingRight: true
    onTargetXChanged: movingRight = targetX > leftEdge
    Behavior on leftEdge { Spring { speed: ws.movingRight ? "default" : "fast" } }
    Behavior on rightEdge { Spring { speed: ws.movingRight ? "fast" : "default" } }

    Rectangle {
        x: ws.leftEdge
        width: ws.rightEdge - ws.leftEdge
        height: 28
        anchors.verticalCenter: parent.verticalCenter
        radius: height / 2
        color: Colors.primary
        visible: ws.activeIndex >= 0
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.NoButton
        onWheel: wheel => {
            const cur = ws.activeIndex >= 0 ? ws.activeIndex + 1 : 1;
            ws.activate(wheel.angleDelta.y > 0 ? Math.max(1, cur - 1) : Math.min(ws.count, cur + 1));
        }
    }

    Row {
        x: ws.pad
        anchors.verticalCenter: parent.verticalCenter
        spacing: ws.spacing

        Repeater {
            model: ws.count
            delegate: Clickable {
                id: slot
                required property int index
                readonly property int wsId: index + 1
                readonly property var wsObj: ws.byId[wsId] || null
                readonly property bool current: index === ws.activeIndex
                readonly property bool occupied: !!wsObj && ((wsObj.toplevels && wsObj.toplevels.values.length > 0) || (wsObj.lastIpcObject && wsObj.lastIpcObject.windows > 0))

                width: ws.slot
                height: ws.slot
                pressedRadius: Motion.shapeSmall
                contentColor: current ? Colors.on_primary : Colors.on_surface
                onClicked: ws.activate(wsId)

                // empty workspace: small dot
                Rectangle {
                    anchors.centerIn: parent
                    width: 6
                    height: 6
                    radius: 3
                    color: Colors.outline
                    opacity: !slot.current && !slot.occupied ? 1 : 0
                    Behavior on opacity { Fade {} }
                }

                Text {
                    anchors.centerIn: parent
                    text: ws.kanji[slot.index] || slot.wsId
                    font.family: Typography.familyJp
                    font.pixelSize: slot.index >= 10 ? 11 : 15
                    font.weight: Font.Bold
                    color: slot.contentColor
                    opacity: slot.current || slot.occupied ? 1 : 0
                    Behavior on opacity { Fade {} }
                    Behavior on color { ColorFade {} }
                }
            }
        }
    }

    Timer {
        id: refresh
        interval: 60
        onTriggered: {
            Hyprland.refreshWorkspaces();
            ws._refresh++;
        }
    }
    Connections {
        target: Hyprland
        function onRawEvent(event) {
            const n = event.name;
            if (n === "openwindow" || n === "closewindow" || n === "movewindow" || n === "movewindowv2")
                refresh.restart();
        }
    }
}
