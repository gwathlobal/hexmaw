#!/usr/bin/env python3
"""Draw the acolyte's firestorm sign, what it lays on the floor under the player before the
storm comes down, as a strip in the format tools/slice_frames.py writes (frames left to right,
2 px transparent gaps, plus a .lisp index):

  tools/draw_fire_sign.py data/sprites/firestorm
  tools/restyle.py --house data/sprites/firestorm/sign.png

writes sign.png/.lisp there. (The fire round it is a shader, the aurora in spells.lisp, and
the cinders falling on it are the cinder's own sprite, acolyte.lisp.)

sign: a sun wheel in embers, seen from above, at the monsters' density (64 px per metre) for
a sign of RADIUS metres: a double ring, eight flame rays curling out from a small ring in the
middle to the inner ring, and tongues of flame licking out round the outside. Frames 0 to 7
draw it in (the outer ring traced round, then the inner ring, then the rays one after
another, then the middle and the tongues); frames 8 to 11 are it whole, pulsing, a loop.

The game draws it alpha-tested (no translucency).
"""

import argparse
import math
from pathlib import Path

from PIL import Image

from draw_grave_circle import arc, plot

PPM = 64
RADIUS = 2.5
GAP = 2
RAYS = 8
TONGUES = 16

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
        f";;; Written by tools/draw_fire_sign.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n'
        f" :frames {len(frames)} :radius {RADIUS})\n")


def ray(img, c, a, r0, r1, col, width, upto=1.0):
    """A flame ray from radius R0 to R1 at angle A round C, curling as it goes and thinning to
    a point, drawn as far as UPTO of its length."""
    n = int((r1 - r0) * 2)
    for i in range(int(n * upto) + 1):
        t = i / n
        r = r0 + (r1 - r0) * t
        # Curls one way, then flicks back at the tip, as a flame bends.
        bend = a + 0.22 * math.sin(math.pi * t) - 0.08 * t * t
        plot(img, c + r * math.cos(bend), c + r * math.sin(bend), col, max(1.0, width * (1.0 - 0.75 * t)))


def sign_frame(stage, pulse):
    """STAGE 0..1 of the draw-in (1 whole); PULSE 0..3 for the brightness of a whole one."""
    size = int(2 * RADIUS * PPM) + 28
    img = Image.new("RGBA", (size, size), (0, 0, 0, 0))
    c = size / 2
    outer = RADIUS * PPM
    inner = outer - 14
    core = 22
    bright = [BRIGHT, WHITE, BRIGHT, MID][pulse] if stage >= 1 else BRIGHT
    glow = [MID, BRIGHT, MID, MID][pulse] if stage >= 1 else MID

    def part(lo, hi):
        return max(0.0, min(1.0, (stage - lo) / (hi - lo)))

    for col, w in ((DARK, 7), (glow, 4), (bright, 2)):
        if part(0, 0.3) > 0:
            arc(img, c, c, outer, col, w, part(0, 0.3))
        if part(0.3, 0.45) > 0:
            arc(img, c, c, inner, col, w * 0.8, part(0.3, 0.45))
        rays = part(0.45, 0.85) * RAYS
        for k in range(RAYS):
            if rays > k:
                a = -math.pi / 2 + 2 * math.pi * k / RAYS
                ray(img, c, a, core + 4, inner - 6, col, w * 2.2, min(1.0, rays - k))
    if part(0.85, 1.0) > 0:
        k_part = part(0.85, 1.0)
        for col, w in ((DARK, 7), (glow, 4), (bright, 2)):
            arc(img, c, c, core, col, w, k_part)
        # Tongues of flame licking out from the outer ring, each a short curved stroke.
        for k in range(int(TONGUES * k_part)):
            a = -math.pi / 2 + 2 * math.pi * (k + 0.5) / TONGUES
            for col, w in ((DARK, 5), (glow, 3), (bright if (k + pulse) % 4 else WHITE, 1.5)):
                for i in range(9):
                    t = i / 8
                    r = outer + 3 + 9 * t
                    bend = a + 0.1 * t * t
                    plot(img, c + r * math.cos(bend), c + r * math.sin(bend), col, w * (1.0 - 0.6 * t))
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
