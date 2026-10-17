import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Expandable detail section for quick settings (Wi-Fi, Bluetooth): header with an
// activity indicator and collapse button; height springs open/closed.
Item {
    id: section

    property bool open: false
    property string title
    property bool busy: false
    default property alias content: body.data

    signal close()

    Layout.fillWidth: true
    implicitHeight: open ? col.implicitHeight : 0
    visible: implicitHeight > 0.5
    clip: true
    Behavior on implicitHeight { Spring { speed: "default"; expressive: false } }

    ColumnLayout {
        id: col
        width: parent.width
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: 4
            spacing: 8
            StyledText { Layout.fillWidth: true; role: "titleMedium"; text: section.title }
            LoadingIndicator {
                visible: section.busy && section.open
                running: visible
                Layout.preferredWidth: 24
                Layout.preferredHeight: 24
                scale: 0.5
            }
            IconButton { icon: "expand_less"; onClicked: section.close() }
        }

        ColumnLayout {
            id: body
            Layout.fillWidth: true
            spacing: 2
        }
    }
}
