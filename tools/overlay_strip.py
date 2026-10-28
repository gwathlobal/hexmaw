#!/usr/bin/env python3
"""Lay an animation strip over a still sprite, making one animated strip of the two.

The wall torch is a still unlit torch and a looping flame, sliced from separate generated
images by tools/slice_frames.py. The game draws the torch as one camera-facing sprite,
so this puts the flame on the torch in every frame:

  tools/overlay_strip.py art/torch/strips/unlit art/torch/strips/flame \\
      data/sprites/torch/torch --sink 0.11

BASE and OVERLAY are strips without extension (<name>.png plus the <name>.lisp index
slice_frames writes); BASE's first frame is the still. The overlay's bottom, centred on
the base's top, sinks --sink of the base's height into it (the flame into the torch
head). Both are drawn at their own pixel size, so slice them at matching --pixel.

Writes <out>.png, a strip in slice_frames' format, and <out>.lisp, its index, with
:overlay-bottom, the row (from the top of a cell) the overlay's bottom sits on.
"""

import argparse
import os
import re

from PIL import Image

GAP = 2


def read_index(stem):
    with open(stem + ".lisp") as f:
        text = f.read()
    return {key: int(value) for key, value in re.findall(r":([a-z-]+) (\d+)", text)}


def frames(stem):
    index = read_index(stem)
    strip = Image.open(stem + ".png").convert("RGBA")
    w, h = index["cell-width"], index["cell-height"]
    return [strip.crop((i * (w + index["gap"]), 0, i * (w + index["gap"]) + w, h))
            for i in range(index["frames"])]


def solid_columns(image, rows):
    """Mean x of the opaque pixels in ROWS of IMAGE."""
    alpha = image.getchannel("A")
    xs = [x for y in rows for x in range(image.width) if alpha.getpixel((x, y)) >= 128]
    return sum(xs) / len(xs)


def solid_bottom(image):
    alpha = image.getchannel("A")
    return max(y for y in range(image.height) for x in range(image.width)
               if alpha.getpixel((x, y)) >= 128)


def solid_top(image):
    alpha = image.getchannel("A")
    return min(y for y in range(image.height) for x in range(image.width)
               if alpha.getpixel((x, y)) >= 128)


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("base")
    parser.add_argument("overlay")
    parser.add_argument("out")
    parser.add_argument("--sink", type=float, default=0.0,
                        help="how far the overlay's bottom goes into the base, as a fraction of the base's height")
    args = parser.parse_args()

    base = frames(args.base)[0]
    overlays = frames(args.overlay)
    top = solid_top(base)
    # Centre the overlay's base on the top of the base sprite (the torch head).
    head = solid_columns(base, range(top, top + max(1, base.height // 10)))
    bottom = max(solid_bottom(o) for o in overlays)
    foot = sum(solid_columns(o, range(bottom - 2, bottom + 1)) for o in overlays) / len(overlays)
    sink = round(args.sink * base.height)
    ox = round(head - foot)                      # overlay's x in base coordinates
    oy = top + sink - bottom                     # overlay's y in base coordinates
    left, right = min(0, ox), max(base.width, ox + overlays[0].width)
    up = min(0, oy)
    width, height = right - left, base.height - up

    strip = Image.new("RGBA", (len(overlays) * (width + GAP) - GAP, height), (0, 0, 0, 0))
    for i, overlay in enumerate(overlays):
        cell = Image.new("RGBA", (width, height), (0, 0, 0, 0))
        cell.alpha_composite(base, (-left, -up))
        cell.alpha_composite(overlay, (ox - left, oy - up))
        strip.paste(cell, (i * (width + GAP), 0))
    os.makedirs(os.path.dirname(args.out) or ".", exist_ok=True)
    strip.save(args.out + ".png")
    name = os.path.basename(args.out)
    with open(args.out + ".lisp", "w") as f:
        f.write(f";;; Written by tools/overlay_strip.py from {os.path.basename(args.base)} and "
                f"{os.path.basename(args.overlay)}; do not edit.\n")
        f.write(f'(:image "{name}.png"\n :cell-width {width} :cell-height {height} :gap {GAP}\n'
                f" :frames {len(overlays)} :overlay-bottom {top + sink - up})\n")
    print(f"{args.out}.png: {len(overlays)} frames of {width}x{height} px, overlay bottom at row {top + sink - up}")


if __name__ == "__main__":
    main()
