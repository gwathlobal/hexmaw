#!/usr/bin/env python3
"""Draw the status icons for the HUD (status-icons.lisp), one strip in the format
tools/slice_frames.py writes, so the game reads it like any other animation strip:

  tools/draw_status_icons.py data/sprites/icons/statuses

writes statuses.png (frames left to right, 2 px transparent gaps) and statuses.lisp. Frames, in
order: burn (fire damage over time), frost, shock, regen (healing over time), slow, ward. Each is
SIZE art pixels square like the weapon icons, drawn from a character map in three shades of its
colour, then outlined in near-black so it reads on any background. The game draws the seconds
left (a ward's points) over the bottom-right corner, so each picture keeps to the upper left.
"""

import sys
from pathlib import Path

from PIL import Image

SIZE = 20
GAP = 2

OUTLINE = (18, 12, 10, 255)

# Each icon: rows of characters, L light, M mid, D dark, anything else empty; and its shades.
ICONS = [
    ("burn", ((255, 236, 150), (250, 150, 40), (200, 60, 20)), [
        "........L.......",
        ".......LL.......",
        "......LML....L..",
        "......MMM...LL..",
        ".....MMMMM..ML..",
        "..L..MMLMM.MMM..",
        "..LM.MLLLMMMMM..",
        "..MMMMLLLMMMDM..",
        "..MMMLLLLLMMDD..",
        "..DMMLLLLLLMDD..",
        "..DMMLLLLLLMMD..",
        "..DDMMLLLLMMDD..",
        "...DDMMMMMMDD...",
        "....DDDDDDDD....",
    ]),
    ("frost", ((240, 250, 255), (140, 205, 255), (50, 120, 210)), [
        ".......L.......",
        ".....L.L.L.....",
        "......LML......",
        ".L.....M.....L.",
        "..L....M....L..",
        "LMMM...M...MMML",
        "..DMM..M..MMD..",
        "....MMMLMMM....",
        "..DMM..M..MMD..",
        "LMMM...M...MMML",
        "..L....M....L..",
        ".L.....M.....L.",
        "......LML......",
        ".....L.L.L.....",
        ".......L.......",
    ]),
    ("shock", ((255, 255, 220), (250, 225, 70), (180, 130, 20)), [
        "........LLLL",
        ".......LMMD.",
        "......LMMD..",
        ".....LMMD...",
        "....LMMD....",
        "...LMMMLLLL.",
        "..LMMMMMMMD.",
        "......MMMD..",
        ".....MMMD...",
        "....MMMD....",
        "...MMMD.....",
        "..MMD.......",
        ".MD.........",
        "D...........",
    ]),
    ("regen", ((220, 255, 210), (110, 220, 90), (40, 140, 40)), [
        ".....LLLL.....",
        ".....LMMD.....",
        ".....LMMD.....",
        ".....LMMD.....",
        ".LLLLLMMDLLLL.",
        ".LMMMMMMMMMMD.",
        ".LMMMMMMMMMMD.",
        ".DDDDDMMDDDDD.",
        ".....LMMD.....",
        ".....LMMD.....",
        ".....LMMD.....",
        ".....DDDD.....",
    ]),
    ("slow", ((230, 240, 255), (150, 175, 235), (70, 90, 170)), [
        "DDDDDDDDDDDD",
        ".DLLLLLLLLD.",
        "..DLLLLLLD..",
        "...DMMMMD...",
        "....DMMD....",
        ".....DD.....",
        ".....LL.....",
        "....D..D....",
        "...D..L.D...",
        "..D..LMM.D..",
        ".D..LMMMM.D.",
        "DDDDDDDDDDDD",
    ]),
    ("ward", ((245, 225, 255), (180, 120, 250), (100, 50, 170)), [
        "LLLLLLLLLLLLL",
        "LMMMMMMMMMMMD",
        "LMMMMLLMMMMMD",
        "LMMMMLLMMMMMD",
        "LMMLLLLLLMMMD",
        "LMMLLLLLLMMMD",
        "LMMMMLLMMMMMD",
        ".LMMMLLMMMMD.",
        ".LMMMLLMMMMD.",
        "..LMMMMMMMD..",
        "...LMMMMMD...",
        "....LMMMD....",
        ".....LMD.....",
        "......D......",
    ]),
]


def draw(shades, rows):
    light, mid, dark = (s + (255,) for s in shades)
    colour = {"L": light, "M": mid, "D": dark}
    # Up and left: the number sits over the bottom-right corner.
    ox, oy = 1, 1
    px = {}
    for y, row in enumerate(rows):
        for x, c in enumerate(row):
            if c in colour:
                px[(ox + x, oy + y)] = colour[c]
    return px


def outlined(px):
    out = dict(px)
    for (x, y) in px:
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if (nx, ny) not in px and 0 <= nx < SIZE and 0 <= ny < SIZE:
                out[(nx, ny)] = OUTLINE
    return out


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "data/sprites/icons/statuses")
    out.parent.mkdir(parents=True, exist_ok=True)
    strip = Image.new("RGBA", (len(ICONS) * SIZE + (len(ICONS) - 1) * GAP, SIZE), (0, 0, 0, 0))
    for i, (_, shades, rows) in enumerate(ICONS):
        for (x, y), c in outlined(draw(shades, rows)).items():
            if 0 <= x < SIZE and 0 <= y < SIZE:
                strip.putpixel((i * (SIZE + GAP) + x, y), c)
    strip.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        ";;; Written by tools/draw_status_icons.py; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {SIZE} :cell-height {SIZE} :gap {GAP}\n"
        f" :frames {len(ICONS)})\n")
    print(out.with_suffix(".png"))


if __name__ == "__main__":
    main()
