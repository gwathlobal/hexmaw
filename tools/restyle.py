#!/usr/bin/env python3
"""Put sliced strips into the house style ("House style" in CLAUDE.md), in place.

    tools/restyle.py --house data/sprites/imp/*.png
    tools/restyle.py data/sprites/bolt/*.png --palette art/style/palette.txt

The last step after the slicers (slice_frames.py, slice_views.py, slice_turnaround.py,
make_shield.py, the recolour tools): --contrast, --tone and --chroma as make_texture.py's, then
--selout (pixelart.selout: the black outline round the shape turned into a dark tone of what it
borders), then --palette (pixelart.quantize_to_palette: every opaque pixel onto the master
palette, part-transparent ones cut at half alpha as the game draws them). Slicing with the box
filter and then quantizing is what the slicers' own --colors does, so running this on a strip
gives what slicing with the palette would. --out DIR writes there instead of over the input.

--house applies the house rule by path: every strip onto art/style/palette.txt, and the solid
things (OUTLINED: creatures, townsfolk, pickups, the gate, the torch, the hands and weapons, and
the bone spikes and the rift sign) sel-outed too. Effects, icons, status auras and blood keep
their outlines: they are light, or drawn small on the HUD. Run it on a strip fresh from its
slicer or recolour, once (a second sel-out finds no black outline left, but darkens nothing more).
"""

import argparse
from pathlib import Path

from PIL import Image

from pixelart import adjust_tone, quantize_to_palette, read_palette, selout

ROOT = Path(__file__).resolve().parent.parent
PALETTE = ROOT / "art/style/palette.txt"
OUTLINED = ["acolyte", "gate", "grave/spikes", "guard", "hands", "harpy", "imp", "knight", "maul",
            "necromancer", "ogre", "pickups", "rift/sign", "riftwalker", "skeleton", "spear",
            "sword", "torch", "townsfolk", "townsman", "townswoman", "wraith"]


def outlined_p(path):
    """Whether the house rule sel-outs PATH, a strip under data/sprites/."""
    rel = Path(path).resolve().as_posix().split("/data/sprites/", 1)[-1]
    return any(rel.startswith(o) for o in OUTLINED)


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("images", nargs="+")
    ap.add_argument("--palette", help="the master palette file")
    ap.add_argument("--selout", action="store_true", help="recolour the black outline")
    ap.add_argument("--contrast", type=float, default=1.0)
    ap.add_argument("--tone", type=float, nargs=2, metavar=("A", "B"))
    ap.add_argument("--chroma", type=float, default=1.0)
    ap.add_argument("--out", help="write into this directory instead of in place")
    ap.add_argument("--house", action="store_true", help="the house rule by path (above)")
    args = ap.parse_args()
    if args.house and not args.palette:
        args.palette = str(PALETTE)
    palette = read_palette(args.palette) if args.palette else None
    for path in args.images:
        img = Image.open(path).convert("RGBA")
        if args.contrast != 1.0 or args.tone or args.chroma != 1.0:
            img = adjust_tone(img, args.contrast, args.tone, args.chroma)
        if args.selout or (args.house and outlined_p(path)):
            img = selout(img)
        if palette is not None:
            img = quantize_to_palette(img, palette)
        out = Path(args.out) / Path(path).name if args.out else Path(path)
        out.parent.mkdir(parents=True, exist_ok=True)
        img.save(out)
        print(out)


if __name__ == "__main__":
    main()
