#!/usr/bin/env python3
"""Draw the weapon slot icons for the HUD, one strip in the format tools/slice_frames.py
writes, so the game reads it like any other animation strip:

  tools/draw_weapon_icons.py data/sprites/icons/weapons

writes weapons.png (frames left to right, 2 px transparent gaps) and weapons.lisp.
Frames, in order: the sword, a flame (a rune whose first effect is fire damage), the spear, the
tornado (the tornado's rune), then a rune's icon for each other first effect (*SPELL-ICONS*,
sword.lisp): frost damage a snowflake, shock a lightning bolt, drain a drop of blood, heal a cross,
ward a shield, slow an hourglass, knockback a shockwave pushing right. Each is SIZE art pixels
square, drawn in the palettes of the sword and bolt sprites, then outlined in near-black so it
reads on any background. The top-left corner of each icon is left empty: the game draws the slot's key
number there.
"""

import math
import sys
from pathlib import Path

from PIL import Image, ImageDraw

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


# The fireball's five shades, heart to rim, for each look.
FIRE = ((255, 250, 220), (255, 222, 110), (252, 160, 40), (232, 92, 22), (178, 40, 14))
LOOKS = {
    "frost": ((236, 250, 255), (160, 222, 255), (84, 170, 246), (40, 110, 214), (22, 58, 150)),
    "shock": ((255, 255, 230), (255, 248, 150), (240, 222, 60), (196, 170, 24), (130, 104, 10)),
    "drain": ((255, 228, 236), (255, 140, 170), (232, 60, 104), (176, 24, 66), (110, 10, 40)),
    "heal": ((240, 255, 230), (176, 250, 150), (100, 220, 80), (44, 166, 44), (20, 104, 30)),
    "arcane": ((250, 232, 255), (230, 160, 255), (196, 90, 240), (140, 40, 196), (84, 20, 130)),
}


def fireball(shades=FIRE):
    heart, glow, flame, body, rim_color = shades
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
                c = heart
            elif r < 3.8:
                c = glow
            elif r < 5.3:
                c = flame
            elif r < rim - 0.8:
                c = body
            elif r < rim:
                c = rim_color
            else:
                continue
            px[(x, y)] = c + (255,)
    # Embers flung off the swirl.
    for x, y in ((18, 4), (2, 15), (17, 17)):
        px[(x, y)] = glow + (255,)
    return px


def spear():
    px = {}
    steel_light = (232, 232, 222, 255)
    steel_mid = (176, 178, 172, 255)
    steel_dark = (110, 112, 112, 255)
    gold = (226, 188, 70, 255)
    gold_dark = (150, 112, 30, 255)
    wood = (122, 66, 34, 255)
    wood_dark = (84, 42, 22, 255)
    # Shaft: a long diagonal from the butt (bottom left) up to the head.
    for i in range(12):
        x, y = 2 + i, 17 - i
        px[(x, y)] = wood
        px[(x + 1, y)] = wood_dark
    # Leather grip wrapped round the rear of the shaft.
    for x, y in ((4, 15), (6, 13)):
        px[(x, y)] = wood_dark
    # Brass socket below the head.
    for x, y in ((13, 6), (14, 6), (14, 5)):
        px[(x, y)] = gold
    px[(14, 6)] = gold_dark
    # The head: a leaf blade on the diagonal up to the tip, lit along its rib, widest
    # in its middle, as the sword's blade is drawn.
    for i, (x, y) in enumerate(((15, 4), (16, 3), (17, 2), (18, 1))):
        px[(x, y)] = steel_light
        if i < 3:
            px[(x - 1, y)] = steel_mid
            px[(x + 1, y)] = steel_dark
        if i in (1, 2):
            px[(x - 1, y - 1)] = steel_mid
            px[(x + 1, y + 1)] = steel_dark
    return px


