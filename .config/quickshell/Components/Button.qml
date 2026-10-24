import QtQuick
import qs

// M3 Expressive common button: sizes xs–xl, round/square, filled/tonal/outlined/text/elevated,
// optional leading icon and toggle behaviour.
Clickable {
    id: button

    property string text
    property string icon
    property string size: "s"        // xs | s | m | l | xl
    property string style: "filled"  // filled | tonal | outlined | text | elevated
    property bool square: false

    // [height, icon, pad, iconGap, squareRadius, pressedRadius, typeRole]
    readonly property var _tokens: ({
        xs: [32, 20, 16, 8, 12, 8, "labelLarge"],
        s: [40, 20, 16, 8, 12, 8, "labelLarge"],
        m: [56, 24, 24, 8, 16, 12, "titleMedium"],
        l: [96, 32, 48, 12, 28, 16, "headlineSmall"],
        xl: [136, 40, 64, 16, 28, 16, "headlineLarge"]
    })
    readonly property var _t: {
        const t = _tokens[size] || _tokens.s;
        return { height: t[0], icon: t[1], pad: style === "text" && size === "s" ? 12 : t[2], gap: t[3], square: t[4], pressed: t[5], role: t[6] };
    }

    color: {
        if (!enabled)
            return style === "text" ? Qt.alpha(Colors.on_surface, 0) : Qt.alpha(Colors.on_surface, Motion.disabledContainer);
        switch (style) {
        case "filled":
            return checkable && !checked ? Colors.surface_container : Colors.primary;
        case "tonal":
            return checkable && checked ? Colors.secondary : Colors.secondary_container;
        case "elevated":
            return checkable && checked ? Colors.primary : Colors.surface_container_low;
        case "outlined": // rendered without a border (design preference): tonal surface fill
            return checkable && checked ? Colors.inverse_surface : Colors.surface_container_highest;
        default: // same hue as the label so fading in and out never passes through black
            return Qt.alpha(Colors.primary, 0);
        }
    }
    contentColor: {
        if (!enabled)
            return Qt.alpha(Colors.on_surface, Motion.disabledContent);
        switch (style) {
        case "filled":
            return checkable && !checked ? Colors.on_surface_variant : Colors.on_primary;
        case "tonal":
            return checkable && checked ? Colors.on_secondary : Colors.on_secondary_container;
        case "elevated":
            return checkable && checked ? Colors.on_primary : Colors.primary;
        case "outlined":
            return checkable && checked ? Colors.inverse_on_surface : Colors.on_surface_variant;
        default:
            return Colors.primary;
        }
    }

    implicitHeight: _t.height
    implicitWidth: Math.max(0, _w)
    property real _w: row.implicitWidth + _t.pad * 2
    Behavior on _w { enabled: button.animate; Spring { speed: "fast" } }

    restRadius: square ? _t.square : height / 2
    pressedRadius: _t.pressed
    checkedRadius: checkable ? (square ? height / 2 : _t.square) : restRadius

    Elevation {
        z: -1
        anchors.fill: parent
        radius: button.radius
        level: button.style === "elevated" && button.enabled ? (button.hovered ? 2 : 1) : 0
    }

    Row {
        id: row
        anchors.centerIn: parent
        spacing: button._t.gap

        Icon {
            id: lead
            // grows in and out when a caller adds or drops the icon
            property real grow: button.icon !== "" ? 1 : 0
            Behavior on grow { enabled: button.animate; Spring { speed: "fast" } }
            property string _last: button.icon
            Connections { target: button; function onIconChanged() { if (button.icon !== "") lead._last = button.icon; } }
            visible: grow > 0.01
            width: button._t.icon * Math.max(0, Math.min(1, grow))
            opacity: Math.max(0, Math.min(1, grow))
            scale: Math.max(0, grow)
            anchors.verticalCenter: parent.verticalCenter
            name: button.icon !== "" ? button.icon : _last
            size: button._t.icon
            color: button.contentColor
            fadeColor: false
        }
        SwapText {
            anchors.verticalCenter: parent.verticalCenter
            value: button.text
            role: button._t.role
            color: button.contentColor
            fadeColor: false
        }
    }
}
