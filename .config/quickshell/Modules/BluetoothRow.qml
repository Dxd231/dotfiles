pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Bluetooth
import qs
import qs.Components

// A Bluetooth device in the Bluetooth page: tap to connect (or pair a new one), trailing
// action disconnects the connected device or forgets a paired one.
DetailRow {
    id: row

    required property var modelData
    required property int index
    property int count: 1   // rows in this group

    readonly property var device: modelData
    // devices can disappear from a scan just before their row is removed, hence the `?.`
    readonly property bool connected: !!device?.connected
    readonly property bool pairing: !!device?.pairing
    readonly property bool working: pairing || device?.state === BluetoothDeviceState.Connecting || device?.state === BluetoothDeviceState.Disconnecting
    readonly property int batteryPercent: Math.round((device?.battery ?? 0) * 100)

    // BlueZ icon name -> a symbol we ship
    function iconFor(name) {
        const i = String(name || "");
        if (i.startsWith("audio-headphones") || i.startsWith("audio-headset")) return "headphones";
        if (i.startsWith("audio-card")) return "speaker_group";
        if (i.startsWith("input-keyboard")) return "keyboard";
        if (i.startsWith("input-mouse")) return "mouse";
        if (i.startsWith("input-gaming")) return "gamepad";
        if (i.startsWith("input-tablet")) return "tablet";
        if (i.startsWith("phone")) return "mobile";
        if (i.startsWith("computer")) return "computer";
        if (i.startsWith("video-display")) return "tv";
        return connected ? "bluetooth_connected" : "bluetooth";
    }

    first: index === 0
    last: index === count - 1
    icon: iconFor(device?.icon)
    highlighted: connected
    title: device?.name || device?.address || "Device"
    subtitle: pairing ? "Pairing…"
        : working ? (connected ? "Disconnecting…" : "Connecting…")
        : connected ? "Connected" + (device?.batteryAvailable ? " · " + batteryPercent + "% battery" : "")
        : device?.paired ? "Paired" : "Available to pair"
    busy: working

    onClicked: {
        if (working || connected)
            return;
        if (device.paired) {
            device.connect();
        } else {
            device.trusted = true;
            device.pair();
        }
    }

    // trailing actions open and close in place as the device's state changes
    Collapse {
        horizontal: true
        open: row.pairing
        IconButton {
            icon: "close"
            onClicked: row.device.cancelPair()
        }
    }
    Collapse {
        horizontal: true
        open: row.connected && !row.working
        IconButton {
            icon: "link_off"
            onClicked: row.device.disconnect()
        }
    }
    Collapse {
        horizontal: true
        open: !row.connected && !!row.device?.paired && !row.working
        IconButton {
            icon: "delete"
            onClicked: row.device.forget()
        }
    }
}
