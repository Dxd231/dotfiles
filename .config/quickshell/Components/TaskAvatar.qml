import QtQuick
import qs
import qs.Services

// A task's first letter on its own turning shape. Every task keeps the shape and accent it was
// given; once `done` the shape morphs (with overshoot) to the sunny one, fills with the accent and
// keeps turning.
ShapeBadge {
    id: avatar

    property var task: null
    property bool done: false
    // text size as a share of the badge
    property real letterScale: 0.42

    implicitWidth: 40
    implicitHeight: 40
    shapeRest: Tasks.shapeFor(task)
    shapeActive: 4
    active: done
    spinning: done && visible
    color: done ? Tasks.accentFor(task) : Tasks.containerFor(task)

    Text {
        anchors.centerIn: parent
        text: avatar.task && avatar.task.name ? avatar.task.name.charAt(0).toUpperCase() : "?"
        color: avatar.done ? Tasks.onAccentFor(avatar.task) : Tasks.onContainerFor(avatar.task)
        font.family: Typography.family
        font.pixelSize: Math.round(avatar.height * avatar.letterScale)
        font.weight: Font.Bold
        Behavior on color { ColorFade {} }
    }
}
