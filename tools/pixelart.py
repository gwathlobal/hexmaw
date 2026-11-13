"""Downscaling and palette helpers shared by the slicing tools.

Generated pixel art is upscaled and noisy below its pixel grid: picking one source
pixel per art pixel (nearest-neighbour) turns that noise into speckle. box_downscale
averages instead, and reduce_colors flattens what's left onto one palette.
"""

import math

import numpy as np
from PIL import Image


def box_bounds(n, src_n):
    """Start and end (exclusive) in the source of each of N output pixels along an axis
    of SRC_N source pixels: every source pixel the output pixel touches, at least one."""
    i = np.arange(n)
    start = (i * src_n / n).astype(int)
    end = np.maximum(start + 1, [math.ceil((k + 1) * src_n / n) for k in i])
    return start, np.minimum(end, src_n)


def box_downscale(img, size):
    """Average the source pixels under each output pixel. A pixel is opaque when at least
    half the source under it is, and takes the mean colour of the opaque ones."""
    src = np.asarray(img.convert("RGBA"), dtype=np.float64)
    (w, h), (sw, sh) = size, img.size
    solid = (src[:, :, 3] > 0).astype(np.float64)
    # Summed-area tables of the opaque pixels' count and colour, padded with a zero row
    # and column, so any block's sum is four lookups.
    layers = np.concatenate([solid[:, :, None], src[:, :, :3] * solid[:, :, None]], axis=2)
    table = np.zeros((sh + 1, sw + 1, 4))
    table[1:, 1:] = layers.cumsum(axis=0).cumsum(axis=1)
    y0, y1 = box_bounds(h, sh)
    x0, x1 = box_bounds(w, sw)
    sums = (table[y1][:, x1] - table[y0][:, x1] - table[y1][:, x0] + table[y0][:, x0])
    count, area = sums[:, :, 0], np.outer(y1 - y0, x1 - x0)
    opaque = count * 2 >= area
    out = np.zeros((h, w, 4), dtype=np.uint8)
    mean = sums[:, :, 1:] / np.maximum(count, 1)[:, :, None]
    out[:, :, :3] = np.where(opaque[:, :, None], mean.round(), 0)
    out[:, :, 3] = np.where(opaque, 255, 0)
    return Image.fromarray(out, "RGBA")


def reduce_colors(img, colors):
    """Map the opaque pixels onto one palette of COLORS colours taken from them (median
    cut, no dither). Transparent pixels stay transparent."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    solid = rgba[:, :, 3] > 0
    if not solid.any():
        return img
    pixels = Image.fromarray(rgba[solid][:, :3].reshape(1, -1, 3), "RGB")
    palette = pixels.quantize(colors=colors, method=Image.MEDIANCUT)
    mapped = Image.fromarray(rgba[:, :, :3], "RGB").quantize(palette=palette, dither=Image.NONE)
    rgba[:, :, :3] = np.asarray(mapped.convert("RGB"))
    rgba[~solid] = 0
    return Image.fromarray(rgba, "RGBA")


def read_palette(path):
    """The colours of a palette file (tools/make_palette.py: a ramp a line, hex colours), as an
    N x 3 uint8 array."""
    import re
    colours = []
    for line in open(path):
        if line.lstrip().startswith("#"):
            continue
        colours += [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4))
                    for h in re.findall(r"\b([0-9a-fA-F]{6})\b", line)]
    return np.array(colours, dtype=np.uint8)


def _lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], -1)


def quantize_to_palette(img, palette):
    """Map IMG's opaque pixels onto PALETTE (read_palette), each to the nearest colour in CIE
    Lab, with no dither. Transparent pixels stay transparent; part-transparent ones become
    opaque or clear at half alpha, as the game's shader cuts them."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    solid = rgba[:, :, 3] >= 128
    pal_lab = _lab(palette.astype(np.float64))
    px = rgba[solid][:, :3]
    keys, inverse = np.unique(px.astype(np.int64) @ np.array([65536, 256, 1]), return_inverse=True)
    unique = np.stack([keys >> 16, (keys >> 8) & 255, keys & 255], 1).astype(np.float64)
    lab = _lab(unique)
    pick = np.empty(len(unique), dtype=np.int64)
    for s in range(0, len(unique), 20000):
        pick[s:s + 20000] = ((lab[s:s + 20000, None, :] - pal_lab[None]) ** 2).sum(2).argmin(1)
    rgba[solid, :3] = palette[pick[inverse.ravel()]]
    rgba[solid, 3] = 255
    rgba[~solid] = 0
    return Image.fromarray(rgba, "RGBA")


