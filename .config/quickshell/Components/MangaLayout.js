.pragma library

// Which pages are shown together. Pages are { w, h } (0 when unknown); a view is a list of page indexes in
// reading order (the reader puts the first on the right for right-to-left books).

function wide(p) {
    return !!p && p.w > 0 && p.h > 0 && p.w / p.h > 1.1;
}

// mode "spread": the cover alone, then pairs; a wide page (already a spread) is alone and breaks the pairing.
// `offset` 1 shifts the pairing by one page, for books whose first page after the cover is a right-hand page.
// Any other mode: one page per view.
function views(pages, mode, offset) {
    const n = pages.length, out = [];
    if (mode !== "spread") {
        for (let i = 0; i < n; i++)
            out.push([i]);
        return out;
    }
    const start = 1 + (offset ? 1 : 0);
    for (let i = 0; i < Math.min(start, n); i++)
        out.push([i]);
    let i = start;
    while (i < n) {
        if (wide(pages[i]) || i + 1 >= n || wide(pages[i + 1])) {
            out.push([i]);
            i += 1;
        } else {
            out.push([i, i + 1]);
            i += 2;
        }
    }
    return out;
}

function viewOf(views, page) {
    for (let v = 0; v < views.length; v++)
        if (views[v].indexOf(page) >= 0)
            return v;
    return 0;
}

function ratio(p) {
    return p && p.w > 0 && p.h > 0 ? p.w / p.h : 0.7;
}

// the size each page of a view is drawn at: one common height that fits the area
function fit(pages, view, areaW, areaH, gap) {
    const ars = view.map(i => ratio(pages[i]));
    const sum = ars.reduce((a, b) => a + b, 0);
    if (sum <= 0)
        return { h: 0, ws: [] };
    const h = Math.max(1, Math.min(areaH, (areaW - gap * (view.length - 1)) / sum));
    return { h: h, ws: ars.map(a => a * h) };
}

// cumulative tops of a column of pages at a width: offs[i] .. offs[i + 1]
function offsets(pages, width) {
    const a = [0];
    let y = 0;
    for (const p of pages) {
        y += p && p.w > 0 && p.h > 0 ? width * p.h / p.w : width * 1.42;
        a.push(y);
    }
    return a;
}

function pageAt(offs, y) {
    let lo = 0, hi = offs.length - 2;
    if (hi < 0)
        return 0;
    while (lo < hi) {
        const mid = (lo + hi + 1) >> 1;
        if (offs[mid] <= y)
            lo = mid;
        else
            hi = mid - 1;
    }
    return lo;
}
