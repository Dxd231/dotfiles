import QtQuick
import qs

// M3 chip (assist / filter / input / suggestion): 32px, 8px corners.
// Filter chips show a leading check and secondary-container fill when selected.
Clickable {
    id: chip

    property string text
    property string icon
    property string kind: "assist" // assist | filter | input | suggestion
    property string trailingIcon
    property bool selected: false
    signal trailingClicked()

    readonly property bool _showCheck: kind === "filter" && selected
    readonly property string _leading: _showCheck ? "check" : icon

    implicitHeight: 32
    implicitWidth: Math.max(0, _w)
    property real _w: row.implicitWidth + (_leading !== "" ? 8 : 16) + (trailingIcon !== "" ? 8 : 16)
    restRadius: Motion.shapeSmall
    // unselected chips use a surface fill rather than the spec's 1px outline (design preference)
    color: selected ? Colors.secondary_container : Colors.surface_container_highest
    contentColor: selected ? Colors.on_secondary_container : Colors.on_surface_variant
    Behavior on _w { Spring { speed: "fast" } }

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: chip._leading !== "" ? 8 : 16
        Behavior on x { Spring { speed: "fast" } }
        spacing: 8

        Icon {
            // the check grows in and out as the chip is selected (M3 filter chip)
            readonly property bool on: chip._leading !== ""
            property real grow: on ? 1 : 0
            Behavior on grow { Spring { speed: "fast" } }
            visible: grow > 0.01
            width: 18 * Math.max(0, Math.min(1, grow))
            opacity: Math.max(0, Math.min(1, grow))
            scale: Math.max(0, grow)
            anchors.verticalCenter: parent.verticalCenter
            name: on ? chip._leading : "check"
            size: 18
            color: chip.selected ? Colors.on_secondary_container : (chip.kind === "assist" ? Colors.primary : Colors.on_surface_variant)
        }
        SwapText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelLarge"
            value: chip.text
            color: chip.contentColor
        }
        Icon {
            visible: chip.trailingIcon !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: chip.trailingIcon
            size: 18
            color: chip.contentColor
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                cursorShape: Qt.PointingHandCursor
                onClicked: chip.trailingClicked()
            }
        }
    }
}
