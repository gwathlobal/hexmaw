#!/usr/bin/env python3
"""Draw the weapon slot icons for the HUD, one strip in the format tools/slice_frames.py
writes, so the game reads it like any other animation strip:

  tools/draw_weapon_icons.py data/sprites/icons/weapons

writes weapons.png (frames left to right, 2 px transparent gaps) and weapons.lisp.
Frames, in order: the sword, the fireball (the casting hands). Each is SIZE art pixels
square, drawn pixel by pixel in the palettes of the sword and bolt sprites, then
outlined in near-black so it reads on any background. The top-left corner of each icon
is left empty: the game draws the slot's key number there.
"""

import math
import sys
from pathlib import Path

from PIL import Image

SIZE = 20
GAP = 2

OUTLINE = (18, 12, 10, 255)


def sword():
    px = {}
    steel_light = (232, 232, 222, 255)
    steel_mid = (176, 178, 172, 255)
    steel_dark = (110, 112, 112, 255)
    gold = (226, 188, 70, 255)
    gold_dark = (150, 112, 30, 255)
    grip = (122, 66, 34, 255)
    grip_dark = (84, 42, 22, 255)
    # Blade: a diagonal band from the guard (bottom left) to the tip (top right),
    # lit along its middle and on its upper-left edge.
    for i in range(11):
        x, y = 8 + i, 11 - i
        px[(x, y)] = steel_light
        if i < 10:
            px[(x - 1, y)] = steel_mid
            px[(x + 1, y)] = steel_dark
    # Crossguard, across the blade.
    for k in range(-3, 4):
        px[(6 + k, 12 + k)] = gold
        px[(7 + k, 12 + k)] = gold_dark
    px[(7, 12)] = gold
    # Grip and pommel.
    for x, y in ((5, 14), (4, 15)):
        px[(x, y)] = grip
        px[(x + 1, y)] = grip_dark
    for x, y in ((2, 16), (3, 16), (2, 17), (3, 17)):
        px[(x, y)] = gold
    px[(3, 17)] = gold_dark
    return px


def fireball():
    px = {}
    cx, cy = 10.5, 10.0
    for y in range(SIZE):
        for x in range(SIZE):
            dx, dy = x + 0.5 - cx, y + 0.5 - cy
            r = math.hypot(dx, dy)
            theta = math.atan2(dy, dx)
            # The swirl of the bolt sprite: the rim wobbles with angle, twisted by radius.
            rim = 7.2 + 0.9 * math.sin(3 * theta + 0.7 * r)
            if r < 2.3:
                c = (255, 250, 220)
            elif r < 3.8:
                c = (255, 222, 110)
            elif r < 5.3:
                c = (252, 160, 40)
            elif r < rim - 0.8:
                c = (232, 92, 22)
            elif r < rim:
                c = (178, 40, 14)
            else:
                continue
            px[(x, y)] = c + (255,)
    # Embers flung off the swirl.
    for x, y in ((18, 4), (2, 15), (17, 17)):
        px[(x, y)] = (255, 190, 70, 255)
    return px


def outlined(px):
    out = dict(px)
    for (x, y) in px:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in px and 0 <= nx < SIZE and 0 <= ny < SIZE:
                out[(nx, ny)] = OUTLINE
    return out


def main():
    out = Path(sys.argv[1])
    out.parent.mkdir(parents=True, exist_ok=True)
    icons = [sword(), fireball()]
    strip = Image.new("RGBA", (len(icons) * SIZE + (len(icons) - 1) * GAP, SIZE), (0, 0, 0, 0))
    for i, icon in enumerate(icons):
        for (x, y), c in outlined(icon).items():
            if 0 <= x < SIZE and 0 <= y < SIZE:
                strip.putpixel((i * (SIZE + GAP) + x, y), c)
    strip.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        f";;; Written by tools/draw_weapon_icons.py; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {SIZE} :cell-height {SIZE} :gap {GAP}\n"
        f" :frames {len(icons)})\n")


if __name__ == "__main__":
    main()
