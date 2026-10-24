import QtQuick
import qs
import qs.Components

// One page: a placeholder with a loading indicator until the picture is ready, then the picture fades in.
// Decoded at the size it is shown; `full` adds a full-resolution layer on top (zoomed in).
Item {
    id: pg

    property var info: null          // { i, w, h, path }
    property real fitHeight: 0       // the height it is drawn at, for decoding
    property bool full: false
    property int vol: -1              // the volume, for the bubbles
    property bool live: false         // the page the pointer can study: bubbles are fetched and hoverable
    readonly property string source: info && info.path ? "file://" + info.path : ""
    readonly property bool ready: base.status === Image.Ready
    // decoded in 256 px steps so small zoom changes don't reload the picture
    readonly property int decodeH: fitHeight > 0 ? Math.ceil(fitHeight / 256) * 256 : 0

    Rectangle {
        anchors.fill: parent
        color: Colors.surface_container
        opacity: pg.ready ? 0 : 1
        visible: opacity > 0.01
        Behavior on opacity { Fade {} }
    }
    Loader {
        anchors.centerIn: parent
        active: base.status === Image.Loading
        sourceComponent: LoadingIndicator {}
    }
    Image {
        id: base
        anchors.fill: parent
        source: pg.source
        asynchronous: true
        smooth: true
        fillMode: Image.Stretch
        sourceSize.height: pg.decodeH
        opacity: pg.ready ? 1 : 0
        Behavior on opacity { Fade {} }
    }
    Loader {
        anchors.fill: parent
        active: pg.full && pg.ready
        sourceComponent: Image {
            source: pg.source
            asynchronous: true
            smooth: true
            fillMode: Image.Stretch
            opacity: status === Image.Ready ? 1 : 0
            Behavior on opacity { Fade {} }
        }
    }
    // the speech bubbles, once the page is there to be read
    Loader {
        anchors.fill: parent
        z: 10
        active: pg.live && pg.ready && pg.vol >= 0 && pg.info !== null
        sourceComponent: MangaBubbles {
            vol: pg.vol
            idx: pg.info.i
        }
    }
}
