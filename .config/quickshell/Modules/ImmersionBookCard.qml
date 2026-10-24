pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Widgets
import qs
import qs.Components

// What you are reading, for a book (ttu) and for manga (Kavita) alike: the cover beside the title and a few
// facts, the progress with what is left, today's numbers, the last days spent on it, and a way back into
// the app. `accent` picks the colours (tertiary for books, secondary for manga).
ColumnLayout {
    id: card

    property string accent: "tertiary"
    property string icon: "auto_stories"
    property string cover: ""
    property string title: ""
    property string subtitle: ""
    property string status: ""                  // "Last read · Yesterday", shown while nothing is being read
    property bool live: false
    property string liveText: "Reading now"
    property var chips: []                      // [{ icon, text }]
    property var progress: null                 // 0..1, or null when unknown
    property string progressText: ""
    property string eta: ""
    property var tiles: []                      // [{ v, l }]
    property var recent: []                     // [{ label, detail }], newest first
    property string hint: ""
    property string actionIcon: ""
    property string actionText: ""
    property bool active: false                 // the panel is open: shapes may turn
    // a colour taken from the cover (transparent = none): the card then tints itself with it
    property color seed: "transparent"
    property bool shown: true                   // this card is the one on show: its parts spring in again
    signal action()

    readonly property bool seeded: seed.a > 0
    readonly property color main: seeded ? seed : accent === "secondary" ? Colors.secondary : Colors.tertiary
    readonly property color textOnMain: seeded ? (seed.hslLightness > 0.55 ? "#1b1b1f" : "#ffffff") : accent === "secondary" ? Colors.on_secondary : Colors.on_tertiary
    readonly property bool dark: Colors.surface.hslLightness < 0.5
    readonly property color container: seeded ? Qt.hsla(seed.hslHue, Math.min(0.5, seed.hslSaturation), dark ? 0.25 : 0.88, 1) : accent === "secondary" ? Colors.secondary_container : Colors.tertiary_container
    // text on the container: near-black or near-white by the container's own lightness, so it always reads
    readonly property color textOnContainer: seeded ? (container.hslLightness > 0.55 ? "#1b1b1f" : "#f6f2ff") : accent === "secondary" ? Colors.on_secondary_container : Colors.on_tertiary_container
    Behavior on seed { ColorFade {} }

    spacing: 12

    // ---- cover and title ----
    RowLayout {
        Layout.fillWidth: true
        Layout.minimumHeight: 240
        Layout.preferredHeight: 240
        Layout.maximumHeight: 240
        spacing: 14

        ClippingRectangle {
            id: coverBox
            Layout.preferredWidth: 170
            Layout.fillHeight: true
            // the shape loosens while a page is being read
            radius: card.live ? Motion.shapeLarge : 36
            Behavior on radius { Spring {} }
            color: card.container
            readonly property bool has: card.cover !== ""
            Appear { shown: card.shown; lift: 0; from: 0.9 }

            Image {
                anchors.fill: parent
                source: coverBox.has ? "file://" + card.cover : ""
                sourceSize.width: 400
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                opacity: status === Image.Ready ? 1 : 0
                Behavior on opacity { Fade {} }
            }
            ShapeBadge {
                anchors.centerIn: parent
                width: 84
                height: 84
                shapeRest: card.accent === "secondary" ? "cookie4" : "cookie9"
                shapeActive: "sunny"
                active: card.live
                spinning: card.live && card.active
                color: card.main
                opacity: coverBox.has ? 0 : 1
                Behavior on opacity { Fade {} }
                Icon { anchors.centerIn: parent; size: 36; name: card.icon; color: card.textOnMain }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 4
            StyledText {
                Layout.fillWidth: true
                jp: true
                role: "titleMedium"
                emphasized: true
                wrapMode: Text.WordWrap
                maximumLineCount: 5
                elide: Text.ElideRight
                text: card.title
            }
            Collapse {
                open: card.subtitle !== ""
                Layout.fillWidth: true
                StyledText {
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    wrapMode: Text.WordWrap
                    text: card.subtitle
                }
            }
            Flow {
                Layout.fillWidth: true
                Layout.topMargin: 4
                spacing: 6
                // chips slide over when one comes or goes
                move: Transition { Spring { properties: "x,y"; speed: "default" } }
                // a count, not the list: a value changing must not rebuild (and replay) the chips
                Repeater {
                    model: card.chips.length
                    delegate: ImmersionChip {
                        required property int index
                        readonly property var d: card.chips[index] || ({})
                        icon: d.icon || ""
                        text: d.text || ""
                    }
                }
            }
            Item { Layout.fillHeight: true }
            // being read right now, or when it last was
            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 28
                Rectangle {
                    height: 28
                    width: liveLabel.implicitWidth + 24
                    radius: 14
                    color: card.main
                    scale: card.live ? 1 : 0.6
                    opacity: card.live ? 1 : 0
                    transformOrigin: Item.BottomLeft
                    Behavior on scale { Spring { speed: "fast" } }
                    Behavior on opacity { Fade {} }
                    StyledText {
                        id: liveLabel
                        anchors.centerIn: parent
                        role: "labelLarge"
                        emphasized: true
                        color: card.textOnMain
                        text: card.liveText
                    }
                }
                StyledText {
                    anchors.verticalCenter: parent.verticalCenter
                    role: "labelLarge"
                    color: Colors.on_surface_variant
                    opacity: card.live ? 0 : 1
                    Behavior on opacity { Fade {} }
                    text: card.status
                }
            }
        }
    }

    // ---- progress, and what is left ----
    Collapse {
        open: card.progress !== null && card.progress !== undefined
        Layout.fillWidth: true
        ColumnLayout {
            spacing: 6
            WavyProgress {
                Layout.fillWidth: true
                thickness: 8
                value: card.progress ? card.progress : 0
                waving: card.live && card.active
                activeColor: card.main
                trackColor: Colors.surface_container_highest
            }
            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 4
                Layout.rightMargin: 4
                StyledText {
                    Layout.fillWidth: true
                    role: "labelMedium"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    text: card.progressText
                }
                Collapse {
                    open: card.eta !== ""
                    StyledText {
                        role: "labelMedium"
                        emphasized: true
                        color: card.main
                        text: card.eta
                    }
                }
            }
        }
    }

    // ---- today ----
    RowLayout {
        Layout.fillWidth: true
        spacing: 3
        Repeater {
            model: card.tiles.length
            delegate: Rectangle {
                id: tile
                required property int index
                readonly property var d: card.tiles[index] || ({ v: "", l: "" })
                Layout.fillWidth: true
                Layout.preferredWidth: 1
                Layout.preferredHeight: 64
                // a bento group: round at the ends, tight where the tiles meet
                topLeftRadius: tile.index === 0 ? 20 : 4
                bottomLeftRadius: topLeftRadius
                topRightRadius: tile.index === card.tiles.length - 1 ? 20 : 4
                bottomRightRadius: topRightRadius
                color: Colors.surface_container
                Appear { shown: card.shown; delay: 90 + tile.index * 55 }
                ColumnLayout {
                    anchors.centerIn: parent
                    spacing: 0
                    RollingDigits {
                        Layout.alignment: Qt.AlignHCenter
                        pixelSize: 16
                        weight: Font.Bold
                        text: tile.d.v
                    }
                    StyledText { Layout.alignment: Qt.AlignHCenter; role: "labelSmall"; color: Colors.on_surface_variant; text: tile.d.l }
                }
            }
        }
    }

    // ---- the last days spent on it: as many rows as fit ----
    Item {
        id: days
        Layout.fillWidth: true
        Layout.fillHeight: true
        Layout.minimumHeight: 0
        clip: true
        readonly property int fit: Math.max(0, Math.floor((height - 24) / 32))
        // always in the layout (it is what soaks up the free height); only its contents come and go
        readonly property bool shown: card.recent.length > 0 && fit > 0
        StyledText {
            x: 4
            opacity: days.shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            role: "labelMedium"
            color: Colors.on_surface_variant
            text: "Recent days"
        }
        Column {
            y: 24
            width: parent.width
            spacing: 2
            opacity: days.shown ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade {} }
            Repeater {
                model: Math.min(days.fit, card.recent.length)
                delegate: Rectangle {
                    id: dayRow
                    required property int index
                    readonly property var d: card.recent[index] || ({ label: "", detail: "" })
                    width: parent.width
                    height: 30
                    radius: Motion.shapeMedium
                    color: Colors.surface_container
                    Appear { shown: card.shown; delay: 160 + dayRow.index * 55; lift: 10 }
                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 8
                        StyledText {
                            Layout.preferredWidth: 92
                            role: "labelLarge"
                            emphasized: true
                            text: dayRow.d.label
                        }
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            elide: Text.ElideRight
                            text: dayRow.d.detail
                        }
                    }
                }
            }
        }
    }

    // ---- why a number is what it is ----
    Collapse {
        open: card.hint !== ""
        Layout.fillWidth: true
        Rectangle {
            implicitHeight: hintText.implicitHeight + 24
            radius: Motion.shapeMedium
            color: Colors.surface_container
            StyledText {
                id: hintText
                anchors.fill: parent
                anchors.margins: 12
                role: "bodySmall"
                color: Colors.on_surface_variant
                wrapMode: Text.WordWrap
                text: card.hint
            }
        }
    }

    Collapse {
        open: card.actionText !== ""
        Layout.fillWidth: true
        Button {
            implicitHeight: 44
            icon: card.actionIcon
            style: "tonal"
            color: card.container
            contentColor: card.textOnContainer
            text: card.actionText
            onClicked: card.action()
        }
    }
}
