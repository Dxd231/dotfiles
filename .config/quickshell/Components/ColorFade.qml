import QtQuick
import qs

// M3 Expressive effects motion for colors.
ColorAnimation {
    property string speed: "fast" // fast | default | slow

    // the expressive effects curves are nearly a step (94% done at 31% of the time), which reads as a
    // flash on colors; ease them in and out over a little longer instead
    duration: (speed === "slow" ? Motion.expressiveSlowEffectsDuration : speed === "default" ? Motion.expressiveDefaultEffectsDuration : Motion.expressiveFastEffectsDuration) + 100
    easing.type: Easing.InOutQuad
}
