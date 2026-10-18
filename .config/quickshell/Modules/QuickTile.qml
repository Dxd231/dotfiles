import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// M3 Expressive quick-settings tile (Android 16 style): a pill when off that morphs to a
// rounded square when on. With `split`, the icon circle toggles and the rest of the tile
// opens a detail page (shown by a trailing chevron).
Clickable {
    id: tile

    property string title
    property string subtitle
    property string icon
    property bool on: false
    property bool split: false
    // the shape its icon badge morphs to while on; spins only while the center is open
    property int shapeOn: 4
    property bool live: false
    // entrance (driven by the card's stagger) and a swell on every toggle
    property real appear: 1
    Behavior on appear { Spring { speed: "default" } }
    property real swell: 1

    signal toggled()
    signal opened()

    implicitHeight: 64
    restRadius: on ? Motion.shapeExtraLarge : height / 2
    pressedRadius: Motion.shapeMedium
    color: on ? Colors.primary : Colors.surface_container_highest
    contentColor: on ? Colors.on_primary : Colors.on_surface
    onClicked: split ? opened() : toggled()

    // pops in on the stagger; presses squish it and the fast spring throws it back
    property real press: pressed ? 0.95 : 1
    Behavior on press { Spring { speed: "fast" } }
    scale: press * (0.8 + 0.2 * appear)
    opacity: Math.max(0, Math.min(1, appear * 1.6))
    transform: Translate { y: (1 - tile.appear) * 16 }

    onOnChanged: swellKick.restart()
    SequentialAnimation {
        id: swellKick
        NumberAnimation { target: tile; property: "swell"; to: 1.25; duration: 1 }
        PauseAnimation { duration: 90 }
        NumberAnimation { target: tile; property: "swell"; to: 1; duration: 1 }
    }

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
            color: "transparent"
            contentColor: tile.on ? Colors.primary : Colors.on_secondary_container
            onClicked: tile.toggled()

            // a cookie that morphs to the tile's own shape, and turns, while the tile is on
            ShapeBadge {
                anchors.fill: parent
                shapeRest: 1
                shapeActive: tile.shapeOn
                active: tile.on
                spinning: tile.on && tile.live
                badgeScale: tile.swell
                color: tile.on ? Colors.on_primary : Colors.secondary_container
            }

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
            name: "chevron_right"
            size: 20
            color: tile.contentColor
        }
    }
}
