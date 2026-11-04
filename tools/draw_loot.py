#!/usr/bin/env python3
"""Draw the found weapons and runes (loot.lisp) as they lie in a level, one strip per pickup in
the format tools/slice_frames.py writes:

  tools/draw_loot.py data/sprites/pickups

writes loot-sword, loot-spear and loot-rune-<look> (.png and .lisp) for each look a spell can have
(*SPELL-LOOKS*, spells.lisp, and the tornado's storm), at the monsters' 64 px per metre. The sword
stands planted point down, 0.75 m; the spear upright, 1.25 m; a rune is a round stone the size of
a palm, a sign cut into it glowing in its look's colours, apart from the glyphs' upright tablets.
4 frames each: a glint runs down the weapons' steel, and a rune's sign and halo pulse.
"""

import math
import sys
from pathlib import Path

from PIL import Image

GAP = 2
FRAMES = 4
OUTLINE = (18, 12, 10, 255)

STEEL_LIGHT = (232, 232, 222, 255)
STEEL_MID = (176, 178, 172, 255)
STEEL_DARK = (110, 112, 112, 255)
GLINT = (255, 255, 250, 255)
GOLD = (226, 188, 70, 255)
GOLD_DARK = (150, 112, 30, 255)
GRIP = (122, 66, 34, 255)
GRIP_DARK = (84, 42, 22, 255)
WOOD = (140, 96, 56, 255)
WOOD_DARK = (96, 62, 34, 255)

STONE = (74, 68, 72, 255)
STONE_LIGHT = (104, 97, 100, 255)
STONE_DARK = (48, 43, 48, 255)

# Heart to rim, the shades tools/draw_weapon_icons.py gives each look's fireball, and the storm's.
LOOKS = {
    "fire": ((255, 250, 220), (255, 222, 110), (252, 160, 40), (232, 92, 22), (178, 40, 14)),
    "frost": ((236, 250, 255), (160, 222, 255), (84, 170, 246), (40, 110, 214), (22, 58, 150)),
    "shock": ((255, 255, 230), (255, 248, 150), (240, 222, 60), (196, 170, 24), (130, 104, 10)),
    "drain": ((255, 228, 236), (255, 140, 170), (232, 60, 104), (176, 24, 66), (110, 10, 40)),
    "heal": ((240, 255, 230), (176, 250, 150), (100, 220, 80), (44, 166, 44), (20, 104, 30)),
    "arcane": ((250, 232, 255), (230, 160, 255), (196, 90, 240), (140, 40, 196), (84, 20, 130)),
    "storm": ((240, 244, 255), (200, 206, 240), (150, 156, 210), (104, 104, 170), (64, 60, 120)),
}


def outlined(px, w, h):
    out = dict(px)
    for (x, y) in px:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in px and 0 <= q[0] < w and 0 <= q[1] < h:
                out[q] = OUTLINE
    return out


