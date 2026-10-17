pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications
import qs
import qs.Components

// One notification, used for popups and for the history list.
// History cards stack as an M3 Expressive segmented group (`first` / `last` get the outer
// corners); popups stand alone with level-3 elevation. Optional auto-dismiss (timeoutMs > 0)
// pauses while hovered or expanded.
Item {
    id: card

    property string summary: ""
    property string body: ""
    property string appName: ""
    property string timeText: ""
    property string iconSource: ""
    property string desktopEntry: ""
    property string appIcon: ""
    property string url: ""
    property int urgency: NotificationUrgency.Normal
    property var actions: []
    property int timeoutMs: 0
    property bool slideIn: false
    property bool isPopup: false
    property bool first: true
    property bool last: true

    property bool expanded: false
    property bool closing: false
    property bool shown: !slideIn
    property real remaining: 1
    property bool heightAnimated: false

    readonly property bool critical: urgency === NotificationUrgency.Critical
    readonly property bool hovered: surface.hovered || hover.hovered
    readonly property bool expandable: measure.lineCount > 2
    readonly property var visibleActions: (actions || []).filter(a => a && a.identifier !== "default").slice(0, 3)

    signal activated
    signal closeRequested
    signal expired
    signal dismissFinished

    function triggerClose() {
        if (closing)
            return;
        if (slideIn) {
            closing = true;
            exitTimer.restart();
        } else {
            closeRequested();
        }
    }
    function triggerExpire() {
        if (closing)
            return;
        if (slideIn) {
            closing = true;
            exitTimer.restart();
        } else {
            expired();
        }
    }

    implicitWidth: 360
    implicitHeight: surface.implicitHeight

    Component.onCompleted: if (slideIn) Qt.callLater(() => card.shown = true)
    Timer {
        running: true
        interval: Motion.short4
        onTriggered: card.heightAnimated = true
    }
    Timer {
        id: exitTimer
        interval: Motion.short4
        onTriggered: {
            card.dismissFinished();
            card.closeRequested();
        }
    }

    NumberAnimation on remaining {
        from: 1
        to: 0
        duration: Math.max(1, card.timeoutMs)
        running: card.timeoutMs > 0 && !card.closing && card.shown
        paused: running && (card.hovered || card.expanded)
        onFinished: card.triggerExpire()
    }

    // enter: spring in from the left; exit: accelerate out
    opacity: shown && !closing ? 1 : 0
    Behavior on opacity { Fade { speed: card.closing ? "fast" : "default" } }
    transform: Translate {
        x: card.closing ? -(card.width + 32) : card.shown ? 0 : -(card.width + 32)
        Behavior on x {
            enabled: card.slideIn
            Spring { speed: "default" }
        }
    }

    HoverHandler { id: hover }

    Elevation {
        anchors.fill: surface
        radius: surface.radius
        level: card.isPopup ? (card.hovered ? 4 : 3) : 0
    }

    Clickable {
        id: surface
        width: parent.width
        implicitHeight: content.implicitHeight + 32
        // expand/collapse and action rows grow on a spring (not during the first layout pass,
        // or a new card would spring up to its size while sliding in)
        Behavior on implicitHeight { enabled: card.heightAnimated; Spring { speed: "default" } }
        clip: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        color: card.isPopup ? Colors.surface_container_high : Colors.surface_container_highest
        contentColor: Colors.on_surface
        restRadius: card.isPopup ? Motion.shapeLargeIncreased : Motion.shapeExtraSmall
        pressedRadius: card.isPopup ? Motion.shapeLarge : Motion.shapeExtraSmall
        topLeftRadius: card.isPopup || card.first ? (pressed ? Motion.shapeLarge : Motion.shapeLargeIncreased) : radius
        topRightRadius: topLeftRadius
        bottomLeftRadius: card.isPopup || card.last ? (pressed ? Motion.shapeLarge : Motion.shapeLargeIncreased) : radius
        bottomRightRadius: bottomLeftRadius
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                card.triggerClose();
            else if (!card.closing)
                card.activated();
        }

        // invisible copy used to decide whether the body can expand
        Text {
            id: measure
            visible: false
            width: bodyText.width
            text: card.body
            font: bodyText.font
            wrapMode: Text.Wrap
        }

        RowLayout {
            id: content
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 16

            // avatar: app icon, or the app's initial on a tonal container
            Item {
                Layout.alignment: Qt.AlignTop
                implicitWidth: 40
                implicitHeight: 40
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    visible: iconImage.status !== Image.Ready
                    color: card.critical ? Colors.error_container : Colors.primary_container
                    StyledText {
                        anchors.centerIn: parent
                        role: "titleMedium"
                        color: card.critical ? Colors.on_error_container : Colors.on_primary_container
                        text: card.appName.length > 0 ? card.appName.charAt(0).toUpperCase() : "?"
                    }
                }
                Image {
                    id: iconImage
                    anchors.fill: parent
                    visible: status === Image.Ready
                    source: card.iconSource
                    sourceSize: Qt.size(80, 80)
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 2

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 4
                    StyledText {
                        Layout.fillWidth: true
                        role: "labelMedium"
                        color: card.critical ? Colors.error : Colors.on_surface_variant
                        elide: Text.ElideRight
                        text: card.appName + (card.timeText ? " · " + card.timeText : "")
                    }
                    IconButton {
                        visible: card.expandable
                        size: "xs"
                        icon: "expand_more"
                        iconSize: 20
                        rotation: card.expanded ? 180 : 0
                        Behavior on rotation { Spring {} }
                        onClicked: card.expanded = !card.expanded
                    }
                    IconButton {
                        size: "xs"
                        icon: "close"
                        iconSize: 20
                        opacity: card.hovered ? 1 : 0
                        Behavior on opacity { Fade {} }
                        onClicked: card.triggerClose()
                    }
                }

                StyledText {
                    Layout.fillWidth: true
                    role: "titleSmall"
                    elide: Text.ElideRight
                    text: card.summary
                }

                StyledText {
                    id: bodyText
                    Layout.fillWidth: true
                    visible: card.body !== ""
                    role: "bodyMedium"
                    color: Colors.on_surface_variant
                    wrapMode: Text.Wrap
                    maximumLineCount: card.expanded ? 12 : 2
                    elide: Text.ElideRight
                    text: card.body
                }

                Flow {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: card.visibleActions.length > 0
                    spacing: 8
                    Repeater {
                        model: card.visibleActions
                        delegate: Button {
                            required property var modelData
                            size: "xs"
                            style: "tonal"
                            text: modelData.text
                            onClicked: {
                                modelData.invoke();
                                card.triggerClose();
                            }
                        }
                    }
                }

                LinearProgress {
                    Layout.fillWidth: true
                    Layout.topMargin: 8
                    visible: card.timeoutMs > 0
                    value: card.remaining
                    showStop: false
                    activeColor: card.critical ? Colors.error : Colors.primary
                    animated: false
                }
            }
        }
    }
}
