#!/usr/bin/env python3
"""Draw the riftwalker's call sign, what its call lays on the floor where the ally will step
out, as a strip in the format tools/slice_frames.py writes (frames left to right, 2 px
transparent gaps, plus a .lisp index):

  tools/draw_rift_sign.py data/sprites/rift

writes sign.png/.lisp there.

sign: a ring in pale silver-blue with a jagged diamond rift torn open in the middle, dark
inside, and cracks running out from its points to the ring, seen from above, at the monsters'
density (64 px per metre) for a sign of RADIUS metres. Frames 0 to 7 draw it in (the ring
traced round, then the cracks running in, then the rift opening); frames 8 to 11 are it whole,
pulsing, a loop.

The game draws it alpha-tested (no translucency).
"""

import argparse
import math
import random
from pathlib import Path

from PIL import Image

from draw_grave_circle import arc, line, plot

PPM = 64
RADIUS = 0.9
GAP = 2
CRACKS = 4

DARK = (16, 20, 52, 255)
MID = (70, 96, 190, 255)
BRIGHT = (150, 190, 255, 255)
WHITE = (226, 240, 255, 255)
VOID = (6, 6, 18, 255)


def write_strip(out, name, frames):
    w, h = frames[0].size
    strip = Image.new("RGBA", (len(frames) * w + (len(frames) - 1) * GAP, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * (w + GAP), 0))
    strip.save(out / f"{name}.png")
    (out / f"{name}.lisp").write_text(
        f";;; Written by tools/draw_rift_sign.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n'
        f" :frames {len(frames)} :radius {RADIUS})\n")


def jagged(a, b, rnd, steps=5, wobble=5.0):
    """Points from A to B, each but the ends knocked aside at random: a crack's path."""
    (x0, y0), (x1, y1) = a, b
    dx, dy = x1 - x0, y1 - y0
    length = math.hypot(dx, dy) or 1.0
    nx, ny = -dy / length, dx / length
    points = [a]
    for i in range(1, steps):
        t = i / steps
        o = rnd.uniform(-wobble, wobble)
        points.append((x0 + dx * t + nx * o, y0 + dy * t + ny * o))
    points.append(b)
    return points


def polyline(img, points, c, width, upto=1.0):
    total = len(points) - 1
    reach = upto * total
    for k in range(total):
        if reach <= k:
            break
        line(img, points[k], points[k + 1], c, width, min(1.0, reach - k))


def sign_frame(stage, pulse):
    """STAGE 0..1 of the draw-in (1 whole); PULSE 0..3 for the brightness of a whole one."""
    rnd = random.Random(7)
    size = int(2 * RADIUS * PPM) + 24
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    outer = RADIUS * PPM
    # The rift: a diamond, taller than wide, its sides jagged.
    half_w, half_h = 0.22 * outer, 0.42 * outer
    tips = [(c, c - half_h), (c + half_w, c), (c, c + half_h), (c - half_w, c)]
    rift = []
    for k in range(4):
        rift += jagged(tips[k], tips[(k + 1) % 4], rnd, 4, 3.0)[:-1]
    # Cracks from the rift's tips out to the ring, then a few short forks.
    cracks = [jagged(tips[k], (c + (outer - 2) * math.cos(-math.pi / 2 + k * math.pi / 2),
                               c + (outer - 2) * math.sin(-math.pi / 2 + k * math.pi / 2)), rnd, 6, 6.0)
              for k in range(CRACKS)]
    forks = []
    for points in cracks:
        a = points[3]
        angle = rnd.uniform(0, 2 * math.pi)
        forks.append(jagged(a, (a[0] + 12 * math.cos(angle), a[1] + 12 * math.sin(angle)), rnd, 3, 3.0))
    bright = [BRIGHT, WHITE, BRIGHT, MID][pulse] if stage >= 1 else BRIGHT
    glow = [MID, BRIGHT, MID, MID][pulse] if stage >= 1 else MID

    def part(lo, hi):
        return max(0.0, min(1.0, (stage - lo) / (hi - lo)))

    for col, w in ((DARK, 7), (glow, 4), (bright, 2)):
        if part(0, 0.35) > 0:
            arc(img, c, c, outer, col, w, part(0, 0.35))
        # The cracks run in from the ring toward the middle.
        if part(0.35, 0.7) > 0:
            for points in cracks:
                polyline(img, list(reversed(points)), col, w * 0.7, part(0.35, 0.7))
        if part(0.6, 0.8) > 0:
            for points in forks:
                polyline(img, points, col, w * 0.5, part(0.6, 0.8))
    # The rift tears open last: its edge, then the void inside it.
    opening = part(0.7, 1.0)
    if opening > 0:
        s = 0.3 + 0.7 * opening
        edge = [(c + (x - c) * s, c + (y - c) * s) for x, y in rift]
        for y in range(size):
            for x in range(size):
                # Inside the diamond the edge points make, by the diamond's own measure.
                if abs(x - c) / (half_w * s) + abs(y - c) / (half_h * s) < 0.82:
                    img.putpixel((x, y), VOID)
        for col, w in ((DARK, 6), (glow, 3.5), (bright if pulse != 1 else WHITE, 1.8)):
            polyline(img, edge + [edge[0]], col, w)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="directory to write the sign into")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frames = [sign_frame((i + 1) / 8, 0) for i in range(8)] + [sign_frame(1.0, p) for p in range(4)]
    write_strip(out, "sign", frames)


if __name__ == "__main__":
    main()
