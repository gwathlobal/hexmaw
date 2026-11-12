#!/usr/bin/env python3
"""Lay one picture's hands over another's fire, for a frame where only the fire moves.

    tools/swap_fire.py art/hands/idle-2.png art/hands/flicker-1.png art/hands/flicker-1-fire.png

The casting hands' idle flicker (art/hands/hands-frames.txt): asked for the rest pose with other
flames, the generator also moves the hands a few pixels, and the hands jitter between the two
frames. So the frame is BASE (the rest pose) with its fire taken out, the fire of DONOR put in
its place (the holes the donor's own hands left in it filled from the fire round them; never
BASE's own fire, or the frame shows two flames at once), and BASE's hands drawn over it, since
the fire burns behind them. Fire is a warm,
saturated or white-hot pixel; the background is magenta, as the generator draws it.
"""

import sys

import numpy as np
from PIL import Image


def masks(rgb):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    background = b > g + 40
    hi, lo = rgb.max(-1).astype(int), rgb.min(-1).astype(int)
    sat = (hi - lo) / np.maximum(hi, 1)
    fire = ~background & (((r >= g) & (g >= b) & (sat > 0.45) & (hi > 150)) | ((hi > 235) & (sat < 0.2)))
    return background, fire


def main():
    base_path, donor_path, out_path = sys.argv[1:4]
    base = np.asarray(Image.open(base_path).convert("RGB"))
    donor = np.asarray(Image.open(donor_path).convert("RGB"))
    base_bg, base_fire = masks(base)
    _, donor_fire = masks(donor)
    hands = ~base_bg & ~base_fire
    out = np.zeros_like(base)
    out[...] = (255, 0, 255)
    # Only the donor's fire: kept with the base's too, the frame showed both flames at once.
    out[donor_fire] = donor[donor_fire]
    # Holes in it where the donor's own hands hid it: filled from the fire around them.
    fire = donor_fire.copy()
    for _ in range(12):
        holes = ~fire & ~hands
        count = np.zeros(fire.shape, int)
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            count += np.roll(np.roll(fire, dy, 0), dx, 1)
        fill = holes & (count >= 3)
        if not fill.any():
            break
        src = np.roll(out, 1, 1)
        out[fill] = np.where(np.roll(fire, 1, 1)[fill][:, None], src[fill], np.roll(out, -1, 1)[fill])
        fire |= fill
    out[hands] = base[hands]
    Image.fromarray(out).save(out_path)
    print(out_path)


if __name__ == "__main__":
    main()
