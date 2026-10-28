#!/usr/bin/env python3
"""Draw the blood particle sprites, one strip in the format tools/slice_frames.py
writes, so the game reads it like any other animation strip:

  tools/draw_blood.py data/sprites/blood/blood

writes blood.png (frames left to right, 2 px transparent gaps) and blood.lisp.
Every cell is SIZE art pixels square, at the monsters' density (64 px per metre), and
the shape sits in its middle. Frames, in order:

  0-3  flying drops, smallest to largest
  4-7  splats on a floor or wall, the splat each drop leaves (drop N makes splat 4+N)

Shapes are drawn pixel by pixel from a fixed seed, so a rerun gives the same strip.
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image

SIZE = 16
GAP = 2

DARK = (74, 4, 8, 255)
MID = (124, 10, 14, 255)
BRIGHT = (168, 20, 20, 255)


def blob(px, cx, cy, r, colour):
    for y in range(SIZE):
        for x in range(SIZE):
            if (x + 0.5 - cx) ** 2 + (y + 0.5 - cy) ** 2 <= r * r:
                px[(x, y)] = colour


def drop(r):
    """A round drop of radius R, darker below, with a glint at its upper left. Drops
    are lit full on, unlike splats, which take the angle to the light, so they stay dark."""
    px = {}
    c = SIZE / 2
    blob(px, c, c, r, MID)
    for (x, y) in list(px):
        if y + 0.5 > c + r * 0.35:
            px[(x, y)] = DARK
    top = min(px, key=lambda p: (p[1] + p[0], p))
    px[top] = BRIGHT
    if r < 1.2:
        px = {p: MID for p in px}
    return px


def splat(rng, r, satellites):
    """A ragged pool of radius about R with SATELLITES flecks thrown out around it."""
    px = {}
    c = SIZE / 2
    # The pool: a lumpy disc, its radius wobbling with the angle.
    bumps = [rng.uniform(0.75, 1.15) for _ in range(7)]
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x + 0.5 - c, y + 0.5 - c
            a = (math.atan2(dy, dx) / (2 * math.pi) + 0.5) * len(bumps)
            i = int(a) % len(bumps)
            t = a - int(a)
            k = bumps[i] * (1 - t) + bumps[(i + 1) % len(bumps)] * t
            if math.hypot(dx, dy) <= r * k:
                px[(x, y)] = MID
    # Flecks: small dots out past the edge, each with a pixel's trail toward the middle.
    for _ in range(satellites):
        a = rng.uniform(0, 2 * math.pi)
        d = rng.uniform(r + 1.2, min(c - 0.6, r + 3.5))
        x, y = int(c + math.cos(a) * d), int(c + math.sin(a) * d)
        if 0 <= x < SIZE and 0 <= y < SIZE:
            px[(x, y)] = MID
            tx, ty = int(c + math.cos(a) * (d - 1)), int(c + math.sin(a) * (d - 1))
            px.setdefault((tx, ty), DARK)
    # Dark rim where the pool meets the floor, a brighter wet patch inside.
    for (x, y) in list(px):
        edge = any((x + dx, y + dy) not in px for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge and px[(x, y)] == MID:
            px[(x, y)] = DARK
    for (x, y) in list(px):
        if math.hypot(x + 0.5 - (c - r * 0.25), y + 0.5 - (c - r * 0.25)) < r * 0.35 and px[(x, y)] == MID:
            px[(x, y)] = BRIGHT
    return px


def frames():
    rng = random.Random(7)
    drops = [drop(r) for r in (0.8, 1.3, 1.9, 2.6)]
    splats = [splat(rng, r, n) for r, n in ((2.1, 2), (2.8, 3), (3.6, 4), (4.6, 5))]
    return drops + splats


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    cells = frames()
    sheet = Image.new("RGBA", (len(cells) * SIZE + (len(cells) - 1) * GAP, SIZE), (0, 0, 0, 0))
    for i, px in enumerate(cells):
        for (x, y), colour in px.items():
            sheet.putpixel((i * (SIZE + GAP) + x, y), colour)
    sheet.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        ";;; Written by tools/draw_blood.py; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {SIZE} :cell-height {SIZE} :gap {GAP}\n"
        f" :frames {len(cells)})\n")
    print(f"wrote {out.with_suffix('.png')} ({len(cells)} frames)")


if __name__ == "__main__":
    main()
