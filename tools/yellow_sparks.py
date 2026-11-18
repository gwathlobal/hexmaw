#!/usr/bin/env python3
"""Turn pink spark pixels back into yellow-white lightning, in place.

Yellow-white lightning drawn on a magenta background comes out of the slicers pink: its
anti-aliased blend with the magenta is kept as part of the figure. This takes every opaque pixel
that reads as yellow light mixed with magenta (bright, red well above green, blue too close to
green for yellow: salmon or pink) and makes it the lightning's yellow at its brightness, so the house palette (tools/restyle.py, run after)
puts it on the yellow ramp. Pixels that aren't bright are left alone, so purple cloth or dark
shading isn't touched.

    tools/yellow_sparks.py data/sprites/votary/turnaround.png [more.png ...]
"""
import sys

from PIL import Image


def fix(path):
    im = Image.open(path).convert("RGBA")
    px = im.load()
    changed = 0
    for y in range(im.height):
        for x in range(im.width):
            r, g, b, a = px[x, y]
            if a < 128:
                continue
            # Bright and red-led, with too much blue for yellow: the lightning's yellow mixed with
            # the magenta (salmon or pink). A white core (red near green) is left white.
            if r >= 200 and r - g >= 20 and b >= 0.7 * g and r + g + b >= 420:
                px[x, y] = (r, max(g, int(r * 0.9)), int(r * 0.5), a)
                changed += 1
    im.save(path)
    print(f"{path}: {changed} pixels")


if __name__ == "__main__":
    for p in sys.argv[1:]:
        fix(p)
