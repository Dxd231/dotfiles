pragma Singleton
import QtQuick

// Material 3 Expressive type scale (baseline + emphasized), values from
// androidx compose material3 TypeScaleTokens. Sizes/line heights in px (1dp = 1px at scale 1).
// Google Sans ships the scale's exact weights (400/500/700); Zen Maru Gothic is used for
// Japanese-heavy text (track titles, artists, lyrics).
QtObject {
    id: typography

    readonly property string family: "Google Sans"
    readonly property string familyDisplay: "Google Sans"
    readonly property string familyBrand: "Google Sans"
    readonly property string familyNumbers: "Google Sans"
    readonly property string familyMono: "JetBrains Mono NF"
    readonly property string familyJp: "Zen Maru Gothic"

    readonly property int weightRegular: boldText ? 500 : 400
    readonly property int weightMedium: boldText ? 700 : 500
    readonly property int weightSemiBold: 600
    readonly property int weightBold: 700

    // role: [size, lineHeight, tracking, weight, emphasizedTracking, emphasizedWeight]
    readonly property var scale: ({
        displayLarge:   [57, 64, -0.2, 400, 0,    500],
        displayMedium:  [45, 52, 0,    400, 0,    500],
        displaySmall:   [36, 44, 0,    400, 0,    500],
        headlineLarge:  [32, 40, 0,    400, 0,    500],
        headlineMedium: [28, 36, 0,    400, 0,    500],
        headlineSmall:  [24, 32, 0,    400, 0,    500],
        titleLarge:     [22, 28, 0,    400, 0,    500],
        titleMedium:    [16, 24, 0.15, 500, 0.15, 700],
        titleSmall:     [14, 20, 0.1,  500, 0.1,  700],
        bodyLarge:      [16, 24, 0.5,  400, 0.15, 500],
        bodyMedium:     [14, 20, 0.25, 400, 0.25, 500],
        bodySmall:      [12, 16, 0.4,  400, 0.4,  500],
        labelLarge:     [14, 20, 0.1,  500, 0.1,  700],
        labelMedium:    [12, 16, 0.5,  500, 0.5,  700],
        labelSmall:     [11, 16, 0.5,  500, 0.5,  700]
    })

    // Heavier rendering of the scale: regular → medium, medium → bold. Nothing renders below 500.
    readonly property bool boldText: true

    function size(role) { return scale[role][0]; }
    function lineHeight(role) { return scale[role][1]; }
    function tracking(role, emphasized) { return scale[role][emphasized ? 4 : 2]; }
    function weight(role, emphasized) {
        const w = scale[role][emphasized ? 5 : 3];
        return boldText ? (w >= 500 ? 700 : 500) : w;
    }

    // Flat size accessors (legacy call sites).
    readonly property int displayLarge: 57
    readonly property int displayMedium: 45
    readonly property int displaySmall: 36
    readonly property int headlineLarge: 32
    readonly property int headlineMedium: 28
    readonly property int headlineSmall: 24
    readonly property int titleLarge: 22
    readonly property int titleMedium: 16
    readonly property int titleSmall: 14
    readonly property int bodyLarge: 16
    readonly property int bodyMedium: 14
    readonly property int bodySmall: 12
    readonly property int labelLarge: 14
    readonly property int labelMedium: 12
    readonly property int labelSmall: 11
    readonly property int labelExtraSmall: 11

    readonly property real trackingTight: -0.2
    readonly property real trackingDisplay: -0.2
    readonly property real trackingHeadline: 0
    readonly property real trackingTitle: 0
    readonly property real trackingNormal: 0
    readonly property real trackingLabel: 0.1
    readonly property real trackingWide: 0.5
}
