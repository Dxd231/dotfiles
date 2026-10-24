import QtQuick
import qs
import qs.Components

// Titled group of segmented rows on a detail page. Rows rise in on their own (DetailRow) and glide
// to their new place as a scan adds or reorders them; the section opens and closes with `shown`.
Column {
    id: section

    property string title
    // opens and closes the whole section (use it instead of `visible`)
    property bool shown: true
    default property alias rows: list.data

    // fill the page body
    width: parent ? parent.width : implicitWidth
    spacing: 8
    property real reveal: shown ? 1 : 0
    Behavior on reveal { Spring { speed: "default"; expressive: false } }
    height: implicitHeight * Math.max(0, Math.min(1, reveal))
    opacity: Math.max(0, Math.min(1, reveal))
    visible: shown || reveal > 0.01
    clip: true

    StyledText {
        leftPadding: 16
        role: "titleSmall"
        color: Colors.primary
        text: section.title
    }

    Column {
        id: list
        width: section.width
        spacing: 2

        move: Transition {
            Spring { property: "y"; speed: "default"; expressive: false }
        }
    }
}
