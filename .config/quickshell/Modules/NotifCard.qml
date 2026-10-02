pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Notifications

// One notification card, used for both the popups and the history list.
//
// - Fixed collapsed height (collapsedHeight). Short notifications never change it.
// - If the body needs more than `collapsedLines` lines, a chevron appears in the footer;
//   clicking it expands the card (up to `expandedLines` lines) and collapses it again.
// - Optional auto-dismiss (timeoutMs > 0) with a thin progress line; pauses while hovered or expanded.
Rectangle {
    id: card

    // ---- inputs ----
    property var theme
    property var settings
    property string summary: ""
    property string body: ""
    property string appName: ""
    property string timeText: ""
    property string iconSource: ""
    property int urgency: NotificationUrgency.Normal
    property var actions: []        // NotificationAction list (popups only)
    property int timeoutMs: 0       // 0 = never auto-close
    property bool slideIn: false    // popups slide in from the left

    // ---- state ----
    property bool expanded: false
    property bool closing: false
    property bool shown: !slideIn
    property real remaining          // 1 -> 0 while the auto-dismiss countdown runs

    readonly property bool hovered: hoverHandler.hovered
    readonly property bool expandable: measurer.lineCount > card.collapsedLines

    // ---- tuning ----
    readonly property int collapsedLines: 2
    readonly property int expandedLines: 12
    readonly property real collapsedHeight: 102
    readonly property real pad: 10

    readonly property color accentColor: {
        if (card.urgency === NotificationUrgency.Critical)
            return card.theme.error;
        if (card.urgency === NotificationUrgency.Low)
            return Qt.alpha(card.theme.on_background, 0.25);
        return Qt.alpha(card.theme.primary, 0.7);
    }

    signal activated
    signal closeRequested

    function toggleExpanded() {
        if (card.expandable)
            card.expanded = !card.expanded;
    }

    // implicitHeight (not height) so it works in both ColumnLayout and ListView.
    implicitHeight: Math.max(card.collapsedHeight, content.implicitHeight + card.pad * 2)
    Behavior on implicitHeight {
        NumberAnimation {
            duration: 180
            easing.type: Easing.OutCirc
        }
    }

    radius: 14
    clip: true
    color: Qt.tint(Qt.alpha(card.theme.background, 1), Qt.alpha(card.theme.on_background, 0.05))
    border.width: 2
    border.color: card.urgency === NotificationUrgency.Critical ? Qt.alpha(card.theme.error, 0.5) : Qt.alpha(card.theme.on_background, 0)

    opacity: (card.closing || !card.shown) ? 0 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: 250
            easing.type: Easing.InCubic
        }
    }
    transform: Translate {
        x: (card.closing || !card.shown) ? -(card.width + 20) : 0
        Behavior on x {
            NumberAnimation {
                duration: 250
                easing.type: Easing.InCubic
            }
        }
    }
    Component.onCompleted: Qt.callLater(() => card.shown = true)

    // auto-dismiss countdown
    NumberAnimation on remaining {
        from: 1
        to: 0
        duration: Math.max(1, card.timeoutMs)
        running: card.timeoutMs > 0 && !card.closing
        paused: card.hovered || card.expanded
        onFinished: card.closeRequested()
    }

    HoverHandler {
        id: hoverHandler
    }

    // whole-card click: left = activated, right = close
    MouseArea {
        anchors.fill: parent
        z: -1
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        cursorShape: Qt.PointingHandCursor
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                card.closeRequested();
            else
                card.activated();
        }
    }

    // urgency accent bar
    Rectangle {
        anchors.left: parent.left
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.leftMargin: 6
        anchors.topMargin: 12
        anchors.bottomMargin: 12
        width: 5
        radius: 5
        color: card.accentColor
    }

    // invisible copy of the body with no line limit, only used to know if the text is long
    Text {
        id: measurer
        width: bodyText.width
        text: card.body
        font: bodyText.font
        wrapMode: Text.Wrap
        opacity: 0
        enabled: false
    }

    RowLayout {
        id: content
        anchors.fill: parent
        anchors.leftMargin: 20
        anchors.rightMargin: 12
        anchors.topMargin: card.pad
        anchors.bottomMargin: card.pad
        spacing: 10

        // icon, with a lettered fallback when there is no usable image
        Item {
            Layout.preferredWidth: 36
            Layout.preferredHeight: 36
            Layout.alignment: Qt.AlignTop

            Rectangle {
                anchors.fill: parent
                radius: 10
                visible: iconImage.status !== Image.Ready
                color: Qt.alpha(card.theme.primary, 0.15)
                Text {
                    anchors.centerIn: parent
                    text: card.appName.length > 0 ? card.appName.charAt(0).toUpperCase() : "?"
                    color: card.theme.primary
                    font.family: card.settings.fontdefault
                    font.pixelSize: 18
                    font.bold: true
                }
            }
            Image {
                id: iconImage
                anchors.fill: parent
                visible: status === Image.Ready
                source: card.iconSource
                sourceSize.width: 72
                sourceSize.height: 72
                fillMode: Image.PreserveAspectFit
                asynchronous: true
            }
        }

        ColumnLayout {
            id: col
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 2

            // header: summary + time (swaps to a close button on hover)
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 20
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: card.summary
                    color: card.theme.on_background
                    opacity: 0.95
                    font.family: card.settings.fontdefault
                    font.pixelSize: 16
                    font.bold: true
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
                Item {
                    Layout.preferredWidth: Math.max(timeLabel.implicitWidth, closeLabel.implicitWidth)
                    Layout.preferredHeight: 20

                    Text {
                        id: timeLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: card.timeText
                        color: card.theme.on_background
                        opacity: card.hovered ? 0 : 0.55
                        font.family: card.settings.fontdefault
                        font.pixelSize: 12
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                    }
                    Text {
                        id: closeLabel
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        text: "\u00d7"
                        color: card.theme.on_background
                        opacity: card.hovered ? 0.7 : 0
                        font.pixelSize: 20
                        Behavior on opacity {
                            NumberAnimation {
                                duration: 120
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            anchors.margins: -4
                            enabled: card.hovered
                            cursorShape: Qt.PointingHandCursor
                            onClicked: card.closeRequested()
                        }
                    }
                }
            }

            // body: clamped to 2 lines, or up to 12 when expanded
            Text {
                id: bodyText
                Layout.fillWidth: true
                visible: card.body !== ""
                text: card.body
                color: card.theme.on_background
                opacity: 0.7
                font.family: card.settings.fontdefault
                font.pixelSize: 13
                wrapMode: Text.Wrap
                maximumLineCount: card.expanded ? card.expandedLines : card.collapsedLines
                elide: Text.ElideRight
            }

            // pushes the footer to the bottom so the collapsed height stays constant
            Item {
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            // footer: app name, action chips, expand/collapse chevron
            RowLayout {
                Layout.fillWidth: true
                Layout.preferredHeight: 22
                spacing: 6

                Text {
                    Layout.fillWidth: true
                    text: card.appName
                    color: card.theme.on_background
                    opacity: 0.5
                    font.family: card.settings.fontdefault
                    font.pixelSize: 11
                    elide: Text.ElideRight
                }

                Repeater {
                    model: card.actions
                    delegate: Rectangle {
                        id: chip
                        required property var modelData
                        required property int index
                        visible: chip.index < 3 && chip.modelData.identifier !== "default"
                        Layout.preferredHeight: 22
                        Layout.preferredWidth: Math.min(96, chipText.implicitWidth + 18)
                        radius: 11
                        color: Qt.alpha(card.theme.primary, chipMouse.containsMouse ? 0.3 : 0.15)
                        Behavior on color {
                            ColorAnimation {
                                duration: 100
                            }
                        }

                        Text {
                            id: chipText
                            anchors.centerIn: parent
                            width: parent.width - 12
                            horizontalAlignment: Text.AlignHCenter
                            text: chip.modelData.text
                            elide: Text.ElideRight
                            color: card.theme.primary
                            font.family: card.settings.fontdefault
                            font.pixelSize: 11
                            font.bold: true
                        }
                        MouseArea {
                            id: chipMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: {
                                chip.modelData.invoke();
                                card.closeRequested();
                            }
                        }
                    }
                }

                Rectangle {
                    id: chevron
                    visible: card.expandable
                    Layout.preferredWidth: 22
                    Layout.preferredHeight: 22
                    radius: 11
                    color: chevMouse.containsMouse ? Qt.alpha(card.theme.primary, 0.18) : "transparent"
                    Behavior on color {
                        ColorAnimation {
                            duration: 100
                        }
                    }

                    Text {
                        anchors.centerIn: parent
                        text: "\u25be"
                        color: card.theme.primary
                        font.pixelSize: 13
                        rotation: card.expanded ? 180 : 0
                        Behavior on rotation {
                            NumberAnimation {
                                duration: 180
                                easing.type: Easing.OutCubic
                            }
                        }
                    }
                    MouseArea {
                        id: chevMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: card.toggleExpanded()
                    }
                }
            }
        }
    }

    // auto-dismiss progress line
    Rectangle {
        visible: card.timeoutMs > 0
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 16
        anchors.bottomMargin: 3
        height: 2
        radius: 1
        width: Math.max(0, (card.width - 32) * card.remaining)
        color: card.theme.primary
        opacity: 0.55
    }
}