def tornado():
    px = {}
    pale = (214, 204, 240, 255)
    mid = (146, 120, 204, 255)
    dark = (84, 60, 140, 255)
    # A funnel, wide at the top and leaning as it narrows, in bands that slant across it.
    rows = ((6, 17), (5, 16), (5, 15), (5, 14), (6, 14), (6, 13), (7, 13), (7, 12), (8, 12),
            (8, 11), (9, 11), (9, 10), (10, 11), (10, 10), (11, 11))
    for i, (x0, x1) in enumerate(rows):
        for x in range(x0, x1 + 1):
            band = (i + (x - x0) // 4) % 3
            px[(x, 3 + i)] = pale if band == 0 else mid if band == 1 else dark
    return px


def drawn(paint):
    """The pixels PAINT draws with ImageDraw on a SIZE square, as a pixel dict."""
    image = Image.new("RGBA", (SIZE, SIZE), (0, 0, 0, 0))
    paint(ImageDraw.Draw(image))
    return {(x, y): image.getpixel((x, y)) for y in range(SIZE) for x in range(SIZE)
            if image.getpixel((x, y))[3] > 0}


def flame():
    """A tongue of fire leaning to the right at its tip, its heart pale and its rim dark."""
    heart, glow, mid, body, rim = FIRE
    px = {}
    for y in range(2, 19):
        t = (y - 2) / 16
        half = 6.6 * t ** 0.65 if t < 0.8 else 6.6 * 0.8 ** 0.65 * math.sqrt(max(0.0, 1 - ((t - 0.8) / 0.2) ** 2))
        cx = 10.5 + 2.6 * (1 - t) ** 2
        for x in range(SIZE):
            d = abs(x + 0.5 - cx) / max(half, 0.01)
            if d > 1:
                continue
            if d < 0.35 and t > 0.5:
                c = heart
            elif d < 0.6 and t > 0.35:
                c = glow
            elif d < 0.85:
                c = mid
            elif d < 0.97:
                c = body
            else:
                c = rim
            px[(x, y)] = c + (255,)
    # A small tongue licking up on the left.
    for x, y in ((5, 8), (5, 9), (6, 9), (6, 10)):
        px[(x, y)] = mid + (255,)
    px[(5, 7)] = body + (255,)
    return px


def snowflake():
    pale, light, mid, dark, deep = LOOKS["frost"]
    px = {}
    cx, cy = 10.5, 10.5
    for k in range(6):
        a = math.pi / 2 + k * math.pi / 3
        for i in range(1, 17):
            r = i * 0.5
            px[(int(cx + r * math.cos(a)), int(cy - r * math.sin(a)))] = (light if r < 6 else mid) + (255,)
        # Barbs off each arm, two thirds out.
        for side in (-1, 1):
            b = a + side * math.pi / 4
            bx, by = cx + 5 * math.cos(a), cy - 5 * math.sin(a)
            for i in range(1, 6):
                r = i * 0.5
                px[(int(bx + r * math.cos(b)), int(by - r * math.sin(b)))] = mid + (255,)
    for x, y in ((10, 10), (9, 10), (10, 9), (9, 9)):
        px[(x, y)] = pale + (255,)
    return px


def lightning():
    pale, light, mid, dark, deep = LOOKS["shock"]
    bolt = [(13, 1), (5, 11), (9, 11), (6, 19), (16, 8), (11, 8), (15, 1)]
    def paint(d):
        d.polygon(bolt, fill=mid + (255,))
        d.line([(13, 2), (7, 10)], fill=pale + (255,))
        d.line([(9, 12), (7, 17)], fill=light + (255,))
    return drawn(paint)


def blood_drop():
    pale, light, mid, dark, deep = LOOKS["drain"]
    def paint(d):
        d.polygon([(10, 2), (5, 11), (15, 11)], fill=dark + (255,))
        d.ellipse([4, 8, 16, 18], fill=dark + (255,))
        d.polygon([(10, 4), (7, 11), (13, 11)], fill=mid + (255,))
        d.ellipse([6, 9, 14, 16], fill=mid + (255,))
        d.ellipse([7, 10, 9, 13], fill=light + (255,))
    return drawn(paint)


def cross():
    pale, light, mid, dark, deep = LOOKS["heal"]
    def paint(d):
        d.rectangle([8, 3, 12, 17], fill=dark + (255,))
        d.rectangle([3, 8, 17, 12], fill=dark + (255,))
        d.rectangle([9, 4, 11, 16], fill=mid + (255,))
        d.rectangle([4, 9, 16, 11], fill=mid + (255,))
        d.rectangle([9, 9, 11, 11], fill=pale + (255,))
    return drawn(paint)


def shield():
    steel_light, steel, steel_dark = (214, 226, 240), (140, 160, 196), (80, 96, 140)
    gold, gold_dark = (226, 188, 70), (150, 112, 30)
    outer = [(4, 3), (16, 3), (16, 10), (10, 18), (4, 10)]
    inner = [(6, 5), (14, 5), (14, 10), (10, 15), (6, 10)]
    def paint(d):
        d.polygon(outer, fill=gold_dark + (255,))
        d.polygon(inner, fill=steel + (255,))
        d.polygon([(6, 5), (10, 5), (10, 15), (6, 10)], fill=steel_light + (255,))
        d.line([(10, 6), (10, 13)], fill=gold + (255,))
        d.line([(7, 8), (13, 8)], fill=gold + (255,))
    return drawn(paint)


def hourglass():
    wood, wood_dark = (122, 66, 34), (84, 42, 22)
    glass, sand = (190, 214, 236), (236, 200, 110)
    def paint(d):
        d.polygon([(6, 4), (14, 4), (10, 10)], fill=glass + (255,))
        d.polygon([(10, 10), (6, 16), (14, 16)], fill=glass + (255,))
        d.polygon([(8, 7), (12, 7), (10, 10)], fill=sand + (255,))
        d.polygon([(10, 12), (7, 16), (13, 16)], fill=sand + (255,))
        d.line([(10, 10), (10, 12)], fill=sand + (255,))
        d.rectangle([4, 2, 16, 3], fill=wood + (255,))
        d.rectangle([4, 17, 16, 18], fill=wood_dark + (255,))
        d.line([(5, 4), (5, 16)], fill=wood_dark + (255,))
        d.line([(15, 4), (15, 16)], fill=wood_dark + (255,))
    return drawn(paint)


def shockwave():
    pale, light, mid, dark, deep = LOOKS["arcane"]
    def paint(d):
        for i, c in enumerate((dark, mid, light)):
            x = 3 + 4 * i
            d.arc([x - 6, 4, x + 4, 16], -60, 60, fill=c + (255,), width=2)
        d.polygon([(13, 6), (18, 10), (13, 14)], fill=pale + (255,))
        d.line([(9, 10), (14, 10)], fill=pale + (255,), width=2)
    return drawn(paint)


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
    icons = [sword(), flame(), spear(), tornado(), snowflake(), lightning(), blood_drop(), cross(),
             shield(), hourglass(), shockwave()]
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