def sword(step):
    """Planted point down: pommel, grip and guard up top, the blade into the floor."""
    w, h = 16, 48
    px = {}
    cx = 7
    for y in (1, 2, 3):
        for x in range(cx - 1, cx + 2):
            px[(x, y)] = GOLD if x <= cx else GOLD_DARK
    for y in range(4, 11):
        px[(cx, y)] = GRIP if y % 2 else GRIP_DARK
        px[(cx + 1, y)] = GRIP_DARK
    for x in range(1, 15):
        px[(x, 11)] = GOLD
        px[(x, 12)] = GOLD_DARK
    blade_top, blade_end = 13, 45
    for y in range(blade_top, blade_end + 1):
        # Tapering to the point over its last six rows.
        half = 2 if y < blade_end - 5 else max(0, (blade_end - y) // 2)
        for x in range(cx - half, cx + half + 2):
            px[(x, y)] = STEEL_LIGHT if x == cx else (STEEL_MID if x < cx + 1 else STEEL_DARK)
    # The glint: a short bright band running down the blade, frame by frame.
    g = blade_top + 2 + step * 8
    for y in range(g, min(g + 3, blade_end)):
        for x in range(cx - 1, cx + 2):
            if (x, y) in px:
                px[(x, y)] = GLINT
    return outlined(px, w, h), w, h


def spear(step):
    """Upright, the butt on the floor: an ash shaft, a binding, a leaf-shaped steel head."""
    w, h = 11, 80
    px = {}
    cx = 5
    head_top, head_end = 1, 17
    for y in range(head_top, head_end + 1):
        t = (y - head_top) / (head_end - head_top)
        half = round(3 * math.sin(math.pi * min(1.0, t * 1.15)))
        for x in range(cx - half, cx + half + 1):
            px[(x, y)] = STEEL_LIGHT if x == cx else (STEEL_MID if x < cx else STEEL_DARK)
    for y in range(head_end + 1, head_end + 4):
        for x in range(cx - 1, cx + 2):
            px[(x, y)] = GRIP_DARK if y % 2 else GRIP
    for y in range(head_end + 4, h - 2):
        px[(cx, y)] = WOOD
        px[(cx + 1, y)] = WOOD_DARK
    g = head_top + 3 + step * 3
    for y in range(g, g + 2):
        for x in range(cx - 1, cx + 2):
            if (x, y) in px:
                px[(x, y)] = GLINT
    return outlined(px, w, h), w, h


SIGN = [
    "...#...",
    "..#.#..",
    ".#.#.#.",
    "#.###.#",
    ".#.#.#.",
    "..#.#..",
    "...#...",
]


def rune(look, step):
    """A round stone lit from the upper left, its sign glowing, a halo pulsing round it."""
    w, h = 22, 22
    shades = LOOKS[look]
    pulse = (0.0, 0.5, 1.0, 0.5)[step]
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pixels = image.load()
    c = (w - 1) / 2
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - c, y - c)
            reach = 10.5 + 0.8 * pulse
            if 7 < d < reach:
                a = round(max(0.0, 1 - (d - 7) / (reach - 7)) * (60 + 60 * pulse))
                if a > 0:
                    pixels[x, y] = (*shades[2], a)
    stone = {}
    for y in range(h):
        for x in range(w):
            d = math.hypot(x - c, y - c)
            if d <= 7.2:
                lit = (x - c) + (y - c) < -3
                dark = (x - c) + (y - c) > 4
                stone[(x, y)] = STONE_LIGHT if lit and d > 5.5 else STONE_DARK if dark and d > 5.5 else STONE
    for (x, y), color in outlined(stone, w, h).items():
        pixels[x, y] = color
    glow = tuple(round(shades[1][i] + (shades[0][i] - shades[1][i]) * pulse) for i in range(3))
    for sy, row in enumerate(SIGN):
        for sx, ch in enumerate(row):
            if ch == "#":
                x, y = 8 + sx, 8 + sy
                if pixels[x + 1, y + 1][:3] == STONE[:3]:
                    pixels[x + 1, y + 1] = (*shades[4], 255)
                pixels[x, y] = (*glow, 255)
    return image


def from_pixels(px, w, h):
    image = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    pixels = image.load()
    for (x, y), color in px.items():
        pixels[x, y] = color
    return image


def write(out, name, frames):
    w, h = frames[0].size
    strip = Image.new("RGBA", (FRAMES * w + (FRAMES - 1) * GAP, h), (0, 0, 0, 0))
    for step, frame in enumerate(frames):
        strip.alpha_composite(frame, (step * (w + GAP), 0))
    strip.save(out / f"{name}.png")
    (out / f"{name}.lisp").write_text(
        f";;; Written by tools/draw_loot.py; do not edit.\n"
        f'(:image "{name}.png"\n :cell-width {w} :cell-height {h} :gap {GAP}\n :frames {FRAMES})\n')
    print(out / f"{name}.png")


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "data/sprites/pickups")
    out.mkdir(parents=True, exist_ok=True)
    write(out, "loot-sword", [from_pixels(*sword(s)) for s in range(FRAMES)])
    write(out, "loot-spear", [from_pixels(*spear(s)) for s in range(FRAMES)])
    for look in LOOKS:
        write(out, f"loot-rune-{look}", [rune(look, s) for s in range(FRAMES)])


if __name__ == "__main__":
    main()
