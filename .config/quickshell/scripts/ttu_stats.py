#!/usr/bin/env python3
"""Reads ttu (ッツ Ebook Reader) reading statistics out of LibreWolf / Firefox's IndexedDB files.

ttu keeps one `statistic` row per book per day (characters read, reading time). Firefox stores
IndexedDB values as snappy-compressed structured clones in a SQLite file, so this decodes them
directly: no browser extension and no server. The profile is only ever opened read-only.

Writes <state>/quickshell/immersion/ttu.json for the shell's Immersion service:
  { updated, latest, rows: [{title, day, chars, secs, modified, speed, max}],
    books: [{title, progress, chars, explored, modified}], stamp }
and exits straight away when none of the database files changed since the last run.

  ttu_stats.py [--out FILE] [--profile DIR ...] [--force] [--dump STORE]
"""
import argparse
import glob
import hashlib
import json
import os
import shutil
import sqlite3
import struct
import sys
import tempfile
import time
import re
import unicodedata

# ---------------------------------------------------------------- snappy


def snappy_decompress(b):
    i = 0
    n = 0
    shift = 0
    while True:
        c = b[i]
        i += 1
        n |= (c & 0x7F) << shift
        shift += 7
        if not c & 0x80:
            break
    out = bytearray()
    while i < len(b):
        t = b[i]
        i += 1
        kind = t & 3
        if kind == 0:
            ln = t >> 2
            if ln >= 60:
                nb = ln - 59
                ln = int.from_bytes(b[i:i + nb], "little")
                i += nb
            ln += 1
            out += b[i:i + ln]
            i += ln
        else:
            if kind == 1:
                ln = ((t >> 2) & 7) + 4
                off = ((t >> 5) << 8) | b[i]
                i += 1
            elif kind == 2:
                ln = (t >> 2) + 1
                off = int.from_bytes(b[i:i + 2], "little")
                i += 2
            else:
                ln = (t >> 2) + 1
                off = int.from_bytes(b[i:i + 4], "little")
                i += 4
            if off <= 0 or off > len(out):
                raise ValueError("bad snappy offset")
            for _ in range(ln):
                out.append(out[-off])
    if n != len(out):
        raise ValueError("snappy length mismatch")
    return bytes(out)


# ------------------------------------------------------- structured clone

T_FLOAT_MAX = 0xFFF00000
T_HEADER = 0xFFF10000
T_NULL, T_UNDEFINED, T_BOOLEAN, T_INT32, T_STRING, T_DATE, T_REGEXP, T_ARRAY, T_OBJECT = (
    0xFFFF0000 + k for k in range(9))
T_BACKREF = 0xFFFF000D
T_END = 0xFFFF0013
T_DOM_BLOB = 0xFFFF8001


class Unsupported(Exception):
    pass


