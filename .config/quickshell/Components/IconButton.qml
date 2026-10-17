import QtQuick
import qs

// M3 Expressive icon button: sizes xs–xl, narrow/default/wide widths, round/square shapes,
// standard/filled/tonal/outlined styles, optional toggle (round ↔ square when selected).
Clickable {
    id: button

    property string icon
    property string size: "s"          // xs | s | m | l | xl
    property string widthMode: "default" // narrow | default | wide
    property string style: "standard"   // standard | filled | tonal | outlined
    property bool square: false
    // override the token icon size where a denser layout needs it
    property real iconSize: _t.icon
    // M3: unselected toggles use the outlined glyph, everything else filled
    property bool iconFilled: !checkable || checked

    // [height, icon, narrowPad, defaultPad, widePad, squareRadius, pressedRadius]
    readonly property var _tokens: ({
        xs: [32, 20, 4, 6, 10, 12, 8],
        s: [40, 24, 4, 8, 14, 12, 8],
        m: [56, 24, 12, 16, 24, 16, 12],
        l: [96, 32, 16, 32, 48, 28, 16],
        xl: [136, 40, 32, 48, 72, 28, 16]
    })
    readonly property var _t: {
        const t = _tokens[size] || _tokens.s;
        return { height: t[0], icon: t[1], pad: widthMode === "narrow" ? t[2] : widthMode === "wide" ? t[4] : t[3], square: t[5], pressed: t[6] };
    }

    readonly property color _container: {
        if (!enabled)
            return style === "standard" ? "transparent" : Qt.alpha(Colors.on_surface, Motion.disabledContainer);
        switch (style) {
        case "filled":
            return checkable && !checked ? Colors.surface_container : Colors.primary;
        case "tonal":
            return checkable && checked ? Colors.secondary : Colors.secondary_container;
        case "outlined": // rendered without a border (design preference): tonal surface fill
            return checkable && checked ? Colors.inverse_surface : Colors.surface_container_highest;
        default:
            return "transparent";
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
        case "outlined":
            return checkable && checked ? Colors.inverse_on_surface : Colors.on_surface_variant;
        default:
            return checkable && checked ? Colors.primary : Colors.on_surface_variant;
        }
    }

    implicitHeight: _t.height
    implicitWidth: _t.icon + _t.pad * 2
    color: _container

    restRadius: square ? _t.square : height / 2
    pressedRadius: _t.pressed
    checkedRadius: checkable ? (square ? height / 2 : _t.square) : restRadius

    Icon {
        anchors.centerIn: parent
        name: button.icon
        size: button.iconSize
        filled: button.iconFilled
        color: button.contentColor
        Behavior on color { ColorFade {} }
    }
}
