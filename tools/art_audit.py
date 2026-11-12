#!/usr/bin/env python3
"""Check the art the game ships against the house style ("House style" in CLAUDE.md).

    tools/art_audit.py              # a line per image under data/sprites, data/textures, data/splash
    tools/art_audit.py --check      # exit 1 on a rule broken that the allowlist doesn't excuse
    tools/art_audit.py --json       # the measurements, one object a line
    tools/art_audit.py imp knight   # only images whose path contains one of these

It reads only data/ and src/, so it runs in a checkout without the LFS art (CI's).

What it measures, per image:
- px/m, art pixels per metre in the world: a strip's cell height over the metres it is drawn
  at. Those come from each `define-fx-animation`'s :size in src/ (its parameters, such as
  *imp-height*, evaluated from their defparameters), a creature's turnaround from its
  *<name>-height*, a townsperson's from its cell over 64, a texture from *texels-per-metre*.
  Screen-space art (the hands, weapons, icons) has none; its screen pixels per art pixel at
  720 and 1080 rows are worked out from the parameters that scale it (SCREEN below).
- colours: distinct colours in its opaque pixels, and with a master palette
  (art/style/palette.txt) the share of them that aren't in it.
- semi: the share of its visible pixels that are part transparent. The game cuts alpha at
  0.5, so they are drawn jagged.
- outline: the share of its edge pixels (opaque beside transparent) that are near black.
- L*: lightness p5..p95 and its spread (standard deviation), the measure of contrast.

The rules (--check), each excused per image by a line in tools/art_audit_allow.txt
(`PATH-SUBSTRING RULE  # why`):
- density: a world image's px/m within DENSITY_BAND;
- semi: no part-transparent pixels;
- palette: every colour in the master palette, once there is one;
- screen: first-person art drawn at the weapons' scale at 1080 rows (square pixels), and
  the HUD's at HUD_SCALE.
"""

import argparse
import glob
import json
import math
import os
import re
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
DATA, SRC = ROOT / "data", ROOT / "src"
PALETTE = ROOT / "art" / "style" / "palette.txt"
ALLOW = ROOT / "tools" / "art_audit_allow.txt"
DENSITY_BAND = (48.0, 96.0)
SCREEN_ASSETS = ("hands/", "sword/", "spear/", "maul/", "icons/")


def source():
    return "\n".join(p.read_text() for p in sorted(SRC.glob("*.lisp")))


def parameters(text):
    """Numeric defparameters of the source, by name: (defparameter *x* 1.5 ...)."""
    out = {}
    for m in re.finditer(r"\(defparameter (\*[\w-]+\*)\s+(-?[\d.]+)(?:f0)?[\s)]", text):
        try:
            out[m.group(1)] = float(m.group(2))
        except ValueError:
            pass
    return out


def evaluate(form, params):
    """The few :size forms the source uses: a number, a parameter, (* P a/b), (/ a b)."""
    form = form.strip()
    m = re.fullmatch(r"\(\* (\S+) (\d+)/(\d+)\)", form)
    if m:
        base = params.get(m.group(1))
        return base and base * int(m.group(2)) / int(m.group(3))
    m = re.fullmatch(r"\(/ ([\d.]+) ([\d.]+)\)", form)
    if m:
        return float(m.group(1)) / float(m.group(2))
    if form in params:
        return params[form]
    try:
        return float(form)
    except ValueError:
        return None


SIZE_FORM = r":size (\(\* \S+ \d+/\d+\)|\(/ [\d.]+ [\d.]+\)|[^\s()]+)"


def strip_sizes(text, params):
    """Metres each strip's cell height is drawn at, by its path under data/sprites without
    extension. A strip several animations share takes the first."""
    sizes = {}
    for m in re.finditer(r'\(define-fx-animation \S+ "sprites/([^"]+)"([^\n]*)', text):
        size = re.search(SIZE_FORM, m.group(2))
        sizes.setdefault(m.group(1), evaluate(size.group(1), params) if size else 1.0)
    return sizes


def atlas(png):
    path = Path(png).with_suffix(".lisp")
    if not path.exists():
        return {}
    text = path.read_text()
    return {k: int(v) for k, v in re.findall(r":(cell-width|cell-height|gap|frames) (\d+)", text)}


