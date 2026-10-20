#!/usr/bin/env python3
"""List the anime folders under each root given on the command line, split into parts.

Prints [{"dir", "path": <first episode>, "episodes": N, "year": 2006|null,
         "parts": [{"id", "kind", "label", "path", "episodes", "minutes", "files": [[path, ep], ...]}]}]
with one row per top-level folder (or loose video file) that holds video. A part is a season ("1", "2"..),
the OVAs ("ova"), the specials ("sp") or a single movie ("movie:<slug>"). Openings, endings, menus and
other extras are left out.
"""
import json
import os
import re
import subprocess
import sys

VIDEO = (".mkv", ".mp4", ".avi", ".webm", ".m4v", ".mov", ".ts")
SKIP = re.compile(r"(nc ?op|nc ?ed|creditless|\bpv\b|\bcm\b|menu|trailer|preview|extras?|bonus|特典|\bscans?\b|\bcds?\b)", re.I)
TAGS = re.compile(r"\[[^\]]*\]|【[^】]*】")
CODEC_PARENS = re.compile(r"\([^)]*(?:\d{3,4}p|BD|BDRip|AV1|HEVC|x26[45]|Opus|FLAC|AAC)[^)]*\)", re.I)
KIND_DIR = re.compile(r"(?:^|[\s\-_])(movies?|ova|oad|specials?|sps?)$", re.I)
SEASON = re.compile(r"(?:\bSeason\s*(\d{1,2})\b|(?<![-+])\bS(\d{1,2})\b)(?!\s*[-+]\s*S?\d)", re.I)
CACHE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "quickshell", "immersion", "durations.json")


def clean(s):
    s = CODEC_PARENS.sub(" ", TAGS.sub(" ", s))
    return re.sub(r"\s+", " ", s.replace("_", " ")).strip()


def loose(s):
    return re.sub(r"[\[\]()]", " ", s)


def videos(top):
    found = []
    for base, dirs, files in os.walk(top):
        dirs.sort()
        for f in sorted(files):
            if f.lower().endswith(VIDEO) and not f.startswith("."):
                found.append(os.path.join(base, f))
    return found


def season_of(text):
    m = SEASON.search(text)
    return int(m.group(1) or m.group(2)) if m else 0


def kind_of_dir(name):
    m = KIND_DIR.search(clean(name))
    if not m:
        return ""
    w = m.group(1).lower()
    return "movie" if w.startswith("movie") else "ova" if w in ("ova", "oad") else "sp"


def episode_of(raw, text):
    m = re.search(r"\[(\d{1,3})(?:v\d)?\]", raw)
    if m:
        return int(m.group(1))
    for pat in (r"\sS\d{1,2}\s*-\s*(\d{1,3})(?:v\d)?(?=\s|$)", r"\s[-–]\s*(\d{1,3})(?:v\d)?(?=\s|$|\W)",
                r"\bE(?:P|pisode)?\s*\.?(\d{1,3})\b"):
        m = re.search(pat, text, re.I)
        if m:
            return int(m.group(1))
    return 0


def slug(s):
    return re.sub(r"[^\w]+", "-", s.lower()).strip("-") or "movie"


