import QtQuick
import QtQuick.Effects

// SDDM greeter: the shell's lock screen (GreeterView) over the blurred wallpaper.
// state/bg.jpg and state/Colors.qml are written by sync.sh whenever the matugen palette changes.
Rectangle {
    id: root
    width: 1920
    height: 1080
    color: Colors.background

    property real blurLevel: 0
    Component.onCompleted: blurLevel = 1
    Behavior on blurLevel { NumberAnimation { duration: 700; easing.type: Easing.OutCubic } }

    Image {
        id: wallpaper
        anchors.fill: parent
        source: "state/bg.jpg"
        fillMode: Image.PreserveAspectCrop
        asynchronous: true
        visible: false
    }
    MultiEffect {
        anchors.fill: parent
        source: wallpaper
        visible: wallpaper.status === Image.Ready
        blurEnabled: true
        blur: 1
        blurMax: 64
        autoPaddingEnabled: false
        opacity: root.blurLevel
    }
    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(Colors.surface, 0.55)
    }

    GreeterView {
        anchors.fill: parent
    }
}
