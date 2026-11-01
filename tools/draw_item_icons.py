#!/usr/bin/env python3
"""Draw the item icons for the inventory and quickslot, one strip in the format
tools/slice_frames.py writes, so the game reads it like any other animation strip:

  tools/draw_item_icons.py data/sprites/icons/items

writes items.png (frames left to right, 2 px transparent gaps) and items.lisp. Frames, in
order: the health potion, the mana potion. Each is SIZE art pixels square, the weapon icons'
size, drawn pixel by pixel in the palette of the potion's pickup sprite, then outlined in
near-black so it reads on any background. The game draws a stack's count over the bottom-right
corner and the quickslot's key over the top-left, so the bottle keeps to the middle.
"""

import sys
from pathlib import Path

from PIL import Image

SIZE = 20
GAP = 2

OUTLINE = (18, 12, 10, 255)
GOLD = (226, 188, 70, 255)
GOLD_DARK = (150, 112, 30, 255)
GLASS = (176, 170, 160, 255)
GLASS_DARK = (110, 104, 100, 255)
SHINE = (255, 244, 236, 255)


def potion(light, mid, dark, deep):
    px = {}
    # The stopper, the band round the neck and the neck itself.
    for x in range(8, 12):
        px[(x, 2)] = GOLD
        px[(x, 3)] = GOLD_DARK
    px[(9, 2)] = (250, 226, 130, 255)
    for x in range(7, 13):
        px[(x, 4)] = GOLD
    px[(12, 4)] = GOLD_DARK
    for x in range(8, 12):
        px[(x, 5)] = GLASS
        px[(x, 6)] = GLASS
    px[(11, 5)] = GLASS_DARK
    px[(11, 6)] = GLASS_DARK
    # The belly: a disc of liquid, lit from the upper left and dark along its lower right.
    cx, cy, r = 9.5, 12.0, 6.6
    for y in range(6, 19):
        for x in range(2, 18):
            dx, dy = x - cx, y - cy
            if dx * dx + dy * dy <= r * r and (x, y) not in px:
                shade = dx * 0.5 + dy * 0.8
                px[(x, y)] = light if shade < -2.5 else mid if shade < 1.5 else dark if shade < 4.0 else deep
    # The liquid's surface shows as a pale line across the top of the belly, and the glass shines.
    for x, y in ((6, 8), (7, 8)):
        px[(x, y)] = SHINE
    px[(6, 9)] = SHINE
    px[(13, 15)] = light
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
    icons = [
        potion((244, 70, 54, 255), (206, 20, 16, 255), (150, 8, 10, 255), (98, 4, 8, 255)),
        potion((84, 150, 250, 255), (26, 76, 214, 255), (14, 44, 156, 255), (8, 24, 100, 255)),
    ]
    strip = Image.new("RGBA", (len(icons) * SIZE + (len(icons) - 1) * GAP, SIZE), (0, 0, 0, 0))
    for i, icon in enumerate(icons):
        for (x, y), c in outlined(icon).items():
            strip.putpixel((i * (SIZE + GAP) + x, y), c)
    strip.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        ";;; Written by tools/draw_item_icons.py; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {SIZE} :cell-height {SIZE} :gap {GAP}\n"
        f" :frames {len(icons)})\n"
    )
    print(out.with_suffix(".png"))


if __name__ == "__main__":
    main()
