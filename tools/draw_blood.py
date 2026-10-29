#!/usr/bin/env python3
"""Draw the blood particle sprites, one strip in the format tools/slice_frames.py
writes, so the game reads it like any other animation strip:

  tools/draw_blood.py data/sprites/blood/blood

writes blood.png (frames left to right, 2 px transparent gaps) and blood.lisp.
Every cell is SIZE art pixels square, at the monsters' density (64 px per metre), and
the point of impact is its middle. Frames, in order, each group smallest to largest:

  0-3    flying drops, in the four drop sizes
  4-27   round splats on a floor or wall, three variants of eight sizes: drop N leaves
         size N, and sizes 4 to 7 are puddles that only drops landing on a splat grow
         it into. Every size of a variant has the same outline, so a pool spreads.
  28-31  streaks, a fast drop's smear on the floor, running toward image right
  32-35  drips on a wall, a splat whose blood runs toward image bottom

ROUND_RADII must match *SPLAT-RADII* in src/gore.lisp.

Shapes are drawn pixel by pixel from fixed seeds, so a rerun gives the same strip.
"""

import math
import random
import sys
from pathlib import Path

from PIL import Image

SIZE = 32
GAP = 2
DROP_RADII = (0.8, 1.3, 1.9, 2.6)
# Radius in art pixels and flecks of each round splat size; the first four are the
# splats drops leave, and the streak and drip sizes too.
ROUND_RADII = ((2.1, 2), (2.8, 3), (3.6, 4), (4.6, 5), (6.0, 5), (7.5, 5), (9.0, 4), (10.5, 4))
SPLAT_RADII = ROUND_RADII[:4]

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


def bumps(rng):
    return [rng.uniform(0.75, 1.15) for _ in range(7)]


def pool(px, cx, cy, r, bumps):
    """A lumpy disc of radius about R at CX CY, its radius wobbling with the angle by BUMPS."""
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            a = (math.atan2(dy, dx) / (2 * math.pi) + 0.5) * len(bumps)
            i = int(a) % len(bumps)
            t = a - int(a)
            k = bumps[i] * (1 - t) + bumps[(i + 1) % len(bumps)] * t
            if math.hypot(dx, dy) <= r * k:
                px[(x, y)] = MID


def fleck(px, x, y, tx, ty):
    """A fleck at X Y with a darker pixel of trail at TX TY."""
    x, y, tx, ty = int(x), int(y), int(tx), int(ty)
    if 0 <= x < SIZE and 0 <= y < SIZE:
        px[(x, y)] = MID
        if 0 <= tx < SIZE and 0 <= ty < SIZE:
            px.setdefault((tx, ty), DARK)


def finish(px, cx, cy, r):
    """A dark rim where the blood meets the surface, a brighter wet patch up and left of CX CY."""
    for (x, y) in list(px):
        edge = any((x + dx, y + dy) not in px for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)))
        if edge and px[(x, y)] == MID:
            px[(x, y)] = DARK
    # A puddle's wet patch is a small glint; a big one would make it look round, not flat.
    spot, off = (r * 0.35, r * 0.25) if r < 6 else (r * 0.16, r * 0.4)
    for (x, y) in list(px):
        if math.hypot(x + 0.5 - (cx - off), y + 0.5 - (cy - off)) < spot and px[(x, y)] == MID:
            px[(x, y)] = BRIGHT
    return px


def splat(shape, flecks, r, satellites):
    """A ragged pool of radius about R, outlined by SHAPE (BUMPS), with SATELLITES of
    FLECKS (angle, and how far out from 0 to 1) thrown out around it."""
    px = {}
    c = SIZE / 2
    pool(px, c, c, r, shape)
    if r >= 6:
        # A puddle spreads unevenly: lobes out along the variant's first fleck angles.
        for a, f in flecks[:3]:
            pool(px, c + math.cos(a) * r * 0.95, c + math.sin(a) * r * 0.95, r * (0.32 + 0.22 * f), shape)
    for a, f in flecks[:satellites]:
        lo, hi = r + 1.2, min(c - 0.6, r + 3.5)
        d = lo + f * max(0, hi - lo)
        fleck(px, c + math.cos(a) * d, c + math.sin(a) * d,
              c + math.cos(a) * (d - 1), c + math.sin(a) * (d - 1))
    return finish(px, c, c, r)


def streak(rng, r, satellites):
    """A drop that hit moving right: a pool a little behind the middle, a tail thinning
    out ahead of it, and flecks thrown further on."""
    px = {}
    c = SIZE / 2
    pool(px, c - r * 0.4, c, r * 0.85, bumps(rng))
    length = r * 2.0 + 1.5
    steps = int(length * 2)
    for n in range(steps + 1):
        t = n / steps
        x = c + t * length
        w = r * 0.65 * (1 - t) ** 1.2 + 0.3
        wobble = math.sin(t * 5 + r) * 0.4
        for y in range(SIZE):
            if abs(y + 0.5 - (c + wobble)) <= w and 0 <= int(x) < SIZE:
                px[(int(x), y)] = MID
    for _ in range(satellites):
        d = rng.uniform(length + 1, min(c - 0.6, length + 4))
        y = c + rng.uniform(-r, r) * 0.8
        fleck(px, c + d, y, c + d - 1, y)
    return finish(px, c - r * 0.4, c, r)


def drip(rng, r, satellites):
    """A splat on a wall with blood running down from it, toward image bottom: one long
    run ending in a bead, and on the biggest a short second run beside it."""
    px = {}
    c = SIZE / 2
    pool(px, c, c, r * 0.9, bumps(rng))
    x = int(c + rng.uniform(-0.3, 0.3) * r)
    top = int(c)
    end = min(SIZE - 2, top + int(rng.uniform(1.6, 2.4) * r + 2))
    for y in range(top, end):
        px[(x, y)] = MID
        if r > 4 and y < top + (end - top) * 0.5:
            px[(x + 1, y)] = MID
    px[(x, end)] = MID
    px[(x + 1, end)] = MID
    px[(x, end - 1)] = MID
    if r > 4:
        x2 = x + rng.choice((-1, 1)) * max(2, int(r * 0.6))
        for y in range(top, top + int(rng.uniform(0.6, 1.0) * r)):
            px[(x2, y)] = MID
    for _ in range(max(0, satellites - 2)):
        a = rng.uniform(math.pi, 2 * math.pi)
        d = rng.uniform(r + 1.2, min(c - 0.6, r + 3.0))
        fleck(px, c + math.cos(a) * d, c + math.sin(a) * d,
              c + math.cos(a) * (d - 1), c + math.sin(a) * (d - 1))
    return finish(px, c, c, r)


def frames():
    drops = [drop(r) for r in DROP_RADII]
    rounds = []
    for seed in (7, 19, 31):
        rng = random.Random(seed)
        shape = bumps(rng)
        flecks = [(rng.uniform(0, 2 * math.pi), rng.random()) for _ in range(5)]
        rounds += [splat(shape, flecks, r, n) for r, n in ROUND_RADII]
    rng = random.Random(43)
    streaks = [streak(rng, r, n) for r, n in SPLAT_RADII]
    rng = random.Random(57)
    drips = [drip(rng, r, n) for r, n in SPLAT_RADII]
    return drops + rounds + streaks + drips


def main():
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    cells = frames()
    sheet = Image.new("RGBA", (len(cells) * SIZE + (len(cells) - 1) * GAP, SIZE), (0, 0, 0, 0))
    for i, px in enumerate(cells):
        for (x, y), colour in px.items():
            if 0 <= x < SIZE and 0 <= y < SIZE:
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
