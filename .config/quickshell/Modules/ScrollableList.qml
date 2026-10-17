import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs

// Height-capped segmented list (2px item gaps) that scrolls once it exceeds `maxHeight`.
ListView {
    id: list

    property real maxHeight: 300

    Layout.fillWidth: true
    implicitHeight: Math.min(maxHeight, contentHeight)
    spacing: 2
    clip: true
    boundsBehavior: Flickable.StopAtBounds
    interactive: contentHeight > maxHeight

    ScrollBar.vertical: ScrollBar {
        id: bar
        policy: ScrollBar.AsNeeded
        contentItem: Rectangle {
            implicitWidth: 4
            radius: 2
            color: Colors.outline
            opacity: bar.size < 1 ? (bar.active ? 1 : 0.4) : 0
        }
        background: Item { implicitWidth: 4 }
    }
}
