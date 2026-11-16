#!/usr/bin/env python3
"""Animate the magic of a still picture of the casting hands at rest, for an idle loop
(art/hands/hands-frames.txt), the hands left exactly as they are:

    tools/animate_idle.py art/hands/absorb-idle-1.png art/hands/absorb-idle-anim spin --frames 4 --step 90 --core 31 --clear 150 --pulse 1,1.25,1,0.8 --at 588,650,60 --at 947,650,60
    tools/animate_idle.py art/hands/ward-idle-1.png art/hands/ward-idle-anim hexes --at 542,445,100 --at 992,445,100
    tools/animate_idle.py art/hands/heal-idle-2.png art/hands/heal-idle-anim flow --frames 4 --hands art/hands/ward-idle-1.png --at 542,445,92 --at 992,445,92
    tools/animate_idle.py art/hands/absorb-idle-anim-{1,2,3,4}.png art/hands/absorb-idle-rim rim --dashes 4 --at 588,650,25,42 --at 947,650,25,42
    tools/animate_idle.py art/hands/absorb-void-1.png art/hands/absorb-void-turn-{1,2,3}.png art/hands/absorb-void-rim rim --dashes 8 --streaks --at 767,593,85,107

writes the loop's frames, STEM-1.png .. STEM-N.png. Asked for the magic moved, the generator moves
the hands too, and the loop would jitter; so only the magic's pixels change:

  spin   each circle (X,Y,RADIUS, in source pixels) turns STEP degrees a frame: the Absorb void's
         blue ring and specks, and its black disc within CORE of the middle (not the fingers'
         outlines round it), are lifted, turned about the middle (nearest pixel) and laid back on
         magenta, their light brightened by PULSE frame by frame. The blue beyond RADIUS but within
         CLEAR is taken out: specks that would sit still.
  hexes  the gold in each circle (the ward's one hexagon and rune) is taken out and three hexagons
         drawn in its place, one on top and two below, in gold lines one art pixel wide; each of
         the 3 frames draws one of them bold, two art pixels and paler, in turn.
  flow   a band of light runs up the healing ribbons (their green): only the band's part of each
         ribbon is drawn, brightest at its head, and it moves up PERIOD / FRAMES a frame, so the loop
         meets itself. Elsewhere the ribbon is gone, so the frames' gauntlets are HANDS, another rest
         pose's (the generator drew none under the ribbons, and the rest poses' gauntlets lie within a
         few pixels of each other), its own magic taken out of the circles AT.
  rim    the Absorb void's plain blue ring, on each of the SOURCES in turn (a loop's frames already
         made), redrawn in art pixels: a navy outer ring, the blue, and a pale inner edge lit from
         the upper left with a glint; round it, DASHES short pale dashes, turning half a dash's
         spacing a frame. Each AT is X,Y,DISC,RING: the void's middle, its black disc's radius and
         its ring's outer radius, in source pixels. With STREAKS the spiralling streaks round it
         shade from navy at their outer ends to ice where they reach the rim: light falling in.
"""

import argparse
import math
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw

MAGENTA = np.array([255, 0, 255], dtype=np.uint8)
SCALE = 0.2  # art pixels a source pixel, the hands' (art/hands/hands-frames.txt)


class ArtGrid:
    """The art pixels make_shield.py --corner right boxes a WIDTH x HEIGHT picture into: the picture
    mirrored, then each art pixel the average of the source pixels under it (pixelart.box_bounds).
    What is drawn in art pixels must be laid on exactly those boxes, or each stroke blends with what
    is beside it and its colour goes."""

    def __init__(self, width, height):
        self.W, self.H = width, height
        self.w, self.h = round(width * SCALE), round(height * SCALE)

    def point(self, x, y):
        """Source point X, Y in art pixels (unmirrored, so drawing reads as the picture does)."""
        return self.w - 1 - (self.W - 1 - x) * self.w / self.W, y * self.h / self.H

    def length(self, n):
        return n * self.w / self.W

    def canvas(self):
        return Image.new('RGBA', (self.w, self.h), (0, 0, 0, 0))

    def lay(self, canvas, frame):
        """Lay what is drawn on CANVAS onto FRAME, each art pixel over its box."""
        art = np.array(canvas)
        for a, j in zip(*np.nonzero(art[..., 3].T)):
            k = self.w - 1 - a
            x0, x1 = int(k * self.W / self.w), math.ceil((k + 1) * self.W / self.w)
            y0, y1 = int(j * self.H / self.h), math.ceil((j + 1) * self.H / self.h)
            frame[y0:y1, self.W - x1:self.W - x0] = art[j, a, :3]


def magenta_mask(rgb):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    return (r > g + 40) & (b > g + 40) & (abs(r - b) < 90)


def gold_mask(rgb):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    return (r > 150) & (g > 110) & (b < 120) & (r - b > 90)


def blue_mask(rgb):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    return (b > r + 40) & (b > g + 10)


def grid(rgb):
    return np.mgrid[0:rgb.shape[0], 0:rgb.shape[1]]


