#!/usr/bin/env python3
"""Draw the necromancer's grave circle, the pentagram it lays on the floor, as a strip
in the format tools/slice_frames.py writes (frames left to right, 2 px transparent
gaps, plus a .lisp index):

  tools/draw_grave_circle.py data/sprites/grave

writes circle.png/.lisp there. (The aurora round it is a shader, in spells.lisp.)

circle: a pentagram in a double ring with glyphs between the rings, seen from above,
at the monsters' density (64 px per metre) for a circle of RADIUS metres. Frames 0 to 7
draw it in (the outer ring traced round, then the inner ring, then the star's five
lines one after another, then the glyphs); frames 8 to 11 are it whole, pulsing, a loop.

The game draws it alpha-tested (no translucency). Fixed seeds, so a rerun gives the
same strip.
"""

import argparse
import math
import random
from pathlib import Path

from PIL import Image

PPM = 64
RADIUS = 2.5
GAP = 2

DARK = (18, 60, 28, 255)
MID = (60, 170, 60, 255)
BRIGHT = (150, 255, 120, 255)
WHITE = (225, 255, 210, 255)


def write_strip(out, name, frames, note=""):
    w, h = frames[0].size
    strip = Image.new("RGBA", (len(frames) * w + (len(frames) - 1) * GAP, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * (w + GAP), 0))
    strip.save(out / f"{name}.png")
    (out / f"{name}.lisp").write_text(
        f";;; Written by tools/draw_grave_circle.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n :frames {len(frames)}{note})\n')


def plot(img, x, y, c, width=1):
    r = width / 2
    for dx in range(-int(r) - 1, int(r) + 2):
        for dy in range(-int(r) - 1, int(r) + 2):
            if dx * dx + dy * dy <= r * r + 0.25:
                px, py = int(round(x + dx)), int(round(y + dy))
                if 0 <= px < img.width and 0 <= py < img.height:
                    img.putpixel((px, py), c)


def line(img, a, b, c, width, upto=1.0):
    (x0, y0), (x1, y1) = a, b
    n = max(1, int(math.hypot(x1 - x0, y1 - y0) * 2))
    for i in range(int(n * upto) + 1):
        t = i / n
        plot(img, x0 + (x1 - x0) * t, y0 + (y1 - y0) * t, c, width)


def arc(img, cx, cy, r, c, width, upto=1.0, start=-math.pi / 2):
    n = int(2 * math.pi * r * 2)
    for i in range(int(n * upto) + 1):
        a = start + 2 * math.pi * i / n
        plot(img, cx + r * math.cos(a), cy + r * math.sin(a), c, width)


def glyph(img, cx, cy, k, c):
    """One of a few angular rune shapes, about 12 px across."""
    rnd = random.Random(k)
    pts = [(cx + rnd.randint(-6, 6), cy + rnd.randint(-6, 6)) for _ in range(3 + k % 2)]
    for a, b in zip(pts, pts[1:]):
        line(img, a, b, c, 2.2)


def circle_frame(stage, pulse):
    """STAGE 0..1 of the draw-in (1 whole); PULSE 0..3 for the brightness of a whole one."""
    size = int(2 * RADIUS * PPM) + 8
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    outer = RADIUS * PPM
    inner = outer - 22
    star = inner - 3
    points = [(c + star * math.cos(-math.pi / 2 + k * 4 * math.pi / 5),
               c + star * math.sin(-math.pi / 2 + k * 4 * math.pi / 5)) for k in range(6)]
    bright = [BRIGHT, WHITE, BRIGHT, MID][pulse] if stage >= 1 else BRIGHT
    glow = [MID, BRIGHT, MID, MID][pulse] if stage >= 1 else MID
    # Draw-in: outer ring 0-0.3, inner ring 0.3-0.45, star lines 0.45-0.9, glyphs 0.9-1.
    def part(lo, hi):
        return max(0.0, min(1.0, (stage - lo) / (hi - lo)))
    for layer, (col, w) in enumerate(((DARK, 8), (glow, 5), (bright, 2.5))):
        if part(0, 0.3) > 0:
            arc(img, c, c, outer, col, w, part(0, 0.3))
        if part(0.3, 0.45) > 0:
            arc(img, c, c, inner, col, w * 0.8, part(0.3, 0.45))
        lines = part(0.45, 0.9) * 5
        for k in range(5):
            if lines > k:
                line(img, points[k], points[k + 1], col, w * 0.8, min(1.0, lines - k))
    if part(0.9, 1.0) > 0:
        n = 15
        for k in range(int(n * part(0.9, 1.0))):
            a = -math.pi / 2 + 2 * math.pi * (k + 0.5) / n
            r = (outer + inner) / 2
            glyph(img, c + r * math.cos(a), c + r * math.sin(a), k, bright if (k + pulse) % 3 else WHITE)
    return img




def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="directory to write circle into")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frames = [circle_frame((i + 1) / 8, 0) for i in range(8)] + [circle_frame(1.0, p) for p in range(4)]
    write_strip(out, "circle", frames)


if __name__ == "__main__":
    main()
