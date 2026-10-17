import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// M3 Expressive quick-settings tile (Android 16 style): a pill when off that morphs to a
// rounded square when on. With `split`, the icon circle toggles and the rest of the tile
// opens a detail drawer (`drawerOpen` shows the chevron flipped).
Clickable {
    id: tile

    property string title
    property string subtitle
    property string icon
    property bool on: false
    property bool split: false
    property bool drawerOpen: false

    signal toggled()
    signal opened()

    implicitHeight: 64
    restRadius: on || drawerOpen ? Motion.shapeExtraLarge - 8 : height / 2
    pressedRadius: Motion.shapeMedium
    color: on ? Colors.primary : Colors.surface_container_highest
    contentColor: on ? Colors.on_primary : Colors.on_surface
    onClicked: split ? opened() : toggled()

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 16
        spacing: 12

        // icon circle; its own toggle target when the tile is split
        Clickable {
            id: iconButton
            implicitWidth: 40
            implicitHeight: 40
            enabled: tile.split
            cursorShape: Qt.PointingHandCursor
            pressedRadius: Motion.shapeSmall
            restRadius: tile.on ? Motion.shapeMedium : 20
            color: tile.on ? Colors.on_primary : Colors.secondary_container
            contentColor: tile.on ? Colors.primary : Colors.on_secondary_container
            onClicked: tile.toggled()

            Icon {
                anchors.centerIn: parent
                name: tile.icon
                size: 20
                filled: tile.on
                color: iconButton.contentColor
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 0
            StyledText {
                Layout.fillWidth: true
                role: "titleSmall"
                color: tile.contentColor
                elide: Text.ElideRight
                text: tile.title
            }
            StyledText {
                Layout.fillWidth: true
                role: "bodySmall"
                color: tile.on ? Colors.on_primary : Colors.on_surface_variant
                opacity: tile.on ? 0.85 : 1
                elide: Text.ElideRight
                text: tile.subtitle
            }
        }

        Icon {
            visible: tile.split
            name: "expand_more"
            size: 20
            rotation: tile.drawerOpen ? 180 : 0
            color: tile.contentColor
            Behavior on rotation { Spring {} }
        }
    }
}
