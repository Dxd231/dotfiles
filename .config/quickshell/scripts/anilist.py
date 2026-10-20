#!/usr/bin/env python3
"""AniList for the shell's library: matches anime series to AniList entries (cover, title, episode count)
and pushes watch progress to the user's list. Input comes in on stdin as JSON, never on argv.

State: <state>/quickshell/immersion/anilist.json
  { matches: {"<key>|<part>": {id, idMal, romaji, native, episodes, siteUrl, cover, color, format, year, related, local} | {miss, at}},
    pins: {"<key>|<part>": id | null}, pushed: {"<mediaId>": progress}, viewer: {name, avatar}|null, clientId }
Token:  <state>/quickshell/anilist-auth.json  {token}  (mode 600, outside the dotfiles repo)

A part is a season number ("1"), "ova", "sp" (never matched unless pinned) or "movie:<slug>".

  anilist.py match     stdin [{key, name, season (the part), label, kind, episodes, minutes, year}]
  anilist.py search    stdin {q}                      -> prints a JSON list
  anilist.py pin       stdin {key, season (the part), id|null, name}
  anilist.py login     stdin {token, clientId}
  anilist.py logout
  anilist.py push      stdin [{id, episode, total}]
  anilist.py client    stdin {clientId}               (remember the client id only)
"""
import json
import difflib
import os
import re
import sys
import tempfile
import time
import urllib.error
import urllib.request

API = "https://graphql.anilist.co"
STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"), "quickshell")
DIR = os.path.join(STATE, "immersion")
FILE = os.path.join(DIR, "anilist.json")
COVERS = os.path.join(DIR, "covers")
AUTH = os.path.join(STATE, "anilist-auth.json")
UA = "quickshell-library/1.0"
MISS_RETRY = 24 * 3600
FORMATS = ("TV", "TV_SHORT", "ONA", "OVA", "MOVIE", "SPECIAL")
SEASON_FORMATS = ("TV", "TV_SHORT", "ONA")


class RateLimited(Exception):
    pass


def load(path, default):
    try:
        with open(path) as f:
            return json.load(f)
    except (OSError, ValueError):
        return default


def save(path, obj, mode=None):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    fd, tmp = tempfile.mkstemp(dir=os.path.dirname(path))
    with os.fdopen(fd, "w") as f:
        json.dump(obj, f, ensure_ascii=False)
    if mode is not None:
        os.chmod(tmp, mode)
    os.replace(tmp, path)


def state():
    s = load(FILE, {})
    for k, d in (("matches", {}), ("pins", {}), ("pushed", {})):
        if not isinstance(s.get(k), dict):
            s[k] = d
    s.setdefault("viewer", None)
    return s


_last = [0.0]


def gql(query, variables, token=None):
    # about one request a second keeps well under the 90 per minute limit
    wait = 1.0 - (time.time() - _last[0])
    if wait > 0:
        time.sleep(wait)
    _last[0] = time.time()
    headers = {"Content-Type": "application/json", "Accept": "application/json", "User-Agent": UA}
    if token:
        headers["Authorization"] = "Bearer " + token
    req = urllib.request.Request(API, json.dumps({"query": query, "variables": variables}).encode(), headers)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            return json.load(r).get("data")
    except urllib.error.HTTPError as e:
        if e.code == 429:
            raise RateLimited()
        return None
    except (urllib.error.URLError, OSError, ValueError):
        return None


MEDIA = """id idMal siteUrl format episodes title { romaji native english } coverImage { extraLarge color }
  startDate { year } duration relations { edges { relationType node { id format } } }"""

SEARCH = "query($q:String){ Page(perPage:8){ media(search:$q, type:ANIME, sort:SEARCH_MATCH){ %s } } }" % MEDIA
BY_ID = "query($id:Int){ Media(id:$id, type:ANIME){ %s } }" % MEDIA


LINKS = ("PREQUEL", "SEQUEL")


def related_of(m):
    edges = (m.get("relations") or {}).get("edges") or []
    return sorted({e["node"]["id"] for e in edges if e.get("relationType") in LINKS})


