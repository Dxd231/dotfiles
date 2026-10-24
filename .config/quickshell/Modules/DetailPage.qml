import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Full-card detail page for a quick-settings tile (Internet, Bluetooth), Android 16 style: a
// top app bar (back, title + status, radio switch), a scrolling body of sections, an optional
// pinned footer, and a centred empty state while the radio is off.
Item {
    id: page

    property string title
    property string subtitle
    property bool checked: true      // radio on
    property bool busy: false        // scanning
    property string offIcon
    property string offTitle
    property string offText
    // children are the body (sections); `footer` is pinned below it
    default property alias content: body.data
    property alias footer: footerSlot.data

    // fades and slides in from the right when it takes the card over
    property bool shown: true

    signal back()
    signal toggled()

    opacity: shown ? 1 : 0
    visible: opacity > 0
    enabled: shown
    Behavior on opacity { Fade {} }
    transform: Translate {
        x: page.shown ? 0 : 24
        Behavior on x { Spring { speed: "default" } }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // ---- top app bar ----
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: 72
            Layout.leftMargin: 8
            Layout.rightMargin: 20
            spacing: 4

            IconButton {
                icon: "arrow_back"
                onClicked: page.back()
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                SwapText {
                    Layout.fillWidth: true
                    role: "titleLarge"
                    elide: Text.ElideRight
                    value: page.title
                }
                SwapText {
                    Layout.fillWidth: true
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    value: page.subtitle
                }
            }
            LoadingIndicator {
                // opens a slot beside the switch and fades in, rather than popping and shoving the title
                property real on: page.busy && page.checked ? 1 : 0
                Behavior on on { Spring { expressive: false } }
                visible: on > 0.01
                opacity: Math.min(1, on)
                running: visible
                Layout.preferredWidth: 24 * Math.max(0, on)
                Layout.preferredHeight: 24
                scale: 0.5
            }
            Switch {
                checked: page.checked
                onToggled: page.toggled()
            }
        }

        // ---- body / off state ----
        Item {
            Layout.fillWidth: true
            Layout.fillHeight: true

            Flickable {
                id: flick
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                visible: opacity > 0
                opacity: page.checked ? 1 : 0
                Behavior on opacity { Fade {} }
                clip: true
                contentWidth: width
                contentHeight: body.implicitHeight
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                Column {
                    id: body
                    width: flick.width
                    spacing: 16
                    bottomPadding: 16
                    // sections glide to their new place when one above them opens or closes
                    move: Transition { Spring { property: "y"; speed: "default"; expressive: false } }
                }
            }

            ColumnLayout {
                anchors.centerIn: parent
                width: parent.width - 64
                spacing: 12
                visible: opacity > 0
                opacity: page.checked ? 0 : 1
                Behavior on opacity { Fade {} }

                // the radio-off hero: a big turning shape that pops in
                ShapeBadge {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.bottomMargin: 8
                    Layout.preferredWidth: 112
                    Layout.preferredHeight: 112
                    shapeRest: "cookie4"
                    shapeActive: "clover4"
                    active: !page.checked
                    spinning: !page.checked && page.shown
                    badgeScale: page.checked ? 0.6 : 1
                    color: Colors.primary_container
                    Icon {
                        anchors.centerIn: parent
                        name: page.offIcon
                        size: 44
                        color: Colors.on_primary_container
                    }
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    role: "titleMedium"
                    text: page.offTitle
                }
                StyledText {
                    Layout.fillWidth: true
                    horizontalAlignment: Text.AlignHCenter
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    wrapMode: Text.Wrap
                    text: page.offText
                }
                Button {
                    Layout.alignment: Qt.AlignHCenter
                    Layout.topMargin: 8
                    text: "Turn on"
                    onClicked: page.toggled()
                }
            }
        }

        // ---- pinned footer ----
        ColumnLayout {
            id: footerSlot
            Layout.fillWidth: true
            Layout.leftMargin: 16
            Layout.rightMargin: 16
            Layout.bottomMargin: 16 * footerSlot.reveal
            readonly property bool open: page.checked && children.length > 0
            property real reveal: open ? 1 : 0
            Behavior on reveal { Spring { speed: "default"; expressive: false } }
            Layout.preferredHeight: implicitHeight * Math.max(0, Math.min(1, reveal))
            visible: open || reveal > 0.01
            opacity: Math.max(0, Math.min(1, reveal))
            clip: true
        }
    }
}
