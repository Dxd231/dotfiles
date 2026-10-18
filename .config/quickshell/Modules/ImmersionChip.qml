import QtQuick
import qs
import qs.Components

// A small read-only pill of facts on the immersion card: "Ep 3 / 12", "1.25×", "Audio only".
Rectangle {
    id: chip

    property string text
    property string icon
    property color tint: Colors.surface_container_highest
    property color ink: Colors.on_surface_variant

    implicitHeight: 26
    implicitWidth: row.implicitWidth + (icon !== "" ? 18 : 22)
    radius: 13
    color: tint
    Appear {}

    Row {
        id: row
        anchors.centerIn: parent
        spacing: 4
        Icon {
            visible: chip.icon !== ""
            anchors.verticalCenter: parent.verticalCenter
            size: 14
            name: chip.icon
            color: chip.ink
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelMedium"
            emphasized: true
            color: chip.ink
            text: chip.text
        }
    }
}
