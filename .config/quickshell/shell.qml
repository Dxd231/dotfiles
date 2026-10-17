pragma ComponentBehavior: Bound
//@ pragma UseQApplication
import Quickshell
import Quickshell.Services.Mpris
import QtQuick
import qs
import qs.Services
import "./Modules"

ShellRoot {
    id: shell

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
        systemStatusPopup: systemStatusPopup
        volumePopup: volumePopup
        albumPopup: albumPopup
        powerMenu: powerMenu
    }

    CalendarPopup {
        id: calendarPopup
        anchorItem: bar.clockChip
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
        player: shell.activePlayer
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

    WallpaperSwitcher {}

    OnScreenDisplay {
        volumePopup: volumePopup
    }

    CopyToast {
        id: copyToast
    }

    ActiveArch {}
}
