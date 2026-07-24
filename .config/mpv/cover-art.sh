#!/usr/bin/env bash
# -------------------------------------------------------------
# fetch_mpv_thumbnail.sh
#
# Grab a single 300px‑wide frame at 30 seconds from any media file.
# The script prints the absolute path to the created PNG on stdout.
# If it cannot produce a frame, it prints nothing.
# -------------------------------------------------------------

set -euo pipefail
#!/usr/bin/env bash
# -------------------------------------------------------------
# fetch_mpv_thumbnail.sh – crisp thumbnail for MPV/any video
# -------------------------------------------------------------
set -euo pipefail

# ---- Configuration ------------------------------------------------
THUMB_DIR="${XDG_RUNTIME_DIR:-/tmp}" # where the PNG will be written
THUMB_PATH="${THUMB_DIR}/mpv_thumbnail.png"
TIMESTAMP=30 # seconds to seek
WIDTH=500    # output width (px)
# -------------------------------------------------------------------

# ---- Input validation ---------------------------------------------
if [[ $# -ne 1 ]]; then
  printf "" # signal "no thumbnail"
  exit 0
fi

MEDIA_PATH="$1"

if [[ ! -f "$MEDIA_PATH" || ! -r "$MEDIA_PATH" ]]; then
  printf ""
  exit 0
fi

# ---- Generate thumbnail --------------------------------------------
ffmpeg -hide_banner -loglevel error \
  -i "$MEDIA_PATH" \
  -ss "$TIMESTAMP" \
  -frames:v 1 \
  -vf "scale=${WIDTH}:-1:flags=lanczos" \
  -compression_level 0 \
  -y "$THUMB_PATH" \
  2>/dev/null

# ---- Return the path ------------------------------------------------
if [[ -f "$THUMB_PATH" && -s "$THUMB_PATH" ]]; then
  printf "%s\n" "$THUMB_PATH"
else
  printf ""
fi