def shift(a, dy, dx, fill=0):
    """A moved DY rows and DX columns, what comes in from past the edge FILL (no wrapping round)."""
    out = np.full_like(a, fill)
    h, w = a.shape[:2]
    out[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)] = a[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)]
    return out


def dilate(mask, n):
    out = mask.copy()
    for _ in range(n):
        grown = out.copy()
        for dy, dx in ((1, 0), (-1, 0), (0, 1), (0, -1)):
            grown |= shift(out, dy, dx)
        out = grown
    return out


def saturation(rgb):
    hi, lo = rgb.max(-1).astype(float), rgb.min(-1).astype(float)
    return (hi - lo) / np.maximum(hi, 1)


def spin(rgb, circles, frames, step, core, clear, pulse):
    ys, xs = grid(rgb)
    blue = blue_mask(rgb) & ~magenta_mask(rgb)
    base = rgb.copy()
    magic = blue.copy()
    for cx, cy, r in circles:
        d2 = (xs - cx) ** 2 + (ys - cy) ** 2
        magic |= (rgb.max(-1) < 15) & (d2 <= core * core)
        base[blue & (d2 > r * r) & (d2 <= clear * clear)] = MAGENTA
    out = []
    for k in range(frames):
        frame = base.copy()
        for cx, cy, r in circles:
            inside = (xs - cx) ** 2 + (ys - cy) ** 2 <= r * r
            lifted = magic & inside
            frame[lifted] = MAGENTA
            a = math.radians(step * k)
            # Each pixel of the turned circle takes the source pixel turned back onto it.
            dx, dy = xs - cx, ys - cy
            sx = np.clip(np.rint(cx + dx * math.cos(a) + dy * math.sin(a)).astype(int), 0, rgb.shape[1] - 1)
            sy = np.clip(np.rint(cy - dx * math.sin(a) + dy * math.cos(a)).astype(int), 0, rgb.shape[0] - 1)
            take = inside & lifted[sy, sx]
            frame[take] = rgb[sy[take], sx[take]]
            # The coloured light (not the black) brightens and dims in turn.
            if pulse:
                lit = take & (rgb[sy, sx].max(-1) >= 15)
                frame[lit] = np.clip(frame[lit] * pulse[k % len(pulse)], 0, 255).astype(np.uint8)
        out.append(frame)
    return out


GOLD = (236, 196, 30)
GOLD_BOLD = (255, 248, 160)


def hex_points(cx, cy, r):
    """The corners of a pointy-topped hexagon of corner radius R round CX, CY, the first again last."""
    return [(cx + r * math.cos(math.radians(90 + 60 * i)), cy - r * math.sin(math.radians(90 + 60 * i)))
            for i in range(7)]


def hexes(rgb, circles, size):
    """Three frames: in each circle the ward's gold taken out and three hexagons of corner radius SIZE
    art pixels drawn, one above two, a different one bold in each."""
    base = without_magic(rgb, circles)
    w = math.sqrt(3) * size
    centres = [(0.0, -0.75 * size), (-w / 2, 0.75 * size), (w / 2, 0.75 * size)]
    grid_ = ArtGrid(rgb.shape[1], rgb.shape[0])
    out = []
    for bold in range(3):
        frame = base.copy()
        canvas = grid_.canvas()
        draw = ImageDraw.Draw(canvas)
        for cx, cy, _ in circles:
            ax, ay = grid_.point(cx, cy)
            for i in [i for i in range(3) if i != bold] + [bold]:
                hx, hy = centres[i]
                pts = hex_points(round(ax + hx), round(ay + hy), size)
                if i == bold:
                    draw.line(pts, fill=GOLD_BOLD + (255,), width=2, joint='curve')
                else:
                    draw.line(pts, fill=GOLD + (255,), width=1)
        grid_.lay(canvas, frame)
        out.append(frame)
    return out


def without_magic(rgb, circles):
    """RGB with what is coloured in the circles (X, Y, R) taken out: a rest pose's magic over the
    fingertips, not the grey steel."""
    ys, xs = grid(rgb)
    base = rgb.copy()
    magic = ~magenta_mask(rgb) & (saturation(rgb) > 0.25)
    for cx, cy, r in circles:
        base[magic & ((xs - cx) ** 2 + (ys - cy) ** 2 <= r * r)] = MAGENTA
    return base


def flow(rgb, frames, period, hands):
    r, g, b = (rgb[..., i].astype(int) for i in range(3))
    green = (g > r + 12) & (g > b + 12) & ~magenta_mask(rgb)
    # The ribbons' pale cores and edges too: light pixels within half a wide ribbon of the green.
    ribbon = green | (dilate(green, 15) & (rgb.min(-1) > 170) & ~magenta_mask(rgb))
    base = hands
    ys = grid(rgb)[0]
    out = []
    for k in range(frames):
        phase = ((ys + k * period / frames) % period) / period
        frame = base.copy()
        head = ribbon & (phase < 0.2)
        tail = ribbon & (phase >= 0.2) & (phase < 0.4)
        frame[head] = np.clip(rgb[head] * 1.3, 0, 255).astype(np.uint8)
        frame[tail] = rgb[tail]
        out.append(frame)
    return out


