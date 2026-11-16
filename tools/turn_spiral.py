#!/usr/bin/env python3
"""Turn the magic held between the hands of a stance picture, for the frames of its loop
(art/hands/hands-frames.txt):

    tools/turn_spiral.py art/hands/absorb-void-1.png art/hands/absorb-void-turn --centre 767,593 --radius 182 --all

writes absorb-void-turn-1.png .. -3.png beside it: the picture with what lies inside the circle of
RADIUS round CENTRE turned a quarter, a half and three quarters round (a quarter turn is lossless on
pixel art). Asked for the magic turned, the generator moves the hands too, and the loop would
jitter. With --all, everything inside the circle that isn't magenta turns (the Absorb void and its
streaks, drawn clear of the hands); without, only fire (as tools/swap_fire.py finds it), the hands
drawn over it again, for a spiral of fire that touches them.
"""

import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image

sys.path.insert(0, str(Path(__file__).resolve().parent))
from swap_fire import masks  # noqa: E402

MAGENTA = np.array([255, 0, 255], dtype=np.uint8)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('source')
    ap.add_argument('stem', help='output path without the -N.png')
    ap.add_argument('--centre', required=True, help='X,Y of the spiral\'s middle, in source pixels')
    ap.add_argument('--radius', type=int, required=True)
    ap.add_argument('--all', action='store_true', help='turn all but magenta inside the circle, not only fire')
    args = ap.parse_args()
    cx, cy = (int(v) for v in args.centre.split(','))
    r = args.radius
    rgb = np.array(Image.open(args.source).convert('RGB'))
    background, fire = masks(rgb)
    ys, xs = np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]
    inside = (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r
    if args.all:
        r_, g_, b_ = (rgb[..., i].astype(int) for i in range(3))
        magenta = (r_ > g_ + 40) & (b_ > g_ + 40) & (abs(r_ - b_) < 90)
        spiral = ~magenta & inside
    else:
        spiral = fire & inside
    hands = ~background & ~fire
    # The square round the circle, the spiral alone in it.
    box = (slice(cy - r, cy + r), slice(cx - r, cx + r))
    patch = np.where(spiral[box][..., None], rgb[box], 0)
    patch_mask = spiral[box]
    for k in (1, 2, 3):
        out = rgb.copy()
        out[spiral] = MAGENTA
        turned = np.rot90(patch, -k)
        turned_mask = np.rot90(patch_mask, -k)
        region = out[box]
        region[turned_mask] = turned[turned_mask]
        # The hands burn in front of the fire.
        if not args.all:
            out[hands] = rgb[hands]
        path = Path(f'{args.stem}-{k}.png')
        Image.fromarray(out).save(path)
        print(path)


if __name__ == '__main__':
    main()