def entry_of(m, local=0):
    return {"id": m["id"], "idMal": m.get("idMal"), "romaji": (m.get("title") or {}).get("romaji") or "",
            "native": (m.get("title") or {}).get("native") or "", "episodes": m.get("episodes"),
            "siteUrl": m.get("siteUrl") or "https://anilist.co/anime/%d" % m["id"],
            "cover": "", "color": (m.get("coverImage") or {}).get("color") or "",
            "format": m.get("format") or "", "year": (m.get("startDate") or {}).get("year"),
            "related": related_of(m), "local": local,
            "_cover": (m.get("coverImage") or {}).get("extraLarge") or ""}


def fetch_cover(entry):
    url = entry.pop("_cover", "")
    if not url:
        return
    dst = os.path.join(COVERS, "anilist-%d.jpg" % entry["id"])
    if not os.path.exists(dst):
        try:
            os.makedirs(COVERS, exist_ok=True)
            with urllib.request.urlopen(urllib.request.Request(url, headers={"User-Agent": UA}), timeout=20) as r, open(dst + ".part", "wb") as f:
                f.write(r.read())
            os.replace(dst + ".part", dst)
        except (urllib.error.URLError, OSError):
            return
    entry["cover"] = dst


def sequel(media, hops):
    """Follow TV sequels `hops` times (S2 -> the entry for the second season). A movie/OVA that sits between two
    seasons is walked through without counting."""
    steps = 0
    while hops > 0 and steps < hops + 4:
        steps += 1
        edges = [e["node"] for e in (media.get("relations") or {}).get("edges") or [] if e.get("relationType") == "SEQUEL"]
        nxt = next((n["id"] for n in edges if n.get("format") in SEASON_FORMATS), None) or next((n["id"] for n in edges if n.get("format") in ("MOVIE", "OVA", "SPECIAL")), None)
        if nxt is None:
            return media
        data = gql(BY_ID, {"id": nxt})
        if not data or not data.get("Media"):
            return media
        media = data["Media"]
        if media.get("format") in SEASON_FORMATS:
            hops -= 1
    return media


def score(m, it, rank, season):
    """How well an AniList entry fits what is on disk."""
    sc = -0.1 * rank
    fmt = m.get("format")
    if season:
        sc += 1 if fmt in SEASON_FORMATS else -3
    else:
        t = m.get("title") or {}
        want = (it.get("label") or "").lower()
        sc += 3 * max([difflib.SequenceMatcher(None, want, (t.get(x) or "").lower()).ratio() for x in ("romaji", "english")] or [0])
        if fmt == "MOVIE" and it.get("kind") == "movie":
            sc += 2
    year = (m.get("startDate") or {}).get("year")
    if it.get("year") and year == it["year"]:
        sc += 3
    eps, local = m.get("episodes"), int(it.get("episodes") or 0)
    if eps and local and season:
        if eps == local:
            sc += 2
        elif abs(eps - local) == 1:
            sc += 1
        elif eps < local:
            sc -= 2
    dur, mins = m.get("duration"), float(it.get("minutes") or 0)
    if dur and mins:
        if abs(dur - mins) <= 4 or (it.get("kind") == "movie" and dur >= 40 and mins >= 40):
            sc += 1
        elif mins > 2.5 * dur or dur > 2.5 * mins:
            sc -= 1
    return sc


GENERIC_MOVIE = re.compile(r"movie\s*(\d+)", re.I)


def title_of(label):
    """"Movie 3 - Chikai no Finale" -> "Chikai no Finale"; "Movie 1" stays as it is."""
    return re.sub(r"^movie\s*\d+\s*[-–:]\s*", "", label.strip(), flags=re.I)


def queries_of(it):
    name, label, kind = it["name"], title_of(it.get("label") or ""), it.get("kind") or "season"
    if kind == "ova":
        return [name + " OVA"]
    if kind == "movie":
        word = (re.findall(r"\w+", name.lower()) or [""])[0]
        q = [label if word and word in label.lower() else name + " " + label]
        if label not in q and not GENERIC_MOVIE.fullmatch(label):
            q.append(label)
        return q
    return [name]


