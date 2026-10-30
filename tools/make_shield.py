#!/usr/bin/env python3
"""Build the first-person shield strip from generated pictures of the shield in hand.

  tools/make_shield.py art/sword-shield/shield-frames.txt data/sprites/sword/shield

The shield is the left half of the sword-and-shield weapon: its own HUD sprite, pinned
to the screen's bottom-left corner as the sword is to the bottom-right. Each frame is
cut from a generated picture (magenta background), scaled to the game's art pixels,
and placed by where one of its source points falls on the screen. The frames file has
one frame per line:

  SOURCE SCALE SX SY X Y

SOURCE is the picture (relative to the frames file's folder, or the working folder),
SCALE the art pixels per source pixel, and source pixel (SX, SY) lands on screen art
pixel (X, Y), counted from the screen's bottom-left corner, Y up. What falls left of
the screen's edge or below its bottom is kept for --margin art pixels (the game sinks
the sprite that far past the corner, the same as *SWORD-DROP*, and the sway shifts it)
and cut beyond. A ; starts a comment.

Every frame shares one cell, sized to hold them all, its bottom-left corner --margin
art pixels past the screen's. Keying is slice_frames.py's (blue well over green is
background). Every frame is box-filtered down, darkened by --brightness, desaturated
by --saturation, and mapped onto one --colors palette, so the frames match.

--corner right pins the frames to the screen's bottom-right corner instead, for a
weapon held on the right (the spear, data/sprites/spear): X counts leftward from the right edge,
the margin is kept past the right edge and the bottom, and SX is still counted from the
picture's left. Such a strip sits as the sword's does, *SWORD-OVERHANG* and *SWORD-DROP*
art pixels past the corner, so give --margin the same.

Writes <out>.png, the frames in a row with 2 px gaps, and <out>.lisp, the index
define-fx-animation reads.

  tools/make_shield.py --corner right art/spear/spear-frames.txt data/sprites/spear/spear
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image

from pixelart import box_downscale, reduce_colors

GAP = 2


def read_frames(path):
    base = Path(path).parent
    frames = []
    for number, line in enumerate(Path(path).read_text().splitlines(), 1):
        line = line.split(";")[0].strip()
        if not line:
            continue
        fields = line.split()
        if len(fields) != 6:
            raise SystemExit(f"{path}:{number}: want SOURCE SCALE SX SY X Y")
        source = Path(fields[0])
        if not source.exists():
            source = base / fields[0]
        frames.append((source, *map(float, fields[1:])))
    return frames


def keyed(path):
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    background = (b > g + 40) | ((b > 150) & (g > 150) & (r < 120))
    alpha = np.where(background, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def grade(img, brightness, saturation):
    """Darken and desaturate IMG's opaque pixels."""
    a = np.asarray(img).astype(float) / 255
    rgb = a[..., :3]
    grey = rgb @ np.array([0.299, 0.587, 0.114])
    rgb = grey[..., None] + (rgb - grey[..., None]) * saturation
    rgb = np.clip(rgb * brightness, 0, 1)
    out = np.dstack([rgb, a[..., 3:]]) * 255
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("frames", help="frames file")
    ap.add_argument("out", help="output strip, without extension")
    ap.add_argument("--margin", type=int, default=6, help="art pixels kept past the screen's left and bottom edges")
    ap.add_argument("--brightness", type=float, default=0.8)
    ap.add_argument("--saturation", type=float, default=0.8)
    ap.add_argument("--colors", type=int, default=48)
    ap.add_argument("--corner", choices=("left", "right"), default="left",
                    help="screen corner the frames are pinned to")
    args = ap.parse_args()
    # A right-corner strip is built as a left-corner one from mirrored pictures, then
    # mirrored back.
    mirror = args.corner == "right"

    placed = []   # (image, left, top) in screen art pixels, Y down from the screen's bottom
    for source, scale, sx, sy, x, y in read_frames(args.frames):
        img = keyed(source)
        if mirror:
            img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            sx = img.width - sx
        w, h = round(img.width * scale), round(img.height * scale)
        small = grade(box_downscale(img, (w, h)), args.brightness, args.saturation)
        left, top = round(x - sx * scale), round(-y - sy * scale)
        # Keep only what shows: past the margins nothing is drawn.
        m = args.margin
        small = small.crop((max(0, -m - left), 0, small.width, min(small.height, m - top)))
        left = max(left, -m)
        bbox = small.getbbox()
        placed.append((small.crop(bbox), left + bbox[0], top + bbox[1]))

    m = args.margin
    right = max(left + img.width for img, left, _ in placed)
    top = min(top for _, _, top in placed)
    cell_w, cell_h = right + m, m - top
    cells = []
    for img, left, top_y in placed:
        # The cell's top-left corner is at screen (-m, top); anything past it is cut.
        cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
        cell.paste(img, (left + m, top_y - top), img)
        cells.append(cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirror else cell)

    strip = Image.new("RGBA", (len(cells) * (cell_w + GAP) - GAP, cell_h), (0, 0, 0, 0))
    for i, cell in enumerate(cells):
        strip.paste(cell, (i * (cell_w + GAP), 0))
    strip = reduce_colors(strip, args.colors)
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        f";;; Written by tools/make_shield.py from {Path(args.frames).name}; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {cell_w} :cell-height {cell_h} :gap {GAP}\n"
        f" :frames {len(cells)})\n")
    print(f"{len(cells)} frames, {cell_w} x {cell_h} cells, {out.with_suffix('.png')}")


if __name__ == "__main__":
    main()