# Palette blues (art/style/palette.txt). All but the navy are bright enough that make_shield.py
# --glow leaves them as they are; the navy is darkened, an outer edge.
NAVY, DEEP, LIGHT, ICE, GLINT = (24, 38, 128), (10, 59, 225), (148, 189, 254), (169, 212, 250), (222, 235, 253)


def rim(sources, circles, dashes, streaks):
    out = []
    for k, rgb in enumerate(sources):
        frame = rgb.copy()
        ys, xs = grid(rgb)
        r_, g_, b_ = (rgb[..., i].astype(int) for i in range(3))
        blue = (b_ > r_ + 40) & (b_ > g_ + 10)
        art = ArtGrid(rgb.shape[1], rgb.shape[0])
        canvas = art.canvas()
        px = canvas.load()

        def put(x, y, colour):
            x, y = round(x), round(y)
            if 0 <= x < canvas.width and 0 <= y < canvas.height:
                px[x, y] = colour + (255,)

        def circle(cx, cy, r, colour, arc=None, step=2):
            for a in range(0, 360, step):
                if arc and not arc[0] <= a <= arc[1]:
                    continue
                put(cx + r * math.cos(math.radians(a)), cy - r * math.sin(math.radians(a)), colour)

        for x0, y0, disc, ring in circles:
            d = np.sqrt((xs - x0) ** 2 + (ys - y0) ** 2)
            # The old ring goes: inside the disc it is black, outside it the background.
            old = blue & (d <= ring)
            frame[old & (d <= disc)] = (12, 8, 8)
            frame[old & (d > disc)] = MAGENTA
            if streaks:
                unit = disc / art.length(disc)  # source pixels an art pixel
                frame[blue & (d > ring) & (d < disc + 7 * unit)] = ICE
                frame[blue & (d > disc + 13 * unit)] = NAVY
            cx, cy = art.point(x0, y0)
            r = round(art.length(disc))
            circle(cx, cy, r + 2, NAVY)
            circle(cx, cy, r + 1, DEEP)
            circle(cx, cy, r, ICE, (100, 200))
            put(cx - r * 0.6, cy - r * 0.75, GLINT)
            # The dashes, a few art pixels long whatever the size, turning half their spacing a frame.
            spacing = 360 / dashes
            arc = math.degrees(1.0 / (r + 4))
            for i in range(dashes):
                a0 = i * spacing + k * spacing / 2
                for j in range(3):
                    a = math.radians(a0 + j * arc)
                    put(cx + (r + 4) * math.cos(a), cy - (r + 4) * math.sin(a), GLINT)
        art.lay(canvas, frame)
        out.append(frame)
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('sources', nargs='+', help='the picture (rim: the loop\'s frames, in order)')
    ap.add_argument('stem', help='output path without the -N.png')
    ap.add_argument('mode', choices=('spin', 'hexes', 'flow', 'rim'))
    ap.add_argument('--frames', type=int, default=4, help='spin and flow: frames in the loop')
    ap.add_argument('--step', type=float, default=90.0, help='spin: degrees a frame')
    ap.add_argument('--at', action='append', default=[], help='spin, hexes, flow (in --hands): X,Y,RADIUS of a circle')
    ap.add_argument('--core', type=int, default=0, help='spin: radius of the black disc at each middle')
    ap.add_argument('--clear', type=int, default=0, help='spin: radius out to which still specks are taken out')
    ap.add_argument('--pulse', help='spin: brightness of the light each frame, as 1,1.2,1,0.85')
    ap.add_argument('--size', type=float, default=9.0, help='hexes: corner radius in art pixels')
    ap.add_argument('--period', type=float, default=120.0, help='flow: source pixels between bands')
    ap.add_argument('--hands', help="flow: the rest pose whose gauntlets the frames show, its magic in the circles AT taken out")
    ap.add_argument('--dashes', type=int, default=8, help='rim: dashes round each void')
    ap.add_argument('--streaks', action='store_true', help='rim: shade the streaks round it, light falling in')
    args = ap.parse_args()
    rgb = np.array(Image.open(args.sources[0]).convert('RGB'))
    circles = [tuple(int(v) for v in at.split(',')) for at in args.at]
    if args.mode == 'rim':
        sources = [np.array(Image.open(p).convert('RGB')) for p in args.sources]
        frames = rim(sources, circles, args.dashes, args.streaks)
    elif len(args.sources) > 1:
        raise SystemExit(f'{args.mode} takes one picture')
    elif args.mode == 'spin':
        pulse = [float(v) for v in args.pulse.split(',')] if args.pulse else None
        frames = spin(rgb, circles, args.frames, args.step, args.core, args.clear, pulse)
    elif args.mode == 'hexes':
        frames = hexes(rgb, circles, args.size)
    else:
        if not args.hands:
            raise SystemExit('flow needs --hands')
        hands = without_magic(np.array(Image.open(args.hands).convert('RGB')), circles)
        frames = flow(rgb, args.frames, args.period, hands)
    for k, frame in enumerate(frames, 1):
        path = Path(f'{args.stem}-{k}.png')
        Image.fromarray(frame).save(path)
        print(path)


if __name__ == '__main__':
    main()
