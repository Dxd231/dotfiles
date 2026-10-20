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

    // history cards pop in on a stagger driven from the center (1 = in place); popups ignore it
    property real appearTarget: 1
    property real appear: appearTarget
    Behavior on appear { Spring { speed: "default" } }
    // popups arrive squashed and wobble flat as they land
    property real pop: shown && !closing ? 1 : 0
    Behavior on pop { enabled: card.slideIn; Spring { speed: "default" } }
    property real shakeX: 0

    // the same app always gets the same shape; critical ones are the soft burst in error colours
    readonly property int avatarShape: {
        if (critical)
            return 0;
        let h = 0;
        for (let i = 0; i < appName.length; i++)
            h = (h * 31 + appName.charCodeAt(i)) >>> 0;
        return [1, 4, 5, 2, 0][h % 5];
    }

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
    signal actionInvoked(var action)
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

    Component.onCompleted: {
        if (slideIn)
            Qt.callLater(() => card.shown = true);
        if (slideIn && critical)
            shakeDelay.start();
    }
    Timer {
        id: shakeDelay
        interval: 380
        onTriggered: shake.start()
    }
    SequentialAnimation {
        id: shake
        NumberAnimation { target: card; property: "shakeX"; to: 9; duration: 55 }
        NumberAnimation { target: card; property: "shakeX"; to: -9; duration: 90 }
        NumberAnimation { target: card; property: "shakeX"; to: 6; duration: 80 }
        NumberAnimation { target: card; property: "shakeX"; to: -6; duration: 70 }
        NumberAnimation { target: card; property: "shakeX"; to: 3; duration: 60 }
        NumberAnimation { target: card; property: "shakeX"; to: 0; duration: 60 }
    }
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
    transform: [
        Translate {
            x: card.closing ? -(card.width + 32) : card.shown ? 0 : -(card.width + 32)
            Behavior on x {
                enabled: card.slideIn
                Spring { speed: "default" }
            }
        },
        Translate { x: card.shakeX },
        Scale {
            origin.x: 0
            origin.y: card.height / 2
            xScale: card.slideIn ? 0.86 + 0.14 * card.pop : 1
            yScale: xScale
        }
    ]

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
        // popups start as a bubble and settle into the card shape as they land
        readonly property real outerRadius: card.isPopup && !card.shown ? Math.min(height / 2, 40) : (pressed ? Motion.shapeLarge : Motion.shapeLargeIncreased)
        topLeftRadius: card.isPopup || card.first ? outerRadius : radius
        topRightRadius: topLeftRadius
        bottomLeftRadius: card.isPopup || card.last ? outerRadius : radius
        bottomRightRadius: bottomLeftRadius
        Behavior on topLeftRadius { Spring { speed: "default" } }
        Behavior on topRightRadius { Spring { speed: "default" } }
        Behavior on bottomLeftRadius { Spring { speed: "default" } }
        Behavior on bottomRightRadius { Spring { speed: "default" } }
        opacity: Math.max(0, Math.min(1, card.appear * 1.6))
        scale: 0.9 + 0.1 * card.appear
        transform: Translate { y: (1 - card.appear) * 18 }
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

            // avatar: a turning shape per app, with the app icon (or its initial) on top; it only turns
            // while the card is a popup or hovered, so a long history stays still
            ShapeBadge {
                Layout.alignment: Qt.AlignTop
                Layout.preferredWidth: 40
                Layout.preferredHeight: 40
                shapeRest: card.avatarShape
                shapeActive: card.avatarShape
                spinning: card.isPopup || card.hovered
                color: card.critical ? Colors.error_container : Colors.primary_container

                StyledText {
                    anchors.centerIn: parent
                    visible: iconImage.status !== Image.Ready
                    role: "titleMedium"
                    color: card.critical ? Colors.on_error_container : Colors.on_primary_container
                    text: card.appName.length > 0 ? card.appName.charAt(0).toUpperCase() : "?"
                }
                Image {
                    id: iconImage
                    anchors.centerIn: parent
                    width: 28
                    height: 28
                    visible: status === Image.Ready
                    source: card.iconSource
                    sourceSize: Qt.size(56, 56)
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
                                card.actionInvoked(modelData);
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
