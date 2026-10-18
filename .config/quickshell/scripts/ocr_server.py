#!/usr/bin/env python3
"""One OCR engine per process, driven over stdin/stdout with JSON lines. The shell starts it when a
snip is first needed and stops it again after a while, so the model only sits in RAM / VRAM while
it is in use.

  ocr_server.py --engine manga     (run with ~/.venv/bin/python:       manga-ocr-base-CPT-flex via
                                    manga_ocr_cpt, else manga_ocr; one text block)
  ocr_server.py --engine paddle    (run with ~/.venv/paddle/bin/python: PaddleOCR, whole text areas)

  -> {"ready": true, "engine": "manga", "device": "cuda", "model": "CPT-flex"}   once the model is loaded
  <- {"id": 1, "path": "/tmp/shot.png", "rect": [x, y, w, h]}          rect (pixels) is optional
  -> {"id": 1, "text": "...", "ms": 412, "engine": "manga"}           or {"id": 1, "error": "..."}
  <- {"id": 2, "path": "/tmp/shot.png", "detect": true}                paddle only: find the text blocks
  -> {"id": 2, "blocks": [{x, y, w, h, text, lines, conf, score, dialogue}], "ms": 640}
  <- {"quit": true}                                                    (or close stdin) to exit

Everything the libraries print goes to stderr; stdout carries the protocol only.
"""
import argparse
import json
import os
import sys
import tempfile
import time

# keep the protocol channel clean: libraries that print() end up on stderr
_out = os.fdopen(os.dup(1), "w", buffering=1, encoding="utf-8")
sys.stdout = sys.stderr

os.environ.setdefault("HF_HUB_OFFLINE", "1")
os.environ.setdefault("PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK", "True")
os.environ.setdefault("TOKENIZERS_PARALLELISM", "false")


def send(obj):
    _out.write(json.dumps(obj, ensure_ascii=False) + "\n")
    _out.flush()


def load_image(path, rect):
    from PIL import Image
    img = Image.open(path).convert("RGB")
    if rect:
        x, y, w, h = [int(v) for v in rect]
        x = max(0, min(img.width - 1, x))
        y = max(0, min(img.height - 1, y))
        img = img.crop((x, y, min(img.width, x + max(1, w)), min(img.height, y + max(1, h))))
    return img


# ------------------------------------------------------------------ manga

class Manga:
    name = "manga"
    CPT_DIR = os.path.expanduser("~/.local/share/manga-ocr/manga-ocr-base-CPT-flex")

    def __init__(self):
        import torch
        self.device = "cuda" if torch.cuda.is_available() else "cpu"
        self.model_name = "base"
        self.model = None
        # manga-ocr-base-CPT-flex (continued pre-training, 6.8k-character vocabulary) when it is
        # installed and downloaded; the original manga-ocr-base otherwise or with QS_MANGA_MODEL=base
        if os.environ.get("QS_MANGA_MODEL", "cpt") != "base" and os.path.isdir(self.CPT_DIR):
            try:
                from manga_ocr_cpt import MangaOcrCPT
                # the plain PyTorch path: ~0.4 GB of VRAM at ~140 ms a read, where the default CUDA-graph
                # path holds ~2.5 GB for ~125 ms (QS_MANGA_BACKEND=auto opts back in)
                self.model = MangaOcrCPT(self.CPT_DIR, device=self.device,
                                         backend=os.environ.get("QS_MANGA_BACKEND", "plain"))
                self.model_name = "CPT-flex"
            except Exception as e:
                print("manga-ocr-CPT unavailable, using manga-ocr-base: %s: %s" % (type(e).__name__, e))
        if self.model is None:
            from manga_ocr import MangaOcr
            self.model = MangaOcr()

    def read(self, img):
        out = self.model(img)
        if isinstance(out, (list, tuple)):
            out = out[0] if out else ""
        return str(out).strip()


# ----------------------------------------------------------------- paddle

class Paddle:
    name = "paddle"

    def __init__(self):
        from paddleocr import PaddleOCR
        self.model = PaddleOCR(use_doc_orientation_classify=False, use_doc_unwarping=False,
                               use_textline_orientation=False, lang="japan")
        try:
            import paddle
            self.device = "cuda" if paddle.device.is_compiled_with_cuda() else "cpu"
        except Exception:
            self.device = "cpu"

    @staticmethod
    def items_of(texts, polys, scores=None):
        items = []
        for k, (t, p) in enumerate(zip(texts, polys)):
            xs = [pt[0] for pt in p]
            ys = [pt[1] for pt in p]
            items.append({"t": t, "x0": min(xs), "y0": min(ys), "x1": max(xs), "y1": max(ys),
                          "x": sum(xs) / len(xs), "y": sum(ys) / len(ys),
                          "w": max(xs) - min(xs), "h": max(ys) - min(ys),
                          "c": float(scores[k]) if scores is not None and k < len(scores) else 1.0})
        return items

    @staticmethod
    def order_items(items):
        """Reading order: vertical columns run right to left, horizontal rows top to bottom then
        left to right."""
        if not items:
            return ""
        items = list(items)
        vertical = sum(1 for i in items if i["h"] > i["w"] * 1.3) > len(items) / 2
        if vertical:
            items.sort(key=lambda i: (-i["x"], i["y"]))
        else:
            # lines whose centres are within half a box height belong to the same row
            items.sort(key=lambda i: i["y"])
            rows, row = [], [items[0]]
            for i in items[1:]:
                if abs(i["y"] - row[-1]["y"]) <= max(row[-1]["h"], i["h"]) * 0.5:
                    row.append(i)
                else:
                    rows.append(row)
                    row = [i]
            rows.append(row)
            items = [i for r in rows for i in sorted(r, key=lambda i: i["x"])]
        return "".join(i["t"] for i in items)

    def predict(self, img):
        with tempfile.NamedTemporaryFile(suffix=".png", delete=False) as f:
            tmp = f.name
        try:
            img.save(tmp)
            res = self.model.predict(tmp)
        finally:
            try:
                os.unlink(tmp)
            except OSError:
                pass
        if not res:
            return [], [], []
        r = res[0]
        return r.get("rec_texts", []) or [], r.get("dt_polys", []) or [], r.get("rec_scores", []) or []

    def read(self, img):
        texts, polys, scores = self.predict(img)
        if texts and len(polys) == len(texts):
            return self.order_items(self.items_of(texts, polys, scores))
        return "".join(texts)

    # ---- text blocks (dialogue boxes, name plates, menu labels, speech bubbles) ----
    def blocks(self, img):
        W, H = img.size
        texts, polys, scores = self.predict(img)
        items = [i for i in self.items_of(texts, polys, scores)
                 if i["t"].strip() and min(i["w"], i["h"]) >= 8 and i["c"] >= 0.5]
        return group_blocks(items, W, H, self.order_items)


