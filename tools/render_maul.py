#!/usr/bin/env python3
"""Render the first-person maul from a procedural 3D model, as reference frames for an image
generator to restyle, the way tools/render_sword.py does the sword:

  tools/render_maul.py art/maul-renders
  tools/render_maul.py art/maul-renders --frames 0,8 --pixel 2

The model is a war maul, an ash haft with a leather grip and iron bands and a long block of
forged steel for a head, held in two gauntlets, right above left, their vambraced forearms
drawn long enough to leave the frame. The gauntlets are render_sword's, the left one mirrored.
tools/blender_maul.py builds the same model into a .blend and renders it toon-shaded.

Every pose places the maul in camera space (metres, +X right, +Y up, the camera looking down
-Z): HEAD, the head's centre, and HAFT, the way the haft runs from its end toward the head. The
head's long axis is always square to the haft and to the camera's X: it lies in the upright plane
straight ahead, the plane of an overhead blow, so the maul strikes with an end face and the
player sees the head's broad side standing up and down. Each hand grips the haft GRIP metres
from its end, its forearm running back to its ELBOW.

POSES are the strip's pictures, art/maul/maul-frames.txt's sources: idle, raise, charged,
strike, impact, recover, shake-lift, shake-swing and shake-slam.

Writes, in the output folder, frame_NN.png (the whole 1536 x 1024 screen, on magenta,
cel-shaded with dark outlines) and the pose's name in names.txt.
"""

import argparse
import math
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_sword as rs   # noqa: E402
from render_sword import Part, normalize, tube   # noqa: E402

try:
    from PIL import Image
except ImportError:   # inside Blender, which only borrows the model
    Image = None

RAMPS = dict(rs.RAMPS, wood=[(40, 22, 12), (66, 38, 20), (96, 58, 32), (128, 82, 48),
                             (158, 108, 66), (186, 136, 90)])
SHINE = dict(rs.SHINE, wood=0.15)

LENGTH = 0.85        # metres from the haft's end to the middle of the head
HAFT_R = 0.019
HEAD_LONG = 0.38     # the head along its axis, end face to end face
HEAD_SIDE = 0.12     # its square section, across the haft (X) and along it (Y)
BEVEL = 0.012
RIGHT_GRIP = 0.30    # where the right hand grips, metres from the haft's end
LEFT_GRIP = 0.14
CLOSE_GRIP = 0.21    # the left hand's grip when the haft points away: lower, only its cuff would show


def box(center, half, material, bevel=0.0):
    """A box, its half-extents HALF along X Y Z, its edges along Z (the long axis) chamfered by
    BEVEL: an octagonal prism with flat end faces."""
    hx, hy, hz = half
    b = bevel
    ring = [(hx - b, hy), (-hx + b, hy), (-hx, hy - b), (-hx, -hy + b),
            (-hx + b, -hy), (hx - b, -hy), (hx, -hy + b), (hx, hy - b)]
    if b <= 0:
        ring = [(hx, hy), (-hx, hy), (-hx, -hy), (hx, -hy)]
    n = len(ring)
    c = np.asarray(center, float)
    verts = [c + (x, y, -hz) for x, y in ring] + [c + (x, y, hz) for x, y in ring]
    faces = []
    for i in range(n):
        j = (i + 1) % n
        faces += [(i, j, n + j), (i, n + j, n + i)]
    for k in range(1, n - 1):
        faces += [(0, k + 1, k), (n, n + k, n + k + 1)]
    return Part(verts, faces, material, smooth=False)


def maul_parts():
    """The maul in maul space: the haft along +Y from its end at the origin, the head's middle at
    y = LENGTH, the head's long axis along Z."""
    parts = []
    parts.append(("haft", tube([(0, 0.0, 0), (0, LENGTH, 0)], HAFT_R, 12, "wood", up=(0, 0, 1))))
    parts.append(("grip", tube([(0, 0.03, 0), (0, 0.44, 0)], HAFT_R + 0.003, 12, "leather", up=(0, 0, 1))))
    parts.append(("cap", tube([(0, -0.012, 0), (0, 0.02, 0)], HAFT_R + 0.006, 12, "iron", up=(0, 0, 1))))
    for k, y in enumerate((LENGTH - 0.30, LENGTH - 0.21, LENGTH - 0.12)):
        parts.append((f"band{k}", tube([(0, y - 0.011, 0), (0, y + 0.011, 0)], HAFT_R + 0.005, 12,
                                       "iron", up=(0, 0, 1))))
    # The socket where the haft goes into the head's underside, and the head.
    parts.append(("socket", [box((0, LENGTH - HEAD_SIDE / 2 - 0.02, 0), (0.032, 0.03, 0.032), "iron", 0.006)]))
    parts.append(("head", [box((0, LENGTH, 0), (HEAD_SIDE / 2, HEAD_SIDE / 2, HEAD_LONG / 2), "steel", BEVEL)]))
    # Two straps round the head either side of the haft, a little proud of it.
    for k, z in enumerate((-0.06, 0.06)):
        parts.append((f"strap{k}", [box((0, LENGTH, z), (HEAD_SIDE / 2 + 0.004, HEAD_SIDE / 2 + 0.004, 0.012),
                                        "iron", BEVEL)]))
    return parts