def metres(rel, cell_h, sizes, params):
    """Metres the cell height of REL (path under data/sprites, no extension) stands for."""
    folder, name = rel.split("/", 1) if "/" in rel else (rel, "")
    if rel == "blood/blood":
        # The blood pool sizes its quads by *blood-pixels-per-metre*, not the animation's size.
        return cell_h / params.get("*blood-pixels-per-metre*", 64.0)
    if rel in sizes and not rel.startswith(SCREEN_ASSETS):
        return sizes[rel]
    if name == "turnaround" and f"*{folder}-height*" in params:
        return params[f"*{folder}-height*"]
    # Townsfolk strips and the faction guards' are drawn at 64 px/m by their cell height
    # (strip-height, townsfolk.lisp), as is anything else that names no size.
    return cell_h / 64.0 if cell_h else None


def screen_scales(params, rows):
    """Screen pixels per art pixel, (across, up), of the first-person and HUD art at ROWS."""
    def cell(rel):
        return atlas(DATA / "sprites" / (rel + ".png")).get("cell-height", 1)
    sy = max(1, round(params.get("*sword-height*", 1.04) * rows / cell("sword/sword")))
    sword = (max(1, round(sy * params.get("*sword-stretch*", 1.0))), sy)
    hud = hud_scale(params, rows)
    # The hands draw at SWORD-SCALE too (layout-hands): their strip is made at the weapons'
    # source scale, so the two share an art pixel.
    return {"sword/": sword, "spear/": sword, "maul/": sword, "hands/": sword,
            "icons/": (hud, hud)}


def hud_scale(params, rows):
    """The HUD's screen pixels per art pixel at ROWS: round(rows / *hud-pixel-rows*) where
    the HUD has that parameter, else the fixed *weapon-icon-scale*."""
    if "*hud-pixel-rows*" in params:
        return max(1, round(rows / params["*hud-pixel-rows*"]))
    return int(params.get("*weapon-icon-scale*", 2))


def read_palette():
    """The master palette's colours as a set of 0xRRGGBB, or None without one. Its file has a
    line per ramp: a name, then hex colours."""
    if not PALETTE.exists():
        return None
    colours = set()
    for line in PALETTE.read_text().splitlines():
        line = line.split("#", 1)[0] if not re.search(r"#[0-9a-fA-F]{6}", line) else line
        colours.update(int(h, 16) for h in re.findall(r"\b([0-9a-fA-F]{6})\b", line))
    return colours


def lightness(rgb):
    """CIE L* of an array of 0..255 RGB values."""
    c = rgb / 255.0
    c = np.where(c > 0.04045, ((c + 0.055) / 1.055) ** 2.4, c / 12.92)
    y = c @ np.array([0.2126, 0.7152, 0.0722])
    return np.where(y > 0.008856, 116 * np.cbrt(y) - 16, 903.3 * y)


def measure(png, palette):
    a = np.asarray(Image.open(png).convert("RGBA")).astype(np.int64)
    alpha = a[..., 3]
    opaque, seen = alpha == 255, alpha > 0
    px = a[..., :3][opaque]
    if not len(px):
        return None
    keys = px[:, 0] * 65536 + px[:, 1] * 256 + px[:, 2]
    unique = np.unique(keys)
    clear = alpha == 0
    near_clear = np.zeros_like(clear)
    near_clear[1:] |= clear[:-1]; near_clear[:-1] |= clear[1:]
    near_clear[:, 1:] |= clear[:, :-1]; near_clear[:, :-1] |= clear[:, 1:]
    edge = opaque & near_clear
    lstar = lightness(px.astype(float))
    elstar = lightness(a[..., :3][edge].astype(float)) if edge.any() else np.array([np.nan])
    out = {"colours": int(len(unique)),
           "semi": float(((alpha > 0) & (alpha < 255)).sum() / max(1, seen.sum())),
           "outline": float((elstar < 20).mean()),
           "l5": float(np.percentile(lstar, 5)), "l95": float(np.percentile(lstar, 95)),
           "lstd": float(lstar.std())}
    if palette is not None:
        outside = ~np.isin(keys, np.fromiter(palette, np.int64))
        out["off_palette"] = float(outside.mean())
    return out


def read_allow():
    rules = []
    if ALLOW.exists():
        for line in ALLOW.read_text().splitlines():
            line = line.split("#", 1)[0].split()
            if len(line) >= 2:
                rules.append((line[0], line[1]))
    return rules


