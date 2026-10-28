#!/usr/bin/env python3
"""Slice a generated animation sheet into per-animation frame strips.

The sheet is a grid of frames on a magenta background, separated by cyan lines.
Rows don't need to line up between each other, cells can differ in size, and a
cell left empty (often the tail of the last row) is skipped. Frames are read in
reading order and handed out to the animations named on the command line:

  tools/slice_frames.py "Bolt Spell Sheet.webp" data/sprites/bolt --pixel 5 flight:5 burst:7

writes, for each animation,

  <out>/<name>.png   one row of frames, left to right, 2 px transparent gaps
  <out>/<name>.lisp  index the game reads: cell size, gap, frame count

Every frame of an animation is cut with the same crop around its cell's centre,
so the sprite doesn't jitter when the game steps through them. --anchor bottom is
for first-person HUD sprites (hands, weapons) whose arms are cut off by the screen
edge: each frame is still centred horizontally on its cell, but its lowest solid row
goes on the strip's bottom edge, wherever the generator happened to cut the arms. --pixel is the
size of one art pixel in the sheet (generated pixel art is upscaled); the frames
are downscaled by it with nearest-neighbour, the same for all animations, so
their sizes stay comparable. Generated art is often noisy below its pixel grid; --filter box
averages each art pixel's source pixels instead of picking one, and --colors N maps every
frame of an animation onto one N-colour palette taken from its own pixels, which merges
the speckle into flat pixel-art colours.

Keying removes the magenta and the soft glow that generators paint into it:
fire, embers and smoke never have much more blue than green, a magenta blend
always does. A bright magenta-tinted rim still touching the background (the halo
of a glow the generator blended into it) is cut away too, and what's left of the
blend inside the sprite (pink edges, mauve smoke) is despilled.
"""

import argparse
import math
from pathlib import Path

from PIL import Image

GAP = 2


def is_cyan(r, g, b):
    return b > 150 and g > 150 and r < 120


def is_background(r, g, b):
    return is_cyan(r, g, b) or b > g + 40


def is_spill(r, g, b):
    """Bright pink: the outer halo of a glow painted into the background. Fire keeps
    blue far below green, pale highlights keep red near green, and dark outlines
    (which stop the cut) are too dark."""
    return b > 120 and b >= g - 16 and r > g + 24


def cut_rims(img):
    """Clear spill pixels reachable from the cleared background."""
    w, h = img.size
    px = img.load()
    todo = [(x, y) for y in range(h) for x in range(w) if px[x, y][3] == 0]
    while todo:
        x, y = todo.pop()
        for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
            if 0 <= nx < w and 0 <= ny < h:
                r, g, b, a = px[nx, ny]
                if a and is_spill(r, g, b):
                    px[nx, ny] = (0, 0, 0, 0)
                    todo.append((nx, ny))


def runs(indices):
    """Group sorted integers into [first, last] runs of consecutive values."""
    out = []
    for i in indices:
        if out and i == out[-1][1] + 1:
            out[-1][1] = i
        else:
            out.append([i, i])
    return out


def spans(lines, length):
    """The (start, end) spans between separator runs, inclusive, ignoring slivers."""
    edges = [-1] + [e for run in runs(lines) for e in run] + [length]
    return [(edges[i] + 1, edges[i + 1] - 1)
            for i in range(0, len(edges), 2) if edges[i + 1] - edges[i] > 20]


