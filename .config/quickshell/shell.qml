pragma ComponentBehavior: Bound
//@ pragma UseQApplication
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import QtQuick
import qs
import qs.Services
import "./Modules"

ShellRoot {
    id: shell

    // so the capture card can toast (Undo after a delete) however the capture was started or adopted
    Component.onCompleted: {
        Capture.toast = copyToast;
        Session.toast = copyToast;
        Health.refresh();   // singletons load on first use; this one only serves `qs ipc call health ...`
        Manga.request({ op: "ping" });   // wakes the manga helper: it scans the library and writes manga.json for the shelf and heatmap
    }

    // Preferred player first, otherwise any playing/paused one.
    property string preferredPlayer: "spotify"
    readonly property var activePlayer: {
        let found = null;
        for (const p of Mpris.players.values) {
            if (p.identity.toLowerCase() === preferredPlayer)
                return p;
            if (p.playbackState === MprisPlaybackState.Playing || p.playbackState === MprisPlaybackState.Paused)
                found = p;
        }
        return found;
    }

    Bar {
        id: bar
        player: shell.activePlayer
        notifications: notifications
        calendarPopup: calendarPopup
        focusPopup: focusPopup
        alarmPopup: alarmPopup
        tasksPopup: taskPopup
        tasksQuickMenu: taskQuickMenu
        immersionPopup: immersionPopup
        ankiPopup: ankiPopup
        systemStatusPopup: systemStatusPopup
        volumePopup: volumePopup
        albumPopup: albumPopup
        powerMenu: powerMenu
    }

    CalendarPopup {
        id: calendarPopup
        anchorItem: bar.clockDateAnchor
    }

    FocusPopup {
        id: focusPopup
        anchorItem: bar.clockFocusAnchor
    }

    AlarmPopup {
        id: alarmPopup
        anchorItem: bar.clockTimeAnchor
    }

    TaskPopup {
        id: taskPopup
        anchorItem: bar.tasksChip
        copyToast: copyToast
    }

    TaskQuickMenu {
        id: taskQuickMenu
        anchorItem: bar.tasksChip
    }

    ImmersionPopup {
        id: immersionPopup
        anchorItem: bar.immersionChip
        copyToast: copyToast
    }

    // opened from mpv (Alt+j), not from a bar item
    JimakuPopup {
        id: jimakuPopup
    }

    AnkiPopup {
        id: ankiPopup
        anchorItem: bar.ankiChip
    }

    SystemStatusPopup {
        id: systemStatusPopup
        anchorItem: bar.statsChip
    }

    VolumePopup {
        id: volumePopup
        anchorItem: bar.volumeModule
    }

    MprisPopup {
        id: albumPopup
        player: shell.activePlayer
        hasPlayer: !!shell.activePlayer
    }

    Notifications {
        id: notifications
        controlCenter: controlCenter
    }

    ControlCenter {
        id: controlCenter
        notifications: notifications
        powerMenu: powerMenu
        activePlayer: shell.activePlayer
        inhibitModule: IdleInhibit
    }

    LockScreen {
        id: lockScreen
    }
    Binding {
        target: Session
        property: "blocked"
        value: lockScreen.locked
    }

    AppDock {
        id: appdock
        launcher: appLauncher
    }

    AppLauncher {
        id: appLauncher
        dock: appdock
    }

    EmojiPicker {
        copyToast: copyToast
    }

    ClipboardManager {
        copyToast: copyToast
    }

    PowerMenu {
        id: powerMenu
        lockScreen: lockScreen
    }

    SessionRestoreCard {}

    ClosingApps {}

    WallpaperSwitcher {}

    ShelfPanel {}

    MangaReader {}

    OnScreenDisplay {
        volumePopup: volumePopup
    }

    CopyToast {
        id: copyToast
    }

    OcrOverlay {}
    OcrCard {}
    SubOverlay {}
    // OCR: snip a region (auto engine), read the last region again, OCR the clipboard image
    IpcHandler {
        target: "ocr"
        function snip(): void { Ocr.toast = copyToast; Ocr.snip(); }
        function again(): void { Ocr.toast = copyToast; Ocr.again(); }
        function clipboard(): void { Ocr.toast = copyToast; Ocr.clipboard(); }
        function dismiss(): void { Ocr.cancel(); Ocr.dismiss(); }
        function warm(engine: string): void { Ocr.warm(engine); }
        function region(x: int, y: int, w: int, h: int): void { Ocr.setRegion(x, y, w, h); }
        function rerun(engine: string): void { Ocr.rerun(engine); }
        function clear(): void { Ocr.clearHistory(); }
        function dialogue(): void { Ocr.toast = copyToast; Ocr.dialogue(); }
        function forget(): void { Ocr.toast = copyToast; Ocr.forget(); }
        function demo(text: string): void { Ocr.demo(text); }
        function demoError(text: string): void { Ocr.demoError(text); }
        function history(): void { Ocr.historyOpen = !Ocr.historyOpen; }
        function stop(): void { Ocr.stopEngines(); }
        function state(): string {
            return JSON.stringify({ phase: Ocr.phase, engine: Ocr.current ? Ocr.current.engine : "", result: Ocr.result, error: Ocr.errorText,
                                    manga: Ocr.mangaReady, paddle: Ocr.paddleReady, region: Ocr.lastRegion, history: Ocr.history.length,
                                    blocks: Ocr.blocks.length, detecting: Ocr.detecting, windowKey: Ocr.windowKey, windowRegion: Ocr.windowRegion,
                                    hooker: Ocr.relayUp, kind: Ocr.startKind, mangaModel: Ocr.mangaModel });
        }
        function last(): string { return Ocr.history.length > 0 ? Ocr.history[0].text : ""; }
    }

    CaptureOverlay {}
    CaptureCard {}
    CaptureGrabber {}
    // screenshots and recordings: the picker, direct shots, and the recorder
    IpcHandler {
        target: "capture"
        function open(): void { Capture.toast = copyToast; Capture.open(null, null); }
        function photo(): void { Capture.toast = copyToast; Capture.open("photo", null); }
        function video(): void { Capture.toast = copyToast; Capture.open("video", null); }
        function region(): void { Capture.toast = copyToast; Capture.open(null, "region"); }
        function pick(mode: string, target: string): void { Capture.toast = copyToast; Capture.open(mode, target); }
        function screen(): void { Capture.toast = copyToast; Capture.quick("photo", "screen"); }
        function window(): void { Capture.toast = copyToast; Capture.quick("photo", "window"); }
        function workspace(): void { Capture.toast = copyToast; Capture.quick("photo", "workspace"); }
        function workspaceOf(id: int): void { Capture.toast = copyToast; Capture.quick("photo", "workspace", id); }
        function windowOf(address: string): void { Capture.toast = copyToast; Capture.quick("photo", "window", address); }
        function record(): void { Capture.toast = copyToast; Capture.toggleRecording(); }
        function recordScreen(): void { Capture.toast = copyToast; Capture.quick("video", "screen"); }
        function recordWindow(): void { Capture.toast = copyToast; Capture.quick("video", "window"); }
        function stop(): void { Capture.stopRecording(); }
        function pause(): void { Capture.pauseRecording(); }
        function cancel(): void { Capture.cancel(); Capture.dismissCard(); }
        function state(): string {
            return JSON.stringify({ phase: Capture.phase, mode: Capture.mode, target: Capture.target, recording: Capture.recording, paused: Capture.recPaused,
                                    elapsed: Capture.elapsed, file: Capture.recFile, windows: Capture.windows.length, workspaces: Capture.workspaces.length,
                                    last: Capture.last, card: Capture.cardShown, delay: Capture.delay, pointer: Capture.pointer, audio: Capture.audio });
        }
    }

    ActiveArch {}
}
