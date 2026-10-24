import QtQuick
import qs
import qs.Components

// Which media the left card of the immersion panel shows: anime (mpv), a book (ttu) or manga (Kavita).
// By default it follows what you are doing; picking one pins the card to it (`pinned`, marked by a
// pin badge). A dot marks every source that is live right now.
Item {
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

    width: 3 * 48 + 2 * 2
    height: 40

    Row {
        spacing: 2
        Repeater {
            model: sw.items
            delegate: Clickable {
                id: slot
                required property var modelData
                required property int index
                readonly property bool here: sw.current === modelData.k
                // a connected group: pill on the outside, tight where segments meet, a 12px squircle when active
                readonly property real outer: here ? 12 : height / 2
                property real _inner: here ? 12 : pressed ? 2 : 4
                property real _outer: outer
                Behavior on _inner { Spring { speed: "fast" } }
                Behavior on _outer { Spring { speed: "fast" } }
                width: 48
                height: 40
                restRadius: 12
                pressedRadius: 12
                topLeftRadius: Math.max(0, index === 0 ? _outer : _inner)
                bottomLeftRadius: topLeftRadius
                topRightRadius: Math.max(0, index === sw.items.length - 1 ? _outer : _inner)
                bottomRightRadius: topRightRadius
                color: here ? modelData.c : Colors.surface_container_highest
                contentColor: here ? modelData.on : Colors.on_surface_variant
                onClicked: sw.picked(modelData.k)
                Icon {
                    anchors.centerIn: parent
                    size: 20
                    name: slot.modelData.i
                    color: slot.here ? slot.modelData.on : Colors.on_surface_variant
                }
                // the pinned source wears a four-point star with a pin, in the corner opposite the live shape
                ShapeBadge {
                    x: parent.width - 14
                    y: parent.height - 14
                    width: 14
                    height: 14
                    shapeRest: "star4"
                    shapeActive: "star4"
                    color: Colors.on_surface
                    scale: sw.pinned && slot.here ? 1 : 0
                    visible: scale > 0.02
                    Behavior on scale { Spring { speed: "fast" } }
                }
                // while that source is live: a small shape that turns and drifts between shapes
                ShapeBadge {
                    x: parent.width - 15
                    y: 3
                    width: 11
                    height: 11
                    shapeRest: "sunny"
                    shapeActive: "sunny"
                    color: slot.here ? slot.modelData.on : slot.modelData.c
                    scale: slot.modelData.live ? 1 : 0
                    visible: scale > 0.02
                    Behavior on scale { Spring { speed: "fast" } }
                    spinning: slot.modelData.live
                    spinSpeed: 40
                    cycle: ["sunny", "cookie4", "softBurst"]
                    cycleInterval: 1700
                }
            }
        }
    }
}
