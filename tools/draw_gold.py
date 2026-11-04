#!/usr/bin/env python3
"""Draw the gold pickup: a small pile of coins with a glint that runs over it, 4 frames.

    tools/draw_gold.py data/sprites/pickups/gold

writes gold.png (frames side by side, 2 px apart, as tools/slice_frames.py does) and gold.lisp,
its index. At the monsters' 64 px per metre the pile is about 0.35 m across.
"""
import sys
from PIL import Image

W, H, GAP, FRAMES = 22, 14, 2, 4
OUTLINE = (58, 36, 10, 255)
DARK = (140, 92, 22, 255)
MID = (206, 150, 40, 255)
LIGHT = (246, 210, 96, 255)
GLINT = (255, 252, 226, 255)

# Coins as (centre x, centre y, half width): ellipses 2:1, bottom row first so the upper ones
# overlap them.
COINS = [(4, 11, 3), (10, 12, 3), (16, 11, 3), (7, 9, 3), (13, 9, 3), (18, 8, 2), (10, 6, 3), (5, 7, 2), (14, 5, 2)]


def coin(img, cx, cy, r):
    for y in range(cy - r // 2 - 1, cy + r // 2 + 2):
        for x in range(cx - r - 1, cx + r + 2):
            dx, dy = (x - cx) / (r + 0.5), (y - cy) / (r / 2 + 0.75)
            d = dx * dx + dy * dy
            if 0 <= x < W and 0 <= y < H and d <= 1.0:
                if d > 0.62:
                    c = OUTLINE
                elif dy > 0.25:
                    c = DARK
                elif dx + dy < -0.35:
                    c = LIGHT
                else:
                    c = MID
                img.putpixel((x, y), c)


def frame(n):
    img = Image.new("RGBA", (W, H), (0, 0, 0, 0))
    for cx, cy, r in COINS:
        coin(img, cx, cy, r)
    # The glint: a small cross on one coin's light side, moving across the pile.
    gx, gy = [(5, 6), (9, 5), (13, 4), (17, 7)][n]
    for x, y in ((gx, gy), (gx - 1, gy), (gx + 1, gy), (gx, gy - 1), (gx, gy + 1)):
        if 0 <= x < W and 0 <= y < H and img.getpixel((x, y))[3]:
            img.putpixel((x, y), GLINT if (x, y) == (gx, gy) else LIGHT)
    return img


def main():
    out = sys.argv[1]
    strip = Image.new("RGBA", (FRAMES * W + (FRAMES - 1) * GAP, H), (0, 0, 0, 0))
    for n in range(FRAMES):
        strip.paste(frame(n), (n * (W + GAP), 0))
    strip.save(out + ".png")
    name = out.rsplit("/", 1)[-1]
    with open(out + ".lisp", "w") as f:
        f.write(";;; Written by tools/draw_gold.py; do not edit.\n")
        f.write(f'(:image "{name}.png"\n :cell-width {W} :cell-height {H} :gap {GAP}\n :frames {FRAMES})\n')


if __name__ == "__main__":
    main()
