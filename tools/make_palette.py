#!/usr/bin/env python3
"""Make the master palette every shipped sprite and texture is drawn in ("House style", CLAUDE.md).

    tools/make_palette.py art/style/palette.txt --colors 128

It samples the art the game ships (data/): the textures, every creature's and townsperson's
strips, the first-person weapons and hands, the pickups and the effects, each group given a
share of the sample (GROUPS) rather than its pixel count, so the small bright effects get their
fire, frost, shock, necrotic and arcane tones and the big textures don't take every colour.
It clusters the sample in CIE Lab (k-means, seeded, so a run gives the same palette), then sorts
the colours into ramps: the near greys by lightness, the rest by hue family, each dark to light.

The palette file is a line per ramp, its name then its colours as hex:

    warm-grey  1a1614 2b2420 ...

tools/pixelart.py's quantize_to_palette maps art onto it, and tools/art_audit.py checks it.
"""

import argparse
import glob
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DATA = ROOT / "data"

# Group: (globs under data/, share of the sample).
GROUPS = {
    "textures": (["textures/*.png"], 0.30),
    "creatures": (["sprites/%s/*.png" % c for c in
                   ("imp", "acolyte", "knight", "harpy", "necromancer", "skeleton", "ogre", "wraith",
                    "riftwalker", "guard", "townsman", "townswoman", "townsfolk")]
                  + ["sprites/guard/*/*.png"], 0.34),
    "first-person": (["sprites/sword/*.png", "sprites/spear/*.png", "sprites/maul/*.png",
                      "sprites/hands/*.png"], 0.12),
    "effects": (["sprites/bolt/*.png", "sprites/spells/*.png", "sprites/grave/*.png", "sprites/rift/*.png",
                 "sprites/status/*.png", "sprites/torch/*.png", "sprites/blood/*.png",
                 "sprites/ogre/dust.png", "sprites/gale/*.png", "sprites/summon/*.png"], 0.14),
    "pickups": (["sprites/pickups/*.png", "sprites/gate/*.png"], 0.10),
}

# Ramps by hue (degrees in Lab's a*b* plane) for colours with chroma over NEUTRAL.
NEUTRAL = 9.0
HUES = [("red", 15), ("orange", 50), ("yellow", 85), ("green", 140), ("teal", 200),
        ("blue", 260), ("violet", 310), ("magenta", 345)]


def srgb_to_lab(rgb):
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    m = np.array([[0.4124, 0.3576, 0.1805], [0.2126, 0.7152, 0.0722], [0.0193, 0.1192, 0.9505]])
    xyz = c @ m.T / np.array([0.95047, 1.0, 1.08883])
    f = np.where(xyz > 0.008856, np.cbrt(xyz), 7.787 * xyz + 16 / 116)
    return np.stack([116 * f[:, 1] - 16, 500 * (f[:, 0] - f[:, 1]), 200 * (f[:, 1] - f[:, 2])], 1)


def lab_to_srgb(lab):
    fy = (lab[:, 0] + 16) / 116
    fx, fz = fy + lab[:, 1] / 500, fy - lab[:, 2] / 200
    f = np.stack([fx, fy, fz], 1)
    xyz = np.where(f > 0.206893, f ** 3, (f - 16 / 116) / 7.787) * np.array([0.95047, 1.0, 1.08883])
    m = np.array([[3.2406, -1.5372, -0.4986], [-0.9689, 1.8758, 0.0415], [0.0557, -0.2040, 1.0570]])
    c = np.clip(xyz @ m.T, 0, 1)
    c = np.where(c > 0.0031308, 1.055 * c ** (1 / 2.4) - 0.055, 12.92 * c)
    return np.clip(np.round(c * 255), 0, 255).astype(np.int64)


def opaque_pixels(path):
    a = np.asarray(Image.open(path).convert("RGBA"))
    return a[a[..., 3] == 255][:, :3]


def sample(total, rng, data=DATA):
    parts = []
    for name, (globs, share) in GROUPS.items():
        files = sorted({f for g in globs for f in glob.glob(str(Path(data) / g))})
        pix = np.concatenate([opaque_pixels(f) for f in files])
        n = int(total * share)
        parts.append(pix[rng.choice(len(pix), n, replace=len(pix) < n)])
    return np.concatenate(parts).astype(float)


def kmeans(points, k, rng, rounds=30):
    """k-means++ seeding, then Lloyd's rounds; returns the centres."""
    centres = [points[rng.integers(len(points))]]
    d2 = ((points - centres[0]) ** 2).sum(1)
    for _ in range(1, k):
        centres.append(points[rng.choice(len(points), p=d2 / d2.sum())])
        d2 = np.minimum(d2, ((points - centres[-1]) ** 2).sum(1))
    centres = np.array(centres)
    for _ in range(rounds):
        near = nearest(points, centres)
        for i in range(k):
            members = points[near == i]
            if len(members):
                centres[i] = members.mean(0)
    return centres


def nearest(points, centres, chunk=200000):
    out = np.empty(len(points), dtype=np.int64)
    for s in range(0, len(points), chunk):
        p = points[s:s + chunk]
        out[s:s + chunk] = ((p[:, None, :] - centres[None, :, :]) ** 2).sum(2).argmin(1)
    return out


def ramps(lab):
    """The palette's colours (Lab) grouped into named ramps, each dark to light."""
    chroma = np.hypot(lab[:, 1], lab[:, 2])
    hue = np.degrees(np.arctan2(lab[:, 2], lab[:, 1])) % 360
    groups = {}
    for i, (l, c, h) in enumerate(zip(lab[:, 0], chroma, hue)):
        if c < NEUTRAL:
            name = "warm-grey" if lab[i, 2] >= 0 else "cool-grey"
        else:
            name = min(HUES, key=lambda nh: min(abs(h - nh[1]), 360 - abs(h - nh[1])))[0]
            name = ("pale-" if c < 25 else "") + name
        groups.setdefault(name, []).append(i)
    order = ["warm-grey", "cool-grey"] + [p + n for n, _ in HUES for p in ("pale-", "")]
    return [(name, sorted(groups[name], key=lambda i: lab[i, 0])) for name in order if name in groups]


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("out", help="the palette file to write")
    ap.add_argument("--colors", type=int, default=128)
    ap.add_argument("--sample", type=int, default=400000, help="pixels sampled from the art")
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--data", default=str(DATA),
                    help="the art to sample: data/ by default; art not yet on any palette (an older"
                    " commit's data/, from git archive) to make one afresh")
    args = ap.parse_args()
    rng = np.random.default_rng(args.seed)
    points = srgb_to_lab(sample(args.sample, rng, args.data))
    centres = kmeans(points, args.colors, rng)
    rgb = lab_to_srgb(centres)
    # Back to Lab from the rounded colours, so the ramps sort what is written.
    lab = srgb_to_lab(rgb.astype(float))
    lines = ["# Hexmaw's master palette: written by tools/make_palette.py (--colors %d --seed %d)."
             % (args.colors, args.seed),
             "# A line per ramp, dark to light. Every shipped sprite and texture is quantized onto it."]
    seen = set()
    for name, members in ramps(lab):
        hexes = []
        for i in members:
            h = "%02x%02x%02x" % tuple(rgb[i])
            if h not in seen:
                seen.add(h)
                hexes.append(h)
        lines.append("%-14s %s" % (name, " ".join(hexes)))
    Path(args.out).parent.mkdir(parents=True, exist_ok=True)
    Path(args.out).write_text("\n".join(lines) + "\n")
    print(args.out, len(seen), "colours in", len(lines) - 2, "ramps")


if __name__ == "__main__":
    main()
