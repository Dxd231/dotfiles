pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import QtQuick.Effects

// One "icon  LABEL  extra  value" row with a thin progress track underneath.
ColumnLayout {
    id: bar

    property var theme
    property var settings
    property string icon: ""
    property string label: ""
    property string valueText: ""
    property string extraText: ""
    property real fraction: 0
    property bool interactive: false
    property bool clickable: false

    signal clicked
    signal valueModified(real frac)

    Layout.fillWidth: true
    Layout.maximumHeight: implicitHeight
    Layout.alignment: Qt.AlignTop
    spacing: 6

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Item {
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22

            Image {
                anchors.fill: parent
                source: bar.icon
                sourceSize.width: 22
                sourceSize.height: 22
                fillMode: Image.PreserveAspectFit
                layer.enabled: true
                layer.effect: MultiEffect {
                    colorization: 1.0
                    colorizationColor: bar.theme.primary
                }
            }

            TapHandler {
                enabled: bar.clickable
                onTapped: bar.clicked()
            }
            HoverHandler {
                cursorShape: bar.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
            }
        }

        Text {
            Layout.fillWidth: true
            text: bar.label
            color: bar.theme.on_background
            opacity: 0.8
            font.family: bar.settings.fontdefault
            font.pixelSize: bar.settings.fontsize
            font.bold: true
            elide: Text.ElideRight
        }
        Text {
            visible: bar.extraText !== ""
            text: bar.extraText
            color: Qt.alpha(bar.theme.on_background, 0.75)
            font.family: bar.settings.fontdefault
            font.pixelSize: 13
            font.bold: true
        }
        Text {
            text: bar.valueText
            color: bar.theme.on_background
            font.family: bar.settings.fontdefault
            font.pixelSize: bar.settings.fontsize
            font.bold: true
        }
    }

    Rectangle {
        id: trackRect
        Layout.fillWidth: true
        Layout.preferredHeight: 8
        radius: 4
        color: Qt.alpha(bar.theme.on_background, 0.10)
        clip: true

        Rectangle {
            height: parent.height
            radius: 4
            color: bar.theme.primary
            width: parent.width * Math.min(1, Math.max(0, bar.fraction))
            Behavior on width {
                enabled: !trackMouse.pressed
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }
        }

        MouseArea {
            id: trackMouse
            anchors.fill: parent
            enabled: bar.interactive
            cursorShape: bar.interactive ? Qt.PointingHandCursor : Qt.ArrowCursor
            onPressed: mouse => bar.valueModified(Math.max(0, Math.min(1, mouse.x / width)))
            onPositionChanged: mouse => {
                if (pressed)
                    bar.valueModified(Math.max(0, Math.min(1, mouse.x / width)))
            }
            onWheel: event => {
                bar.valueModified(Math.max(0, Math.min(1, bar.fraction + (event.angleDelta.y > 0 ? 0.05 : -0.05))))
                event.accepted = true
            }
        }
    }
}
