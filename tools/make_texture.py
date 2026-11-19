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
pixel grid.

A strip (--strip H) is one band of a face, H metres tall and --metres wide, such as a
sarcophagus's side, drawn on a magenta background: it is cropped to what isn't magenta,
scaled to that size and stood on the bottom of a texture --period metres tall (default
1), the rows above filled by repeating its top row. Rows start at y = 0, so on a box
standing on a floor the strip fits the box's sides whatever storey it is on, as long
as --period divides the storey height.

A panel (--panel W --on TEXTURE) is one picture on a wall, W metres wide, such as a doorway,
drawn on a magenta background: it is cropped to what isn't magenta, scaled to that width,
keyed and stood on the bottom middle of a texture --metres wide and --period tall, over the
wall TEXTURE repeated as it would lie there, its rows and columns starting at the bottom left.
Walls lie on the world's grid and rows start at y = 0, so it stays in place on a wall whose
middle is a cell's as long as --metres is the cell's size and --period divides the storey height.

The house style ("House style" in CLAUDE.md) ends with --contrast (the lightness spread about
its mean, times this: generated surfaces come out flatter than the sprites), --tone (the mean
colour moved to a CIE a* b*, so the stones of one dungeon are one family) and --chroma, then
--palette, the master palette in place of --colors' own.