class Reader:
    def __init__(self, data):
        self.d = data
        self.p = 0
        # every object, in the order it was met: a later back-reference points into this list
        self.objs = []

    def pair(self):
        if self.p + 8 > len(self.d):
            raise Unsupported("eof")
        lo, hi = struct.unpack_from("<II", self.d, self.p)
        self.p += 8
        return lo, hi

    def double_from(self, lo, hi):
        return struct.unpack("<d", struct.pack("<II", lo, hi))[0]

    def string(self, lo):
        ln = lo & 0x7FFFFFFF
        latin1 = bool(lo & 0x80000000)
        nbytes = ln if latin1 else ln * 2
        raw = self.d[self.p:self.p + nbytes]
        if len(raw) != nbytes:
            raise Unsupported("string overrun")
        self.p += (nbytes + 7) & ~7
        return raw.decode("latin-1" if latin1 else "utf-16-le", errors="replace")

    def value(self, lo, hi, partial=None):
        if hi < T_FLOAT_MAX:
            return self.double_from(lo, hi)
        if hi == T_NULL or hi == T_UNDEFINED:
            return None
        if hi == T_BOOLEAN:
            return bool(lo)
        if hi == T_INT32:
            return lo - (1 << 32) if lo & 0x80000000 else lo
        if hi == T_STRING:
            return self.string(lo)
        if hi == T_DATE:
            a, b = self.pair()
            v = self.double_from(a, b)
            self.objs.append(v)
            return v
        if hi == T_DOM_BLOB:
            # the blob's bytes live in an external file; lo is its index among the row's files.
            # Then comes its size (one word) and its mime type (length word + padded chars)
            a, _ = self.pair()
            n, _ = self.pair()
            self.p += (n + 7) & ~7
            blob = {"_blob": lo, "size": a}
            self.objs.append(blob)
            return blob
        if hi == T_BACKREF:
            if lo >= len(self.objs):
                raise Unsupported("bad back-reference")
            return self.objs[lo]
        if hi == T_OBJECT or hi == T_ARRAY:
            return self.container(hi == T_ARRAY, partial)
        raise Unsupported("tag %08x" % hi)

    def container(self, is_array, partial=None):
        out = [] if is_array else {}
        self.objs.append(out)
        if partial is not None:
            partial.append(out)
        while True:
            lo, hi = self.pair()
            if hi == T_END:
                return out
            if hi == T_STRING:
                key = self.string(lo)
            elif hi == T_INT32:
                key = lo
            else:
                raise Unsupported("key tag %08x" % hi)
            vlo, vhi = self.pair()
            val = self.value(vlo, vhi)
            if is_array:
                if key > 100000:
                    raise Unsupported("sparse array")
                while len(out) <= key:
                    out.append(None)
                out[key] = val
            else:
                out[key] = val


def decode(data, partial_ok=False):
    """Decode one IndexedDB value. With partial_ok, an object that hits something unsupported
    deep inside still returns the fields read before that point."""
    r = Reader(data)
    lo, hi = r.pair()
    if hi != T_HEADER:
        raise Unsupported("no header")
    lo, hi = r.pair()
    if not partial_ok:
        return r.value(lo, hi)
    holder = []
    try:
        return r.value(lo, hi, holder)
    except Unsupported:
        if holder:
            return holder[0]
        raise


# ------------------------------------------------------------- database

STORES = ("statistic", "bookmark", "lastItem", "data")


def idb_files(profiles):
    found = []
    for prof in profiles:
        for pat in ("*ttsu*", "*ttu*"):
            found += glob.glob(os.path.join(prof, "storage", "default", pat, "idb", "*.sqlite"))
    return sorted(set(found))


def stamp_of(files):
    # the version bump makes a changed script re-read an unchanged database
    s = {"_version": 3}
    for f in files:
        for suffix in ("", "-wal"):
            try:
                st = os.stat(f + suffix)
                s[f + suffix] = [st.st_mtime_ns, st.st_size]
            except OSError:
                pass
    return s


def decode_key(blob):
    """A numeric IndexedDB key (type byte 0x10 + the double's bits, sign-adjusted, trailing zero
    bytes dropped). Anything else gives None."""
    b = bytes(blob)
    if not b or b[0] != 0x10:
        return None
    bits = int.from_bytes(b[1:9].ljust(8, b"\0"), "big")
    bits = bits ^ (1 << 63) if bits >> 63 else ~bits & ((1 << 64) - 1)
    v = struct.unpack(">d", bits.to_bytes(8, "big"))[0]
    return int(v) if v == int(v) else v


def open_db(f):
    """Open the browser's database read-only. While the browser has it locked (it checkpoints now
    and then), work on a private copy of the file and its write-ahead log instead. Returns
    (connection, tempdir or None)."""
    for _ in range(2):
        try:
            db = sqlite3.connect("file:%s?mode=ro" % f, uri=True, timeout=1)
            db.execute("select count(*) from object_store").fetchone()
            return db, None
        except sqlite3.Error:
            time.sleep(0.2)
    tmp = tempfile.mkdtemp(prefix="ttu-")
    try:
        for suffix in ("", "-wal"):
            if os.path.exists(f + suffix):
                shutil.copyfile(f + suffix, os.path.join(tmp, "db.sqlite" + suffix))
        db = sqlite3.connect(os.path.join(tmp, "db.sqlite"), timeout=1)
        db.execute("select count(*) from object_store").fetchone()
        return db, tmp
    except (sqlite3.Error, OSError):
        shutil.rmtree(tmp, ignore_errors=True)
        raise


