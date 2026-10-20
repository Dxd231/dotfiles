#!/usr/bin/env python3
"""Subtitle lexicon helper for the interactive-subtitle overlay. One long-lived process, JSON lines
on stdin/stdout (same shape as ocr_server.py). Run with ~/.venv/bin/python (needs fugashi + unidic_lite).

Words are cut with fugashi/unidic (merged into "head + trailing auxiliaries"), looked up through the
Yomitan API that LibreWolf exposes on 127.0.0.1:19633 (deinflection, frequency, pitch, glossaries),
and given a status from the known-words store (Anki cards + manual marks).

  -> {"ready": true, "yomitan": bool, "words": N}
  <- {"id": 1, "op": "segment", "text": "...", "lines": ["...", ...]}   "text" or "lines"
  -> {"id": 1, "lines": [[{s, k, term, reading, status, freq, key}, ...], ...]}
        k is word | func | punct; term/reading/freq are empty when Yomitan has no answer
  <- {"id": 2, "op": "define", "term": "分かる", "reading": "わかる", "surface": "分かってた"}
  -> {"id": 2, "term", "reading", "freq": [..], "pitch": [..], "chain": [..], "sections": [{dict, tags, html}]}
  <- {"id": 3, "op": "mark", "term": "..", "reading": "..", "status": "known|learning|ignored|unknown|clear"}
  <- {"id": 4, "op": "sync"}                       pull card status from AnkiConnect
  -> {"id": 4, "known": n, "learning": n}
  <- {"id": 5, "op": "parse_file", "path": "x.ja.srt"}
  -> {"id": 5, "lines": n, "tokens": n, "known": n, "unknown": n, "pct": 87.1, "newWords": n, "plusOne": n}
  <- {"id": 7, "op": "transcript", "path": "x.ja.srt"}
  -> {"id": 7, "lines": [{start, end, text, toks, unk}], "stats": {..as parse_file..}}
  <- {"id": 8, "op": "mine", "term", "reading", "surface", "prefix", "body", "suffix", "force"?, "path"?, "start"?}
  -> {"noteId", "span": [a, b], "line": i, "lines": n} | {"dup": true, "noteId"} | {"error": "yomitan-offline|no-entry|..."}
     with path (the subtitle file) and start (the line's file time) the sentence takes in the neighbouring lines it continues into
  <- {"id": 9, "op": "capture", "noteId", "path", "video", "span": [a, b], "line": i}
  -> {"done": bool, "audio"?, "picture"?}   cuts the span's audio and the line's picture with ffmpeg into the note
  <- {"id": 6, "op": "status"}                     -> {"yomitan": bool, "words": n}
  <- {"quit": true}                                (or close stdin) to exit

Errors come back as {"id": n, "error": "..."}. stdout carries the protocol only.
"""
import base64
import json
import os
import re
import socket
import sqlite3
import subprocess
import sys
import threading
import time
import urllib.request

_out = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr
_out_lock = threading.Lock()

STATE = os.path.join(os.environ.get("XDG_STATE_HOME") or os.path.expanduser("~/.local/state"),
                     "quickshell", "lexicon")
YOMITAN = os.environ.get("QS_YOMITAN_API", "http://127.0.0.1:19633")
ANKI = os.environ.get("QS_ANKI_URL", "http://127.0.0.1:8765")
ANKI_QUERY = os.environ.get("QS_LEXICON_QUERY", 'deck:Japanese note:Kiku')
MATURE_DAYS = 21
# words at or above this frequency rank (1 = most common) count as known without a card
KNOWN_FREQ = int(os.environ.get("QS_KNOWN_FREQ", 4500))

FUNC_POS = {"助詞", "助動詞", "補助記号", "記号", "空白", "接頭辞"}
PUNCT_POS = {"補助記号", "記号", "空白"}
RANK = {"unknown": 0, "ignored": 1, "learning": 2, "known": 3}


def send(obj):
    with _out_lock:
        _out.write(json.dumps(obj, ensure_ascii=False) + "\n")
        _out.flush()


