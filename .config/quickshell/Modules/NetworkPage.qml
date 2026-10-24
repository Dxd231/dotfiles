pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components

// Internet detail page: Wi-Fi switch, the connected network, saved and nearby networks.
DetailPage {
    id: page

    required property var cc

    title: "Internet"
    subtitle: !cc.wifiOn ? "Wi-Fi off" : cc.activeNetwork ? cc.activeSsid : "Not connected"
    checked: cc.wifiOn
    busy: cc.wifiScanning
    offIcon: "wifi_off"
    offTitle: "Wi-Fi is off"
    offText: "Turn on Wi-Fi to see and join nearby networks."
    onBack: cc.page = ""
    onToggled: cc.toggleWifi()

    ListSection {
        title: "Connected"
        shown: !!page.cc.activeNetwork
        Repeater {
            model: page.cc.activeNetwork ? [page.cc.activeNetwork] : []
            delegate: NetworkRow { cc: page.cc }
        }
    }
    ListSection {
        title: "Saved networks"
        shown: page.cc.savedNetworks.length > 0
        Repeater {
            model: page.cc.savedNetworks
            delegate: NetworkRow { cc: page.cc; count: page.cc.savedNetworks.length }
        }
    }
    ListSection {
        title: "Available networks"
        shown: page.cc.availableNetworks.length > 0
        Repeater {
            model: page.cc.availableNetworks
            delegate: NetworkRow { cc: page.cc; count: page.cc.availableNetworks.length }
        }
    }

    // nothing found yet
    Collapse {
        width: parent.width
        open: !page.cc.activeNetwork && page.cc.sortedNetworks.length === 0
        Item {
            implicitHeight: 160
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
                    text: "Searching for networks…"
                }
            }
        }
    }

    // pinned below the list: also keeps the last row off the card edge
    footer: Button {
        Layout.fillWidth: true
        style: "text"
        icon: "refresh"
        text: "Rescan"
        onClicked: page.cc.rescanWifi()
    }
}