def root_of(media):
    """The first season of a TV run (walk PREQUEL links back), so that S2/S3 count from the start."""
    for _ in range(8):
        edges = (media.get("relations") or {}).get("edges") or []
        prev = next((e["node"]["id"] for e in edges
                     if e.get("relationType") == "PREQUEL" and e["node"].get("format") in SEASON_FORMATS), None)
        if prev is None:
            break
        data = gql(BY_ID, {"id": prev})
        if not data or not data.get("Media"):
            break
        media = data["Media"]
    return media


def resolve(it, pin, taken=()):
    if pin is not None:
        data = gql(BY_ID, {"id": pin})
        return (data or {}).get("Media")
    part = str(it.get("season") or "1")
    kind = it.get("kind") or ("season" if part.isdigit() else part.split(":")[0])
    it = dict(it, kind=kind)
    media, seen = [], set()
    for q in queries_of(it):
        data = gql(SEARCH, {"q": q})
        for m in ((data or {}).get("Page") or {}).get("media") or []:
            if m.get("format") in FORMATS and m["id"] not in seen:
                seen.add(m["id"])
                media.append(m)
    it = dict(it, label=title_of(it.get("label") or ""))
    if kind == "season":
        n = int(part)
        if not media:
            return None
        ranked = sorted(enumerate(media), key=lambda p: -score(p[1], it if n == 1 else dict(it, episodes=0), p[0], True))
        first = ranked[0][1]
        if n == 1:
            return first
        got = sequel(root_of(first), n - 1)
        if got.get("format") in SEASON_FORMATS and got["id"] not in taken:
            return got
        # the sequel links ran through movies/OVAs and lost the thread: look the season up by name
        found = []
        for q in ("%s %d" % (it["name"], n), "%s season %d" % (it["name"], n)):
            data = gql(SEARCH, {"q": q})
            found += [m for m in ((data or {}).get("Page") or {}).get("media") or []
                      if m.get("format") in SEASON_FORMATS and m["id"] not in taken and m["id"] != first["id"]]
        if not found:
            return got
        return sorted(enumerate(found), key=lambda p: -score(p[1], it, p[0], True))[0][1]
    wanted = ("MOVIE", "SPECIAL", "OVA") if kind == "movie" else ("OVA", "SPECIAL")
    pool = [m for m in media if m.get("format") in wanted and m["id"] not in taken]
    num = GENERIC_MOVIE.fullmatch((it.get("label") or "").strip())
    if kind == "movie" and (not pool or num):
        # "Movie 2": the show's own movies, oldest first
        data = gql(SEARCH, {"q": it["name"]})
        films = [m for m in ((data or {}).get("Page") or {}).get("media") or [] if m.get("format") == "MOVIE"]
        films.sort(key=lambda m: (m.get("startDate") or {}).get("year") or 9999)
        if num and len(films) >= int(num.group(1)):
            pick = films[int(num.group(1)) - 1]
            return pick if pick["id"] not in taken else None
        pool = pool or [m for m in films if m["id"] not in taken]
    if not pool:
        return None
    ranked = sorted(enumerate(pool), key=lambda p: -score(p[1], it, p[0], False))
    return ranked[0][1]


def do_match(items):
    s = state()
    now = time.time()
    # movies with a real title first, so "Movie 2" is left with what the others did not take
    items = sorted(items, key=lambda i: bool(GENERIC_MOVIE.fullmatch(title_of(i.get("label") or ""))))
    try:
        for it in items:
            part = str(it.get("season") or "1")
            k = "%s|%s" % (it["key"], part)
            cur = s["matches"].get(k)
            pinned = k in s["pins"]
            local = int(it.get("episodes") or 0)
            if not pinned and (part == "sp" or (part != "ova" and not part.isdigit() and not part.startswith("movie:"))):
                continue
            if cur and not cur.get("miss"):
                stale = (part.isdigit() and not pinned and cur.get("local") is None
                         and cur.get("episodes") and local > cur["episodes"])
                if stale:
                    s["matches"].pop(k, None)
                    cur = None
                elif "related" not in cur:
                    data = gql(BY_ID, {"id": cur["id"]})
                    m = (data or {}).get("Media")
                    if m:
                        cur.update({"format": m.get("format") or "", "year": (m.get("startDate") or {}).get("year"),
                                    "related": related_of(m)})
                        cur.setdefault("local", local)
                        save(FILE, s)
                    continue
                else:
                    continue
            if cur and cur.get("miss") and now - cur.get("at", 0) < MISS_RETRY and not pinned:
                continue
            if pinned and s["pins"][k] is None:
                s["matches"][k] = {"miss": True, "at": now}
                continue
            taken = {v["id"] for kk, v in s["matches"].items() if kk.startswith(it["key"] + "|") and kk != k and not v.get("miss")}
            m = resolve(it, s["pins"].get(k), taken)
            if m:
                e = entry_of(m, local)
                fetch_cover(e)
                s["matches"][k] = e
            else:
                s["matches"][k] = {"miss": True, "at": now}
            save(FILE, s)
    except RateLimited:
        pass
    save(FILE, s)


