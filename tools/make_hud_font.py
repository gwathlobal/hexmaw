#!/usr/bin/env python3
"""Draw the HUD's bitmap font from Jersey 15, the menus' typeface.

    tools/make_hud_font.py data/fonts/Jersey15.ttf data/fonts/hud-font

Jersey 15 is drawn on a pixel grid: rendered at SIZE (27 px), every outline falls on whole
pixels and every advance is a whole number, so its strokes come out even. At any other size
(15, or 15 scaled up) some strokes round to one pixel and some to two. So the HUD draws it at
exactly this size, one screen pixel per font pixel (hud.lisp, `hud-text`).

Writes OUT.png, the printable ASCII glyphs (32 to 126) side by side in one row, each in a cell
ROWS tall: red the glyph, green its shadow one pixel right and down, so the shader draws both in
one pass. OUT.lisp gives the row height and, per glyph, its cell's x, width and advance.
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

SIZE = 27
TOP, BOTTOM = 4, 25          # the rows any glyph's ink reaches at SIZE: "$" and "[" to "g"
FIRST, LAST = 32, 126


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("font", help="the TTF")
    ap.add_argument("out", help="output path without extension")
    args = ap.parse_args()
    font = ImageFont.truetype(args.font, SIZE)
    rows = BOTTOM - TOP + 1 + 1             # the ink and the shadow's extra row
    cells = []
    for code in range(FIRST, LAST + 1):
        ch = chr(code)
        advance = int(font.getlength(ch))
        box = font.getbbox(ch)
        assert box[1] >= TOP and box[3] <= BOTTOM + 1, f"{ch!r} reaches outside rows {TOP}-{BOTTOM}"
        assert box[0] >= 0, f"{ch!r} starts left of its origin"
        width = max(advance, box[2]) + 1     # room for the shadow
        im = Image.new("L", (width + 2, SIZE + 4), 0)
        d = ImageDraw.Draw(im)
        d.fontmode = "1"
        d.text((0, 0), ch, font=font, fill=255)
        glyph = np.asarray(im)[TOP:TOP + rows, :width] > 127
        shadow = np.zeros_like(glyph)
        shadow[1:, 1:] = glyph[:-1, :-1]
        cells.append((ch, glyph, shadow, advance))
    total = sum(g.shape[1] for _, g, _, _ in cells)
    out = np.zeros((rows, total, 4), dtype=np.uint8)
    index, x = [], 0
    for ch, glyph, shadow, advance in cells:
        w = glyph.shape[1]
        out[:, x:x + w, 0] = glyph * 255
        out[:, x:x + w, 1] = shadow * 255
        out[:, x:x + w, 3] = (glyph | shadow) * 255
        index.append((x, w, advance))
        x += w
    out_path = Path(args.out)
    Image.fromarray(out, "RGBA").save(out_path.with_suffix(".png"))
    with open(out_path.with_suffix(".lisp"), "w") as f:
        f.write(";;; Written by tools/make_hud_font.py from %s at %d px; do not edit.\n" % (Path(args.font).name, SIZE))
        f.write("(:image \"%s\" :height %d :first %d\n :glyphs #(" % (out_path.with_suffix(".png").name, rows, FIRST))
        f.write("\n   ".join(" ".join("(%d %d %d)" % g for g in index[i:i + 10]) for i in range(0, len(index), 10)))
        f.write("))\n")
    print(out_path.with_suffix(".png"), total, "x", rows)


if __name__ == "__main__":
    main()
