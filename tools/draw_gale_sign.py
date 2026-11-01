#!/usr/bin/env python3
"""Draw the gale wraith's sign, what it lays on the floor where its tornado will form, as a
strip in the format tools/slice_frames.py writes (frames left to right, 2 px transparent
gaps, plus a .lisp index):

  tools/draw_gale_sign.py data/sprites/gale

writes sign.png/.lisp there.

sign: a spiral of three arms of wind in a ring, seen from above, at the monsters' density
(64 px per metre) for a sign of RADIUS metres. Frames 0 to 7 draw it in (the ring traced
round, then the arms growing inward from it); frames 8 to 11 are it whole, its arms turned
a further 30 degrees each frame, a loop that seems to spin.

The game draws it alpha-tested (no translucency).
"""

import argparse
import math
from pathlib import Path

from PIL import Image

from draw_grave_circle import arc, plot

PPM = 64
RADIUS = 2.0
GAP = 2
ARMS = 3

DARK = (34, 18, 64, 255)
MID = (104, 66, 186, 255)
BRIGHT = (186, 148, 255, 255)
WHITE = (235, 226, 255, 255)


def write_strip(out, name, frames):
    w, h = frames[0].size
    strip = Image.new("RGBA", (len(frames) * w + (len(frames) - 1) * GAP, h), (0, 0, 0, 0))
    for i, f in enumerate(frames):
        strip.paste(f, (i * (w + GAP), 0))
    strip.save(out / f"{name}.png")
    (out / f"{name}.lisp").write_text(
        f";;; Written by tools/draw_gale_sign.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n'
        f" :frames {len(frames)} :radius {RADIUS})\n")


def arm(img, c, outer, inner, turn, col, width, upto):
    """An arm winding in from the ring to INNER, a half turn on the way, UPTO of it drawn."""
    n = int((outer - inner) * 6)
    for i in range(int(n * upto) + 1):
        t = i / n
        r = outer + (inner - outer) * t
        a = turn + t * math.pi
        plot(img, c + r * math.cos(a), c + r * math.sin(a), col, width * (1.0 - 0.45 * t))


def sign_frame(stage, step):
    """STAGE 0..1 of the draw-in (1 whole); STEP 0..3 of the spin of a whole one."""
    size = int(2 * RADIUS * PPM) + 8
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    outer = RADIUS * PPM
    inner = 0.16 * outer

    def part(lo, hi):
        return max(0.0, min(1.0, (stage - lo) / (hi - lo)))

    turn = step * math.pi / 6
    for col, w in ((DARK, 9), (MID, 5.5), (BRIGHT, 2.5)):
        if part(0, 0.3) > 0:
            arc(img, c, c, outer, col, w, part(0, 0.3))
        if part(0.3, 1.0) > 0:
            for k in range(ARMS):
                arm(img, c, outer - 2, inner, turn + k * 2 * math.pi / ARMS, col, w, part(0.3, 1.0))
    if stage >= 1:
        # The eye of it.
        arc(img, c, c, inner * 0.5, WHITE if step % 2 else BRIGHT, 2.5)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="directory to write the sign into")
    args = ap.parse_args()
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    frames = [sign_frame((i + 1) / 8, 0) for i in range(8)] + [sign_frame(1.0, s) for s in range(4)]
    write_strip(out, "sign", frames)


if __name__ == "__main__":
    main()
