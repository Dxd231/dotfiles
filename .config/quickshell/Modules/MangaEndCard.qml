import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// Shown at the end of a volume: go on to the next one, or back to the library.
Rectangle {
    id: card

    property var next: null          // { id, title } or null for the last volume
    property string nextCover: ""
    property string seriesTitle: ""
    property bool shown: false
    signal nextVolume()
    signal library()
    signal dismissed()

    implicitWidth: row.implicitWidth + 48
    implicitHeight: row.implicitHeight + 48
    radius: Motion.shapeExtraLarge
    color: Colors.surface_container_high
    opacity: shown ? 1 : 0
    visible: opacity > 0.01
    scale: shown ? 1 : 0.9
    Behavior on opacity { Fade {} }
    Behavior on scale { Spring {} }

    // a click on the card is not a click on the page behind it
    MouseArea { anchors.fill: parent }

    RowLayout {
        id: row
        anchors.centerIn: parent
        spacing: 20

        ClippingRectangle {
            visible: card.next !== null
            Layout.preferredWidth: 96
            Layout.preferredHeight: 136
            radius: Motion.shapeMedium
            color: Colors.surface_container
            Image {
                anchors.fill: parent
                source: card.nextCover
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
            }
        }
        ColumnLayout {
            spacing: 4
            StyledText {
                role: "labelLarge"
                color: Colors.on_surface_variant
                text: card.next ? "Finished. Up next" : "Finished"
            }
            StyledText {
                role: "headlineSmall"
                emphasized: true
                jp: true
                text: card.next ? card.next.title : card.seriesTitle
                Layout.maximumWidth: 320
                elide: Text.ElideRight
            }
            RowLayout {
                Layout.topMargin: 12
                spacing: 8
                Button {
                    visible: card.next !== null
                    text: "Next volume"
                    icon: "skip_next"
                    onClicked: card.nextVolume()
                }
                Button {
                    text: "Library"
                    icon: "grid_view"
                    style: card.next ? "tonal" : "filled"
                    onClicked: card.library()
                }
            }
        }
    }
}
