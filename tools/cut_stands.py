#!/usr/bin/env python3
"""Cut a generated turnaround sheet into its five standing cells, art/<who>/stand-<view>.png,
for tools/gen_monster_views.sh to reference (CLAUDE.md, "Monster sprites").

The cells are cut at the sheet's cyan separators, full height, the magenta background kept, so
each is the figure as drawn. --mirror flips the named views, for a sheet whose turned view faces
image-right.

  tools/cut_stands.py art/guard/turnaround-1.png art/guard
"""

import argparse
from pathlib import Path

from PIL import Image, ImageOps

VIEWS = ["front", "front-quarter", "side", "back-quarter", "back"]


def is_cyan(r, g, b):
    return b > 150 and g > 150 and r < 120


def separators(image):
    """The x ranges of the columns that are cyan most of the way down."""
    w, h = image.size
    px = image.load()
    ys = range(0, h, max(1, h // 64))
    columns = [x for x in range(w) if sum(is_cyan(*px[x, y][:3]) for y in ys) > 0.8 * len(ys)]
    runs = []
    for x in columns:
        if runs and x == runs[-1][1] + 1:
            runs[-1][1] = x
        else:
            runs.append([x, x])
    return runs


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet", type=Path)
    ap.add_argument("out", type=Path, help="the folder to write stand-<view>.png into")
    ap.add_argument("--margin", type=int, default=4, help="pixels to skip next to each separator")
    ap.add_argument("--mirror", nargs="*", default=[], choices=VIEWS, metavar="VIEW")
    args = ap.parse_args()
    image = Image.open(args.sheet).convert("RGB")
    w, h = image.size
    runs = separators(image)
    edges = [-1] + [x for run in runs for x in run] + [w]
    # Each cell lies between one separator's right edge and the next one's left edge.
    cells = [(edges[i] + 1 + args.margin, edges[i + 1] - args.margin)
             for i in range(0, len(edges) - 1, 2) if edges[i + 1] - edges[i] > 20]
    if len(cells) != len(VIEWS):
        raise SystemExit(f"{args.sheet}: found {len(cells)} cells, not {len(VIEWS)}")
    args.out.mkdir(parents=True, exist_ok=True)
    for view, (x0, x1) in zip(VIEWS, cells):
        cell = image.crop((x0, 0, x1, h))
        if view in args.mirror:
            cell = ImageOps.mirror(cell)
        cell.save(args.out / f"stand-{view}.png")
        print(f"stand-{view}.png: {x1 - x0} x {h}")


if __name__ == "__main__":
    main()
