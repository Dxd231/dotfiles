import QtQuick
import qs
import qs.Components

// XS (32px) bar item following M3 Expressive toggle-button shape rules:
// full pill at rest, 8px while pressed, 12px square while selected (its popup is open).
Clickable {
    id: chip

    property bool danger: false // selected state uses the error container (power)
    property int horizontalPadding: 12

    implicitHeight: 32
    height: 32
    restRadius: 16
    pressedRadius: Motion.shapeSmall
    checkedRadius: Motion.shapeMedium
    checkable: true
    color: checked ? (danger ? Colors.error_container : Colors.secondary_container) : Colors.surface_container_high
    contentColor: checked ? (danger ? Colors.on_error_container : Colors.on_secondary_container) : Colors.on_surface
}
