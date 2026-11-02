#!/usr/bin/env python3
"""Draw the boss's summoning sigil, what Summon lays on the floor where each minion will
rise, as a strip in the format tools/slice_frames.py writes (frames left to right, 2 px
transparent gaps, plus a .lisp index):

  tools/draw_summon_sigil.py data/sprites/summon

writes sigil.png/.lisp there. (The flame that bursts up from it is a shader, the aurora
in spells.lisp.)

sigil: a double ring in embers with an inverted triangle inside, a bead on each of its
points, and tongues of flame round the outside, seen from above, at the monsters' density
(64 px per metre) for a sigil of RADIUS metres. Frames 0 to 7 draw it in (the outer ring
traced round, then the inner ring, then the triangle's three sides, then the beads and
tongues); frames 8 to 11 are it whole, pulsing, a loop.

The game draws it alpha-tested (no translucency).
"""

import argparse
import math
from pathlib import Path

from PIL import Image

from draw_grave_circle import arc, line, plot

PPM = 64
RADIUS = 0.9
GAP = 2
TONGUES = 9

DARK = (58, 12, 4, 255)
MID = (186, 58, 14, 255)
BRIGHT = (255, 146, 36, 255)
WHITE = (255, 228, 160, 255)


def write_strip(out, name, frames):
    w, h = frames[0].size
    strip = Image.new("RGBA", (len(frames) * w + (len(frames) - 1) * GAP, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * (w + GAP), 0))
    strip.save(out / f"{name}.png")
    (out / f"{name}.lisp").write_text(
        f";;; Written by tools/draw_summon_sigil.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n'
        f" :frames {len(frames)} :radius {RADIUS})\n")


def sigil_frame(stage, pulse):
    """STAGE 0..1 of the draw-in (1 whole); PULSE 0..3 for the brightness of a whole one."""
    size = int(2 * RADIUS * PPM) + 24
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    outer = RADIUS * PPM
    inner = outer - 12
    tri = inner - 2
    # Inverted: one point toward the bottom of the picture, two at the top.
    points = [(c + tri * math.cos(math.pi / 2 + k * 2 * math.pi / 3),
               c + tri * math.sin(math.pi / 2 + k * 2 * math.pi / 3)) for k in range(4)]
    bright = [BRIGHT, WHITE, BRIGHT, MID][pulse] if stage >= 1 else BRIGHT
    glow = [MID, BRIGHT, MID, MID][pulse] if stage >= 1 else MID

    def part(lo, hi):
        return max(0.0, min(1.0, (stage - lo) / (hi - lo)))

    for col, w in ((DARK, 7), (glow, 4), (bright, 2)):
        if part(0, 0.3) > 0:
            arc(img, c, c, outer, col, w, part(0, 0.3))
        if part(0.3, 0.45) > 0:
            arc(img, c, c, inner, col, w * 0.8, part(0.3, 0.45))
        sides = part(0.45, 0.8) * 3
        for k in range(3):
            if sides > k:
                line(img, points[k], points[k + 1], col, w * 0.8, min(1.0, sides - k))
    if part(0.8, 1.0) > 0:
        k_part = part(0.8, 1.0)
        # A bead on each point of the triangle.
        for (x, y) in points[:3]:
            for col, w in ((DARK, 9), (glow, 6), (bright, 3)):
                plot(img, x, y, col, w)
        # Tongues of flame licking out from the outer ring, each a short curved stroke.
        for k in range(int(TONGUES * k_part)):
            a = -math.pi / 2 + 2 * math.pi * (k + 0.5) / TONGUES
            for col, w in ((DARK, 5), (glow, 3), (bright if (k + pulse) % 3 else WHITE, 1.5)):
                for i in range(9):
                    t = i / 8
                    r = outer + 3 + 9 * t
                    bend = a + 0.12 * t * t
                    plot(img, c + r * math.cos(bend), c + r * math.sin(bend), col, w * (1.0 - 0.6 * t))
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="directory to write the sigil into")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frames = [sigil_frame((i + 1) / 8, 0) for i in range(8)] + [sigil_frame(1.0, p) for p in range(4)]
    write_strip(out, "sigil", frames)


if __name__ == "__main__":
    main()