def classify(top, v, top_season):
    """-> (kind, id, label, ep) or None for extras."""
    comps = os.path.relpath(v, top).split(os.sep) if os.path.isdir(top) else [os.path.basename(v)]
    dirs, fname = comps[:-1], comps[-1]
    stem = os.path.splitext(fname)[0]
    if any(SKIP.search(clean(c)) for c in dirs) or SKIP.search(clean(stem)):
        return None
    text = clean(stem)
    season, ep, kind = 0, 0, ""
    m = re.search(r"\bS(\d{1,2})\s*E(\d{1,3})(?:v\d)?\b", text, re.I)
    if m:
        season, ep = int(m.group(1)), int(m.group(2))
        if season == 0:
            kind = "sp"
    elif (m := re.search(r"\bS(\d{1,2})(OVA|OAD)\b", text, re.I)):
        season, kind = int(m.group(1)), "ova"
    elif (m := re.search(r"\bS(\d{1,2})S(\d{1,3})\b", text, re.I)):
        season, kind = int(m.group(1)), "sp"
    else:
        ep = episode_of(stem, text)
        m = re.search(r"\bS(\d{1,2})\s*-\s*\d{1,3}\b", text)
        if m:
            season = int(m.group(1))
    dkind = ""
    for d in reversed(dirs):
        dkind = kind_of_dir(d)
        if dkind:
            break
    kind = dkind or kind
    if not kind and ep == 0:
        kind = "movie"
    if not season:
        for d in reversed(dirs):
            season = season_of(loose(d))
            if season:
                break
    season = season or top_season or 1
    if kind == "movie":
        label = text.split(" - ", 1)[1] if " - " in text else text
        label = re.sub(r"^S\d+E\d+\s*[-–]?\s*", "", label).strip() or text
        return "movie", "movie:" + slug(label), label, 1
    if kind == "ova":
        return "ova", "ova", "OVA", ep
    if kind == "sp":
        return "sp", "sp", "Specials", ep
    return "season", str(season), "Season %d" % season, ep


def durations(paths):
    try:
        with open(CACHE) as f:
            cache = json.load(f)
    except (OSError, ValueError):
        cache = {}
    out, dirty = {}, False
    for p in paths:
        try:
            st = os.stat(p)
        except OSError:
            continue
        k = "%s|%d|%d" % (p, st.st_size, int(st.st_mtime))
        if k not in cache:
            try:
                r = subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", p],
                                   capture_output=True, text=True, timeout=15)
                cache[k] = round(float(r.stdout.strip()) / 60, 1)
            except (OSError, ValueError, subprocess.SubprocessError):
                continue
            dirty = True
        out[p] = cache[k]
    if dirty:
        live = {"%s|%d|%d" % (p, os.stat(p).st_size, int(os.stat(p).st_mtime)) for p in out}
        try:
            os.makedirs(os.path.dirname(CACHE), exist_ok=True)
            with open(CACHE, "w") as f:
                json.dump({k: v for k, v in cache.items() if k in live or k.split("|")[0] not in out}, f)
        except OSError:
            pass
    return out


def scan(p, n):
    vids = [p] if os.path.isfile(p) else videos(p)
    top_season = 0 if os.path.isfile(p) else season_of(loose(n))
    parts = {}
    for v in vids:
        c = classify(p, v, top_season)
        if c is None:
            continue
        kind, pid, label, ep = c
        part = parts.setdefault(pid, {"id": pid, "kind": kind, "label": label, "files": []})
        part["files"].append([v, ep])
    if not parts:
        return None
    order = {"season": 0, "ova": 1, "sp": 2, "movie": 3}
    out = []
    for part in sorted(parts.values(), key=lambda x: (order[x["kind"]], int(x["id"]) if x["id"].isdigit() else 0, x["label"])):
        part["files"].sort(key=lambda f: (f[1] or 9999, f[0]))
        for i, f in enumerate(part["files"]):
            if part["kind"] != "season" or f[1] == 0:
                f[1] = i + 1
        part["path"] = part["files"][0][0]
        part["episodes"] = len(part["files"])
        out.append(part)
    seasons = [x for x in out if x["kind"] == "season"] or out
    year = re.search(r"\((19\d\d|20\d\d)\)", n)
    return {"dir": p, "path": seasons[0]["path"], "episodes": sum(x["episodes"] for x in seasons),
            "year": int(year.group(1)) if year else None, "parts": out}


shows = []
for root in sys.argv[1:]:
    try:
        names = sorted(os.listdir(root))
    except OSError:
        continue
    for n in names:
        p = os.path.join(root, n)
        if (os.path.isfile(p) and n.lower().endswith(VIDEO)) or os.path.isdir(p):
            s = scan(p, n)
            if s:
                shows.append(s)

# one sample per part is enough for the typical episode (or movie) length
mins = durations([x["path"] for s in shows for x in s["parts"]])
for s in shows:
    for x in s["parts"]:
        x["minutes"] = mins.get(x["path"], 0)
print(json.dumps(shows))
