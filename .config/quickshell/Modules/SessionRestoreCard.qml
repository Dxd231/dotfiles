pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// "Restore last session?" card, bottom-right. While restoring, each row ticks as its window lands.
Scope {
    id: root

    readonly property bool shown: Session.offering || Session.restoring
    readonly property int maxRows: 6

    function ago(ms) {
        const m = Math.round((Date.now() - ms) / 60000);
        if (m < 1)
            return "just now";
        if (m < 60)
            return m + " min ago";
        const h = Math.round(m / 60);
        if (h < 24)
            return h + (h === 1 ? " hour ago" : " hours ago");
        return Math.round(h / 24) + " days ago";
    }

    PanelWindow {
        WlrLayershell.namespace: "quickshell:session_restore"
        WlrLayershell.layer: WlrLayer.Overlay
        anchors.bottom: true
        anchors.right: true
        margins.bottom: 24
        margins.right: 24
        exclusiveZone: 0
        visible: root.shown || card.opacity > 0
        implicitWidth: card.width + 16
        implicitHeight: card.height + 16
        color: "transparent"

        Elevation {
            anchors.fill: card
            radius: card.radius
            level: 3
            opacity: card.opacity
            scale: card.scale
            transform: Translate { y: card.rise }
        }

        Rectangle {
            id: card
            x: 8
            y: 8
            width: 340
            height: col.implicitHeight + 32
            radius: Motion.shapeExtraLarge
            color: Colors.surface_container_high
            property real rise: root.shown ? 0 : 28
            Behavior on rise { Spring { speed: "default" } }
            Behavior on height { Spring { speed: "default" } }
            opacity: root.shown ? 1 : 0
            scale: root.shown ? 1 : 0.9
            transformOrigin: Item.BottomRight
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            transform: Translate { y: card.rise }

            ColumnLayout {
                id: col
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 16
                spacing: 12

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 12
                    ShapeBadge {
                        Layout.preferredWidth: 44
                        Layout.preferredHeight: 44
                        shapeRest: 1
                        shapeActive: 4
                        active: Session.restoring
                        spinning: root.shown
                        color: Colors.primary
                        Icon {
                            anchors.centerIn: parent
                            name: "history"
                            size: 24
                            color: Colors.on_primary
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            Layout.fillWidth: true
                            role: "titleMedium"
                            emphasized: true
                            color: Colors.on_surface
                            text: Session.restoring ? "Restoring apps…" : "Restore last session?"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            role: "bodySmall"
                            color: Colors.on_surface_variant
                            text: Session.restoring ? Session.placed + " of " + Session.items.length + " in place" : "Saved " + root.ago(Session.last.savedAt)
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 2
                    Repeater {
                        model: Session.items.slice(0, root.maxRows)
                        delegate: RowLayout {
                            id: row
                            required property var modelData
                            Layout.fillWidth: true
                            spacing: 10
                            Icon {
                                name: row.modelData.done ? "check_circle" : "radio_button_unchecked"
                                size: 18
                                color: row.modelData.done ? Colors.primary : Colors.on_surface_variant
                                Behavior on color { ColorFade {} }
                            }
                            StyledText {
                                Layout.fillWidth: true
                                role: "bodyMedium"
                                color: Colors.on_surface
                                elide: Text.ElideRight
                                text: row.modelData.media && row.modelData.media.title
                                    ? row.modelData.media.title.replace(/\.[A-Za-z0-9]{2,4}$/, "")
                                    : row.modelData.name
                            }
                            StyledText {
                                role: "bodySmall"
                                color: Colors.on_surface_variant
                                text: row.modelData.wsName ? row.modelData.wsName.replace(/^special:/, "") + " (special)" : "Workspace " + row.modelData.ws
                            }
                        }
                    }
                    StyledText {
                        visible: Session.items.length > root.maxRows
                        role: "bodySmall"
                        color: Colors.on_surface_variant
                        text: "+" + (Session.items.length - root.maxRows) + " more"
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: 4
                    spacing: 8
                    Item { Layout.fillWidth: true }
                    Button {
                        style: "text"
                        text: Session.restoring ? "Close" : "Not now"
                        onClicked: Session.restoring ? Session._finish() : Session.dismiss()
                    }
                    Button {
                        visible: !Session.restoring
                        icon: "history"
                        text: "Restore"
                        onClicked: Session.restore()
                    }
                }
            }
        }
    }
}
