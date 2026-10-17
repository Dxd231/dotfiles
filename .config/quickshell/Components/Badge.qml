import QtQuick
import qs

// M3 badge: 6px dot when `text` is empty, otherwise a 16px pill with labelSmall text.
Rectangle {
    id: badge

    property string text
    property color textColor: Colors.on_error

    readonly property bool large: text !== ""
    implicitHeight: large ? 16 : 6
    implicitWidth: large ? Math.max(16, label.implicitWidth + 8) : 6
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    color: Colors.error

    StyledText {
        id: label
        visible: badge.large
        anchors.centerIn: parent
        role: "labelSmall"
        text: badge.text
        color: badge.textColor
    }
}
