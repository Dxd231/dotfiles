#!/usr/bin/env python3
"""
Fetch random safe desktop wallpapers from Konachan matching end-4's random wallpaper pool and tags.
API: https://konachan.net/post.json?tags=rating:safe&page=<1..1000>
"""
import json
import random
import re
import sys
import urllib.request

USER_AGENT = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/123.0.0.0 Safari/537.36"

def safe_tags(raw, max_tags=8, max_len=100):
    """Tags that are safe to put in a file name, in API order, capped in count and length."""
    out = []
    length = 0
    for tag in str(raw or "").split():
        tag = re.sub(r"[^A-Za-z0-9_()-]", "", tag)
        if not tag or tag in out:
            continue
        if len(out) >= max_tags or length + len(tag) + 1 > max_len:
            break
        out.append(tag)
        length += len(tag) + 1
    return " ".join(out)

def main():
    # Retry up to 3 random pages if needed
    for _ in range(3):
        # Pick random page across the first 1000 pages (matching end-4's random_konachan_wall.sh)
        page = random.randint(1, 1000)
        url = f"https://konachan.net/post.json?tags=rating:safe&limit=20&page={page}"
        try:
            req = urllib.request.Request(
                url,
                headers={"User-Agent": USER_AGENT}
            )
            with urllib.request.urlopen(req, timeout=10) as resp:
                data = json.loads(resp.read().decode("utf-8"))

            if not isinstance(data, list) or not data:
                continue

            # Filter for landscape desktop wallpapers with valid URLs
            candidates = [
                p for p in data
                if p.get("sample_url") and p.get("file_url")
                and p.get("width", 0) > p.get("height", 0)
                and (1.3 <= (p.get("width", 0) / max(1, p.get("height", 1))) <= 2.5)
            ]

            # Fallback to any valid post on the page if no strict landscape ratio
            if not candidates:
                candidates = [
                    p for p in data
                    if p.get("sample_url") and p.get("file_url")
                ]

            if not candidates:
                continue

            selected = random.choice(candidates)
            sample_url = selected.get("sample_url", "").strip()
            file_url = selected.get("file_url", "").strip()
            post_id = str(selected.get("id", "")).strip()

            if sample_url and file_url and post_id:
                print(f"{sample_url}\t{file_url}\t{post_id}\t{safe_tags(selected.get('tags'))}")
                return
        except Exception:
            continue

    sys.exit(1)

if __name__ == "__main__":
    main()
