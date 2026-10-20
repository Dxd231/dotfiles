#!/bin/sh
# Assembles the SDDM theme from the shell's own components, so the two can't drift apart:
# Components/*.qml + Motion/Typography are copied with the `qs` imports dropped (the greeter has no
# Quickshell), and an icon table trimmed to the glyphs used is embedded as IconPaths.qml.
# Output: ~/.cache/quickshell-sddm/theme (or $1)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
SHELL_DIR="$SRC/.."
OUT="${1:-$HOME/.cache/quickshell-sddm/theme}"
rm -rf "$OUT"; mkdir -p "$OUT/state"

for c in WavyRing MorphShape LoadingIndicator RollingDigits Icon Elevation Spring Fade ColorFade \
         StyledText IconButton StateLayer Clickable ShapeBadge Appear ShapeField; do
    grep -v '^import qs' "$SHELL_DIR/Components/$c.qml" > "$OUT/$c.qml"
done
for s in Motion Typography; do
    cp "$SHELL_DIR/$s.qml" "$OUT/$s.qml"
done
cp "$SRC"/Main.qml "$SRC"/GreeterView.qml "$SRC"/metadata.desktop "$SRC"/theme.conf "$OUT/"

python3 - "$SHELL_DIR/Components/icons.json" "$OUT/IconPaths.qml" <<'PY'
import json, sys
src, dst = sys.argv[1:]
d = json.load(open(src))
keep = ["lock", "error", "password", "keyboard_capslock", "bedtime", "restart_alt", "power_settings_new", "desktop_windows"]
out = {k: {n: d[k][n] for n in keep if n in d[k]} for k in ("filled", "outlined")}
open(dst, "w").write("pragma Singleton\nimport QtQuick\n\nQtObject {\n    readonly property var filled: (%s)\n    readonly property var outlined: (%s)\n}\n"
                      % (json.dumps(out["filled"]), json.dumps(out["outlined"])))
PY

cat > "$OUT/qmldir" <<'Q'
singleton Colors state/Colors.qml
singleton Motion Motion.qml
singleton Typography Typography.qml
singleton IconPaths IconPaths.qml
Q
# Icon.qml is the only component that does `import qs.Components`; it is already stripped above.
