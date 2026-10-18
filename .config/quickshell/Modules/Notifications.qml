pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Services.Notifications
import Quickshell.Wayland
import qs
import qs.Components
import qs.Services

// Notification server, popups, and the left-side center (quick settings + history).
Scope {
    id: notify_root

    property var controlCenter: null

    // ---- state ----
    property bool centerOpen: false
    property bool dnd: false            // do not disturb: no popups / sound (critical still shows)
    onDndChanged: Sound.muted = dnd
    property int unread: 0              // notifications received while the center was closed
    property int maxHistory: 100
    property var mutedApps: []
    readonly property bool hasNotifications: history.count > 0

    property double nowMs: Date.now()   // drives the relative timestamps
    property double _closedAt: 0

    onCenterOpenChanged: {
        if (centerOpen) {
            unread = 0;
            nowMs = Date.now();
        } else {
            _closedAt = Date.now();
        }
    }

    ListModel {
        id: history
    }

    ListModel {
        id: activePopupsModel
    }

    readonly property int activePopupCount: activePopupsModel.count

    function showPopup(n) {
        if (!n) return;
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).notifId === n.id) {
                return;
            }
        }
        const notifUrl = notify_root.findUrlFromNotification(n);
        activePopupsModel.insert(0, {
            notifId: n.id,
            summary: n.summary ?? "",
            body: n.body ?? "",
            appName: n.appName ?? "",
            desktopEntry: n.desktopEntry ?? "",
            appIcon: n.appIcon ?? "",
            url: notifUrl ?? "",
            image: notify_root.iconFor(n),
            urgency: n.urgency ?? NotificationUrgency.Normal,
            expireTimeout: n.expireTimeout ?? 0,
            trackedRef: n
        });
    }

    function removePopup(notifId) {
        if (notifId === undefined || notifId === null) return;
        for (let i = 0; i < activePopupsModel.count; i++) {
            if (activePopupsModel.get(i).notifId === notifId) {
                activePopupsModel.remove(i);
                break;
            }
        }
    }

    function dismissTracked(notifId) {
        if (notifId === undefined || notifId === null) return;
        try {
            const tracked = server.trackedNotifications.values.find(t => t.id === notifId);
            if (tracked)
                tracked.dismiss();
        } catch (e) {}
    }

    function dismissNotification(notifId, index) {
        dismissTracked(notifId);
        removePopup(notifId);
        if (index !== undefined && index >= 0 && index < history.count) {
            history.remove(index);
        } else if (notifId !== undefined) {
            for (let i = 0; i < history.count; i++) {
                if (history.get(i).notifId === notifId) {
                    history.remove(i);
                    break;
                }
            }
        }
    }

    function clearAllHistory() {
        for (let i = 0; i < history.count; i++) {
            const item = history.get(i);
            if (item && item.notifId !== undefined) {
                dismissTracked(item.notifId);
            }
        }
        history.clear();
        activePopupsModel.clear();
    }

    // ---------------------------------------------------------------- helpers

    // Bell button in the bar uses this: if the focus grab just closed the panel
    // on the same click, don't reopen it.
    function toggleCenter() {
        if (!notify_root.centerOpen && Date.now() - notify_root._closedAt < 250)
            return;
        notify_root.centerOpen = !notify_root.centerOpen;
    }

    function iconFor(n) {
        if (n.image)
            return n.image;
        const ic = n.appIcon || "";
        if (ic === "")
            return "";
        if (ic.startsWith("/") || ic.indexOf("://") !== -1)
            return ic;
        return Quickshell.iconPath(ic, true) || "";
    }

    function relTime(ms) {
        const s = Math.max(0, (notify_root.nowMs - ms) / 1000);
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m ago";
        if (s < 86400)
            return Math.floor(s / 3600) + "h ago";
        return Qt.formatDateTime(new Date(ms), "d MMM");
    }

    function formatSpeed(kb) {
        if (kb >= 1024)
            return (kb / 1024).toFixed(1) + " MB/s";
        if (kb >= 1)
            return kb.toFixed(0) + " KB/s";
        return "0 KB/s";
    }

    function playSound() {
        Quickshell.execDetached(["paplay", Quickshell.shellPath("assets/notification.mp3")]);
    }


    function extractUrl(text) {
        if (!text || typeof text !== "string")
            return null;

        // 1. HTML anchor tag: <a href="...">
        const anchorMatch = text.match(/<a\s+[^>]*href=["']?([^"'>\s]+)/i);
        if (anchorMatch && anchorMatch[1])
            return anchorMatch[1].replace(/&amp;/g, "&");

        // 2. Markdown [title](url)
        const mdMatch = text.match(/\[[^\]]*\]\((https?:\/\/[^\s\)]+)\)/i);
        if (mdMatch && mdMatch[1])
            return mdMatch[1].replace(/&amp;/g, "&");

        // 3. Standard http/https URL
        const urlMatch = text.match(/https?:\/\/[^\s"'<>\)]+/i);
        if (urlMatch)
            return urlMatch[0].replace(/[.,;:!?]+$/, "").replace(/&amp;/g, "&");

        // 4. youtube.com or youtu.be or www. link
        const domainMatch = text.match(/\b(youtube\.com\/[^\s"'<>\)]+|youtu\.be\/[^\s"'<>\)]+|www\.[^\s"'<>\)]+)/i);
        if (domainMatch)
            return ("https://" + domainMatch[0]).replace(/[.,;:!?]+$/, "").replace(/&amp;/g, "&");

        return null;
    }

    function findUrlFromNotification(n) {
        if (!n)
            return "";

        // 1. Check hints
        if (n.hints) {
            const h = n.hints;
            const urlKeys = ["url", "URL", "link", "x-kde-urls", "default-action-url", "action-urls"];
            for (let i = 0; i < urlKeys.length; i++) {
                const val = h[urlKeys[i]];
                if (val) {
                    if (typeof val === "string") {
                        const u = notify_root.extractUrl(val);
                        if (u)
                            return u;
                    } else if (Array.isArray(val) && val.length > 0) {
                        const u = notify_root.extractUrl(String(val[0]));
                        if (u)
                            return u;
                    }
                }
            }
        }

        // 2. Check actions
        if (n.actions) {
            const acts = n.actions;
            for (let i = 0; i < acts.length; i++) {
                const act = acts[i];
                if (act) {
                    const u1 = notify_root.extractUrl(act.identifier);
                    if (u1)
                        return u1;
                    const u2 = notify_root.extractUrl(act.text);
                    if (u2)
                        return u2;
                }
            }
        }

        // 3. Check body
        const bodyUrl = notify_root.extractUrl(n.body);
        if (bodyUrl)
            return bodyUrl;

        // 4. Check summary
        const sumUrl = notify_root.extractUrl(n.summary);
        if (sumUrl)
            return sumUrl;

        return "";
    }

    function openNotification(notifData, index) {
        if (!notifData)
            return;

        // If index was not provided, locate it in history
        if (index === undefined && notifData.notifId !== undefined) {
            for (let i = 0; i < history.count; i++) {
                if (history.get(i).notifId === notifData.notifId) {
                    index = i;
                    break;
                }
            }
        }

        // Remove from popups if currently displayed
        if (notifData.notifId !== undefined) {
            notify_root.removePopup(notifData.notifId);
        }

        // 1. If active in trackedNotifications, invoke default action
        let actionInvoked = false;
        if (notifData.notifId !== undefined) {
            try {
                const tracked = server.trackedNotifications.values.find(t => t.id === notifData.notifId);
                if (tracked) {
                    const acts = tracked.actions;
                    if (acts && acts.length > 0) {
                        const def = acts.find(a => a.identifier === "default") ?? acts[0];
                        if (def) {
                            def.invoke();
                            actionInvoked = true;
                        }
                    }
                    if (!actionInvoked || tracked.resident) {
                        tracked.dismiss();
                    }
                }
            } catch (e) {}
        }

        // 2. Fallback when no D-Bus action exists: open URL if present
        if (!actionInvoked) {
            const targetUrl = (notifData.url && notifData.url.length > 0)
                ? notifData.url
                : (notify_root.extractUrl(notifData.body) ?? notify_root.extractUrl(notifData.summary));

            if (targetUrl) {
                Qt.openUrlExternally(targetUrl);
            }
        }

        // 3. Remove from history
        if (index !== undefined && index >= 0 && index < history.count) {
            history.remove(index);
        }

        // 5. Close notification center
        notify_root.centerOpen = false;
    }

    // keeps "5m ago" fresh while the panel is open
    Timer {
        interval: 30000
        running: notify_root.centerOpen
        repeat: true
        onTriggered: notify_root.nowMs = Date.now()
    }

    // when each notification arrived (id -> ms), kept on disk so a reload can put the carried-over
    // ones back in the history with their real times. Ids restart with the process, but only
    // notifications from the previous generation look their stamp up, so stale entries are harmless.
    property var stamps: ({})
    function rememberStamp(id, stamp) {
        const next = {};
        for (let i = 0; i < history.count; i++) {
            const h = history.get(i);
            if (h.notifId !== undefined && notify_root.stamps[h.notifId])
                next[h.notifId] = notify_root.stamps[h.notifId];
        }
        next[id] = stamp;
        notify_root.stamps = next;
        stampAdapter.stamps = next;
        stampStore.writeAdapter();
    }
    FileView {
        id: stampStore
        path: (Quickshell.env("XDG_STATE_HOME") ? Quickshell.env("XDG_STATE_HOME") : (Quickshell.env("HOME") + "/.local/state")) + "/quickshell/notif-stamps.json"
        printErrors: false
        blockLoading: true
        onLoaded: notify_root.stamps = stampAdapter.stamps || {}
        JsonAdapter {
            id: stampAdapter
            property var stamps: ({})
        }
    }

    // ---------------------------------------------------------------- server

    NotificationServer {
        id: server
        actionsSupported: true
        bodySupported: true
        bodyMarkupSupported: true
        bodyHyperlinksSupported: true
        imageSupported: true
        onNotification: n => {
            // after a reload the server hands back the notifications it was still tracking: they go
            // back into the history as they were (same time, same place), without a popup, a sound
            // or an unread mark
            const carried = n.lastGeneration;
            const stamp = carried && notify_root.stamps[n.id] ? notify_root.stamps[n.id] : Date.now();
            let at = 0;
            while (at < history.count && history.get(at).stamp >= stamp)
                at++;
            const notifUrl = notify_root.findUrlFromNotification(n);
            history.insert(at, {
                notifId: n.id,
                summary: n.summary,
                body: n.body,
                appName: n.appName,
                desktopEntry: n.desktopEntry || "",
                appIcon: n.appIcon || "",
                url: notifUrl || "",
                urgency: n.urgency,
                stamp: stamp,
                image: notify_root.iconFor(n)
            });

            // Keep notification tracked on D-Bus so default action & resources remain valid
            n.tracked = true;

            while (history.count > notify_root.maxHistory) {
                const old = history.get(history.count - 1);
                if (old && old.notifId !== undefined) {
                    notify_root.dismissTracked(old.notifId);
                }
                history.remove(history.count - 1);
            }

            notify_root.rememberStamp(n.id, stamp);
            if (carried)
                return;

            if (!notify_root.centerOpen)
                notify_root.unread++;

            const muted = notify_root.mutedApps.indexOf(n.appName) !== -1;
            const critical = n.urgency === NotificationUrgency.Critical;
            if (muted || (notify_root.dnd && !critical))
                return;   // kept in history & tracked on D-Bus, but no popup and no sound

            notify_root.showPopup(n);
            // the task and focus-timer alarms play their own sound
            if (n.appName !== "Tasks" && n.appName !== "Focus timer")
                notify_root.playSound();
        }
    }

    Connections {
        target: server
        function onTrackedNotificationsChanged() {
            const tracked = server.trackedNotifications.values;
            for (let i = activePopupsModel.count - 1; i >= 0; i--) {
                const item = activePopupsModel.get(i);
                if (tracked.indexOf(item.trackedRef) === -1) {
                    activePopupsModel.remove(i);
                }
            }
        }
    }

    IpcHandler {
        target: "notifications"
        function toggle(): void {
            notify_root.toggleCenter();
        }
        function show(): void {
            notify_root.centerOpen = true;
        }
        function open(): void {
            notify_root.centerOpen = true;
        }
        function hide(): void {
            notify_root.centerOpen = false;
        }
        function close(): void {
            notify_root.centerOpen = false;
        }
        function toggleDnd(): void {
            notify_root.dnd = !notify_root.dnd;
        }
        function clear(): void {
            notify_root.clearAllHistory();
        }
        function mute(app: string): void {
            if (notify_root.mutedApps.indexOf(app) === -1)
                notify_root.mutedApps = notify_root.mutedApps.concat([app]);
        }
        function unmute(app: string): void {
            notify_root.mutedApps = notify_root.mutedApps.filter(a => a !== app);
        }
    }

    // ---------------------------------------------------------------- notification center

    HyprlandFocusGrab {
        windows: [centerPanel]
        active: centerPanel.visible && notify_root.centerOpen
        onCleared: notify_root.centerOpen = false
    }

    PanelWindow {
        id: centerPanel
        WlrLayershell.namespace: "quickshell:center"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: notify_root.centerOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
        exclusiveZone: 0
        anchors { top: true; bottom: true; left: true }
        margins.bottom: 8
        implicitWidth: 400 + 8 + 24
        color: "transparent"
        visible: notify_root.centerOpen || column.x > -column.width
        mask: Region { item: column }

        // entrance: the quick-settings tiles and then the history cards pop in one after another;
        // the counter restarts every time the window has been hidden and is shown again
        property int enterStage: 0
        onVisibleChanged: if (!visible) enterStage = 0
        Timer {
            running: notify_root.centerOpen && centerPanel.enterStage < 18
            interval: 50
            repeat: true
            onTriggered: centerPanel.enterStage += 1
        }

        Item {
            anchors.fill: parent
            focus: notify_root.centerOpen
            // Escape steps back from a quick-settings detail page before it closes the center
            Keys.onEscapePressed: {
                if (notify_root.controlCenter && notify_root.controlCenter.page !== "")
                    notify_root.controlCenter.page = "";
                else
                    notify_root.centerOpen = false;
            }
        }

        Column {
            id: column
            width: 400
            y: 8
            spacing: 8
            x: notify_root.centerOpen ? 8 : -width - 24
            Behavior on x {
                Spring { speed: "default"; expressive: notify_root.centerOpen }
            }

            Item {
                width: ccCard.width
                height: ccCard.height
                Elevation { anchors.fill: parent; radius: Motion.shapeExtraLarge; level: 3 }
                ControlCenterCard {
                    id: ccCard
                    controlCenter: notify_root.controlCenter
                    stage: centerPanel.enterStage
                    live: notify_root.centerOpen
                }
            }

            Item {
                width: 400
                height: Math.min(560, centerPanel.height - ccCard.height - 16 - 8)
                Behavior on height { Spring { speed: "default" } }

                Elevation { anchors.fill: notifSurface; radius: notifSurface.radius; level: 3 }
                Rectangle {
                    id: notifSurface
                    anchors.fill: parent
                    radius: Motion.shapeExtraLarge
                    color: Colors.surface_container

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 12

                        // header
                        RowLayout {
                            Layout.fillWidth: true
                            Layout.leftMargin: 8
                            spacing: 8

                            ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0
                                Row {
                                    spacing: 8
                                    StyledText { role: "titleLarge"; text: "Notifications" }
                                    // a count, not an alert: primary rather than error; the digits roll
                                    Rectangle {
                                        anchors.verticalCenter: parent.verticalCenter
                                        visible: history.count > 0
                                        height: 22
                                        width: countDigits.implicitWidth + 16
                                        radius: height / 2
                                        color: Colors.primary
                                        Behavior on width { Spring {} }
                                        RollingDigits {
                                            id: countDigits
                                            anchors.centerIn: parent
                                            pixelSize: 13
                                            color: Colors.on_primary
                                            text: String(history.count)
                                        }
                                    }
                                }
                                StyledText {
                                    role: "bodyMedium"
                                    color: Colors.on_surface_variant
                                    text: notify_root.dnd ? "Do not disturb is on" : Qt.formatDate(new Date(notify_root.nowMs), "dddd, d MMMM")
                                }
                            }

                            IconButton {
                                icon: notify_root.dnd ? "notifications_paused" : "notifications_active"
                                style: "tonal"
                                checkable: true
                                checked: notify_root.dnd
                                onClicked: notify_root.dnd = !notify_root.dnd
                            }
                            IconButton {
                                visible: notify_root.hasNotifications
                                icon: "clear_all"
                                style: "tonal"
                                onClicked: notify_root.clearAllHistory()
                            }
                        }

                        // history
                        Item {
                            Layout.fillWidth: true
                            Layout.fillHeight: true

                            ListView {
                                id: historyList
                                anchors.fill: parent
                                spacing: 2
                                clip: true
                                model: history
                                boundsBehavior: Flickable.StopAtBounds
                                // no scrollbar: the cards are short-lived, and wheel / drag scrolling doesn't need one

                                add: Transition {
                                    Fade { property: "opacity"; from: 0; to: 1; speed: "default" }
                                    Spring { property: "scale"; from: 0.9; to: 1; speed: "default" }
                                }
                                remove: Transition {
                                    Fade { property: "opacity"; to: 0 }
                                    NumberAnimation { property: "scale"; to: 0.8; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
                                    NumberAnimation { property: "x"; to: -historyList.width; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
                                }
                                // neighbours close the gap on the fast, bouncy spring
                                displaced: Transition {
                                    Spring { properties: "x,y"; speed: "fast" }
                                }

                                delegate: NotifCard {
                                    id: hcard
                                    required property var model
                                    required property int index

                                    width: historyList.width
                                    appearTarget: centerPanel.enterStage >= 6 + Math.min(hcard.index, 8) ? 1 : 0
                                    first: index === 0
                                    last: index === historyList.count - 1
                                    summary: model.summary
                                    body: model.body
                                    appName: model.appName
                                    desktopEntry: model.desktopEntry ?? ""
                                    appIcon: model.appIcon ?? ""
                                    url: model.url ?? ""
                                    iconSource: model.image
                                    urgency: model.urgency
                                    timeText: notify_root.relTime(model.stamp)
                                    actions: {
                                        const tracked = server.trackedNotifications.values.find(t => t.id === hcard.model.notifId);
                                        return tracked ? tracked.actions : [];
                                    }
                                    onActivated: notify_root.openNotification(hcard.model, hcard.index)
                                    onCloseRequested: notify_root.dismissNotification(hcard.model.notifId, hcard.index)
                                }
                            }

                            ColumnLayout {
                                anchors.centerIn: parent
                                spacing: 12
                                visible: history.count === 0

                                // a big turning shape that pops in when the list empties; sunny while do-not-disturb is on
                                ShapeBadge {
                                    id: emptyBadge
                                    Layout.alignment: Qt.AlignHCenter
                                    Layout.preferredWidth: 104
                                    Layout.preferredHeight: 104
                                    shapeRest: 1
                                    shapeActive: 4
                                    active: notify_root.dnd
                                    spinning: history.count === 0 && centerPanel.visible
                                    color: notify_root.dnd ? Colors.tertiary_container : Colors.secondary_container
                                    badgeScale: history.count === 0 ? 1 : 0.5
                                    Icon {
                                        anchors.centerIn: parent
                                        size: 40
                                        name: notify_root.dnd ? "notifications_paused" : "notifications"
                                        color: notify_root.dnd ? Colors.on_tertiary_container : Colors.on_secondary_container
                                    }
                                }
                                StyledText { Layout.alignment: Qt.AlignHCenter; role: "titleMedium"; text: "All caught up" }
                                StyledText { Layout.alignment: Qt.AlignHCenter; role: "bodyMedium"; color: Colors.on_surface_variant; text: "No new notifications" }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------------- popups

    PanelWindow {
        id: popupWindow
        WlrLayershell.namespace: "quickshell:popup"
        WlrLayershell.layer: WlrLayer.Overlay
        exclusiveZone: 0
        // fixed-size surface: resizing it every frame while cards animate made them stutter;
        // the mask below limits input to the cards
        anchors { top: true; bottom: true; left: true }
        implicitWidth: 360 + 32
        color: "transparent"
        visible: !notify_root.centerOpen && activePopupsModel.count > 0
        mask: Region { item: popupList }

        ListView {
            id: popupList
            x: 8
            y: 4
            width: 360
            height: contentHeight
            interactive: false
            spacing: 8
            model: activePopupsModel
            // standard (non-overshooting) spring so the stack glides instead of wobbling
            displaced: Transition {
                Spring { property: "y"; speed: "default"; expressive: false }
            }

            delegate: NotifCard {
                id: pcard
                required property var model
                required property int index

                width: 360
                isPopup: true
                slideIn: true
                summary: model.summary
                body: model.body
                appName: model.appName
                desktopEntry: model.desktopEntry ?? ""
                appIcon: model.appIcon ?? ""
                iconSource: model.image
                urgency: model.urgency
                actions: {
                    const tracked = server.trackedNotifications.values.find(t => t.id === pcard.model.notifId);
                    return tracked ? tracked.actions : (pcard.model.trackedRef ? pcard.model.trackedRef.actions : []);
                }
                // critical notifications stay until dismissed; others use the app's timeout (seconds) or 5s
                timeoutMs: model.urgency === NotificationUrgency.Critical ? 0 : (model.expireTimeout > 0 ? Math.min(30000, model.expireTimeout * 1000) : 5000)

                onExpired: notify_root.removePopup(pcard.model.notifId)
                onCloseRequested: notify_root.removePopup(pcard.model.notifId)
                onActivated: notify_root.openNotification({
                    notifId: pcard.model.notifId,
                    appName: pcard.model.appName,
                    desktopEntry: pcard.model.desktopEntry,
                    appIcon: pcard.model.appIcon,
                    url: pcard.model.url,
                    body: pcard.model.body,
                    summary: pcard.model.summary
                })
            }
        }
    }
}
