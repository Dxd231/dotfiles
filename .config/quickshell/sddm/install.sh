#!/bin/sh
# Builds the theme and installs it to /usr/share/sddm/themes/quickshell (needs sudo), points SDDM at
# it, and makes state/ writable by the current user so sync.sh runs without sudo.
#   sudo -E ./install.sh      (or run as your user; it will call sudo itself)
set -e
SRC="$(cd "$(dirname "$0")" && pwd)"
ME="${SUDO_USER:-$USER}"
DEST=/usr/share/sddm/themes/quickshell

"$SRC/build.sh" /tmp/quickshell-sddm-build
sudo rm -rf "$DEST"
sudo cp -r /tmp/quickshell-sddm-build "$DEST"
sudo chown -R root:root "$DEST"
sudo chown "$ME" "$DEST/state"
printf '[Theme]\nCurrent=quickshell\n' | sudo tee /etc/sddm.conf.d/theme.conf >/dev/null
# /etc/sddm.conf is read after /etc/sddm.conf.d/*, so a theme named there overrides the snippet
if [ -f /etc/sddm.conf ] && grep -q '^Current=' /etc/sddm.conf; then
    sudo sed -i 's/^Current=.*/Current=quickshell/' /etc/sddm.conf
fi
THEME_DIR="$DEST" "$SRC/sync.sh"
echo "installed; to roll back set Current= to material-you-dark in /etc/sddm.conf (the old theme is still in /usr/share/sddm/themes)"
