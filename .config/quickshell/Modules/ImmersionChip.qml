import QtQuick
import qs
import qs.Components

// A small read-only pill of facts on the immersion card: "Ep 3 / 12", "1.25×", "Audio only".
Rectangle {
    id: chip

    property string text
    property string icon
    // { known, learning } (0..1): a tiny three-way wavy ring in place of the icon
    property var ring: null
    property color tint: Colors.surface_container_highest
    property color ink: Colors.on_surface_variant

    implicitHeight: 26
    implicitWidth: Math.max(0, _w)
    property real _w: row.implicitWidth + (icon !== "" || ring !== null ? 18 : 22)
    Behavior on _w { Spring { speed: "fast" } }
    radius: 13
    color: tint
    Behavior on color { ColorFade {} }
    Appear {}

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        WavyRing {
            opacity: chip.ring !== null ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            anchors.verticalCenter: parent.verticalCenter
            width: 16
            height: 16
            thickness: 3
            amplitude: 0.5
            waves: 8
            gap: 44
            value: chip.ring ? chip.ring.known : 0
            secondValue: chip.ring ? chip.ring.learning : 0
            activeColor: chip.ink
            secondColor: Colors.secondary
            trackColor: Qt.alpha(chip.ink, 0.28)
        }
        Icon {
            opacity: chip.icon !== "" && chip.ring === null ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            name: chip.icon
            color: chip.ink
        }
        SwapText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelMedium"
            emphasized: true
            color: chip.ink
            value: chip.text
        }
    }
}
