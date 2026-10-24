import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// One row of a detail-page list (Wi-Fi network, Bluetooth device): a 40px leading circle, two
// lines of text, trailing actions and an optional area that expands below (password entry).
// Rows are segmented: 4px corners between rows, large corners on the outer ends of a group.
Clickable {
    id: row

    property bool first: false
    property bool last: false
    property string icon
    property string badgeIcon
    property bool highlighted: false
    property string title
    property string subtitle
    property bool busy: false
    // children go to the trailing action area; `extra` fills the expanding area below
    default property alias trailing: trailingRow.data
    property alias extra: extraSlot.data

    readonly property color _fg: highlighted ? Colors.on_secondary_container : Colors.on_surface
    readonly property color _fgVariant: highlighted ? Colors.on_secondary_container : Colors.on_surface_variant

    // rows rise in as a wave from top to bottom each time their page opens (delay follows screen y)
    property real appear: 1
    property bool snap: false
    Behavior on appear { enabled: !row.snap; Spring { speed: "default" } }
    opacity: Math.max(0, Math.min(1, appear * 1.6))
    scale: 0.94 + 0.06 * appear
    transform: Translate { y: (1 - row.appear) * 14 }
    // a row that turns up while its page is already open (a scan result) rises in on its own
    Component.onCompleted: if (visible) _enter()
    onVisibleChanged: _enter()
    function _enter() {
        snap = true;
        appear = 0;
        snap = false;
        if (visible) {
            enterDelay.interval = Math.max(0, Math.min(500, (mapToItem(null, 0, 0).y - 100) * 0.45));
            enterDelay.restart();
        } else {
            enterDelay.stop();
        }
    }
    Timer {
        id: enterDelay
        onTriggered: row.appear = 1
    }

    width: parent ? parent.width : 0
    implicitHeight: body.implicitHeight + 24
    Behavior on implicitHeight { Spring { speed: "default" } }
    clip: true

    restRadius: Motion.shapeExtraSmall
    pressedRadius: Motion.shapeMedium
    // the outer corners spring as rows are added, removed or reordered around this one
    property real _top: first ? Motion.shapeLarge : radius
    property real _bottom: last ? Motion.shapeLarge : radius
    Behavior on _top { Spring {} }
    Behavior on _bottom { Spring {} }
    topLeftRadius: Math.max(0, _top)
    topRightRadius: topLeftRadius
    bottomLeftRadius: Math.max(0, _bottom)
    bottomRightRadius: bottomLeftRadius
    color: highlighted ? Colors.secondary_container : Colors.surface_container_highest
    contentColor: _fg

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.leftMargin: 16
        anchors.rightMargin: 8
        anchors.topMargin: 12
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            // connected rows are the sunny shape and turn; the rest are a still cookie
            ShapeBadge {
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                shapeRest: "cookie4"
                shapeActive: "clover4"
                active: row.highlighted
                spinning: row.highlighted && row.visible
                color: row.highlighted ? Colors.primary : Colors.secondary_container

                Icon {
                    anchors.centerIn: parent
                    name: row.icon
                    color: row.highlighted ? Colors.on_primary : Colors.on_secondary_container
                    Icon {
                        opacity: row.badgeIcon !== "" ? 1 : 0
                        scale: row.badgeIcon !== "" ? 1 : 0.3
                        visible: opacity > 0
                        Behavior on opacity { Fade {} }
                        Behavior on scale { Spring { speed: "fast" } }
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        anchors.margins: -3
                        name: row.badgeIcon
                        size: 12
                        color: parent.color
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                SwapText {
                    Layout.fillWidth: true
                    role: "bodyLarge"
                    color: row._fg
                    elide: Text.ElideRight
                    value: row.title
                }
                SwapText {
                    Layout.fillWidth: true
                    role: "bodyMedium"
                    color: row._fgVariant
                    elide: Text.ElideRight
                    value: row.subtitle
                }
            }

            LoadingIndicator {
                property real on: row.busy ? 1 : 0
                Behavior on on { Spring { expressive: false } }
                visible: on > 0.01
                opacity: Math.min(1, on)
                running: visible
                Layout.preferredWidth: 24 * Math.max(0, on)
                Layout.preferredHeight: 24
                scale: 0.5
            }

            RowLayout {
                id: trailingRow
                spacing: 0
            }
        }

        ColumnLayout {
            id: extraSlot
            Layout.fillWidth: true
            Layout.rightMargin: 8
            visible: implicitHeight > 0
        }
    }
}
