pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Bluetooth detail page: adapter switch, connected / paired / nearby devices, scan button.
DetailPage {
    id: page

    required property var cc

    title: "Bluetooth"
    subtitle: !cc.bluetoothOn ? "Off" : cc.activeBtDevice ? (cc.activeBtDevice.name || "Connected") : "On"
    checked: cc.bluetoothOn
    busy: cc.btDiscovering
    offIcon: "bluetooth_disabled"
    offTitle: "Bluetooth is off"
    offText: "Turn on Bluetooth to connect headphones, keyboards and other devices."
    onBack: cc.page = ""
    onToggled: cc.toggleBluetooth()

    ListSection {
        title: "Connected"
        visible: page.cc.connectedBtDevices.length > 0
        Repeater {
            model: page.cc.connectedBtDevices
            delegate: BluetoothRow { count: page.cc.connectedBtDevices.length }
        }
    }
    ListSection {
        title: "Paired devices"
        visible: page.cc.pairedBtDevices.length > 0
        Repeater {
            model: page.cc.pairedBtDevices
            delegate: BluetoothRow { count: page.cc.pairedBtDevices.length }
        }
    }
    ListSection {
        title: "Available devices"
        visible: page.cc.nearbyBtDevices.length > 0
        Repeater {
            model: page.cc.nearbyBtDevices
            delegate: BluetoothRow { count: page.cc.nearbyBtDevices.length }
        }
    }

    // nothing found yet
    Item {
        width: parent.width
        height: 160
        visible: page.cc.btDevices.length === 0
        ColumnLayout {
            anchors.centerIn: parent
            spacing: 12
            LoadingIndicator {
                Layout.alignment: Qt.AlignHCenter
                contained: true
            }
            StyledText {
                role: "bodyMedium"
                color: Colors.on_surface_variant
                text: "Looking for devices…"
            }
        }
    }

    footer: Button {
        Layout.fillWidth: true
        style: "tonal"
        icon: "bluetooth_searching"
        text: page.cc.btDiscovering ? "Stop scanning" : "Scan for devices"
        onClicked: page.cc.toggleBtDiscover()
    }
}
