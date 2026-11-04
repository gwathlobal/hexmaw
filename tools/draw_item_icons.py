#!/usr/bin/env python3
"""Draw the item icons for the inventory and quickslot, one strip in the format
tools/slice_frames.py writes, so the game reads it like any other animation strip:

  tools/draw_item_icons.py data/sprites/icons/items

writes items.png (frames left to right, 2 px transparent gaps) and items.lisp. Frames, in
order: the health potion, the mana potion, arcane dust (a glittering violet heap) and gold (a
pile of coins). Each is SIZE art pixels square, the weapon icons'
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


def dust():
    """A low heap of violet powder, lit from the upper left, flecked with bright grains."""
    px = {}
    light, mid, dark, deep = (226, 196, 255, 255), (164, 110, 240, 255), (106, 56, 186, 255), (62, 26, 120, 255)
    for y in range(8, 18):
        half = round((y - 7) * 0.85) + 1
        for x in range(10 - half, 10 + half):
            shade = (x - 10) * 0.4 + (y - 12) * 0.6
            px[(x, y)] = light if shade < -1.5 else mid if shade < 1.0 else dark if shade < 3.0 else deep
    for x, y in ((8, 10), (12, 12), (6, 15), (10, 14), (14, 16), (9, 9)):
        px[(x, y)] = (255, 255, 255, 255)
    for x, y in ((2, 17), (17, 17), (4, 16)):
        px[(x, y)] = mid
    return px


def gold():
    """A short stack of coins seen edge-on, and one coin face-on beside it, gold lit from the
    upper left."""
    px = {}
    light, mid, dark = (255, 236, 140, 255), (226, 180, 50, 255), (150, 104, 20, 255)
    # The stack: each coin an ellipse's top face over a dark rim, one on another.
    for i, cy in enumerate((16, 14, 12, 10)):
        cx = 7 + (i % 2)
        for x in range(cx - 4, cx + 5):
            px[(x, cy + 1)] = dark
            px[(x, cy)] = mid
        for x in range(cx - 3, cx + 4):
            px[(x, cy - 1)] = light if x < cx else mid
    # The face-on coin: a disc with a darker rim and a struck centre.
    for y in range(9, 18):
        for x in range(11, 19):
            d = ((x - 14.5) ** 2 + (y - 13) ** 2) ** 0.5
            if d <= 3.9:
                px[(x, y)] = dark if d > 3.0 else (light if x + y < 27 else mid)
    px[(14, 13)] = dark
    px[(15, 13)] = dark
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
        dust(),
        gold(),
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
