#!/usr/bin/env python3
"""Give a generated sheet's frames wider cells, so nothing crosses a cyan line.

Generators don't keep a frame inside its cell: a maul held out reaches across the cyan
line, and the slicer, which reads one cell at a time, cuts the maul off in its own frame
and gives the piece that crossed to the next one. This moves each such piece back to the
frame it belongs to and redraws the sheet with cells wide enough for every frame, each
frame's cell centre where it was relative to the frame, so slicing it keeps the sprite's
alignment. The sheets are rewritten in place, and one with nothing crossing is left alone:

  tools/respace_cells.py art/ogre/walk-{front,front-quarter,side,back-quarter,back}.png

A piece that crossed is one not joined to the biggest piece in its cell, touching the line
where the neighbouring cell has something solid at the same height. The columns under the
line were painted over, so they are filled in between the two sides.
"""

import argparse
from collections import deque

import numpy as np
from PIL import Image

from stack_views import CYAN, LINE, MAGENTA, cyan_columns

FRINGE = 2       # columns beside a line that its anti-aliasing reaches
EDGE = 3         # a piece this close to its cell's edge touches the line
MIN_PIECE = 4    # smaller pieces are speckle


def label(mask):
    """8-connected pieces of a boolean array: an array of labels from 1, and their sizes."""
    h, w = mask.shape
    labels = np.zeros((h, w), int)
    sizes = []
    for y, x in zip(*np.nonzero(mask)):
        if labels[y, x]:
            continue
        n = len(sizes) + 1
        labels[y, x] = n
        queue, count = deque([(y, x)]), 0
        while queue:
            cy, cx = queue.popleft()
            count += 1
            for ny in range(max(cy - 1, 0), min(cy + 2, h)):
                for nx in range(max(cx - 1, 0), min(cx + 2, w)):
                    if mask[ny, nx] and not labels[ny, nx]:
                        labels[ny, nx] = n
                        queue.append((ny, nx))
        sizes.append(count)
    return labels, sizes


def solid_mask(a):
    r, g, b = a[:, :, 0], a[:, :, 1], a[:, :, 2]
    cyan = (b > 150) & (g > 150) & (r < 120)
    return ~(cyan | (b > g + 40))


def respace(path):
    img = Image.open(path).convert("RGB")
    a = np.array(img).astype(int)
    h, w, _ = a.shape
    lines = [(max(x0 - FRINGE, 0), min(x1 + FRINGE, w)) for x0, x1 in cyan_columns(img)]
    edges = [(0, 0)] + lines + [(w, w)]
    spans = [(p[1], q[0]) for p, q in zip(edges, edges[1:]) if q[0] - p[1] > 8]
    solid = solid_mask(a)
    # What each frame is made of, in sheet coordinates: a mask over the whole sheet.
    frames = [np.zeros((h, w), bool) for _ in spans]
    moved = []
    for k, (x0, x1) in enumerate(spans):
        cell = solid[:, x0:x1]
        labels, sizes = label(cell)
        main = int(np.argmax(sizes)) + 1 if sizes else 0
        for n, size in enumerate(sizes, 1):
            piece = labels == n
            if n == main:
                frames[k][:, x0:x1] |= piece
                continue
            if size < MIN_PIECE:
                continue
            ys, xs = np.nonzero(piece)
            owner = k
            # Whose is it? The neighbour with something solid across the line from it.
            if k > 0 and xs.min() < EDGE and solid[ys[xs < EDGE], spans[k - 1][1] - 1 - EDGE:spans[k - 1][1]].any():
                owner = k - 1
            elif k < len(spans) - 1 and xs.max() >= x1 - x0 - EDGE \
                    and solid[ys[xs >= x1 - x0 - EDGE], spans[k + 1][0]:spans[k + 1][0] + EDGE + 1].any():
                owner = k + 1
            elif xs.max() - xs.min() < EDGE:
                continue        # a sliver of the line's own anti-aliasing
            frames[owner][:, x0:x1] |= piece
            if owner != k:
                moved.append((k, owner, size))
    if not moved:
        print(f"{path}: nothing crosses a line")
        return
    # Fill the columns under each line a piece crossed, between the two sides.
    out = a.copy()
    for frame in frames:
        for (_, r), (l, _) in zip(spans, spans[1:]):
            for y in np.nonzero(frame[:, r - 1 - EDGE:r].any(axis=1) & frame[:, l:l + EDGE + 1].any(axis=1))[0]:
                left = r - 1 - EDGE + np.nonzero(frame[y, r - 1 - EDGE:r])[0][-1]
                right = l + np.nonzero(frame[y, l:l + EDGE + 1])[0][0]
                for x in range(left + 1, right):
                    t = (x - left) / (right - left)
                    out[y, x] = (1 - t) * a[y, left] + t * a[y, right]
                    frame[y, x] = True
    # Each frame keeps its cell's centre, in a cell wide enough for the widest.
    centres = [(x0 + x1) // 2 for x0, x1 in spans]
    half = 0
    for frame, c in zip(frames, centres):
        xs = np.nonzero(frame.any(axis=0))[0]
        if len(xs):
            half = max(half, c - int(xs.min()), int(xs.max()) + 1 - c)
    half += LINE
    sheet = np.zeros((h, len(spans) * (2 * half + LINE) - LINE, 3), np.uint8)
    sheet[:] = MAGENTA
    for k, (frame, c) in enumerate(zip(frames, centres)):
        x = k * (2 * half + LINE)
        ys, xs = np.nonzero(frame)
        sheet[ys, x + half + xs - c] = out[ys, xs]
        if k:
            sheet[:, x - LINE:x] = CYAN
    Image.fromarray(sheet).save(path)
    for k, owner, size in moved:
        print(f"{path}: cell {k + 1} gave {size} px back to cell {owner + 1}")
    print(f"{path}: cells now {2 * half} px wide")


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("sheets", nargs="+")
    for path in ap.parse_args().sheets:
        respace(path)


if __name__ == "__main__":
    main()
