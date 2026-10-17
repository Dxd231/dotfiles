import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Metric card for the system status popup: icon tile, title/subtitle, big value,
// progress indicator and a row of detail stats ([label, value, severity]).
Rectangle {
    id: card
    property string icon
    property string title
    property string subtitle
    property real percent
    property int level
    property var details: []
    property var severityColors: (lvl, normal) => normal
    readonly property var tone: severityColors(level, [Colors.secondary_container, Colors.on_secondary_container, Colors.primary])

    Layout.fillWidth: true
    implicitHeight: cardCol.implicitHeight + 32
    radius: Motion.shapeMedium
    color: Colors.surface_container_highest

    ColumnLayout {
        id: cardCol
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 12

        RowLayout {
            spacing: 16
            Rectangle {
                implicitWidth: 40
                implicitHeight: 40
                radius: Motion.shapeMedium
                color: card.tone[0]
                Behavior on color { ColorFade {} }
                Icon { anchors.centerIn: parent; name: card.icon; color: card.tone[1] }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { role: "titleMedium"; text: card.title }
                StyledText {
                    Layout.fillWidth: true
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    text: card.subtitle
                }
            }
            StyledText {
                role: "headlineSmall"
                emphasized: true
                color: card.level ? card.tone[2] : Colors.on_surface
                text: Math.round(card.percent) + "%"
            }
        }

        LinearProgress {
            Layout.fillWidth: true
            thickness: 8
            value: card.percent / 100
            activeColor: card.tone[2]
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 8
            Repeater {
                model: card.details
                delegate: ColumnLayout {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    spacing: 0
                    StyledText { role: "labelMedium"; color: Colors.on_surface_variant; text: parent.modelData[0] }
                    StyledText {
                        role: "titleSmall"
                        text: parent.modelData[1]
                        color: parent.modelData[2] ? card.severityColors(parent.modelData[2])[2] : Colors.on_surface
                    }
                }
            }
        }
    }
}
