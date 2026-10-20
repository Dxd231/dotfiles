#!/usr/bin/env python3
"""Lower ModernX's OSC hover point. Run as root: sudo python3 modernx-lower-hover.py [path]

ModernX shows the OSC when the pointer moves in the bottom `bottom_hover_zone` pixels (of 720). The default, 200, is
high enough to cover the subtitle line, so reaching a word always lifts it. This patch shows the OSC only from a thin
bottom strip (`bottom_hover_zone`, 40), and keeps it while the pointer is anywhere over the OSC itself (the
`bottom_keep_zone`, 200). Both can be set in ~/.config/mpv/script-opts/modernx.conf. Safe to run twice; the original is
kept as modernx.lua.orig.

It also stops ModernX showing the OSC when the shell pauses the video itself (hovering a word of the live subtitle):
the shell sets the mpv property user-data/lexicon-hold around that pause. The pacman hook next to this script runs it again after the package is upgraded.
"""
import os
import shutil
import sys

path = sys.argv[1] if len(sys.argv) > 1 else "/etc/mpv/scripts/modernx.lua"
src = open(path, encoding="utf-8").read()
edits = [
    ("    bottom_hover_zone = 200,",
     "    bottom_hover_zone = 40,"),
    ("-- height of hover zone for bottom_hover (in pixels)",
     "-- height of the strip that shows the OSC (in pixels)\n    bottom_keep_zone = 200,                 -- height of the area that keeps it up once shown (in pixels)"),
    ("if mouseY > osc_param.playresy - (user_opts.bottom_hover_zone or 200) or",
     "if mouseY > osc_param.playresy - ((state.osc_visible and user_opts.bottom_keep_zone) or user_opts.bottom_hover_zone or 200) or"),
    ("    if user_opts.show_on_pause then\n        if enabled then",
     "    if user_opts.show_on_pause and not mp.get_property_native(\"user-data/lexicon-hold\") then\n        if enabled then"),
]
changed = False
for old, new in edits:
    if new in src:
        continue
    if src.count(old) != 1:
        sys.exit("unexpected modernx.lua: %r not found exactly once" % old[:50])
    src = src.replace(old, new)
    changed = True
if not changed:
    print("already patched")
    sys.exit(0)
if not os.path.exists(path + ".orig"):
    shutil.copy2(path, path + ".orig")
open(path, "w", encoding="utf-8").write(src)
print("patched", path)
