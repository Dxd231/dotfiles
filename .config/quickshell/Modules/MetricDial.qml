import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// One system metric: a shape badge and title, a wavy dial around the rolling percentage (calm when
// idle, rippling as the load climbs, flashing on a severity change) and a few tinted detail pills.
Rectangle {
    id: card

    property string icon
    property string title
    property string subtitle
    property real percent
    property int level                    // 0 normal, 1 warning, 2 critical
    property int badgeShape: 1
    property bool waving: false
    property var details: []              // [label, value, severity]
    property var severityColors: (lvl, normal) => normal
    readonly property var tone: severityColors(level, [Colors.secondary_container, Colors.on_secondary_container, Colors.primary])

    // wave height follows the load; a severity change adds a spring kick on top
    property real kick: 0
    property bool kickSpring: true
    Behavior on kick {
        enabled: card.kickSpring
        SpringAnimation { spring: 3; damping: 0.16; epsilon: 0.01 }
    }
    onLevelChanged: {
        kickSpring = false;
        kick = 7;
        kickSpring = true;
        kick = 0;
    }
    property real baseAmp: 1.5 + 4.5 * Math.max(0, Math.min(1, percent / 100))
    Behavior on baseAmp { SpringAnimation { spring: 2.4; damping: 0.3; epsilon: 0.01 } }

    Layout.fillWidth: true
    implicitHeight: col.implicitHeight + 32
    radius: Motion.shapeLarge
    color: Colors.surface_container_highest

    ColumnLayout {
        id: col
        x: 16
        y: 16
        width: parent.width - 32
        spacing: 12

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Item {
                implicitWidth: 44
                implicitHeight: 44
                MorphShape {
                    anchors.fill: parent
                    shape: card.badgeShape
                    fromShape: card.badgeShape
                    color: card.tone[0]
                    Behavior on color { ColorFade {} }
                }
                Icon { anchors.centerIn: parent; name: card.icon; size: 22; color: card.tone[1] }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { role: "titleMedium"; emphasized: true; text: card.title }
                StyledText {
                    Layout.fillWidth: true
                    role: "bodySmall"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    text: card.subtitle
                }
            }
        }

        // ---- the dial ----
        Item {
            Layout.alignment: Qt.AlignHCenter
            implicitWidth: 140
            implicitHeight: 140

            WavyRing {
                anchors.fill: parent
                thickness: 8
                amplitude: card.baseAmp + card.kick
                waves: 14
                waving: card.waving
                value: card.percent / 100
                activeColor: card.tone[2]
                trackColor: card.level >= 2 ? Colors.error_container : Colors.secondary_container
                Behavior on activeColor { ColorFade {} }
            }
            Row {
                anchors.centerIn: parent
                spacing: 2
                RollingDigits {
                    anchors.verticalCenter: parent.verticalCenter
                    text: String(Math.round(card.percent))
                    pixelSize: 38
                    color: card.level ? card.tone[2] : Colors.on_surface
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.verticalCenterOffset: 6
                    role: "titleMedium"
                    emphasized: true
                    color: Colors.on_surface_variant
                    text: "%"
                }
            }
        }

        // ---- details ----
        Flow {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: card.details
                delegate: Rectangle {
                    required property var modelData
                    readonly property int sev: modelData[2] || 0
                    height: 30
                    width: pillRow.implicitWidth + 24
                    radius: height / 2
                    color: sev ? card.severityColors(sev)[0] : Colors.surface_container_high
                    Behavior on color { ColorFade {} }
                    Row {
                        id: pillRow
                        anchors.centerIn: parent
                        spacing: 6
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "labelMedium"
                            color: sev ? card.severityColors(sev)[1] : Colors.on_surface_variant
                            text: modelData[0]
                        }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "labelLarge"
                            emphasized: true
                            color: sev ? card.severityColors(sev)[1] : Colors.on_surface
                            text: modelData[1]
                        }
                    }
                }
            }
        }
    }
}
