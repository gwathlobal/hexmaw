#!/usr/bin/env python3
"""Lengthen a first-person arm past the edges of a generated picture.

  tools/extend_arm.py art/sword-shield/merge-rim-1.png art/sword-shield/merge-rim-1-arm.png \\
      --vanish 234,720 --edge 0,866 --edge 200,1010 --pad 600,500

A generated weapon picture cuts the forearm off at the image's edge. Moved further onto
the screen (a raised shield), that cut would show. The forearm is a foreshortened
cylinder: its outlines and highlight all run toward one vanishing point (--vanish, in
source pixels, found by extending them). Every pixel added past the image's left and
bottom edges takes the colour where the ray from the vanishing point through it leaves
the image, so outlines and highlight carry on in perspective and the arm widens toward
the viewer. Only rays between the two --edge points (one on each outline, where it
meets the image's edge) are extended: the rest of what touches the edge, such as the
shield, stays cut.

--pad L,B grows the canvas by L pixels on the left and B at the bottom; the picture's
own pixels move right by L, so a point (x, y) in it is (x + L, y) in the output.
"""

import argparse

import numpy as np
from PIL import Image


def point(text):
    x, y = text.split(",")
    return float(x), float(y)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("out")
    ap.add_argument("--vanish", type=point, required=True)
    ap.add_argument("--edge", type=point, action="append", required=True)
    ap.add_argument("--pad", type=point, default=(600, 500))
    args = ap.parse_args()
    if len(args.edge) != 2:
        raise SystemExit("give two --edge points, one on each outline")

    src = np.asarray(Image.open(args.source).convert("RGB"))
    h, w = src.shape[:2]
    pad_l, pad_b = (int(v) for v in args.pad)
    out = np.empty((h + pad_b, w + pad_l, 3), np.uint8)
    out[...] = (255, 0, 255)
    out[:h, pad_l:] = src

    vx, vy = args.vanish
    angles = sorted(np.arctan2(ey - vy, ex - vx) for ex, ey in args.edge)
    ys, xs = np.mgrid[0:h + pad_b, 0:w + pad_l]
    px, py = xs - pad_l + 0.5, ys + 0.5          # in source coordinates
    outside = (px < 0) | (py > h)
    dx, dy = px - vx, py - vy
    angle = np.arctan2(dy, dx)
    wedge = outside & (angles[0] <= angle) & (angle <= angles[1])
    # Where the ray from the vanishing point leaves the image: through the left edge or
    # the bottom one, whichever it crosses first.
    with np.errstate(divide="ignore", invalid="ignore"):
        s_left = np.where(dx < 0, (0.5 - vx) / dx, np.inf)
        s_bottom = np.where(dy > 0, (h - 0.5 - vy) / dy, np.inf)
    s = np.minimum(s_left, s_bottom)
    qx = np.clip(np.floor(vx + s * dx), 0, w - 1).astype(int)
    qy = np.clip(np.floor(vy + s * dy), 0, h - 1).astype(int)
    out[wedge] = src[qy[wedge], qx[wedge]]
    Image.fromarray(out).save(args.out)
    print(f"{args.out}: {w + pad_l} x {h + pad_b}, the picture moved right by {pad_l}")


if __name__ == "__main__":
    main()
