#!/usr/bin/env python3
"""Find a thumbnail image for each anime directory given on the command line.

Prints {"<dir>": "<image path>"} for the directories that have one. The directory itself is searched
first, then its parent (a season folder inherits the series folder's art) unless the parent is generic.
"""
import json
import os
import re
import sys

EXTS = (".jpg", ".jpeg", ".png", ".webp", ".avif", ".bmp")
PREFER = ["cover", "poster", "folder", "thumb", "thumbnail", "banner", "fanart"]
GENERIC = re.compile(r"^(videos?|downloads?|animes?|tv|tmp|media|shows?)$", re.I)


def pick(d):
    try:
        names = sorted(f for f in os.listdir(d) if f.lower().endswith(EXTS) and os.path.isfile(os.path.join(d, f)))
    except OSError:
        return None
    if not names:
        return None
    for want in PREFER:
        for f in names:
            if os.path.splitext(f)[0].lower() == want:
                return os.path.join(d, f)
    return os.path.join(d, names[0])


def usable_parent(p):
    home = os.path.expanduser("~")
    return p not in ("/", home) and not os.path.ismount(p) and not GENERIC.match(os.path.basename(p))


out = {}
for d in sys.argv[1:]:
    img = pick(d)
    if img is None:
        parent = os.path.dirname(d.rstrip("/"))
        if usable_parent(parent):
            img = pick(parent)
    if img:
        out[d] = img
print(json.dumps(out))
