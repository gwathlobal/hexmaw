#!/usr/bin/env python3
"""Stack one animation sheet per view into a single sheet for tools/slice_frames.py.

A monster's walk (or any per-view animation) comes from the generator as one sheet per
view: a row of frames on magenta, separated by cyan lines, in the turnaround's view
order (front, front-quarter, side, back-quarter, back). Each sheet is generated on its
own, so the monster comes out a different size in each; this scales every sheet so its
tallest frame is --height pixels, mirrors each frame of the views named in --mirror (in
place, so the frame order stays), and stacks the rows top to bottom with a cyan line
between:

  tools/stack_views.py "art/imp/Imp Walk Sheet.png" front.png front-quarter.png side.png \\
      back-quarter.png back.png --height 768 --mirror 4

tools/slice_views.py stacks and slices in one step without writing the sheet; this tool
is for looking at it.

--mirror takes 1-based input positions. Turned views must face image-left, like the
turnaround; generators don't always draw them that way.

--frame N scales each view by its Nth frame (1-based) instead of its tallest, for an
animation whose tallest frame varies between views (fire held over the head in one view
and beside it in another): name a frame that is the same pose in every view, such as
the standing one, and give its height.

--blank N empties frame N of every view after scaling, so slice_frames skips it: for a
pose drawn only to set the scale. The acolyte's pain sheets open with a copy of the
standing pose, which sets the scale with --frame 1 and is dropped with --blank 1.

--grid reads each sheet as a grid of frames, cyan lines both ways, row by row, and lays
it out as one row first: for poses too wide to fit a row of five (the harpy's spread
wings come as a 2 x 2 grid).
"""

import argparse

from PIL import Image

LINE = 6
CYAN = (0, 255, 255)
MAGENTA = (255, 0, 255)


def is_cyan(r, g, b):
    return b > 150 and g > 150 and r < 120


def is_background(r, g, b):
    return is_cyan(r, g, b) or b > g + 40


def cyan_columns(img):
    """X ranges of the cyan separator columns."""
    w, h = img.size
    px = img.load()
    cols = [sum(is_cyan(*px[x, y]) for y in range(0, h, 4)) > h // 8 for x in range(w)]
    runs, start = [], None
    for x, c in enumerate(cols + [False]):
        if c and start is None:
            start = x
        elif not c and start is not None:
            runs.append((start, x))
            start = None
    return runs


def cells(img):
    """X ranges of the frames between separators."""
    edges = [(0, 0)] + cyan_columns(img) + [(img.width, img.width)]
    return [(a[1], b[0]) for a, b in zip(edges, edges[1:]) if b[0] - a[1] > 8]


def cyan_rows(img):
    """Y ranges of the cyan separator rows."""
    return cyan_columns(img.transpose(Image.TRANSPOSE))


def ungrid(img):
    """A grid of frames as one row: its rows' cells side by side, cyan lines between."""
    edges = [(0, 0)] + cyan_rows(img) + [(img.height, img.height)]
    bands = [img.crop((0, a[1], img.width, b[0])) for a, b in zip(edges, edges[1:]) if b[0] - a[1] > 8]
    frames = [band.crop((x0, 0, x1, band.height)) for band in bands for x0, x1 in cells(band)]
    height = max(f.height for f in frames)
    out = Image.new("RGB", (sum(f.width for f in frames) + LINE * (len(frames) - 1), height), MAGENTA)
    x = 0
    for k, frame in enumerate(frames):
        if k:
            out.paste(CYAN, (x, 0, x + LINE, height))
            x += LINE
        out.paste(frame, (x, 0))
        x += frame.width
    return out


def sprite_height(img, frame=None):
    """Height of the tallest frame, or of FRAME (0-based) alone."""
    spans = cells(img) if frame is None else [cells(img)[frame]]
    # Inside the cells only: a separator's anti-aliased end can miss is_cyan.
    xs = [x for x0, x1 in spans for x in range(x0 + 3, x1 - 3, 2)]
    px = img.load()
    rows = [y for y in range(img.height) if any(not is_background(*px[x, y]) for x in xs)]
    return rows[-1] - rows[0] + 1


def add_stack_arguments(ap):
    ap.add_argument("--height", type=int, required=True, help="tallest frame of every view, in pixels")
    ap.add_argument("--frame", type=int, help="1-based frame to scale by, at --height, instead of the tallest")
    ap.add_argument("--mirror", type=int, nargs="*", default=[], help="1-based inputs to mirror frame by frame")
    ap.add_argument("--blank", type=int, nargs="*", default=[], help="1-based frames to empty in every view")
    ap.add_argument("--grid", action="store_true", help="each input is a grid of frames, read row by row")


def stack(args):
    """The stacked sheet of ARGS.inputs, as an RGB image."""
    rows = []
    for n, path in enumerate(args.inputs, 1):
        img = Image.open(path).convert("RGB")
        if args.grid:
            img = ungrid(img)
        if n in args.mirror:
            for x0, x1 in cells(img):
                img.paste(img.crop((x0, 0, x1, img.height)).transpose(Image.FLIP_LEFT_RIGHT), (x0, 0))
        scale = args.height / sprite_height(img, None if args.frame is None else args.frame - 1)
        for frame in args.blank:
            x0, x1 = cells(img)[frame - 1]
            img.paste(MAGENTA, (x0, 0, x1, img.height))
        # Nearest keeps the key colours pure; slice_frames does the real downscaling.
        rows.append(img.resize((round(img.width * scale), round(img.height * scale)), Image.NEAREST))

    width = max(r.width for r in rows)
    out = Image.new("RGB", (width, sum(r.height for r in rows) + LINE * (len(rows) - 1)), MAGENTA)
    y = 0
    for k, row in enumerate(rows):
        if k:
            out.paste(CYAN, (0, y, width, y + LINE))
            y += LINE
        out.paste(row, (0, y))
        # Close a narrower row with cyan, or its last frame's cell runs on to the edge.
        if row.width < width:
            out.paste(CYAN, (row.width, y, width, y + row.height))
        y += row.height
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("output")
    ap.add_argument("inputs", nargs="+")
    add_stack_arguments(ap)
    args = ap.parse_args()

    out = stack(args)
    out.save(args.output)
    print(f"{args.output}: {len(args.inputs)} views, {out.width} x {out.height}")


if __name__ == "__main__":
    main()
