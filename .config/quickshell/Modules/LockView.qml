pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.Components
import qs.Services

// What the lock screen shows over the blurred screenshot: a card with a seconds ring around a
// rolling clock, the password pill, a Caps Lock warning, today's tasks and goals and a power toolbar,
// with a field of drifting shapes behind it.
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
    property string greetName: Quickshell.env("USER") || ""

    signal suspendRequested
    signal restartRequested
    signal poweroffRequested
    // "reboot" | "poweroff": chosen here, runs once the session is unlocked (the lock hides apps' save prompts)
    property string pendingPower: ""

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

    ShapeField {
        anchors.fill: parent
        enter: view.enter
        keyTick: view.keyTick
        failed: view.failed
        unlockT: view.unlockT
    }

    Column {
        id: content
        anchors.centerIn: parent
        spacing: 16
        opacity: Math.min(1, view.enter) * (1 - Math.max(0, Math.min(1, (view.unlockT - 0.3) / 0.7)))
        scale: 0.9 + 0.1 * view.enter

        // ---- greeting ----
        Item {
            id: greeting
            width: 760
            height: greetText.implicitHeight
            Appear { delay: 60; lift: 14 }
            StyledText {
                id: greetText
                anchors.horizontalCenter: parent.horizontalCenter
                jp: true
                role: "displaySmall"
                emphasized: true
                color: Colors.on_surface
                text: {
                    const h = view.date.getHours();
                    const hello = h >= 5 && h < 11 ? "おはよう" : h >= 11 && h < 18 ? "こんにちは" : "こんばんは";
                    return view.greetName ? hello + "、" + view.greetName : hello;
                }
            }
        }

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
                                        shape: ["cookie4", "flower", "clover4", "gem", "softBurst", "cookie9", "clover8", "sunny"][slot.index % 8]
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

        // ---- today: tasks left, immersion and Anki goals (display only: the keyboard here is for the password) ----
        RowLayout {
            id: todayRow
            width: 760
            height: 80
            spacing: 16

            Item {
                id: taskGlance
                visible: Tasks.count > 0
                Layout.fillWidth: true
                Layout.preferredWidth: 304
                Layout.preferredHeight: 80
                Appear { delay: 220 }
                Elevation { anchors.fill: glanceSurface; radius: glanceSurface.radius; level: 3 }
                Rectangle {
                    id: glanceSurface
                    anchors.fill: parent
                    radius: Motion.shapeExtraLarge
                    color: Colors.surface_container_high

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16
                        anchors.rightMargin: 16
                        spacing: 12

                        // a few of today's tasks; done ones fill in and turn
                        Row {
                            spacing: 6
                            Repeater {
                                model: Math.min(3, Tasks.active.length)
                                delegate: TaskAvatar {
                                    required property int index
                                    width: 40
                                    height: 40
                                    task: Tasks.active[index]
                                    done: Tasks.isDone(Tasks.active[index], Tasks.todayKey)
                                }
                            }
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 0
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                role: "titleMedium"
                                emphasized: true
                                text: Tasks.dueCount === 0 ? "Nothing due"
                                    : Tasks.pendingCount === 0 ? "All done"
                                    : Tasks.pendingCount + (Tasks.pendingCount === 1 ? " task" : " tasks") + " left"
                            }
                            StyledText {
                                Layout.fillWidth: true
                                elide: Text.ElideRight
                                role: "bodyMedium"
                                color: Colors.on_surface_variant
                                visible: Tasks.dueCount > 0
                                text: (Tasks.dueCount - Tasks.pendingCount) + " of " + Tasks.dueCount + " done"
                            }
                        }
                    }
                }
            }

            // immersion minutes against the day's goal
            Item {
                Layout.fillWidth: true
                Layout.preferredWidth: 212
                Layout.preferredHeight: 80
                Appear { delay: 300 }
                Elevation { anchors.fill: immSurface; radius: immSurface.radius; level: 3 }
                Rectangle {
                    id: immSurface
                    anchors.fill: parent
                    radius: Motion.shapeExtraLarge
                    color: Colors.surface_container_high
                    Row {
                        anchors.centerIn: parent
                        spacing: 12
                        GoalBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            progress: Math.min(1, Immersion.todayMinutes / Math.max(1, Immersion.todayGoal))
                            over: Math.min(1, Immersion.overLaps)
                            arcColor: Immersion.goalMet ? Colors.tertiary : Colors.primary
                            Icon { anchors.centerIn: parent; name: "headphones"; size: 14; color: Colors.on_primary_container }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText { role: "titleMedium"; emphasized: true; text: Math.floor(Immersion.todayMinutes) + " / " + Immersion.todayGoal + " min" }
                            StyledText { role: "bodyMedium"; color: Colors.on_surface_variant; text: Immersion.goalMet ? "Goal met" : "Immersion" }
                        }
                    }
                }
            }

            // cards mined against the day's goal
            Item {
                visible: Anki.online || Anki.minedToday > 0
                Layout.fillWidth: true
                Layout.preferredWidth: 212
                Layout.preferredHeight: 80
                Appear { delay: 380 }
                Elevation { anchors.fill: ankiSurface; radius: ankiSurface.radius; level: 3 }
                Rectangle {
                    id: ankiSurface
                    anchors.fill: parent
                    radius: Motion.shapeExtraLarge
                    color: Colors.surface_container_high
                    Row {
                        anchors.centerIn: parent
                        spacing: 12
                        GoalBadge {
                            anchors.verticalCenter: parent.verticalCenter
                            progress: Math.min(1, Anki.minedToday / Math.max(1, Anki.todayGoal))
                            over: Math.min(1, Math.max(0, Anki.minedToday / Math.max(1, Anki.todayGoal) - 1))
                            arcColor: Anki.goalMet ? Colors.tertiary : Colors.primary
                            Icon { anchors.centerIn: parent; name: "style"; size: 14; color: Colors.on_primary_container }
                        }
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            StyledText { role: "titleMedium"; emphasized: true; text: Anki.minedToday + " / " + Anki.todayGoal + " cards" }
                            StyledText { role: "bodyMedium"; color: Colors.on_surface_variant; text: Anki.goalMet ? "Goal met" : "Mined" }
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

        // chosen but waiting for the unlock
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            anchors.bottom: toolbar.top
            anchors.bottomMargin: 12
            role: "titleMedium"
            emphasized: true
            color: Colors.on_surface
            id: pendingLabel
            // keeps its words while it fades out, and pops when the choice changes
            property string shownPower: ""
            property real pop: 1
            opacity: view.pendingPower !== "" ? 1 : 0
            scale: (view.pendingPower !== "" ? 1 : 0.9) * pop
            transform: Translate { y: (1 - pendingLabel.opacity) * 8 }
            Behavior on opacity { Fade { speed: "default" } }
            Behavior on scale { Spring { speed: "default" } }
            text: shownPower === "reboot" ? "Unlock to restart" : shownPower === "poweroff" ? "Unlock to shut down" : ""
            Connections {
                target: view
                function onPendingPowerChanged() {
                    if (view.pendingPower === "")
                        return;
                    if (pendingLabel.shownPower !== "" && pendingLabel.shownPower !== view.pendingPower && pendingLabel.opacity > 0.5)
                        pendingPop.restart();
                    pendingLabel.shownPower = view.pendingPower;
                }
            }
            SequentialAnimation {
                id: pendingPop
                PropertyAction { target: pendingLabel; property: "pop"; value: 0.88 }
                NumberAnimation { target: pendingLabel; property: "pop"; to: 1; duration: 350; easing.type: Easing.OutBack }
            }
        }
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
                    style: view.pendingPower === "reboot" ? "filled" : "tonal"
                    onClicked: view.restartRequested()
                }
                IconButton {
                    icon: "power_settings_new"
                    style: "tonal"
                    color: view.pendingPower === "poweroff" ? Colors.error : Colors.error_container
                    contentColor: view.pendingPower === "poweroff" ? Colors.on_error : Colors.on_error_container
                    onClicked: view.poweroffRequested()
                }
            }
        }
    }
}
