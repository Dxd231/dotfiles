import QtQuick
import qs

// A field of big, soft M3 Expressive shapes around the edges of a screen (the lock screen and the
// login screen), so the card in the middle has company. They spin slowly, drift a few pixels and
// morph through their own shape cycles. The field listens: key presses nudge a couple of shapes,
// `failed` turns them all to the error container, and `unlocking` sends them outward.
Item {
    id: field

    property real enter: 1            // 0 -> 1, springs the shapes in one after another
    property int keyTick: 0
    property bool failed: false
    property real unlockT: 0          // 0 -> 1 while unlocking

    // x, y: centre as a share of the field; size: share of its height
    readonly property var _spec: [
        { x: 0.07, y: 0.14, size: 0.42, role: 0, cycle: [7, 4, 1], speed: 9, every: 7000 },
        { x: 0.94, y: 0.17, size: 0.34, role: 1, cycle: [5, 0, 2], speed: -12, every: 6000 },
        { x: 0.11, y: 0.90, size: 0.36, role: 2, cycle: [3, 6, 4], speed: -8, every: 8200 },
        { x: 0.91, y: 0.88, size: 0.46, role: 0, cycle: [1, 7, 5], speed: 14, every: 5600 },
        { x: 0.235, y: 0.47, size: 0.13, role: 3, cycle: [4, 7], speed: 18, every: 5200 },
        { x: 0.775, y: 0.45, size: 0.15, role: 1, cycle: [0, 2, 5], speed: -16, every: 6800 },
        { x: 0.72, y: 0.04, size: 0.2, role: 2, cycle: [6, 5, 3], speed: 11, every: 7600 }
    ]
    readonly property var _fill: [Colors.primary_container, Colors.tertiary_container, Colors.secondary_container, Colors.primary]

    property real _t: 0
    FrameAnimation {
        running: field.visible
        onTriggered: field._t += frameTime
    }

    Repeater {
        model: field._spec.length
        delegate: Item {
            id: slot
            required property int index
            readonly property var spec: field._spec[index]
            readonly property real size: field.height * spec.size
            readonly property real cx: field.width * spec.x
            readonly property real cy: field.height * spec.y
            // the shape's own spring in, staggered
            property real arrive: 0
            property real kick: 0

            Timer {
                interval: 90 + slot.index * 80
                running: true
                onTriggered: slot.arrive = 1
            }
            Behavior on arrive { Spring { speed: "slow" } }

            Connections {
                target: field
                function onKeyTickChanged() {
                    const n = field._spec.length;
                    if (slot.index === field.keyTick % n || slot.index === (field.keyTick * 3 + 2) % n) {
                        slot.kick = 1;
                        kickBack.restart();
                    }
                }
            }
            Timer {
                id: kickBack
                interval: 110
                onTriggered: slot.kick = 0
            }

            // outward from the middle while unlocking
            readonly property real _dx: (cx - field.width / 2) / Math.max(1, field.width / 2)
            readonly property real _dy: (cy - field.height / 2) / Math.max(1, field.height / 2)

            width: size
            height: size
            x: cx - size / 2 + Math.sin(field._t * 0.35 + index * 1.7) * 12 + _dx * field.width * 0.22 * field.unlockT
            y: cy - size / 2 + Math.cos(field._t * 0.28 + index * 2.3) * 10 + _dy * field.height * 0.22 * field.unlockT
            scale: (0.5 + 0.5 * Math.max(0, arrive)) * (1 + 0.35 * field.unlockT)
            opacity: Math.min(1, arrive * 1.5) * (1 - field.unlockT) * 0.9

            ShapeBadge {
                anchors.fill: parent
                shapeRest: slot.spec.cycle[0]
                cycle: slot.spec.cycle
                cycleInterval: slot.spec.every
                spinning: true
                spinSpeed: slot.spec.speed
                color: field.failed ? Colors.error_container : field._fill[slot.spec.role]
                badgeScale: 1 + 0.06 * slot.kick
            }
        }
    }
}
