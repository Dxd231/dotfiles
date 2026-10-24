import QtQuick
import qs

// StyledText whose words cross-fade (and lift a little) when they change, instead of swapping in place.
// Set `value`, not `text`. It drives its own opacity and transform: wrap it to fade it from outside.
StyledText {
    id: t

    property string value

    property real _k: 1
    opacity: _k
    transform: Translate { y: (1 - t._k) * 4 }
    Component.onCompleted: text = value
    onValueChanged: {
        // nothing on screen to fade (or it has never been shown): just take the new words
        if (!visible || text === "") {
            swap.stop();
            text = value;
            _k = 1;
            return;
        }
        swap.restart();
    }
    SequentialAnimation {
        id: swap
        NumberAnimation { target: t; property: "_k"; to: 0; duration: 90; easing.type: Easing.InQuad }
        ScriptAction { script: t.text = t.value }
        NumberAnimation { target: t; property: "_k"; to: 1; duration: 220; easing.type: Easing.OutQuad }
    }
}
