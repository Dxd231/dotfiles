import QtQuick
import qs
import qs.Components

// Which media the left card of the immersion panel shows: video (mpv), a book (ttu) or manga (Kavita).
// By default it follows what you are doing; picking one pins the card to it (`pinned`, the indicator
// squares off). A dot marks every source that is live right now.
Rectangle {
    id: sw

    property string current: "mpv"
    property bool pinned: false
    property bool liveMpv: false
    property bool liveTtu: false
    property bool liveKavita: false
    signal picked(string kind)

    readonly property var items: [
        { k: "mpv", i: "movie", c: Colors.primary, on: Colors.on_primary, live: liveMpv },
        { k: "ttu", i: "auto_stories", c: Colors.tertiary, on: Colors.on_tertiary, live: liveTtu },
        { k: "kavita", i: "menu_book", c: Colors.secondary, on: Colors.on_secondary, live: liveKavita }
    ]
    readonly property int idx: Math.max(0, items.findIndex(x => x.k === current))

    width: 3 * 42 + 8
    height: 40
    radius: 20
    color: Qt.alpha(Colors.surface_container_lowest, 0.94)

    Rectangle {
        y: 4
        height: 32
        width: 42
        x: 4 + sw.idx * 42
        radius: sw.pinned ? 10 : 16
        color: sw.items[sw.idx].c
        Behavior on x { Spring { speed: "default" } }
        Behavior on radius { Spring { speed: "fast" } }
        Behavior on color { ColorFade {} }
    }
    Row {
        x: 4
        y: 4
        Repeater {
            model: sw.items
            delegate: Clickable {
                id: slot
                required property var modelData
                readonly property bool here: sw.current === modelData.k
                width: 42
                height: 32
                restRadius: 16
                pressedRadius: 10
                onClicked: sw.picked(modelData.k)
                Icon {
                    anchors.centerIn: parent
                    size: 20
                    name: slot.modelData.i
                    color: slot.here ? slot.modelData.on : Colors.on_surface_variant
                }
                // while that source is live: a small shape that turns and drifts between shapes
                ShapeBadge {
                    x: parent.width - 15
                    y: 3
                    width: 11
                    height: 11
                    shapeRest: 4
                    shapeActive: 4
                    color: slot.here ? slot.modelData.on : slot.modelData.c
                    scale: slot.modelData.live ? 1 : 0
                    visible: scale > 0.02
                    Behavior on scale { Spring { speed: "fast" } }
                    spinning: slot.modelData.live
                    spinSpeed: 40
                    cycle: [4, 5, 0]
                    cycleInterval: 1700
                }
            }
        }
    }
}
