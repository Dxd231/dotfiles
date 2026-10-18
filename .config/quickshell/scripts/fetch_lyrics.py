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
import difflib
import time

USER_AGENT = "Mozilla/5.0 (X11; Linux x86_64; rv:120.0) Gecko/20100101 Firefox/120.0"
CACHE_DIR = os.path.expanduser("~/.cache/quickshell_lyrics")
os.makedirs(CACHE_DIR, exist_ok=True)

def get_cache_path(title, artist):
    key = f"v11_{title.strip().lower()}___{artist.strip().lower()}".encode("utf-8")
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

# Second-pass mode for romanised titles ("watasi tati mo koisita gensoukyou"): the title can't be
# compared with the source's kanji one, so only the artist and a tight duration identify the song.
LOOSE = {"on": False}

def match_duration(target_sec, cand_sec, tolerance=8.0):
    if LOOSE["on"]:
        tolerance = 2.5
    if target_sec and cand_sec:
        return abs(target_sec - cand_sec) <= tolerance
    return True

def is_instrumental(title, album=""):
    pattern = (
        r"\b(?:instrumental|off[\s\-_]*vocals?|backing[\s\-_]*tracks?|karaoke|without[\s\-_]*vocals?)\b|"
        r"インスト|オフボーカル|伴奏|純音楽|纯音乐|超絶(?:PIANO|piano|ピアノ)"
    )
    return bool(re.search(pattern, f"{title} {album}", re.IGNORECASE))

# Sources that raised or timed out during this run (a failed source can hide a better answer).
FAILED = set()

def title_core(s):
    """A title reduced to what identifies the song: no bracketed glosses ("(移动、移动)"), no
    "～チノVer.～" / " - Remastered" tails, no spaces or punctuation."""
    s = normalize(s)
    s = re.sub(r"\s*[\(\[（【〔].*?[\)\]）】〕]", "", s)
    s = re.sub(r"\s*[～~〜].*?[～~〜]\s*$", "", s)
    s = re.sub(r"\s+[-–—]\s+.*$", "", s)
    return re.sub(r"[\W_]+", "", s)

def match_title(target, cand):
    """Is `cand` the same song as `target`? Search endpoints return the artist's other songs when the
    keyword is a little off, so every hit has to be checked, not just its artist and duration."""
    if not target or not cand:
        return True
    if is_instrumental(cand) and not is_instrumental(target):
        return False
    a, b = title_core(target), title_core(cand)
    if not a or not b or a == b:
        return True
    short, long_ = sorted((a, b), key=len)
    if len(short) >= 3 and short in long_:
        return True
    return difflib.SequenceMatcher(None, a, b).ratio() >= 0.72

def title_ok(target, cand):
    return LOOSE["on"] or match_title(target, cand)

def search_artist(artist):
    """Artist for search keywords: Spotify sometimes truncates "チノ(水瀬いのり)" to "チノ(水瀬いのり"."""
    return " ".join(re.sub(r"[()（）\[\]【】]", " ", artist or "").split())

# "<names> - <title>" cards some sources put on the first line.
HEADER_RE = re.compile(r"^(.{1,60}?)\s+[-–—]\s+(.{1,60})$")

def check_header(lines, title):
    """Drop a leading "<names> - <title>" card when it names this song; None when it names another
    one (the whole result belongs to a different song)."""
    for l in lines[:3]:
        if l["time"] >= 5:
            break
        m = HEADER_RE.match(l["text"])
        if not m:
            continue
        if not (LOOSE["on"] or match_title(title, m.group(2))):
            return None
        return [x for x in lines if x is not l]
    return lines

def line_set(lines):
    return {re.sub(r"[\W_]+", "", normalize(l["text"])) for l in lines if l["text"].strip("• ")} - {""}

def agreement(a, b):
    """How much of the smaller lyric also appears in the other (1.0 when either is empty)."""
    sa, sb = line_set(a), line_set(b)
    return len(sa & sb) / min(len(sa), len(sb)) if sa and sb else 1.0

def clean_lrc_line(text):
    if not text:
        return ""
    # Remove unclosed NetEase bracket annotations (e.g. "いっしょのときは 〖")
    text = re.sub(r"\s*〖[^〗]*$", "", text)
    # Remove complete 〖...〗 transcriber annotations
    text = re.sub(r"\s*〖.*?〗", "", text)
    return text.strip()