OPEN_CURL = 228
"""Degrees round the haft an open hand's fingertips reach (a fist's go to 248): about its middle
as the player sees it."""

THUMB_REACH = -105
"""Degrees round the haft the thumb's tip reaches, over the wrist's side from the back of the hand
(0, +X; -90 is +Z): to about the haft's middle as the player sees it (at -150 it crossed it)."""


def thumb_parts():
    """The thumb, from the back of the hand by the index knuckle round the wrist's side of the haft,
    hugging the grip: render_sword's, drawn for a sword's thin grip, hooked out past a thick one."""
    r = HAFT_R + 0.003 + 0.011   # on the leather
    base = [np.array([0.040, 0.046, -0.004])]   # by the index knuckle
    wrap = rs.arc(r, 0.048, -15, THUMB_REACH, 6)
    return [("thumb0", tube(base + wrap[:3], [0.0135, 0.0125, 0.012, 0.0115], 8, "iron")),
            ("thumb1", tube(wrap[2:], [0.0115, 0.011, 0.0105, 0.0095], 8, "iron"))]


def fist_parts(open_hand=False):
    """render_sword's fist with THUMB_PARTS' thumb. OPEN_HAND: the haft rests on the palm, the
    fingers closed only to OPEN_CURL round it."""
    out = []
    for name, ms in rs.fist_parts():
        if name.startswith("thumb"):
            continue
        if open_hand and name.endswith(".2"):
            # The last joint closes only to OPEN_CURL, as render_sword's fist_parts draws it.
            i = int(name[len("finger")])
            y = 0.034 - 0.0225 * i
            r = 0.0118 * (1 - 0.05 * i) * (1 - 0.06 * 2)
            ms = tube(rs.arc(0.028, y, 178, OPEN_CURL, 3), r, 8, "iron")
        out.append((name, ms))
    return out + thumb_parts()


def hand_parts(cock, open_hand=False):
    """The gauntlet as render_sword's hand_parts, with FIST_PARTS' fist."""
    m = rs.cock_matrix(cock)
    return fist_parts(open_hand) + [(name, [p.transformed(m, 0) for p in ms]) for name, ms in rs.back_parts()]


MIRROR = np.diag([-1.0, 1.0, 1.0])


def mirrored(parts):
    """PARTS (name, [Part]) mirrored across X, their faces turned back outward: a left hand."""
    return [(name, [Part(p.verts @ MIRROR, p.faces[:, ::-1], p.material, p.smooth) for p in ms])
            for name, ms in parts]


def maul_frame(haft):
    """Columns: maul space's X, Y (the haft) and Z (the head's axis) in camera space. The head's
    axis is square to the haft and to the camera's X, so it lies in the plane of the blow."""
    y = normalize(np.asarray(haft, float))
    z = normalize(np.cross((1.0, 0, 0), y))
    x = np.cross(y, z)
    return np.stack([x, y, z], 1)


def about(axis, angle):
    """The rotation ANGLE degrees about AXIS."""
    k = normalize(np.asarray(axis, float))
    a = math.radians(angle)
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    return np.eye(3) + math.sin(a) * kx + (1 - math.cos(a)) * kx @ kx


