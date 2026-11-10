#!/usr/bin/env python3
"""Lengthen a weapon's shaft in a generated picture by repeating a plain stretch of it.

The shaft is a straight line, y = Y0 + (x - X0) * (Y1 - Y0) / (X1 - X0) in source pixels, and
everything within --band pixels of it (up and down) belongs to it. The cap at its end, from the
end's x to --cap, is cut out, the plain stretch between --segment's two x's is laid along the line
again and again outward over --length pixels (measured across, in x), and the cap goes back on at
the new end. The end may be the shaft's left (the default) or its right one (--right). Past the
picture's edge the canvas grows by --pad (magenta), so a frames file placing the picture by its
bottom-right corner must take SX + PAD with --pad on the left.

  tools/extend_shaft.py art/spear/sweep-follow-long-2.png art/spear/sweep-follow-long-2-haft.png \\
      --axis 80,712.5,240,738 --end 38 --cap 72 --segment 90,230 --band 22 --length 200 --pad 200
  tools/extend_shaft.py art/spear/sweep-windup-long-2.png art/spear/sweep-windup-long-2-haft.png \\
      --axis 440,885,500,869 --end 422 --cap 448 --segment 452,530 --band 22 --length 200
"""
import argparse
from PIL import Image


def is_background(p):
    r, g, b = p[:3]
    return r > 200 and g < 90 and b > 200


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("src")
    ap.add_argument("out")
    ap.add_argument("--axis", required=True, help="X0,Y0,X1,Y1: two points on the shaft's centre line")
    ap.add_argument("--end", type=float, required=True, help="x of the shaft's end (the cap's tip)")
    ap.add_argument("--cap", type=float, required=True, help="x where the cap piece stops")
    ap.add_argument("--segment", required=True, help="S0,S1: x range of a plain stretch of shaft to repeat")
    ap.add_argument("--band", type=float, default=22, help="pixels up and down from the line that are the shaft")
    ap.add_argument("--length", type=int, required=True, help="pixels across to lengthen it by")
    ap.add_argument("--pad", type=int, default=0, help="pixels of canvas added beyond that end")
    ap.add_argument("--right", action="store_true", help="the end is the shaft's right one")
    args = ap.parse_args()

    x0, y0, x1, y1 = (float(v) for v in args.axis.split(","))
    slope = (y1 - y0) / (x1 - x0)
    s0, s1 = (float(v) for v in args.segment.split(","))
    sign = 1 if args.right else -1

    src = Image.open(args.src).convert("RGB")
    w, h = src.size
    pad = args.pad
    shift = 0 if args.right else pad
    canvas = Image.new("RGB", (w + pad, h), (255, 0, 255))
    canvas.paste(src, (shift, 0))
    px = canvas.load()

    def on_shaft(x, y):
        return abs(y - (y0 + (x - shift - x0) * slope)) <= args.band

    def piece(xa, xb):
        """The shaft's pixels with source x in [xa, xb], as (x, y, colour) in canvas pixels."""
        lo, hi = sorted((xa, xb))
        out = []
        for x in range(int(lo) + shift, int(hi) + shift + 1):
            for y in range(h):
                if on_shaft(x, y) and not is_background(px[x, y]):
                    out.append((x, y, px[x, y]))
        return out

    def lay(pixels, dx, limit=None):
        """PIXELS moved DX across along the line; with LIMIT, none past that source x outward."""
        dy = round(dx * slope)
        for x, y, colour in pixels:
            nx, ny = x + dx, y + dy
            if limit is not None and sign * (nx - shift - limit) > 0:
                continue
            if 0 <= nx < canvas.width and 0 <= ny < h:
                px[nx, ny] = colour

    cap = piece(args.end - sign * 2, args.cap)
    segment = piece(s0, s1)
    # Take the old cap off.
    for x, y, _ in cap:
        px[x, y] = (255, 0, 255)
    # Each copy overlaps the last by a fifth, and none reaches past where the cap goes back on.
    width = abs(s1 - s0)
    near = args.cap - (s1 if not args.right else s0)
    limit = args.cap + sign * args.length
    offset = near
    while abs(offset - near) <= args.length:
        lay(segment, int(round(offset)), limit)
        offset += sign * width * 0.8
    lay(cap, sign * args.length)
    canvas.save(args.out)
    print(f"{args.out}: {canvas.width} x {h}, shaft {args.length} px longer, padded {pad}")


if __name__ == "__main__":
    main()
