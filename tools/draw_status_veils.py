#!/usr/bin/env python3
"""Draw the status veils (hud.lisp): what shows at the screen's edges while a lasting effect is on
the player, one strip of tiles in the format tools/slice_frames.py writes:

  tools/draw_status_veils.py data/sprites/veils

writes veils.png and veils.lisp. Each veil is two tiles of TILE HUD art pixels, resting and
flared (brighter, as when the effect acts), and the game repeats a tile along its part of the
screen's edge, fading inward in steps (STATUS-VEIL, hud.lisp). Frames, in order:

  0, 1  ward: a lattice of hexagons in ward gold, laid along the left and right edges;
  2, 3  blessing: warm white rays of light, laid in the four corners;
  4, 5  healing over time: green motes and small crosses, laid along the bottom edge and rising.

Each tile wraps (its left edge meets its right, its top its bottom), so the repeats join. Only
the lines are drawn; the rest is transparent. The colours go through the master palette.
"""

import math
import sys
from pathlib import Path

from PIL import Image

from pixelart import HOUSE_PALETTE, quantize_to_palette, read_palette

TILE = 32
GAP = 2

WARD = ((255, 236, 160), (226, 186, 90), (150, 110, 40))
BLESS = ((255, 250, 232), (250, 226, 170), (210, 170, 110))
HEAL = ((210, 255, 190), (110, 220, 100), (50, 140, 60))


def put(img, x, y, color):
    img.putpixel((x % TILE, y % TILE), color + (255,))


def ward(flare):
    """A honeycomb: the borders between the cells round a grid of centres 16 px apart, every other
    row shifted by 8, so the cells are hexagons and the tile wraps. A knot of light where three
    cells meet; flared, the lines are light too."""
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    light, mid, dark = WARD
    centres = [(x + (8 if row % 2 else 0), row * 16) for row in range(2) for x in range(0, TILE, 16)]

    def distances(px, py):
        ds = []
        for cx, cy in centres:
            for ox in (-TILE, 0, TILE):
                for oy in (-TILE, 0, TILE):
                    ds.append(math.hypot(px - cx - ox, (py - cy - oy) * 1.15))
        ds.sort()
        return ds

    for y in range(TILE):
        for x in range(TILE):
            d = distances(x + 0.5, y + 0.5)
            if d[1] - d[0] < 1.2:
                knot = d[2] - d[0] < 2.4
                put(img, x, y, light if (knot or flare) else mid)
            elif d[1] - d[0] < 2.2 and not flare:
                put(img, x, y, dark)
    return img


def bless(flare):
    """Rays: thin slanting strokes of warm light, falling from the upper left as the house's light
    does, with a few bright motes; the corners' veil stacks them in steps."""
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    light, mid, dark = BLESS
    for start, length in ((0, 12), (9, 7), (17, 14), (25, 9)):
        for i in range(length):
            put(img, start + i, i * 2, mid if i % 3 else light)
            put(img, start + i, i * 2 + 1, dark)
    for x, y in ((5, 20), (21, 6), (28, 27), (13, 29)):
        put(img, x, y, light)
        if flare:
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                put(img, x + dx, y + dy, mid)
    return img


def heal(flare):
    """Green motes and small crosses, scattered so they rise in no lines."""
    img = Image.new("RGBA", (TILE, TILE), (0, 0, 0, 0))
    light, mid, dark = HEAL
    crosses = ((6, 6), (22, 13), (11, 24), (27, 28))
    motes = ((16, 3), (3, 17), (19, 21), (29, 8), (8, 13))
    for cx, cy in crosses:
        arm = 2 if flare else 1
        for d in range(-arm, arm + 1):
            put(img, cx + d, cy, light if d == 0 else mid)
            put(img, cx, cy + d, light if d == 0 else mid)
        put(img, cx + 1, cy + 1, dark)
    for x, y in motes:
        put(img, x, y, light if flare else mid)
    return img


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.mkdir(parents=True, exist_ok=True)
    frames = [ward(False), ward(True), bless(False), bless(True), heal(False), heal(True)]
    palette = read_palette(HOUSE_PALETTE)
    strip = Image.new("RGBA", (len(frames) * (TILE + GAP), TILE), (0, 0, 0, 0))
    for i, frame in enumerate(frames):
        strip.paste(quantize_to_palette(frame, palette), (i * (TILE + GAP), 0))
    strip.save(out / "veils.png")
    (out / "veils.lisp").write_text(
        f"(:frames {len(frames)} :cell-width {TILE} :cell-height {TILE} :gap {GAP} "
        f":width {strip.width} :height {strip.height})\n")
    print(f"Wrote {out / 'veils.png'}: {len(frames)} tiles of {TILE} px.")


if __name__ == "__main__":
    main()
