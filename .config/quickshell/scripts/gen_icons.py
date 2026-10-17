#!/usr/bin/env python3
"""Generate Components/icons.json from Material Symbols Rounded.

Filled glyphs come from the SVG pack in ~/material-rounded-svg (one path per icon,
viewBox "0 -960 960 960"); outlined glyphs are extracted from the installed variable
font's default instance (FILL 0, wght 400, opsz 24), which uses the same grid.

Only names that appear as string literals in the shell's QML files are emitted, so
re-run this after adding a new icon:  python3 scripts/gen_icons.py
"""
import json
import pathlib
import re
import sys

from fontTools.pens.svgPathPen import SVGPathPen
from fontTools.pens.transformPen import TransformPen
from fontTools.ttLib import TTFont

ROOT = pathlib.Path(__file__).resolve().parent.parent
PACK = pathlib.Path.home() / "material-rounded-svg"
FONT = pathlib.Path("/usr/share/fonts/TTF/MaterialSymbolsRounded[FILL,GRAD,opsz,wght].ttf")
OUT = ROOT / "Components" / "icons.json"

LITERAL = re.compile(r'"([a-z0-9_]+)"')
PATH_D = re.compile(r'\sd="([^"]+)"')


def used_names(known):
    names = set()
    for qml in ROOT.rglob("*.qml"):
        if ".share" in qml.parts or qml.name == "IconPaths.qml":
            continue
        for lit in LITERAL.findall(qml.read_text(errors="ignore")):
            if lit in known:
                names.add(lit)
    return sorted(names)


def glyph_path(glyphs, name):
    if name not in glyphs:
        return None
    pen = SVGPathPen(glyphs, ntos=lambda v: f"{v:.1f}".rstrip("0").rstrip("."))
    glyphs[name].draw(TransformPen(pen, (1, 0, 0, -1, 0, 0)))  # font is y-up, SVG grid is y-down
    return pen.getCommands()


def main():
    font = TTFont(FONT)
    glyphs = font.getGlyphSet()
    pack = {p.stem for p in PACK.glob("*.svg")}
    known = pack | {g for g in font.getGlyphOrder() if "." not in g}
    names = used_names(known)

    filled, outlined, missing = {}, {}, []
    for name in names:
        svg = PACK / f"{name}.svg"
        d = None
        if svg.exists():
            paths = PATH_D.findall(svg.read_text())
            d = " ".join(paths) if paths else None
        filled[name] = d or glyph_path(glyphs, f"{name}.fill") or glyph_path(glyphs, name)
        outlined[name] = glyph_path(glyphs, name) or filled[name]
        if not filled[name]:
            missing.append(name)

    # read at runtime by Components/IconPaths.qml through a watched FileView, so a re-run
    # shows up immediately (generated QML/JS is cached across Quickshell hot reloads)
    OUT.write_text(json.dumps({"filled": filled, "outlined": outlined}, separators=(",", ":")))
    print(f"{len(names)} icons -> {OUT.relative_to(ROOT)} ({OUT.stat().st_size // 1024} KiB)")
    if missing:
        print("missing:", ", ".join(missing), file=sys.stderr)


if __name__ == "__main__":
    main()
