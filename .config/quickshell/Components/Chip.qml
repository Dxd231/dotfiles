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
    implicitWidth: row.implicitWidth + (_leading !== "" ? 8 : 16) + (trailingIcon !== "" ? 8 : 16)
    restRadius: Motion.shapeSmall
    // unselected chips use a surface fill rather than the spec's 1px outline (design preference)
    color: selected ? Colors.secondary_container : Colors.surface_container_highest
    contentColor: selected ? Colors.on_secondary_container : Colors.on_surface_variant

    Row {
        id: row
        anchors.verticalCenter: parent.verticalCenter
        x: chip._leading !== "" ? 8 : 16
        spacing: 8

        Icon {
            visible: chip._leading !== ""
            anchors.verticalCenter: parent.verticalCenter
            name: chip._leading
            size: 18
            color: chip.selected ? Colors.on_secondary_container : (chip.kind === "assist" ? Colors.primary : Colors.on_surface_variant)
        }
        StyledText {
            anchors.verticalCenter: parent.verticalCenter
            role: "labelLarge"
            text: chip.text
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
