#!/usr/bin/env python3
import sys
import os
import json
import re
import hashlib
import unicodedata
import urllib.request
import urllib.parse
import base64
import concurrent.futures

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"
CACHE_DIR = os.path.expanduser("~/.cache/quickshell_lyrics")
os.makedirs(CACHE_DIR, exist_ok=True)

def get_cache_path(title, artist):
    key = f"v8_{title.strip().lower()}___{artist.strip().lower()}".encode("utf-8")
    return os.path.join(CACHE_DIR, f"{hashlib.sha256(key).hexdigest()}.json")

def save_cache(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            json.dump(data, f, ensure_ascii=False)
    except Exception:
        pass

def normalize(s):
    return unicodedata.normalize("NFKC", str(s or "")).strip().lower()

def artist_tokens(artist):
    s = normalize(artist)
    tokens = set(re.findall(r"[\w\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]{2,}", s))
    tokens.difference_update({"feat", "featuring", "with", "and", "cv"})
    return tokens

def match_artist(target, candidate):
    if not target or not candidate:
        return True
    t_toks = artist_tokens(target)
    if isinstance(candidate, (list, tuple, set)):
        c_toks = set().union(*(artist_tokens(c) for c in candidate))
    else:
        c_toks = artist_tokens(candidate)
    return bool(t_toks & c_toks)

def match_duration(target_sec, cand_sec, tolerance=8.0):
    if target_sec and cand_sec:
        return abs(target_sec - cand_sec) <= tolerance
    return True

def is_instrumental(title, album=""):
    pattern = (
        r"\b(?:instrumental|off[\s\-_]*vocals?|backing[\s\-_]*tracks?|karaoke|without[\s\-_]*vocals?)\b|"
        r"インスト|オフボーカル|伴奏|純音楽|纯音乐|超絶(?:PIANO|piano|ピアノ)"
    )
    return bool(re.search(pattern, f"{title} {album}", re.IGNORECASE))

def clean_lrc_line(text):
    if not text:
        return ""
    # Remove unclosed NetEase bracket annotations (e.g. "いっしょのときは 〖")
    text = re.sub(r"\s*〖[^〗]*$", "", text)
    # Remove complete 〖...〗 transcriber annotations
    text = re.sub(r"\s*〖.*?〗", "", text)
    return text.strip()

def is_credit_or_meta(text, title="", artist="", time=None):
    t = text.strip()
    if not t:
        return True

    # 1. Staff & creator credits. CJK role words and "<role> by" forms are credits even without a
    #    colon ("作曲・X", "Written by X"). Bare English words need a colon: without it, ordinary
    #    lyrics that start with them ("Music in the air", "Drums are beating") were dropped.
    credit_re = re.compile(
        r"^(?:(?:作?[词詞曲]|编[曲劇]|編[曲劇]|制作|製作|監[制製]|和声|コーラス|录音|録音|混音|ミキシング|マスタリング|"
        r"演唱|歌手|歌|唄|演奏|吉他|ギター|贝斯|ベース|鼓|ドラム|键盘|キーボード|钢琴|ピアノ|弦乐|ストリングス|"
        r"歌[词詞][提製制]供?|字幕|翻[译譯])(?:\s*[:：・･·]|\s)|"
        r"(?:Written|Produced|Arranged|Composed|Lyrics|Music|Vocals?|Mixed|Mastered|Recorded|Performed|Translated)\s+by\b|"
        r"(?:Written|Produced|Arranged|Composed|Lyrics|Music|Vocals?|Mixed|Mastered|Recorded|Performed|"
        r"Guitar|Bass|Drums|Piano|Keyboard|Strings|Artist|Title|Album|Track|LRC|Translated|Offset|Source|Credit)\s*[:：])",
        re.I
    )
    if credit_re.match(t):
        return True

    # 2. End markers
    if re.match(r"^(?:[〜～~—\s]*)(?:終わり|おわり|オワリ|the\s+end|fin|end)(?:[〜～~—\s]*)$", t, re.I):
        return True

    # 3. Transcriber signatures & uploader notes
    if re.search(r"(?:网易云音乐|QQ音乐|酷狗音乐|酷我音乐|spicetify|lrclib|lrc\s+by)", t, re.I):
        return True

    # 4. Title cards enclosed in quotes/brackets or exact match
    #    A bare line equal to the title is only a title card at the very start; later on it is
    #    usually the chorus ("Stay" in a song called "Stay"), so keep it.
    stripped = t.strip("「」『』【】《》\"' ").lower()
    clean_title = re.sub(r"\s*[\(\[～~].*?[\)\]～~]", "", title or "").strip().lower()
    if stripped and clean_title and (stripped == clean_title or stripped == (title or "").lower()):
        wrapped = stripped != t.lower()
        if wrapped or (time is not None and time < 3.0):
            return True

    return False

def lyric_coverage(lines):
    return sum(len(re.sub(r"\s+", "", l.get("text", ""))) for l in lines)

def add_interlude_dots(lines, min_gap=5.0):
    if not lines or len(lines) < 2:
        return lines

    result = []
    # Intro interlude if first lyric starts after min_gap
    if lines[0]["time"] >= min_gap:
        result.append({"time": 1.0, "text": "• • •", "endTime": lines[0]["time"]})

    for i in range(len(lines)):
        result.append(lines[i])
        if i + 1 < len(lines):
            cur = lines[i]
            nxt = lines[i + 1]
            end_t = cur.get("endTime")
            if end_t is None:
                txt_len = len(cur.get("text", ""))
                end_t = round(cur["time"] + min(5.0, max(2.0, txt_len * 0.28 + 0.6)), 2)

            gap = nxt["time"] - end_t
            if gap >= min_gap:
                dot_time = round(end_t + 0.4, 2)
                result.append({"time": dot_time, "text": "• • •", "endTime": nxt["time"]})

    return result

def parse_lrclib_lyricsfile(raw, title="", artist=""):
    if not raw:
        return []
    lines = []
    blocks = raw.split("- text:")
    for b in blocks:
        if not b.strip():
            continue
        m_start = re.search(r"start_ms:\s*(\d+)", b)
        if not m_start:
            continue
        text_part = b[:m_start.start()].strip()
        text = re.sub(r"^['\"]|['\"]$", "", text_part).strip()
        text = clean_lrc_line(text)
        s_ms = int(m_start.group(1))
        if not text or is_credit_or_meta(text, title=title, artist=artist, time=s_ms / 1000.0):
            continue
        m_end = re.search(r"end_ms:\s*(\d+)", b[m_start.end():])
        e_ms = int(m_end.group(1)) if m_end else None

        start_t = round(s_ms / 1000.0, 2)
        end_t = round(e_ms / 1000.0, 2) if e_ms else None
        item = {"time": start_t, "text": text}
        if end_t and end_t > start_t:
            item["endTime"] = end_t
        lines.append(item)
    return lines

def parse_lrc(lrc_text, title="", artist=""):
    if not lrc_text:
        return []
    raw_items = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        times = re.findall(r"\[(\d+):(\d+(?:\.\d+)?)\]", raw)
        if not times:
            continue
        text = re.sub(r"\[\d+:\d+(?:\.\d+)?\]", "", raw).strip()
        text = clean_lrc_line(text)
        for m, s in times:
            t = round(int(m) * 60 + float(s), 2)
            raw_items.append((t, text))

    raw_items.sort(key=lambda x: x[0])

    lines = []
    for t, text in raw_items:
        if not text:
            # Blank line with timestamp indicates vocal cutoff / end of preceding lyric line
            if lines and "endTime" not in lines[-1]:
                if t > lines[-1]["time"]:
                    lines[-1]["endTime"] = t
            continue
        if is_credit_or_meta(text, title=title, artist=artist, time=t):
            continue
        if t == 0.0 and (" - " in text or ":" in text or "：" in text):
            continue
        lines.append({"time": t, "text": text})

    return lines

def fetch_lrclib(title, artist, album="", duration=0):
    dur_sec = (duration / 1000000.0) if duration > 10000 else duration
    clean_t = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()
    candidates = [title] if clean_t == title else [title, clean_t]

    for cand in candidates:
        params = {"track_name": cand, "artist_name": artist}
        if album:
            params["album_name"] = album
        if dur_sec:
            params["duration"] = int(dur_sec)

        # 1. Exact get
        try:
            req = urllib.request.Request(f"https://lrclib.net/api/get?{urllib.parse.urlencode(params)}", headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=3) as resp:
                d = json.loads(resp.read().decode("utf-8"))
                if not d.get("instrumental") and match_artist(artist, d.get("artistName")) and match_duration(dur_sec, d.get("duration")):
                    if d.get("lyricsfile"):
                        lines = parse_lrclib_lyricsfile(d["lyricsfile"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if d.get("syncedLyrics"):
                        lines = parse_lrc(d["syncedLyrics"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if d.get("plainLyrics"):
                        lines = [{"time": -1, "text": l} for l in d["plainLyrics"].splitlines() if l.strip() and not is_credit_or_meta(l, title=cand, artist=artist)]
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": False, "lines": lines}
        except Exception:
            pass

        # 2. Search fallback
        try:
            req = urllib.request.Request(f"https://lrclib.net/api/search?{urllib.parse.urlencode(params)}", headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=3) as resp:
                items = json.loads(resp.read().decode("utf-8"))
                for item in (items if isinstance(items, list) else []):
                    if item.get("instrumental") or not match_artist(artist, item.get("artistName")) or not match_duration(dur_sec, item.get("duration")):
                        continue
                    if item.get("lyricsfile"):
                        lines = parse_lrclib_lyricsfile(item["lyricsfile"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if item.get("syncedLyrics"):
                        lines = parse_lrc(item["syncedLyrics"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if item.get("plainLyrics"):
                        lines = [{"time": -1, "text": l} for l in item["plainLyrics"].splitlines() if l.strip() and not is_credit_or_meta(l, title=cand, artist=artist)]
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": False, "lines": lines}
        except Exception:
            pass

    return None

def fetch_netease(title, artist, duration=0):
    dur_sec = (duration / 1000000.0) if duration > 10000 else duration
    clean_t = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()
    candidates = [title] if clean_t == title else [title, clean_t]

    seen_ids = set()
    for cand in candidates:
        q = f"{cand} {artist}".strip()
        url = f"https://music.163.com/api/search/get?s={urllib.parse.quote(q)}&type=1&limit=5"
        try:
            req = urllib.request.Request(url, headers={"Referer": "https://music.163.com/", "User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=3) as resp:
                songs = json.loads(resp.read().decode("utf-8")).get("result", {}).get("songs", [])
                for s in songs:
                    sid = s.get("id")
                    if not sid or sid in seen_ids:
                        continue
                    seen_ids.add(sid)

                    cand_artists = [a.get("name", "") for a in s.get("artists", [])]
                    if not match_artist(artist, cand_artists) or not match_duration(dur_sec, s.get("duration", 0) / 1000.0):
                        continue

                    lreq = urllib.request.Request(f"https://music.163.com/api/song/lyric?id={sid}&lv=1&kv=1&tv=-1",
                                                  headers={"Referer": "https://music.163.com/", "User-Agent": USER_AGENT})
                    with urllib.request.urlopen(lreq, timeout=3) as lresp:
                        ld = json.loads(lresp.read().decode("utf-8"))
                        if ld.get("nolyric") or ld.get("uncollected"):
                            continue
                        lrc = ld.get("lrc", {}).get("lyric", "")
                        if not lrc or "纯音乐" in lrc or "没有填词" in lrc:
                            continue
                        lines = parse_lrc(lrc, title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "NetEase", "synced": True, "lines": lines}
        except Exception:
            pass

    return None

def fetch_kugou(title, artist, duration=0):
    dur_sec = (duration / 1000000.0) if duration > 10000 else duration
    clean_t = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()
    candidates = [title] if clean_t == title else [title, clean_t]

    for cand in candidates:
        q = f"{cand} {artist}".strip()
        url = f"http://mobilecdn.kugou.com/api/v3/search/song?format=json&keyword={urllib.parse.quote(q)}&page=1&pagesize=5"
        try:
            req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=3) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                songs = data.get("data", {}).get("info", [])
                for s in songs:
                    shash = s.get("hash")
                    sdur = s.get("duration", 0)
                    if not shash:
                        continue
                    if not match_artist(artist, s.get("singername")) or not match_duration(dur_sec, sdur):
                        continue

                    # Search lyric candidates
                    lurl = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration={sdur * 1000}&hash={shash}"
                    lreq = urllib.request.Request(lurl, headers={"User-Agent": USER_AGENT})
                    with urllib.request.urlopen(lreq, timeout=3) as lresp:
                        ldata = json.loads(lresp.read().decode("utf-8"))
                        cand_list = ldata.get("candidates", [])
                        if not cand_list:
                            continue
                        cand_lrc = cand_list[0]
                        cid = cand_lrc.get("id")
                        ackey = cand_lrc.get("accesskey")

                        # Download lyric
                        durl = f"http://krcs.kugou.com/download?ver=1&client=mobi&id={cid}&accesskey={ackey}&fmt=lrc&charset=utf8"
                        dreq = urllib.request.Request(durl, headers={"User-Agent": USER_AGENT})
                        with urllib.request.urlopen(dreq, timeout=3) as dresp:
                            ddata = json.loads(dresp.read().decode("utf-8"))
                            content = ddata.get("content")
                            if content:
                                lrc = base64.b64decode(content).decode("utf-8", errors="ignore")
                                lines = parse_lrc(lrc, title=cand, artist=artist)
                                if len(lines) >= 3:
                                    return {"source": "Kugou", "synced": True, "lines": lines}
        except Exception:
            pass

    return None

def main():
    if len(sys.argv) < 3:
        print(json.dumps({"success": False, "message": "Usage: fetch_lyrics.py <title> <artist> [album] [duration]"}))
        return

    title = sys.argv[1]
    artist = sys.argv[2]
    album = sys.argv[3] if len(sys.argv) > 3 else ""
    try:
        duration = float(sys.argv[4]) if len(sys.argv) > 4 and sys.argv[4] else 0
    except (ValueError, TypeError):
        duration = 0

    cache_file = get_cache_path(title, artist)
    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                cached = json.load(f)
                if cached.get("success") and cached.get("lines"):
                    print(json.dumps(cached, ensure_ascii=False))
                    return
        except Exception:
            pass

    # Source prioritization:
    # For CJK / Japanese tracks, query NetEase and Kugou first (authentic Japanese Kanji), then LRCLIB.
    # For Western / non-CJK tracks, query LRCLIB first, then NetEase, Kugou.
    is_cjk = bool(re.search(r"[\u3040-\u30ff\u3400-\u4dbf\u4e00-\u9fff]", f"{title} {artist}"))
    order = [fetch_netease, fetch_kugou, fetch_lrclib] if is_cjk else [fetch_lrclib, fetch_netease, fetch_kugou]

    def run(fetcher):
        try:
            if fetcher == fetch_lrclib:
                return fetcher(title, artist, album=album, duration=duration)
            return fetcher(title, artist, duration=duration)
        except Exception:
            return None

    # Query every source at once: the first synced hit isn't necessarily the most complete one
    # (NetEase often blanks out English lines that Kugou/LRCLIB have).
    with concurrent.futures.ThreadPoolExecutor(max_workers=len(order)) as pool:
        results = list(pool.map(run, order))

    synced_result = None
    plain_result = None
    for res in results:
        if not res or not res.get("lines"):
            continue
        if res.get("synced"):
            # Keep the higher-priority source unless a later one is clearly more complete.
            if synced_result is None or lyric_coverage(res["lines"]) > lyric_coverage(synced_result["lines"]) * 1.15:
                synced_result = res
        elif not plain_result:
            plain_result = res

    result = synced_result or plain_result

    if result and result.get("lines"):
        lines_with_dots = add_interlude_dots(result["lines"])
        out = {
            "success": True,
            "source": result.get("source", "Unknown"),
            "synced": result.get("synced", True),
            "title": title,
            "artist": artist,
            "lines": lines_with_dots
        }
        save_cache(cache_file, out)
        print(json.dumps(out, ensure_ascii=False))
    else:
        out = {"success": False, "message": "Lyrics not found", "title": title, "artist": artist}
        print(json.dumps(out, ensure_ascii=False))

if __name__ == "__main__":
    main()

