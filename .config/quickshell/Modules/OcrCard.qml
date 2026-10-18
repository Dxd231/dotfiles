pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Widgets
import qs
import qs.Components
import qs.Services

// What an OCR run is doing and found: a card at the bottom of the screen with the crop, the text
// (already on the clipboard and sent to the Texthooker UI), buttons to read the same crop with the
// other engine, and the last few results to copy again. It never takes keyboard focus, so a game
// keeps its input; it hides itself after a while unless the pointer is on it.
PanelWindow {
    id: win

    readonly property bool wanted: Ocr.phase === "warming" || Ocr.phase === "running" || Ocr.phase === "done" || Ocr.phase === "error"
    readonly property bool historyOpen: Ocr.historyOpen
    property bool copied: false

    anchors { bottom: true; left: true; right: true }
    implicitHeight: 560
    exclusiveZone: -1
    color: "transparent"
    WlrLayershell.namespace: "quickshell:ocrcard"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    visible: wanted || card.appear > 0.01
    mask: Region { item: card }

    onWantedChanged: {
        copied = false;
        if (wanted) {
            hideTimer.restart();
        } else {
            hideTimer.stop();
            Ocr.historyOpen = false;
        }
    }
    Connections {
        target: Ocr
        function onPhaseChanged() {
            win.copied = false;
            if (Ocr.phase === "done" || Ocr.phase === "error")
                hideTimer.restart();
        }
    }
    Timer {
        id: hideTimer
        interval: 12000
        onTriggered: {
            if (hover.hovered || win.historyOpen)
                restart();
            else
                Ocr.dismiss();
        }
    }

    Elevation {
        x: card.x
        y: card.y
        width: card.width
        height: card.height
        radius: card.radius
        level: 3
        opacity: card.opacity
        scale: card.scale
        transformOrigin: Item.Bottom
    }

    Rectangle {
        id: card
        width: 580
        height: body.implicitHeight + 32
        anchors.horizontalCenter: parent.horizontalCenter
        radius: Motion.shapeExtraLarge
        color: Colors.surface_container_high
        property real appear: win.wanted ? 1 : 0
        Behavior on appear { Spring { speed: "default" } }
        y: win.height - height - 28 + (1 - appear) * 40
        opacity: Math.max(0, Math.min(1, appear * 1.6))
        scale: 0.92 + 0.08 * appear
        transformOrigin: Item.Bottom

        HoverHandler { id: hover }

        ColumnLayout {
            id: body
            x: 16
            y: 16
            width: parent.width - 32
            spacing: 12

            // ---- header: crop, engine, status, close ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                ClippingRectangle {
                    id: thumb
                    // as wide as the crop is, so a tall strip isn't cut to a sliver
                    Layout.preferredWidth: thumb.rect ? Math.max(40, Math.min(168, 56 * thumb.rect[2] / Math.max(1, thumb.rect[3]))) : 96
                    Layout.preferredHeight: 56
                    radius: 14
                    color: Colors.surface_container_highest
                    readonly property var rect: Ocr.current ? Ocr.current.rect : null
                    Image {
                        anchors.fill: parent
                        visible: !!thumb.rect
                        source: !!thumb.rect && Ocr.current ? "file://" + Ocr.current.path : ""
                        sourceClipRect: thumb.rect ? Qt.rect(thumb.rect[0], thumb.rect[1], thumb.rect[2], thumb.rect[3]) : Qt.rect(0, 0, 0, 0)
                        fillMode: Image.PreserveAspectFit
                        cache: false
                        asynchronous: true
                    }
                    LoadingIndicator {
                        anchors.centerIn: parent
                        width: 40
                        height: 40
                        visible: Ocr.phase === "warming" || Ocr.phase === "running"
                        running: visible
                    }
                    Icon {
                        anchors.centerIn: parent
                        size: 24
                        visible: !thumb.rect && Ocr.phase !== "warming" && Ocr.phase !== "running"
                        name: Ocr.phase === "error" ? "error" : "crop_free"
                        color: Colors.on_surface_variant
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 0
                    StyledText {
                        role: "titleMedium"
                        emphasized: true
                        text: Ocr.phase === "warming" ? "Loading " + Ocr.engineLabel(Ocr.current ? Ocr.current.engine : "paddle") + "…"
                            : Ocr.phase === "running" ? "Reading…"
                            : Ocr.phase === "error" ? "Could not read"
                            : Ocr.result && Ocr.result.text === "" ? "No text found" : "Copied"
                    }
                    StyledText {
                        Layout.fillWidth: true
                        role: "bodySmall"
                        color: Colors.on_surface_variant
                        elide: Text.ElideRight
                        text: {
                            if (Ocr.phase === "warming")
                                return "The first read after a while takes a few seconds";
                            if (Ocr.phase === "running" || Ocr.phase === "error")
                                return Ocr.phase === "error" ? Ocr.errorText : "";
                            if (!Ocr.result)
                                return "";
                            const dev = Ocr.result.engine === "manga" ? Ocr.mangaDevice : Ocr.paddleDevice;
                            return Ocr.engineLabel(Ocr.result.engine) + "  ·  " + Ocr.result.ms + " ms" + (dev ? "  ·  " + dev.toUpperCase() : "")
                                + (Ocr.hookerSent && Ocr.result.text !== "" ? "  ·  sent to texthooker" : "");
                        }
                    }
                }
                IconButton { icon: "close"; size: "xs"; onClicked: Ocr.dismiss() }
            }

            // ---- the text ----
            Rectangle {
                Layout.fillWidth: true
                // whole lines only (at most four), so a line is never cut in half at the edge
                Layout.preferredHeight: Math.max(64, Math.min(textEdit.contentHeight, 4 * textEdit.contentHeight / Math.max(1, textEdit.lineCount)) + 24)
                visible: Ocr.phase === "done" && !!Ocr.result && Ocr.result.text !== ""
                radius: Motion.shapeLarge
                color: Colors.surface_container
                clip: true
                Flickable {
                    id: textFlick
                    anchors.fill: parent
                    anchors.margins: 12
                    // the text wraps at the box's width and only scrolls vertically
                    contentWidth: width
                    contentHeight: textEdit.contentHeight
                    boundsBehavior: Flickable.StopAtBounds
                    flickableDirection: Flickable.VerticalFlick
                    clip: true
                    TextEdit {
                        id: textEdit
                        width: textFlick.width
                        readOnly: true
                        selectByMouse: true
                        wrapMode: TextEdit.Wrap
                        color: Colors.on_surface
                        selectionColor: Colors.primary
                        selectedTextColor: Colors.on_primary
                        font.family: Typography.familyJp
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        text: Ocr.result ? Ocr.result.text : ""
                    }
                }
            }
            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: errText.implicitHeight + 24
                visible: Ocr.phase === "error"
                radius: Motion.shapeLarge
                color: Colors.error_container
                StyledText {
                    id: errText
                    anchors.fill: parent
                    anchors.margins: 12
                    role: "bodyMedium"
                    color: Colors.on_error_container
                    wrapMode: Text.WordWrap
                    text: Ocr.errorText
                }
            }

            // ---- re-read with the other engine, copy again, history ----
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                visible: Ocr.phase === "done" || Ocr.phase === "error"
                Chip {
                    kind: "filter"
                    text: "Manga"
                    selected: Ocr.current ? Ocr.current.engine === "manga" : false
                    enabled: !!Ocr.current && !Ocr.busy
                    onClicked: Ocr.rerun("manga")
                }
                Chip {
                    kind: "filter"
                    text: "General"
                    selected: Ocr.current ? Ocr.current.engine === "paddle" : false
                    enabled: !!Ocr.current && !Ocr.busy
                    onClicked: Ocr.rerun("paddle")
                }
                Item { Layout.fillWidth: true }
                IconButton {
                    icon: "history"
                    style: "tonal"
                    size: "xs"
                    checkable: true
                    checked: win.historyOpen
                    enabled: Ocr.history.length > 0
                    onClicked: Ocr.historyOpen = !Ocr.historyOpen
                }
                Button {
                    visible: Ocr.phase === "done" && !!Ocr.result && Ocr.result.text !== ""
                    size: "xs"
                    style: "tonal"
                    icon: win.copied ? "check" : "content_copy"
                    text: win.copied ? "Copied" : "Copy"
                    onClicked: {
                        Ocr.copyText(Ocr.result.text);
                        win.copied = true;
                    }
                }
            }

            // ---- the last few results ----
            // the wrapper animates its height and clips, so rows can't spill out of the card while it
            // opens or closes; the card follows because its height is the layout's
            Item {
                id: historyWrap
                Layout.fillWidth: true
                Layout.preferredHeight: Math.max(0, historyWrap.shown)
                // a spring can undershoot zero, and a negative preferred height means "use the content's"
                property real shown: win.historyOpen ? historyList.implicitHeight : 0
                Behavior on shown { Spring { speed: "default" } }
                visible: historyWrap.shown > 0.5 || win.historyOpen
                clip: true
                opacity: win.historyOpen ? 1 : 0
                Behavior on opacity { Fade {} }
            ColumnLayout {
                id: historyList
                width: parent.width
                spacing: 2
                Repeater {
                    model: Math.min(5, Ocr.history.length)
                    delegate: Item {
                        id: hrow
                        required property int index
                        readonly property var h: Ocr.history[index]
                        Layout.fillWidth: true
                        Layout.preferredHeight: 40
                        HoverHandler { id: rowHover }
                        Rectangle {
                            anchors.fill: parent
                            radius: Motion.shapeMedium
                            color: rowHover.hovered ? Colors.surface_container_highest : "transparent"
                            Behavior on color { ColorFade {} }
                        }
                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 10
                            StyledText {
                                Layout.fillWidth: true
                                jp: true
                                role: "bodyLarge"
                                emphasized: true
                                elide: Text.ElideRight
                                text: hrow.h ? hrow.h.text.replace(/\n/g, " ") : ""
                            }
                            StyledText {
                                role: "labelSmall"
                                color: Colors.on_surface_variant
                                text: hrow.h ? (hrow.h.engine === "manga" ? "manga" : "general") + " · " + Qt.formatTime(new Date(hrow.h.ts), "HH:mm") : ""
                            }
                            Icon {
                                size: 18
                                name: "content_copy"
                                color: Colors.on_surface_variant
                                opacity: rowHover.hovered ? 1 : 0
                                Behavior on opacity { Fade {} }
                            }
                        }
                        TapHandler {
                            onTapped: {
                                if (hrow.h) {
                                    Ocr.copyText(hrow.h.text);
                                    if (Ocr.toast)
                                        Ocr.toast.showToast("Copied again");
                                }
                            }
                        }
                    }
                }
            }
            }
        }
    }
}
