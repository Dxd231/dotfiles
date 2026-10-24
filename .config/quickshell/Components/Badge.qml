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
    width: Math.max(0, _w)
    height: Math.max(0, _h)
    property real _w: implicitWidth
    property real _h: implicitHeight
    Behavior on _w { Spring { speed: "fast" } }
    Behavior on _h { Spring { speed: "fast" } }
    Behavior on color { ColorFade {} }
    radius: height / 2
    color: Colors.error

    StyledText {
        id: label
        opacity: badge.large ? 1 : 0
        visible: opacity > 0
        Behavior on opacity { Fade {} }
        anchors.centerIn: parent
        role: "labelSmall"
        text: badge.text
        color: badge.textColor
    }
}
