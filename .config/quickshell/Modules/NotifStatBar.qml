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
    property bool clickable: false

    signal clicked

    Layout.fillWidth: true
    Layout.maximumHeight: implicitHeight
    Layout.alignment: Qt.AlignTop
    spacing: 6

    TapHandler {
        enabled: bar.clickable
        onTapped: bar.clicked()
    }
    HoverHandler {
        cursorShape: bar.clickable ? Qt.PointingHandCursor : Qt.ArrowCursor
    }

    RowLayout {
        Layout.fillWidth: true
        spacing: 6

        Image {
            source: bar.icon
            sourceSize.width: 22
            sourceSize.height: 22
            Layout.preferredWidth: 22
            Layout.preferredHeight: 22
            fillMode: Image.PreserveAspectFit
            layer.enabled: true
            layer.effect: MultiEffect {
                colorization: 1.0
                colorizationColor: bar.theme.primary
            }
        }
        Text {
            Layout.fillWidth: true
            text: bar.label
            color: bar.theme.on_background
            opacity: 0.7
            font.family: bar.settings.fontdefault
            font.pixelSize: bar.settings.fontsize
            font.bold: true
        }
        Text {
            visible: bar.extraText !== ""
            text: bar.extraText
            color: Qt.alpha(bar.theme.on_background, 0.75)
            font.family: bar.settings.fontdefault
            font.pixelSize: 11
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
        Layout.fillWidth: true
        Layout.preferredHeight: 5
        radius: 5
        color: Qt.alpha(bar.theme.on_background, 0.15)

        Rectangle {
            height: parent.height
            radius: 5
            color: bar.theme.primary
            width: parent.width * Math.min(1, Math.max(0, bar.fraction))
            Behavior on width {
                NumberAnimation {
                    duration: 300
                    easing.type: Easing.OutCubic
                }
            }
        }
    }
}