def post(url, body, timeout=8):
    req = urllib.request.Request(url, json.dumps(body).encode(), {"Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        return json.loads(r.read().decode("utf-8"))


# ------------------------------------------------------------------ store

class Store:
    """Manual marks (words.db) + Anki-derived status (anki table). Manual wins."""

    def __init__(self):
        os.makedirs(STATE, exist_ok=True)
        self.db = sqlite3.connect(os.path.join(STATE, "words.db"), check_same_thread=False)
        self.lock = threading.Lock()
        self.db.execute("create table if not exists manual(term text primary key, reading text, status text, updated real)")
        self.db.execute("create table if not exists anki(term text primary key, reading text, status text)")
        self.db.execute("create table if not exists names(surface text primary key, flag int)")
        self.db.execute("create table if not exists cuts(span text primary key, parts text)")
        self.db.commit()
        self.manual, self.anki = {}, {}
        self.names = {t: f for t, f in self.db.execute("select surface, flag from names")}
        self.cuts = {t: p.split("|") for t, p in self.db.execute("select span, parts from cuts")}
        for t, r, s in self.db.execute("select term, reading, status from manual"):
            self.manual[t] = s
        for t, r, s in self.db.execute("select term, reading, status from anki"):
            self.anki[t] = s
        self._index_kana()

    def _index_kana(self):
        # cards written in kana (する, ある) also stand for the kanji headword Yomitan returns (為る, 有る)
        self.kana = {}
        for t, s in self.anki.items():
            if re.fullmatch(r"[\u3040-\u309f\u30a0-\u30ffー]+", t):
                if RANK.get(s, 0) > RANK.get(self.kana.get(t), -1):
                    self.kana[t] = s

    def status(self, term, reading="", rank=0):
        return (self.manual.get(term) or self.anki.get(term) or (self.kana.get(reading) if reading else None)
                or ("known" if 0 < rank <= KNOWN_FREQ else "unknown"))

    def is_auto(self, term, reading, rank):
        """known only because the word is common"""
        return (0 < rank <= KNOWN_FREQ and not self.manual.get(term) and not self.anki.get(term)
                and not (reading and self.kana.get(reading)))

    def mark(self, term, reading, status):
        with self.lock:
            if status == "clear":
                self.manual.pop(term, None)
                self.db.execute("delete from manual where term=?", (term,))
            else:
                self.manual[term] = status
                self.db.execute("insert or replace into manual values(?,?,?,?)", (term, reading, status, time.time()))
            self.db.commit()

    def set_name(self, surface, flag):
        with self.lock:
            if flag == "clear":
                self.names.pop(surface, None)
                self.db.execute("delete from names where surface=?", (surface,))
            else:
                self.names[surface] = int(flag)
                self.db.execute("insert or replace into names values(?,?)", (surface, int(flag)))
            self.db.commit()

    def set_cut(self, span, parts):
        with self.lock:
            if parts is None:
                self.cuts.pop(span, None)
                self.db.execute("delete from cuts where span=?", (span,))
            else:
                self.cuts[span] = parts
                self.db.execute("insert or replace into cuts values(?,?)", (span, "|".join(parts)))
            self.db.commit()

    def replace_anki(self, rows):
        with self.lock:
            self.db.execute("delete from anki")
            self.db.executemany("insert or replace into anki values(?,?,?)", rows)
            self.db.commit()
            self.anki = {t: s for t, _, s in rows}
            self._index_kana()

    def counts(self):
        return len(set(self.manual) | set(self.anki))


# ------------------------------------------------------------------ segmentation

_tagger = None


def tagger():
    global _tagger
    if _tagger is None:
        import fugashi
        _tagger = fugashi.Tagger()
    return _tagger


def kata_to_hira(s):
    return "".join(chr(ord(c) - 0x60) if "ァ" <= c <= "ヶ" else c for c in s or "")


def _segment(text):
    """-> [{s, k, lemma, kana}] words; trailing auxiliaries (た, て, ない, させ, られ ...) join the verb."""
    words = []
    for t in tagger()(text):
        f = t.feature
        pos1 = f.pos1 or ""
        pos2 = f.pos2 or ""
        verbish = words and words[-1]["pos"] in ("動詞", "形容詞", "助動詞", "形状詞") and words[-1]["k"] == "word"
        glue = verbish and (pos1 == "助動詞" or (pos1 == "助詞" and pos2 == "接続助詞")
                            or (pos1 == "動詞" and pos2 == "非自立可能") or pos1 == "接尾辞")
        # a verb's own aux chain only: stop at sentence-ending / copula-like だ,です after a noun
        if glue and words[-1]["pos"] == "助動詞" and pos1 == "助詞":
            glue = words[-1]["tail"] in ("て", "で")
        if glue:
            w = words[-1]
            w["s"] += t.surface
            w["tail"] = t.surface
            w["morph"].append((t.surface, getattr(f, "kana", "") or ""))
            continue
        kind = "punct" if pos1 in PUNCT_POS else ("func" if pos1 in FUNC_POS or pos2 == "準体助詞" else "word")
        lemma = (f.lemma or t.surface).split("-")[0]
        words.append({"s": t.surface, "k": kind, "lemma": lemma, "kana": getattr(f, "kana", "") or "",
                      "pos": pos1, "tail": t.surface, "morph": [(t.surface, getattr(f, "kana", "") or "")],
                      "name": pos2 == "固有名詞" and (f.pos3 or "") == "人名"})
    return words


# 加藤(かとう): a kanji run with its kana reading in brackets right after it. The kanji is a name (or a rare
# spelling), the bracketed reading is not a word.
INLINE_READING = re.compile(r"([\u3400-\u9fff々〆ヶ]+)([(（])([\u3041-\u3096\u30a1-\u30faー]+)([)）])")


KANJI = re.compile(r"[\u3400-\u9fff々〆ヶ]+")


def ruby(morph):
    """[(surface, kana)] -> [[text, reading]]: the reading sits over the kanji only ("" over okurigana)."""
    out = []
    for surf, kana in morph:
        reading = kata_to_hira(kana)
        parts = re.split(r"([\u3400-\u9fff々〆ヶ]+)", surf)
        parts = [x for x in parts if x]
        if not KANJI.search(surf) or not reading:
            out.append([surf, ""])
            continue
        pat = "".join("(.+?)" if KANJI.fullmatch(x) else re.escape(kata_to_hira(x)) for x in parts)
        m = re.fullmatch(pat, reading)
        if not m:
            out.append([surf, reading])
            continue
        g = iter(m.groups())
        for x in parts:
            out.append([x, next(g)] if KANJI.fullmatch(x) else [x, ""])
    merged = []
    for t, r in out:
        if merged and r == "" and merged[-1][1] == "":
            merged[-1][0] += t
        else:
            merged.append([t, r])
    return merged


def _punct(s):
    return {"s": s, "k": "punct", "lemma": s, "kana": "", "pos": "補助記号", "tail": s, "name": False}


def _chunk(text, label=False):
    words, pos = [], 0
    for m in INLINE_READING.finditer(text):
        if m.start() > pos:
            words.extend(_segment(text[pos:m.start()]))
        words.append({"s": m.group(1), "k": "word", "lemma": m.group(1), "kana": m.group(3), "pos": "名詞",
                      "tail": m.group(1), "morph": [(m.group(1), m.group(3))], "name": True})
        words.append(_punct(m.group(2) + m.group(3) + m.group(4)))
        pos = m.end()
    if pos < len(text):
        words.extend(_segment(text[pos:]))
    if label:
        for w in words:
            if w["k"] == "word":
                w["name"] = True
    return words


def segment_text(text):
    """_segment plus the subtitle conventions: a leading （speaker） label is all names, and kanji(reading) is a name."""
    if text[:1] in ("（", "("):
        depth = 0
        for j, ch in enumerate(text):
            depth += ch in "（(" 
            depth -= ch in "）)"
            if depth == 0:
                break
        if depth == 0 and 2 < j <= 24 and j + 1 < len(text):
            return [_punct(text[0])] + _chunk(text[1:j], True) + [_punct(text[j])] + _chunk(text[j + 1:])
    return _chunk(text)


def default_cut(span):
    return [w["s"] for w in segment_text(span)]


def apply_cuts(words, cuts):
    """Re-cut runs of whole words whose joined text has a saved rule (longest run first)."""
    if not cuts:
        return words
    out, i = [], 0
    while i < len(words):
        for n in (4, 3, 2, 1):
            run = words[i:i + n]
            if len(run) < n or any(w["k"] == "punct" for w in run):
                continue
            parts = cuts.get("".join(w["s"] for w in run))
            if parts and parts != [w["s"] for w in run]:
                for part in parts:
                    out.extend(segment_text(part) if part else [])
                i += n
                break
        else:
            out.append(words[i])
            i += 1
    return out


# ------------------------------------------------------------------ yomitan

class Yomitan:
    def __init__(self):
        self.path = os.path.join(STATE, "lookups2.json")
        self.cache = {}
        self.up = False
        self.dirty = 0
        try:
            self.cache = json.load(open(self.path))
        except Exception:
            pass

    def alive(self):
        try:
            post(YOMITAN + "/serverVersion", {}, 1.5)
            self.up = True
        except Exception:
            self.up = False
        return self.up

    def save(self):
        if not self.dirty:
            return
        try:
            tmp = self.path + ".tmp"
            json.dump(self.cache, open(tmp, "w"), ensure_ascii=False)
            os.replace(tmp, self.path)
            self.dirty = 0
        except Exception as e:
            print("save failed:", e)

    @staticmethod
    def _summary(entry):
        hw = entry["headwords"][0]
        ranks = [f["frequency"] for f in entry.get("frequencies", [])
                 if f.get("frequencyMode") == "rank-based" and isinstance(f.get("frequency"), (int, float))]
        pitch = []
        for p in entry.get("pronunciations", []):
            for x in p.get("pronunciations", []):
                if x.get("type") == "pitch-accent" and isinstance(x.get("positions"), int):
                    pitch.append(x["positions"])
        chain = [r["name"] for c in entry.get("inflectionRuleChainCandidates", [])[:1] for r in c.get("inflectionRules", [])]
        # JPDB also ranks the kana spelling of a kanji word (displayValue ends in ㋕); that says nothing about
        # how common the kanji word is, so the auto-known rule ignores it
        kana_term = re.fullmatch(r"[\u3040-\u309f\u30a0-\u30ffー]+", hw["term"]) is not None
        own = [f["frequency"] for f in entry.get("frequencies", [])
               if f.get("frequencyMode") == "rank-based" and isinstance(f.get("frequency"), (int, float))
               and (kana_term or "㋕" not in str(f.get("displayValue", "")))]
        return {"term": hw["term"], "reading": hw["reading"], "freq": min(ranks) if ranks else 0,
                "rank": min(own) if own else 0, "pitch": pitch[:1], "chain": chain}

    def _pick(self, surface, entries):
        for e in entries:
            if not e.get("headwords"):
                continue
            for s in e["headwords"][0].get("sources", []):
                if s.get("isPrimary") and s.get("originalText") == surface:
                    return e
        return None

    def lookup_many(self, surfaces):
        """{surface: summary or None}. Cached; misses go to /termEntries in batches."""
        need = [s for s in dict.fromkeys(surfaces) if s not in self.cache]
        if need and self.alive():
            for i in range(0, len(need), 40):
                batch = need[i:i + 40]
                try:
                    res = post(YOMITAN + "/termEntries", {"term": batch}, 30)
                except Exception as e:
                    print("termEntries failed:", e)
                    self.up = False
                    break
                for r in res:
                    s = batch[r["index"]]
                    e = self._pick(s, r.get("dictionaryEntries", []))
                    self.cache[s] = self._summary(e) if e else None
                    self.dirty += 1
            self.save()
        return {s: self.cache.get(s) for s in surfaces}

    def entry(self, surface, term, reading):
        res = post(YOMITAN + "/termEntries", {"term": surface}, 15)
        ents = res.get("dictionaryEntries", [])
        for e in ents:
            h = e["headwords"][0]
            if h["term"] == term and (not reading or h["reading"] == reading):
                return e
        return ents[0] if ents else None


# ------------------------------------------------------------------ glossary -> html

def sc_html(n):
    if n is None:
        return ""
    if isinstance(n, str):
        return n.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
    if isinstance(n, list):
        return "".join(sc_html(x) for x in n)
    if isinstance(n, dict):
        t = n.get("type")
        if t == "structured-content":
            return sc_html(n.get("content"))
        if t == "image":
            return ""
        tag = n.get("tag")
        inner = sc_html(n.get("content"))
        if tag == "rt":
            return '<span style="font-size:small">(%s)</span>' % inner
        if tag == "rp":
            return ""
        if tag in ("ul", "ol", "li", "b", "i", "br", "strong", "em", "sup", "sub"):
            return "<%s>%s</%s>" % (tag, inner, tag) if tag != "br" else "<br>"
        if tag == "ruby":
            return inner
        if tag in ("div", "p", "tr", "table", "details", "summary"):
            return inner + "<br>"
        if tag in ("td", "th"):
            return inner + " "
        return inner
    return ""


def glossary(entry):
    out = []
    for d in entry.get("definitions", []):
        parts = []
        for g in d.get("entries", []):
            if isinstance(g, dict) and g.get("type") == "image":
                continue
            parts.append(sc_html(g if not isinstance(g, dict) or g.get("type") else g))
        html = "<br>".join(p for p in parts if p.strip())
        tags = [t["name"] for t in d.get("tags", []) if t.get("category") in ("partOfSpeech", "misc", "field", "dialect")]
        if html:
            out.append({"dict": d.get("dictionary", ""), "tags": tags, "html": html})
    return out


# ------------------------------------------------------------------ anki sync

def anki(action, **params):
    r = post(ANKI, {"action": action, "version": 6, "params": params}, 20)
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r["result"]


def plain(s):
    return re.sub(r"<[^>]+>|\[sound:[^\]]*\]", "", s or "").strip()


# (query, word field, reading field, kind). "core" decks are a suspended starter list the user
# already studied: every word counts as known. "mined" cards are graded by their interval.
ANKI_SOURCES = [
    (ANKI_QUERY, "Expression", "ExpressionReading", "mined"),
    (os.environ.get("QS_LEXICON_CORE", 'deck:"Kaishi 1.5k"'), "Word", "Word Reading", "core"),
]


def sync_anki(store):
    best = {}
    for query, wf, rf, kind in ANKI_SOURCES:
        ids = anki("findCards", query=query)
        for i in range(0, len(ids), 500):
            for c in anki("cardsInfo", cards=ids[i:i + 500]):
                f = c.get("fields", {})
                term = plain(f.get(wf, {}).get("value"))
                if not term or len(term) > 20:       # Kaishi's first note is a welcome text
                    continue
                reading = plain(f.get(rf, {}).get("value"))
                if kind == "core":
                    st = "known"
                elif c.get("queue") == -1:           # suspended mined card: no information
                    continue
                else:
                    st = "known" if c.get("type") == 2 and c.get("interval", 0) >= MATURE_DAYS else "learning"
                if term not in best or RANK[st] > RANK[best[term][2]]:
                    best[term] = (term, reading, st)
    store.replace_anki(list(best.values()))
    return {"known": sum(1 for v in best.values() if v[2] == "known"),
            "learning": sum(1 for v in best.values() if v[2] == "learning")}


# ------------------------------------------------------------------ core

store = Store()
yom = Yomitan()


def _status(term, reading, rank, matched):
    st = store.status(term, reading, rank)
    return "none" if st == "unknown" and not matched else st


def annotate(texts):
    """texts: [str] -> [[token]] with lookups resolved in one batch."""
    segs = [apply_cuts(segment_text(t), store.cuts) for t in texts]
    isname = lambda w: bool(store.names.get(w["s"], w.get("name")))
    surfaces = [w["s"] for ws in segs for w in ws if w["k"] == "word" and not isname(w)]
    found = yom.lookup_many(surfaces)
    # words Yomitan could not match as a whole: retry with the unidic dictionary form
    miss = [w["lemma"] for ws in segs for w in ws if w["k"] == "word" and not isname(w) and not found.get(w["s"]) and w["lemma"] != w["s"]]
    found2 = yom.lookup_many(miss) if miss else {}
    out = []
    for ws in segs:
        toks = []
        for w in ws:
            tok = {"s": w["s"], "k": w["k"]}
            if w["k"] == "word" and (store.names.get(w["s"], w.get("name"))):
                reading = kata_to_hira(w["kana"])
                tok.update(term=w["s"], reading=reading, freq=0, rank=0, status="name", known=False, auto=False,
                           name=True, key=w["s"] + "|" + reading)
                if KANJI.search(w["s"]):
                    tok["ruby"] = ruby(w["morph"])
            elif w["k"] == "word":
                info = found.get(w["s"]) or found2.get(w["lemma"])
                term = info["term"] if info else w["lemma"]
                reading = info["reading"] if info else kata_to_hira(w["kana"])
                rank = info["rank"] if info else 0
                tok.update(term=term, reading=reading, freq=info["freq"] if info else 0, rank=rank,
                           status=_status(term, reading, rank, bool(info)), known=bool(info),
                           auto=store.is_auto(term, reading, rank))
                tok["key"] = term + "|" + reading
                if KANJI.search(w["s"]):
                    tok["ruby"] = ruby(w["morph"])
            toks.append(tok)
        out.append(toks)
    return out


def parse_srt(path):
    raw = open(path, encoding="utf-8-sig", errors="replace").read().replace("\r", "")
    lines = []
    for block in re.split(r"\n\s*\n", raw):
        m = re.search(r"(\d+):(\d+):(\d+)[,.](\d+)\s*-->\s*(\d+):(\d+):(\d+)[,.](\d+)", block)
        if not m:
            continue
        g = [int(x) for x in m.groups()]
        text = block[m.end():].strip()
        text = re.sub(r"<[^>]+>|\{[^}]*\}", "", text).replace("\n", " ").strip()
        if text:
            lines.append((g[0] * 3600 + g[1] * 60 + g[2] + g[3] / 1000, g[4] * 3600 + g[5] * 60 + g[6] + g[7] / 1000, text))
    return lines


_parsed = {}  # path -> (mtime, lines, toks): annotating a whole file is slow, statuses are re-read on every call


def _load(path):
    mt = os.path.getmtime(path)
    hit = _parsed.get(path)
    if not hit or hit[0] != mt:
        lines = parse_srt(path)
        hit = (mt, lines, annotate([l[2] for l in lines]))
        _parsed[path] = hit
    return hit[1], hit[2]


def _stats(lines, toks):
    n_known = n_unknown = n_tokens = plus_one = 0
    new = set()
    for ts in toks:
        unk_here = set()
        for t in ts:
            if t["k"] != "word":
                continue
            if t.get("name"):
                continue
            t["status"] = _status(t["term"], t["reading"], t.get("rank", 0), t.get("known", False))
            if t["status"] == "none":
                continue
            n_tokens += 1
            t["auto"] = store.is_auto(t["term"], t["reading"], t.get("rank", 0))
            if t["status"] in ("known", "ignored"):
                n_known += 1
            elif t["status"] == "unknown":
                n_unknown += 1
                unk_here.add(t["key"])
        new |= unk_here
        if len(unk_here) == 1:
            plus_one += 1
    return {"lines": len(lines), "tokens": n_tokens, "known": n_known, "unknown": n_unknown,
            "pct": round(100.0 * n_known / n_tokens, 1) if n_tokens else 0.0,
            "newWords": len(new), "plusOne": plus_one}


def parse_file(path):
    lines, toks = _load(path)
    return _stats(lines, toks)


def transcript(path):
    """Every line of the file with its words (statuses fresh), and the file's stats."""
    lines, toks = _load(path)
    stats = _stats(lines, toks)
    out = []
    for (a, b, text), ts in zip(lines, toks):
        unk = {t["key"] for t in ts if t["k"] == "word" and t["status"] == "unknown"}
        out.append({"start": a, "end": b, "text": text, "toks": ts, "unk": len(unk)})
    return {"lines": out, "stats": stats}


# ------------------------------------------------------------------ mining

MINE_FORMAT = os.environ.get("QS_MINE_FORMAT", "")
MINE_TAGS = [t for t in os.environ.get("QS_MINE_TAGS", "mining").split(",") if t]
MEDIA_TMP = os.path.join(STATE, "media")
SUBS2SRS_CONF = os.path.expanduser("~/.config/mpv/script-opts/subs2srs.conf")


def anki(action, **params):
    r = post(ANKI, {"action": action, "version": 6, "params": params}, 15)
    if r.get("error"):
        raise RuntimeError(r["error"])
    return r.get("result")


def mpvacious_opt(name, default):
    """mpvacious's own setting, so the wait looks at the field its script fills"""
    try:
        for line in open(SUBS2SRS_CONF, encoding="utf-8"):
            k, _, v = line.partition("=")
            if k.strip() == name and v.strip():
                return v.strip()
    except OSError:
        pass
    return default


def _plain_pitch(html):
    return ",".join(re.findall(r"\d+", re.sub(r"<[^>]+>", " ", html)))


def mine(req):
    """Add the word the way Yomitan's own card format would: the format's field templates are filled from
    /ankiFields, with the cloze sentence supplied by the caller. mpvacious then adds the line's audio and picture."""
    term, reading, surface = req["term"], req.get("reading", ""), req.get("surface") or req["term"]
    if not yom.alive():
        return {"error": "yomitan-offline"}
    try:
        fmts = post(YOMITAN + "/ankiCardFormats", {}, 5)
    except Exception:
        return {"error": "yomitan-offline"}
    fmt = next((f for f in fmts if f["name"] == MINE_FORMAT), fmts[0] if fmts else None)
    if not fmt:
        return {"error": "no-format"}
    templates = {k: v["value"] for k, v in fmt["fields"].items()}
    markers = sorted({m for v in templates.values() for m in re.findall(r"\{([^{}]+)\}", v)})
    body = {"type": "term", "markers": markers, "maxEntries": 1, "includeMedia": True}
    res = post(YOMITAN + "/ankiFields", dict(body, text=surface), 30)
    if not res.get("fields") or res["fields"][0].get("expression") != term:
        res = post(YOMITAN + "/ankiFields", dict(body, text=term), 30)
    if not res.get("fields"):
        return {"error": "no-entry"}
    vals = dict(res["fields"][0])
    nospace = lambda t: re.sub(r"\s+", "", t)
    prefix, suffix = nospace(req.get("prefix", "")), nospace(req.get("suffix", ""))
    span, line = [0, 0], -1
    if req.get("path") and req.get("start") is not None and req["start"] >= 0:
        try:
            lines, _toks = _load(req["path"])
            line = _line_at(lines, req["start"])
            if line >= 0:
                a, b = sentence_span(lines, line)
                span = [a, b]
                # the caller sent one row of the cue (the live line is drawn row by row): add the rest of the cue
                cue = nospace(lines[line][2])
                row = prefix + nospace(req.get("body", surface)) + suffix
                at = cue.find(row)
                before, after = (cue[:at], cue[at + len(row):]) if at >= 0 else ("", "")
                prefix = "".join(nospace(l[2]) for l in lines[a:line]) + before + prefix
                suffix = suffix + after + "".join(nospace(l[2]) for l in lines[line + 1:b + 1])
        except OSError:
            pass
    prefix = _strip_label(prefix)
    vals["cloze-prefix"] = prefix
    vals["cloze-body"] = req.get("body", surface)
    vals["cloze-suffix"] = suffix
    vals["popup-selection-text"] = ""
    vals["document-title"] = ""
    if "pitch-accent-positions" in vals:
        vals["pitch-accent-positions"] = _plain_pitch(vals["pitch-accent-positions"])
    fields = {k: re.sub(r"\{([^{}]+)\}", lambda m: str(vals.get(m.group(1), "")), v) for k, v in templates.items()}

    # media Yomitan attached: the audio marker holds the [sound:name] tags in the order of audioMedia
    names = re.findall(r"\[sound:([^\]]+)\]", str(vals.get("audio", "")))
    for name, m in zip(names, res.get("audioMedia", [])):
        anki("storeMediaFile", filename=name, data=m["content"])
    for m in res.get("dictionaryMedia", []):
        if m.get("ankiFilename") and m.get("content"):
            anki("storeMediaFile", filename=m["ankiFilename"], data=m["content"])

    first = next(iter(fields))
    note = {"deckName": fmt["deck"], "modelName": fmt["model"], "fields": fields, "tags": MINE_TAGS,
            "options": {"allowDuplicate": bool(req.get("force"))}}
    if not req.get("force"):
        ok = anki("canAddNotesWithErrorDetail", notes=[note])[0]
        if not ok.get("canAdd"):
            ids = anki("findNotes", query='"note:%s" "%s:%s"' % (fmt["model"], first, fields[first].replace('"', '\\"')))
            return {"dup": True, "noteId": ids[-1] if ids else 0}
    note_id = anki("addNote", note=note)
    if store.manual.get(term) == "unknown":
        store.mark(term, reading, "clear")
    return {"noteId": note_id, "span": span, "line": line, "lines": span[1] - span[0] + 1 if line >= 0 else 1}


# A subtitle cue is often half a sentence. These decide whether the neighbours belong to the target's sentence.
SPAN_GAP = 1.2       # seconds of silence that still counts as one utterance
SPAN_MAX = 12.0      # longest span taken
END_MARKS = "。！？!?」』"
OPEN_MARKS = "、…‥ー,"
WEAK_PARTICLES = {"けど", "けれど", "けれども", "が", "から", "し", "のに", "ので", "って", "と"}
FINAL_PARTICLES = {"か", "ね", "よ", "な", "わ", "ぞ", "ぜ", "さ", "の", "かな", "かしら", "よね"}
LABEL_START = ("（", "(")


def _unfinished(text):
    """How sure a line stops mid-sentence: 2 a comma, a trailing て/を/に, a stem form; 1 a trailing けど/が/から/…
    (often a speaker trailing off: those join only when the next line starts like a continuation); 0 it is finished."""
    t = text.rstrip()
    if not t:
        return 0
    if t[-1] in END_MARKS:
        return 0
    if t[-1] in "…‥" or t.endswith("..."):
        return 1
    if t[-1] in OPEN_MARKS:
        return 2
    last = None
    for tk in tagger()(t):
        if (tk.feature.pos1 or "") not in PUNCT_POS:
            last = tk
    if last is None:
        return 0
    f = last.feature
    pos1, pos2 = f.pos1 or "", f.pos2 or ""
    if pos1 == "助詞":
        if pos2 == "終助詞" or last.surface in FINAL_PARTICLES:
            return 0
        return 1 if last.surface in WEAK_PARTICLES else 2
    if pos1 in ("動詞", "形容詞", "助動詞", "形状詞"):
        form = getattr(f, "cForm", "") or ""
        return 2 if form.startswith(("連用", "未然", "仮定")) else 0
    return 0


def _continues(text):
    """True when a line starts like the tail of a sentence (、 or a particle / auxiliary)."""
    t = text.lstrip()
    if t[:1] == "、":
        return True
    for tk in tagger()(t):
        pos1 = tk.feature.pos1 or ""
        if pos1 in PUNCT_POS:
            continue
        return pos1 in ("助詞", "助動詞")
    return False


def sentence_span(lines, i):
    """-> (first, last): the target line index with at most one neighbour either side that is part of the same sentence."""
    def joins(a, b):
        if b < 0 or b >= len(lines) or a < 0 or a >= len(lines):
            return False
        gap = lines[b][0] - lines[a][1]
        if gap > SPAN_GAP or lines[b][2][:1] in LABEL_START or "♪" in lines[a][2] + lines[b][2]:
            return False
        if _continues(lines[b][2]):
            return True
        return _unfinished(lines[a][2]) == 2

    first, last = i, i
    if joins(i - 1, i):
        first = i - 1
    if joins(i, i + 1):
        last = i + 1
    if lines[last][1] - lines[first][0] > SPAN_MAX:
        last = i
    if lines[last][1] - lines[first][0] > SPAN_MAX:
        first = i
    return first, last


def _strip_label(t):
    """Drop a leading （speaker） label: it is not part of the sentence."""
    if t[:1] in LABEL_START:
        depth = 0
        for j, ch in enumerate(t):
            depth += ch in "（("
            depth -= ch in "）)"
            if depth == 0:
                break
        if depth == 0 and 2 < j <= 24 and j + 1 < len(t):
            return t[j + 1:]
    return t


def _line_at(lines, start):
    best, gap = -1, 0.3
    for k, (a, _b, _t) in enumerate(lines):
        if abs(a - start) < gap:
            best, gap = k, abs(a - start)
    return best


def _mpv_get(*props):
    """Properties of the running mpv through its IPC socket (the shell's own, QS_MPV_SOCKET); {} when it is not there."""
    out = {}
    try:
        s = socket.socket(socket.AF_UNIX)
        s.settimeout(2)
        s.connect(os.environ.get("QS_MPV_SOCKET") or "/tmp/mpv-socket")
        f = s.makefile("rw", encoding="utf-8")
        for k, p in enumerate(props, 1):
            f.write(json.dumps({"command": ["get_property", p], "request_id": k}) + "\n")
            f.flush()
            while True:
                line = f.readline()
                if not line:
                    return out
                r = json.loads(line)
                if r.get("request_id") == k:
                    out[p] = r.get("data")
                    break
    except Exception:
        pass
    return out


def _tag_name(filename):
    """mpvacious's %n and %d for a file name: show name with the episode number cut out, and the number."""
    name = re.sub(r"\.\w+$", "", filename)
    name = re.sub(r"2160p|1080p|720p|576p|480p", "", name)
    name = re.sub(r"\[[^\]]*\]", "", name) if mpvacious_opt("tag_nuke_brackets", "yes") == "yes" else name
    ep = ""
    m = re.search(r"(?:[\s_]|^)[sS]?\d*[eE][pP]?(\d{1,3})(?!\d)", name) or re.search(r"[\s_-](\d{1,3})(?:[\s_]|$)", name)
    if m:
        ep = m.group(1)
        name = name[:m.start(1)].rstrip("EePp") if mpvacious_opt("tag_del_episode_num", "yes") == "yes" else name
        name = re.sub(r"[sS]\d*$", "", name) if mpvacious_opt("tag_del_after_episode_num", "yes") == "yes" else name
    name = re.sub(r"_-_", "_", name.strip().replace(" ", "_")).strip("-_ ")
    return name, ep


def _hms(t):
    h, m, sec = int(t // 3600), int(t // 60) % 60, int(t % 60)
    return ("%dh" % h if h else "") + "%02dm%02ds%03dms" % (m, sec, int(t * 1000) % 1000)


def _ffmpeg(args):
    r = subprocess.run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-y"] + args, capture_output=True, text=True, timeout=120)
    if r.returncode != 0:
        raise RuntimeError(r.stderr.strip().splitlines()[-1] if r.stderr.strip() else "ffmpeg failed")


def capture(req):
    """Cut the sentence's audio and the target line's picture straight from the video and put them in the note.
    Settings come from mpvacious's subs2srs.conf so the files look like the ones mpvacious makes."""
    lines, _toks = _load(req["path"])
    a, b = req["span"]
    i = req.get("line", a)
    video = req.get("video") or ""
    mp = _mpv_get("path", "working-directory", "sub-delay", "track-list")
    if not os.path.isabs(video):
        video = os.path.join(mp.get("working-directory") or "", video)
    if not os.path.exists(video):
        return {"error": "no-video"}
    delay = float(mp.get("sub-delay") or 0) if os.path.basename(str(mp.get("path") or "")) == os.path.basename(video) else 0.0
    amap = "0:a:0"
    for t in mp.get("track-list") or []:
        if t.get("type") == "audio" and t.get("selected") and t.get("ff-index") is not None:
            amap = "0:%d" % t["ff-index"]

    opt = mpvacious_opt
    pad = float(opt("audio_padding", "0") or 0)
    t0 = max(0.0, lines[a][0] + delay - pad)
    t1 = lines[b][1] + delay + pad
    show = re.sub(r"[\W_]+", "", re.sub(r"\.\w+$", "", os.path.basename(video)))[:40].lower() or "clip"
    stamp = "_%s_%s" % (_hms(t0), _hms(t1))
    out = {"done": False}
    fields = {}

    afmt = opt("audio_format", "mp3")
    aname = show + stamp + (".ogg" if afmt == "opus" and opt("opus_container", "ogg") == "ogg" else ".opus" if afmt == "opus" else ".mp3")
    apath = os.path.join(MEDIA_TMP, aname)
    os.makedirs(MEDIA_TMP, exist_ok=True)
    codec = ["-c:a", "libopus"] if afmt == "opus" else ["-c:a", "libmp3lame"]
    _ffmpeg(["-ss", "%.3f" % t0, "-t", "%.3f" % (t1 - t0), "-i", video, "-map", amap, "-vn"] + codec
            + ["-b:a", opt("audio_bitrate", "128k"), apath])
    anki("storeMediaFile", filename=aname, data=base64.b64encode(open(apath, "rb").read()).decode())
    os.remove(apath)
    fields[opt("audio_field", "SentenceAudio")] = opt("audio_template", "[sound:%s]").replace("%s", aname)
    out["audio"] = aname

    ts, te = lines[i][0] + delay, lines[i][1] + delay
    try:
        if opt("animated_snapshot_enabled", "no") == "yes":
            dur = min(6.0, max(0.5, te - ts))
            pname = show + "_" + _hms(ts) + "_" + _hms(ts + dur) + ".avif"
            ppath = os.path.join(MEDIA_TMP, pname)
            _ffmpeg(["-ss", "%.3f" % ts, "-t", "%.3f" % dur, "-i", video, "-an", "-sn",
                     "-vf", "fps=%s,scale=-2:%s" % (opt("animated_snapshot_fps", "24"), opt("animated_snapshot_height", "200")),
                     "-c:v", "libsvtav1", "-crf", str(100 - int(opt("animated_snapshot_quality", "80"))), "-preset", "8", ppath])
        else:
            pname = show + "_" + _hms((ts + te) / 2) + ".avif"
            ppath = os.path.join(MEDIA_TMP, pname)
            _ffmpeg(["-ss", "%.3f" % ((ts + te) / 2), "-i", video, "-frames:v", "1",
                     "-vf", "scale=-2:%s" % opt("snapshot_height", "350"), "-c:v", "libaom-av1", "-still-picture", "1",
                     "-crf", opt("snapshot_quality", "15"), "-cpu-used", "8", ppath])
        anki("storeMediaFile", filename=pname, data=base64.b64encode(open(ppath, "rb").read()).decode())
        os.remove(ppath)
        fields[opt("image_field", "Picture")] = opt("image_template", '<img alt="snapshot" src="%s">').replace("%s", pname)
        out["picture"] = pname
    except Exception as e:
        out["pictureError"] = str(e)

    if opt("miscinfo_enable", "no") == "yes":
        name, ep = _tag_name(os.path.basename(video))
        fmt = opt("miscinfo_format", "%n EP%d (%t)")
        fields[opt("miscinfo_field", "MiscInfo")] = fmt.replace("%n", name).replace("%d", ep).replace("%t", _hms(ts))
    anki("updateNoteFields", note={"id": req["noteId"], "fields": fields})
    out["done"] = "audio" in out
    return out


def handle(req):
    op = req.get("op")
    if op == "segment":
        texts = req.get("lines") or [req.get("text", "")]
        return {"lines": annotate(texts)}
    if op == "define":
        surface, term, reading = req.get("surface") or req["term"], req["term"], req.get("reading", "")
        if not yom.alive():
            return {"error": "yomitan-offline"}
        e = yom.entry(surface, term, reading)
        if not e:
            return {"error": "no-entry"}
        s = Yomitan._summary(e)
        s["freqs"] = [{"dict": f["dictionary"], "value": f.get("displayValue") or str(f.get("frequency", ""))}
                      for f in e.get("frequencies", []) if f.get("headwordIndex", 0) == 0]
        s["sections"] = glossary(e)
        s["status"] = store.status(s["term"], s["reading"], s["rank"])
        s["auto"] = store.is_auto(s["term"], s["reading"], s["rank"])
        return s
    if op == "mark":
        store.mark(req["term"], req.get("reading", ""), req["status"])
        return {"ok": True, "status": store.status(req["term"], req.get("reading", ""), req.get("rank", 0))}
    if op == "name":
        store.set_name(req["surface"], req["flag"])
        _parsed.clear()
        return {"ok": True}
    if op == "cut":
        span, parts = req["span"], [p for p in req["parts"] if p]
        if "".join(parts) != span:
            return {"error": "parts do not join to span"}
        store.set_cut(span, None if parts == default_cut(span) else parts)
        _parsed.clear()
        return {"ok": True, "toks": annotate([span])[0]}
    if op == "sync":
        return sync_anki(store)
    if op == "parse_file":
        return parse_file(req["path"])
    if op == "transcript":
        return transcript(req["path"])
    if op == "mine":
        return mine(req)
    if op == "browse":
        anki("guiBrowse", query="nid:%d" % req["noteId"])
        return {"ok": True}
    if op == "capture":
        return capture(req)
    if op == "status":
        return {"yomitan": yom.alive(), "words": store.counts()}
    return {"error": "unknown op %r" % op}


def run(req):
    try:
        res = handle(req)
    except Exception as e:
        res = {"error": "%s: %s" % (type(e).__name__, e)}
    res["id"] = req.get("id")
    send(res)


def main():
    try:
        tagger()
    except Exception as e:
        send({"ready": False, "error": "fugashi: %s" % e})
        return 1
    send({"ready": True, "yomitan": yom.alive(), "words": store.counts()})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        if req.get("quit"):
            break
        # slow ops run on a thread so a long parse_file never blocks hover lookups
        if req.get("op") in ("parse_file", "transcript", "sync", "mine", "capture"):
            threading.Thread(target=run, args=(req,), daemon=True).start()
        else:
            run(req)
    yom.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
