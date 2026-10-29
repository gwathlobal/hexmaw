#!/usr/bin/env python3
"""Turn a generated surface image into a tiling game texture.

    tools/make_texture.py art/textures/wall-stone-1.png data/textures/wall-stone --metres 4

The game draws level textures at 64 art pixels per metre (the monsters' density), so a
texture covering --metres is metres * 64 pixels square. The source is cropped to a
square in the middle (--crop shrinks that square further, to drop a generator's
border). Asked for a seamless texture, the generator's image mostly tiles already. If
the seam shows, --blend PX cross-fades a band PX source pixels wide past the right and
bottom edges into the left and top edges, so the last column runs on into the first;
it ghosts joints that don't line up, so a fresh image is often the better fix.

Then it is box-filtered down to size (averaging, as slice_frames.py --filter box does),
and --colors reduces it to one palette, which flattens the generator's noise below the
pixel grid. Writes <out>.png and, beside the source, <source stem>-tiled.png: the
texture 3 x 3 at 4x zoom, to check the seams by eye. It prints how far the wrapped
edges differ from neighbouring rows inside the tile (1.0: no more than any two rows).
"""

import argparse
from pathlib import Path

from PIL import Image, ImageChops, ImageStat

PIXELS_PER_METRE = 64


def wrap_blend(img, band):
    """Square IMG of side S + BAND to side S, cross-fading the BAND pixels past the right
    and bottom edges into the left and top edges so that the result wraps."""
    if band <= 0:
        return img
    w, h = img.size
    s = w - band
    # Columns: column x < BAND fades from source column x + S (which follows column S - 1)
    # to source column x.
    cols = img.crop((0, 0, s, h))
    for x in range(band):
        t = (x + 0.5) / band
        a = img.crop((x + s, 0, x + s + 1, h))
        b = img.crop((x, 0, x + 1, h))
        cols.paste(Image.blend(a, b, t), (x, 0))
    # Then rows, the same way.
    out = cols.crop((0, 0, s, s))
    for y in range(band):
        t = (y + 0.5) / band
        a = cols.crop((0, y + s, s, y + s + 1))
        b = cols.crop((0, y, s, y + 1))
        out.paste(Image.blend(a, b, t), (0, y))
    return out


def seam_ratio(tex):
    """Mean difference across the wrapped edges over the mean difference between
    neighbouring rows and columns inside TEX."""
    w, h = tex.size

    def diff(a, b):
        return sum(ImageStat.Stat(ImageChops.difference(a, b)).mean[:3]) / 3

    edge = (diff(tex.crop((0, 0, 1, h)), tex.crop((w - 1, 0, w, h)))
            + diff(tex.crop((0, 0, w, 1)), tex.crop((0, h - 1, w, h)))) / 2
    inner = (diff(tex.crop((0, 0, w - 1, h)), tex.crop((1, 0, w, h)))
             + diff(tex.crop((0, 0, w, h - 1)), tex.crop((0, 1, w, h)))) / 2
    return edge / max(inner, 1e-6)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("out", help="output path without extension, e.g. data/textures/wall-stone")
    ap.add_argument("--metres", type=float, required=True, help="metres the texture covers on a side")
    ap.add_argument("--crop", type=int, default=0, help="source pixels to drop on every side first")
    ap.add_argument("--blend", type=int, default=0,
                    help="source pixels cross-faded across the wrapped edges (default 0: none)")
    ap.add_argument("--colors", type=int, default=32, help="palette size (default 32, 0 to keep every colour)")
    args = ap.parse_args()

    src = Image.open(args.source).convert("RGB")
    w, h = src.size
    side = min(w, h) - 2 * args.crop
    left, top = (w - side) // 2, (h - side) // 2
    img = src.crop((left, top, left + side, top + side))
    img = wrap_blend(img, args.blend)

    size = round(args.metres * PIXELS_PER_METRE)
    tex = img.resize((size, size), Image.BOX)
    if args.colors:
        tex = tex.quantize(args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")

    out = Path(args.out).with_suffix(".png")
    out.parent.mkdir(parents=True, exist_ok=True)
    tex.save(out)

    tiled = Image.new("RGB", (size * 3, size * 3))
    for i in range(3):
        for j in range(3):
            tiled.paste(tex, (i * size, j * size))
    source = Path(args.source)
    preview = source.with_name(source.stem + "-tiled.png")
    tiled.resize((size * 12, size * 12), Image.NEAREST).save(preview)
    print(f"{out}: {size} x {size} px; seam {seam_ratio(tex):.2f}; preview {preview}")


if __name__ == "__main__":
    main()