def allowed(rules, path, rule):
    return any(sub in path and r in (rule, "*") for sub, r in rules)


def images(filters):
    found = sorted(glob.glob(str(DATA / "sprites" / "**" / "*.png"), recursive=True))
    found += sorted(glob.glob(str(DATA / "textures" / "*.png")))
    found += sorted(glob.glob(str(DATA / "splash" / "*.png")))
    return [p for p in found if not filters or any(f in p for f in filters)]


def audit(filters=()):
    text = source()
    params = parameters(text)
    sizes = strip_sizes(text, params)
    palette = read_palette()
    tpm = params.get("*texels-per-metre*", 64.0)
    rows = []
    for png in images(filters):
        rel = os.path.relpath(png, DATA)
        m = measure(png, palette)
        if m is None:
            continue
        info = atlas(png)
        row = {"path": rel, **m, "cell": [info.get("cell-width"), info.get("cell-height")]}
        if rel.startswith("textures/"):
            row["kind"], row["ppm"] = "texture", tpm
        elif rel.startswith("splash/"):
            row["kind"] = "splash"
        else:
            sprite = rel[len("sprites/"):-len(".png")]
            if sprite.startswith(SCREEN_ASSETS):
                row["kind"] = "screen"
                for r in (720, 1080):
                    scales = screen_scales(params, r)
                    row[f"screen{r}"] = next(v for k, v in scales.items() if sprite.startswith(k))
            else:
                row["kind"] = "world"
                height = metres(sprite, info.get("cell-height"), sizes, params)
                row["ppm"] = info.get("cell-height", 0) / height if height else None
        rows.append(row)
    return rows, params


def problems(rows, params):
    rules = read_allow()
    found = []
    weapons = screen_scales(params, 1080)["sword/"]
    hud = hud_scale(params, 1080)
    for r in rows:
        p = r["path"]
        def flag(rule, why):
            if not allowed(rules, p, rule):
                found.append((p, rule, why))
        ppm = r.get("ppm")
        if r["kind"] == "world" and ppm and not DENSITY_BAND[0] <= ppm <= DENSITY_BAND[1]:
            flag("density", f"{ppm:.0f} px/m, outside {DENSITY_BAND[0]:.0f}-{DENSITY_BAND[1]:.0f}")
        if r["semi"] > 0:
            flag("semi", f"{r['semi']:.0%} of its pixels part transparent")
        if r.get("off_palette", 0) > 0:
            flag("palette", f"{r['off_palette']:.0%} of its pixels off the master palette")
        s = r.get("screen1080")
        if s:
            want = (hud, hud) if p.startswith("sprites/icons/") else weapons
            if tuple(s) != tuple(want):
                flag("screen", f"{s[0]}x{s[1]} screen px per art px at 1080 rows, not {want[0]}x{want[1]}")
    return found


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("filters", nargs="*", help="only images whose path contains one of these")
    ap.add_argument("--check", action="store_true", help="exit 1 on a rule broken")
    ap.add_argument("--json", action="store_true", help="the measurements, one object a line")
    args = ap.parse_args()
    rows, params = audit(args.filters)
    if args.json:
        for r in rows:
            print(json.dumps(r))
        return
    if not args.check:
        print(f"{'image':44s} {'px/m':>8s} {'colours':>7s} {'off':>4s} {'semi':>5s} "
              f"{'outl':>5s} {'L* p5-p95':>10s} {'Lsd':>5s}")
        for r in rows:
            ppm = r.get("ppm")
            dens = (f"{ppm:.0f}" if ppm else "-") if r["kind"] != "screen" else \
                "{}x{}/{}x{}".format(*r["screen720"], *r["screen1080"])
            off = f"{r['off_palette']:.0%}" if "off_palette" in r else "-"
            print(f"{r['path'][:44]:44s} {dens:>8s} {r['colours']:7d} {off:>4s} {r['semi']:5.2f} "
                  f"{r['outline']:5.2f} {r['l5']:4.0f}-{r['l95']:<4.0f} {r['lstd']:5.1f}")
    found = problems(rows, params)
    for p, rule, why in found:
        print(f"{rule:8s} {p}: {why}", file=sys.stderr if not args.check else sys.stdout)
    if args.check:
        print(f"{len(found)} problem(s) in {len(rows)} images.")
        sys.exit(1 if found else 0)


if __name__ == "__main__":
    main()
