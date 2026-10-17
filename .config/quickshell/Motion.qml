pragma Singleton
import QtQuick

// Material 3 Expressive motion, shape, state and elevation tokens.
// Values from androidx compose material3 tokens (ExpressiveMotionTokens, StandardMotionTokens,
// ShapeTokens, StateTokens, ElevationTokens) and the M3 easing/duration tables.
QtObject {
    // ---- Springs (Qt SpringAnimation parameters) ----
    // Qt integrates `v += (spring*Δ - damping*v) / mass` every 16 ms, so an M3 spring with
    // stiffness k and damping ratio ζ maps to spring = 0.016·k, damping = 0.016·2ζ√k.
    function springOf(stiffness, ratio) {
        return { spring: 0.016 * stiffness, damping: 0.016 * 2 * ratio * Math.sqrt(stiffness) };
    }
    // Spatial (position, size, shape): expressive schemes overshoot, standard barely do.
    readonly property var springFastSpatial: springOf(800, 0.6)
    readonly property var springDefaultSpatial: springOf(380, 0.8)
    readonly property var springSlowSpatial: springOf(200, 0.8)
    readonly property var springStandardFastSpatial: springOf(1400, 0.9)
    readonly property var springStandardDefaultSpatial: springOf(700, 0.9)
    readonly property var springStandardSlowSpatial: springOf(300, 0.9)

    // ---- Cubic-bezier equivalents of the springs (for timed/sequenced animations) ----
    readonly property var expressiveFastSpatial: [0.42, 1.67, 0.21, 0.90, 1, 1]
    readonly property var expressiveDefaultSpatial: [0.38, 1.21, 0.22, 1.00, 1, 1]
    readonly property var expressiveSlowSpatial: [0.39, 1.29, 0.35, 0.98, 1, 1]

    readonly property var expressiveFastEffects: [0.31, 0.94, 0.34, 1.00, 1, 1]
    readonly property var expressiveDefaultEffects: [0.34, 0.80, 0.34, 1.00, 1, 1]
    readonly property var expressiveSlowEffects: [0.34, 0.88, 0.34, 1.00, 1, 1]

    readonly property var standardFastSpatial: [0.27, 1.06, 0.18, 1.00, 1, 1]
    readonly property var standardDefaultSpatial: [0.27, 1.06, 0.18, 1.00, 1, 1]
    readonly property var standardSlowSpatial: [0.27, 1.06, 0.18, 1.00, 1, 1]

    readonly property int expressiveFastSpatialDuration: 350
    readonly property int expressiveDefaultSpatialDuration: 500
    readonly property int expressiveSlowSpatialDuration: 650

    readonly property int expressiveFastEffectsDuration: 150
    readonly property int expressiveDefaultEffectsDuration: 200
    readonly property int expressiveSlowEffectsDuration: 300

    readonly property int standardFastSpatialDuration: 350
    readonly property int standardDefaultSpatialDuration: 500
    readonly property int standardSlowSpatialDuration: 750

    readonly property int durationFastSpatial: 350
    readonly property int durationDefaultSpatial: 500
    readonly property int durationSlowSpatial: 650
    readonly property int durationFastEffects: 150
    readonly property int durationDefaultEffects: 200
    readonly property int durationSlowEffects: 300

    // ---- Classic M3 easing (exits and non-physical transitions) ----
    readonly property var emphasized: [0.05, 0, 0.133333, 0.06, 0.166666, 0.4, 0.208333, 0.82, 0.25, 1, 1, 1]
    readonly property var emphasizedDecelerate: [0.05, 0.7, 0.1, 1, 1, 1]
    readonly property var emphasizedAccelerate: [0.3, 0, 0.8, 0.15, 1, 1]
    readonly property var standard: [0.2, 0, 0, 1, 1, 1]
    readonly property var standardDecelerate: [0, 0, 0, 1, 1, 1]
    readonly property var standardAccelerate: [0.3, 0, 1, 1, 1, 1]
    readonly property var linear: [0, 0, 1, 1, 1, 1]

    readonly property int short1: 50
    readonly property int short2: 100
    readonly property int short3: 150
    readonly property int short4: 200
    readonly property int medium1: 250
    readonly property int medium2: 300
    readonly property int medium3: 350
    readonly property int medium4: 400
    readonly property int long1: 450
    readonly property int long2: 500
    readonly property int long3: 550
    readonly property int long4: 600
    readonly property int extraLong1: 700
    readonly property int extraLong2: 800
    readonly property int extraLong3: 900
    readonly property int extraLong4: 1000

    // ---- Shape (corner radius) ----
    readonly property int shapeNone: 0
    readonly property int shapeExtraSmall: 4
    readonly property int shapeSmall: 8
    readonly property int shapeMedium: 12
    readonly property int shapeLarge: 16
    readonly property int shapeLargeIncreased: 20
    readonly property int shapeExtraLarge: 28
    readonly property int shapeExtraLargeIncreased: 32
    readonly property int shapeExtraExtraLarge: 48
    readonly property int shapeFull: 9999

    // ---- State layer opacities ----
    readonly property real stateHover: 0.08
    readonly property real stateFocus: 0.10
    readonly property real statePressed: 0.10
    readonly property real stateDragged: 0.16

    // ---- Disabled ----
    readonly property real disabledContent: 0.38
    readonly property real disabledContainer: 0.10

    // ---- Elevation (dp) ----
    readonly property int level0: 0
    readonly property int level1: 1
    readonly property int level2: 3
    readonly property int level3: 6
    readonly property int level4: 8
    readonly property int level5: 12

    // Deprecated: M3 replaced tinted elevation with surface-container roles.
    // Kept so the share picker (which symlinks this file) keeps loading.
    readonly property real elev0: 0.00
    readonly property real elev1: 0.05
    readonly property real elev2: 0.08
    readonly property real elev3: 0.11
    readonly property real elev4: 0.12
    readonly property real elev5: 0.14
    function surfaceColor(baseSurface, tintColor, factor) {
        return Qt.tint(baseSurface, Qt.alpha(tintColor, factor));
    }
}
