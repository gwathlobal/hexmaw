#!/usr/bin/env python3
"""Contact sheets of the shipped art, to compare groups at the size they reach the screen.

    tools/art_sheets.py /tmp/sheets                 # every sheet, the world at 3 m on 1080 rows
    tools/art_sheets.py /tmp/sheets --distance 5 --rows 720
    tools/art_sheets.py /tmp/sheets --only world first-person

Sheets (PNG, named after them):
- world: monsters, townsfolk, effects, pickups, the torch and the gate over the stone wall, each
  scaled as the camera (75 degree field of view) draws it at --distance metres on --rows rows.
- first-person: the hands and weapons at their screen scale on --rows rows (sword-scale and the
  hands' own, from src/ as tools/art_audit.py reads them), beside an imp 1.5 m away.
- monsters: every creature's and townsperson's front view at 3x, against one dark tone.
- textures: a 2 m corner of every texture at 3x.
- drawn: the HUD icons and the floor signs, at 4x and 1x.
- palette: the master palette's ramps (art/style/palette.txt), when there is one.

It reads data/ and src/ only. The same frames make art/style/anchor.png (--anchor), the
reference sheet attached to new prompts: imp, knight, wall, floor, flask and sword.
"""

import argparse
import math
import re
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

import art_audit

DATA = art_audit.DATA
FONT_PATH = DATA / "fonts" / "Jersey15.ttf"


def font(size=27):
    return ImageFont.truetype(str(FONT_PATH), size)


def frame(rel, i=0):
    """Frame I of the strip REL (under data/sprites, no extension)."""
    png = DATA / "sprites" / (rel + ".png")
    im = Image.open(png).convert("RGBA")
    a = art_audit.atlas(png)
    cw, ch, gap = a["cell-width"], a["cell-height"], a.get("gap", 2)
    x = i * (cw + gap)
    return im.crop((x, 0, x + cw, ch))


def scaled(im, sx, sy=None):
    sy = sy or sx
    return im.resize((max(1, round(im.width * sx)), max(1, round(im.height * sy))), Image.NEAREST)


def per_metre(distance, rows):
    """Screen pixels per metre at DISTANCE on ROWS rows, for the player's 75 degree view."""
    return rows / (2 * distance * math.tan(math.radians(37.5)))


def sheet(items, background, width=3600):
    """ITEMS: (label, image). Laid out left to right, bottoms aligned, wrapping at WIDTH, on
    BACKGROUND (an image to tile, or a colour)."""
    pad, label_h = 24, 34
    rows, row, x, height = [], [], pad, 0
    f = font()
    for label, im in items:
        w = max(im.width, int(f.getlength(label)) + 8)
        if x + w > width - pad and row:
            rows.append((row, height))
            row, x, height = [], pad, 0
        row.append((label, im, x))
        x += w + pad
        height = max(height, im.height)
    rows.append((row, height))
    total = sum(h + label_h + pad for _, h in rows) + pad
    out = Image.new("RGBA", (width, total), background if isinstance(background, tuple) else (0, 0, 0, 255))
    if isinstance(background, Image.Image):
        for yy in range(0, total, background.height):
            for xx in range(0, width, background.width):
                out.paste(background, (xx, yy))
    d = ImageDraw.Draw(out)
    d.fontmode = "1"
    y = pad
    for row, height in rows:
        for label, im, x in row:
            if label:
                d.rectangle((x - 3, y, x + f.getlength(label) + 4, y + 28), fill=(0, 0, 0, 210))
                d.text((x, y - 4), label, font=f, fill=(255, 220, 140, 255))
            out.alpha_composite(im, (x, y + label_h + height - im.height))
        y += height + label_h + pad
    return out.convert("RGB")


def wall(screen_per_metre, dim=0.8):
    im = Image.open(DATA / "textures" / "wall-stone.png").convert("RGBA")
    im = scaled(im, screen_per_metre / 64)
    return Image.eval(im, lambda v: int(v * dim))


def world_sheet(distance, rows):
    text = art_audit.source()
    params = art_audit.parameters(text)
    sizes = art_audit.strip_sizes(text, params)
    spm = per_metre(distance, rows)

    def at(rel, i=0, metres=None):
        f = frame(rel, i)
        m = metres or art_audit.metres(rel, f.height, sizes, params)
        k = spm * m / f.height
        return f"{rel.split('/')[-1] if '/' in rel else rel} {f.height / m:.0f}", scaled(f, k)

    burst_r = 2.0
    items = [at(r) for r in ("imp/turnaround", "acolyte/turnaround", "knight/turnaround",
                             "skeleton/turnaround", "wraith/turnaround", "riftwalker/turnaround",
                             "guard/deepwardens/turnaround", "townsfolk/priest")]
    items[0] = ("imp " + items[0][0].split()[-1], items[0][1])
    items += [("torch", at("torch/torch", 2)[1]), ("bolt flight", at("bolt/flight", 2)[1]),
              ("bolt burst", at("bolt/burst", 3)[1]),
              (f"burst r={burst_r:g}m", at("spells/arcane-burst", 3,
                                            0.9 * max(1.0, burst_r / params.get("*burst-size*", 0.45)))[1]),
              ("rift burst", at("rift/burst", 3)[1]), ("grave skull", at("grave/flight", 1)[1]),
              ("burn aura (imp)", at("status/burn", 2, 1.5 * 1.25)[1]),
              ("ogre dust", at("ogre/dust", 2)[1]), ("blood", at("blood/blood", 6)[1]),
              ("shard", at("pickups/shard")[1]), ("flask", at("pickups/flask")[1]),
              ("glyph", at("pickups/glyph-frost")[1]), ("rune", at("pickups/loot-rune-fire")[1]),
              ("loot sword", at("pickups/loot-sword")[1]), ("gold", at("pickups/gold")[1]),
              ("dust", at("pickups/dust")[1]), ("gate", at("gate/gate")[1])]
    return sheet(items, wall(spm))


