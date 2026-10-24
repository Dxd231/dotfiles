pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell.Networking
import qs
import qs.Components

// A Wi-Fi network in the Internet page: tap to connect (asks for a password for new secured
// networks), trailing action disconnects the current network or forgets a saved one.
DetailRow {
    id: row

    required property var modelData
    required property int index
    property var cc
    property int count: 1   // rows in this group

    readonly property var network: modelData
    // a scan can drop a network (destroying it) just before its row is removed, hence the `?.`
    readonly property bool connected: !!cc && !!network && cc.isActiveNetwork(network)
    readonly property bool connecting: network?.state === ConnectionState.Connecting
    readonly property int signal: Math.round((network?.signalStrength ?? 0) * 100)
    readonly property bool secured: !!network && network.security !== WifiSecurityType.Open
    readonly property bool needsPassword: secured && !network?.known
    property bool askPassword: false

    first: index === 0
    last: index === count - 1
    icon: signal >= 75 ? "signal_wifi_4_bar" : signal >= 50 ? "network_wifi_3_bar" : signal >= 25 ? "network_wifi_2_bar" : "network_wifi_1_bar"
    badgeIcon: secured ? "lock" : ""
    highlighted: connected
    title: network?.name || "Hidden network"
    subtitle: connecting ? "Connecting…" : connected ? "Connected" : secured ? (network?.known ? "Saved" : "Secured") : "Open"
    busy: connecting

    onClicked: {
        if (connected || connecting)
            return;
        if (needsPassword)
            askPassword = !askPassword;
        else
            cc.connectNetwork(network, "");
    }

    // trailing actions open and close in place as the network's state changes
    Collapse {
        horizontal: true
        open: row.connected
        IconButton {
            icon: "link_off"
            onClicked: row.network.disconnect()
        }
    }
    Collapse {
        horizontal: true
        open: !row.connected && !!row.network?.known
        IconButton {
            icon: "delete"
            onClicked: row.network.forget()
        }
    }

    // the password entry slides open below the row and fades in
    extra: Collapse {
        Layout.bottomMargin: 4 * Math.max(0, Math.min(1, reveal))
        open: row.askPassword
        RowLayout {
            spacing: 8

            TextField {
                id: pass
                Layout.fillWidth: true
                label: "Password"
                password: true
                onVisibleChanged: if (visible) forceActiveFocus()
                onAccepted: text => {
                    row.cc.connectNetwork(row.network, text);
                    row.askPassword = false;
                }
            }
            IconButton {
                icon: "arrow_forward"
                style: "filled"
                size: "m"
                widthMode: "narrow"
                onClicked: {
                    row.cc.connectNetwork(row.network, pass.text);
                    row.askPassword = false;
                }
            }
        }
    }
}
