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
                StyledText {
                    Layout.fillWidth: true
                    role: "titleLarge"
                    elide: Text.ElideRight
                    text: page.title
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    text: page.subtitle
                }
            }
            LoadingIndicator {
                visible: page.busy && page.checked
                running: visible
                Layout.preferredWidth: 24
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
                    shapeRest: 1
                    shapeActive: 4
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
            Layout.bottomMargin: 16
            visible: page.checked && children.length > 0
        }
    }
}
