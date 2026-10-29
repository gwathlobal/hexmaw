#!/usr/bin/env python3
"""Turn a generated picture into a menu splash screen.

    tools/make_splash.py art/splash/title-1.png data/splash/title

The menus draw a splash over the whole window, cropped to cover it (menu.lisp), with
nearest filtering. The source is cropped to 16:9 around its middle (--shift moves the
crop up or down, as a fraction of the height cut off: -1 keeps the top, 1 the bottom),
box-filtered down to --width (640: 2 screen pixels per splash pixel at 1280 x 720, 3 at
1920 x 1080). --colors N flattens it to one palette, as make_texture.py does, but a
splash has small spots of colour (the knight's blue runes) that a median-cut palette
merges away, so by default it keeps every colour. Writes <out>.png.
"""

import argparse
from pathlib import Path

from PIL import Image


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("out", help="output path without extension, e.g. data/splash/title")
    ap.add_argument("--width", type=int, default=640, help="output width in pixels (default 640)")
    ap.add_argument("--shift", type=float, default=0.0,
                    help="where the 16:9 crop sits, -1 top to 1 bottom (default 0: middle)")
    ap.add_argument("--colors", type=int, default=0, help="palette size (default 0: keep every colour)")
    args = ap.parse_args()

    src = Image.open(args.source).convert("RGB")
    w, h = src.size
    cw, ch = w, round(w * 9 / 16)
    if ch > h:
        cw, ch = round(h * 16 / 9), h
    left = (w - cw) // 2
    top = round((h - ch) / 2 * (1 + max(-1.0, min(1.0, args.shift))))
    img = src.crop((left, top, left + cw, top + ch))

    size = (args.width, round(args.width * 9 / 16))
    out_img = img.resize(size, Image.BOX)
    if args.colors:
        out_img = out_img.quantize(args.colors, method=Image.Quantize.MEDIANCUT,
                                   dither=Image.Dither.NONE).convert("RGB")

    out = Path(args.out).with_suffix(".png")
    out.parent.mkdir(parents=True, exist_ok=True)
    out_img.save(out)
    print(f"{out}: {size[0]} x {size[1]} px from {cw} x {ch} at y {top}")


if __name__ == "__main__":
    main()
