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
