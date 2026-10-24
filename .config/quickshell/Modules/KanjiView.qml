pragma ComponentBehavior: Bound
import QtQuick
import QtQuick.Layouts
import Quickshell
import qs
import qs.Components
import qs.Services

// A kanji's own entry, like the one Yomitan opens from a character of a headword: the glyph with its meanings and
// numbers, on/kun readings, the parts it is built from and common words with it (the ones you have are tinted).
// WordPopup shows it in place of the glossary, in the same space; it scrolls if it is taller. `ch` is the character
// asked for; a part opened from here keeps a way Back.
Item {
    id: pop
    clip: true

    property string ch: ""
    property bool shown: false
    signal closeRequested()

    // "loading" | "ready" | "none" | "offline"
    property string phase: "loading"
    property var info: null
    readonly property var k: info || ({})
    property var trail: []
    readonly property real contentH: col.implicitHeight

    function statNote(k) {
        const out = [];
        if (k.strokes) out.push(k.strokes + " strokes");
        if (k.grade) out.push("Grade " + k.grade);
        if (k.jlpt) out.push("JLPT N" + k.jlpt);
        if (k.freq) out.push("#" + k.freq);
        if (k.jouyou) out.push("常用");
        if (k.kentei) out.push("漢検 " + k.kentei);
        return out;
    }

    // `ch` is what the overlay asks for (a click on a headword glyph); a part opened from the card goes through
    // open(), which keeps the way back
    property string _last: ""
    onChChanged: {
        if (ch === "" || ch === _last)
            return;
        trail = [];
        load(ch);
    }
    function open(c, back) {
        if (c === _last)
            return;
        if (!back)
            trail = trail.concat([_last]);
        load(c);
    }
    function back() {
        if (trail.length === 0) {
            closeRequested();
            return;
        }
        const t = trail.slice();
        const prev = t.pop();
        trail = t;
        load(prev, true);
    }
    function load(c, quiet) {
        _last = c;
        phase = "loading";
        Lexicon.kanji(c, r => {
            if (c !== pop._last)
                return;
            if (r.error) {
                pop.phase = r.error === "yomitan-offline" ? "offline" : "none";
                return;
            }
            pop.info = r.kanji;
            pop.phase = "ready";
            swap.restart();
        });
    }
    onShownChanged: {
        if (!shown) {
            _last = "";
            trail = [];
            info = null;
        }
    }
    NumberAnimation {
        id: swap
        target: col
        property: "opacity"
        from: 0.25
        to: 1
        duration: Motion.medium1
        easing.type: Easing.BezierSpline
        easing.bezierCurve: Motion.emphasizedDecelerate
    }

    Flickable {
        id: flick
        anchors.fill: parent
        anchors.margins: 0
        contentWidth: width
        contentHeight: col.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds

        ColumnLayout {
            id: col
            width: flick.width
            spacing: 2

            RowLayout {
                Layout.fillWidth: true
                Layout.bottomMargin: 6
                spacing: 4
                IconButton {
                    size: "xs"
                    icon: "arrow_back"
                    onClicked: pop.back()
                }
                StyledText {
                    Layout.fillWidth: true
                    role: "labelLarge"
                    emphasized: true
                    color: Colors.on_surface_variant
                    text: "Kanji"
                }
            }

            Collapse {
                open: pop.phase === "loading"
                Layout.fillWidth: true
                Item {
                    implicitHeight: 72
                    LoadingIndicator {
                        anchors.centerIn: parent
                        running: pop.shown && pop.phase === "loading"
                    }
                }
            }
            Collapse {
                open: pop.phase === "none" || pop.phase === "offline"
                Layout.fillWidth: true
                Layout.topMargin: 4
                Layout.bottomMargin: 4
                StyledText {
                    horizontalAlignment: Text.AlignHCenter
                    color: Colors.on_surface_variant
                    text: pop.phase === "offline" ? "Open LibreWolf for kanji entries" : "No kanji entry for " + pop.ch
                }
            }

            // glyph, meanings, numbers
            Collapse {
                open: pop.phase === "ready"
                Layout.fillWidth: true
                Rectangle {
                    Appear { shown: pop.phase === "ready"; delay: 0; lift: 10 }
                    implicitHeight: hero.implicitHeight + 24
                    topLeftRadius: 20
                    topRightRadius: 20
                    bottomLeftRadius: 4
                    bottomRightRadius: 4
                    color: Colors.surface_container_highest
                    RowLayout {
                        id: hero
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 14
                        StyledText {
                            Layout.alignment: Qt.AlignTop
                            jp: true
                            emphasized: true
                            font.pixelSize: 64
                            text: pop.ch
                        }
                        ColumnLayout {
                            Layout.fillWidth: true
                            Layout.alignment: Qt.AlignVCenter
                            spacing: 8
                            StyledText {
                                Layout.fillWidth: true
                                visible: text !== ""
                                role: "titleMedium"
                                emphasized: true
                                wrapMode: Text.Wrap
                                text: (pop.k.meanings || []).join(", ")
                            }
                            Flow {
                                Layout.fillWidth: true
                                spacing: 4
                                Repeater {
                                    model: pop.k.char ? pop.statNote(pop.k) : []
                                    InfoPill {
                                        required property string modelData
                                        jp: true
                                        text: modelData
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // on'yomi / kun'yomi
            Collapse {
                open: pop.phase === "ready" && ((pop.k.on || []).length > 0 || (pop.k.kun || []).length > 0)
                Layout.fillWidth: true
                Rectangle {
                    Appear { shown: pop.phase === "ready"; delay: 60; lift: 10 }
                    implicitHeight: rd.implicitHeight + 24
                    radius: 4
                    color: Colors.surface_container_highest
                    ColumnLayout {
                        id: rd
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 4
                        Collapse {
                            open: (pop.k.on || []).length > 0
                            Layout.fillWidth: true
                            RowLayout {
                                spacing: 10
                                StyledText {
                                    Layout.preferredWidth: 28
                                    role: "labelMedium"
                                    emphasized: true
                                    color: Colors.primary
                                    text: "On"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    jp: true
                                    wrapMode: Text.Wrap
                                    text: (pop.k.on || []).join("、")
                                }
                            }
                        }
                        Collapse {
                            open: (pop.k.kun || []).length > 0 || (pop.k.share || []).length > 0
                            Layout.fillWidth: true
                            RowLayout {
                                spacing: 10
                                StyledText {
                                    Layout.preferredWidth: 28
                                    role: "labelMedium"
                                    emphasized: true
                                    color: Colors.primary
                                    text: "Kun"
                                }
                                StyledText {
                                    Layout.fillWidth: true
                                    jp: true
                                    wrapMode: Text.Wrap
                                    // JPDB's readings carry how often each is used; KANJIDIC's are the plain list
                                    text: ((pop.k.share || []).length > 0 ? pop.k.share : (pop.k.kun || [])).join("、")
                                }
                            }
                        }
                    }
                }
            }

            // what the character is built from; a part that is a kanji opens
            Collapse {
                open: pop.phase === "ready" && (pop.k.parts || []).length > 0
                Layout.fillWidth: true
                Rectangle {
                    Appear { shown: pop.phase === "ready"; delay: 120; lift: 10 }
                    implicitHeight: pt.implicitHeight + 24
                    radius: 4
                    color: Colors.surface_container_highest
                    ColumnLayout {
                        id: pt
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 6
                        StyledText {
                            role: "labelMedium"
                            emphasized: true
                            color: Colors.primary
                            text: "Parts"
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: pop.k.parts || []
                                Button {
                                    required property string modelData
                                    style: "tonal"
                                    size: "xs"
                                    enabled: /[㐀-鿿]/.test(modelData) && modelData !== pop.ch
                                    text: modelData
                                    onClicked: pop.open(modelData, false)
                                }
                            }
                        }
                    }
                }
            }

            // common words with it; the ones you already have are tinted
            Collapse {
                open: pop.phase === "ready" && (pop.k.words || []).length > 0
                Layout.fillWidth: true
                Rectangle {
                    Appear { shown: pop.phase === "ready"; delay: 180; lift: 10 }
                    implicitHeight: wd.implicitHeight + 24
                    topLeftRadius: 4
                    topRightRadius: 4
                    bottomLeftRadius: 20
                    bottomRightRadius: 20
                    color: Colors.surface_container_highest
                    ColumnLayout {
                        id: wd
                        x: 16
                        y: 12
                        width: parent.width - 32
                        spacing: 6
                        StyledText {
                            role: "labelMedium"
                            emphasized: true
                            color: Colors.primary
                            text: "Words"
                        }
                        Flow {
                            Layout.fillWidth: true
                            spacing: 6
                            Repeater {
                                model: pop.k.words || []
                                InfoPill {
                                    id: wp

                                    required property string modelData
                                    readonly property string st: {
                                        const m = (pop.k.mine || []).find(x => x.term === modelData);
                                        return m ? m.status : "";
                                    }
                                    jp: true
                                    text: modelData
                                    container: st === "known" ? Colors.primary_container : st === "learning" ? Colors.secondary_container : Colors.surface_container
                                    content: st === "known" ? Colors.on_primary_container : st === "learning" ? Colors.on_secondary_container : Colors.on_surface_variant
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
