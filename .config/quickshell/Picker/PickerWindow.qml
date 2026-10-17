pragma ComponentBehavior: Bound

import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Components

Item {
    id: picker

    required property var hostWindow

    // QSP_THEME no longer picks between palettes - all colors come from the shared Colors
    // singleton. themeName/darkTheme are kept only because runSmoke() asserts they track the
    // environment.
    readonly property string themeName: String(Quickshell.env("QSP_THEME") || "light").toLowerCase()
    readonly property bool darkTheme: themeName === "dark"
    readonly property color backgroundColor: Colors.surface_container_high
    readonly property bool testMode: Quickshell.env("QSP_TEST_MODE") === "1"
    readonly property bool liveTestMode: Quickshell.env("QSP_LIVE_TEST_MODE") === "1"
    readonly property bool smokeMode: Quickshell.env("QSP_SMOKE_MODE") === "1"
        && Quickshell.env("QT_QPA_PLATFORM") === "offscreen"
    readonly property bool slurpAvailable: Quickshell.env("QSP_SLURP_AVAILABLE") === "1"
    readonly property bool regionRecovery: Quickshell.env("QSP_REGION_RECOVERY") === "1"
    readonly property bool allowTokenSelection: Quickshell.env("QSP_ALLOW_TOKEN_SELECTION") === "1"
    property var preferredScreen: null
    readonly property var session: loadSession()

    property var screenEntries: []
    property var windowEntries: []
    property var filteredWindowEntries: []
    property string windowFilterText: ""
    property bool windowFilterActive: false
    property bool windowOrderingFrozen: false
    property var identificationScreen: null
    property string identificationLabel: ""
    property bool identificationVisible: false
    property bool windowModelReady: false
    property bool finalized: false
    property bool rebuilding: false
    property int rebuildAttempts: 0

    readonly property int preferredWidth: initialWidth()
    readonly property int preferredHeight: initialHeight()

    function parseJson(text, fallback) {
        if (!text)
            return fallback;
        try {
            return JSON.parse(text);
        } catch (error) {
            return fallback;
        }
    }

    function loadSession() {
        return parseJson(sessionFile.text(), {
            "windows": [],
            "mock": {
                "enabled": false,
                "currentWorkspaceId": -1,
                "screens": [],
                "toplevels": []
            }
        });
    }

    function loadGeometry() {
        const geometry = parseJson(geometryFile.text(), {});
        return geometry.surface === "panel" ? geometry : { "width": 800, "height": 500 };
    }

    function boundedDimension(value, fallback, lower, upper) {
        const number = Number(value);
        if (!Number.isFinite(number))
            return fallback;
        return Math.max(lower, Math.min(upper, Math.round(number)));
    }

    function initialWidth() {
        const geometry = loadGeometry();
        return boundedDimension(geometry.width, 800, 640, 2400);
    }

    function initialHeight() {
        const geometry = loadGeometry();
        return boundedDimension(geometry.height, 500, 400, 1600);
    }

    function saveGeometry() {
        geometryFile.setText(JSON.stringify({
            "height": Math.round(hostWindow.height),
            "surface": "panel",
            "width": Math.round(hostWindow.width)
        }) + "\n");
    }

    function iconFor(windowClass) {
        const requested = String(windowClass || "");
        const safeName = /^[A-Za-z0-9._+-]+$/.test(requested) ? requested : "";
        if (safeName && Quickshell.hasThemeIcon(safeName))
            return Quickshell.iconPath(safeName, "application-x-executable");
        const lower = safeName.toLowerCase();
        if (lower && Quickshell.hasThemeIcon(lower))
            return Quickshell.iconPath(lower, "application-x-executable");
        return Quickshell.iconPath("application-x-executable", true);
    }

    function resolvePreferredScreen() {
        const screens = [...Quickshell.screens];
        if (screens.length === 0)
            return null;
        const focused = Hyprland.focusedMonitor;
        if (focused) {
            const match = screens.find(screen => String(screen.name) === String(focused.name));
            if (match)
                return match;
        }
        return screens[0];
    }

    function rebuildScreens() {
        const source = session.mock && session.mock.enabled
            ? session.mock.screens
            : [...Quickshell.screens];
        const result = [];
        for (let index = 0; index < source.length; ++index) {
            const screen = source[index];
            const monitor = session.mock && session.mock.enabled ? null : Hyprland.monitorFor(screen);
            const refreshRate = monitor && monitor.lastIpcObject
                ? Number(monitor.lastIpcObject["refreshRate"] || 0) : 0;
            result.push({
                "height": Number(screen.height),
                "index": index,
                "monitor": monitor,
                "name": String(screen.name),
                "refreshRate": refreshRate,
                "scale": monitor ? Number(monitor.scale) : Number(screen.scale || 1),
                "screen": session.mock && session.mock.enabled ? null : screen,
                "width": Number(screen.width),
                "x": Number(screen.x),
                "y": Number(screen.y)
            });
        }
        screenEntries = result;
        if (screenList.currentIndex < 0 && result.length > 0) {
            const preferredName = preferredScreen ? String(preferredScreen.name) : "";
            const preferredIndex = result.findIndex(entry => entry.name === preferredName);
            screenList.currentIndex = preferredIndex >= 0 ? preferredIndex : 0;
        }
    }

    function runtimeToplevels() {
        if (session.mock && session.mock.enabled)
            return session.mock.toplevels || [];
        return Hyprland.toplevels.values;
    }

    function currentWorkspaceId() {
        if (session.mock && session.mock.enabled)
            return Number(session.mock.currentWorkspaceId);
        return Hyprland.focusedWorkspace ? Number(Hyprland.focusedWorkspace.id) : -1;
    }

    function workspaceSection(workspaceId, workspaceName, isCurrent, matched) {
        if (!matched)
            return "Unavailable workspace";
        if (isCurrent)
            return "Current · " + (workspaceName || workspaceId);
        if (workspaceId > 0)
            return "Workspace " + (workspaceName || workspaceId);
        return "Special · " + (workspaceName || "workspace");
    }

    function workspaceSortCategory(workspaceId, isCurrent, matched) {
        if (isCurrent)
            return 0;
        if (matched && workspaceId > 0)
            return 1;
        if (matched)
            return 2;
        return 3;
    }

    function windowKey(entry) {
        return liveTestMode ? entry.address : entry.handle;
    }

    function refreshFilteredWindows() {
        const previous = selectedWindow();
        const previousKey = previous ? windowKey(previous) : "";
        const query = windowFilterText.trim().toLowerCase();
        const result = query ? windowEntries.filter(entry => {
            const haystack = (entry.className + " " + entry.title + " "
                + entry.workspaceName + " " + entry.workspaceId).toLowerCase();
            return haystack.includes(query);
        }) : windowEntries;
        filteredWindowEntries = result;
        let selectedIndex = result.length > 0 ? 0 : -1;
        if (previousKey) {
            const preservedIndex = result.findIndex(entry => windowKey(entry) === previousKey);
            if (preservedIndex >= 0)
                selectedIndex = preservedIndex;
        }
        windowList.currentIndex = selectedIndex;
    }

    function moveWindowSelection(direction) {
        if (direction > 0)
            windowList.incrementCurrentIndex();
        else if (direction < 0)
            windowList.decrementCurrentIndex();
    }

    function focusCurrentTab() {
        Qt.callLater(() => {
            if (tabs.currentIndex === 0)
                screenList.forceActiveFocus();
            else if (tabs.currentIndex === 1)
                (windowFilterActive ? windowFilter : windowList).forceActiveFocus();
            else
                regionButton.forceActiveFocus();
        });
    }

    function windowModelsEqual(left, right) {
        if (left.length !== right.length)
            return false;
        for (let index = 0; index < left.length; ++index) {
            const a = left[index];
            const b = right[index];
            if (a.address !== b.address || a.captureSource !== b.captureSource
                    || a.className !== b.className || a.handle !== b.handle
                    || a.matched !== b.matched || a.sourceIndex !== b.sourceIndex
                    || a.title !== b.title || a.workspaceId !== b.workspaceId
                    || a.workspaceName !== b.workspaceName || a.sectionLabel !== b.sectionLabel
                    || a.sortCategory !== b.sortCategory
                    || a.isCurrentWorkspace !== b.isCurrentWorkspace)
                return false;
        }
        return true;
    }

    function rebuildWindows() {
        if (!windowModelReady || rebuilding)
            return;
        rebuilding = true;

        try {
            const toplevels = runtimeToplevels();
            const currentWorkspace = currentWorkspaceId();
            const result = [];

            if (liveTestMode) {
                for (let index = 0; index < toplevels.length; ++index) {
                    const toplevel = toplevels[index];
                    const workspace = toplevel.workspace;
                    const workspaceId = workspace ? Number(workspace.id) : -1;
                    const wayland = toplevel.wayland;
                    result.push({
                        "address": String(toplevel.address),
                        "captureSource": wayland || null,
                        "className": String(wayland ? wayland.appId : ""),
                        "handle": String(index + 1),
                        "matched": true,
                        "sourceIndex": index,
                        "title": String(toplevel.title || (wayland ? wayland.title : "")),
                        "workspaceId": workspaceId,
                        "workspaceName": workspace ? String(workspace.name) : "",
                        "sectionLabel": workspaceSection(workspaceId, workspace ? String(workspace.name) : "",
                            workspaceId === currentWorkspace, true),
                        "sortCategory": workspaceSortCategory(workspaceId, workspaceId === currentWorkspace, true),
                        "isCurrentWorkspace": workspaceId === currentWorkspace
                    });
                }
            } else {
                const portalWindows = session.windows || [];
                for (let index = 0; index < portalWindows.length; ++index) {
                    const portalWindow = portalWindows[index];
                    let match = null;
                    for (let candidateIndex = 0; candidateIndex < toplevels.length; ++candidateIndex) {
                        const candidate = toplevels[candidateIndex];
                        if (String(candidate.address) === portalWindow.normalizedAddress) {
                            match = candidate;
                            break;
                        }
                    }

                    const workspace = match ? match.workspace : null;
                    const workspaceId = workspace ? Number(workspace.id) : -1;
                    const workspaceName = workspace ? String(workspace.name) : "";
                    let captureSource = null;
                    if (!(session.mock && session.mock.enabled) && match && match.wayland)
                        captureSource = match.wayland;

                    result.push({
                        "address": portalWindow.normalizedAddress,
                        "captureSource": captureSource,
                        "className": String(portalWindow.class || (match && match.wayland ? match.wayland.appId : "")),
                        "handle": String(portalWindow.handle),
                        "matched": match !== null,
                        "sourceIndex": Number(portalWindow.sourceIndex),
                        "title": String(portalWindow.title || (match ? match.title : "")),
                        "workspaceId": workspaceId,
                        "workspaceName": workspaceName,
                        "sectionLabel": workspaceSection(workspaceId, workspaceName,
                            workspaceId === currentWorkspace, match !== null),
                        "sortCategory": workspaceSortCategory(workspaceId,
                            workspaceId === currentWorkspace, match !== null),
                        "isCurrentWorkspace": workspaceId === currentWorkspace
                    });
                }
            }

            const previousOrder = {};
            const previousEntries = {};
            for (let index = 0; index < windowEntries.length; ++index) {
                const key = windowKey(windowEntries[index]);
                previousOrder[key] = index;
                previousEntries[key] = windowEntries[index];
            }
            if (windowOrderingFrozen) {
                for (let index = 0; index < result.length; ++index) {
                    const previousEntry = previousEntries[windowKey(result[index])];
                    if (previousEntry) {
                        result[index].sectionLabel = previousEntry.sectionLabel;
                        result[index].sortCategory = previousEntry.sortCategory;
                    }
                }
            }

            result.sort((left, right) => {
                if (windowOrderingFrozen) {
                    const leftOrder = previousOrder[windowKey(left)];
                    const rightOrder = previousOrder[windowKey(right)];
                    const leftKnown = leftOrder !== undefined;
                    const rightKnown = rightOrder !== undefined;
                    if (leftKnown !== rightKnown)
                        return leftKnown ? -1 : 1;
                    if (leftKnown && leftOrder !== rightOrder)
                        return leftOrder - rightOrder;
                }
                if (left.sortCategory !== right.sortCategory)
                    return left.sortCategory - right.sortCategory;
                if (left.sortCategory === 1 && left.workspaceId !== right.workspaceId)
                    return left.workspaceId - right.workspaceId;
                return left.sourceIndex - right.sourceIndex;
            });

            if (windowModelsEqual(windowEntries, result))
                return;

            windowEntries = result;
            refreshFilteredWindows();
        } finally {
            rebuilding = false;
        }
    }

    function requestScreenIdentification(entry) {
        if (!entry || !entry.screen || testMode || smokeMode)
            return;
        identificationScreen = entry.screen;
        const rate = entry.refreshRate > 0 ? " · " + Math.round(entry.refreshRate) + " Hz" : "";
        identificationLabel = entry.name + "\n" + entry.width + "×" + entry.height
            + " · scale " + entry.scale + rate;
        identificationVisible = false;
        identificationDelay.restart();
    }

    function selectedScreen() {
        const index = screenList.currentIndex;
        return index >= 0 && index < screenEntries.length ? screenEntries[index] : null;
    }

    function selectedWindow() {
        const index = windowList.currentIndex;
        return index >= 0 && index < filteredWindowEntries.length ? filteredWindowEntries[index] : null;
    }

    function finish(selection) {
        if (finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.visible ? restoreToken.checked : true;
        const flags = allowRestore ? "r" : "";
        resultFile.setText("[SELECTION]" + flags + "/" + selection + "\n");
        Qt.quit();
    }

    function cancel() {
        if (finalized)
            return;
        finalized = true;
        saveGeometry();
        Qt.quit();
    }

    function shareCurrent() {
        if (tabs.currentIndex === 0) {
            const screen = selectedScreen();
            if (screen)
                finish("screen:" + screen.name);
        } else if (tabs.currentIndex === 1) {
            const window = selectedWindow();
            if (window)
                finish("window:" + window.handle);
        } else {
            selectRegion();
        }
    }

    function lastRegionAvailable() {
        const region = session.lastRegion;
        if (!region)
            return false;
        const screen = screenEntries.find(entry => entry.name === region.output);
        return screen !== undefined
            && screen.width === region.outputWidth
            && screen.height === region.outputHeight
            && region.x >= 0 && region.y >= 0
            && region.width > 0 && region.height > 0
            && region.x + region.width <= screen.width
            && region.y + region.height <= screen.height;
    }

    function regionScreens() {
        return screenEntries.map(entry => ({
            "height": entry.height,
            "name": entry.name,
            "width": entry.width,
            "x": entry.x,
            "y": entry.y
        }));
    }

    function selectRegion() {
        if (!slurpAvailable || finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.visible ? restoreToken.checked : true;
        regionRequestFile.setText(JSON.stringify({
            "allowRestore": allowRestore,
            "screens": regionScreens()
        }) + "\n");
        Qt.quit();
    }

    function repeatLastRegion() {
        if (!session.lastRegion || finalized)
            return;
        finalized = true;
        saveGeometry();
        const allowRestore = restoreToken.visible ? restoreToken.checked : true;
        repeatRegionRequestFile.setText(JSON.stringify({
            "allowRestore": allowRestore,
            "region": session.lastRegion,
            "screens": regionScreens()
        }) + "\n");
        Qt.quit();
    }

    function shareEnabled() {
        if (tabs.currentIndex === 0)
            return selectedScreen() !== null;
        if (tabs.currentIndex === 1)
            return selectedWindow() !== null;
        return slurpAvailable;
    }

    function runSmoke() {
        const smokeRegion = Quickshell.env("QSP_SMOKE_REGION") === "1";
        if (Quickshell.appId !== "io.github.samsaffron.quickshell-share-picker")
            throw new Error("unexpected Quickshell app ID: " + Quickshell.appId);
        if (tabs.currentIndex !== (smokeRegion ? 2 : 1))
            throw new Error("picker did not open on the requested tab");
        if (regionRecovery !== smokeRegion)
            throw new Error("region recovery state did not follow the environment");
        if (rebuilding)
            throw new Error("window rebuild guard remained set");
        if (!windowModelReady)
            throw new Error("window model was published before it was ready");
        if ((Quickshell.env("QSP_THEME") === "dark") !== darkTheme)
            throw new Error("theme selection did not follow the environment");
        const stableEntries = windowEntries;
        rebuildWindows();
        if (windowEntries !== stableEntries)
            throw new Error("unchanged window model was unnecessarily replaced");
        if (previewRefreshTimer.interval !== 1000 || !previewRefreshTimer.repeat)
            throw new Error("selected window preview refresh timer is misconfigured");
        if (screenPreviewRefreshTimer.interval !== 1000 || !screenPreviewRefreshTimer.repeat)
            throw new Error("selected screen preview refresh timer is misconfigured");
        if (screenEntries.length > 0 && screenList.currentIndex !== 0)
            throw new Error("first screen was not selected before publication");
        if (!smokeRegion && windowEntries.length > 0) {
            windowFilterText = windowEntries[0].className.toLowerCase();
            refreshFilteredWindows();
            if (filteredWindowEntries.length === 0)
                throw new Error("window filter hid a matching entry");
            windowFilterText = "";
            refreshFilteredWindows();
            if (filteredWindowEntries.length !== windowEntries.length)
                throw new Error("clearing the window filter did not restore the model");
            const previousIndex = windowList.currentIndex;
            windowList.currentIndex = 0;
            moveWindowSelection(1);
            if (windowList.currentIndex !== Math.min(1, windowEntries.length - 1))
                throw new Error("filter-field down navigation did not move selection");
            moveWindowSelection(-1);
            if (windowList.currentIndex !== 0)
                throw new Error("filter-field up navigation did not move selection");
            windowList.currentIndex = previousIndex;
            if (!windowEntries[0].sectionLabel)
                throw new Error("window workspace section label is missing");
        }
        if (!smokeRegion && liveTestMode) {
            if (windowEntries.length !== 3 || !selectedWindow()
                    || selectedWindow().handle !== "1" || selectedWindow().address !== "abc123")
                throw new Error("live-test toplevel rebuild did not complete");
        } else if (!smokeRegion && (windowEntries.length !== 1 || !selectedWindow() || selectedWindow().handle !== "17")) {
            throw new Error("production window-list rebuild did not complete");
        }
        if (restoreToken.visible !== allowTokenSelection)
            throw new Error("restore-token visibility did not follow the environment");
        if (restoreToken.visible && !restoreToken.checked)
            throw new Error("visible restore-token checkbox did not start checked");
        if (Quickshell.env("QSP_SMOKE_UNCHECK_TOKEN") === "1")
            restoreToken.checked = false;
        shareCurrent();
    }

    Component.onCompleted: {
        preferredScreen = resolvePreferredScreen();
        rebuildScreens();
        const requestedTab = regionRecovery ? "region"
            : String(Quickshell.env("XDPH_PICKER_DEFAULT_TAB") || "window").toLowerCase();
        tabs.currentIndex = requestedTab === "screen" ? 0 : requestedTab === "region" ? 2 : 1;
        restoreToken.checked = Quickshell.env("QSP_ALLOW_TOKEN") !== "0";
        if (smokeMode) {
            windowModelReady = true;
            rebuildWindows();
            Qt.callLater(runSmoke);
        } else {
            initialWindowTimer.start();
        }
    }

    Connections {
        target: Hyprland

        function onFocusedWorkspaceChanged() {
            if (picker.windowModelReady)
                picker.rebuildWindows();
        }
    }

    Connections {
        target: Hyprland.toplevels

        function onValuesChanged() {
            if (picker.windowModelReady)
                picker.rebuildWindows();
        }
    }

    FileView {
        id: sessionFile
        path: String(Quickshell.env("QSP_SESSION_FILE") || "")
        blockLoading: true
        printErrors: true
    }

    FileView {
        id: resultFile
        path: String(Quickshell.env("QSP_RESULT_FILE") || "")
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: regionRequestFile
        path: String(Quickshell.env("QSP_REGION_REQUEST_FILE") || "")
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: repeatRegionRequestFile
        path: String(Quickshell.env("QSP_REPEAT_REGION_REQUEST_FILE") || "")
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    FileView {
        id: geometryFile
        path: String(Quickshell.env("QSP_GEOMETRY_FILE") || "")
        blockLoading: true
        blockWrites: true
        atomicWrites: true
        printErrors: false
    }

    Timer {
        id: identificationDelay
        interval: 500
        onTriggered: {
            picker.identificationVisible = true;
            identificationTimeout.restart();
        }
    }

    Timer {
        id: identificationTimeout
        interval: 1000
        onTriggered: picker.identificationVisible = false
    }

    Timer {
        id: initialWindowTimer
        interval: 250
        onTriggered: {
            picker.windowModelReady = true;
            picker.rebuildScreens();
            picker.rebuildWindows();
            picker.focusCurrentTab();
            rebuildTimer.start();
        }
    }

    Timer {
        id: rebuildTimer
        interval: 250
        repeat: true
        onTriggered: {
            picker.rebuildAttempts += 1;
            picker.rebuildScreens();
            picker.rebuildWindows();
            if (picker.rebuildAttempts >= 12)
                stop();
        }
    }

    Shortcut {
        sequences: [StandardKey.Cancel]
        onActivated: {
            if (picker.windowFilterActive) {
                picker.windowFilterText = "";
                picker.windowFilterActive = false;
                picker.refreshFilteredWindows();
                windowList.forceActiveFocus();
            } else {
                picker.cancel();
            }
        }
    }

    Shortcut {
        sequence: "Ctrl+1"
        onActivated: tabs.currentIndex = 0
    }

    Shortcut {
        sequence: "Ctrl+2"
        onActivated: tabs.currentIndex = 1
    }

    Shortcut {
        sequence: "Ctrl+3"
        onActivated: tabs.currentIndex = 2
    }

    Shortcut {
        sequence: "Ctrl+Tab"
        onActivated: tabs.currentIndex = (tabs.currentIndex + 1) % 3
    }

    Shortcut {
        sequence: "Ctrl+Shift+Tab"
        onActivated: tabs.currentIndex = (tabs.currentIndex + 2) % 3
    }

    Shortcut {
        sequence: "/"
        enabled: tabs.currentIndex === 1 && !picker.windowFilterActive
        onActivated: {
            picker.windowOrderingFrozen = true;
            picker.windowFilterActive = true;
            picker.windowFilterText = "";
            picker.refreshFilteredWindows();
            picker.focusCurrentTab();
        }
    }

    Shortcut {
        sequence: "Ctrl+Return"
        onActivated: {
            if (picker.shareEnabled())
                picker.shareCurrent();
        }
    }

    // ---------------------------------------------------------------- tab state
    // Screen / Window / Region; kept as `tabs.currentIndex` for the logic and smoke tests.
    QtObject {
        id: tabs
        property int currentIndex: 1
        onCurrentIndexChanged: if (picker.windowModelReady) picker.focusCurrentTab()
    }

    // rebuild the window list when any toplevel's identity or workspace changes
    Repeater {
        model: picker.testMode ? null : Hyprland.toplevels
        delegate: Item {
            id: associationDelegate
            required property var modelData
            visible: false
            Connections {
                target: associationDelegate.modelData
                function onAddressChanged() { picker.rebuildWindows(); }
                function onWaylandHandleChanged() { picker.rebuildWindows(); }
                function onWorkspaceChanged() { picker.rebuildWindows(); }
            }
        }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 16

        // ---- header: title + source segmented control ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Rectangle {
                implicitWidth: 48
                implicitHeight: 48
                radius: Motion.shapeLarge
                color: Colors.primary_container
                Icon { anchors.centerIn: parent; name: "screen_share"; color: Colors.on_primary_container }
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { role: "headlineSmall"; text: "Share your screen" }
                StyledText { role: "bodyMedium"; color: Colors.on_surface_variant; text: "Choose what to stream" }
            }

            Row {
                spacing: 2
                Repeater {
                    model: [["Screen", "desktop_windows"], ["Window", "web_asset"], ["Region", "crop_free"]]
                    delegate: ConnectedButton {
                        required property var modelData
                        required property int index
                        implicitHeight: 40
                        position: index === 0 ? "first" : index === 2 ? "last" : "middle"
                        icon: modelData[1]
                        text: modelData[0]
                        selected: tabs.currentIndex === index
                        onClicked: tabs.currentIndex = index
                    }
                }
            }
        }

        StackLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            currentIndex: tabs.currentIndex

            // ---------------------------------------------------------------- screens
            RowLayout {
                spacing: 16

                Rectangle {
                    Layout.preferredWidth: 280
                    Layout.minimumWidth: 220
                    Layout.maximumWidth: 300
                    Layout.fillHeight: true
                    radius: Motion.shapeLarge
                    color: Colors.surface_container

                    ListView {
                        id: screenList
                        anchors.fill: parent
                        anchors.margins: 4
                        clip: true
                        spacing: 2
                        model: picker.screenEntries
                        activeFocusOnTab: true
                        keyNavigationEnabled: true
                        boundsBehavior: Flickable.StopAtBounds
                        Keys.onReturnPressed: event => {
                            if (picker.selectedScreen())
                                picker.shareCurrent();
                            event.accepted = true;
                        }
                        highlightFollowsCurrentItem: false
                        ScrollIntoView { view: screenList }
                        highlight: Rectangle {
                            width: screenList.width
                            height: 64
                            radius: Motion.shapeLarge
                            color: Colors.secondary_container
                            y: screenList.currentItem ? screenList.currentItem.y : 0
                            visible: screenList.count > 0
                            Behavior on y { Spring {} }
                        }

                        delegate: Clickable {
                            id: screenItem
                            required property var modelData
                            required property int index
                            readonly property bool current: ListView.isCurrentItem

                            width: screenList.width
                            height: 64
                            restRadius: Motion.shapeLarge
                            pressedRadius: Motion.shapeSmall
                            contentColor: current ? Colors.on_secondary_container : Colors.on_surface
                            onClicked: {
                                screenList.currentIndex = index;
                                picker.requestScreenIdentification(modelData);
                            }
                            onHoveredChanged: if (hovered) picker.requestScreenIdentification(modelData)
                            Connections {
                                target: screenItem.mouseArea
                                function onDoubleClicked() {
                                    screenList.currentIndex = screenItem.index;
                                    picker.finish("screen:" + screenItem.modelData.name);
                                }
                            }

                            RowLayout {
                                anchors.fill: parent
                                anchors.leftMargin: 16
                                anchors.rightMargin: 16
                                spacing: 16
                                Icon {
                                    name: "desktop_windows"
                                    color: screenItem.current ? Colors.on_secondary_container : Colors.on_surface_variant
                                }
                                ColumnLayout {
                                    Layout.fillWidth: true
                                    spacing: 0
                                    StyledText {
                                        Layout.fillWidth: true
                                        role: "bodyLarge"
                                        color: screenItem.contentColor
                                        elide: Text.ElideRight
                                        text: screenItem.modelData.name
                                    }
                                    StyledText {
                                        Layout.fillWidth: true
                                        role: "bodyMedium"
                                        color: screenItem.current ? Colors.on_secondary_container : Colors.on_surface_variant
                                        elide: Text.ElideRight
                                        text: screenItem.modelData.width + "×" + screenItem.modelData.height + " at " + screenItem.modelData.x + ", " + screenItem.modelData.y
                                    }
                                }
                            }
                        }
                    }
                }

                Rectangle {
                    id: screenPreviewFrame
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    Layout.minimumWidth: 200
                    radius: Motion.shapeLarge
                    color: Colors.surface_container_lowest
                    clip: true

                    readonly property var selection: picker.selectedScreen()
                    readonly property real sourceRatio: screenPreview.sourceSize.height > 0 ? screenPreview.sourceSize.width / screenPreview.sourceSize.height : 1

                    ScreencopyView {
                        id: screenPreview
                        anchors.centerIn: parent
                        captureSource: screenPreviewFrame.selection ? screenPreviewFrame.selection.screen : null
                        live: false
                        paintCursor: false
                        width: hasContent ? Math.min(screenPreviewFrame.width, screenPreviewFrame.height * screenPreviewFrame.sourceRatio) : 0
                        height: hasContent ? width / screenPreviewFrame.sourceRatio : 0
                    }
                    Timer {
                        id: screenPreviewRefreshTimer
                        interval: 1000
                        repeat: true
                        running: picker.windowModelReady && tabs.currentIndex === 0 && screenPreview.captureSource !== null
                        onTriggered: screenPreview.captureFrame()
                    }

                    PreviewPlaceholder {
                        visible: !screenPreview.hasContent
                        loading: !!screenPreviewFrame.selection && !!screenPreview.captureSource
                        text: !screenPreviewFrame.selection ? "Select a screen to preview"
                            : picker.testMode ? "Preview unavailable in mock mode"
                            : !screenPreviewFrame.selection.screen ? "No preview available"
                            : "Loading preview…"
                    }

                    PreviewCaption {
                        visible: screenPreviewFrame.selection !== null
                        icon: "desktop_windows"
                        title: screenPreviewFrame.selection ? screenPreviewFrame.selection.name : ""
                        subtitle: screenPreviewFrame.selection
                            ? screenPreviewFrame.selection.width + "×" + screenPreviewFrame.selection.height + " · scale " + screenPreviewFrame.selection.scale
                                + (screenPreviewFrame.selection.refreshRate > 0 ? " · " + Math.round(screenPreviewFrame.selection.refreshRate) + " Hz" : "")
                            : ""
                    }
                }
            }

            // ---------------------------------------------------------------- windows
            RowLayout {
                spacing: 16

                Rectangle {
                    Layout.preferredWidth: 300
                    Layout.minimumWidth: 220
                    Layout.maximumWidth: 320
                    Layout.fillHeight: true
                    radius: Motion.shapeLarge
                    color: Colors.surface_container

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 4
                        spacing: 4

                        RowLayout {
                            Layout.fillWidth: true
                            visible: picker.windowFilterActive
                            spacing: 8

                            TextField {
                                id: windowFilter
                                Layout.fillWidth: true
                                label: "Filter windows"
                                leadingIcon: "search"
                                text: picker.windowFilterText
                                onEdited: text => {
                                    picker.windowFilterText = text;
                                    picker.refreshFilteredWindows();
                                }
                                onAccepted: {
                                    if (picker.selectedWindow())
                                        picker.shareCurrent();
                                }
                                Keys.onDownPressed: event => {
                                    picker.moveWindowSelection(1);
                                    event.accepted = true;
                                }
                                Keys.onUpPressed: event => {
                                    picker.moveWindowSelection(-1);
                                    event.accepted = true;
                                }
                                Keys.onEscapePressed: event => {
                                    if (text.length > 0) {
                                        text = "";
                                        picker.windowFilterText = "";
                                        picker.refreshFilteredWindows();
                                    } else {
                                        picker.windowFilterActive = false;
                                        windowList.forceActiveFocus();
                                    }
                                    event.accepted = true;
                                }
                            }
                            StyledText {
                                Layout.rightMargin: 8
                                role: "labelMedium"
                                color: Colors.on_surface_variant
                                text: picker.filteredWindowEntries.length + " / " + picker.windowEntries.length
                            }
                        }

                        ListView {
                            id: windowList
                            Layout.fillWidth: true
                            Layout.fillHeight: true
                            clip: true
                            spacing: 2
                            model: picker.filteredWindowEntries
                            activeFocusOnTab: true
                            keyNavigationEnabled: true
                            boundsBehavior: Flickable.StopAtBounds
                            section.property: "sectionLabel"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                required property string section
                                width: windowList.width
                                height: 36
                                StyledText {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    anchors.leftMargin: 16
                                    anchors.bottomMargin: 6
                                    role: "labelLarge"
                                    color: Colors.primary
                                    elide: Text.ElideRight
                                    text: parent.section
                                }
                            }
                            Keys.onReturnPressed: event => {
                                picker.windowOrderingFrozen = true;
                                if (picker.selectedWindow())
                                    picker.shareCurrent();
                                event.accepted = true;
                            }
                            highlightFollowsCurrentItem: false
                            ScrollIntoView { view: windowList }
                            highlight: Rectangle {
                                width: windowList.width
                                height: 56
                                radius: Motion.shapeLarge
                                color: Colors.secondary_container
                                y: windowList.currentItem ? windowList.currentItem.y : 0
                                visible: windowList.count > 0
                                Behavior on y { Spring {} }
                            }

                            delegate: Clickable {
                                id: windowItem
                                required property var modelData
                                required property int index
                                readonly property bool current: ListView.isCurrentItem

                                width: windowList.width
                                height: 56
                                restRadius: Motion.shapeLarge
                                pressedRadius: Motion.shapeSmall
                                contentColor: current ? Colors.on_secondary_container : Colors.on_surface
                                onClicked: {
                                    picker.windowOrderingFrozen = true;
                                    windowList.currentIndex = index;
                                }
                                Connections {
                                    target: windowItem.mouseArea
                                    function onDoubleClicked() {
                                        picker.windowOrderingFrozen = true;
                                        windowList.currentIndex = windowItem.index;
                                        picker.finish("window:" + windowItem.modelData.handle);
                                    }
                                }

                                RowLayout {
                                    anchors.fill: parent
                                    anchors.leftMargin: 16
                                    anchors.rightMargin: 12
                                    spacing: 16
                                    Image {
                                        Layout.preferredWidth: 24
                                        Layout.preferredHeight: 24
                                        sourceSize: Qt.size(48, 48)
                                        fillMode: Image.PreserveAspectFit
                                        source: picker.iconFor(windowItem.modelData.className)
                                    }
                                    ColumnLayout {
                                        Layout.fillWidth: true
                                        spacing: 0
                                        StyledText {
                                            id: windowTitle
                                            Layout.fillWidth: true
                                            role: "bodyLarge"
                                            color: windowItem.contentColor
                                            elide: Text.ElideRight
                                            text: windowItem.modelData.title || windowItem.modelData.className
                                        }
                                        StyledText {
                                            Layout.fillWidth: true
                                            role: "bodySmall"
                                            color: windowItem.current ? Colors.on_secondary_container : Colors.on_surface_variant
                                            elide: Text.ElideRight
                                            text: windowItem.modelData.className + (windowItem.modelData.matched ? "" : " · no preview")
                                        }
                                    }
                                }

                                // full title as an M3 plain tooltip when truncated
                                Rectangle {
                                    readonly property bool shown: windowItem.hovered && windowTitle.truncated && tipDelay.done
                                    x: 16
                                    y: windowItem.height + 4
                                    z: 10
                                    width: Math.min(420, tipText.implicitWidth + 16)
                                    height: tipText.implicitHeight + 8
                                    radius: Motion.shapeExtraSmall
                                    color: Colors.inverse_surface
                                    opacity: shown ? 1 : 0
                                    visible: opacity > 0
                                    Behavior on opacity { Fade {} }
                                    StyledText {
                                        id: tipText
                                        x: 8
                                        y: 4
                                        width: Math.min(implicitWidth, 404)
                                        role: "bodySmall"
                                        color: Colors.inverse_on_surface
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 3
                                        text: windowTitle.text
                                    }
                                    Timer {
                                        id: tipDelay
                                        property bool done: false
                                        interval: 650
                                        running: windowItem.hovered
                                        onRunningChanged: if (!running) done = false
                                        onTriggered: done = true
                                    }
                                }
                            }

                            StyledText {
                                anchors.centerIn: parent
                                width: parent.width - 32
                                horizontalAlignment: Text.AlignHCenter
                                wrapMode: Text.WordWrap
                                role: "bodyLarge"
                                color: Colors.on_surface_variant
                                visible: picker.filteredWindowEntries.length === 0
                                text: picker.windowFilterText ? "No windows match this filter" : "No shareable windows\nTry Screen or Region"
                            }
                        }
                    }
                }

                Rectangle {
                    id: previewFrame
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    radius: Motion.shapeLarge
                    color: Colors.surface_container_lowest
                    clip: true

                    readonly property var selection: picker.selectedWindow()
                    readonly property real sourceRatio: preview.sourceSize.height > 0 ? preview.sourceSize.width / preview.sourceSize.height : 1

                    ScreencopyView {
                        id: preview
                        anchors.centerIn: parent
                        captureSource: previewFrame.selection ? previewFrame.selection.captureSource : null
                        live: false
                        paintCursor: false
                        width: hasContent ? Math.min(previewFrame.width, previewFrame.height * previewFrame.sourceRatio) : 0
                        height: hasContent ? width / previewFrame.sourceRatio : 0
                    }
                    Timer {
                        id: previewRefreshTimer
                        interval: 1000
                        repeat: true
                        running: picker.windowModelReady && tabs.currentIndex === 1 && preview.captureSource !== null
                        onTriggered: preview.captureFrame()
                    }

                    PreviewPlaceholder {
                        visible: !preview.hasContent
                        loading: !!previewFrame.selection && !!preview.captureSource
                        text: !previewFrame.selection ? "Select a window to preview"
                            : picker.testMode ? "Preview unavailable in mock mode"
                            : !previewFrame.selection.matched || !previewFrame.selection.captureSource ? "No preview available"
                            : "Loading preview…"
                    }

                    PreviewCaption {
                        visible: previewFrame.selection !== null
                        image: previewFrame.selection ? picker.iconFor(previewFrame.selection.className) : ""
                        title: previewFrame.selection ? previewFrame.selection.className : ""
                        subtitle: previewFrame.selection ? previewFrame.selection.title : ""
                    }
                }
            }

            // ---------------------------------------------------------------- region
            Item {
                Rectangle {
                    anchors.centerIn: parent
                    width: Math.min(520, parent.width)
                    height: regionCol.implicitHeight + 48
                    radius: Motion.shapeExtraLarge
                    color: Colors.surface_container

                    ColumnLayout {
                        id: regionCol
                        anchors.centerIn: parent
                        width: parent.width - 48
                        spacing: 16

                        Rectangle {
                            Layout.alignment: Qt.AlignHCenter
                            implicitWidth: 72
                            implicitHeight: 72
                            radius: Motion.shapeExtraLarge
                            color: Colors.primary_container
                            Icon { anchors.centerIn: parent; name: "crop_free"; size: 36; color: Colors.on_primary_container }
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            role: "headlineSmall"
                            text: "Share a region"
                        }
                        StyledText {
                            Layout.fillWidth: true
                            horizontalAlignment: Text.AlignHCenter
                            wrapMode: Text.WordWrap
                            role: "bodyMedium"
                            color: picker.regionRecovery ? Colors.error : Colors.on_surface_variant
                            text: picker.regionRecovery
                                ? "Region selection was canceled. Choose again, repeat the last region, or use another tab."
                                : "Drag a rectangle anywhere on your screens to share only that part."
                        }
                        Button {
                            id: regionButton
                            Layout.alignment: Qt.AlignHCenter
                            size: "m"
                            icon: "crop_free"
                            enabled: picker.slurpAvailable
                            text: picker.slurpAvailable ? "Select region" : "Select region (slurp is not installed)"
                            onClicked: picker.selectRegion()
                        }
                        Button {
                            Layout.alignment: Qt.AlignHCenter
                            visible: picker.lastRegionAvailable()
                            style: "tonal"
                            icon: "replay"
                            text: picker.session.lastRegion
                                ? "Repeat " + picker.session.lastRegion.output + " · " + picker.session.lastRegion.width + "×" + picker.session.lastRegion.height
                                : "Repeat last region"
                            onClicked: picker.repeatLastRegion()
                        }
                    }
                }
            }
        }

        // ---- footer ----
        RowLayout {
            Layout.fillWidth: true
            spacing: 16

            Item {
                id: restoreToken
                property bool checked: true
                visible: picker.allowTokenSelection
                implicitWidth: tokenRow.implicitWidth
                implicitHeight: tokenRow.implicitHeight
                Row {
                    id: tokenRow
                    spacing: 12
                    Switch {
                        anchors.verticalCenter: parent.verticalCenter
                        checked: restoreToken.checked
                        onToggled: restoreToken.checked = !restoreToken.checked
                    }
                    ColumnLayout {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 0
                        StyledText { role: "bodyLarge"; text: "Remember this choice" }
                        StyledText { role: "bodySmall"; color: Colors.on_surface_variant; text: "Gives the app a restore token so it can skip this picker" }
                    }
                }
            }

            StyledText {
                visible: !restoreToken.visible
                Layout.fillWidth: true
                role: "bodySmall"
                color: Colors.on_surface_variant
                elide: Text.ElideRight
                text: tabs.currentIndex === 1
                    ? "↑↓ select · Enter share · / filter · Ctrl+1–3 tabs · Esc cancel"
                    : "↑↓ select · Enter share · Ctrl+1–3 tabs · Esc cancel"
            }
            Item { visible: restoreToken.visible; Layout.fillWidth: true }

            Button {
                style: "text"
                text: "Cancel"
                onClicked: picker.cancel()
            }
            Button {
                icon: "screen_share"
                text: "Share"
                enabled: picker.shareEnabled()
                onClicked: picker.shareCurrent()
            }
        }
    }

    // preview pane placeholder: loading indicator or message
    component PreviewPlaceholder: Column {
        id: placeholder
        property bool loading
        property string text
        anchors.centerIn: parent
        spacing: 16
        LoadingIndicator {
            anchors.horizontalCenter: parent.horizontalCenter
            visible: placeholder.loading
            running: visible && placeholder.visible
        }
        StyledText {
            anchors.horizontalCenter: parent.horizontalCenter
            role: "bodyLarge"
            color: Colors.on_surface_variant
            text: placeholder.text
        }
    }

    // caption chip floating over the bottom of a preview
    component PreviewCaption: Rectangle {
        id: caption
        property string icon
        property string image
        property string title
        property string subtitle
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.margins: 12
        height: 64
        radius: Motion.shapeLarge
        color: Qt.alpha(Colors.surface_container_highest, 0.94)

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 16
            anchors.rightMargin: 16
            spacing: 16
            Icon {
                visible: caption.icon !== ""
                name: caption.icon
                color: Colors.primary
            }
            Image {
                visible: caption.image !== ""
                Layout.preferredWidth: 32
                Layout.preferredHeight: 32
                sourceSize: Qt.size(64, 64)
                fillMode: Image.PreserveAspectFit
                source: caption.image
            }
            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText { Layout.fillWidth: true; role: "titleSmall"; elide: Text.ElideRight; text: caption.title }
                StyledText {
                    Layout.fillWidth: true
                    role: "bodySmall"
                    color: Colors.on_surface_variant
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.Wrap
                    text: caption.subtitle
                }
            }
        }
    }
}
