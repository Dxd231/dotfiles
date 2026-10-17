pragma Singleton
import QtQuick
import Quickshell

// Keep-awake state. Modes: 0 off, 1–4 timed (5/15/30/60 min), 5 indefinite.
// The bar owns the actual IdleInhibitor (it needs a window) and binds it to `active`.
Singleton {
    id: inhibit

    property int mode: 0
    property double expiresAt: 0
    property string remainingText: ""
    readonly property bool active: mode > 0
    readonly property bool timed: mode >= 1 && mode <= 4
    readonly property var durations: [0, 5, 15, 30, 60]

    function _set(m) {
        mode = m;
        if (timed) {
            expiresAt = Date.now() + durations[m] * 60000;
            _tick();
        } else {
            expiresAt = 0;
            remainingText = "";
        }
    }
    function advanceMode() { _set((mode + 1) % 6); }
    function toggleActive() { _set(active ? 0 : 5); }

    function _tick() {
        const left = expiresAt - Date.now();
        if (left <= 0) {
            _set(0);
            return;
        }
        const s = Math.ceil(left / 1000);
        remainingText = Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }

    Timer {
        interval: 1000
        repeat: true
        running: inhibit.timed
        onTriggered: inhibit._tick()
    }
}
