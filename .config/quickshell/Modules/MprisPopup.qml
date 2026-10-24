pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Effects
import QtQuick.Shapes
import Quickshell
import Quickshell.Io
import Quickshell.Hyprland
import Quickshell.Services.Mpris
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components

// Now playing: cookie-shaped spinning artwork (drag or scroll it to seek), wavy progress,
// an M3 Expressive button group for transport, and an attached lyrics pane.
PanelWindow {
    id: win

    property var player: null
    property bool hasPlayer: !!player
    property real discSpinSpeed: 0.62
    property bool isOpen: false
    property bool showLyrics: false
    readonly property bool playing: hasPlayer && player.playbackState === MprisPlaybackState.Playing

    function formatTime(seconds) {
        if (isNaN(seconds) || seconds < 0)
            return "0:00";
        const s = Math.floor(seconds % 60);
        return Math.floor(seconds / 60) + ":" + (s < 10 ? "0" : "") + s;
    }

    // ---- entrance: the pieces pop in one after another (reset once the window is hidden) ----
    property int stage: 0
    onVisibleChanged: if (!visible) stage = 0
    Timer {
        id: stageTimer
        interval: 75
        repeat: true
        onTriggered: {
            win.stage += 1;
            if (win.stage >= 6)
                stop();
        }
    }

    // ---- track change: disc outline and halo morph with overshoot, the text slides over ----
    readonly property string titleNow: hasPlayer && player.trackTitle ? player.trackTitle : "No media"
    readonly property string artistNow: hasPlayer ? (player.trackArtist || "") : ""
    readonly property string trackKey: titleNow + "\n" + artistNow
    property string shownTitle: titleNow
    property string shownArtist: artistNow
    property int slideDir: 1                 // 1 sends the old text left, -1 right
    property int nextDir: 1                  // set by "previous" so the next change slides the other way
    readonly property var discLobes: [12, 9, 7, 10, 8]
    readonly property var haloShapes: ["cookie4", "flower", "softBurst", "clover4", "gem", "cookie9"]
    property int trackCount: 0
    property int lobes: 12
    property int fromLobes: 12
    property var haloShape: "cookie9"
    property var haloFrom: "cookie9"
    property real shapeMorph: 1
    property bool shapeSpring: true
    property real haloSpin: 0
    // a quarter turn per change, accumulated so the outline never jumps back
    readonly property real shapeTurn: trackCount * 90 + shapeMorph * 90

    Behavior on shapeMorph {
        enabled: win.shapeSpring
        SpringAnimation { spring: 3.4; damping: 0.17; epsilon: 0.001 }
    }

    onTrackKeyChanged: {
        if (!isOpen) {
            shownTitle = titleNow;
            shownArtist = artistNow;
            return;
        }
        slideDir = nextDir;
        nextDir = 1;
        textSwap.restart();
        trackCount += 1;
        fromLobes = lobes;
        lobes = discLobes[trackCount % discLobes.length];
        haloFrom = haloShape;
        haloShape = haloShapes[trackCount % haloShapes.length];
        shapeSpring = false;
        shapeMorph = 0;
        shapeSpring = true;
        shapeMorph = 1;
        discContainer.squishSpring = false;
        discContainer.squish = 0.78;
        discContainer.squishSpring = true;
        discContainer.squish = 1;
    }

    FrameAnimation {
        running: win.playing && win.isOpen
        onTriggered: win.haloSpin = (win.haloSpin - frameTime * 9) % 360
    }

    onPlayingChanged: {
        if (!isOpen)
            return;
        play.spinSpring = false;
        play.iconRotation = -90;
        play.iconScale = 0.4;
        play.spinSpring = true;
        play.iconRotation = 0;
        play.iconScale = 1;
    }

    onIsOpenChanged: {
        if (isOpen) {
            shownTitle = titleNow;
            shownArtist = artistNow;
            stage = 0;
            stageTimer.restart();
            showLyrics = lyricViewer.hasLyrics && !lyricViewer.loading;
        } else {
            // commit any in-flight scrub so the seek isn't lost and playback resumes
            if (discMouseArea.wheelSeeking)
                discMouseArea.commitWheel();
            if (discMouseArea.isDragging)
                discMouseArea.endDrag();
        }
    }

    WlrLayershell.namespace: "quickshell:mpris_popup"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: isOpen ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.None
    visible: (isOpen || panel.opacity > 0) && hasPlayer
    color: "transparent"
    anchors { top: true; left: true; right: true }
    exclusiveZone: 0
    implicitHeight: panel.height + 32
    mask: Region {
        x: Math.round(panel.x)
        y: Math.round(panel.y)
        width: Math.round(panel.width)
        height: Math.round(panel.height)
    }

    IpcHandler {
        target: "mprispopup"
        function open(): void { win.isOpen = true; }
        function close(): void { win.isOpen = false; }
        function toggle(): void { win.isOpen = !win.isOpen; }
    }

    HyprlandFocusGrab {
        windows: [win]
        active: win.visible && win.isOpen
        onCleared: win.isOpen = false
    }

    Elevation {
        anchors.fill: panel
        radius: panel.radius
        level: 3
        opacity: panel.opacity
        scale: panel.scale
        transformOrigin: Item.Top
    }

    ClippingRectangle {
        id: panel
        anchors.horizontalCenter: parent.horizontalCenter
        y: 4
        width: 360 + (win.showLyrics ? 400 : 0)
        height: 520
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container
        transformOrigin: Item.Top
        opacity: 0
        scale: 0.9
        Behavior on width { Spring { speed: "default" } }

        states: State {
            name: "open"
            when: win.isOpen
            PropertyChanges { panel.opacity: 1; panel.scale: 1 }
        }
        transitions: [
            Transition {
                to: "open"
                Spring { property: "scale"; speed: "default" }
                Fade { property: "opacity"; speed: "default" }
            },
            Transition {
                from: "open"
                NumberAnimation { property: "scale"; duration: Motion.short4; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
                NumberAnimation { property: "opacity"; duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.standardAccelerate }
            }
        ]

        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onWheel: wheel => wheel.accepted = true
        }

        Item {
            anchors.fill: parent
            focus: win.isOpen
            Keys.onEscapePressed: win.isOpen = false
        }

        // ---- blurred artwork backdrop, cross-faded between tracks ----
        Item {
            id: backdrop
            anchors.fill: parent
            layer.enabled: true
            layer.effect: MultiEffect {
                blurEnabled: true
                blur: 0.9
                blurMax: 32
                saturation: 0.3
            }

            readonly property string target: win.hasPlayer && win.player.trackArtUrl ? win.player.trackArtUrl : ""
            property bool useA: true
            onTargetChanged: {
                const next = useA ? artB : artA;
                next.source = target;
                if (!target || next.status === Image.Ready)
                    useA = !useA;
            }
            Component.onCompleted: artA.source = target

            Image {
                id: artA
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(256, 256)
                opacity: backdrop.useA && source != "" ? 1 : 0
                Behavior on opacity { Fade { speed: "slow" } }
                onStatusChanged: if (status === Image.Ready && !backdrop.useA && source == backdrop.target) backdrop.useA = true
            }
            Image {
                id: artB
                anchors.fill: parent
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                sourceSize: Qt.size(256, 256)
                opacity: !backdrop.useA && source != "" ? 1 : 0
                Behavior on opacity { Fade { speed: "slow" } }
                onStatusChanged: if (status === Image.Ready && backdrop.useA && source == backdrop.target) backdrop.useA = false
            }
        }
        // surface scrim keeps on-surface content legible over any artwork
        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: Qt.alpha(Colors.surface_container, 0.35) }
                GradientStop { position: 0.5; color: Qt.alpha(Colors.surface_container, 0.6) }
                GradientStop { position: 1.0; color: Qt.alpha(Colors.surface_container, 0.85) }
            }
        }

        // ---------------------------------------------------------------- player
        Item {
            id: playerPane
            width: 360
            height: parent.height

            IconButton {
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 12
                z: 10
                icon: "lyrics"
                checkable: true
                checked: win.showLyrics
                enabled: lyricViewer.hasLyrics && !lyricViewer.loading
                opacity: win.stage >= 2 ? 1 : 0
                iconScale: win.stage >= 2 ? 1 : 0.4
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on iconScale { Spring {} }
                onClicked: win.showLyrics = !win.showLyrics
            }

            // which player this is
            Rectangle {
                x: 12
                y: 12
                z: 10
                height: 40
                width: Math.min(176, chipRow.implicitWidth + 28)
                radius: height / 2
                color: Colors.surface_container_highest
                visible: win.hasPlayer
                opacity: win.stage >= 2 ? 1 : 0
                scale: win.stage >= 2 ? 1 : 0.7
                transformOrigin: Item.Left
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on scale { Spring {} }
                Row {
                    id: chipRow
                    anchors.centerIn: parent
                    spacing: 6
                    Icon { anchors.verticalCenter: parent.verticalCenter; name: "music_note"; size: 18; color: Colors.primary }
                    StyledText {
                        anchors.verticalCenter: parent.verticalCenter
                        width: Math.min(implicitWidth, 176 - 28 - 24)
                        elide: Text.ElideRight
                        role: "labelLarge"
                        emphasized: true
                        color: Colors.on_surface
                        text: win.hasPlayer ? win.player.identity : ""
                    }
                }
            }

            // turning halo behind the disc; takes the next shape on every track change
            MorphShape {
                id: halo
                width: 296
                height: 296
                anchors.horizontalCenter: discContainer.horizontalCenter
                anchors.verticalCenter: discContainer.verticalCenter
                shape: win.haloShape
                fromShape: win.haloFrom
                morph: win.shapeMorph
                spin: win.haloSpin + win.trackCount * 90
                color: Qt.alpha(Colors.primary_container, 0.55)
                opacity: win.stage >= 1 ? 1 : 0
                scale: (win.stage >= 1 ? (win.playing ? (discMouseArea.isScrubbing ? 1.04 : 1) : 0.92) : 0.5)
                Behavior on opacity { Fade { speed: "slow" } }
                Behavior on scale { Spring { speed: "default" } }
            }

            Item {
                id: discContainer
                width: 248
                height: 248
                anchors.horizontalCenter: parent.horizontalCenter
                y: 28
                // entrance pop, track-change squish and drag press are separate so they don't smooth each other
                property real pop: win.stage >= 1 ? 1 : 0.6
                property real squish: 1
                property bool squishSpring: true
                property real press: discMouseArea.isDragging ? 0.96 : 1
                scale: pop * squish * press
                rotation: (1 - pop) * -150
                opacity: win.stage >= 1 ? 1 : 0
                Behavior on pop { Spring { speed: "default" } }
                Behavior on press { Spring {} }
                Behavior on opacity { Fade { speed: "default" } }
                Behavior on squish {
                    enabled: discContainer.squishSpring
                    Spring {}
                }

                // M3 Expressive cookie shape, used as the artwork mask
                Item {
                    id: discMask
                    anchors.fill: parent
                    visible: false
                    layer.enabled: true
                    layer.smooth: true

                    Shape {
                        id: waveShape
                        anchors.fill: parent
                        preferredRendererType: Shape.CurveRenderer
                        transform: Rotation {
                            origin.x: waveShape.width / 2
                            origin.y: waveShape.height / 2
                            angle: discMouseArea.stretch + win.shapeTurn
                        }

                        property real amp: discMouseArea.isScrubbing ? (discMouseArea.isAtBoundary ? 3 : 8) : (win.playing ? 6 : 2)
                        Behavior on amp { Spring {} }

                        ShapePath {
                            fillColor: "white"
                            strokeColor: "transparent"
                            strokeWidth: 0
                            PathPolyline {
                                path: {
                                    const cx = waveShape.width / 2, cy = waveShape.height / 2;
                                    const base = Math.min(cx, cy) - waveShape.amp - 1;
                                    const pts = [];
                                    for (let i = 0; i <= 240; i++) {
                                        const t = i / 240 * Math.PI * 2;
                                        const m = win.shapeMorph;
                                        const r = base + waveShape.amp * ((1 - m) * Math.cos(win.fromLobes * t) + m * Math.cos(win.lobes * t));
                                        pts.push(Qt.point(cx + r * Math.cos(t), cy + r * Math.sin(t)));
                                    }
                                    return pts;
                                }
                            }
                        }
                    }
                }

                Item {
                    anchors.fill: parent
                    layer.enabled: true
                    layer.smooth: true
                    layer.effect: MultiEffect {
                        maskEnabled: true
                        maskSource: discMask
                        maskThresholdMin: 0.5
                        maskSpreadAtMin: 1.0
                    }

                    Item {
                        id: discImage
                        anchors.centerIn: parent
                        width: Math.ceil(discContainer.width * 1.42)
                        height: Math.ceil(discContainer.height * 1.42)
                        transform: Rotation {
                            origin.x: discImage.width / 2
                            origin.y: discImage.height / 2
                            angle: discMouseArea.stretch
                        }

                        Rectangle {
                            anchors.fill: parent
                            z: 5
                            color: Colors.primary_container
                            opacity: discImage.target === "" ? 1 : 0
                            visible: opacity > 0
                            Behavior on opacity { Fade {} }
                            Icon {
                                anchors.centerIn: parent
                                name: "music_note"
                                size: 64
                                color: Colors.on_primary_container
                            }
                        }

                        // two covers: the new one fades in over the old one once it has loaded
                        readonly property string target: win.hasPlayer && win.player.trackArtUrl ? win.player.trackArtUrl : ""
                        property bool topIsA: true
                        property var pending: null
                        function swapIn(next) {
                            const prev = next === coverA ? coverB : coverA;
                            pending = null;
                            prev.z = 1;
                            next.z = 2;
                            next.opacity = 0;
                            coverFade.target = next;
                            coverFade.restart();
                            topIsA = next === coverA;
                        }
                        onTargetChanged: {
                            if (target === "") {
                                pending = null;
                                return;
                            }
                            const next = topIsA ? coverB : coverA;
                            pending = next;
                            next.source = target;
                            if (next.status === Image.Ready)
                                swapIn(next);
                        }
                        Component.onCompleted: if (target !== "") coverA.source = target
                        NumberAnimation {
                            id: coverFade
                            property: "opacity"
                            to: 1
                            duration: Motion.expressiveDefaultEffectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveDefaultEffects
                        }

                        Image {
                            id: coverA
                            anchors.fill: parent
                            z: 2
                            sourceSize: Qt.size(512, 512)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: if (status === Image.Ready && discImage.pending === coverA) discImage.swapIn(coverA)
                        }
                        Image {
                            id: coverB
                            anchors.fill: parent
                            z: 1
                            sourceSize: Qt.size(512, 512)
                            fillMode: Image.PreserveAspectCrop
                            asynchronous: true
                            onStatusChanged: if (status === Image.Ready && discImage.pending === coverB) discImage.swapIn(coverB)
                        }
                    }
                }

                // spin while playing and visible; wave rotates the other way
                FrameAnimation {
                    running: win.playing && win.isOpen && !discMouseArea.isScrubbing
                    onTriggered: {
                        discImage.rotation = (discImage.rotation + frameTime * win.discSpinSpeed / 0.030) % 360;
                        waveShape.rotation = (waveShape.rotation - frameTime * 14) % 360;
                    }
                }

                MouseArea {
                    id: discMouseArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: (!win.hasPlayer || !win.player || win.player.length <= 0)
                        ? Qt.ArrowCursor
                        : (isDragging ? Qt.ClosedHandCursor : Qt.OpenHandCursor)

                    property real lastAngle: 0
                    property real initialRotation: 0
                    property real initialWaveRotation: 0
                    // Raw (capped) drag rotation; any excess past a boundary drives the rubber-band stretch
                    property real accumulatedDelta: 0
                    property real startPosition: 0
                    property real previewPosition: 0
                    property bool isDragging: false
                    property bool wasPlaying: false
                    property bool hasMoved: false
                    property bool wheelSeeking: false
                    property bool isAtBeginning: false
                    property bool isAtEnd: false
                    readonly property bool isAtBoundary: isAtBeginning || isAtEnd
                    readonly property bool isScrubbing: isDragging || wheelSeeking
                    readonly property real seekDeltaSec: previewPosition - startPosition

                    // Rubber-band overscroll (degrees), applied as a separate transform on disc + wave
                    property real stretch: 0
                    readonly property real stretchMax: 16
                    readonly property real stretchFalloff: 32
                    readonly property real overscrollCap: 96
                    // Travel (degrees) needed to leave a boundary; acts as a small detent and stops flicker
                    readonly property real boundaryHysteresis: 4
                    // One-shot pulse applied to the badge when a boundary is reached
                    property real boundaryPulse: 1.0

                    // Spring back with the expressive default spatial spring (slight overshoot = settle wobble)
                    Behavior on stretch {
                        enabled: !discMouseArea.isDragging && !stretchKick.running
                        NumberAnimation {
                            duration: Motion.expressiveDefaultSpatialDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveDefaultSpatial
                        }
                    }

                    // Wheel hitting a boundary: push into the end, then spring back
                    SequentialAnimation {
                        id: stretchKick
                        property real kickTo: 0
                        NumberAnimation {
                            target: discMouseArea
                            property: "stretch"
                            to: stretchKick.kickTo
                            duration: Motion.expressiveFastEffectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveFastEffects
                        }
                        NumberAnimation {
                            target: discMouseArea
                            property: "stretch"
                            to: 0
                            duration: Motion.expressiveDefaultSpatialDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveDefaultSpatial
                        }
                    }

                    SequentialAnimation {
                        id: boundaryPulseAnim
                        NumberAnimation {
                            target: discMouseArea
                            property: "boundaryPulse"
                            to: 1.1
                            duration: Motion.expressiveFastEffectsDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveFastEffects
                        }
                        NumberAnimation {
                            target: discMouseArea
                            property: "boundaryPulse"
                            to: 1.0
                            duration: Motion.expressiveFastSpatialDuration
                            easing.type: Easing.BezierSpline
                            easing.bezierCurve: Motion.expressiveFastSpatial
                        }
                    }

                    onIsAtBoundaryChanged: {
                        if (isAtBoundary && isScrubbing)
                            boundaryPulseAnim.restart();
                    }

                    function getAngle(x, y) {
                        var cx = discContainer.width / 2;
                        var cy = discContainer.height / 2;
                        var angle = Math.atan2(y - cy, x - cx) * 180 / Math.PI;
                        return angle < 0 ? angle + 360 : angle;
                    }

                    function formatDelta(deltaSec) {
                        if (isNaN(deltaSec) || Math.abs(deltaSec) < 0.5) return "";
                        var sign = deltaSec > 0 ? "+" : "-";
                        var absSec = Math.round(Math.abs(deltaSec));
                        var m = Math.floor(absSec / 60);
                        var s = absSec % 60;
                        if (m > 0) {
                            return sign + m + ":" + (s < 10 ? "0" + s : s);
                        }
                        return sign + s + "s";
                    }

                    // Asymptotic resistance: approaches stretchMax the further you pull past the end
                    function rubberBand(excess) {
                        var s = stretchMax * (1 - Math.exp(-Math.abs(excess) / stretchFalloff));
                        return excess < 0 ? -s : s;
                    }

                    function wrap360(deg) {
                        var r = deg % 360;
                        return r < 0 ? r + 360 : r;
                    }

                    function rotateBy(deg) {
                        discImage.rotation = wrap360(discImage.rotation + deg);
                        waveShape.rotation = wrap360(waveShape.rotation + deg);
                    }

                    function commitWheel() {
                        wheelCommitTimer.stop();
                        if (!wheelSeeking) return;
                        if (win.player && win.player.length > 0) {
                            win.player.position = previewPosition;
                            if (wasPlaying && win.player.canPlay)
                                win.player.play();
                        }
                        wheelSeeking = false;
                        hasMoved = false;
                        // Boundary flags are kept so the badge doesn't morph back while it fades out
                    }

                    function endDrag() {
                        if (!isDragging) return;
                        if (hasMoved && win.player && win.player.length > 0)
                            win.player.position = previewPosition;
                        hasMoved = false;
                        isDragging = false;     // re-enables the stretch Behavior before releasing it
                        stretch = 0;            // springs back
                        if (win.player && wasPlaying && win.player.canPlay && win.player.playbackState !== MprisPlaybackState.Playing)
                            win.player.play();
                    }

                    Timer {
                        id: wheelCommitTimer
                        interval: 300
                        onTriggered: discMouseArea.commitWheel()
                    }

                    onWheel: wheel => {
                        if (!win.hasPlayer || !win.player || win.player.length <= 0) return;
                        if (isDragging) return;

                        var delta = wheel.angleDelta.y !== 0 ? wheel.angleDelta.y : wheel.angleDelta.x;
                        if (delta === 0) return;

                        var totalLen = win.player.length;

                        if (!wheelSeeking) {
                            isAtBeginning = false;
                            isAtEnd = false;
                            wasPlaying = (win.player.playbackState === MprisPlaybackState.Playing);
                            if (wasPlaying && win.player.canPause)
                                win.player.pause();
                            startPosition = Math.max(0, Math.min(totalLen, win.player.position));
                            previewPosition = startPosition;
                            wheelSeeking = true;
                        }

                        hasMoved = true;
                        // Step size: 5 seconds per standard wheel tick (120 units)
                        var stepSec = (delta / 120.0) * 5.0;
                        var target = previewPosition + stepSec;

                        if (target <= 0 || target >= totalLen) {
                            var dir = target <= 0 ? -1 : 1;
                            var edge = dir < 0 ? 0 : totalLen;
                            // Finish the remaining travel to the edge, then kick against it
                            rotateBy(((edge - previewPosition) / totalLen) * 720.0);
                            previewPosition = edge;
                            isAtBeginning = dir < 0;
                            isAtEnd = dir > 0;

                            stretchKick.stop();
                            stretchKick.kickTo = dir * stretchMax * 0.5;
                            stretchKick.start();
                        } else {
                            previewPosition = target;
                            isAtBeginning = false;
                            isAtEnd = false;
                            rotateBy((stepSec / totalLen) * 720.0);
                        }

                        wheelCommitTimer.restart();
                    }

                    onPressed: function(mouse) {
                        if (!win.hasPlayer || !win.player || win.player.length <= 0) {
                            mouse.accepted = false;
                            return;
                        }

                        var totalLen = win.player.length;
                        var from, resume;
                        if (wheelSeeking) {
                            // Continue from the pending wheel seek instead of discarding it
                            wheelCommitTimer.stop();
                            wheelSeeking = false;
                            from = previewPosition;
                            resume = wasPlaying;
                        } else {
                            from = win.player.position;
                            resume = (win.player.playbackState === MprisPlaybackState.Playing);
                        }

                        stretchKick.stop();
                        // Reset boundary state before the badge becomes visible again
                        isAtBeginning = false;
                        isAtEnd = false;
                        hasMoved = false;
                        accumulatedDelta = 0;
                        startPosition = Math.max(0, Math.min(totalLen, from));
                        previewPosition = startPosition;
                        lastAngle = getAngle(mouse.x, mouse.y);

                        isDragging = true;
                        // Fold any in-flight spring-back into the base rotation so grabbing never jumps
                        initialRotation = discImage.rotation + stretch;
                        initialWaveRotation = waveShape.rotation + stretch;
                        stretch = 0;

                        // Pausing waits for the drag to actually move, so a plain click doesn't interrupt playback
                        wasPlaying = resume;
                    }

                    onPositionChanged: function(mouse) {
                        if (!isDragging || !win.player || win.player.length <= 0) return;

                        var cx = discContainer.width / 2;
                        var cy = discContainer.height / 2;
                        var dist = Math.hypot(mouse.x - cx, mouse.y - cy);
                        var currentAngle = getAngle(mouse.x, mouse.y);

                        // Deadzone filtering: ignore jitter near center singularity
                        if (dist < 20) {
                            lastAngle = currentAngle;
                            return;
                        }

                        var delta = currentAngle - lastAngle;
                        if (delta > 180) {
                            delta -= 360;
                        } else if (delta < -180) {
                            delta += 360;
                        }

                        lastAngle = currentAngle;

                        // Threshold to declare intentional movement
                        if (Math.abs(delta) > 0.3) {
                            if (!hasMoved && wasPlaying && win.player.canPause && win.player.playbackState === MprisPlaybackState.Playing)
                                win.player.pause();
                            hasMoved = true;
                        }

                        var totalLen = win.player.length;
                        var degPerSec = 720.0 / totalLen;
                        var minDelta = -startPosition * degPerSec;
                        var maxDelta = (totalLen - startPosition) * degPerSec;

                        // Keep the raw rotation (capped) so pulling past an end stretches instead of stopping dead,
                        // and reversing unwinds the stretch first
                        accumulatedDelta = Math.max(minDelta - overscrollCap, Math.min(maxDelta + overscrollCap, accumulatedDelta + delta));
                        var clamped = Math.max(minDelta, Math.min(maxDelta, accumulatedDelta));

                        // Boundary state with hysteresis (small detent at each end)
                        isAtBeginning = accumulatedDelta < minDelta || (isAtBeginning && clamped - minDelta < boundaryHysteresis);
                        isAtEnd = accumulatedDelta > maxDelta || (isAtEnd && maxDelta - clamped < boundaryHysteresis);

                        if (isAtBeginning)
                            previewPosition = 0;
                        else if (isAtEnd)
                            previewPosition = totalLen;
                        else
                            previewPosition = Math.max(0, Math.min(totalLen, startPosition + clamped / degPerSec));

                        discImage.rotation = wrap360(initialRotation + clamped);
                        waveShape.rotation = wrap360(initialWaveRotation + clamped);
                        stretch = rubberBand(accumulatedDelta - clamped);
                    }

                    onReleased: endDrag()
                    onCanceled: endDrag()
                }

                // scrub readout
                Item {
                    anchors.centerIn: parent
                    width: scrubBadge.width
                    height: scrubBadge.height
                    z: 30
                    opacity: discMouseArea.isScrubbing ? 1 : 0
                    scale: (discMouseArea.isScrubbing ? 1 : 0.75) * discMouseArea.boundaryPulse
                    visible: opacity > 0.001
                    Behavior on opacity { Fade {} }
                    Behavior on scale { Spring {} }

                    Elevation { anchors.fill: scrubBadge; radius: scrubBadge.radius; level: 2 }
                    Rectangle {
                        id: scrubBadge
                        height: 40
                        width: scrubRow.implicitWidth + 24
                        // full pill normally, 12px square at a boundary (clamped so overshoot can't invert it)
                        property real morph: discMouseArea.isAtBoundary ? 1 : 0
                        Behavior on morph { Spring {} }
                        radius: Math.max(Motion.shapeSmall, Math.min(height / 2, height / 2 + (Motion.shapeMedium - height / 2) * morph))
                        color: discMouseArea.isAtBoundary ? Colors.tertiary_container : Colors.surface_container_highest
                        Behavior on color { ColorFade {} }
                        Behavior on width { Spring {} }

                        Row {
                            id: scrubRow
                            anchors.centerIn: parent
                            spacing: 8
                            Icon {
                                anchors.verticalCenter: parent.verticalCenter
                                size: 18
                                name: discMouseArea.isAtBeginning ? "skip_previous" : discMouseArea.isAtEnd ? "skip_next" : discMouseArea.seekDeltaSec < 0 ? "fast_rewind" : "fast_forward"
                                color: discMouseArea.isAtBoundary ? Colors.on_tertiary_container : Colors.primary
                            }
                            StyledText {
                                anchors.verticalCenter: parent.verticalCenter
                                role: "titleSmall"
                                color: discMouseArea.isAtBoundary ? Colors.on_tertiary_container : Colors.on_surface
                                text: win.formatTime(discMouseArea.previewPosition)
                            }
                            Rectangle {
                                anchors.verticalCenter: parent.verticalCenter
                                opacity: (discMouseArea.isAtBoundary || Math.abs(discMouseArea.seekDeltaSec) >= 1) ? 1 : 0
                                visible: opacity > 0
                                Behavior on opacity { Fade {} }
                                height: 20
                                width: deltaLabel.implicitWidth + 12
                                radius: height / 2
                                color: discMouseArea.isAtBoundary ? Colors.tertiary : Colors.primary_container
                                StyledText {
                                    id: deltaLabel
                                    anchors.centerIn: parent
                                    role: "labelSmall"
                                    emphasized: true
                                    color: discMouseArea.isAtBoundary ? Colors.on_tertiary : Colors.on_primary_container
                                    text: discMouseArea.isAtBeginning ? "START" : discMouseArea.isAtEnd ? "END" : discMouseArea.formatDelta(discMouseArea.seekDeltaSec)
                                }
                            }
                        }
                    }
                }
            }

            // ---- track info: slides out and in on a track change ----
            Column {
                id: info
                anchors.top: discContainer.bottom
                anchors.topMargin: 20
                anchors.horizontalCenter: parent.horizontalCenter
                width: 296
                spacing: 2

                property real shift: 0
                property real textOp: 1
                property real enter: win.stage >= 2 ? 1 : 0
                Behavior on enter { Fade { speed: "default" } }
                opacity: enter * textOp
                transform: Translate { x: info.shift; y: (1 - info.enter) * 16 }

                SequentialAnimation {
                    id: textSwap
                    ParallelAnimation {
                        NumberAnimation { target: info; property: "shift"; to: -42 * win.slideDir; duration: Motion.short3; easing.type: Easing.BezierSpline; easing.bezierCurve: Motion.emphasizedAccelerate }
                        NumberAnimation { target: info; property: "textOp"; to: 0; duration: Motion.short3 }
                    }
                    ScriptAction {
                        script: {
                            win.shownTitle = win.titleNow;
                            win.shownArtist = win.artistNow;
                            info.shift = 42 * win.slideDir;
                        }
                    }
                    ParallelAnimation {
                        Spring { target: info; property: "shift"; to: 0; speed: "default" }
                        Fade { target: info; property: "textOp"; to: 1; speed: "default" }
                    }
                }

                Marquee {
                    width: parent.width
                    role: "titleLarge"
                    emphasized: true
                    jp: true
                    running: win.isOpen
                    text: win.shownTitle
                }
                Marquee {
                    width: parent.width
                    opacity: win.shownArtist !== "" ? 1 : 0
                    visible: opacity > 0
                    Behavior on opacity { Fade {} }
                    role: "bodyLarge"
                    jp: true
                    running: win.isOpen
                    color: Colors.on_surface_variant
                    text: win.shownArtist
                }
            }

            // ---- wavy progress / seek ----
            Item {
                id: seekBar
                anchors.top: info.bottom
                anchors.topMargin: 12
                anchors.horizontalCenter: parent.horizontalCenter
                width: 296
                height: 24
                opacity: win.stage >= 3 ? 1 : 0
                Behavior on opacity { Fade { speed: "default" } }

                readonly property real length: win.hasPlayer ? win.player.length : 0
                readonly property real targetProgress: {
                    if (length <= 0)
                        return 0;
                    if (seekMouse.pressed)
                        return Math.max(0, Math.min(1, seekMouse.mouseX / width));
                    if (discMouseArea.isScrubbing)
                        return Math.max(0, Math.min(1, discMouseArea.previewPosition / length));
                    return Math.max(0, Math.min(1, win.player.position / length));
                }
                property real progress: targetProgress
                Behavior on progress {
                    enabled: !seekMouse.pressed && !discMouseArea.isScrubbing
                    Spring { expressive: false }
                }

                // M3 Expressive wavy progress tokens: 4px stroke, 3px amplitude, 40px wavelength, 4px gaps
                readonly property real thickness: 4
                readonly property real wavelength: 40
                readonly property real handleWidth: 4
                readonly property real gap: 4
                readonly property real splitX: width * progress
                property real amplitude: win.playing ? 3 : 0
                Behavior on amplitude { Spring { speed: "default" } }
                property real phase: 0
                FrameAnimation {
                    running: win.playing && win.isOpen
                    onTriggered: seekBar.phase = (seekBar.phase + frameTime * 40) % seekBar.wavelength
                }

                Rectangle {
                    id: track
                    readonly property real startX: Math.min(seekBar.width, seekBar.splitX + seekBar.handleWidth / 2 + seekBar.gap)
                    x: startX
                    width: Math.max(0, seekBar.width - startX)
                    height: seekBar.thickness
                    radius: height / 2
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.secondary_container
                    visible: width > 0.5
                }
                Rectangle {
                    width: seekBar.thickness
                    height: width
                    radius: width / 2
                    x: seekBar.width - width
                    anchors.verticalCenter: parent.verticalCenter
                    color: Colors.primary
                    visible: track.width > width * 3
                }
                Shape {
                    id: wave
                    anchors.fill: parent
                    preferredRendererType: Shape.CurveRenderer
                    readonly property real cap: seekBar.thickness / 2
                    readonly property real endX: Math.max(cap, seekBar.splitX - seekBar.handleWidth / 2 - seekBar.gap - cap)
                    // ease the amplitude in over the first wavelength so short progress stays flat
                    readonly property real amp: {
                        const t = Math.max(0, Math.min(1, (endX - cap) / seekBar.wavelength));
                        return seekBar.amplitude * t * t * (3 - 2 * t);
                    }
                    visible: seekBar.splitX - seekBar.handleWidth / 2 - seekBar.gap > seekBar.thickness

                    ShapePath {
                        strokeColor: Colors.primary
                        strokeWidth: seekBar.thickness
                        fillColor: "transparent"
                        capStyle: ShapePath.RoundCap
                        joinStyle: ShapePath.RoundJoin
                        PathPolyline {
                            path: {
                                const mid = wave.height / 2, k = 2 * Math.PI / seekBar.wavelength, pts = [];
                                for (let x = wave.cap; x < wave.endX; x += 1.5)
                                    pts.push(Qt.point(x, mid + wave.amp * Math.sin(k * (x - seekBar.phase))));
                                pts.push(Qt.point(wave.endX, mid + wave.amp * Math.sin(k * (wave.endX - seekBar.phase))));
                                return pts;
                            }
                        }
                    }
                }
                Rectangle {
                    x: Math.max(0, Math.min(seekBar.width - width, seekBar.splitX - width / 2))
                    anchors.verticalCenter: parent.verticalCenter
                    width: seekMouse.pressed ? 2 : seekBar.handleWidth
                    height: 24
                    radius: width / 2
                    color: Colors.primary
                    Behavior on width { Spring {} }
                }

                MouseArea {
                    id: seekMouse
                    anchors.fill: parent
                    anchors.topMargin: -8
                    anchors.bottomMargin: -8
                    cursorShape: Qt.PointingHandCursor
                    property bool resume: false
                    function seekTo(x) {
                        if (seekBar.length > 0)
                            win.player.position = seekBar.length * Math.max(0, Math.min(1, x / width));
                    }
                    onPressed: mouse => {
                        resume = win.playing;
                        if (resume && win.player.canPause)
                            win.player.pause();
                        seekTo(mouse.x);
                    }
                    onReleased: mouse => {
                        seekTo(mouse.x);
                        if (resume && win.player.canPlay)
                            win.player.play();
                        resume = false;
                    }
                    onCanceled: {
                        if (resume && win.player.canPlay)
                            win.player.play();
                        resume = false;
                    }
                }

                // MPRIS doesn't push position updates; poll while visible
                Timer {
                    running: win.playing && win.isOpen && !seekMouse.pressed && !discMouseArea.isScrubbing
                    interval: 250
                    repeat: true
                    onTriggered: win.player.positionChanged()
                }
            }

            Item {
                id: times
                anchors.top: seekBar.bottom
                anchors.left: seekBar.left
                anchors.right: seekBar.right
                height: 18
                opacity: win.stage >= 3 ? 1 : 0
                Behavior on opacity { Fade { speed: "default" } }
                RollingDigits {
                    pixelSize: 13
                    color: Colors.on_surface_variant
                    text: win.formatTime(seekBar.progress * seekBar.length)
                }
                RollingDigits {
                    anchors.right: parent.right
                    pixelSize: 13
                    color: Colors.on_surface_variant
                    text: win.formatTime(seekBar.length)
                }
            }

            // ---- transport: M3 Expressive standard button group ----
            // the pressed button widens ~15% and its neighbours give way; shuffle and loop flank it
            Row {
                id: transport
                anchors.top: times.bottom
                anchors.topMargin: 16
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 8
                readonly property int pressedIndex: prev.pressed ? 0 : play.pressed ? 1 : next.pressed ? 2 : -1
                function widthFor(i, base) {
                    if (pressedIndex < 0)
                        return base;
                    if (pressedIndex === i)
                        return base * 1.15;
                    return base - (pressedIndex === 1 ? 96 : 56) * 0.15 / 2;
                }

                IconButton {
                    id: shuffle
                    anchors.verticalCenter: parent.verticalCenter
                    size: "s"
                    style: "outlined"
                    icon: "shuffle"
                    checkable: true
                    visible: win.hasPlayer && win.player.shuffleSupported
                    checked: win.hasPlayer && win.player.shuffle
                    enabled: win.hasPlayer && win.player.canControl
                    opacity: win.stage >= 4 ? 1 : 0
                    iconScale: win.stage >= 4 ? 1 : 0.3
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on iconScale { Spring {} }
                    onClicked: win.player.shuffle = !win.player.shuffle
                }
                IconButton {
                    id: prev
                    size: "m"
                    style: "tonal"
                    icon: "skip_previous"
                    width: transport.widthFor(0, 56)
                    Behavior on width { Spring {} }
                    opacity: win.stage >= 4 ? 1 : 0
                    scale: win.stage >= 4 ? 1 : 0.5
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on scale { Spring {} }
                    enabled: win.hasPlayer && win.player.canGoPrevious
                    onClicked: {
                        win.nextDir = -1;
                        win.player.previous();
                    }
                }
                IconButton {
                    id: play
                    size: "m"
                    style: "filled"
                    icon: win.playing ? "pause" : "play_arrow"
                    iconSize: 28
                    width: transport.widthFor(1, 96)
                    Behavior on width { Spring {} }
                    property bool spinSpring: true
                    iconKick: false
                    Behavior on iconRotation { enabled: play.spinSpring; Spring {} }
                    Behavior on iconScale { enabled: play.spinSpring; Spring {} }
                    opacity: win.stage >= 5 ? 1 : 0
                    scale: win.stage >= 5 ? 1 : 0.5
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on scale { Spring {} }
                    // round while paused, square while playing
                    restRadius: win.playing ? Motion.shapeLarge : height / 2
                    enabled: win.hasPlayer && win.player.canTogglePlaying
                    onClicked: win.player.togglePlaying()
                }
                IconButton {
                    id: next
                    size: "m"
                    style: "tonal"
                    icon: "skip_next"
                    width: transport.widthFor(2, 56)
                    Behavior on width { Spring {} }
                    opacity: win.stage >= 6 ? 1 : 0
                    scale: win.stage >= 6 ? 1 : 0.5
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on scale { Spring {} }
                    enabled: win.hasPlayer && win.player.canGoNext
                    onClicked: win.player.next()
                }
                IconButton {
                    id: loop
                    anchors.verticalCenter: parent.verticalCenter
                    size: "s"
                    style: "outlined"
                    icon: win.hasPlayer && win.player.loopState === MprisLoopState.Track ? "repeat_one" : "repeat"
                    checkable: true
                    visible: win.hasPlayer && win.player.loopSupported
                    checked: win.hasPlayer && win.player.loopState !== MprisLoopState.None
                    enabled: win.hasPlayer && win.player.canControl
                    opacity: win.stage >= 6 ? 1 : 0
                    iconScale: win.stage >= 6 ? 1 : 0.3
                    Behavior on opacity { Fade { speed: "default" } }
                    Behavior on iconScale { Spring {} }
                    onClicked: win.player.loopState = win.player.loopState === MprisLoopState.None ? MprisLoopState.Playlist
                        : win.player.loopState === MprisLoopState.Playlist ? MprisLoopState.Track : MprisLoopState.None
                }
            }
        }

        // ---------------------------------------------------------------- lyrics
        LyricViewer {
            id: lyricViewer
            x: 360
            width: 400
            height: parent.height
            opacity: win.showLyrics ? 1 : 0
            visible: opacity > 0
            Behavior on opacity { Fade { speed: "default" } }
            player: win.player
            hasPlayer: win.hasPlayer
            onLyricsDetected: detected => win.showLyrics = detected
        }
    }
}
