pragma ComponentBehavior: Bound
import QtQuick
import qs
import qs.Components
import qs.Services
import "../Components/MangaLayout.js" as ML

// Vertical scrolling: every page at one width, heights known from the page sizes so nothing jumps while
// pictures load. The wheel moves a goal and the view follows it on a spring.
Flickable {
    id: fl

    property var pages: []
    property real baseWidth: 600
    property real zoom: 1
    property bool rtl: true
    readonly property real pageW: baseWidth * zoom
    readonly property var offs: ML.offsets(pages, pageW)
    property int currentPage: 0
    // set while a jump is under way, so scrolling past pages on the way doesn't count as reading them
    property bool jumping: false
    property real goal: 0
    // the volume's last page shows below the pictures
    property real footerHeight: 0

    signal pageSeen(int page)
    signal zoomWheel(real delta, real x)
    signal tapped(real x, real y)

    interactive: false
    clip: true
    contentWidth: Math.max(width, pageW)
    contentHeight: offs[offs.length - 1] + footerHeight
    boundsBehavior: Flickable.StopAtBounds
    // contentY follows a frame-accurate spring (see SpringValue)
    SpringValue {
        id: sy
        stiffness: 300
        ratio: 1
        epsilon: 0.2
        onValueChanged: fl.contentY = value
    }
    // one wheel notch scrolls this far; quick successive notches add up faster
    readonly property real wheelStep: Math.max(240, height * 0.4)
    property double _lastWheel: 0
    property real _wheelMult: 1

    function maxY() { return Math.max(0, contentHeight - height); }
    function clampY(y) { return Math.max(0, Math.min(maxY(), y)); }
    function scrollBy(dy) {
        goal = clampY(goal + dy);
        sy.target = goal;
    }
    function jumpTo(page, animate) {
        jumping = true;
        jumpTimer.restart();
        goal = clampY(offs[Math.max(0, Math.min(pages.length - 1, page))]);
        if (animate)
            sy.target = goal;
        else
            sy.jump(goal);
    }
    Timer { id: jumpTimer; interval: 700; onTriggered: fl.jumping = false }

    // pages holding pictures: one screen above the view, two below; these change only at page boundaries
    property int firstNear: 0
    property int lastNear: 0
    function updateNear() {
        const a = ML.pageAt(offs, Math.max(0, contentY - height));
        const b = ML.pageAt(offs, contentY + height * 3);
        if (a !== firstNear)
            firstNear = a;
        if (b !== lastNear)
            lastNear = b;
    }
    onHeightChanged: updateNear()
    Component.onCompleted: updateNear()

    onContentYChanged: {
        updateNear();
        const p = ML.pageAt(offs, contentY + height * 0.4);
        if (p !== currentPage) {
            currentPage = p;
            if (!jumping)
                pageSeen(p);
        }
    }
    // a different width keeps the same place in the book
    property real _lastW: pageW
    onOffsChanged: {
        updateNear();
        if (_lastW > 0 && pageW !== _lastW && contentHeight > 0) {
            goal = clampY(contentY * (pageW / _lastW));
            sy.jump(goal);
        }
        _lastW = pageW;
    }

    Item {
        id: sheet
        width: fl.contentWidth
        height: fl.contentHeight

        Repeater {
            model: fl.pages.length
            delegate: Item {
                id: slot
                required property int index
                x: (sheet.width - width) / 2
                y: fl.offs[index]
                width: fl.pageW
                height: fl.offs[index + 1] - fl.offs[index]
                Loader {
                    anchors.fill: parent
                    asynchronous: true
                    active: slot.index >= fl.firstNear && slot.index <= fl.lastNear
                    sourceComponent: MangaPage {
                        info: fl.pages[slot.index]
                        fitHeight: slot.height
                        full: fl.zoom > 1.3
                        vol: Manga.openVol
                        live: Math.abs(slot.index - fl.currentPage) <= 1
                    }
                }
            }
        }
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: ev => {
            if (ev.modifiers & Qt.ControlModifier) {
                fl.zoomWheel(ev.angleDelta.y, point.position.x);
                return;
            }
            if (ev.pixelDelta.y !== 0) {
                fl.scrollBy(-ev.pixelDelta.y * 2);
            } else if (ev.angleDelta.y !== 0) {
                const now = Date.now();
                fl._wheelMult = now - fl._lastWheel < 150 ? Math.min(2.5, fl._wheelMult * 1.25) : 1;
                fl._lastWheel = now;
                fl.scrollBy(-ev.angleDelta.y / 120 * fl.wheelStep * fl._wheelMult);
            }
            if (ev.angleDelta.x !== 0 || ev.pixelDelta.x !== 0)
                fl.contentX = Math.max(0, Math.min(fl.contentWidth - fl.width, fl.contentX - (ev.pixelDelta.x || ev.angleDelta.x)));
        }
    }
    // drag to scroll: the pages follow the pointer, and letting go with speed flings on the spring
    DragHandler {
        id: drag
        target: null
        property real startX: 0
        property real startY: 0
        onActiveChanged: {
            if (active) {
                startX = fl.contentX;
                startY = fl.contentY;
                fl.goal = fl.contentY;
                sy.jump(fl.contentY);
            } else {
                const vy = centroid.velocity.y;
                const fast = Math.abs(vy) > 300;
                fl.goal = fl.clampY(fl.contentY - (fast ? vy * 0.35 : 0));
                sy.fling(fl.goal, fast ? -vy : 0);
            }
        }
        onTranslationChanged: if (active) {
            fl.goal = fl.clampY(startY - translation.y);
            sy.jump(fl.goal);
            if (fl.pageW > fl.width + 1)
                fl.contentX = Math.max(0, Math.min(fl.contentWidth - fl.width, startX - translation.x));
        }
    }
    HoverHandler {
        cursorShape: drag.active ? Qt.ClosedHandCursor : Qt.OpenHandCursor
    }
    TapHandler {
        onTapped: (pt) => fl.tapped(pt.position.x, pt.position.y)
    }
}
