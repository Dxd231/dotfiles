import QtQuick
import qs

// M3 Expressive effects motion (opacity, and other non-spatial numbers). Never overshoots.
NumberAnimation {
    property string speed: "fast" // fast | default | slow

    duration: speed === "slow" ? Motion.expressiveSlowEffectsDuration : speed === "default" ? Motion.expressiveDefaultEffectsDuration : Motion.expressiveFastEffectsDuration
    easing.type: Easing.BezierSpline
    easing.bezierCurve: speed === "slow" ? Motion.expressiveSlowEffects : speed === "default" ? Motion.expressiveDefaultEffects : Motion.expressiveFastEffects
}