def snappy_frames(b):
    """A snappy stream (the format of the files IndexedDB keeps a big value in)."""
    out = bytearray()
    i = 0
    while i + 4 <= len(b):
        kind, n = b[i], int.from_bytes(b[i + 1:i + 4], "little")
        body = b[i + 4:i + 4 + n]
        i += 4 + n
        if kind == 0:
            out += snappy_decompress(bytes(body[4:]))
        elif kind == 1:
            out += body[4:]
    return bytes(out)


def external_value(files_dir, fids):
    """A value too big for the database sits in the file marked with a leading dot in file_ids."""
    for fid in (fids or "").split():
        if fid.startswith("."):
            try:
                with open(os.path.join(files_dir, fid[1:]), "rb") as fh:
                    return snappy_frames(fh.read())
            except OSError:
                return None
    return None


def read_store(db, name, keys=False, files_dir=None):
    row = db.execute("select id from object_store where name = ?", (name,)).fetchone()
    if not row:
        return []
    out = []
    for key, blob, fids in db.execute("select key, data, file_ids from object_data where object_store_id = ?", (row[0],)):
        # a value too big for the database sits in a separate file and leaves an integer here
        try:
            if isinstance(blob, (bytes, bytearray, memoryview)):
                raw = snappy_decompress(bytes(blob))
            else:
                raw = external_value(files_dir, fids) if files_dir else None
                if raw is None:
                    continue
            val = decode(raw, partial_ok=name == "data")
        except Exception:
            continue
        out.append((decode_key(key), val, fids) if keys else val)
    return out


def cover_of(rec, fids):
    """The external file index of a book's cover: its coverImage blob, else a blob named *cover*."""
    cov = rec.get("coverImage")
    if isinstance(cov, dict) and "_blob" in cov:
        idx = cov["_blob"]
    else:
        idx = None
        for name, v in (rec.get("blobs") or {}).items():
            if isinstance(v, dict) and "_blob" in v and "cover" in str(name).lower():
                idx = v["_blob"]
                break
    ids = (fids or "").split()
    if idx is None or idx >= len(ids):
        return None
    return ids[idx].lstrip(".")


def norm(work):
    return re.sub(r"[\W_]+", "", unicodedata.normalize("NFKC", work).lower())


def describe(title):
    """-> (work, volume, extra) from a book title: 'Title ６ (文庫)' -> ('Title', '6', False)."""
    t = unicodedata.normalize("NFKC", title).strip()
    m = re.match(r"^『(.*?)\s*(\d+(?:\.\d+)?)』", t)
    if m:
        return m.group(1).strip(), m.group(2), True
    t = re.sub(r"\s*\([^()]*\)\s*$", "", t).strip()
    m = re.match(r"^(.*?\S)\s*(\d+(?:\.\d+)?)$", t)
    if m and not re.search(r"\d$", m.group(1)):
        return m.group(1).strip(), m.group(2), False
    return t, "", False


def tag_books(books):
    """Give each book its work, volume and group, so volumes of one work can share a card."""
    for b in books:
        b["work"], b["volume"], b["extra"] = describe(b["title"])
        b["group"] = norm(b["work"])
    for g in {b["group"] for b in books}:
        members = [b for b in books if b["group"] == g]
        if len(members) > 1 and any(b["volume"] for b in members):
            for b in members:
                if not b["volume"]:
                    b["volume"] = "1"


