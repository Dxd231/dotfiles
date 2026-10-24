pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import qs
import qs.Components
import qs.Services

// Where the page text recognition stands, beside the volume being read: the volume's cover (it changes shape
// with every page read), its share on one wavy bar that waves faster the quicker the pages come, and the
// switch that lets the other volumes be read while the computer is idle. The card takes a tint from its state.
Rectangle {
    id: card

    property bool shown: true
    property int delay: 0

    readonly property var o: Manga.ocr
    readonly property string st: o.state
    readonly property bool working: st === "reading"
    readonly property bool starting: working && !o.worker.running
    readonly property bool problem: st === "error" || st === "missing"
    readonly property bool quiet: st === "off" || st === "idle"
    // the volume being read, else the one open in the reader
    readonly property var vol: o.current ? o.current : o.focus ? o.focus : null
    readonly property int pages: vol ? vol.pages : 0
    readonly property int done: vol ? vol.done : 0
    readonly property real frac: pages > 0 ? Math.min(1, done / pages) : 0
    readonly property bool finished: pages > 0 && done >= pages
    readonly property real rate: o.rate_ppm > 0 ? o.rate_ppm : 0

    function coverOf(id) {
        for (const s of Manga.series)
            for (const v of s.volumes)
                if (v.id === id)
                    return v.cover;
        return "";
    }
    readonly property string coverPath: vol ? coverOf(vol.vol) : ""

    readonly property string stateLabel: {
        switch (st) {
        case "reading": return o.worker.running ? "Reading" : "Starting";
        case "waiting_idle": return "Waiting for idle";
        case "waiting_memory": return "Waiting for memory";
        case "paused": return "Paused";
        case "missing": return "Not installed";
        case "error": return "Error";
        case "idle": return "All read";
        default: return "Off";
        }
    }
    readonly property string line: {
        if (st === "error" && o.error !== "")
            return o.error;
        if (finished)
            return "Ready for study";
        if (vol) {
            let t = (o.current ? "p " + (o.current.idx + 1) + "  ·  " : "") + done + " / " + pages + " pages";
            if (working && rate > 0)
                t += "  ·  " + Math.round(rate) + "/min" + (pages > done ? "  ·  " + Manga.fmtTime((pages - done) / rate * 60) + " left" : "");
            return t;
        }
        switch (st) {
        case "waiting_idle": return "Other volumes wait until you step away";
        case "waiting_memory": return "Not enough free memory yet, trying again soon";
        case "paused": return "Paused";
        case "missing": return "The text reader is not installed";
        default: return "Reads the volume you open";
        }
    }
    readonly property var shapes: ["cookie9", "sunny", "softBurst", "pentagon", "cookie4"]
    property int shapeAt: 0
    onDoneChanged: if (working) shapeAt = (shapeAt + 1) % shapes.length

    implicitHeight: body.implicitHeight + 28
    radius: Motion.shapeExtraLarge
    color: problem ? Qt.tint(Colors.surface_container, Qt.alpha(Colors.error_container, 0.6)) : working || finished ? Qt.tint(Colors.surface_container, Qt.alpha(Colors.tertiary_container, 0.55)) : Colors.surface_container
    Behavior on color { ColorFade {} }
    Appear { shown: card.shown; delay: card.delay; from: 0.97 }

    ColumnLayout {
        id: body
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: 18
        anchors.rightMargin: 18
        spacing: 8

        RowLayout {
            Layout.fillWidth: true
            spacing: 14

            ShapeMask {
                Layout.preferredWidth: card.vol ? 52 : 0
                Layout.preferredHeight: 52
                Layout.alignment: Qt.AlignVCenter
                visible: Layout.preferredWidth > 0.5
                Behavior on Layout.preferredWidth { Spring { speed: "default" } }
                source: card.coverPath !== "" ? Manga.cover(card.coverPath) : ""
                shape: card.working ? card.shapes[card.shapeAt] : "cookie4"
                opacity: card.vol ? 1 : 0
                Behavior on opacity { Fade {} }
            }

            ColumnLayout {
                Layout.fillWidth: true
                spacing: 0
                StyledText {
                    role: "titleLarge"
                    emphasized: true
                    text: "Text recognition"
                    Layout.fillWidth: true
                    elide: Text.ElideRight
                }
                SwapText {
                    Layout.fillWidth: true
                    role: "bodyMedium"
                    emphasized: true
                    jp: true
                    elide: Text.ElideRight
                    color: card.problem ? Colors.error : Colors.on_surface_variant
                    value: card.vol ? card.vol.series + "  ·  " + (card.vol.title || "") : card.line
                }
            }

            // the share of the volume, or a tick once it is all read
            Item {
                Layout.preferredWidth: pctRow.implicitWidth
                Layout.preferredHeight: 40
                Layout.alignment: Qt.AlignVCenter
                RowLayout {
                    id: pctRow
                    anchors.centerIn: parent
                    spacing: 2
                    opacity: card.finished ? 0 : 1
                    Behavior on opacity { Fade {} }
                    RollingDigits {
                        text: Math.round(card.frac * 100).toString()
                        pixelSize: 32
                        color: card.problem ? Colors.error : Colors.on_surface
                    }
                    StyledText {
                        role: "titleMedium"
                        emphasized: true
                        text: "%"
                        color: Colors.on_surface_variant
                        Layout.alignment: Qt.AlignBottom
                    }
                }
                ShapeBadge {
                    anchors.centerIn: parent
                    width: 44
                    height: 44
                    badgeScale: card.finished ? 1 : 0
                    visible: badgeScale > 0.02
                    shapeRest: "cookie9"
                    shapeActive: "sunny"
                    color: Colors.tertiary_container
                    Icon {
                        anchors.centerIn: parent
                        name: "check"
                        size: 24
                        color: Colors.on_tertiary_container
                    }
                }
            }
        }

        // one bar for the volume: it waves faster and higher the quicker the pages come
        WavyProgress {
            Layout.fillWidth: true
            thickness: 8
            wavelength: 26
            amplitude: card.working && !card.finished ? 2 + Math.min(2, card.rate / 20) : 0
            value: card.frac
            indeterminate: card.starting && card.vol === null
            waving: card.working && !card.finished && card.shown
            activeColor: card.problem ? Colors.error : card.working || card.finished ? Colors.tertiary : Colors.outline
            trackColor: card.working || card.finished ? Qt.alpha(Colors.tertiary, 0.2) : Colors.surface_container_highest
            Behavior on activeColor { ColorFade {} }
            Behavior on trackColor { ColorFade {} }
        }

        SwapText {
            Layout.fillWidth: true
            role: "bodyMedium"
            emphasized: true
            elide: Text.ElideRight
            visible: card.vol !== null
            color: card.problem ? Colors.error : card.finished ? Colors.on_tertiary_container : Colors.on_surface_variant
            value: card.line
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 12
            Switch {
                showIcons: false
                checked: card.o.bg
                onToggled: Manga.ocrBackground(!card.o.bg)
            }
            StyledText {
                role: "bodyMedium"
                emphasized: true
                text: "Other volumes while idle"
                Layout.fillWidth: true
                elide: Text.ElideRight
            }
            Rectangle {
                implicitHeight: 28
                implicitWidth: stateText.implicitWidth + 24
                radius: height / 2
                color: card.problem ? Colors.error_container : card.working ? Colors.tertiary_container : card.quiet ? Colors.surface_container_highest : Colors.secondary_container
                Behavior on color { ColorFade {} }
                Behavior on implicitWidth { Spring { speed: "fast" } }
                SwapText {
                    id: stateText
                    anchors.centerIn: parent
                    role: "labelLarge"
                    emphasized: true
                    value: card.stateLabel
                    color: card.problem ? Colors.on_error_container : card.working ? Colors.on_tertiary_container : card.quiet ? Colors.on_surface_variant : Colors.on_secondary_container
                }
            }
            IconButton {
                size: "xs"
                style: "tonal"
                icon: card.o.paused ? "play_arrow" : "pause"
                enabled: card.st !== "missing"
                onClicked: card.o.paused ? Manga.ocrResume() : Manga.ocrPause()
            }
        }
    }
}
