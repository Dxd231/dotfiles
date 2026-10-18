pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.Mpris
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// What the lock screen shows over the blurred screenshot: a card with a seconds ring around a
// rolling clock, the password pill, a Caps Lock warning, the media card and a power toolbar.
// It is driven entirely by properties (LockScreen owns authentication and the session lock), so
// it can be rendered and tested in an ordinary window.
Item {
    id: view

    property var date: new Date()
    property string buffer: ""
    property bool failed: false
    property bool busy: false
    property bool unlocking: false
    property bool shown: true         // the lock is up (drives the entrance)
    property bool capsOn: false
    property int keyTick: 0           // bumped on every key press, ripples the ring
    property var player: null

    signal suspendRequested
    signal restartRequested
    signal poweroffRequested

    // ---- entrance and unlock ----
    property real enter: shown ? 1 : 0
    Behavior on enter { Spring { speed: "slow" } }
    // 0 -> 1 over the unlock: the ring completes, pops and bursts away, then the rest fades
    property real unlockT: unlocking ? 1 : 0
    Behavior on unlockT { NumberAnimation { duration: 640; easing.type: Easing.InOutQuad } }
    property real unlockPop: unlocking ? 1 : 0
    Behavior on unlockPop { SpringAnimation { spring: 2.6; damping: 0.2; epsilon: 0.001 } }

    // ---- the ring ripples on every key press and flashes on a wrong password ----
    property real amp: 3
    property bool ampSpring: true
    Behavior on amp {
        enabled: view.ampSpring
        SpringAnimation { spring: 3; damping: 0.17; epsilon: 0.01 }
    }
    function kick(to) {
        ampSpring = false;
        amp = to;
        ampSpring = true;
        amp = 3;
    }
    onKeyTickChanged: kick(9)
    onFailedChanged: if (failed) kick(14)

    readonly property color ringColor: unlocking ? Colors.tertiary : failed ? Colors.error : Colors.primary
    readonly property real seconds: date.getSeconds() + date.getMilliseconds() / 1000

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 16
        opacity: Math.min(1, view.enter) * (1 - Math.max(0, Math.min(1, (view.unlockT - 0.3) / 0.7)))
        scale: 0.9 + 0.1 * view.enter

        // ---- clock + password ----
        Item {
            id: mainHolder
            width: 760
            height: mainCard.height
            Elevation { anchors.fill: mainCard; radius: mainCard.radius; level: 3 }
            Rectangle {
                id: mainCard
                width: parent.width
                height: mainCol.implicitHeight + 64
                radius: Motion.shapeExtraExtraLarge
                color: Colors.surface_container_high

                Column {
                    id: mainCol
                    anchors.centerIn: parent
                    width: parent.width - 64
                    spacing: 8

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 40
                        width: dateRow.implicitWidth + 32
                        radius: height / 2
                        color: Colors.secondary_container
                        Row {
                            id: dateRow
                            anchors.centerIn: parent
                            spacing: 8
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "lock"; size: 20; color: Colors.on_secondary_container }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "titleMedium"
                                color: Colors.on_secondary_container
                                text: Qt.formatDateTime(view.date, "dddd, d MMMM")
                            }
                        }
                    }

                    // ---- dial: seconds fill the wavy ring around the time ----
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 380
                        height: 380
                        scale: 1 + 0.25 * view.unlockPop

                        WavyRing {
                            anchors.fill: parent
                            thickness: 10
                            amplitude: view.amp
                            waves: 18
                            value: view.unlocking ? 1 : view.seconds / 60
                            activeColor: view.ringColor
                            trackColor: view.failed ? Colors.error_container : Colors.secondary_container
                            Behavior on activeColor { ColorFade {} }
                        }
                        RollingDigits {
                            anchors.centerIn: parent
                            text: Qt.formatDateTime(view.date, "HH:mm")
                            pixelSize: 112
                            letterSpacing: -2
                            color: Colors.on_surface
                        }
                    }

                    // ---- password field: pill at rest, squircle while typing ----
                    Rectangle {
                        id: pwBox
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 480
                        height: 64
                        radius: view.buffer.length > 0 || view.busy ? Motion.shapeLargeIncreased : height / 2
                        color: view.failed ? Colors.error_container : Colors.surface_container_highest
                        Behavior on radius { Spring {} }
                        Behavior on color { ColorFade {} }

                        transform: Translate { id: shake }
                        SequentialAnimation {
                            id: shakeAnim
                            NumberAnimation { target: shake; property: "x"; to: -14; duration: 45; easing.type: Easing.OutQuad }
                            NumberAnimation { target: shake; property: "x"; to: 14; duration: 55; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: shake; property: "x"; to: -10; duration: 55; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: shake; property: "x"; to: 10; duration: 55; easing.type: Easing.InOutQuad }
                            NumberAnimation { target: shake; property: "x"; to: 0; duration: 60; easing.type: Easing.OutQuad }
                        }
                        Connections {
                            target: view
                            function onFailedChanged() {
                                if (view.failed)
                                    shakeAnim.restart();
                            }
                        }

                        // typed characters: each is a different little shape that springs in with a turn
                        Row {
                            anchors.centerIn: parent
                            visible: !view.busy
                            Repeater {
                                model: 22
                                delegate: Item {
                                    id: slot
                                    required property int index
                                    readonly property bool active: index < view.buffer.length
                                    property bool inRow: active
                                    onActiveChanged: {
                                        if (active) {
                                            collapse.stop();
                                            inRow = true;
                                        } else {
                                            collapse.restart();
                                        }
                                    }
                                    Timer {
                                        id: collapse
                                        interval: 160
                                        onTriggered: slot.inRow = false
                                    }
                                    width: inRow ? 26 : 0
                                    height: 32
                                    Behavior on width { Spring {} }

                                    MorphShape {
                                        anchors.centerIn: parent
                                        width: 22
                                        height: 22
                                        shape: [1, 5, 4, 2, 0][slot.index % 5]
                                        fromShape: shape
                                        color: view.failed ? Colors.on_error_container : Colors.primary
                                        opacity: slot.active ? 1 : 0
                                        scale: slot.active ? 1 : 0.3
                                        rotation: slot.active ? 0 : -90
                                        Behavior on scale { Spring {} }
                                        Behavior on rotation { Spring {} }
                                        Behavior on opacity { Fade {} }
                                    }
                                }
                            }
                        }

                        LoadingIndicator {
                            anchors.centerIn: parent
                            visible: view.busy
                            running: visible
                        }

                        Row {
                            anchors.centerIn: parent
                            spacing: 12
                            visible: view.buffer.length === 0 && !view.busy
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                name: view.failed ? "error" : "password"
                                color: view.failed ? Colors.on_error_container : Colors.on_surface_variant
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "titleMedium"
                                color: view.failed ? Colors.on_error_container : Colors.on_surface_variant
                                text: view.failed ? "Incorrect password" : "Enter password"
                            }
                        }
                    }

                    // ---- Caps Lock warning: springs in under the field (the space is always reserved) ----
                    Item {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: capsPill.width
                        height: 40

                        Rectangle {
                            id: capsPill
                            anchors.centerIn: parent
                            height: 36
                            width: capsRow.implicitWidth + 28
                            radius: height / 2
                            color: Colors.tertiary_container
                            opacity: view.capsOn ? 1 : 0
                            scale: view.capsOn ? 1 : 0.4
                            Behavior on opacity { Fade { speed: "default" } }
                            Behavior on scale { Spring { speed: "default" } }
                            Row {
                                id: capsRow
                                anchors.centerIn: parent
                                spacing: 8
                                Icon { anchors.verticalCenter: parent.verticalCenter; name: "keyboard_capslock"; size: 20; color: Colors.on_tertiary_container }
                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    role: "labelLarge"
                                    emphasized: true
                                    color: Colors.on_tertiary_container
                                    text: "Caps Lock is on"
                                }
                            }
                        }
                    }
                }
            }
        }

        // ---- tasks left today (display only: the keyboard here is for the password) ----
        Item {
            id: taskGlance
            visible: Tasks.count > 0
            width: 760
            height: 80

            Elevation { anchors.fill: glanceSurface; radius: glanceSurface.radius; level: 3 }
            Rectangle {
                id: glanceSurface
                anchors.fill: parent
                radius: Motion.shapeExtraLarge
                color: Colors.surface_container_high

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 20
                    anchors.rightMargin: 20
                    spacing: 16

                    // a few of today's tasks; done ones fill in and turn
                    Row {
                        spacing: 8
                        Repeater {
                            model: Math.min(5, Tasks.active.length)
                            delegate: TaskAvatar {
                                required property int index
                                width: 44
                                height: 44
                                task: Tasks.active[index]
                                done: Tasks.isDone(Tasks.active[index], Tasks.todayKey)
                            }
                        }
                    }
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 0
                        StyledText {
                            role: "titleMedium"
                            emphasized: true
                            text: Tasks.dueCount === 0 ? "Nothing due today"
                                : Tasks.pendingCount === 0 ? "All done today"
                                : Tasks.pendingCount + (Tasks.pendingCount === 1 ? " task" : " tasks") + " left today"
                        }
                        StyledText {
                            role: "bodyMedium"
                            color: Colors.on_surface_variant
                            visible: Tasks.dueCount > 0
                            text: (Tasks.dueCount - Tasks.pendingCount) + " of " + Tasks.dueCount + " done"
                        }
                    }
                    Rectangle {
                        visible: Tasks.topStreak > 0
                        Layout.preferredHeight: 40
                        Layout.preferredWidth: streakRow.implicitWidth + 28
                        radius: 20
                        color: Colors.tertiary_container
                        Row {
                            id: streakRow
                            anchors.centerIn: parent
                            spacing: 6
                            Icon { anchors.verticalCenter: parent.verticalCenter; name: "local_fire_department"; size: 20; color: Colors.on_tertiary_container }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "labelLarge"
                                emphasized: true
                                color: Colors.on_tertiary_container
                                text: Tasks.topStreak + (Tasks.topStreak === 1 ? " day" : " days")
                            }
                        }
                    }
                }
            }
        }

        // ---- now playing ----
        Item {
            id: mediaCard
            readonly property bool playing: !!view.player && view.player.playbackState === MprisPlaybackState.Playing
            readonly property real len: view.player ? (view.player.length || 0) : 0
            readonly property real pos: view.player ? (view.player.position || 0) : 0
            function fmt(sec) {
                const t = Math.max(0, Math.floor(sec));
                return Math.floor(t / 60) + ":" + String(t % 60).padStart(2, "0");
            }

            visible: !!view.player && (view.player.trackTitle || "").length > 0
            width: 760
            height: 128

            Elevation { anchors.fill: mediaSurface; radius: mediaSurface.radius; level: 3 }
            Rectangle {
                id: mediaSurface
                anchors.fill: parent
                radius: Motion.shapeExtraLarge
                color: Colors.surface_container_high

                RowLayout {
                    anchors.fill: parent
                    anchors.margins: 16
                    spacing: 16

                    ClippingRectangle {
                        Layout.preferredWidth: 96
                        Layout.preferredHeight: 96
                        radius: Motion.shapeLarge
                        color: Colors.primary_container
                        Icon {
                            anchors.centerIn: parent
                            visible: art.status !== Image.Ready
                            name: "music_note"
                            size: 40
                            color: Colors.on_primary_container
                        }
                        Image {
                            id: art
                            anchors.fill: parent
                            source: view.player ? (view.player.trackArtUrl || "") : ""
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                        }
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 2
                        Marquee {
                            Layout.fillWidth: true
                            centered: false
                            role: "titleMedium"
                            jp: true
                            text: view.player ? (view.player.trackTitle || "") : ""
                        }
                        Marquee {
                            Layout.fillWidth: true
                            centered: false
                            role: "bodyMedium"
                            jp: true
                            color: Colors.on_surface_variant
                            visible: text.length > 0
                            text: view.player ? (view.player.trackArtist || "") : ""
                        }
                        LinearProgress {
                            Layout.fillWidth: true
                            Layout.topMargin: 8
                            visible: mediaCard.len > 0
                            value: mediaCard.pos / Math.max(1, mediaCard.len)
                            MouseArea {
                                anchors.fill: parent
                                anchors.margins: -8
                                cursorShape: Qt.PointingHandCursor
                                onClicked: mouse => view.player.position = mediaCard.len * Math.max(0, Math.min(1, (mouse.x - 8) / parent.width))
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true
                            visible: mediaCard.len > 0
                            StyledText { role: "labelSmall"; color: Colors.on_surface_variant; text: mediaCard.fmt(mediaCard.pos) }
                            Item { Layout.fillWidth: true }
                            StyledText { role: "labelSmall"; color: Colors.on_surface_variant; text: mediaCard.fmt(mediaCard.len) }
                        }
                    }

                    Row {
                        spacing: 8
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_previous"
                            style: "tonal"
                            onClicked: view.player.previous()
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            size: "m"
                            style: "filled"
                            icon: mediaCard.playing ? "pause" : "play_arrow"
                            // round while paused, square while playing
                            restRadius: mediaCard.playing ? Motion.shapeLarge : height / 2
                            onClicked: view.player.togglePlaying()
                        }
                        IconButton {
                            anchors.verticalCenter: parent.verticalCenter
                            icon: "skip_next"
                            style: "tonal"
                            onClicked: view.player.next()
                        }
                    }
                }
            }
        }
    }

    // ---- power actions: floating toolbar ----
    Item {
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 40
        anchors.horizontalCenter: parent.horizontalCenter
        width: toolbar.width
        height: toolbar.height
        opacity: content.opacity

        Elevation { anchors.fill: toolbar; radius: toolbar.radius; level: 3 }
        Rectangle {
            id: toolbar
            width: actions.implicitWidth + 16
            height: 64
            radius: height / 2
            color: Colors.surface_container

            Row {
                id: actions
                anchors.centerIn: parent
                spacing: 4
                IconButton {
                    icon: "bedtime"
                    style: "tonal"
                    color: Colors.tertiary_container
                    contentColor: Colors.on_tertiary_container
                    onClicked: view.suspendRequested()
                }
                IconButton {
                    icon: "restart_alt"
                    style: "tonal"
                    onClicked: view.restartRequested()
                }
                IconButton {
                    icon: "power_settings_new"
                    style: "tonal"
                    color: Colors.error_container
                    contentColor: Colors.on_error_container
                    onClicked: view.poweroffRequested()
                }
            }
        }
    }
}