# Set by main(): True when the playing track looks Japanese (kana in title / artist / album).
TRACK_CONTEXT = {"japanese": False}

HAN_RE = re.compile(r"[\u3400-\u4dbf\u4e00-\u9fff]")
KANA_RE = re.compile(r"[\u3040-\u30ff]")
# Notices streaming sites put on speech-recognition "lyrics" (e.g. Kugou's "本字幕由TME AI技术生成").
# Those transcripts are invented for instrumentals and unreliable elsewhere, so the whole result is dropped.
AI_LYRICS_RE = re.compile(
    r"字幕由.{0,12}(?:AI|人工智能)|(?:AI|人工智能)\s*(?:技术|技術)?\s*生成|由.{0,12}AI.{0,6}生成|"
    r"(?:ai|auto)[\s\-]*generated|generated\s+by\s+(?:ai|tme)",
    re.I,
)

def looks_chinese(texts):
    """True when most lines are Han-only (no kana): Chinese lyrics rather than Japanese ones."""
    texts = [t for t in texts if t.strip()]
    if not texts:
        return False
    han_only = sum(1 for t in texts if HAN_RE.search(t) and not KANA_RE.search(t))
    with_kana = sum(1 for t in texts if KANA_RE.search(t))
    return han_only >= 0.5 * len(texts) and with_kana <= 0.05 * len(texts)

def lyrics_unusable(texts):
    if any(AI_LYRICS_RE.search(t) for t in texts):
        return True
    # a Japanese track whose "lyrics" are Chinese is a wrong match or a translation
    return TRACK_CONTEXT["japanese"] and looks_chinese(texts)

def usable(lines):
    return [] if lyrics_unusable([l["text"] for l in lines]) else lines

def has_japanese(text):
    return bool(KANA_RE.search(text) or HAN_RE.search(text))

def japanese_share(lines):
    texts = [l["text"] for l in lines if l["text"].strip("• ")]
    return sum(1 for t in texts if has_japanese(t)) / len(texts) if texts else 0

