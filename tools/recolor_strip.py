#!/usr/bin/env python3
"""Turn the fire in a strip to another colour, leaving what isn't fire alone: a copy of the
strip and its .lisp index under a new name, the fire's lightness kept and its hue replaced.

  tools/recolor_strip.py data/sprites/hands/hands data/sprites/hands/storm

Fire is a saturated, bright pixel in the hue band --hues (degrees; orange and yellow by
default), since what holds it (skin, leather, steel) is duller or darker. Raise
--min-saturation or --min-value if the recolour reaches the hands.
"""

import argparse
import colorsys
from pathlib import Path

from PIL import Image


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source", help="strip path without extension")
    ap.add_argument("target", help="new strip path without extension")
    ap.add_argument("--hues", type=float, nargs=2, default=(5.0, 65.0), help="hue band of the fire, in degrees")
    ap.add_argument("--min-saturation", type=float, default=0.78)
    ap.add_argument("--min-value", type=float, default=0.8)
    ap.add_argument("--core-value", type=float, default=0.97, help="brightness above which a pixel is the fire's heart")
    ap.add_argument("--core-tint", type=float, default=0.12, help="least saturation of the new colour")
    ap.add_argument("--hue", type=float, default=268.0, help="hue of the new colour, in degrees")
    ap.add_argument("--saturation", type=float, default=0.7, help="how much of the old saturation it keeps")
    args = ap.parse_args()

    source = Path(args.source)
    target = Path(args.target)
    img = Image.open(source.with_suffix(".png")).convert("RGBA")
    px = img.load()
    for y in range(img.height):
        for x in range(img.width):
            r, g, b, a = px[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            in_band = args.hues[0] <= h * 360 <= args.hues[1]
            # The fire, or the pale heart of it: nothing else in the strip is nearly white.
            if in_band and ((args.min_saturation <= s and args.min_value <= v) or args.core_value <= v):
                nr, ng, nb = colorsys.hsv_to_rgb(args.hue / 360, max(s * args.saturation, args.core_tint), v)
                px[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    img.save(target.with_suffix(".png"))
    index = source.with_suffix(".lisp").read_text()
    index = index.replace(f'"{source.name}.png"', f'"{target.name}.png"')
    target.with_suffix(".lisp").write_text(
        f";;; Written by tools/recolor_strip.py from {source.name}; do not edit.\n"
        + "\n".join(line for line in index.splitlines() if not line.startswith(";;;")) + "\n")


if __name__ == "__main__":
    main()