def first_person_sheet(rows):
    params = art_audit.parameters(art_audit.source())
    scales = art_audit.screen_scales(params, rows)
    sw, hd = scales["sword/"], scales["hands/"]
    items = [(f"sword {sw[0]}x{sw[1]}", scaled(frame("sword/sword", 0), *sw)),
             (f"shield {sw[0]}x{sw[1]}", scaled(frame("sword/shield", 0), *sw)),
             (f"spear {sw[0]}x{sw[1]}", scaled(frame("spear/spear", 0), *sw)),
             (f"maul {sw[0]}x{sw[1]}", scaled(frame("maul/maul", 0), *sw)),
             (f"hands {hd[0]}x{hd[1]}", scaled(frame("hands/hands", 10), *hd))]
    spm = per_metre(1.5, rows)
    imp = frame("imp/turnaround", 0)
    items.append(("imp at 1.5 m", scaled(imp, spm * 1.5 / imp.height)))
    return sheet(items, wall(per_metre(3.0, rows)), width=3800)


def monsters_sheet():
    items = []
    for who in ("imp", "acolyte", "knight", "harpy", "necromancer", "skeleton", "ogre", "wraith",
                "riftwalker", "guard/deepwardens", "townsman", "townswoman"):
        items.append((who.split("/")[0], scaled(frame(who + "/turnaround", 0), 3)))
    for who in ("priest", "shopkeeper", "trainer", "quest-giver"):
        items.append((who, scaled(frame("townsfolk/" + who, 0), 3)))
    return sheet(items, (40, 34, 30, 255), width=3200)


def textures_sheet():
    items = []
    for p in sorted((DATA / "textures").glob("*.png")):
        im = Image.open(p).convert("RGBA")
        items.append((p.stem, scaled(im.crop((0, 0, min(128, im.width), min(128, im.height))), 3)))
    return sheet(items, (20, 18, 16, 255), width=3200)


def drawn_sheet():
    items = []
    for rel in ("icons/items", "icons/weapons", "icons/statuses"):
        n = art_audit.atlas(DATA / "sprites" / (rel + ".png")).get("frames", 1)
        for i in range(n):
            items.append(("", scaled(frame(rel, i), 4)))
    for rel in ("grave/circle", "gale/sign", "summon/sigil", "rift/sign"):
        items.append((rel, frame(rel, 0)))
    return sheet(items, (20, 18, 16, 255), width=3000)


def palette_sheet():
    if not art_audit.PALETTE.exists():
        return None
    ramps = []
    for line in art_audit.PALETTE.read_text().splitlines():
        hexes = re.findall(r"\b([0-9a-fA-F]{6})\b", line)
        if hexes:
            ramps.append((line.split()[0], [tuple(int(h[i:i + 2], 16) for i in (0, 2, 4)) for h in hexes]))
    sw, f = 40, font()
    out = Image.new("RGB", (260 + sw * max(len(c) for _, c in ramps), 16 + len(ramps) * (sw + 8)), (20, 18, 16))
    d = ImageDraw.Draw(out)
    d.fontmode = "1"
    for i, (name, colours) in enumerate(ramps):
        y = 8 + i * (sw + 8)
        d.text((8, y + 4), name, font=f, fill=(255, 220, 140))
        for j, c in enumerate(colours):
            d.rectangle((250 + j * sw, y, 250 + (j + 1) * sw - 2, y + sw), fill=c)
    return out


def anchor_sheet():
    """The style anchor for prompts: imp, knight, flask and sword frame over wall and floor."""
    k = 3
    wall_t = scaled(Image.open(DATA / "textures" / "wall-stone.png").convert("RGBA").crop((0, 0, 256, 192)), k)
    floor_t = scaled(Image.open(DATA / "textures" / "floor-flags.png").convert("RGBA").crop((0, 0, 256, 64)), k)
    out = Image.new("RGBA", (wall_t.width, wall_t.height + floor_t.height), (0, 0, 0, 255))
    out.paste(wall_t, (0, 0))
    out.paste(floor_t, (0, wall_t.height))
    ground = wall_t.height + 20 * k
    x = 30
    for rel, i in (("imp/turnaround", 0), ("knight/turnaround", 1), ("pickups/flask", 0)):
        im = scaled(frame(rel, i), k)
        out.alpha_composite(im, (x, ground - im.height))
        x += im.width + 40
    sword = scaled(frame("sword/sword", 0), 2)
    out.alpha_composite(sword, (out.width - sword.width, out.height - sword.height))
    return out.convert("RGB")


SHEETS = {"world": None, "first-person": None, "monsters": monsters_sheet, "textures": textures_sheet,
          "drawn": drawn_sheet, "palette": palette_sheet}


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("out", nargs="?", help="directory for the sheets")
    ap.add_argument("--distance", type=float, default=3.0, help="metres to the world sheet's art")
    ap.add_argument("--rows", type=int, default=1080, help="screen rows")
    ap.add_argument("--only", nargs="+", choices=list(SHEETS), help="only these sheets")
    ap.add_argument("--anchor", help="write the style anchor sheet to this path")
    args = ap.parse_args()
    if args.anchor:
        anchor_sheet().save(args.anchor)
        print(args.anchor)
    if not args.out:
        return
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    for name in args.only or SHEETS:
        if name == "world":
            im = world_sheet(args.distance, args.rows)
        elif name == "first-person":
            im = first_person_sheet(args.rows)
        else:
            im = SHEETS[name]()
        if im is not None:
            im.save(out / f"{name}.png")
            print(out / f"{name}.png", im.size)


if __name__ == "__main__":
    main()
