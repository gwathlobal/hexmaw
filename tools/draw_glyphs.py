#!/usr/bin/env python3
"""Draw the glyph pickups (pickups.lisp), which teach the player an effect for the spellforge,
one strip per glyph in the format tools/slice_frames.py writes:

  tools/draw_glyphs.py data/sprites/pickups

writes glyph-<kind>.png and .lisp for each kind in GLYPHS. A glyph is a small standing tablet of
dark stone, a rune cut into it glowing in the effect's colour, at the monsters' 64 px per metre.
Its 4 frames pulse the glow: the rune brightens and a faint halo swells round the tablet. Each
rune is its own shape, so two glyphs of near colours still read apart.

It also writes altar-sigil.png and .lisp, the sign that hangs over a spellforge altar
(forge.lisp): a ring of runes round a four-pointed star, 8 frames turning an eighth of the way
between runes and pulsing.
"""

import math

import sys
from pathlib import Path

from PIL import Image

W, H = 22, 30
GAP = 2
FRAMES = 4

OUTLINE = (16, 12, 14, 255)
STONE = (74, 68, 72, 255)
STONE_LIGHT = (104, 97, 100, 255)
STONE_DARK = (48, 43, 48, 255)

# (light, mid, dark) of each glyph's glow.
GLYPHS = {
    "frost": ((220, 244, 255), (110, 190, 250), (40, 100, 190)),
    "shock": ((255, 252, 200), (250, 220, 60), (170, 120, 20)),
    "slow": ((210, 240, 255), (120, 160, 230), (60, 80, 170)),
    "drain": ((255, 200, 210), (230, 60, 90), (130, 20, 50)),
    "ward": ((240, 220, 255), (180, 120, 250), (100, 50, 170)),
    "area": ((255, 230, 190), (250, 150, 60), (170, 70, 20)),
}

# Runes, 9 wide and 13 tall, '#' cut and lit.
RUNES = {
    "frost": [
        "....#....",
        "..#.#.#..",
        "...###...",
        "....#....",
        "#...#...#",
        ".#..#..#.",
        "..#####..",
        ".#..#..#.",
        "#...#...#",
        "....#....",
        "...###...",
        "..#.#.#..",
        "....#....",
    ],
    "shock": [
        ".....##..",
        "....##...",
        "...##....",
        "..##.....",
        ".#######.",
        ".....##..",
        "....##...",
        "...##....",
        "..##.....",
        ".##......",
        ".#.......",
        "#........",
        ".........",
    ],
    "slow": [
        ".#######.",
        ".#.....#.",
        "..#...#..",
        "...#.#...",
        "....#....",
        "....#....",
        "...#.#...",
        "..#.#.#..",
        ".#.###.#.",
        ".#######.",
        ".........",
        "..#...#..",
        ".........",
    ],
    "drain": [
        "....#....",
        "...###...",
        "..#.#.#..",
        ".#..#..#.",
        "....#....",
        "....#....",
        "..#####..",
        ".#.....#.",
        "#.......#",
        "#.......#",
        ".#.....#.",
        "..#####..",
        ".........",
    ],
    "ward": [
        "..#####..",
        ".#.....#.",
        "#...#...#",
        "#..###..#",
        "#...#...#",
        "#...#...#",
        ".#..#..#.",
        ".#.....#.",
        "..#...#..",
        "...#.#...",
        "....#....",
        ".........",
        ".........",
    ],
    "area": [
        "....#....",
        "..#...#..",
        ".........",
        "#...#...#",
        "...###...",
        "..#####..",
        "#.##.##.#",
        "..#####..",
        "...###...",
        "#...#...#",
        ".........",
        "..#...#..",
        "....#....",
    ],
}


def blend(a, b, k):
    return tuple(round(a[i] + (b[i] - a[i]) * k) for i in range(3))


def tablet():
    """The stone: an upright slab with a rounded top and a plinth, lit from the upper left."""
    px = {}
    left, right, top, bottom = 5, 16, 3, 26
    for y in range(top, bottom + 1):
        for x in range(left, right + 1):
            # Round the top two corners.
            if y < top + 2 and (x < left + 2 - (y - top) or x > right - 2 + (y - top)):
                continue
            edge = x == left or x == right or y == top or (y == top + 1 and (x == left + 1 or x == right - 1))
            if edge:
                px[(x, y)] = STONE_LIGHT if x < (left + right) / 2 or y <= top + 1 else STONE_DARK
            else:
                px[(x, y)] = STONE
    # A plinth, wider than the slab.
    for y in range(bottom + 1, bottom + 3):
        for x in range(left - 2, right + 3):
            px[(x, y)] = STONE_DARK if y == bottom + 2 else STONE_LIGHT
    return px


def outline(px):
    """Near-black round every drawn pixel, so the glyph reads on any floor."""
    out = dict(px)
    for (x, y) in px:
        for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            q = (x + dx, y + dy)
            if q not in px and 0 <= q[0] < W and 0 <= q[1] < H:
                out[q] = OUTLINE
    return out


