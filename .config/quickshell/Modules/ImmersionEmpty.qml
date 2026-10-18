import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// A source with nothing to show yet (or nothing at all): a shape in the source's colour, what it is, what to
// do about it. `actions` is [{ id, icon, text, style }] and `triggered(id)` says which was pressed.
ColumnLayout {
    id: empty

    property string accent: "primary"           // primary | tertiary | secondary
    property string icon: "movie"
    property string title: ""
    property string text: ""
    property var actions: []
    property bool active: false
    signal triggered(string id)

    readonly property color container: accent === "secondary" ? Colors.secondary_container : accent === "tertiary" ? Colors.tertiary_container : Colors.primary_container
    readonly property color onContainer: accent === "secondary" ? Colors.on_secondary_container : accent === "tertiary" ? Colors.on_tertiary_container : Colors.on_primary_container

    spacing: 12

    // everything springs in, one after the other, whenever the state comes on show
    ShapeBadge {
        Layout.alignment: Qt.AlignHCenter
        Layout.preferredWidth: 96
        Layout.preferredHeight: 96
        shapeRest: empty.accent === "secondary" ? 5 : 1
        spinning: empty.active
        color: empty.container
        Icon { anchors.centerIn: parent; size: 40; name: empty.icon; color: empty.onContainer }
        Appear { shown: empty.active; lift: 0; from: 0.55 }
    }
    StyledText {
        Layout.alignment: Qt.AlignHCenter
        role: "titleMedium"
        emphasized: true
        text: empty.title
        Appear { shown: empty.active; delay: 90 }
    }
    StyledText {
        Layout.fillWidth: true
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        role: "bodyMedium"
        color: Colors.on_surface_variant
        text: empty.text
        Appear { shown: empty.active; delay: 150 }
    }
    Repeater {
        model: empty.actions
        delegate: Button {
            id: act
            required property var modelData
            required property int index
            Layout.alignment: Qt.AlignHCenter
            icon: modelData.icon || ""
            style: modelData.style || "tonal"
            text: modelData.text
            Appear { shown: empty.active; delay: 210 + act.index * 70 }
            onClicked: empty.triggered(modelData.id)
        }
    }
}