def hand_pose(pos, haft, elbow, back=None, roll=0.0, open_hand=False):
    """A hand gripping the haft at POS, its thumb along HAFT (toward the head), the back of the hand
    facing BACK's side (in camera space). render_sword's pose turns the hand so that its forearm runs
    to ELBOW; when that faces the back the other way, the back is turned to BACK, square to the haft,
    and the forearm runs back from the fist in the hand's own plane, toward ELBOW as near as that
    allows. Either way hand and forearm are one straight line, the wrist never bending. Then both turn together ROLL degrees about the haft. OPEN_HAND
    rests the haft on the palm (FIST_PARTS)."""
    u = normalize(np.asarray(haft, float))
    toward = normalize(np.asarray(elbow, float) - pos)
    cock = math.degrees(math.asin(max(-1.0, min(1.0, -u.dot(toward)))))
    p = rs.pose(pos, elbow, u, cock=cock)
    # That pose faces the back of the hand BACK's way unless the forearm runs nearly along the haft
    # (the haft pointing away from low hands): there it turns the hand round under the haft.
    if back is not None and p["rot"][:, 0].dot(normalize(np.asarray(back, float))) < BACK_TURN:
        b = np.asarray(back, float)
        x = normalize(b - b.dot(u) * u)
        z = np.cross(x, u)
        # The forearm leaves the fist toward +Z, cocked toward the pinky's end (-Y), up to past
        # straight along the haft when the elbow lies behind the knuckles.
        cock = max(0.0, min(100.0, math.degrees(math.atan2(-toward.dot(u), toward.dot(z)))))
        p = {"pos": np.asarray(pos, float), "rot": np.stack([x, u, z], 1), "cock": cock, "trail": False}
    p["rot"] = about(u, roll) @ p["rot"]
    p["open"] = open_hand
    return p


RIGHT_BACK = (1.0, 0.0, 0.0)
LEFT_BACK = (-1.0, 0.0, 0.0)
BACK_TURN = 0.5      # the back of a hand turned more than 60 degrees from its BACK is turned to it


def pose(name, head, haft, right_elbow, left_elbow, right_grip=RIGHT_GRIP, left_grip=LEFT_GRIP,
         right_back=None, left_back=LEFT_BACK, right_roll=0.0, left_roll=0.0,
         right_open=False, left_open=False):
    """HEAD the head's middle, HAFT the way the haft runs toward it; each ELBOW an offset from its
    hand, where its forearm runs; each BACK the way the back of its hand should face, within
    BACK_TURN (outward: the right hand's to the right, the left's to the left, the fingers round the
    inside of the haft and under it), or None for wherever its forearm turns it; each ROLL how far its
    hand turns about the haft from there, and each OPEN whether the haft rests on its palm."""
    rot = maul_frame(haft)
    u = rot[:, 1]
    end = np.asarray(head, float) - LENGTH * u
    hands = []
    for grip, elbow, back, roll, open_hand, left in (
            (right_grip, right_elbow, right_back, right_roll, right_open, False),
            (left_grip, left_elbow, left_back, left_roll, left_open, True)):
        at = end + grip * u
        # A left hand is the right one mirrored across hand X: its back faces -X.
        facing = None if back is None else -np.asarray(back, float) if left else back
        hands.append((hand_pose(at, u, at + np.asarray(elbow, float), facing, roll, open_hand), left))
    return {"name": name, "end": end, "rot": rot, "hands": hands}


RIGHT_ELBOW = (0.10, -0.24, 0.30)
LEFT_ELBOW = (-0.06, -0.26, 0.30)


def from_hand(name, hand, haft, right_elbow=RIGHT_ELBOW, left_elbow=LEFT_ELBOW, **rolls):
    """The pose with the right hand at HAND, the haft running HAFT from it."""
    u = normalize(np.asarray(haft, float))
    head = np.asarray(hand, float) + (LENGTH - RIGHT_GRIP) * u
    return pose(name, head, u, right_elbow, left_elbow, **rolls)