def frame(kind, step):
    light, mid, dark = GLYPHS[kind]
    pulse = (0.0, 0.5, 1.0, 0.5)[step]
    image = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    pixels = image.load()
    # The halo, under the stone: a soft ring of the glow that swells with the pulse.
    cx, cy = (W - 1) / 2, 14.0
    for y in range(H):
        for x in range(W):
            d = ((x - cx) ** 2 / 1.0 + (y - cy) ** 2 / 2.2) ** 0.5
            reach = 9.5 + 1.2 * pulse
            if d < reach:
                a = round(max(0.0, 1 - d / reach) * (50 + 50 * pulse))
                if a > 0:
                    pixels[x, y] = (*mid, a)
    for (x, y), color in outline(tablet()).items():
        pixels[x, y] = color
    # The rune, cut into the face: its strokes in the glow, a dark cut under each.
    rune = RUNES[kind]
    ox, oy = 6, 8
    for ry, row in enumerate(rune):
        for rx, c in enumerate(row):
            if c == "#":
                x, y = ox + rx, oy + ry
                below = (x + 1, y + 1)
                if below[0] <= 15 and below[1] <= 25 and pixels[below][:3] == STONE[:3]:
                    pixels[below] = (*blend(STONE_DARK, dark, 0.5), 255)
                pixels[x, y] = (*blend(mid, light, pulse), 255)
    return image


SIGIL = 48
SIGIL_FRAMES = 8
SIGIL_LIGHT = (255, 236, 190)
SIGIL_MID = (196, 140, 255)
SIGIL_DARK = (96, 50, 170)


def sigil_frame(step):
    image = Image.new("RGBA", (SIGIL, SIGIL), (0, 0, 0, 0))
    pixels = image.load()
    c = (SIGIL - 1) / 2
    pulse = 0.5 + 0.5 * math.cos(2 * math.pi * step / SIGIL_FRAMES)
    turn = 2 * math.pi * step / SIGIL_FRAMES / 8
    for y in range(SIGIL):
        for x in range(SIGIL):
            dx, dy = x - c, y - c
            r = math.hypot(dx, dy)
            a = math.atan2(dy, dx)
            color = None
            # The ring, two pixels thick.
            if 18.5 <= r < 20.5:
                color = (*SIGIL_MID, 255)
            # Eight runes on the ring, turning: short bars across it.
            for i in range(8):
                ra = turn + i * math.pi / 4
                rx, ry = c + 19.5 * math.cos(ra), c + 19.5 * math.sin(ra)
                if abs(x - rx) <= 1.6 and abs(y - ry) <= 1.6:
                    color = (*SIGIL_LIGHT, 255)
            # The star: four points, its arms thinning out to 14 px.
            arm = min(abs(dx), abs(dy))
            if max(abs(dx), abs(dy)) <= 14 and arm <= 2.6 * (1 - max(abs(dx), abs(dy)) / 15):
                color = (*(SIGIL_LIGHT if r < 3 + 3 * pulse else SIGIL_MID), 255)
            # A soft glow round it all.
            if color is None and r < 23:
                k = max(0.0, 1 - abs(r - 12) / 11)
                alpha = round(k * (40 + 50 * pulse))
                if alpha > 0:
                    color = (*SIGIL_DARK, alpha)
            if color:
                pixels[x, y] = color
    return image


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "data/sprites/pickups")
    out.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (SIGIL_FRAMES * SIGIL + (SIGIL_FRAMES - 1) * GAP, SIGIL), (0, 0, 0, 0))
    for step in range(SIGIL_FRAMES):
        strip.alpha_composite(sigil_frame(step), (step * (SIGIL + GAP), 0))
    strip.save(out / "altar-sigil.png")
    (out / "altar-sigil.lisp").write_text(
        f";;; Written by tools/draw_glyphs.py; do not edit.\n"
        f'(:image "altar-sigil.png"\n :cell-width {SIGIL} :cell-height {SIGIL} :gap {GAP}\n :frames {SIGIL_FRAMES})\n')
    print(out / "altar-sigil.png")
    for kind in GLYPHS:
        strip = Image.new("RGBA", (FRAMES * W + (FRAMES - 1) * GAP, H), (0, 0, 0, 0))
        for step in range(FRAMES):
            strip.alpha_composite(frame(kind, step), (step * (W + GAP), 0))
        name = f"glyph-{kind}"
        strip.save(out / f"{name}.png")
        (out / f"{name}.lisp").write_text(
            f";;; Written by tools/draw_glyphs.py; do not edit.\n"
            f'(:image "{name}.png"\n :cell-width {W} :cell-height {H} :gap {GAP}\n :frames {FRAMES})\n')
        print(out / f"{name}.png")


if __name__ == "__main__":
    main()
