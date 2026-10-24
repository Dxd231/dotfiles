#!/bin/sh
# Builds qs-manga and installs it to ~/.local/bin. Build output stays out of the dotfiles tree.
set -e
cd "$(dirname "$0")"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-$HOME/.cache/qs-manga/target}"
cargo build --release
mkdir -p "$HOME/.local/bin"
install -m 755 "$CARGO_TARGET_DIR/release/qs-manga" "$HOME/.local/bin/qs-manga"
echo "installed $HOME/.local/bin/qs-manga"
