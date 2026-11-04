#!/usr/bin/env python3
"""Make a recoloured copy of an animation strip, for an item that differs from another only in
colour, so the two keep one silhouette:

  tools/recolor_hue.py data/sprites/pickups/flask data/sprites/pickups/mana-potion --hue 222 --below 13 --reach 60

writes mana-potion.png and mana-potion.lisp. Every pixel from row --below down whose hue is within
--reach degrees of --from (red by default) turns to --hue, keeping its saturation and brightness,
so shading and highlights survive (--saturation and --value scale them, to tone down a key
colour such as the townsfolk guard's green tabard). The rows above stay as they are: the flask's tan stopper and
neck are close enough in hue to the orange glints on its belly that only the row tells them apart.

--spread keeps that fraction of each pixel's hue off --from, so a gradient (the bolt's red to
yellow fire) stays one, in the new colour; the spell looks (spells.lisp) are made that way:

  tools/recolor_hue.py data/sprites/bolt/flight data/sprites/spells/frost-flight --from 30 --reach 60 --hue 200 --spread 0.5
"""

import argparse
import colorsys
from pathlib import Path

from PIL import Image


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("source", type=Path, help="the strip, without extension")
    parser.add_argument("out", type=Path, help="the new strip, without extension")
    parser.add_argument("--from", dest="start", type=float, default=0.0, help="hue to change, in degrees")
    parser.add_argument("--hue", type=float, required=True, help="hue it becomes, in degrees")
    parser.add_argument("--reach", type=float, default=22.0, help="degrees either side of --from to change")
    parser.add_argument("--below", type=int, default=0, help="first row to change, from the top")
    parser.add_argument("--spread", type=float, default=0.0,
                        help="fraction of each pixel's hue off --from that it keeps")
    parser.add_argument("--min-saturation", type=float, default=0.12, help="leave anything greyer than this")
    parser.add_argument("--saturation", type=float, default=1.0, help="scale the changed pixels' saturation by this")
    parser.add_argument("--value", type=float, default=1.0, help="scale the changed pixels' brightness by this")
    args = parser.parse_args()

    strip = Image.open(args.source.with_suffix(".png")).convert("RGBA")
    pixels = strip.load()
    for y in range(args.below, strip.height):
        for x in range(strip.width):
            r, g, b, a = pixels[x, y]
            if a == 0:
                continue
            h, s, v = colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)
            off = (h * 360 - args.start + 180) % 360 - 180
            if abs(off) <= args.reach and args.min_saturation <= s:
                nr, ng, nb = colorsys.hsv_to_rgb(((args.hue + off * args.spread) % 360) / 360, min(1.0, s * args.saturation), min(1.0, v * args.value))
                pixels[x, y] = (round(nr * 255), round(ng * 255), round(nb * 255), a)
    strip.save(args.out.with_suffix(".png"))

    index = args.source.with_suffix(".lisp").read_text().splitlines()
    index = [f";;; Written by tools/recolor_hue.py from {args.source.name}.png; do not edit."] + index[1:]
    text = "\n".join(index).replace(f'"{args.source.name}.png"', f'"{args.out.name}.png"')
    args.out.with_suffix(".lisp").write_text(text + "\n")
    print(args.out.with_suffix(".png"))


if __name__ == "__main__":
    main()
