import QtQuick
import qs

// M3 Expressive spatial spring (position, size, corner radius, scale).
// Retains velocity when retargeted mid-flight, unlike a timed easing curve.
SpringAnimation {
    property string speed: "fast" // fast | default | slow
    property bool expressive: true

    readonly property var _params: expressive
        ? (speed === "slow" ? Motion.springSlowSpatial : speed === "default" ? Motion.springDefaultSpatial : Motion.springFastSpatial)
        : (speed === "slow" ? Motion.springStandardSlowSpatial : speed === "default" ? Motion.springStandardDefaultSpatial : Motion.springStandardFastSpatial)

    spring: _params.spring
    damping: _params.damping
    epsilon: 0.005
}