def collect(files, covers_dir):
    failed = 0
    rows = {}
    bookmarks = {}
    items = {}
    last_item = None
    for f in files:
        try:
            db, tmp = open_db(f)
        except (sqlite3.Error, OSError):
            failed += 1
            continue
        try:
            for r in read_store(db, "statistic"):
                if not isinstance(r, dict) or not r.get("title") or not r.get("dateKey"):
                    continue
                key = (r["title"], r["dateKey"])
                mod = r.get("lastStatisticModified") or 0
                if key not in rows or mod >= rows[key]["modified"] * 1000:
                    rows[key] = {
                        "title": r["title"],
                        "day": r["dateKey"],
                        "chars": int(r.get("charactersRead") or 0),
                        "secs": float(r.get("readingTime") or 0),
                        "modified": mod / 1000.0,
                        "speed": float(r.get("lastReadingSpeed") or 0),
                        "max": float(r.get("maxReadingSpeed") or 0),
                    }
            # the book's id is its key, not a field of the value
            for k, r, fids in read_store(db, "data", keys=True, files_dir=os.path.splitext(f)[0] + ".files"):
                if isinstance(r, dict) and k is not None and r.get("title"):
                    items[k] = {"title": r["title"], "chars": r.get("characters"), "cover": None}
                    fid = cover_of(r, fids)
                    src = os.path.join(os.path.splitext(f)[0] + ".files", fid) if fid else None
                    if src and os.path.isfile(src):
                        items[k]["cover"] = copy_cover(src, r["title"], covers_dir)
            for r in read_store(db, "bookmark"):
                if isinstance(r, dict) and r.get("dataId") is not None:
                    bookmarks[r["dataId"]] = r
            for r in read_store(db, "lastItem"):
                if isinstance(r, dict):
                    last_item = r
        except sqlite3.Error:
            pass
        finally:
            db.close()
            if tmp:
                shutil.rmtree(tmp, ignore_errors=True)

    cover_by_title = {it["title"]: it["cover"] for it in items.values() if it.get("cover")}
    books = {}
    for did, bm in bookmarks.items():
        it = items.get(did)
        if not it:
            continue
        chars = it.get("chars")
        explored = bm.get("exploredCharCount")
        prog = bm.get("progress")
        if prog is None and chars and explored is not None:
            prog = explored / chars
        books[it["title"]] = {
            "title": it["title"],
            "progress": float(prog) if prog is not None else None,
            "chars": int(chars) if chars else None,
            "explored": int(explored) if explored is not None else None,
            "modified": (bm.get("lastBookmarkModified") or 0) / 1000.0,
            "cover": cover_by_title.get(it["title"]),
            "id": did,
        }
    # a book that was never bookmarked still shows up through its stats
    for (title, _day) in rows:
        books.setdefault(title, {"title": title, "progress": None, "chars": None, "explored": None, "modified": 0,
                                 "cover": cover_by_title.get(title)})
    # every book in the ttu library is listed, read or not
    for did, it in items.items():
        if it["title"] in books:
            books[it["title"]].setdefault("id", did)
        books.setdefault(it["title"], {"title": it["title"], "progress": None, "chars": int(it["chars"]) if it.get("chars") else None,
                                       "explored": None, "modified": 0, "cover": it.get("cover"), "id": did})
    for b in books.values():
        b.setdefault("cover", cover_by_title.get(b["title"]))
    tag_books(list(books.values()))
    return (sorted(rows.values(), key=lambda r: (r["day"], r["modified"])), list(books.values()), last_item, items,
            failed == len(files) and bool(files))


def copy_cover(src, title, covers_dir):
    """Copy the cover next to the log (once) so the shell never reads the browser's files."""
    name = hashlib.sha1(title.encode("utf-8")).hexdigest()[:12] + ".jpg"
    dst = os.path.join(covers_dir, name)
    try:
        if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src):
            os.makedirs(covers_dir, exist_ok=True)
            shutil.copyfile(src, dst + ".tmp")
            os.replace(dst + ".tmp", dst)
    except OSError:
        return None
    return dst


# ------------------------------------------------------------ estimates

# ttu keeps only the latest bookmark per book. Without its tracker running there is no time or
# character count, so each run compares the bookmark with the one seen last time and turns the
# step into a reading estimate: the time between two saves (a page turn every so often) and the
# characters moved forward.
SESSION_GAP = 240      # seconds; a longer pause between saves starts a new session
SESSION_START = 20     # credited to the first page of a session
MAX_STEP_CHARS = 6000  # a bigger forward move is a seek, not reading


