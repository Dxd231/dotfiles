pragma Singleton
import QtQuick

// The shell's shapes: one table, addressed by name ("cookie4", "sunny"). MorphShape, ShapeBadge and
// LoadingIndicator all take their outlines from `radius()`; nothing else keeps a copy of the formulas.
//
// Rules
//  - Symmetric shapes only. Static or directional ones (heart, arch, triangle) add nothing next to an icon.
//  - A shape means the same thing everywhere. Families: calm, count, festive, playful, special, loud.
//    `boom` is for error / recording / ringing only.
//  - Morph = a state change. Spin = something is running. At most one spinner per surface; continuous
//    cycling only on decorative surfaces (lock screen, idle).
//  - Morph between shapes of compatible symmetry (4 <-> 8) and check each pair used at morph 0.5.
//  - Detailed shapes need >= 20 px (`minSize`); below that ShapeBadge draws the entry's `small` instead.
//  - Small stuff never gets thin shapes: a shape whose valleys pinch in (inner <= 0.7 with more than two lobes:
//    flower, clover4, clover8, star4) is drawn only at >= 36 px, else its `small`, which must be a full shape
//    (inner > 0.7). forSize() enforces it, so a new thin shape follows without a minSize of its own. A spot
//    that asked for its thin shape on purpose (the bar's power star) opts out with `allowThin`.
//  - Image masks (ShapeMask) use calm / festive shapes only and never spin.
//  - No cusps and no breathing amplitude.
//
// Entry fields: r(t) polar radius with a max of 1; inner = its smallest radius (drives glyph fit);
// sym = rotational symmetry; family; minSize; small = fallback below minSize; phase = turn (degrees)
// the shape wants at rest.
//
// Old code addressed shapes by number; `resolve()` still accepts those until every call site is on names.
QtObject {
    id: shapes

    readonly property var legacy: ["softBurst", "cookie9", "pentagon", "pill", "sunny", "cookie4", "oval", "star4"]

    function _cookie(n, a) {
        return t => 1 - a * (1 - Math.cos(n * t));
    }
    // n lobes with round tips; `p` < 1 widens the lobes and narrows the valleys (still smooth)
    function _lobes(n, floor, p) {
        return t => floor + (1 - floor) * Math.pow((1 + Math.cos(n * t)) / 2, p);
    }
    // n puffy lobes: round bumps over narrow rounded valleys (`e` = valley width, smaller is tighter)
    function _puffy(n, floor, e) {
        const lo = Math.sqrt(e), span = Math.sqrt(1 + e) - lo;
        return t => floor + (1 - floor) * (Math.sqrt((1 + Math.cos(n * t)) / 2 + e) - lo) / span;
    }
    // superellipse with exponent p, scaled to a max of 1 (p > 2 squircle, p < 2 rounded diamond)
    function _super(p) {
        let top = 0;
        for (let i = 0; i < 360; i++) {
            const t = i / 360 * Math.PI / 2;
            top = Math.max(top, Math.pow(Math.pow(Math.abs(Math.cos(t)), p) + Math.pow(Math.abs(Math.sin(t)), p), -1 / p));
        }
        return t => Math.pow(Math.pow(Math.abs(Math.cos(t)), p) + Math.pow(Math.abs(Math.sin(t)), p), -1 / p) / top;
    }

    // superellipse left unscaled: it touches the box on its axes (|x|^p + |y|^p = 1), so a mask of this
    // shape fills the whole picture and only the corners are trimmed
    function _boxed(p) {
        return t => Math.pow(Math.pow(Math.abs(Math.cos(t)), p) + Math.pow(Math.abs(Math.sin(t)), p), -1 / p);
    }

    readonly property var table: ({
        softBurst: { r: _cookie(10, 0.06), inner: 0.88, sym: 10, family: "festive", minSize: 14, small: "cookie9" },
        cookie9:   { r: _cookie(9, 0.07), inner: 0.86, sym: 9, family: "count", minSize: 0, small: "cookie9" },
        pentagon:  { r: _cookie(5, 0.09), inner: 0.82, sym: 5, family: "count", minSize: 0, small: "pentagon" },
        pill:      { r: t => 1 / Math.pow(Math.pow(Math.abs(Math.cos(t)), 4) + Math.pow(Math.abs(Math.sin(t) / 0.62), 4), 0.25),
                     inner: 0.62, sym: 2, family: "calm", minSize: 0, small: "pill" },
        sunny:     { r: _cookie(8, 0.1), inner: 0.8, sym: 8, family: "festive", minSize: 14, small: "cookie4" },
        cookie4:   { r: _cookie(4, 0.14), inner: 0.72, sym: 4, family: "calm", minSize: 0, small: "cookie4" },
        oval:      { r: t => 1 / Math.sqrt(Math.pow(Math.cos(t), 2) + Math.pow(Math.sin(t) / 0.78, 2)) * 0.95,
                     inner: 0.74, sym: 2, family: "calm", minSize: 0, small: "oval" },
        star4:     { r: t => 0.6 + 0.4 * Math.pow((1 + Math.cos(4 * t)) / 2, 1.5),
                     inner: 0.6, sym: 4, family: "special", minSize: 20, small: "cookie4" },
        tile:      { r: _boxed(8), inner: 0.95, sym: 4, family: "calm", minSize: 0, small: "tile" },
        tileSoft:  { r: _boxed(7), inner: 0.94, sym: 4, family: "calm", minSize: 0, small: "tileSoft" },
        flower:    { r: _puffy(8, 0.7, 0.06), inner: 0.7, sym: 8, family: "festive", minSize: 20, small: "sunny" },
        clover4:   { r: _lobes(4, 0.55, 0.8), inner: 0.55, sym: 4, family: "playful", minSize: 16, small: "cookie4" },
        clover8:   { r: _puffy(8, 0.52, 0.025), inner: 0.52, sym: 8, family: "playful", minSize: 24, small: "sunny" },
        gem:       { r: _super(1.3), inner: 0.83, sym: 4, family: "special", minSize: 16, small: "cookie4" },
        boom:      { r: _lobes(12, 0.74, 1.5), inner: 0.74, sym: 12, family: "loud", minSize: 24, small: "sunny" }
    })

    // name (or an old number) -> a name that exists; unknown names warn once per call site and become oval
    function resolve(shape) {
        if (typeof shape === "string" && table[shape] !== undefined)
            return shape;
        if (typeof shape === "number" && Number.isFinite(shape))
            return legacy[shape] !== undefined ? legacy[shape] : "oval";
        console.warn("Shapes: unknown shape", shape);
        return "oval";
    }

    function radius(shape, t) {
        return table[resolve(shape)].r(t);
    }

    // the largest glyph that fits inside the shape at `size` px, with a little slack
    function glyphMax(shape, size) {
        return 1.2 * table[resolve(shape)].inner * size / 2;
    }

    // below this many px, thin shapes fall back to their `small`
    readonly property int thinMinSize: 36
    function isThin(shape) {
        const e = table[resolve(shape)];
        return e.inner <= 0.7 && e.sym > 2;
    }

    // what to actually draw at `size` px
    function forSize(shape, size, allowThin) {
        const n = resolve(shape), e = table[n];
        return size < e.minSize || (!allowThin && size < thinMinSize && isThin(n)) ? e.small : n;
    }
}