def _rgb(lab):
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], -1)
    xyz = np.where(f > 0.206893, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = np.clip(xyz @ m.T, 0, 1)
    c = np.where(c > 0.0031308, 1.055 * c ** (1 / 2.4) - 0.055, 12.92 * c)
    return np.clip(np.round(c * 255), 0, 255).astype(np.uint8)


def adjust_tone(img, contrast=1.0, tone=None, chroma=1.0):
    """Change IMG's opaque pixels in CIE Lab: lightness spread CONTRAST times as far about its
    mean, the colour's mean moved to TONE (a*, b*) if given, keeping each pixel's difference
    from it, and every colour's chroma times CHROMA."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    solid = rgba[:, :, 3] > 0
    if not solid.any():
        return img
    lab = _lab(rgba[solid][:, :3].astype(np.float64))
    mean = lab.mean(0)
    lab[:, 0] = np.clip(mean[0] + contrast * (lab[:, 0] - mean[0]), 0, 100)
    if tone is not None:
        lab[:, 1:] += np.array(tone) - mean[1:]
    lab[:, 1:] *= chroma
    rgba[solid, :3] = _rgb(lab)
    return Image.fromarray(rgba, "RGBA")


def selout(img, darken=0.45, below=25.0):
    """Turn the near-black outline round IMG's shape (an opaque pixel beside a transparent one,
    lightness under BELOW) into a dark tone of what it borders: the mean of its inner neighbours
    at DARKEN of their lightness. Pixel artists' "selective outline": the shape keeps its edge
    without a black line round it that nothing in the level has."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    opaque = rgba[:, :, 3] > 0
    clear = ~opaque
    near = np.zeros_like(clear)
    near[1:] |= clear[:-1]; near[:-1] |= clear[1:]; near[:, 1:] |= clear[:, :-1]; near[:, :-1] |= clear[:, 1:]
    edge = opaque & near
    lab = _lab(rgba[:, :, :3].astype(np.float64))
    target = edge & (lab[:, :, 0] < below)
    inner = opaque & ~edge
    total = np.zeros(lab.shape)
    count = np.zeros(lab.shape[:2])
    for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (1, -1), (-1, 1), (-1, -1)):
        shifted = np.roll(np.roll(lab, dy, 0), dx, 1)
        ok = np.roll(np.roll(inner, dy, 0), dx, 1)
        total += shifted * ok[..., None]
        count += ok
    has = target & (count > 0)
    mean = total[has] / count[has][:, None]
    mean[:, 0] *= darken
    mean[:, 1:] *= 0.85
    rgba[has, :3] = _rgb(mean)
    return Image.fromarray(rgba, "RGBA")


HOUSE_PALETTE = __import__("pathlib").Path(__file__).resolve().parent.parent / "art/style/palette.txt"


def relief(img, glow=None, seed=1, bevel=9.0, carve=11.0, speckle=0.22, grain=5.0, gradient=8.0):
    """Shade a flat, script-drawn IMG the way the generated sprites are: lit from the upper left.
    Every opaque pixel that isn't outline (lightness under 20) or GLOW (a predicate on a pixel's
    Lab, for the parts that shine) is a surface: lighter by BEVEL where its upper-left side meets
    the outline or nothing, darker where its lower-right side does; a glowing stroke cut into it is a
    groove, its upper-left wall in shadow (CARVE) and its lower-right lip lit; and SPECKLE of the
    surface, picked by SEED (the same pixels in every frame of a strip), is a GRAIN lighter or
    darker, the wear and chips a generated sprite has; and the whole surface is up to GRADIENT
    lighter toward the shape's upper left and darker toward its lower right, so it reads round
    rather than flat. Lightness only: house_finish then snaps the
    colours onto the palette."""
    rgba = np.asarray(img.convert("RGBA")).copy()
    h, w = rgba.shape[:2]
    op = rgba[:, :, 3] >= 128
    lab = _lab(rgba[:, :, :3].astype(np.float64))
    line = op & (lab[:, :, 0] < 20)
    shine = np.zeros_like(op)
    if glow is not None:
        shine = op & np.apply_along_axis(glow, 2, lab)
    body = op & ~line & ~shine
    out = ~op | line

    def near(mask, dy, dx):
        """True where the pixel DY, DX away is in MASK (nothing beyond the image's edge)."""
        m = np.zeros_like(mask)
        ys, yd = (slice(0, h - dy), slice(dy, h)) if dy >= 0 else (slice(-dy, h), slice(0, h + dy))
        xs, xd = (slice(0, w - dx), slice(dx, w)) if dx >= 0 else (slice(-dx, w), slice(0, w + dx))
        m[ys, xs] = mask[yd, xd]
        return m

    edge_out = near(out, 0, -1) | near(out, -1, 0)    # nothing above or left of it
    edge_in = near(out, 0, 1) | near(out, 1, 0)       # nothing below or right
    d = np.zeros((h, w))
    d += bevel * (edge_out & ~edge_in) - bevel * (edge_in & ~edge_out)
    groove = near(shine, 0, 1) | near(shine, 1, 0) | near(shine, 1, 1)
    lip = near(shine, 0, -1) | near(shine, -1, 0)
    d -= carve * (groove & ~lip)
    d += 0.6 * carve * (lip & ~groove)
    if gradient and body.any():
        ys, xs = np.nonzero(op)
        diag = (np.arange(w)[None, :] - xs.mean()) / max(1, np.ptp(xs)) + (np.arange(h)[:, None] - ys.mean()) / max(1, np.ptp(ys))
        d -= gradient * np.clip(diag, -1, 1)
    noise = np.random.default_rng(seed).random((h, w))
    d -= grain * (noise < speckle / 2)
    d += grain * ((noise >= speckle / 2) & (noise < speckle))
    lab[:, :, 0] = np.clip(lab[:, :, 0] + d * body, 0, 100)
    rgba[body, :3] = _rgb(lab[body])
    rgba[~op] = 0
    rgba[op, 3] = 255
    return Image.fromarray(rgba, "RGBA")


def house_finish(img, glow=None, seed=1, palette=None, **relief_args):
    """A script-drawn frame in the house style ("House style", CLAUDE.md): relief, sel-out, then
    every pixel onto the master palette (opaque or clear, nothing between)."""
    palette = read_palette(HOUSE_PALETTE) if palette is None else palette
    return quantize_to_palette(selout(relief(img, glow, seed, **relief_args)), palette)


def glowing(min_chroma=30.0, min_lightness=45.0):
    """A predicate for relief's GLOW: saturated and bright, the strokes that shine."""
    return lambda lab: bool(lab[1] ** 2 + lab[2] ** 2 > min_chroma ** 2 and lab[0] > min_lightness)