def load_state(path):
    try:
        with open(path) as fh:
            st = json.load(fh)
        if isinstance(st.get("books"), dict):
            return st
    except (OSError, ValueError, AttributeError):
        pass
    return {"books": {}}


def estimate(path, books, real_rows):
    state = load_state(path)
    before = json.dumps(state, sort_keys=True)
    for b in books:
        title, ex, mod = b["title"], b.get("explored"), b.get("modified")
        if ex is None or not mod:
            continue
        st = state["books"].get(title)
        if not isinstance(st, dict) or "mod" not in st:
            state["books"][title] = {"mod": mod, "explored": ex, "days": {}}
            continue
        if mod <= st["mod"]:
            continue
        gap = mod - st["mod"]
        delta = ex - st["explored"]
        jump = delta < 0 or delta > MAX_STEP_CHARS
        if delta != 0:
            day = time.strftime("%Y-%m-%d", time.localtime(mod))
            d = st["days"].setdefault(day, {"secs": 0, "chars": 0, "last": 0})
            if gap <= SESSION_GAP:
                d["secs"] += gap
            elif not jump:
                d["secs"] += SESSION_START
            if 0 < delta <= MAX_STEP_CHARS:
                d["chars"] += delta
            d["last"] = mod
        st["mod"] = mod
        st["explored"] = ex
    if json.dumps(state, sort_keys=True) != before:
        tmp = path + ".tmp"
        os.makedirs(os.path.dirname(path), exist_ok=True)
        with open(tmp, "w") as fh:
            json.dump(state, fh, ensure_ascii=False)
        os.replace(tmp, path)

    real = {(r["title"], r["day"]) for r in real_rows if r["secs"] >= 30}
    out = []
    for title, st in state["books"].items():
        for day, d in (st.get("days") or {}).items():
            if (title, day) in real or d["secs"] <= 0:
                continue
            out.append({"title": title, "day": day, "chars": int(d["chars"]), "secs": float(d["secs"]),
                        "modified": float(d.get("last") or 0),
                        "speed": d["chars"] / (d["secs"] / 3600.0) if d["secs"] else 0.0, "max": 0.0, "est": True})
    return out


def default_out():
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "quickshell", "immersion", "ttu.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=default_out())
    ap.add_argument("--profile", action="append", default=[])
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--dump", metavar="STORE", help="print the decoded rows of one store and exit")
    a = ap.parse_args()

    profiles = a.profile or [p for p in os.environ.get("TTU_PROFILE", "").split(":") if p] or glob.glob(os.path.join(os.path.expanduser("~"), ".librewolf", "*")) \
        + glob.glob(os.path.join(os.path.expanduser("~"), ".mozilla", "firefox", "*"))
    files = idb_files(profiles)

    if a.dump:
        for f in files:
            db, _tmp = open_db(f)
            print(f)
            for r in read_store(db, a.dump):
                print(json.dumps(r, ensure_ascii=False, default=lambda o: "<%s>" % type(o).__name__)[:600])
        return 0

    stamp = stamp_of(files)
    if not a.force:
        try:
            with open(a.out) as fh:
                if json.load(fh).get("stamp") == stamp:
                    return 0
        except (OSError, ValueError):
            pass

    rows, books, last_item, items, unreadable = collect(files, os.path.join(os.path.dirname(a.out), "covers"))
    if unreadable:
        # keep the last good output; the next run tries again (the stamp isn't saved)
        return 1
    rows = sorted(rows + estimate(os.path.join(os.path.dirname(a.out), "ttu-progress.json"), books, rows),
                  key=lambda r: (r["day"], r["modified"]))
    latest = max((r["day"] for r in rows), default="")
    out = {"updated": int(time.time()), "latest": latest, "rows": rows, "books": books, "stamp": stamp,
           "lastTitle": (items.get(last_item.get("dataId"), {}) or {}).get("title") if last_item else None}

    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(out, fh, ensure_ascii=False)
    os.replace(tmp, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
