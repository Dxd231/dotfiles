import QtQuick
import qs
import qs.Components

// Titled group of segmented rows on a detail page. Rows fade / scale in and glide to
// their new place as a scan adds or reorders them.
Column {
    id: section

    property string title
    default property alias rows: list.data

    // fill the page body
    width: parent ? parent.width : implicitWidth
    spacing: 8

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

        add: Transition {
            Fade { property: "opacity"; from: 0; to: 1; speed: "default" }
            Spring { property: "scale"; from: 0.92; to: 1; speed: "default" }
        }
        move: Transition {
            Spring { property: "y"; speed: "default"; expressive: false }
        }
    }
}
