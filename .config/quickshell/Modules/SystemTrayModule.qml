pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Services.SystemTray
import Quickshell.Wayland
import Qt5Compat.GraphicalEffects
import qs
import qs.Components

// Status notifier tray + M3 Expressive context menus (one submenu level).
Rectangle {
    id: tray

    required property var barWindow

    implicitHeight: 32
    implicitWidth: items.implicitWidth + 4
    radius: 16
    color: Colors.surface_container_high
    visible: itemRepeater.count > 0

    Row {
        id: items
        anchors.centerIn: parent
        spacing: 0

        Repeater {
            id: itemRepeater
            model: SystemTray.items
            delegate: Clickable {
                id: trayItem
                required property SystemTrayItem modelData
                readonly property bool menuOpen: menu.visible && menu.forItem === modelData
                readonly property bool tintIcon: {
                    const id = (modelData.id || modelData.icon || "").toLowerCase();
                    return id.includes("fcitx") || id.includes("unikey");
                }

                width: 28
                height: 28
                pressedRadius: Motion.shapeSmall
                checkable: true
                checked: menuOpen
                checkedRadius: Motion.shapeSmall
                color: checked ? Colors.secondary_container : "transparent"
                acceptedButtons: Qt.LeftButton | Qt.RightButton
                onClicked: mouse => {
                    if (mouse.button === Qt.RightButton && modelData.hasMenu) {
                        if (menuOpen)
                            menu.close();
                        else
                            menu.openFor(modelData, trayItem);
                    } else {
                        modelData.activate();
                    }
                }

                Image {
                    id: trayIcon
                    anchors.centerIn: parent
                    width: 20
                    height: 20
                    sourceSize: Qt.size(20, 20)
                    source: trayItem.modelData.icon
                    visible: !trayItem.tintIcon
                }
                // input-method icons ship monochrome; tint them to the theme
                ColorOverlay {
                    anchors.fill: trayIcon
                    source: trayIcon
                    visible: trayItem.tintIcon
                    color: Colors.primary
                }
            }
        }
    }

    // ---------------------------------------------------------------- menus
    MenuPopup {
        id: menu
        property SystemTrayItem forItem: null
        anchor.window: tray.barWindow
        menuHandle: forItem ? forItem.menu : null

        function openFor(item, anchorItem) {
            submenu.visible = false;
            forItem = item;
            target = anchorItem;
            anchor.updateAnchor();
            visible = true;
        }
        function close() {
            visible = false;
            submenu.visible = false;
        }
        anchor.onAnchoring: {
            if (!target)
                return;
            const p = target.mapToItem(null, target.width / 2, target.height);
            anchor.rect.x = p.x - implicitWidth / 2;
            anchor.rect.y = p.y + 4;
        }
        onVisibleChanged: if (!visible) submenu.visible = false
    }

    MenuPopup {
        id: submenu
        anchor.window: menu
        anchor.onAnchoring: {
            if (!target)
                return;
            const p = target.mapToItem(null, target.width, 0);
            anchor.rect.x = p.x - shadowPad + 4;
            anchor.rect.y = p.y - shadowPad - 4;
        }
    }

    // full-screen catcher so clicking anywhere else dismisses the menus
    PanelWindow {
        visible: menu.visible
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "quickshell:tray_menu_dismiss"
        exclusiveZone: -1
        color: "transparent"
        anchors { top: true; bottom: true; left: true; right: true }
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.AllButtons
            onClicked: menu.close()
        }
    }

    component MenuPopup: PopupWindow {
        id: popup
        property var menuHandle: null
        property Item target: null
        readonly property int shadowPad: 12

        visible: false
        color: "transparent"
        implicitWidth: 240 + shadowPad * 2
        implicitHeight: list.implicitHeight + 8 + shadowPad * 2

        QsMenuOpener {
            id: opener
            menu: popup.menuHandle
        }

        Elevation {
            anchors.fill: surface
            radius: surface.radius
            level: 2
        }
        Rectangle {
            id: surface
            anchors.fill: parent
            anchors.margins: popup.shadowPad
            radius: Motion.shapeLarge
            color: Colors.surface_container_low
            focus: popup.visible
            Keys.onEscapePressed: menu.close()

            Column {
                id: list
                x: 4
                y: 4
                width: parent.width - 8
                spacing: 0

                Repeater {
                    model: opener.children
                    delegate: MenuEntry {
                        ownerPopup: popup
                        count: opener.children.values.length
                    }
                }
            }
        }
    }

    component MenuEntry: Item {
        id: entry
        required property QsMenuEntry modelData
        required property int index
        required property var ownerPopup
        required property int count
        readonly property bool checkedEntry: modelData.buttonType !== QsMenuButtonType.None && modelData.checkState === Qt.Checked

        width: parent ? parent.width : 0
        // separators become an M3 Expressive group gap rather than a rule
        height: modelData.isSeparator ? 8 : 44

        Clickable {
            id: row
            visible: !entry.modelData.isSeparator
            enabled: entry.modelData.enabled
            anchors.fill: parent
            // segmented-menu item shape: 4px, with 12px outer corners on the first/last item
            restRadius: Motion.shapeExtraSmall
            topLeftRadius: entry.index === 0 ? Motion.shapeMedium : radius
            topRightRadius: entry.index === 0 ? Motion.shapeMedium : radius
            bottomLeftRadius: entry.index === entry.count - 1 ? Motion.shapeMedium : radius
            bottomRightRadius: entry.index === entry.count - 1 ? Motion.shapeMedium : radius
            color: entry.checkedEntry ? Colors.tertiary_container : "transparent"
            contentColor: entry.checkedEntry ? Colors.on_tertiary_container : Colors.on_surface
            onClicked: {
                if (entry.modelData.hasChildren) {
                    submenu.menuHandle = entry.modelData;
                    submenu.target = entry;
                    submenu.anchor.updateAnchor();
                    submenu.visible = true;
                } else {
                    entry.modelData.triggered();
                    menu.close();
                }
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 12
                anchors.rightMargin: 12
                spacing: 12
                opacity: entry.modelData.enabled ? 1 : Motion.disabledContent

                Icon {
                    visible: entry.checkedEntry
                    name: "check"
                    size: 20
                    color: row.contentColor
                }
                Image {
                    visible: !entry.checkedEntry && entry.modelData.icon !== ""
                    source: entry.modelData.icon
                    sourceSize: Qt.size(20, 20)
                    Layout.preferredWidth: 20
                    Layout.preferredHeight: 20
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "bodyLarge"
                    color: row.contentColor
                    elide: Text.ElideRight
                    text: entry.modelData.text
                }
                Icon {
                    visible: entry.modelData.hasChildren
                    name: "arrow_right"
                    size: 20
                    color: Colors.on_surface_variant
                }
            }
        }
    }
}
