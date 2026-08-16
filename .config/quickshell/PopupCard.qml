import QtQuick
import QtQuick.Effects

// Drop this next to shell.qml. Wrap any popup's content in it instead of a
// bare Rectangle and you get the celestia look (cream card, soft shadow,
// spring-in animation) for free. Toggle it with the `open` property.
Item {
    id: root

    // ---- palette, tweak to taste ----
    property color bgCream: "#f6ece3"
    property color cardBlush: "#fbe2df"
    property color accentRose: "#9c4f47"
    property color textDark: "#5b3a35"
    property color textMuted: Qt.rgba(0.36, 0.23, 0.21, 0.55)

    property bool open: false
    property real cardRadius: 24
    default property alias content: contentHolder.data

    implicitWidth: 300
    implicitHeight: 350
    visible: opacity > 0.01
    transformOrigin: Item.Top

    // ---- open/close animation ----
    state: open ? "open" : "closed"
    states: [
        State {
            name: "open"
            PropertyChanges { target: root; opacity: 1.0; scale: 1.0; y: 0 }
        },
        State {
            name: "closed"
            PropertyChanges { target: root; opacity: 0.0; scale: 0.9; y: -18 }
        }
    ]
    transitions: [
        Transition {
            from: "closed"; to: "open"
            ParallelAnimation {
                NumberAnimation { properties: "opacity"; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { properties: "scale,y"; duration: 420; easing.type: Easing.OutBack; easing.overshoot: 1.35 }
            }
        },
        Transition {
            from: "open"; to: "closed"
            NumberAnimation { properties: "opacity,scale,y"; duration: 180; easing.type: Easing.InCubic }
        }
    ]

    // card body — this is what gets the soft drop shadow
    Rectangle {
        id: card
        anchors.fill: parent
        radius: root.cardRadius
        color: root.bgCream
        border.width: 1
        border.color: Qt.rgba(1, 1, 1, 0.65)
    }
    layer.enabled: true
    layer.effect: MultiEffect {
        shadowEnabled: true
        shadowColor: Qt.rgba(0.32, 0.18, 0.16, 0.32)
        shadowBlur: 0.7
        shadowVerticalOffset: 12
        shadowHorizontalOffset: 0
    }

    Item {
        id: contentHolder
        anchors.fill: parent
        anchors.margins: 16
    }
}