def do_search(q):
    data = gql(SEARCH, {"q": q})
    out = []
    for m in ((data or {}).get("Page") or {}).get("media") or []:
        t = m.get("title") or {}
        out.append({"id": m["id"], "romaji": t.get("romaji") or "", "native": t.get("native") or "",
                    "year": (m.get("startDate") or {}).get("year"), "format": m.get("format") or "",
                    "episodes": m.get("episodes"), "cover": (m.get("coverImage") or {}).get("extraLarge") or ""})
    print(json.dumps(out, ensure_ascii=False))


def do_pin(a):
    s = state()
    part = str(a.get("season") or "1")
    k = "%s|%s" % (a["key"], part)
    s["pins"][k] = a.get("id")
    s["matches"].pop(k, None)
    save(FILE, s)
    do_match([{"key": a["key"], "name": a.get("name") or a["key"], "season": part}])


def do_login(a):
    token = (a.get("token") or "").strip()
    data = gql("query{ Viewer { name avatar { large } } }", {}, token) if token else None
    v = (data or {}).get("Viewer")
    if not v:
        print(json.dumps({"ok": False}))
        return
    save(AUTH, {"token": token}, 0o600)
    s = state()
    s["viewer"] = {"name": v["name"], "avatar": (v.get("avatar") or {}).get("large") or ""}
    s["clientId"] = a.get("clientId") or ""
    save(FILE, s)
    print(json.dumps({"ok": True}))


def do_logout():
    try:
        os.remove(AUTH)
    except OSError:
        pass
    s = state()
    s["viewer"] = None
    save(FILE, s)


def do_push(items):
    token = load(AUTH, {}).get("token")
    if not token:
        return
    s = state()
    try:
        for it in items:
            mid, ep, total = int(it["id"]), int(it["episode"]), it.get("total")
            if ep <= int(s["pushed"].get(str(mid), 0)):
                continue
            data = gql("query($id:Int){ Media(id:$id){ mediaListEntry { progress status } } }", {"id": mid}, token)
            if data is None:
                continue
            cur = (data.get("Media") or {}).get("mediaListEntry") or {}
            # only ever move forward, and leave finished entries alone
            if cur.get("status") in ("COMPLETED", "REPEATING") or ep <= int(cur.get("progress") or 0):
                s["pushed"][str(mid)] = max(ep, int(cur.get("progress") or 0))
                continue
            status = "COMPLETED" if total and ep >= int(total) else "CURRENT"
            r = gql("mutation($id:Int,$p:Int,$s:MediaListStatus){ SaveMediaListEntry(mediaId:$id, progress:$p, status:$s){ id } }",
                    {"id": mid, "p": ep, "s": status}, token)
            if r:
                s["pushed"][str(mid)] = ep
    except RateLimited:
        pass
    save(FILE, s)


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd == "logout":
        return do_logout()
    try:
        arg = json.loads(sys.stdin.read() or "null")
    except ValueError:
        return
    try:
        if cmd == "match":
            do_match(arg or [])
        elif cmd == "search":
            do_search((arg or {}).get("q") or "")
        elif cmd == "pin":
            do_pin(arg)
        elif cmd == "login":
            do_login(arg or {})
        elif cmd == "push":
            do_push(arg or [])
        elif cmd == "client":
            s = state()
            s["clientId"] = (arg or {}).get("clientId") or ""
            save(FILE, s)
    except RateLimited:
        pass


if __name__ == "__main__":
    main()