A stained-glass pane (--glass W H) is one window drawn on magenta, W by H metres, as
glass.lisp lays it on a pane: cropped to what isn't magenta and scaled to W x H x 64, its lead
(near black in every channel, and any magenta inside the panel, such as a lancet's corners outside its arch) one
dark opaque colour, alpha 255, and its glass each texel's average over its glass alone, so the
lead doesn't darken the pieces' edges, on the --palette, alpha 128: the shader tells lead from
glass by it. It prints the glass's commonest colours, for the shards' ramps (*GLASS-LOOKS*).

It also cuts the pane into the pieces it shatters into (glass.lisp's shards): each piece of glass
between the lead, the big ones cracked into pieces of about --piece texels, each taking the lead
within a texel or two of it, so a shard has lead on its edges. What stays in the frame when the
pane breaks is piece 0: its frame (the lead joined to its outer edge: the border, a lancet's
corners outside its arch, a rose's round its circle), jagged teeth of glass along it (up to
--teeth texels) and lead too thick to go with any piece. --frame N first turns the glass within N
texels of the frame into lead, so it reads as a frame (the rose window's). Written as
<out dir>/glass/<name>-pieces.png, each texel's piece in red + 256 x green, rows as the texture's,
and <name>.lisp, the pieces' boxes in texels from the bottom left, (X0 Y0 X1 Y1) inclusive.

--brightness scales every colour first, for a generated surface that came
out too light or dark beside the rest of the level. Writes <out>.png and, beside the source, <source stem>-tiled.png: the
texture 3 x 3 at 4x zoom, to check the seams by eye. It prints how far the wrapped
edges differ from neighbouring rows inside the tile (1.0: no more than any two rows).
"""

import argparse
from pathlib import Path

import numpy as np
from PIL import Image, ImageChops, ImageStat

from pixelart import adjust_tone, quantize_to_palette, read_palette

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


def make_strip(src, args):
    """The strip texture of SRC, a band drawn on magenta, as --strip describes."""
    w, h = src.size
    px = src.load()
    keyed = lambda c: c[0] > 180 and c[2] > 180 and c[1] < 90
    rows = [y for y in range(h) if sum(not keyed(px[x, y]) for x in range(0, w, 4)) > w // 16]
    band = src.crop((0, rows[0], w, rows[-1] + 1))
    width = round(args.metres * PIXELS_PER_METRE)
    tall = round(args.strip * PIXELS_PER_METRE)
    period = round(args.period * PIXELS_PER_METRE)
    strip = band.resize((width, tall), Image.BOX)
    if args.brightness != 1.0:
        strip = strip.point(lambda v: min(255, round(v * args.brightness)))
    if args.colors:
        strip = strip.quantize(args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    tex = Image.new("RGB", (width, period))
    for y in range(period - tall):
        tex.paste(strip.crop((0, 0, width, 1)), (0, y))
    tex.paste(strip, (0, period - tall))
    return tex


def make_panel(src, args):
    """The panel texture of SRC, a picture drawn on magenta, as --panel describes."""
    picture = src.convert("RGBA")
    px = picture.load()
    for x in range(picture.width):
        for y in range(picture.height):
            r, g, b, _ = px[x, y]
            if r > 150 and b > 150 and g < 120:
                px[x, y] = (r, g, b, 0)
    picture = picture.crop(picture.getchannel("A").point(lambda a: 255 if a else 0).getbbox())
    width = round(args.panel * PIXELS_PER_METRE)
    tall = round(picture.height * width / picture.width)
    picture = picture.resize((width, tall), Image.BOX)
    solid = picture.getchannel("A").point(lambda a: 255 if a >= 128 else 0)
    rgb = picture.convert("RGB")
    if args.brightness != 1.0:
        rgb = rgb.point(lambda v: min(255, round(v * args.brightness)))
    if args.colors:
        rgb = rgb.quantize(args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    wall = Image.open(args.on).convert("RGB")
    size = (round(args.metres * PIXELS_PER_METRE), round(args.period * PIXELS_PER_METRE))
    tex = Image.new("RGB", size)
    for x in range(0, size[0], wall.width):
        for y in range(size[1] - wall.height, -wall.height, -wall.height):
            tex.paste(wall, (x, y))
    tex.paste(rgb, ((size[0] - width) // 2, size[1] - tall), solid)
    return tex


def frame_of(lead):
    """The frame of a pane whose lead is LEAD: the lead joined to its outer edge (a lancet's corners
    outside its arch, a rose's round its circle), and each texel's distance from it, in steps."""
    from collections import deque
    h, w = lead.shape
    # Every lead line is joined to the border, so only thick lead counts: lead that keeps a texel
    # after eroding a texel away on every side (thin lines don't), grown back, and the two
    # outermost rows and columns.
    core = lead.copy()
    core[1:, :] &= lead[:-1, :]; core[:-1, :] &= lead[1:, :]
    core[:, 1:] &= lead[:, :-1]; core[:, :-1] &= lead[:, 1:]
    thick = core.copy()
    thick[1:, :] |= core[:-1, :]; thick[:-1, :] |= core[1:, :]
    thick[:, 1:] |= core[:, :-1]; thick[:, :-1] |= core[:, 1:]
    thick &= lead
    ys, xs = np.mgrid[0:h, 0:w]
    thick |= lead & (np.minimum(np.minimum(ys, h - 1 - ys), np.minimum(xs, w - 1 - xs)) <= 1)
    frame = np.zeros((h, w), dtype=bool)
    todo = deque((y, x) for y in range(h) for x in range(w)
                 if (y in (0, h - 1) or x in (0, w - 1)) and thick[y, x])
    for c in todo:
        frame[c] = True
    while todo:
        y, x = todo.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (y + dy, x + dx)
            if 0 <= n[0] < h and 0 <= n[1] < w and thick[n] and not frame[n]:
                frame[n] = True
                todo.append(n)
    dist = np.full((h, w), 10 ** 6, dtype=np.int64)
    todo = deque(zip(*np.nonzero(frame)))
    for c in todo:
        dist[c] = 0
    while todo:
        y, x = todo.popleft()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            n = (y + dy, x + dx)
            if 0 <= n[0] < h and 0 <= n[1] < w and dist[n] > dist[y, x] + 1:
                dist[n] = dist[y, x] + 1
                todo.append(n)
    return frame, dist


def cut_pieces(lead, frame, dist, args):
    """Cut a pane of H x W texels, LEAD true where it is lead, FRAME where that lead is its frame
    and DIST each texel's distance from it, into the pieces it shatters into, and write their map
    and boxes (see --glass)."""
    import random
    from collections import deque
    rnd = random.Random(args.seed)
    h, w = lead.shape
    piece = np.full((h, w), -1, dtype=np.int64)
    # The frame's teeth: the glass within a jagged depth of the frame, 1 to --teeth texels, the
    # depth a blocky noise over the pane, so the teeth run round an arch or a circle as along a side.
    step = 3
    grid = [[rnd.randint(1, args.teeth) for _ in range(w // step + 2)] for _ in range(h // step + 2)]
    teeth = np.zeros((h, w), dtype=bool)
    for y in range(h):
        for x in range(w):
            gy, gx, fy, fx = y // step, x // step, (y % step) / step, (x % step) / step
            depth = ((grid[gy][gx] * (1 - fx) + grid[gy][gx + 1] * fx) * (1 - fy)
                     + (grid[gy + 1][gx] * (1 - fx) + grid[gy + 1][gx + 1] * fx) * fy)
            teeth[y, x] = not lead[y, x] and dist[y, x] <= round(depth)
    def neighbours(y, x):
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            if 0 <= y + dy < h and 0 <= x + dx < w:
                yield y + dy, x + dx
    def components(mask):
        seen = np.zeros_like(mask)
        out = []
        for y in range(h):
            for x in range(w):
                if mask[y, x] and not seen[y, x]:
                    cells, todo = [], deque([(y, x)])
                    seen[y, x] = True
                    while todo:
                        c = todo.popleft()
                        cells.append(c)
                        for n in neighbours(*c):
                            if mask[n] and not seen[n]:
                                seen[n] = True
                                todo.append(n)
                    out.append(cells)
        return out
    pieces = []
    for cells in components(~lead & ~teeth):
        k = max(1, round(len(cells) / args.piece))
        if k == 1:
            pieces.append(cells)
            continue
        # Cracked: each texel to the nearest of K points scattered over it, a little jittered so
        # the cracks run crooked, then each part's own connected parts.
        seeds = rnd.sample(cells, k)
        part = {}
        for (y, x) in cells:
            part[(y, x)] = min(range(k), key=lambda i: (seeds[i][0] - y) ** 2 + (seeds[i][1] - x) ** 2
                               + rnd.uniform(0, 6))
        for i in range(k):
            mask = np.zeros((h, w), dtype=bool)
            for c, j in part.items():
                if j == i:
                    mask[c] = True
            pieces.extend(components(mask))
    # Crumbs of a texel or two join a neighbouring piece, or fly on their own.
    for i, cells in enumerate(pieces):
        for c in cells:
            piece[c] = i
    for i, cells in enumerate(pieces):
        if len(cells) <= 2:
            for c in cells:
                near = [piece[n] for n in neighbours(*c) if piece[n] >= 0 and piece[n] != i]
                piece[c] = near[0] if near else i
    # Each piece takes the lead within two texels of it, so its edges are leaded.
    for _ in range(2):
        grow = piece.copy()
        for y in range(h):
            for x in range(w):
                if piece[y, x] < 0 and lead[y, x] and not frame[y, x]:
                    near = [piece[n] for n in neighbours(y, x) if piece[n] >= 0]
                    if near:
                        grow[y, x] = near[0]
        piece = grow
    # Number them from 1, 0 being what stays in the frame.
    ids = sorted({int(i) for i in piece.ravel() if i >= 0})
    renumber = {old: new + 1 for new, old in enumerate(ids)}
    final = np.zeros((h, w), dtype=np.int64)
    boxes = {}
    for y in range(h):
        for x in range(w):
            if piece[y, x] >= 0:
                n = renumber[int(piece[y, x])]
                final[y, x] = n
                by = h - 1 - y  # From the bottom, as the texture's rows are read.
                b = boxes.setdefault(n, [x, by, x, by])
                b[0], b[1], b[2], b[3] = min(b[0], x), min(b[1], by), max(b[2], x), max(b[3], by)
    out = Path(args.out)
    folder = out.parent / "glass"
    folder.mkdir(parents=True, exist_ok=True)
    rgba = np.zeros((h, w, 4), dtype=np.uint8)
    rgba[..., 0] = final & 255
    rgba[..., 1] = final >> 8
    rgba[..., 3] = 255
    Image.fromarray(rgba, "RGBA").save(folder / f"{out.name}-pieces.png")
    with open(folder / f"{out.name}.lisp", "w") as f:
        f.write(";; Written by tools/make_texture.py --glass: the pane's pieces, (X0 Y0 X1 Y1) in texels\n")
        f.write(";; from the bottom left, inclusive, piece 1 first.\n")
        f.write(f"(:width {w} :height {h} :pieces (\n")
        for n in range(1, len(ids) + 1):
            f.write(" (%d %d %d %d)\n" % tuple(boxes[n]))
        f.write("))\n")
    print(f"{len(ids)} pieces; {round(100 * (final == 0).mean())}% stays in the frame")


def make_glass(src, args):
    """The pane texture of SRC, a window drawn on magenta, as --glass describes."""
    rgb = np.asarray(src.convert("RGB")).astype(np.float64)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    magenta = (r > 150) & (b > 150) & (g < 120)
    ys, xs = np.nonzero(~magenta)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    rgb, magenta = rgb[y0:y1, x0:x1], magenta[y0:y1, x0:x1]
    # Near black in every channel: deep blue and violet glass is dark but not in its own channel.
    lead = magenta | (rgb.max(-1) < args.lead)
    w, h = round(args.glass[0] * PIXELS_PER_METRE), round(args.glass[1] * PIXELS_PER_METRE)
    glass = (~lead).astype(np.float64)
    def down(a):
        return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize((w, h), Image.BOX), dtype=np.float64)
    share = down(glass)
    colour = np.stack([down(rgb[..., c] * glass) for c in range(3)], -1) / np.maximum(share, 1e-6)[..., None]
    if args.brightness != 1.0:
        colour = colour * args.brightness
    tex = Image.fromarray(np.clip(colour, 0, 255).astype(np.uint8), "RGB")
    if args.contrast != 1.0 or args.tone or args.chroma != 1.0:
        tex = adjust_tone(tex, args.contrast, args.tone, args.chroma)
    if args.palette:
        tex = quantize_to_palette(tex, read_palette(args.palette)).convert("RGB")
    out = np.asarray(tex.convert("RGBA")).copy()
    is_lead = share < 0.5
    frame, dist = frame_of(is_lead)
    if args.frame:
        # The frame made thicker: the glass along it turned to lead, so a round window's rim
        # reads as the frame the glass is set in.
        is_lead |= dist <= args.frame
        frame, dist = frame_of(is_lead)
    out[is_lead, :3] = args.lead_colour
    out[..., 3] = np.where(is_lead, 255, 128)
    tex = Image.fromarray(out, "RGBA")
    cut_pieces(is_lead, frame, dist, args)
    counts = {}
    for c in out[~is_lead][:, :3]:
        key = "%02x%02x%02x" % tuple(c)
        counts[key] = counts.get(key, 0) + 1
    common = sorted(counts.items(), key=lambda kv: -kv[1])[:12]
    print("lead %d%%; glass colours: %s" % (round(100 * is_lead.mean()), " ".join(f"{k}:{n}" for k, n in common)))
    return tex


def finish(tex, args):
    """The house style's last steps: --contrast, --tone and --chroma, then the --palette."""
    if args.contrast != 1.0 or args.tone or args.chroma != 1.0:
        tex = adjust_tone(tex, args.contrast, args.tone, args.chroma)
    if args.palette:
        alpha = tex.mode == "RGBA"
        tex = quantize_to_palette(tex, read_palette(args.palette))
        tex = tex if alpha else tex.convert("RGB")
    return tex


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("source")
    ap.add_argument("out", help="output path without extension, e.g. data/textures/wall-stone")
    ap.add_argument("--metres", type=float, required=True, help="metres the texture covers on a side")
    ap.add_argument("--crop", type=int, default=0, help="source pixels to drop on every side first")
    ap.add_argument("--blend", type=int, default=0,
                    help="source pixels cross-faded across the wrapped edges (default 0: none)")
    ap.add_argument("--colors", type=int, default=32, help="palette size (default 32, 0 to keep every colour)")
    ap.add_argument("--strip", type=float, default=0, help="metres tall: the source is a strip on magenta")
    ap.add_argument("--period", type=float, default=1.0, help="metres tall a strip's or panel's texture is (default 1)")
    ap.add_argument("--panel", type=float, default=0, help="metres wide: the source is a picture on magenta")
    ap.add_argument("--on", help="the wall texture a panel stands on")
    ap.add_argument("--brightness", type=float, default=1.0, help="factor every colour is scaled by (default 1)")
    ap.add_argument("--contrast", type=float, default=1.0,
                    help="lightness spread about its mean, times this (CIE L*; house style 1.6)")
    ap.add_argument("--tone", type=float, nargs=2, metavar=("A", "B"),
                    help="move the mean colour to this CIE a* b*, keeping each texel's difference from it")
    ap.add_argument("--chroma", type=float, default=1.0, help="every colour's saturation, times this")
    ap.add_argument("--palette", help="map onto this palette file (art/style/palette.txt) instead of --colors")
    ap.add_argument("--glass", type=float, nargs=2, metavar=("W", "H"),
                    help="metres wide and tall: the source is a stained-glass window on magenta")
    ap.add_argument("--piece", type=int, default=70, help="texels a glass shard is, about (default 70)")
    ap.add_argument("--frame", type=int, default=0,
                    help="texels of glass along the frame made lead, to thicken it (default 0)")
    ap.add_argument("--teeth", type=int, default=5, help="most texels of glass a broken pane keeps along a side (default 5)")
    ap.add_argument("--seed", type=int, default=1, help="the cracks' random seed (default 1)")
    ap.add_argument("--lead", type=float, default=48.0, help="brightest channel under which a source pixel is lead (default 48)")
    ap.add_argument("--key", action="store_true",
                    help="the source is drawn on magenta, which becomes see-through (a bloodroot's roots)")
    args = ap.parse_args()

    src = Image.open(args.source).convert("RGB")
    if args.glass:
        args.lead_colour = (24, 17, 14)
        tex = make_glass(src, args)
        out = Path(args.out).with_suffix(".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        tex.save(out)
        print(f"{out}: {tex.size[0]} x {tex.size[1]} px")
        return
    if args.strip or args.panel:
        tex = finish(make_panel(src, args) if args.panel else make_strip(src, args), args)
        out = Path(args.out).with_suffix(".png")
        out.parent.mkdir(parents=True, exist_ok=True)
        tex.save(out)
        print(f"{out}: {tex.size[0]} x {tex.size[1]} px; seam {seam_ratio(tex):.2f}")
        return
    w, h = src.size
    side = min(w, h) - 2 * args.crop
    left, top = (w - side) // 2, (h - side) // 2
    img = src.crop((left, top, left + side, top + side))
    img = wrap_blend(img, args.blend)

    size = round(args.metres * PIXELS_PER_METRE)
    solid = None
    if args.key:
        # Where at least half a texel's source isn't magenta, it is solid; the magenta under the
        # solid texels' edges is filled with a dark tone of the roots, an outline, not a pink fringe.
        px = img.load()
        mask = Image.new("L", img.size)
        mpx = mask.load()
        for x in range(img.width):
            for y in range(img.height):
                r, g, b = px[x, y]
                if r > 150 and b > 150 and g < 120:
                    mpx[x, y] = 0
                    px[x, y] = (52, 18, 14)
                else:
                    mpx[x, y] = 255
        solid = mask.resize((size, size), Image.BOX).point(lambda a: 255 if a >= 128 else 0)
    tex = img.resize((size, size), Image.BOX)
    if args.brightness != 1.0:
        tex = tex.point(lambda v: min(255, round(v * args.brightness)))
    if args.colors and not args.palette:
        tex = tex.quantize(args.colors, method=Image.Quantize.MEDIANCUT, dither=Image.Dither.NONE).convert("RGB")
    tex = finish(tex, args)
    if solid is not None:
        tex = tex.convert("RGBA")
        tex.putalpha(solid)

    out = Path(args.out).with_suffix(".png")
    out.parent.mkdir(parents=True, exist_ok=True)
    tex.save(out)

    tiled = Image.new("RGB", (size * 3, size * 3), (128, 120, 110))
    for i in range(3):
        for j in range(3):
            tiled.paste(tex, (i * size, j * size), tex if tex.mode == "RGBA" else None)
    source = Path(args.source)
    preview = source.with_name(source.stem + "-tiled.png")
    tiled.resize((size * 12, size * 12), Image.NEAREST).save(preview)
    print(f"{out}: {size} x {size} px; seam {seam_ratio(tex):.2f}; preview {preview}")


if __name__ == "__main__":
    main()
