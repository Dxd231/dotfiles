import QtQuick
import qs

// M3 Expressive linear progress indicator: rounded active indicator, 4px gap,
// track, and a stop dot at the end. Thickness defaults to the 4px token.
Item {
    id: progress

    property real value: 0 // 0..1
    property real thickness: 4
    property color activeColor: Colors.primary
    property color trackColor: Colors.secondary_container
    property bool showStop: true
    // spring between values; turn off when the value already moves continuously (countdowns)
    property bool animated: true

    property real _visual: Math.max(0, Math.min(1, value))
    Behavior on _visual {
        enabled: progress.animated
        Spring { expressive: false }
    }

    implicitWidth: 200
    implicitHeight: thickness

    Rectangle {
        id: active
        height: progress.thickness
        anchors.verticalCenter: parent.verticalCenter
        width: progress._visual * progress.width
        visible: width > 0.5
        radius: height / 2
        color: progress.activeColor
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        height: progress.thickness
        width: Math.max(0, progress.width - active.width - (active.visible ? 4 : 0))
        visible: width > height
        radius: height / 2
        color: progress.trackColor

        Rectangle {
            visible: progress.showStop
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: 4
            height: 4
            radius: 2
            anchors.rightMargin: (progress.thickness - 4) / 2
            color: progress.activeColor
        }
    }
}
