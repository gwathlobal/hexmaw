#!/usr/bin/env python3
"""Make the game's icons from one generated picture (art/icon/, art/prompts/icon.txt).

    tools/make_icon.py art/icon/icon-2.png data/icon

writes, into data/icon/:
  hexmaw.ico      the Windows executable's, which tools/exe-icon/set-icon.lisp writes into
                  it (tools/build-dist); every size Windows asks for, each scaled from the
                  source rather than one image the ICO writer shrinks
  hexmaw.icns     the macOS bundle's (Deploy copies it into Hexmaw.app)
  hexmaw-64.png   the game window's, set at launch (main.lisp)

The source is the maw on flat magenta: the magenta and the pink fringe round it are keyed
out, the maw is cropped to its outline and centred on a transparent square.
"""
import argparse
from pathlib import Path

from PIL import Image

# What Windows asks an executable for: small and large list views, the taskbar at
# 100-250% scaling, and Explorer's extra large view.
ICO_SIZES = [16, 20, 24, 32, 40, 48, 64, 256]
ICNS_SIZES = [16, 32, 64, 128, 256, 512]
# The silhouette may fill this much of the square, so it never touches the edge.
FILL = 0.94


def key_magenta(image):
    """Transparent where the picture is the magenta background or a blend into it."""
    image = image.convert("RGBA")
    pixels = image.load()
    for y in range(image.height):
        for x in range(image.width):
            r, g, b, a = pixels[x, y]
            # Magenta and its blends: red and blue both well above green.
            if r > 150 and b > 150 and g < 0.6 * min(r, b):
                pixels[x, y] = (0, 0, 0, 0)
    return image


def squared(image):
    box = image.getbbox()
    image = image.crop(box)
    side = round(max(image.size) / FILL)
    square = Image.new("RGBA", (side, side), (0, 0, 0, 0))
    square.paste(image, ((side - image.width) // 2, (side - image.height) // 2), image)
    return square


def scaled(image, size):
    # A box filter averages the pixels each output pixel covers: a nearest-neighbour shrink
    # of pixel art to 16 px drops whole fangs.
    return image.resize((size, size), Image.BOX)


def main():
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("source", type=Path)
    parser.add_argument("out", type=Path)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)
    icon = squared(key_magenta(Image.open(args.source)))
    biggest = scaled(icon, ICNS_SIZES[-1])
    images = [scaled(icon, s) for s in ICO_SIZES]
    images[-1].save(args.out / "hexmaw.ico", format="ICO", sizes=[(s, s) for s in ICO_SIZES],
                    append_images=images[:-1])
    biggest.save(args.out / "hexmaw.icns", format="ICNS",
                 append_images=[scaled(icon, s) for s in ICNS_SIZES[:-1]])
    scaled(icon, 64).save(args.out / "hexmaw-64.png")
    print(f"wrote {args.out}/hexmaw.ico, hexmaw.icns, hexmaw-64.png from {args.source}")


if __name__ == "__main__":
    main()
