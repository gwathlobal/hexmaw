#!/usr/bin/env python3
"""Build the first-person shield strip from generated pictures of the shield in hand.

  tools/make_shield.py art/sword-shield/shield-frames.txt data/sprites/sword/shield

The shield is the left half of the sword-and-shield weapon: its own HUD sprite, pinned
to the screen's bottom-left corner as the sword is to the bottom-right. Each frame is
cut from a generated picture (magenta background), scaled to the game's art pixels,
and placed by where one of its source points falls on the screen. The frames file has
one frame per line:

  SOURCE SCALE SX SY X Y [magic]

SOURCE is the picture (relative to the frames file's folder, or the working folder),
SCALE the art pixels per source pixel, and source pixel (SX, SY) lands on screen art
pixel (X, Y), counted from the screen's bottom-left corner, Y up. What falls left of
the screen's edge or below its bottom is kept for --margin art pixels (the game sinks
the sprite that far past the corner, the same as *SWORD-DROP*, and the sway shifts it)
and cut beyond. A trailing "magic" marks a picture whose light isn't fire (the casting hands'
Absorb, healing and ward): only magenta is keyed out, so its blue stays, with --glow every
bright colour stays light, not only fire's, and it keeps its own colours rather than sharing
--colors with the rest. A ; starts a comment.

Every frame shares one cell, sized to hold them all, its bottom-left corner --margin
art pixels past the screen's. Keying is slice_frames.py's (blue well over green is
background). Every frame is box-filtered down, darkened by --brightness, desaturated
by --saturation (but for its fire, with --glow: the casting hands'), and mapped onto one
--colors palette, so the frames match.

--corner right pins the frames to the screen's bottom-right corner instead, for a
weapon held on the right (the spear, data/sprites/spear): X counts leftward from the right edge,
the margin is kept past the right edge and the bottom, and SX is still counted from the
picture's left. Such a strip sits as the sword's does, *SWORD-OVERHANG* and *SWORD-DROP*
art pixels past the corner, so give --margin the same. --side-margin keeps more past the side
edge than the bottom, for a weapon placed by its aim whose pictures reach past the corner (the
spear's sweep); the index then says so (:overhang), and the game sits that strip so far past.

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
        if len(fields) not in (6, 7) or (len(fields) == 7 and fields[6] != "magic"):
            raise SystemExit(f"{path}:{number}: want SOURCE SCALE SX SY X Y [magic]")
        source = Path(fields[0])
        if not source.exists():
            source = base / fields[0]
        frames.append((source, *map(float, fields[1:6]), len(fields) == 7))
    return frames


def keyed(path, magic=False):
    """PATH's picture with its background keyed out: magenta, its blends with the dark outlines, and
    cyan separator lines. With MAGIC (the frame's flag), only magenta and its blends: the picture's
    own blue light (the Absorb void's rim) stays."""
    rgb = np.asarray(Image.open(path).convert("RGB")).astype(int)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    if magic:
        background = (r > g + 40) & (b > g + 40) & (abs(r - b) < 90)
    else:
        background = (b > g + 40) | ((b > 150) & (g > 150) & (r < 120))
    alpha = np.where(background, 0, 255)
    return Image.fromarray(np.dstack([rgb, alpha]).astype(np.uint8), "RGBA")


def glowing(rgb, magic=False):
    """Where RGB (0 to 1) is fire: bright, and orange to yellow or near white. With MAGIC, any
    bright light of any colour (healing's green ribbons, a void's blue rim)."""
    hi, lo = rgb.max(-1), rgb.min(-1)
    sat = (hi - lo) / np.maximum(hi, 1e-6)
    warm = (rgb[..., 0] >= rgb[..., 1]) & (rgb[..., 1] >= rgb[..., 2])
    if magic:
        return (hi > 0.85) & ((sat > 0.3) | (sat < 0.2))
    return (hi > 0.85) & ((warm & (sat > 0.45)) | (sat < 0.2))


def grade(img, brightness, saturation, glow=False, magic=False):
    """Darken and desaturate IMG's opaque pixels; with GLOW, not its fire (or, MAGIC, its light)."""
    a = np.asarray(img).astype(float) / 255
    rgb = a[..., :3]
    keep = glowing(rgb, magic) if glow else np.zeros(rgb.shape[:2], bool)
    grey = rgb @ np.array([0.299, 0.587, 0.114])
    graded = grey[..., None] + (rgb - grey[..., None]) * saturation
    graded = np.clip(graded * brightness, 0, 1)
    rgb = np.where(keep[..., None], rgb, graded)
    out = np.dstack([rgb, a[..., 3:]]) * 255
    return Image.fromarray(np.round(out).astype(np.uint8), "RGBA")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("frames", help="frames file")
    ap.add_argument("out", help="output strip, without extension")
    ap.add_argument("--margin", type=int, default=6, help="art pixels kept past the screen's left and bottom edges")
    ap.add_argument("--side-margin", type=int, default=None,
                    help="art pixels kept past the side edge instead (default --margin); written into the index as :overhang")
    ap.add_argument("--brightness", type=float, default=0.8)
    ap.add_argument("--saturation", type=float, default=0.8)
    ap.add_argument("--colors", type=int, default=48)
    ap.add_argument("--glow", action="store_true",
                    help="leave fire (bright orange to yellow, and near white) out of --brightness and --saturation")
    ap.add_argument("--corner", choices=("left", "right"), default="left",
                    help="screen corner the frames are pinned to")
    args = ap.parse_args()
    # A right-corner strip is built as a left-corner one from mirrored pictures, then
    # mirrored back.
    mirror = args.corner == "right"
    side = args.margin if args.side_margin is None else args.side_margin

    placed = []   # (image, left, top) in screen art pixels, Y down from the screen's bottom
    for source, scale, sx, sy, x, y, magic in read_frames(args.frames):
        img = keyed(source, magic)
        if mirror:
            img = img.transpose(Image.Transpose.FLIP_LEFT_RIGHT)
            sx = img.width - sx
        w, h = round(img.width * scale), round(img.height * scale)
        small = grade(box_downscale(img, (w, h)), args.brightness, args.saturation, args.glow, magic)
        left, top = round(x - sx * scale), round(-y - sy * scale)
        # Keep only what shows: past the margins nothing is drawn.
        small = small.crop((max(0, -side - left), 0, small.width, min(small.height, args.margin - top)))
        left = max(left, -side)
        bbox = small.getbbox()
        placed.append((small.crop(bbox), left + bbox[0], top + bbox[1], magic))

    right = max(left + img.width for img, left, _, _ in placed)
    top = min(top for _, _, top, _ in placed)
    cell_w, cell_h = right + side, args.margin - top
    cells = []
    for img, left, top_y, _ in placed:
        # The cell's top-left corner is at screen (-side, top); anything past it is cut.
        cell = Image.new("RGBA", (cell_w, cell_h), (0, 0, 0, 0))
        cell.paste(img, (left + side, top_y - top), img)
        cells.append(cell.transpose(Image.Transpose.FLIP_LEFT_RIGHT) if mirror else cell)

    # The fire's frames share --colors colours; a magic frame keeps its own (the house palette maps
    # them later): squeezed in with the fire, a void's few blues became greys and yellows.
    strip = Image.new("RGBA", (len(cells) * (cell_w + GAP) - GAP, cell_h), (0, 0, 0, 0))
    for i, (cell, (_, _, _, magic)) in enumerate(zip(cells, placed)):
        if not magic:
            strip.paste(cell, (i * (cell_w + GAP), 0))
    strip = reduce_colors(strip, args.colors)
    for i, (cell, (_, _, _, magic)) in enumerate(zip(cells, placed)):
        if magic:
            strip.paste(cell, (i * (cell_w + GAP), 0))
    out = Path(args.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    strip.save(out.with_suffix(".png"))
    out.with_suffix(".lisp").write_text(
        f";;; Written by tools/make_shield.py from {Path(args.frames).name}; do not edit.\n"
        f'(:image "{out.name}.png"\n'
        f" :cell-width {cell_w} :cell-height {cell_h} :gap {GAP}\n"
        f" :frames {len(cells)}"
        + (f" :overhang {side}" if args.side_margin is not None else "")
        + ")\n")
    print(f"{len(cells)} frames, {cell_w} x {cell_h} cells, {out.with_suffix('.png')}")


if __name__ == "__main__":
    main()
