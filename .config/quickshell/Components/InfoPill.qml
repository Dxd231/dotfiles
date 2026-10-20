import QtQuick
import qs

// A small read-only label in a tonal pill (a frequency rank, an inflection, a part of speech). Not
// clickable, so it stays visibly different from a Chip.
Rectangle {
    id: pill

    property string text
    property color container: Colors.surface_container_highest
    property color content: Colors.on_surface_variant
    property bool jp: false

    implicitHeight: 24
    implicitWidth: label.implicitWidth + 20
    radius: height / 2
    color: container

    StyledText {
        id: label
        anchors.centerIn: parent
        role: "labelMedium"
        emphasized: true
        jp: pill.jp
        text: pill.text
        color: pill.content
    }
}