def cells(img):
    """(left, top, right, bottom) of every cell, in reading order."""
    w, h = img.size
    px = img.load()
    rows = [y for y in range(h)
            if sum(1 for x in range(0, w, 4) if is_cyan(*px[x, y][:3])) > (w // 4) * 0.5]
    out = []
    for top, bottom in spans(rows, h):
        cols = [x for x in range(w)
                if sum(1 for y in range(top, bottom + 1, 4) if is_cyan(*px[x, y][:3]))
                > ((bottom - top) // 4) * 0.5]
        out += [(left, top, right, bottom) for left, right in spans(cols, w)]
    return out


def solid_bottom(frame):
    """Index of the lowest row of FRAME with a solid run of opaque pixels, ignoring
    stray specks left by keying."""
    w, h = frame.size
    alpha = frame.getchannel("A").load()
    need = max(3, w // 50)
    for y in range(h - 1, -1, -1):
        if sum(1 for x in range(w) if alpha[x, y]) >= need:
            return y
    return h - 1


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheet")
    ap.add_argument("out", help="output directory")
    ap.add_argument("animations", nargs="+", metavar="NAME:FRAMES",
                    help="animations in sheet order, with their frame counts")
    ap.add_argument("--pixel", type=float, default=1.0, help="source pixels per art pixel (default 1)")
    ap.add_argument("--anchor", choices=("center", "bottom"), default="center",
                    help="keep each frame's cell centre in place, or put its lowest solid row on the bottom edge")
    ap.add_argument("--ground-like", action="append", default=[], metavar="FRAME:REF",
                    help="with --anchor bottom, put frame FRAME (numbered from 1 over the whole sheet) on the "
                         "ground of frame REF in the same row instead of its own solid bottom, for a frame "
                         "with something (a blood pool) reaching below the ground line; repeatable")
    ap.add_argument("--margin", type=int, default=4, help="source pixels to skip next to each separator")
    ap.add_argument("--exact", action="store_true",
                    help="the sheet is a render on pure magenta (255, 0, 255): key only that, with no "
                         "rim cut or despill, which would eat a render's outlines and bluish steel")
    ap.add_argument("--filter", choices=("nearest", "box"), default="nearest",
                    help="downscale by picking one source pixel per art pixel, or by averaging them")
    ap.add_argument("--colors", type=int, help="reduce each animation to a palette of this many colours")
    ap.add_argument("--min-pixels", type=int, default=50,
                    help="cells with fewer opaque pixels than this after keying are empty")
    args = ap.parse_args()

    animations = []
    for spec in args.animations:
        name, _, count = spec.partition(":")
        animations.append((name, int(count)))

    src = Image.open(args.sheet).convert("RGBA")
    # Find the cells before keying, which erases the cyan separators.
    found = [(l + args.margin, t + args.margin, r - args.margin, b - args.margin) for l, t, r, b in cells(src)]
    px = src.load()
    w, h = src.size
    for y in range(h):
        for x in range(w):
            r, g, b, _ = px[x, y]
            if ((r, g, b) == (255, 0, 255) or is_cyan(r, g, b)) if args.exact else is_background(r, g, b):
                px[x, y] = (0, 0, 0, 0)
    if not args.exact:
        cut_rims(src)
        for y in range(h):
            for x in range(w):
                r, g, b, a = px[x, y]
                if a and b > g:
                    # Despill: edges and smoke blended with magenta turn pink; pull blue down to green.
                    # A dark pixel is an outline blended with magenta: pull red down too, or it
                    # rims the sprite in dark red.
                    px[x, y] = (min(r, g + 24) if r < 96 and b > g + 16 else r, g, g, 255)

    frames = []
    for box in found:
        opaque = sum(1 for a in src.crop(box).getchannel("A").get_flattened_data() if a)
        if opaque >= args.min_pixels:
            frames.append(box)
    wanted = sum(n for _, n in animations)
    if len(frames) != wanted:
        raise SystemExit(f"Found {len(frames)} non-empty cells, expected {wanted}. Cells at {found}")

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    # Ground row of every frame, in sheet coordinates, for --anchor bottom.
    grounds = [t + solid_bottom(src.crop((l, t, r + 1, b + 1))) for l, t, r, b in frames]
    for spec in args.ground_like:
        frame, _, ref = spec.partition(":")
        frame, ref = int(frame) - 1, int(ref) - 1
        grounds[frame] = frames[frame][1] + grounds[ref] - frames[ref][1]

    start = 0
    for name, count in animations:
        boxes = frames[start:start + count]
        bottoms = grounds[start:start + count]
        start += count
        # Shared crop: the largest extent from the cell centre over all frames, or
        # with --anchor bottom, the tallest frame above its solid bottom.
        half_w = half_h = 0
        for i, (l, t, r, b) in enumerate(boxes):
            cell = src.crop((l, t, r + 1, b + 1))
            bbox = cell.getbbox()
            cx, cy = (r - l + 1) / 2, (b - t + 1) / 2   # bounds are inclusive
            half_w = max(half_w, cx - bbox[0], bbox[2] - cx)
            if args.anchor == "bottom":
                half_h = max(half_h, (bottoms[i] - t + 1 - bbox[1]) / 2)
            else:
                half_h = max(half_h, cy - bbox[1], bbox[3] - cy)
        half_w, half_h = math.ceil(half_w), math.ceil(half_h)
        cell_w = max(1, round(2 * half_w / args.pixel))
        cell_h = max(1, round(2 * half_h / args.pixel))
        strip = Image.new("RGBA", (count * cell_w + (count - 1) * GAP, cell_h), (0, 0, 0, 0))
        for i, (l, t, r, b) in enumerate(boxes):
            cx, cy = (l + r + 1) // 2, (t + b + 1) // 2
            if args.anchor == "bottom":
                cy = bottoms[i] + 1 - half_h
            # Take pixels from this cell only: a crop taller than the cell would
            # otherwise pick up the frame in the row above.
            frame = Image.new("RGBA", (2 * half_w, 2 * half_h), (0, 0, 0, 0))
            frame.paste(src.crop((l, t, r + 1, b + 1)), (l - (cx - half_w), t - (cy - half_h)))
            strip.paste(frame.resize((cell_w, cell_h), Image.NEAREST), (i * (cell_w + GAP), 0))
        strip.save(out / f"{name}.png")
        (out / f"{name}.lisp").write_text(
            f";;; Written by tools/slice_frames.py from {Path(args.sheet).name}; do not edit.\n"
            f"(:image \"{name}.png\"\n"
            f" :cell-width {cell_w} :cell-height {cell_h} :gap {GAP}\n"
            f" :frames {count})\n")
        print(f"{out / name}.png: {count} frames of {cell_w}x{cell_h} px "
              f"(source crop {2 * half_w}x{2 * half_h})")


if __name__ == "__main__":
    main()
