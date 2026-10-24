import QtQuick
import qs
import qs.Components

// How well a word is known: a connected group of four segments (Unknown, Learning, Known, Ignore), pill
// on the outside, tight where segments meet, the chosen one a 12px squircle in its own colour.
Item {
    id: group

    property string current: "unknown"
    // false snaps the segments to the status (a card that is still being placed)
    property bool animate: true
    signal picked(string status)

    readonly property var items: [
        { k: "unknown", t: "Unknown", c: Colors.tertiary, on: Colors.on_tertiary },
        { k: "learning", t: "Learning", c: Colors.secondary, on: Colors.on_secondary },
        { k: "known", t: "Known", c: Colors.primary, on: Colors.on_primary },
        { k: "ignored", t: "Ignore", c: Colors.inverse_surface, on: Colors.inverse_on_surface }
    ]

    implicitHeight: 40

    Row {
        spacing: 2
        Repeater {
            model: group.items
            delegate: Clickable {
                id: seg
                required property var modelData
                required property int index
                readonly property bool here: group.current === modelData.k
                property real _inner: here ? 12 : pressed ? 2 : 4
                property real _outer: here ? 12 : height / 2
                Behavior on _inner { enabled: group.animate; Spring { speed: "fast" } }
                Behavior on _outer { enabled: group.animate; Spring { speed: "fast" } }
                width: Math.max(0, (group.width - 6) / 4)
                height: 40
                animate: group.animate
                restRadius: 12
                pressedRadius: 12
                topLeftRadius: Math.max(0, index === 0 ? _outer : _inner)
                bottomLeftRadius: topLeftRadius
                topRightRadius: Math.max(0, index === group.items.length - 1 ? _outer : _inner)
                bottomRightRadius: topRightRadius
                color: here ? modelData.c : Colors.surface_container_highest
                contentColor: here ? modelData.on : Colors.on_surface_variant
                onClicked: group.picked(modelData.k)

                StyledText {
                    anchors.centerIn: parent
                    role: "labelLarge"
                    emphasized: true
                    text: seg.modelData.t
                    color: seg.contentColor
                }
            }
        }
    }
}
