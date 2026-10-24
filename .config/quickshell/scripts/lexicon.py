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
  -> {"id": 5, "lines": n, "tokens": n, "known": n, "unknown": n, "pct": 87.1, "learning": n, "learnPct": 4.2, "newWords": n, "plusOne": n}
  <- {"id": 12, "op": "learning", "path": "x.ja.srt"}   (path optional)
  -> {"words": [{term, reading, ivl, lapses, due, leech, note, source: anki|manual, here}], "marks": [{term, reading, status, updated, ivl, lapses, due, leech, note, anki, here}]}
        words = everything being learned, here = lines it is in; marks = the user's own known/unknown/ignored marks
  <- {"id": 7, "op": "transcript", "path": "x.ja.srt"}
  -> {"id": 7, "lines": [{start, end, text, toks, unk, lrn, flag}], "stats": {..as parse_file..}}
        lrn = learning words in the line, flag = one of them is due or a leech; learning word tokens carry due, leech, ivl, lapses
  <- {"id": 8, "op": "mine", "term", "reading", "surface", "prefix", "body", "suffix", "force"?, "replace"? (note id to overwrite), "path"?, "start"?}
  -> {"noteId", "span": [a, b], "line": i, "lines": n} | {"dup": true, "noteId"} | {"error": "yomitan-offline|no-entry|..."}
     with path (the subtitle file) and start (the line's file time) the sentence takes in the neighbouring lines it continues into
  <- {"id": 9, "op": "capture", "noteId", "path", "video", "span": [a, b], "line": i}
  -> {"done": bool, "audio"?, "picture"?}   cuts the span's audio and the line's picture with ffmpeg into the note
  <- {"id": 5, "op": "pick", "surface", "base", "term", "reading"}      -> {"ok": true}   which dictionary entry a word means (empty term clears)
  <- {"id": 8, "op": "recheck", "term", "reading", "rank"}
  -> {"status", "changed": bool, "noteId"?}   asks Anki again about one word (a deleted or re-graded card), no full sync
  <- {"id": 10, "op": "span", "path", "start"}
  -> {"line": i, "auto": [a, b], "lines": [{i, text, start, end}]}   the cue and its neighbours; line -1 when not found
  <- {"id": 11, "op": "respan", "noteId", "term", ..., "span": [a, b]}   -> {"span", "line", "lines"}   rewrites the sentence of a mined note
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
import urllib.parse
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
# a word with this many lapses is a leech
LEECH_LAPSES = int(os.environ.get("QS_LEECH_LAPSES", 4))
# words at or above this frequency rank (1 = most common) count as known without a card
KNOWN_FREQ = int(os.environ.get("QS_KNOWN_FREQ", 4500))

FUNC_POS = {"助詞", "助動詞", "補助記号", "記号", "空白", "接頭辞"}
PUNCT_POS = {"補助記号", "記号", "空白"}
# vocal reactions (うう, フフッ, ハハハ, うわぁ): interjections made only of vowel / laugh / gasp kana are not vocabulary
SOUND_KANA = re.compile(r"[あ-おぁ-ぉア-オァ-ォうゔヴッっーんンはひふへほハヒフヘホわワゃャキ]+")
SOUND_KEEP = {"はい", "いえ", "ええ", "うん", "ほう"}
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
        have = {r[1] for r in self.db.execute("pragma table_info(anki)")}
        for col in ("ivl", "lapses", "due", "note"):
            if col not in have:
                self.db.execute("alter table anki add column %s int default 0" % col)
        self.db.execute("create table if not exists names(surface text primary key, flag int)")
        self.db.execute("create table if not exists cuts(span text primary key, parts text)")
        self.db.execute("create table if not exists picks(surface text, base text, term text, reading text, primary key(surface, base))")
        self.db.commit()
        self.manual, self.anki = {}, {}
        self.names = {t: f for t, f in self.db.execute("select surface, flag from names")}
        self.cuts = {t: p.split("|") for t, p in self.db.execute("select span, parts from cuts")}
        self.picks = {(s, b): (t, r) for s, b, t, r in self.db.execute("select surface, base, term, reading from picks")}
        self.readings = {}
        for t, r, s in self.db.execute("select term, reading, status from manual"):
            self.manual[t] = s
            self.readings[t] = r or ""
        self.card = {}
        for t, r, s, ivl, lap, due, note in self.db.execute("select term, reading, status, ivl, lapses, due, note from anki"):
            self.anki[t] = s
            self.readings.setdefault(t, r or "")
            self.card[t] = {"ivl": ivl or 0, "lapses": lap or 0, "due": bool(due), "note": note or 0}
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

    def set_pick(self, surface, base, term, reading):
        with self.lock:
            if not term:
                self.picks.pop((surface, base), None)
                self.db.execute("delete from picks where surface=? and base=?", (surface, base))
            else:
                self.picks[(surface, base)] = (term, reading)
                self.db.execute("insert or replace into picks values(?,?,?,?)", (surface, base, term, reading))
            self.db.commit()

    def replace_anki(self, rows):
        with self.lock:
            self.db.execute("delete from anki")
            self.db.executemany("insert or replace into anki(term, reading, status, ivl, lapses, due, note) values(?,?,?,?,?,?,?)", rows)
            self.db.commit()
            self.anki = {r[0]: r[2] for r in rows}
            for r in rows:
                self.readings.setdefault(r[0], r[1] or "")
            self.card = {r[0]: {"ivl": r[3], "lapses": r[4], "due": bool(r[5]), "note": r[6]} for r in rows}
            self._index_kana()

    def set_anki(self, term, reading, status, card=None):
        with self.lock:
            if status:
                c = card or {}
                self.db.execute("insert or replace into anki(term, reading, status, ivl, lapses, due, note) values(?,?,?,?,?,?,?)",
                                (term, reading, status, c.get("ivl", 0), c.get("lapses", 0), int(bool(c.get("due"))), c.get("note", 0)))
                self.anki[term] = status
                self.card[term] = {"ivl": c.get("ivl", 0), "lapses": c.get("lapses", 0), "due": bool(c.get("due")), "note": c.get("note", 0)}
            else:
                self.db.execute("delete from anki where term=?", (term,))
                self.anki.pop(term, None)
                self.card.pop(term, None)
            self.db.commit()
            self._index_kana()

    def reading_of(self, term):
        return self.readings.get(term, "")

    def card_of(self, term, reading=""):
        """Card facts for a word being learned: the card behind its term, or behind the kana spelling of its reading."""
        if self.manual.get(term):
            return None
        c = self.card.get(term)
        if c is None and reading and self.kana.get(reading) == "learning":
            c = self.card.get(reading)
        return c

    def counts(self):
        return len(set(self.manual) | set(self.anki))

    def words_with(self, ch, limit=12):
        """words with this character that are known or being learned, known first"""
        seen = {}
        for t in list(self.manual) + list(self.anki):
            if ch in t and t not in seen:
                st = self.manual.get(t) or self.anki.get(t)
                if st in ("known", "learning"):
                    seen[t] = st
        order = sorted(seen.items(), key=lambda kv: (kv[1] != "known", len(kv[0])))
        return [{"term": t, "status": st} for t, st in order[:limit]]


# ------------------------------------------------------------------ segmentation

_tagger = None


def tagger():
    global _tagger
    if _tagger is None:
        import fugashi
        _tagger = fugashi.Tagger()
    return _tagger


def is_sound(w):
    return w["k"] == "word" and w["pos"] == "感動詞" and w["s"] not in SOUND_KEEP and SOUND_KANA.fullmatch(w["s"]) is not None


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
        base = getattr(f, "orthBase", "") or t.surface
        words.append({"s": t.surface, "k": kind, "lemma": lemma, "kana": getattr(f, "kana", "") or "",
                      "base": base, "lform": kata_to_hira(getattr(f, "lForm", "") or ""),
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
        self.path = os.path.join(STATE, "lookups6.json")
        self.cache = {}
        self.kanji_cache = {}
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

    @staticmethod
    def _matches(surface, entries):
        for e in entries:
            if e.get("headwords") and any(s.get("isPrimary") and s.get("originalText") == surface
                                           for s in e["headwords"][0].get("sources", [])):
                yield e

    def _pick(self, surface, entries, hint=None):
        """The entry for a surface. Yomitan lists exact nouns first (しない -> 市内, 竹刀 before する), so
        what unidic says about the word in context (dictionary form, reading, inflected or not) re-ranks them;
        a manual choice in hint["pick"] = (term, reading) beats that."""
        hint = hint or {}
        best, top = None, -1
        cands = list(self._matches(surface, entries))
        # keep the entries that spell the word the way the subtitle does: a kana surface wants a kana
        # headword (した -> する, not 下), a kanji one the same written stem (感じてる -> 感じる, not unidic's
        # older 感ずる). Surfaces with no such entry (はし) keep them all for the scoring.
        KANA = re.compile(r"[\u3040-\u309f\u30a0-\u30ffー]+")
        if KANA.fullmatch(surface):
            # (and read the way unidic reads the word, or a short-causative う would beat 箸 for はし)
            faithful = [e for e in cands if KANA.fullmatch(e["headwords"][0]["term"])
                        and (not hint.get("lform") or e["headwords"][0]["reading"] == hint["lform"])]
        else:
            faithful = [e for e in cands if re.search(r"[\u3400-\u9fff]", e["headwords"][0]["term"])
                        and surface.startswith(e["headwords"][0]["term"][:-1] or e["headwords"][0]["term"])]
        if faithful and not hint.get("pick"):
            cands = faithful
        for e in cands:
            h = e["headwords"][0]
            if hint.get("pick"):
                if (h["term"], h["reading"]) == tuple(hint["pick"]):
                    return e
                continue
            score = 0
            if hint.get("base") and h["term"] in (hint["base"], hint.get("lemma")):
                score += 4
            if hint.get("lform") and h["reading"] == hint["lform"]:
                score += 2
            if "infl" in hint and bool(e.get("inflectionRuleChainCandidates")) == hint["infl"]:
                score += 2
            if score > top:
                best, top = e, score
        return best

    @staticmethod
    def _key(surface, hint):
        if not hint:
            return surface
        pick = hint.get("pick")
        return "\t".join([surface, hint.get("base", ""), "p:%s|%s" % tuple(pick) if pick else "v" if hint.get("infl") else "n"])

    def lookup_many(self, items):
        """items: surfaces, or (surface, hint) pairs where the hint is the unidic view of the word in context
        ({base, lemma, lform, infl, pick}). -> [summary or None] in the same order. Cached by surface + hint;
        misses go to /termEntries in batches."""
        items = [(x, None) if isinstance(x, str) else x for x in items]
        keys = [self._key(s, h) for s, h in items]
        need = {}
        for (s, h), k in zip(items, keys):
            if k not in self.cache:
                need.setdefault(s, {})[k] = h
        names = list(need)
        if names and self.alive():
            for i in range(0, len(names), 40):
                batch = names[i:i + 40]
                try:
                    res = post(YOMITAN + "/termEntries", {"term": batch}, 30)
                except Exception as e:
                    print("termEntries failed:", e)
                    self.up = False
                    break
                for r in res:
                    s = batch[r["index"]]
                    for k, h in need[s].items():
                        e = self._pick(s, r.get("dictionaryEntries", []), h)
                        e = self._follow(e) if e else e
                        self.cache[k] = self._summary(e) if e else None
                        self.dirty += 1
            self.save()
        return [self.cache.get(k) for k in keys]

    def alternates(self, surface):
        """distinct headwords Yomitan offers for a surface, in its order"""
        res = post(YOMITAN + "/termEntries", {"term": surface}, 15)
        out, seen = [], set()
        for e in self._matches(surface, res.get("dictionaryEntries", [])):
            h = e["headwords"][0]
            if (h["term"], h["reading"]) in seen:
                continue
            seen.add((h["term"], h["reading"]))
            chain = [r["name"] for c in e.get("inflectionRuleChainCandidates", [])[:1] for r in c.get("inflectionRules", [])]
            out.append({"term": h["term"], "reading": h["reading"], "chain": chain})
        return out

    def entry(self, surface, term, reading):
        res = post(YOMITAN + "/termEntries", {"term": surface}, 15)
        ents = res.get("dictionaryEntries", [])
        for e in ents:
            h = e["headwords"][0]
            if h["term"] == term and (not reading or h["reading"] == reading):
                return e
        return self._follow(ents[0]) if ents else None

    def kanji(self, ch):
        """one summary for a character, merged from the kanji dictionaries (KANJIDIC, JPDB Kanji); kanji data
        never changes, so it is kept for the session"""
        if ch in self.kanji_cache:
            return self.kanji_cache[ch]
        res = post(YOMITAN + "/kanjiEntries", {"character": ch}, 15)
        out = None
        for e in res if isinstance(res, list) else []:
            name = e.get("dictionary", "")
            misc = {x["name"]: x["value"] for x in e.get("stats", {}).get("misc", [])}
            if name.startswith("KANJIDIC"):
                out = out or {"char": ch}
                out.update(meanings=e.get("definitions", []), on=e.get("onyomi", []), kun=e.get("kunyomi", []),
                           strokes=misc.get("strokes", ""), grade=misc.get("grade", ""), jlpt=misc.get("jlpt", ""),
                           freq=misc.get("freq", ""), jouyou=any(t.get("name") == "jouyou" for t in e.get("tags", [])))
            elif name.startswith("JPDB Kanji"):
                out = out or {"char": ch}
                defs = e.get("definitions", [])
                cut = defs.index("漢字分解:") if "漢字分解:" in defs else len(defs)
                out.update(words=[w for w in defs[:cut] if w][:12],
                           parts=(defs[cut + 1].split() if cut + 1 < len(defs) else []),
                           share=e.get("kunyomi", []), kentei=misc.get("漢字検定", ""))
        if out:
            out.setdefault("meanings", [])
            out.setdefault("on", [])
            out.setdefault("kun", [])
            out.setdefault("words", [])
            out.setdefault("parts", [])
            out.setdefault("share", [])
        self.kanji_cache[ch] = out
        return out

    def _follow(self, entry):
        """JMdict lists a spelling variant (降りはじめる) as a stub that only says ⟶降り始める: use the entry it points to."""
        target = _redirect(entry)
        if not target:
            return entry
        try:
            ents = post(YOMITAN + "/termEntries", {"term": target}, 15).get("dictionaryEntries", [])
        except Exception:
            return entry
        tail = re.sub(r"[^\u3040-\u309f]", "", entry["headwords"][0]["term"])
        best = [e for e in ents if e["headwords"][0]["term"] == target]
        best.sort(key=lambda e: tail not in e["headwords"][0]["reading"])
        return best[0] if best else entry


# ------------------------------------------------------------------ glossary -> html

GLOSS_SEP = "\u2063|\u2063"     # between the senses of one definition; the card dims it, see WordPopup.tidy


def _inline_glossary(html):
    """Anki's rendered glossary lists (data-sc-content="glossary") as one line: a | b | c, the pipes dimmed"""
    def one(m):
        items = re.findall(r"<li[^>]*>(.*?)</li>", m.group(1), re.S)
        if not items:
            return m.group(0)
        pipe = '<span style="opacity:0.4"> | </span>'
        return '<span data-sc-content="glossary">%s</span>' % pipe.join(items)
    return re.sub(r'<ul[^>]*data-sc-content="glossary"[^>]*>(.*?)</ul>', one, html, flags=re.S)


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
        if tag in ("ul", "ol") and (n.get("data") or {}).get("content") == "glossary":
            items = n.get("content")
            items = items if isinstance(items, list) else [items]
            return GLOSS_SEP.join(sc_html(i.get("content") if isinstance(i, dict) else i) for i in items) + "<br>"
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


def _sc_text(n, links):
    """plain text of structured content, hrefs collected into links"""
    if isinstance(n, str):
        return n
    if isinstance(n, list):
        return "".join(_sc_text(x, links) for x in n)
    if isinstance(n, dict):
        if n.get("tag") == "a" and n.get("href"):
            links.append(n["href"])
        return _sc_text(n.get("content"), links)
    return ""


def _redirect(entry):
    """the term an entry only points to (every definition is just ⟶ and one link), else None"""
    target = None
    defs = entry.get("definitions", [])
    for d in defs:
        for g in d.get("entries", []):
            links = []
            text = _sc_text(g, links).strip()
            if not text.startswith("⟶") or len(links) != 1:
                return None
            q = urllib.parse.parse_qs(urllib.parse.urlparse(links[0]).query).get("query")
            if not q or (target and q[0] != target):
                return None
            target = q[0]
    return target


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


def _grade(c, kind):
    if kind == "core":
        return "known"
    if c.get("queue") == -1:                     # suspended mined card: no information
        return None
    return "known" if c.get("type") == 2 and c.get("interval", 0) >= MATURE_DAYS else "learning"


def _card(c, due):
    return {"ivl": c.get("interval", 0), "lapses": c.get("lapses", 0), "due": c.get("cardId", 0) in due,
            "note": c.get("note", 0)}


def _due_ids(extra=""):
    ids = anki("findCards", query="(%s) is:due%s" % (ANKI_QUERY, extra))
    return set(ids or [])


def recheck_anki(store, term, reading="", rank=0):
    """Re-reads the cards of one word, so a card deleted (or suspended, or matured) in Anki is noticed when the
    word is looked at instead of at the next full sync."""
    esc = term.replace("\\", "\\\\").replace('"', '\\"').replace("*", "\\*").replace("_", "\\_")
    best, card = None, None
    due = _due_ids()
    for query, wf, rf, kind in ANKI_SOURCES:
        ids = anki("findCards", query='(%s) "%s:*%s*"' % (query, wf, esc))
        for c in anki("cardsInfo", cards=ids) if ids else []:
            if plain(c.get("fields", {}).get(wf, {}).get("value")) != term:
                continue
            st = _grade(c, kind)
            if st and (best is None or RANK[st] > RANK[best]):
                best, card = st, _card(c, due)
    before = store.anki.get(term)
    if best != before or (card and card != store.card.get(term)):
        store.set_anki(term, reading, best, card)
    return {"status": store.status(term, reading, rank), "changed": best != before, "noteId": (card or {}).get("note", 0)}


def sync_anki(store):
    best = {}
    due = _due_ids()
    for query, wf, rf, kind in ANKI_SOURCES:
        ids = anki("findCards", query=query)
        for i in range(0, len(ids), 500):
            for c in anki("cardsInfo", cards=ids[i:i + 500]):
                f = c.get("fields", {})
                term = plain(f.get(wf, {}).get("value"))
                if not term or len(term) > 20:       # Kaishi's first note is a welcome text
                    continue
                reading = plain(f.get(rf, {}).get("value"))
                st = _grade(c, kind)
                if not st:                           # suspended mined card: no information
                    continue
                k = _card(c, due) if kind != "core" else {"ivl": 0, "lapses": 0, "due": False, "note": 0}
                old = best.get(term)
                if old is None or RANK[st] > RANK[old[2]] or (st == old[2] == "learning" and k["ivl"] < old[3]):
                    best[term] = (term, reading, st, k["ivl"], k["lapses"], int(k["due"]), k["note"])
                elif st == old[2]:                   # several cards of one word: lapses add up, due if any is
                    best[term] = old[:4] + (max(old[4], k["lapses"]), int(old[5] or k["due"]), old[6])
    store.replace_anki(list(best.values()))
    return {"known": sum(1 for v in best.values() if v[2] == "known"),
            "learning": sum(1 for v in best.values() if v[2] == "learning")}


# ------------------------------------------------------------------ core

store = Store()
yom = Yomitan()


# ソロ, コンクール: loan words are not tracked (plain, outside the stats) unless a card or a mark of yours says otherwise.
# QS_TRACK_KATAKANA=1 brings them back.
KATAKANA_WORD = re.compile(r"[\u30a1-\u30faー・]+")
TRACK_KATAKANA = os.environ.get("QS_TRACK_KATAKANA", "") == "1"


def _status(term, reading, rank, matched):
    st = store.status(term, reading, rank)
    if st == "unknown" and (not matched or (not TRACK_KATAKANA and KATAKANA_WORD.fullmatch(term) and term not in store.manual)):
        return "none"
    return st


def hint_of(w):
    """what unidic knows about a word in context, for Yomitan._pick; a manual pick overrides it"""
    base = w.get("base") or w["lemma"]
    h = {"base": base, "lemma": w["lemma"], "lform": w.get("lform", ""),
         "infl": w["pos"] in ("動詞", "形容詞", "助動詞") and w["s"] != base}
    pick = store.picks.get((w["s"], base))
    if pick:
        h["pick"] = list(pick)
    return h


def flag_card(t):
    """Marks a word token being learned with what its card says: due today, leech, interval, lapses."""
    for k in ("due", "leech", "ivl", "lapses"):
        t.pop(k, None)
    if t.get("status") != "learning":
        return
    c = store.card_of(t["term"], t.get("reading", ""))
    if c:
        t.update(due=c["due"], leech=c["lapses"] >= LEECH_LAPSES, ivl=c["ivl"], lapses=c["lapses"])


def annotate(texts):
    """texts: [str] -> [[token]] with lookups resolved in one batch."""
    segs = [apply_cuts(segment_text(t), store.cuts) for t in texts]
    isname = lambda w: bool(store.names.get(w["s"], w.get("name"))) or is_sound(w)
    cand = [w for ws in segs for w in ws if w["k"] == "word" and not isname(w)]
    res = yom.lookup_many([(w["s"], hint_of(w)) for w in cand])
    found = {id(w): r for w, r in zip(cand, res)}
    # words Yomitan could not match as a whole: retry with the unidic dictionary form
    miss = [w for w in cand if not found[id(w)] and w["lemma"] != w["s"]]
    found2 = {id(w): r for w, r in zip(miss, yom.lookup_many([w["lemma"] for w in miss]))} if miss else {}
    out = []
    for ws in segs:
        toks = []
        for w in ws:
            tok = {"s": w["s"], "k": w["k"]}
            if is_sound(w) and not store.names.get(w["s"]):
                reading = kata_to_hira(w["kana"])
                tok.update(term=w["s"], reading=reading, freq=0, rank=0, status="none", known=False, auto=False,
                           sound=True, key=w["s"] + "|" + reading)
            elif w["k"] == "word" and (store.names.get(w["s"], w.get("name"))):
                reading = kata_to_hira(w["kana"])
                tok.update(term=w["s"], reading=reading, freq=0, rank=0, status="name", known=False, auto=False,
                           name=True, key=w["s"] + "|" + reading)
                if KANJI.search(w["s"]):
                    tok["ruby"] = ruby(w["morph"])
            elif w["k"] == "word":
                info = found.get(id(w)) or found2.get(id(w))
                term = info["term"] if info else w["lemma"]
                reading = info["reading"] if info else kata_to_hira(w["kana"])
                rank = info["rank"] if info else 0
                tok.update(term=term, reading=reading, freq=info["freq"] if info else 0, rank=rank,
                           status=_status(term, reading, rank, bool(info)), known=bool(info),
                           auto=store.is_auto(term, reading, rank))
                tok["key"] = term + "|" + reading
                tok["base"] = w.get("base") or w["lemma"]
                flag_card(tok)
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
    n_known = n_unknown = n_tokens = plus_one = n_learn = 0
    new = set()
    for ts in toks:
        unk_here = set()
        for t in ts:
            if t["k"] != "word":
                continue
            if t.get("name") or t.get("sound"):
                continue
            t["status"] = _status(t["term"], t["reading"], t.get("rank", 0), t.get("known", False))
            if t["status"] == "none":
                continue
            n_tokens += 1
            t["auto"] = store.is_auto(t["term"], t["reading"], t.get("rank", 0))
            flag_card(t)
            if t["status"] == "learning":
                n_learn += 1
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
            "learning": n_learn, "learnPct": round(100.0 * n_learn / n_tokens, 1) if n_tokens else 0.0,
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
        lrn = {t["key"] for t in ts if t["k"] == "word" and t["status"] == "learning"}
        flag = any(t.get("due") or t.get("leech") for t in ts if t["k"] == "word")
        out.append({"start": a, "end": b, "text": text, "toks": ts, "unk": len(unk), "lrn": len(lrn), "flag": flag})
    return {"lines": out, "stats": stats}


def learning_list(path=""):
    """Every word being learned (a card with interval under 21 days, or marked learning by hand), with its card facts
    and how often it comes up in the subtitle file."""
    here = {}
    if path:
        lines, toks = _load(path)
        _stats(lines, toks)
        for ts in toks:
            seen = set()
            for t in ts:
                if t["k"] == "word" and t["term"] not in seen:
                    seen.add(t["term"])
                    here[t["term"]] = here.get(t["term"], 0) + 1
    out = []
    # a manual mark wins over the card, so a word the user marked known/unknown/ignored is no longer being learned
    terms = {t for t, s in store.anki.items() if s == "learning" and store.manual.get(t, "learning") == "learning"} | {t for t, s in store.manual.items() if s == "learning"}
    for term in terms:
        manual = store.manual.get(term) == "learning"
        c = {} if manual else store.card.get(term, {})
        out.append({"term": term, "reading": store.reading_of(term), "ivl": c.get("ivl", 0), "lapses": c.get("lapses", 0),
                    "due": bool(c.get("due")), "leech": c.get("lapses", 0) >= LEECH_LAPSES, "note": c.get("note", 0),
                    "source": "manual" if manual else "anki", "here": here.get(term, 0)})
    marks = []
    with store.lock:
        rows = store.db.execute("select term, reading, status, updated from manual where status != 'learning' order by updated desc").fetchall()
    for term, reading, status, updated in rows:
        c = store.card.get(term, {})
        marks.append({"term": term, "reading": reading or "", "status": status, "updated": updated or 0, "ivl": c.get("ivl", 0),
                      "lapses": c.get("lapses", 0), "due": bool(c.get("due")), "leech": c.get("lapses", 0) >= LEECH_LAPSES,
                      "note": c.get("note", 0), "anki": store.anki.get(term, ""), "here": here.get(term, 0)})
    return out, marks


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


SPAN_LIMIT = 4       # lines either side of the target the card can be stretched to


def _prepare(req):
    """The note fields for a word: the format's templates filled from /ankiFields, with the cloze sentence taken from
    the lines the span covers (req["span"], else sentence_span's pick). -> dict, or {"error"}."""
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
                if req.get("span"):
                    a = min(line, max(line - SPAN_LIMIT, req["span"][0]))
                    b = max(line, min(line + SPAN_LIMIT, len(lines) - 1, req["span"][1]))
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
    for k in vals:
        if "glossary" in k and isinstance(vals[k], str):
            vals[k] = _inline_glossary(vals[k])
    fields = {k: re.sub(r"\{([^{}]+)\}", lambda m: str(vals.get(m.group(1), "")), v) for k, v in templates.items()}
    return {"fmt": fmt, "fields": fields, "templates": templates, "res": res, "vals": vals, "span": span, "line": line}


def _blank_derived(note_id, fields, out):
    """Fields an Anki add-on derives from the sentence (Kiku's furigana) would go stale when `fields` rewrites it:
    blank them in `out`, Anki then shows the plain sentence."""
    if "Sentence" not in fields:
        return
    have = (anki("notesInfo", notes=[note_id]) or [{}])[0].get("fields", {})
    for k in ("SentenceFurigana",):
        if k in have and k not in fields:
            out[k] = ""


def mine(req):
    """Add the word the way Yomitan's own card format would (see _prepare). The caller then asks `capture` for the
    sentence's audio and picture."""
    term, reading = req["term"], req.get("reading", "")
    p = _prepare(req)
    if "error" in p:
        return p
    fmt, fields, vals, res, span, line = p["fmt"], p["fields"], p["vals"], p["res"], p["span"], p["line"]

    # media Yomitan attached: the audio marker holds the [sound:name] tags in the order of audioMedia
    names = re.findall(r"\[sound:([^\]]+)\]", str(vals.get("audio", "")))
    for name, m in zip(names, res.get("audioMedia", [])):
        anki("storeMediaFile", filename=name, data=m["content"])
    for m in res.get("dictionaryMedia", []):
        if m.get("ankiFilename") and m.get("content"):
            anki("storeMediaFile", filename=m["ankiFilename"], data=m["content"])

    if req.get("replace"):
        # overwrite the card already in Anki: same note (id, tags, review history), every field rebuilt
        note_id = req["replace"]
        _blank_derived(note_id, fields, fields)
        anki("updateNoteFields", note={"id": note_id, "fields": fields})
        return {"noteId": note_id, "span": span, "line": line, "lines": span[1] - span[0] + 1 if line >= 0 else 1}

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


def span_info(req):
    """The cue under the word and its neighbours, for the card's sentence preview: `auto` is what mining would take."""
    try:
        lines, _toks = _load(req["path"])
    except (OSError, KeyError):
        return {"line": -1}
    line = _line_at(lines, req.get("start", -1)) if req.get("start", -1) >= 0 else -1
    if line < 0:
        return {"line": -1}
    a, b = sentence_span(lines, line)
    lo, hi = max(0, line - SPAN_LIMIT), min(len(lines) - 1, line + SPAN_LIMIT)
    return {"line": line, "auto": [a, b],
            "lines": [{"i": k, "text": _strip_label(re.sub(r"\s+", "", lines[k][2])), "start": lines[k][0], "end": lines[k][1]}
                      for k in range(lo, hi + 1)]}


def respan(req):
    """Rewrite the sentence of a note already mined, for another set of lines; the caller then re-runs `capture`."""
    p = _prepare(req)
    if "error" in p:
        return p
    want = {k: v for k, v in p["fields"].items() if re.search(r"\{(cloze-prefix|cloze-suffix|cloze-body|sentence)\}", p["templates"][k])}
    if want:
        _blank_derived(req["noteId"], want, want)
        anki("updateNoteFields", note={"id": req["noteId"], "fields": want})
    a, b = p["span"]
    return {"noteId": req["noteId"], "span": p["span"], "line": p["line"], "lines": b - a + 1 if p["line"] >= 0 else 1}


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
            # the clip covers the whole span, so it follows the sentence when a neighbouring line is added
            cs, ce = lines[a][0] + delay, lines[b][1] + delay
            dur = min(12.0, max(0.5, ce - cs))
            pname = show + "_" + _hms(cs) + "_" + _hms(cs + dur) + ".avif"
            ppath = os.path.join(MEDIA_TMP, pname)
            _ffmpeg(["-ss", "%.3f" % max(0.0, cs), "-t", "%.3f" % dur, "-i", video, "-an", "-sn",
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
        s["alts"] = yom.alternates(surface)
        s["freqs"] = [{"dict": f["dictionary"], "value": f.get("displayValue") or str(f.get("frequency", ""))}
                      for f in e.get("frequencies", []) if f.get("headwordIndex", 0) == 0]
        s["sections"] = glossary(e)
        s["uk"] = any(t.get("name") == "uk" for d in e.get("definitions", []) for t in d.get("tags", []))
        s["status"] = store.status(s["term"], s["reading"], s["rank"])
        s["auto"] = store.is_auto(s["term"], s["reading"], s["rank"])
        return s
    if op == "kanji":
        if not yom.alive():
            return {"error": "yomitan-offline"}
        out = []
        for ch in req.get("chars", []):
            k = yom.kanji(ch)
            out.append(dict(k, mine=store.words_with(ch)) if k else None)
        return {"kanji": out}
    if op == "mark":
        store.mark(req["term"], req.get("reading", ""), req["status"])
        return {"ok": True, "status": store.status(req["term"], req.get("reading", ""), req.get("rank", 0))}
    if op == "name":
        store.set_name(req["surface"], req["flag"])
        _parsed.clear()
        return {"ok": True}
    if op == "pick":
        store.set_pick(req["surface"], req["base"], req.get("term", ""), req.get("reading", ""))
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
    if op == "recheck":
        return recheck_anki(store, req["term"], req.get("reading", ""), req.get("rank", 0))
    if op == "learning":
        words, marks = learning_list(req.get("path", ""))
        return {"words": words, "marks": marks}
    if op == "parse_file":
        return parse_file(req["path"])
    if op == "transcript":
        return transcript(req["path"])
    if op == "mine":
        return mine(req)
    if op == "span":
        return span_info(req)
    if op == "respan":
        return respan(req)
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
        if req.get("op") in ("parse_file", "transcript", "sync", "mine", "respan", "span", "capture"):
            threading.Thread(target=run, args=(req,), daemon=True).start()
        else:
            run(req)
    yom.save()
    return 0


if __name__ == "__main__":
    sys.exit(main())
