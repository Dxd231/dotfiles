import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Single-item segmented row for empty / off states, with an optional action button.
SegmentedItem {
    id: row

    property string icon
    property string title
    property string actionText
    signal action()

    first: true
    last: true
    Layout.fillWidth: true
    implicitHeight: 64

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 16
        anchors.rightMargin: 16
        spacing: 16
        Icon { name: row.icon; color: Colors.on_surface_variant }
        StyledText { Layout.fillWidth: true; role: "bodyLarge"; text: row.title; elide: Text.ElideRight }
        Button {
            visible: row.actionText !== ""
            size: "xs"
            text: row.actionText
            onClicked: row.action()
        }
    }
}
