pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts

// The shell's LockView (Modules/LockView.qml) as a login screen: the same card with a seconds ring
// around a rolling clock and the password pill, plus a user chip and a session chip. Authentication
// goes through SDDM instead of PAM.
FocusScope {
    id: view

    property var date: new Date()
    property string buffer: ""
    property bool failed: false
    property bool busy: false
    property bool unlocking: false
    property int keyTick: 0
    readonly property bool capsOn: keyboard.capsLock

    // ---- users and sessions (SDDM models, mirrored into plain arrays for the chips) ----
    property var users: []
    property var sessions: []
    property int userIndex: Math.max(0, userModel.lastIndex)
    property int sessionIndex: Math.max(0, sessionModel.lastIndex)
    readonly property string userName: users[userIndex] ? users[userIndex].name : ""
    readonly property string userLabel: users[userIndex] ? (users[userIndex].real || users[userIndex].name) : ""
    readonly property string sessionName: sessions[sessionIndex] || ""

    Repeater {
        model: userModel
        delegate: Item {
            required property int index
            required property string name
            required property string realName
            Component.onCompleted: {
                const u = view.users.slice();
                u[index] = { name: name, real: realName };
                view.users = u;
            }
        }
    }
    Repeater {
        model: sessionModel
        delegate: Item {
            required property int index
            required property string name
            Component.onCompleted: {
                const s = view.sessions.slice();
                s[index] = name;
                view.sessions = s;
            }
        }
    }

    // ---- entrance and unlock ----
    property real enter: 0
    Component.onCompleted: {
        enter = 1;
        forceActiveFocus();
    }
    Behavior on enter { Spring { speed: "slow" } }
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

    Timer {
        interval: 33
        running: true
        repeat: true
        onTriggered: view.date = new Date()
    }

    // ---- authentication ----
    function submit() {
        if (busy || unlocking || buffer.length === 0 || userName === "")
            return;
        busy = true;
        failed = false;
        sddm.login(userName, buffer, sessionIndex);
    }
    Connections {
        target: sddm
        function onLoginFailed() {
            view.busy = false;
            view.failed = true;
            view.buffer = "";
        }
        function onLoginSucceeded() {
            view.busy = false;
            view.unlocking = true;
        }
    }

    Keys.onPressed: event => {
        if (view.busy || view.unlocking)
            return;
        if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            view.submit();
        } else if (event.key === Qt.Key_Backspace) {
            view.buffer = event.modifiers & Qt.ControlModifier ? "" : view.buffer.slice(0, -1);
            view.keyTick++;
        } else if (event.key === Qt.Key_Escape) {
            view.buffer = "";
            view.failed = false;
        } else if (event.text.length > 0 && event.text.charCodeAt(0) >= 32 && !(event.modifiers & (Qt.ControlModifier | Qt.AltModifier))) {
            if (view.failed)
                view.failed = false;
            view.buffer += event.text;
            view.keyTick++;
        }
    }

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
                    return view.userLabel ? hello + "、" + view.userLabel : hello;
                }
            }
        }

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

                    // dial: seconds fill the wavy ring around the time
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

                    // user chip: tap to switch when there is more than one
                    Rectangle {
                        id: userChip
                        anchors.horizontalCenter: parent.horizontalCenter
                        height: 40
                        width: userRow.implicitWidth + 16 + 20
                        radius: height / 2
                        color: Colors.primary_container
                        Row {
                            id: userRow
                            anchors.verticalCenter: parent.verticalCenter
                            x: 8
                            spacing: 10
                            MorphShape {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 28
                                height: 28
                                shape: 4
                                fromShape: 4
                                color: Colors.primary
                                StyledText {
                                    anchors.centerIn: parent
                                    role: "labelLarge"
                                    emphasized: true
                                    color: Colors.on_primary
                                    text: view.userLabel.charAt(0).toUpperCase()
                                }
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "titleMedium"
                                jp: true
                                color: Colors.on_primary_container
                                text: view.userLabel
                            }
                        }
                        StateLayer {
                            tint: Colors.on_primary_container
                            hovered: userMouse.containsMouse && view.users.length > 1
                            pressed: userMouse.pressed && view.users.length > 1
                        }
                        MouseArea {
                            id: userMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: view.users.length > 1 ? Qt.PointingHandCursor : Qt.ArrowCursor
                            onClicked: {
                                if (view.users.length > 1)
                                    view.userIndex = (view.userIndex + 1) % view.users.length;
                                view.forceActiveFocus();
                            }
                        }
                    }

                    // password field: pill at rest, squircle while typing
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

                    // Caps Lock warning: springs in under the field (the space is always reserved)
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
    }

    // ---- session + power: floating toolbar ----
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

                // session chip: tap to cycle
                Clickable {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: view.sessions.length > 0
                    height: 40
                    width: sessionRow.implicitWidth + 32
                    color: Colors.secondary_container
                    contentColor: Colors.on_secondary_container
                    onClicked: {
                        if (view.sessions.length > 1)
                            view.sessionIndex = (view.sessionIndex + 1) % view.sessions.length;
                        view.forceActiveFocus();
                    }
                    Row {
                        id: sessionRow
                        anchors.centerIn: parent
                        spacing: 8
                        Icon { anchors.verticalCenter: parent.verticalCenter; name: "desktop_windows"; size: 20; color: Colors.on_secondary_container }
                        StyledText {
                            anchors.verticalCenter: parent.verticalCenter
                            role: "labelLarge"
                            emphasized: true
                            color: Colors.on_secondary_container
                            text: view.sessionName
                        }
                    }
                }
                IconButton {
                    icon: "bedtime"
                    style: "tonal"
                    color: Colors.tertiary_container
                    contentColor: Colors.on_tertiary_container
                    visible: sddm.canSuspend
                    onClicked: sddm.suspend()
                }
                IconButton {
                    icon: "restart_alt"
                    style: "tonal"
                    visible: sddm.canReboot
                    onClicked: sddm.reboot()
                }
                IconButton {
                    icon: "power_settings_new"
                    style: "tonal"
                    color: Colors.error_container
                    contentColor: Colors.on_error_container
                    visible: sddm.canPowerOff
                    onClicked: sddm.powerOff()
                }
            }
        }
    }
}