def group_blocks(items, W, H, order):
    """Merge neighbouring text lines into blocks: stacked rows of a dialogue box, side-by-side
    columns of vertical text. Returns blocks sorted top to bottom, the likely dialogue box flagged."""
    n = len(items)
    if n == 0:
        return []
    thick = sorted(min(i["w"], i["h"]) for i in items)
    med = thick[len(thick) // 2]
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            parent[a] = parent[parent[a]]
            a = parent[a]
        return a

    def overlap(a0, a1, b0, b1):
        return max(0.0, min(a1, b1) - max(a0, b0))

    for i in range(n):
        for j in range(i + 1, n):
            a, b = items[i], items[j]
            # stacked rows
            gy = max(0.0, max(a["y0"], b["y0"]) - min(a["y1"], b["y1"]))
            ox = overlap(a["x0"], a["x1"], b["x0"], b["x1"]) / max(1.0, min(a["w"], b["w"]))
            # side-by-side columns
            gx = max(0.0, max(a["x0"], b["x0"]) - min(a["x1"], b["x1"]))
            oy = overlap(a["y0"], a["y1"], b["y0"], b["y1"]) / max(1.0, min(a["h"], b["h"]))
            # a short label right above a wide box is a name plate, not the box's first line
            upper, lower = (a, b) if a["y0"] <= b["y0"] else (b, a)
            plate = upper["w"] < 0.4 * lower["w"] and upper["w"] >= upper["h"]
            if (gy < 0.9 * med and ox >= 0.3 and gy <= max(a["h"], b["h"]) and not plate) or \
               (gx < 0.9 * med and oy >= 0.3 and gx <= max(a["w"], b["w"]) and a["h"] > a["w"] and b["h"] > b["w"]):
                parent[find(i)] = find(j)

    groups = {}
    for i in range(n):
        groups.setdefault(find(i), []).append(items[i])
    pad = 10
    out = []
    for members in groups.values():
        x0 = max(0, min(m["x0"] for m in members) - pad)
        y0 = max(0, min(m["y0"] for m in members) - pad)
        x1 = min(W, max(m["x1"] for m in members) + pad)
        y1 = min(H, max(m["y1"] for m in members) + pad)
        text = order(members)
        conf = sum(m["c"] for m in members) / len(members)
        # a dialogue box sits low on the screen, is wide or several lines long, and holds a fair bit of text
        cx = (x0 + x1) / 2 / W
        cy = (y0 + y1) / 2 / H
        clamp = lambda v: max(0.0, min(1.0, v))
        score = (0.35 * clamp((cy - 0.45) / 0.5) + 0.25 * clamp((x1 - x0) / W / 0.5) + 0.15 * clamp(len(members) / 3)
                 + 0.10 * (1 - min(1.0, abs(cx - 0.5) / 0.5)) + 0.15 * clamp(len(text) / 40))
        out.append({"x": round(x0), "y": round(y0), "w": round(x1 - x0), "h": round(y1 - y0), "text": text,
                    "lines": len(members), "conf": round(conf, 3), "score": round(score, 3), "dialogue": False})
    out.sort(key=lambda b: (b["y"], b["x"]))
    best = max(out, key=lambda b: b["score"])
    if best["score"] >= 0.45:
        best["dialogue"] = True
    return out


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--engine", choices=("manga", "paddle"), required=True)
    a = ap.parse_args()
    try:
        engine = Manga() if a.engine == "manga" else Paddle()
    except Exception as e:  # missing package, no model, out of memory
        send({"ready": False, "engine": a.engine, "error": "%s: %s" % (type(e).__name__, e)})
        return 1
    send({"ready": True, "engine": a.engine, "device": engine.device, "model": getattr(engine, "model_name", "")})

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
        rid = req.get("id")
        t0 = time.time()
        try:
            img = load_image(req["path"], req.get("rect"))
            if req.get("detect"):
                if not hasattr(engine, "blocks"):
                    raise RuntimeError("detection needs the general engine")
                send({"id": rid, "blocks": engine.blocks(img), "size": list(img.size),
                      "ms": int((time.time() - t0) * 1000), "engine": a.engine})
                continue
            text = engine.read(img)
            send({"id": rid, "text": text, "ms": int((time.time() - t0) * 1000), "engine": a.engine,
                  "model": getattr(engine, "model_name", "")})
        except Exception as e:
            send({"id": rid, "error": "%s: %s" % (type(e).__name__, e), "engine": a.engine})
    return 0


if __name__ == "__main__":
    sys.exit(main())
