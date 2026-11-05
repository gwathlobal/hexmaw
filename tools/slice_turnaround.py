#!/usr/bin/env python3
"""Slice a generated turnaround sheet into a sprite atlas.

The sheet is N views side by side on a magenta background, separated by cyan
vertical lines (front, 3/4 front, side, 3/4 back, back). This keys out the
background, cuts the views with a shared crop so the feet and centre line stay
put when the game switches views, downscales, and writes:

  <out>.png   atlas, one cell per view, left to right, 2 px transparent gaps
  <out>.lisp  index the game reads: cell size, gap, view names

The game expects the three turned views (front-quarter, side, back-quarter) to
face image-left, and mirrors them for the other side. Generated sheets are not
always consistent; check each view and flip the odd ones out with --mirror.

Views are downscaled with nearest-neighbour unless --filter box, which averages the
source pixels under each sprite pixel: generated sheets are noisy below their pixel
grid, and picking one source pixel turns that into speckle. --colors N then maps the
whole atlas onto one N-colour palette taken from its own pixels.

  tools/slice_turnaround.py art/imp/turnaround.png data/sprites/imp/turnaround \\
      --height 96 --mirror back-quarter
"""

import argparse
from pathlib import Path

from PIL import Image

from pixelart import box_downscale, reduce_colors

VIEWS = ["front", "front-quarter", "side", "back-quarter", "back"]
GAP = 2


def is_background(r, g, b):
    # Magenta, including the darker purple fringes where it blends into outlines.
    magenta = min(r, b) > 60 and g < 0.5 * min(r, b) and abs(r - b) < 0.35 * max(r, b)
    cyan = b > 150 and g > 150 and r < 120
    return magenta or cyan


def separator_columns(img):
    w, h = img.size
    px = img.load()
    cols = []
    for x in range(w):
        cyan = sum(1 for y in range(0, h, 4)
                   if px[x, y][2] > 150 and px[x, y][1] > 150 and px[x, y][0] < 120)
        if cyan > (h // 4) * 0.5:
            cols.append(x)
    return cols


def panels(img, expected):
    """(left, right) pixel ranges of each view, split on the cyan lines."""
    w, _ = img.size
    cuts, prev = [], None
    for x in separator_columns(img):
        if prev is None or x != prev + 1:
            cuts.append([x, x])
        else:
            cuts[-1][1] = x
        prev = x
    edges = [-1] + [c for run in cuts for c in run] + [w]
    ranges = [(edges[i] + 1, edges[i + 1] - 1) for i in range(0, len(edges), 2)]
    ranges = [r for r in ranges if r[1] - r[0] > 20]
    if len(ranges) != expected:
        raise SystemExit(f"Found {len(ranges)} views, expected {expected}. Separators at {cuts}")
    return ranges


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("out", help="output path without extension")
    ap.add_argument("--height", type=int, default=96, help="sprite height in pixels (default 96)")
    ap.add_argument("--margin", type=int, default=4, help="source pixels to skip next to each separator")
    ap.add_argument("--mirror", nargs="*", default=[], choices=VIEWS, metavar="VIEW",
                    help="views to flip so they face image-left")
    ap.add_argument("--filter", choices=("nearest", "box"), default="nearest",
                    help="downscale by picking one source pixel per sprite pixel, or by averaging them")
    ap.add_argument("--colors", type=int, help="reduce the atlas to a palette of this many colours")
    args = ap.parse_args()

    src = Image.open(args.sheet).convert("RGBA")
    # Find the views before keying, which erases the cyan separators.
    ranges = [(l + args.margin, r - args.margin) for l, r in panels(src, len(VIEWS))]
    px = src.load()
    w, h = src.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if is_background(r, g, b):
                px[x, y] = (0, 0, 0, 0)

    # Shared crop: one vertical span for all views, one half-width around each panel's centre.
    top, bottom, half = h, 0, 0
    for l, r in ranges:
        bbox = src.crop((l, 0, r + 1, h)).getbbox()
        if not bbox:
            raise SystemExit(f"View at x {l}..{r} is empty after keying")
        centre = (r - l) / 2
        top, bottom = min(top, bbox[1]), max(bottom, bbox[3])
        half = max(half, centre - bbox[0], bbox[2] - centre)
    half = int(half) + 1

    scale = args.height / (bottom - top)
    cell_w = max(1, round(2 * half * scale))
    cell_h = args.height
    atlas = Image.new("RGBA", (len(VIEWS) * cell_w + (len(VIEWS) - 1) * GAP, cell_h), (0, 0, 0, 0))
    for i, (l, r) in enumerate(ranges):
        centre = l + (r - l) // 2
        view = src.crop((centre - half, top, centre + half, bottom))
        if args.filter == "box":
            view = box_downscale(view, (cell_w, cell_h))
        else:
            view = view.resize((cell_w, cell_h), Image.NEAREST)
        if VIEWS[i] in args.mirror:
            view = view.transpose(Image.FLIP_LEFT_RIGHT)
        atlas.paste(view, (i * (cell_w + GAP), 0))
    if args.colors:
        atlas = reduce_colors(atlas, args.colors)

    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    atlas.save(out.with_suffix(".png"))
    names = " ".join(f":{v}" for v in VIEWS)
    out.with_suffix(".lisp").write_text(
        f";;; Written by tools/slice_turnaround.py from {Path(args.sheet).name}; do not edit.\n"
        f";;; Turned views face image-left{'; mirrored: ' + ', '.join(args.mirror) if args.mirror else ''}.\n"
        f"(:image \"{out.with_suffix('.png').name}\"\n"
        f" :cell-width {cell_w} :cell-height {cell_h} :gap {GAP}\n"
        f" :views ({names}))\n")
    print(f"{out.with_suffix('.png')}: {len(VIEWS)} views of {cell_w}x{cell_h} px "
          f"(source crop {2 * half}x{bottom - top}, scale {scale:.3f})")


if __name__ == "__main__":
    main()
