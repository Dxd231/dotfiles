#!/usr/bin/env bash
# Wrapper to run your custom Quickshell share picker instance
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# The shell's recorder (Services/Capture.qml) writes the window it wants to record here just before it
# starts gpu-screen-recorder; when the note is fresh and that window is in the list xdph passed us, answer
# straight away instead of showing the picker. Anything else goes to the picker as before.
note="${XDG_RUNTIME_DIR:-/tmp}/qs-share-preselect"
if [ -f "$note" ] && [ -n "${XDPH_WINDOW_SHARING_LIST:-}" ]; then
    handle=$(python3 -I - "$note" <<'PY'
import os, sys, time
try:
    st = os.stat(sys.argv[1])
    want = open(sys.argv[1]).read().strip()
except OSError:
    sys.exit(0)
os.unlink(sys.argv[1])
if time.time() - st.st_mtime > 15 or not want.startswith("window:"):
    sys.exit(0)
want = want[7:].lower().replace("0x", "")
for rec in os.environ["XDPH_WINDOW_SHARING_LIST"].split("[HA>]"):
    try:
        head, addr = rec.split("[HE>]")
        hid = head.split("[HC>]")[0]
        if format(int(addr.strip()), "x") == want:
            print(int(hid))
            break
    except ValueError:
        pass
PY
)
    if [ -n "$handle" ]; then
        printf '[SELECTION]/window:%s\n' "$handle"
        exit 0
    fi
fi

# Ensure symlinks in .share exist
mkdir -p "$SCRIPT_DIR/.share"
ln -sfn "$SCRIPT_DIR" "$SCRIPT_DIR/.share/quickshell"
ln -sfn /usr/share/quickshell-share-picker/lib "$SCRIPT_DIR/.share/lib"
ln -sfn /usr/share/quickshell-share-picker/fixtures "$SCRIPT_DIR/.share/fixtures"
ln -sfn ../Colors.qml "$SCRIPT_DIR/Colors.qml"
ln -sfn ../Motion.qml "$SCRIPT_DIR/Motion.qml"
ln -sfn ../Typography.qml "$SCRIPT_DIR/Typography.qml"
ln -sfn ../Components "$SCRIPT_DIR/Components"

export QSP_SHARE_DIR="$SCRIPT_DIR/.share"
exec quickshell-share-picker "$@"