# A haft running nearly level, forward from low hands, rises on screen toward the middle, and its
# head stands up and down with its broad side to the player; tipped up or down, the head tips
# with it.
POSE_ARGS = [
    # At rest: low at the right, the haft running forward and a little up, the head standing up;
    # the far hand's fingers turned round the near side of the haft, its forearm a little less, out
    # to the right.
    ("idle", dict(hand=(0.12, -0.21, -0.60), haft=(0.40, 0.24, -0.88), right_roll=-60.0,
                  right_open=True, left_grip=CLOSE_GRIP)),
    # Lifting it: the haft tipped up toward the right shoulder, the head high at the right; the near
    # hand turned to show its fingers round the haft rather than its back.
    ("raise", dict(hand=(0.15, -0.16, -0.62), haft=(0.28, 0.74, -0.61), left_grip=CLOSE_GRIP,
                   left_roll=-40.0)),
    # Wound up: the haft leaning back over the shoulder, the head above the screen's top.
    ("charged", dict(hand=(0.17, -0.05, -0.62), haft=(0.14, 0.92, 0.36),
                     right_elbow=(0.10, -0.34, 0.14), left_elbow=(-0.04, -0.36, 0.16))),
    # Coming down over the middle, the head tipped toward the player.
    ("strike", dict(hand=(0.05, -0.16, -0.60), haft=(0.02, 0.70, -0.71), left_grip=CLOSE_GRIP)),
    # The blow lands: the haft running level ahead, the head standing on what it hit, a little below
    # the middle of the view.
    ("impact", dict(hand=(0.04, -0.20, -0.56), haft=(0.01, 0.12, -0.99), left_grip=CLOSE_GRIP,
                    right_back=RIGHT_BACK)),
    # On its way back to rest.
    ("recover", dict(hand=(0.09, -0.21, -0.58), haft=(0.26, 0.16, -0.95), left_grip=CLOSE_GRIP,
                     right_back=RIGHT_BACK)),
    # The earthshake: lifted up in front, then driven straight down into the floor at the
    # player's feet, the hands thrust down at the screen's bottom and the head below it, out of
    # view (its dust shows the impact in the game).
    ("shake-lift", dict(hand=(0.03, -0.12, -0.62), haft=(0.01, 0.94, -0.34),
                        right_elbow=(0.10, -0.34, 0.16), left_elbow=(-0.08, -0.34, 0.16))),
    # Coming over: the butt end up and back, the head swinging down and out to the right, so the
    # haft shows its length (straight down the middle it points at the camera, all end cap).
    ("shake-swing", dict(hand=(0.0, -0.06, -0.64), haft=(0.45, -0.5, -0.74),
                         right_elbow=(0.10, -0.38, 0.12), left_elbow=(-0.10, -0.38, 0.12),
                         left_back=None)),
    ("shake-slam", dict(hand=(0.03, -0.31, -0.58), haft=(0.01, -0.92, -0.38),
                        right_elbow=(0.16, -0.10, 0.30), left_elbow=(-0.16, -0.10, 0.30),
                        left_back=None)),
]
POSES = [from_hand(name, **args) for name, args in POSE_ARGS]


def scene(p):
    """Labelled parts of the whole model in camera space for pose P."""
    rot, end = p["rot"], p["end"]
    out = [(name, [m.transformed(rot, end) for m in ms]) for name, ms in maul_parts()]
    for hp, left in p["hands"]:
        hand = hand_parts(hp["cock"], hp["open"])
        if left:
            hand = mirrored(hand)
        out += [(name, [m.transformed(hp["rot"], hp["pos"]) for m in ms]) for name, ms in hand]
        line = rs.cock_matrix(hp["cock"])
        wrist_local = rs.WRIST * (MIRROR.diagonal() if left else 1)
        wrist = hp["rot"] @ (line @ wrist_local) + hp["pos"]
        out += rs.arm_parts(wrist, hp["rot"] @ line[:, 2])
    return out


def render(p, w, h, line):
    labelled = scene(p)
    parts, materials = [], []
    for name, meshes in labelled:
        materials.append(meshes[0].material)
        parts += [(len(materials) - 1, m) for m in meshes]
    invz, nbuf, ibuf = rs.rasterize(parts, w, h)
    saved = rs.RAMPS, rs.SHINE
    rs.RAMPS, rs.SHINE = RAMPS, SHINE
    try:
        img, _ = rs.shade(invz, nbuf, ibuf, materials, w, h, line)
    finally:
        rs.RAMPS, rs.SHINE = saved
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--pixel", type=int, default=1,
                    help="render at 1536x1024 / PIXEL and upscale by PIXEL, nearest-neighbour (default 1)")
    ap.add_argument("--frames", help="comma-separated pose indices to render (default all)")
    args = ap.parse_args()
    w, h = 1536 // args.pixel, 1024 // args.pixel
    line = max(1, round(min(w, h) / 300))
    args.out.mkdir(parents=True, exist_ok=True)
    which = range(len(POSES)) if not args.frames else [int(x) for x in args.frames.split(",")]
    for i in which:
        im = Image.fromarray(render(POSES[i], w, h, line)).resize((1536, 1024), Image.NEAREST)
        im.save(args.out / f"frame_{i:02d}.png")
        print(f"frame {i:2d} {POSES[i]['name']}")
    (args.out / "names.txt").write_text("".join(f"{i:02d} {p['name']}\n" for i, p in enumerate(POSES)))


if __name__ == "__main__":
    main()
