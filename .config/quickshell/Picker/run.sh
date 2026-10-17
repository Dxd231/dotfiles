#!/usr/bin/env bash
# Wrapper to run your custom Quickshell share picker instance
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

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
