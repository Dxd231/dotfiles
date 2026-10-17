import QtQuick
import qs

// M3 filled text field: 56px, surface-container-highest, floating label, optional leading icon
// and password visibility toggle. Drawn without the bottom active-indicator line (design
// preference); focus shows through the primary label and a focus state layer.
Rectangle {
    id: field

    property alias text: input.text
    property alias input: input
    property string label
    property string leadingIcon
    property bool password: false
    property bool revealed: false
    readonly property bool focused: input.activeFocus
    readonly property bool floated: focused || input.text.length > 0

    signal accepted(string text)
    // user edits only (not programmatic text changes)
    signal edited(string text)

    function forceActiveFocus() { input.forceActiveFocus(); }

    implicitWidth: 240
    implicitHeight: 56
    color: Colors.surface_container_highest
    radius: Motion.shapeLarge

    StateLayer {
        hovered: hover.hovered
        focused: field.focused
        tint: field.focused ? Colors.primary : Colors.on_surface
    }
    HoverHandler {
        id: hover
        cursorShape: Qt.IBeamCursor
    }
    TapHandler { onTapped: input.forceActiveFocus() }

    Icon {
        id: lead
        visible: field.leadingIcon !== ""
        anchors.verticalCenter: parent.verticalCenter
        x: 12
        name: field.leadingIcon
        color: Colors.on_surface_variant
    }

    readonly property real _textX: leadingIcon !== "" ? 52 : 16

    StyledText {
        id: labelText
        x: field._textX
        role: field.floated ? "bodySmall" : "bodyLarge"
        y: field.floated ? 8 : (field.height - height) / 2
        color: field.focused ? Colors.primary : Colors.on_surface_variant
        text: field.label
        Behavior on y { Spring { expressive: false } }
    }

    TextInput {
        id: input
        x: field._textX
        anchors.right: trail.visible ? trail.left : parent.right
        anchors.rightMargin: trail.visible ? 4 : 16
        y: field.label !== "" ? 24 : (field.height - height) / 2
        color: Colors.on_surface
        selectionColor: Colors.primary
        selectedTextColor: Colors.on_primary
        font.family: Typography.family
        font.pixelSize: Typography.size("bodyLarge")
        font.weight: Typography.weight("bodyLarge")
        echoMode: field.password && !field.revealed ? TextInput.Password : TextInput.Normal
        clip: true
        onAccepted: field.accepted(text)
        onTextEdited: field.edited(text)
    }

    IconButton {
        id: trail
        visible: field.password
        anchors.verticalCenter: parent.verticalCenter
        anchors.right: parent.right
        anchors.rightMargin: 4
        icon: field.revealed ? "visibility_off" : "visibility"
        onClicked: field.revealed = !field.revealed
    }
}
