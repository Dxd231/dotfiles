#!/usr/bin/env python3
"""Manga page OCR worker for qs-manga (run with ~/.venv/mokuro/bin/python -I).

comic-text-detector (the mokuro detector) finds the bubbles, manga-ocr-base-CPT-flex reads each bubble whole.
JSON lines on stdin/stdout, like ocr_server.py:
  -> {"ready": true, "device": "cuda", "detector": "comic-text-detector", "reader": "CPT-flex"}   once the models are loaded
  <- {"id": 1, "path": "/path/page.png"}
  -> {"id": 1, "w": 1600, "h": 2338, "ms": 812, "blocks": [{"box": [x0, y0, x1, y1], "vertical": true, "ctd_vertical": true,
       "font_size": 38.0, "lines": [[[x, y] * 4], ...], "text": "...", "drop": null | "nojp" | "edge"}]}
     or {"id": 1, "error": "..."}
A block is vertical when its box is at least as tall as it is wide. Blocks with no kana or kanji, and small blocks hugging the page
edge (watermarks, page numbers), are kept but flagged in `drop`. Closing stdin ends the worker.
"""
import json
import os
import re
import sys
import time

# libraries print progress to stdout; the protocol gets the real one
OUT = sys.stdout
sys.stdout = sys.stderr

import cv2
import numpy as np
import torch

CPT_DIR = os.environ.get("QS_MANGA_CPT_DIR", os.path.expanduser("~/.local/share/manga-ocr/manga-ocr-base-CPT-flex"))
PAD = 6                  # px added around a bubble before it is read
EDGE_FRAC = 0.03         # a box within this share of a page edge ...
EDGE_AREA = 0.01         # ... and smaller than this share of the page is a margin mark
JP = re.compile("[぀-ヿ一-鿿㐀-䶿]")


def send(obj):
    OUT.write(json.dumps(obj, ensure_ascii=False) + "\n")
    OUT.flush()


def load():
    from comic_text_detector.inference import TextDetector
    from manga_ocr_cpt import MangaOcrCPT
    from mokuro.cache import cache
    device = "cuda" if torch.cuda.is_available() else "cpu"
    detector = TextDetector(model_path=cache.comic_text_detector, input_size=1024, device=device, act="leaky")
    reader = MangaOcrCPT(CPT_DIR, device=device, backend="plain")
    return detector, reader, device


def drop_reason(text, box, W, H):
    if not JP.search(text):
        return "nojp"
    x0, y0, x1, y1 = box
    mx, my = W * EDGE_FRAC, H * EDGE_FRAC
    touches = x0 < mx or y0 < my or x1 > W - mx or y1 > H - my
    if touches and (x1 - x0) * (y1 - y0) < W * H * EDGE_AREA:
        return "edge"
    return None


def page(detector, reader, path):
    img = cv2.imdecode(np.fromfile(path, np.uint8), cv2.IMREAD_COLOR)   # sniffs the content, not the extension
    if img is None:
        raise ValueError("cannot decode " + path)
    H, W = img.shape[:2]
    _, _, blks = detector(img, refine_mode=1, keep_undetected_mask=True)
    rgb = cv2.cvtColor(img, cv2.COLOR_BGR2RGB)
    crops, boxes = [], []
    for b in blks:
        x0, y0, x1, y1 = [int(v) for v in b.xyxy]
        boxes.append([max(0, x0), max(0, y0), min(W, x1), min(H, y1)])
        crops.append(rgb[max(0, y0 - PAD):min(H, y1 + PAD), max(0, x0 - PAD):min(W, x1 + PAD)])
    texts = [""] * len(crops)
    ok = [i for i, c in enumerate(crops) if c.shape[0] > 1 and c.shape[1] > 1]
    if ok:
        for i, t in zip(ok, reader([crops[i] for i in ok])):
            texts[i] = str(t).strip()
    out = []
    for b, box, text in zip(blks, boxes, texts):
        out.append({
            "box": box,
            "vertical": (box[3] - box[1]) >= (box[2] - box[0]),
            "ctd_vertical": bool(b.vertical),
            "font_size": float(b.font_size),
            "lines": [np.asarray(l).astype(int).tolist() for l in b.lines_array()],
            "text": text,
            "drop": drop_reason(text, box, W, H),
        })
    return W, H, out


def main():
    detector, reader, device = load()
    # one throw-away page so the first real one isn't slow
    reader([np.full((64, 64, 3), 255, np.uint8)])
    send({"ready": True, "device": device, "detector": "comic-text-detector", "reader": "CPT-flex"})
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            req = json.loads(line)
        except ValueError:
            continue
        rid = req.get("id")
        t0 = time.time()
        try:
            W, H, blocks = page(detector, reader, req["path"])
            send({"id": rid, "w": W, "h": H, "ms": round((time.time() - t0) * 1000), "blocks": blocks})
        except Exception as e:   # one bad page must not end the worker
            send({"id": rid, "error": "%s: %s" % (type(e).__name__, e)})


if __name__ == "__main__":
    main()
