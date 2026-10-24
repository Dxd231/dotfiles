import QtQuick
import qs

// Text set in an M3 type-scale role, e.g. `StyledText { role: "titleMedium"; emphasized: true }`.
Text {
    id: styled

    property string role: "bodyMedium"
    property bool emphasized: false
    // Zen Maru Gothic, for text that is often Japanese (track titles, artists, lyrics)
    property bool jp: false
    // fast | default | slow, for the colour fade
    property string colorSpeed: "fast"

    color: Colors.on_surface
    font.family: jp ? Typography.familyJp : Typography.family
    font.pixelSize: Typography.size(role)
    font.weight: Typography.weight(role, emphasized)
    font.letterSpacing: Typography.tracking(role, emphasized)
    lineHeightMode: wrapMode === Text.NoWrap ? Text.ProportionalHeight : Text.FixedHeight
    lineHeight: wrapMode === Text.NoWrap ? 1 : Typography.lineHeight(role)
    verticalAlignment: Text.AlignVCenter

    property bool fadeColor: true
    Behavior on color { enabled: styled.fadeColor; ColorFade { speed: styled.colorSpeed } }
}
