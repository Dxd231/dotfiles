import QtQuick

QtObject {
  property string fontdefault: "Space Grotesk"

  property string fontjp: "Zen Maru Gothic Medium"

  property int fontsize: 12

<* for name, value in colors *>
    readonly property string {{name}}: "{{value.default.hex}}"
<* endfor *>
}