def drop_translations(lines):
    """Collapse lines that share a timestamp: a translation or romaji printed under each original.
    On a Japanese track the line containing kana / Han is the one kept."""
    out = []
    for l in lines:
        if out and abs(l["time"] - out[-1]["time"]) <= 0.05:
            if TRACK_CONTEXT["japanese"] and not has_japanese(out[-1]["text"]) and has_japanese(l["text"]):
                out[-1] = l
            continue
        out.append(l)
    return out

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
    lines = check_header(usable(drop_translations(lines)), title)
    return lines or []

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

    lines = check_header(usable(drop_translations(lines)), title)
    return lines or []

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
                if not d.get("instrumental") and match_artist(artist, d.get("artistName")) and title_ok(title, d.get("trackName")) and match_duration(dur_sec, d.get("duration")):
                    if d.get("lyricsfile"):
                        lines = parse_lrclib_lyricsfile(d["lyricsfile"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if d.get("syncedLyrics"):
                        lines = parse_lrc(d["syncedLyrics"], title=cand, artist=artist)
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": True, "lines": lines}
                    if d.get("plainLyrics"):
                        lines = usable([{"time": -1, "text": l} for l in d["plainLyrics"].splitlines() if l.strip() and not is_credit_or_meta(l, title=cand, artist=artist)])
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": False, "lines": lines}
        except Exception:
            FAILED.add("LRCLIB")

        # 2. Search fallback
        try:
            req = urllib.request.Request(f"https://lrclib.net/api/search?{urllib.parse.urlencode(params)}", headers={"User-Agent": USER_AGENT})
            with urllib.request.urlopen(req, timeout=3) as resp:
                items = json.loads(resp.read().decode("utf-8"))
                for item in (items if isinstance(items, list) else []):
                    if item.get("instrumental") or not match_artist(artist, item.get("artistName")) or not title_ok(title, item.get("trackName")) or not match_duration(dur_sec, item.get("duration")):
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
                        lines = usable([{"time": -1, "text": l} for l in item["plainLyrics"].splitlines() if l.strip() and not is_credit_or_meta(l, title=cand, artist=artist)])
                        if len(lines) >= 3:
                            return {"source": "LRCLIB", "synced": False, "lines": lines}
        except Exception:
            FAILED.add("LRCLIB")

    return None

def fetch_netease(title, artist, duration=0):
    dur_sec = (duration / 1000000.0) if duration > 10000 else duration
    clean_t = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()
    candidates = [title] if clean_t == title else [title, clean_t]

    seen_ids = set()
    for cand in candidates:
        q = f"{cand} {search_artist(artist)}".strip()
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
                    if not match_artist(artist, cand_artists) or not title_ok(title, s.get("name")) or not match_duration(dur_sec, s.get("duration", 0) / 1000.0):
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
            FAILED.add("NetEase")

    return None

def fetch_kugou(title, artist, duration=0):
    dur_sec = (duration / 1000000.0) if duration > 10000 else duration
    clean_t = re.sub(r"\s*[\(\[].*?[\)\]]", "", title).strip()
    candidates = [title] if clean_t == title else [title, clean_t]

    for cand in candidates:
        q = f"{cand} {search_artist(artist)}".strip()
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
                    if not match_artist(artist, s.get("singername")) or not title_ok(title, s.get("songname")) or not match_duration(dur_sec, sdur):
                        continue

                    # Search lyric candidates
                    lurl = f"http://krcs.kugou.com/search?ver=1&man=yes&client=mobi&keyword=&duration={sdur * 1000}&hash={shash}"
                    lreq = urllib.request.Request(lurl, headers={"User-Agent": USER_AGENT})
                    with urllib.request.urlopen(lreq, timeout=3) as lresp:
                        ldata = json.loads(lresp.read().decode("utf-8"))
                        # the candidates are ranked by score, not by how well they fit: take the first one that
                        # is this song (title) and this recording (duration)
                        for cand_lrc in ldata.get("candidates", [])[:6]:
                            if not title_ok(title, cand_lrc.get("song")) or not match_duration(dur_sec, (cand_lrc.get("duration") or 0) / 1000.0):
                                continue
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
            FAILED.add("Kugou")

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

    TRACK_CONTEXT["japanese"] = bool(KANA_RE.search(f"{title} {artist} {album}"))

    cache_file = get_cache_path(title, artist)
    if os.path.exists(cache_file):
        try:
            with open(cache_file, "r", encoding="utf-8") as f:
                cached = json.load(f)
                # an entry written while a better source was down expires, so it gets another chance
                expired = cached.get("retry_after") and time.time() > cached["retry_after"]
                if cached.get("success") and cached.get("lines") and not expired:
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

    # Nothing matched by title. A romanised title on a Japanese track can't be compared with the
    # kanji one a source lists, so try again with the artist and a tight duration as the evidence.
    if (not any(r and r.get("lines") for r in results) and TRACK_CONTEXT["japanese"] and duration
            and not has_japanese(title)):
        LOOSE["on"] = True
        with concurrent.futures.ThreadPoolExecutor(max_workers=len(order)) as pool:
            results = list(pool.map(run, order))
        LOOSE["on"] = False

    # On a Japanese track, a result with no kana / Han at all is romaji or a translation, not the
    # lyrics, so it is ruled out once another source has real Japanese (English-only songs by
    # Japanese artists have no such source and are left alone).
    has_japanese_source = TRACK_CONTEXT["japanese"] and any(r and r.get("lines") and japanese_share(r["lines"]) >= 0.2 for r in results)

    synced_result = None
    plain_result = None
    for res in results:
        if not res or not res.get("lines"):
            continue
        if has_japanese_source and japanese_share(res["lines"]) < 0.05:
            continue
        if res.get("synced"):
            # Keep the higher-priority source unless a later one is clearly more complete.
            # ...and only when it is the same lyrics (two different recordings of a song can differ)
            if synced_result is None or (lyric_coverage(res["lines"]) > lyric_coverage(synced_result["lines"]) * 1.15
                                         and agreement(res["lines"], synced_result["lines"]) >= 0.4):
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
        # a source ranked above the chosen one failed (timeout, 5xx): remember the result for a few
        # minutes only, so a later run can find the better one
        names = {fetch_netease: "NetEase", fetch_kugou: "Kugou", fetch_lrclib: "LRCLIB"}
        ranked = [names[f] for f in order]
        chosen = ranked.index(out["source"]) if out["source"] in ranked else len(ranked)
        if any(n in FAILED for n in ranked[:chosen]):
            out["retry_after"] = time.time() + 600
        save_cache(cache_file, out)
        print(json.dumps(out, ensure_ascii=False))
    else:
        out = {"success": False, "message": "Lyrics not found", "title": title, "artist": artist}
        print(json.dumps(out, ensure_ascii=False))

if __name__ == "__main__":
    main()

