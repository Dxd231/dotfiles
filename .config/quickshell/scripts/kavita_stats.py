#!/usr/bin/env python3
"""Reads Kavita's reading sessions out of its SQLite database (it is world-readable on this machine).

Kavita records, per reading stretch, which series and chapter was open, how many pages were read and
when it started and ended. This turns that into one row per series and day for the shell's Immersion
service. Nothing is written to Kavita.

Writes <state>/quickshell/immersion/kavita.json:
  { updated, latest, rows: [{series, work, volume, day, secs, pages, modified}],
    series: [{id, name, work, volume, pages, read, progress, cover, modified}],
    active, activeSeries, modified, stamp }
and exits straight away when the database files did not change since the last run.

  kavita_stats.py [--out FILE] [--db FILE] [--force]     (env KAVITA_DB overrides the db path)
"""
import argparse
import calendar
import hashlib
import json
import os
import re
import shutil
import sqlite3
import sys
import tempfile
import time

DEFAULT_DB = "/opt/kavita/config/kavita.db"
VERSION = 1
# a stretch is capped so a reader left open (or a jump through the pages) doesn't pile up time
SECS_PER_PAGE_CAP = 180
MIN_CAP = 60
ACTIVE_WINDOW = 300     # a progress save this recent means the reader is open


def utc_epoch(text):
    """'2026-09-17 11:00:55.7158246' or '2026-09-17T11:00:55.7' (UTC) -> epoch seconds."""
    if not text:
        return 0.0
    t = text.replace("T", " ")
    try:
        sec = calendar.timegm(time.strptime(t[:19], "%Y-%m-%d %H:%M:%S"))
    except ValueError:
        return 0.0
    frac = 0.0
    m = re.match(r"^[^.]*(\.\d+)", t[19:] if len(t) > 19 else "")
    if m:
        frac = float(m.group(1))
    return sec + frac


def local_day(epoch):
    return time.strftime("%Y-%m-%d", time.localtime(epoch))


# ---------------------------------------------------------------- naming

VOLUME = re.compile(
    r"^(?P<work>.*?)[\s_\-–]*(?:第\s*(?P<k>\d+)\s*[巻卷]|(?:v|vol\.?|volume)\s*(?P<v>\d+)|#\s*(?P<n>\d+))\D{0,3}$",
    re.IGNORECASE)


BARE_NUMBER = re.compile(r"^(.*[^\d\s].*?)\s+(\d{1,3})$")


def split_name(name):
    """'ご注文はうさぎですか？ 第04巻' -> ('ご注文はうさぎですか？', 'Vol 4')."""
    name = (name or "").strip()
    m = VOLUME.match(name)
    if m and m.group("work").strip():
        num = m.group("k") or m.group("v") or m.group("n")
        return m.group("work").strip().rstrip(" -–_"), "Vol %d" % int(num)
    # a bare number at the end ("... ロータスイーター達の酔醒 7")
    m = BARE_NUMBER.match(name)
    if m:
        return m.group(1).strip(), "Vol %d" % int(m.group(2))
    return name, ""


# -------------------------------------------------------------- database

def stamp_of(db):
    s = {"_version": VERSION}
    for suffix in ("", "-wal"):
        try:
            st = os.stat(db + suffix)
            s[db + suffix] = [st.st_mtime_ns, st.st_size]
        except OSError:
            pass
    return s


def open_copy(db):
    """The database sits in WAL mode in a directory we can't write to, so read a private copy of the
    file and its write-ahead log. Returns (connection, tempdir)."""
    tmp = tempfile.mkdtemp(prefix="kavita-")
    try:
        for suffix in ("", "-wal"):
            if os.path.exists(db + suffix):
                shutil.copyfile(db + suffix, os.path.join(tmp, "k.db" + suffix))
        con = sqlite3.connect(os.path.join(tmp, "k.db"), timeout=2)
        con.execute("select count(*) from Series").fetchone()
        return con, tmp
    except (sqlite3.Error, OSError):
        shutil.rmtree(tmp, ignore_errors=True)
        raise


def copy_cover(config_dir, name, covers_dir):
    if not name:
        return None
    src = os.path.join(config_dir, "covers", name)
    if not os.path.isfile(src):
        return None
    dst = os.path.join(covers_dir, hashlib.sha1(("kavita:" + name).encode()).hexdigest()[:12] + os.path.splitext(name)[1])
    try:
        if not os.path.exists(dst) or os.path.getsize(dst) != os.path.getsize(src):
            os.makedirs(covers_dir, exist_ok=True)
            shutil.copyfile(src, dst + ".tmp")
            os.replace(dst + ".tmp", dst)
    except OSError:
        return None
    return dst


def collect(db, covers_dir):
    con, tmp = open_copy(db)
    try:
        series = {}
        for sid, name, loc, pages, cover in con.execute(
                "select Id, Name, LocalizedName, Pages, CoverImage from Series"):
            work, volume = split_name(name)
            series[sid] = {"id": sid, "name": name, "work": work, "volume": volume, "pages": pages or 0,
                           "read": 0, "progress": None, "cover": None, "modified": 0.0, "_cover": cover}

        # pages read per series, and the newest progress save
        last_progress = 0.0
        last_series = None
        for sid, pages, mod in con.execute(
                "select SeriesId, PagesRead, LastModifiedUtc from AppUserProgresses"):
            s = series.get(sid)
            if not s:
                continue
            s["read"] += pages or 0
            m = utc_epoch(mod)
            s["modified"] = max(s["modified"], m)
            if m > last_progress:
                last_progress, last_series = m, sid
        for s in series.values():
            if s["pages"]:
                s["progress"] = min(1.0, s["read"] / s["pages"])
            s["cover"] = copy_cover(os.path.dirname(db), s.pop("_cover"), covers_dir)

        # reading stretches: the activity table first, then the daily history for what it lacks
        acts = {}

        def add(sid, cid, start, end, pages, name=None):
            if pages is None or pages <= 0:
                return
            if sid not in series:
                # a series that was removed from the library still has its history
                if not name:
                    return
                work, volume = split_name(name)
                series[sid] = {"id": sid, "name": name, "work": work, "volume": volume, "pages": 0, "read": 0,
                               "progress": None, "cover": None, "modified": 0.0}
            key = (sid, cid, int(start))
            if key not in acts:
                acts[key] = (sid, start, end, pages)

        for sid, cid, start, end, pages in con.execute(
                "select SeriesId, ChapterId, StartTimeUtc, EndTimeUtc, PagesRead from AppUserReadingSessionActivityData"):
            add(sid, cid, utc_epoch(start), utc_epoch(end), pages)
        for (data,) in con.execute("select Data from AppUserReadingHistory"):
            try:
                for a in json.loads(data).get("Activities", []):
                    add(a.get("SeriesId"), a.get("ChapterId"), utc_epoch(a.get("StartTimeUtc")),
                        utc_epoch(a.get("EndTimeUtc")), a.get("PagesRead"), a.get("SeriesName"))
            except (ValueError, AttributeError, TypeError):
                continue

        days = {}
        for sid, start, end, pages in acts.values():
            if end < start:
                continue
            secs = min(end - start, max(MIN_CAP, pages * SECS_PER_PAGE_CAP))
            day = local_day(end)
            d = days.setdefault((sid, day), {"secs": 0.0, "pages": 0, "modified": 0.0})
            d["secs"] += secs
            d["pages"] += pages
            d["modified"] = max(d["modified"], end)
            series[sid]["modified"] = max(series[sid]["modified"], end)
        rows = []
        for (sid, day), d in days.items():
            s = series[sid]
            rows.append({"series": s["name"], "work": s["work"], "volume": s["volume"], "sid": sid, "day": day,
                         "secs": d["secs"], "pages": d["pages"], "modified": d["modified"]})
        rows.sort(key=lambda r: (r["day"], r["modified"]))

        active_session = bool(con.execute(
            "select 1 from AppUserReadingSession where IsActive = 1 limit 1").fetchone())
        newest = max([r["modified"] for r in rows] + [last_progress] + [0.0])
        active_series = last_series
        if rows and rows[-1]["modified"] >= last_progress:
            active_series = rows[-1]["sid"]
        active = bool(newest) and (time.time() - newest < ACTIVE_WINDOW or (active_session and time.time() - newest < 3600))
        used = {r["sid"] for r in rows} | {s["id"] for s in series.values() if s["read"] > 0}
        return rows, [s for s in series.values() if s["id"] in used], active, active_series, newest
    finally:
        con.close()
        shutil.rmtree(tmp, ignore_errors=True)


def default_out():
    state = os.environ.get("XDG_STATE_HOME") or os.path.join(os.path.expanduser("~"), ".local", "state")
    return os.path.join(state, "quickshell", "immersion", "kavita.json")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default=default_out())
    ap.add_argument("--db", default=os.environ.get("KAVITA_DB", DEFAULT_DB))
    ap.add_argument("--force", action="store_true")
    a = ap.parse_args()

    if not os.path.exists(a.db):
        return 0
    stamp = stamp_of(a.db)
    if not a.force:
        try:
            with open(a.out) as fh:
                if json.load(fh).get("stamp") == stamp:
                    return 0
        except (OSError, ValueError):
            pass
    try:
        rows, series, active, active_series, newest = collect(a.db, os.path.join(os.path.dirname(a.out), "covers"))
    except (sqlite3.Error, OSError):
        # keep the last good output; the next run tries again
        return 1
    out = {"updated": int(time.time()), "latest": rows[-1]["day"] if rows else "", "rows": rows, "series": series,
           "active": active, "activeSeries": active_series, "modified": newest, "stamp": stamp}
    os.makedirs(os.path.dirname(a.out), exist_ok=True)
    tmp = a.out + ".tmp"
    with open(tmp, "w") as fh:
        json.dump(out, fh, ensure_ascii=False)
    os.replace(tmp, a.out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
