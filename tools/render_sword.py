#!/usr/bin/env python3
"""Render the first-person sword from a procedural 3D model, as reference frames for an
image generator to restyle (and as a placeholder sheet the game can slice directly):

  tools/render_sword.py art/sword-renders
  tools/render_sword.py art/sword-renders --cell 800x600 --pixel 4

The model is a right gauntlet gripping an arming sword, plus the vambraced forearm,
drawn long enough to run off screen so the elbow never shows. POSES lists the 12
frames of the strip: 4 idle, then an 8-frame right-to-left slash. Each pose puts the
hand in camera space (metres, +X right, +Y up, the camera looking down -Z): where the
grip is, which way the forearm runs from it, how far the wrist cocks the blade off
square, and which way the blade turns about the forearm. Fist and forearm are one
rigid line, and the sword never turns in the fist. The cut frames are one rigid pose
turned about an axis near the line of sight, so the blade sweeps edge first.

Writes, in the output folder:

  frame_NN.png  one frame per pose on magenta, cel-shaded with dark outlines
  sheet.png     the frames in a 4-wide grid with cyan separators, the layout
                tools/slice_frames.py reads (--pixel there is --pixel here)

No dependencies past numpy and Pillow: a small z-buffer rasterizer, Lambert plus
Blinn specular, quantized into per-material colour ramps.
"""

import argparse
import math
from pathlib import Path

import numpy as np

try:
    from PIL import Image, ImageDraw
except ImportError:   # inside Blender, which only borrows the model
    Image = ImageDraw = None

MAGENTA = (255, 0, 255)
CYAN = (0, 255, 255)
OUTLINE = (20, 16, 14)

RAMPS = {
    "steel": [(52, 56, 64), (84, 90, 100), (120, 126, 136), (158, 164, 172),
              (196, 200, 206), (232, 234, 238), (255, 255, 255)],
    "iron": [(34, 34, 38), (56, 56, 62), (82, 82, 90), (112, 112, 120),
             (150, 150, 156), (196, 196, 200), (240, 240, 242)],
    "brass": [(70, 44, 14), (118, 80, 28), (166, 120, 46), (210, 166, 76),
              (242, 210, 124), (255, 240, 190)],
    "leather": [(36, 22, 12), (60, 38, 20), (88, 58, 34), (118, 82, 50),
                (148, 106, 68)],
}
SHINE = {"steel": 0.6, "iron": 0.6, "brass": 0.7, "leather": 0.1}
TRAIL = [(255, 255, 244), (255, 244, 196), (250, 218, 140), (236, 178, 86)]

LIGHT = np.array([-0.45, 0.75, 0.5])
LIGHT /= np.linalg.norm(LIGHT)
VFOV = 55.0          # degrees, vertical
ARM_REACH = 0.7      # metres of forearm drawn from the wrist, enough to leave the frame
GRIP_TWIST = 80.0    # degrees the sword turns in the fist about its grip, from flats facing the palm


# --------------------------------------------------------------------------- meshes

class Part:
    """A mesh: VERTS (n, 3), FACES (m, 3) indices; SMOOTH averages normals over
    shared vertices, otherwise each face is flat."""

    def __init__(self, verts, faces, material, smooth=True):
        self.verts = np.asarray(verts, float)
        self.faces = np.asarray(faces, int)
        self.material = material
        self.smooth = smooth

    def transformed(self, rot, pos):
        return Part(self.verts @ rot.T + pos, self.faces, self.material, self.smooth)


def normalize(v):
    return v / np.linalg.norm(v, axis=-1, keepdims=True)


def tube(path, radii, sides=12, material="iron", up=None, caps=True, smooth=True):
    """Sweep an ellipse along PATH. RADII per point is r or (r_up, r_side); UP is the
    direction the first radius lies along (default: any)."""
    path = np.asarray(path, float)
    n = len(path)
    radii = np.asarray(radii, float)
    if radii.ndim == 0:
        radii = np.full(n, float(radii))
    if radii.ndim == 1:
        radii = np.stack([radii, radii], 1)
    tang = np.gradient(path, axis=0)
    tang = normalize(tang)
    ref = np.asarray(up, float) if up is not None else (
        np.array([0, 1.0, 0]) if abs(tang[0][1]) < 0.9 else np.array([1.0, 0, 0]))
    verts, faces = [], []
    nrm = ref - ref.dot(tang[0]) * tang[0]
    nrm /= np.linalg.norm(nrm)
    ang = np.linspace(0, 2 * math.pi, sides, endpoint=False)
    for i in range(n):
        nrm = nrm - nrm.dot(tang[i]) * tang[i]
        nrm /= np.linalg.norm(nrm)
        bi = np.cross(tang[i], nrm)
        ru, rs = radii[i]
        for a in ang:
            verts.append(path[i] + ru * math.cos(a) * nrm + rs * math.sin(a) * bi)
    for i in range(n - 1):
        for j in range(sides):
            a, b = i * sides + j, i * sides + (j + 1) % sides
            c, d = a + sides, b + sides
            faces += [(a, b, d), (a, d, c)]
    parts = [Part(verts, faces, material, smooth)]
    if caps:
        for ring in (0, n - 1):
            if radii[ring].max() < 1e-6:
                continue
            cap = [verts[ring * sides + j] for j in range(sides)] + [path[ring]]
            # wound against the side faces' rim edge, as a closed mesh's are
            fan = [((j + 1) % sides, j, sides) if ring == 0 else (j, (j + 1) % sides, sides)
                   for j in range(sides)]
            parts.append(Part(cap, fan, material, smooth=False))
    return parts


def sphere(center, r, material, sides=10):
    """A ball as a capped tube, its poles cut flat a little short of the ends."""
    c = np.asarray(center, float)
    t = np.linspace(-0.92, 0.92, 7)
    path = [c + np.array([0, 0, r * x]) for x in t]
    return tube(path, r * np.sqrt(1 - t ** 2), sides, material, up=(0, 1, 0))


def arc(radius, y, theta0, theta1, steps):
    """Points around the grip axis (sword Y): theta 0 is +X, 90 is -Z (forward)."""
    th = np.radians(np.linspace(theta0, theta1, steps))
    return [np.array([radius * math.cos(a), y, -radius * math.sin(a)]) for a in th]


def blade_parts():
    """Diamond-section blade, guard, grip, pommel, in sword space: grip along +Y, the
    guard at y = 0.075, edges along X, flats facing Z."""
    parts = []
    ys = np.array([0.085, 0.12, 0.45, 0.64, 0.70, 0.76])
    half_w = np.array([0.034, 0.033, 0.029, 0.024, 0.014, 0.0])
    half_t = np.array([0.008, 0.0075, 0.0065, 0.0055, 0.004, 0.0])
    verts, faces = [], []
    for y, w, t in zip(ys[:-1], half_w, half_t):
        verts += [(w, y, 0), (0, y, t), (-w, y, 0), (0, y, -t)]
    tip = len(verts)
    verts.append((0, ys[-1], 0))
    for i in range(len(ys) - 1):
        for j in range(4):
            a, b = 4 * i + j, 4 * i + (j + 1) % 4
            faces += [(a, b, b + 4), (a, b + 4, a + 4)] if i < len(ys) - 2 else [(a, b, tip)]
    faces += [(0, 2, 1), (0, 3, 2)]
    parts.append(("blade", [Part(verts, faces, "steel", smooth=False)]))

    bar = [np.array([x, 0.075 + 0.25 * x * x, 0]) for x in np.linspace(-0.10, 0.10, 9)]
    parts.append(("guard", tube(bar, 0.0095, 10, "brass", up=(0, 1, 0))
                  + sphere((-0.104, 0.078, 0), 0.015, "brass")
                  + sphere((0.104, 0.078, 0), 0.015, "brass")
                  + tube([(0, 0.064, 0), (0, 0.11, 0)], [(0.016, 0.026), (0.004, 0.006)], 4,
                         "brass", up=(0, 0, 1))))
    parts.append(("grip", tube([(0, -0.075, 0), (0, 0.068, 0)], 0.0165, 10, "leather")))
    parts.append(("pommel", tube([(0, -0.09, -0.011), (0, -0.09, 0.011)], 0.022, 16,
                                 "brass", up=(0, 1, 0))
                  + tube([(0, -0.09, -0.015), (0, -0.09, 0.015)], 0.01, 10, "brass",
                         up=(0, 1, 0))))
    return parts


def cock_matrix(cock):
    """Turn about hand X taking +Z (toward the wrist) to the arm line, COCK degrees
    down toward the pommel."""
    a = math.radians(cock)
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def fist_parts():
    """Right gauntlet's fingers, knuckles and thumb in hand space: the grip runs along +Y
    (thumb side), the back of the hand faces +X, the knuckles -Z."""
    parts = []
    parts.append(("knuckles", tube([(0.044, -0.047, -0.012), (0.046, 0.047, -0.012)],
                                   [(0.0125, 0.0125)] * 2, 8, "iron", up=(1, 0, 0))))
    for i in range(4):
        y = 0.034 - 0.0225 * i
        r = 0.0118 * (1 - 0.05 * i)
        segs = [[np.array([0.042, y, -0.018])] + arc(0.029, y, 62, 108, 4),
                arc(0.029, y, 104, 182, 6),
                arc(0.028, y, 178, 248, 5)]
        for k, seg in enumerate(segs):
            parts.append((f"finger{i}.{k}", tube(seg, r * (1 - 0.06 * k), 8, "iron")))
    thumb = [(0.034, 0.044, 0.045), (0.016, 0.052, 0.04), (-0.008, 0.050, 0.032),
             (-0.026, 0.044, 0.016), (-0.032, 0.040, 0.0)]
    parts.append(("thumb0", tube(thumb[:3], [0.0135, 0.0125, 0.012], 8, "iron")))
    parts.append(("thumb1", tube(thumb[2:], [0.0118, 0.011, 0.0095], 8, "iron")))
    return parts


def back_parts():
    """The back of the hand and the cuff, along +Z from the knuckles to the wrist, in
    hand space before the cock."""
    return [("hand", tube([(0.037, 0.0, 0.085), (0.035, 0.0, 0.03), (0.032, 0.0, -0.012)],
                          [(0.048, 0.024), (0.052, 0.024), (0.049, 0.02)], 10, "iron",
                          up=(0, 1, 0))),
            ("cuff", tube([(0.037, 0.0, 0.07), (0.04, 0.0, 0.14)],
                          [(0.05, 0.03), (0.054, 0.04)], 12, "iron", up=(0, 1, 0))),
            ("cuffband", tube([(0.04, 0.0, 0.125), (0.0405, 0.0, 0.142)],
                              [(0.0555, 0.0415)] * 2, 12, "leather", up=(0, 1, 0)))]


def hand_parts(cock):
    """The whole gauntlet in hand space. The back of the hand and the cuff lie along
    the arm line, COCK degrees from +Z toward the pommel: the grip crosses the fist
    at a slant, as it does in a real one, and the wrist never bends."""
    m = cock_matrix(cock)
    return fist_parts() + [(name, [p.transformed(m, 0) for p in ms]) for name, ms in back_parts()]


WRIST = np.array([0.04, 0.0, 0.12])   # in hand space before the cock


def arm_parts(wrist, direction):
    """Vambraced forearm from WRIST along DIRECTION, drawn ARM_REACH long so it always
    runs off screen: the elbow never shows."""
    end = wrist + ARM_REACH * direction
    pts = [wrist + (end - wrist) * t for t in (0.0, 0.4, 1.0)]
    parts = [("forearm", tube(pts, [0.04, 0.047, 0.056], 14, "iron"))]
    for k, at in enumerate((0.10, 0.22)):
        a, b = wrist + direction * (at - 0.012), wrist + direction * (at + 0.012)
        r = 0.0445 + 0.02 * at
        parts.append((f"strap{k}", tube([a, b], r, 14, "leather")))
    return parts


# --------------------------------------------------------------------------- poses

def twist(deg):
    a = math.radians(deg)
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def pose(pos, elbow, blade, cock=40.0, trail=False):
    """The grip at POS, the forearm and fist on one line from ELBOW, and the blade
    cocked COCK degrees past square to that line, turned about it toward BLADE."""
    toward_elbow = normalize(np.asarray(elbow, float) - pos)
    h = np.asarray(blade, float)
    side = normalize(h - h.dot(toward_elbow) * toward_elbow)
    a = math.radians(cock)
    y = math.cos(a) * side - math.sin(a) * toward_elbow
    x = normalize(np.cross(y, toward_elbow))
    rot = np.stack([x, y, np.cross(x, y)], 1)   # columns: hand X, Y, Z in camera space
    return {"pos": np.asarray(pos, float), "rot": rot, "cock": cock, "trail": trail}


IDLE = dict(pos=(0.13, -0.22, -0.66), elbow=(0.29, -0.37, -0.27), blade=(-0.3, 1.0, -0.1))
BOB = [(0.0, 0.0), (0.0, -0.006), (0.002, -0.011), (0.0, -0.006)]

def turned(p, axis, angle, pos):
    """Pose P with the fist, sword and forearm turned ANGLE degrees about AXIS as one
    piece, the grip moved to POS: nothing turns in the hand or at the wrist."""
    k = normalize(np.asarray(axis, float))
    a = math.radians(angle)
    kx = np.array([[0, -k[2], k[1]], [k[2], 0, -k[0]], [-k[1], k[0], 0]])
    r = np.eye(3) + math.sin(a) * kx + (1 - math.cos(a)) * kx @ kx
    return dict(p, pos=np.asarray(pos, float), rot=r @ p["rot"], trail=True)


# The cut, right to left: one rigid pose of fist, sword and forearm, CUT_AT (its flat
# toward the viewer), turned about CUT_AXIS, close to the line of sight, through each
# angle, the grip at each point. The blade sweeps across the screen edge first.
CUT_AXIS = (0.16, 0.08, 0.98)
CUT_AT = turned(pose((0.04, -0.10, -0.60), (0.24, -0.30, -0.26), (-0.7, 0.6, -0.3), cock=35),
                CUT_AXIS, 28, (0, 0, 0))
CUT_AT = turned(CUT_AT, (CUT_AT["rot"] @ twist(GRIP_TWIST))[:, 1], -35, (0, 0, 0))   # flat to the viewer
CUT = [(-75, (0.12, -0.04, -0.55)), (-40, (0.02, -0.09, -0.58)), (0, (-0.10, -0.15, -0.58)),
       (22, (-0.18, -0.18, -0.58)), (40, (-0.25, -0.23, -0.57))]

POSES = [pose(np.add(IDLE["pos"], (dx, dy, 0)), IDLE["elbow"], IDLE["blade"]) for dx, dy in BOB] + [
    # raise and draw back over the right shoulder, the wrist cocking back
    pose((0.17, -0.12, -0.50), (0.32, -0.40, -0.30), (0.1, 1.0, 0.3), cock=15),
    pose((0.17, -0.05, -0.48), (0.33, -0.36, -0.28), (0.7, 0.5, 0.5), cock=0),
    # come over and across, right to left
] + [turned(CUT_AT, CUT_AXIS, a, at) for a, at in CUT] + [
    pose((0.11, -0.25, -0.65), IDLE["elbow"], IDLE["blade"]),
]


def quat(m):
    t = np.trace(m)
    if t > 0:
        s = math.sqrt(t + 1) * 2
        return np.array([0.25 * s, (m[2, 1] - m[1, 2]) / s, (m[0, 2] - m[2, 0]) / s,
                         (m[1, 0] - m[0, 1]) / s])
    i = int(np.argmax(np.diag(m)))
    j, k = (i + 1) % 3, (i + 2) % 3
    s = math.sqrt(1 + m[i, i] - m[j, j] - m[k, k]) * 2
    q = np.zeros(4)
    q[0] = (m[k, j] - m[j, k]) / s
    q[1 + i] = 0.25 * s
    q[1 + j] = (m[j, i] + m[i, j]) / s
    q[1 + k] = (m[k, i] + m[i, k]) / s
    return q


def quat_matrix(q):
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([[1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
                     [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
                     [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)]])


def slerp(a, b, t):
    qa, qb = quat(a), quat(b)
    if qa.dot(qb) < 0:
        qb = -qb
    d = min(1.0, qa.dot(qb))
    th = math.acos(d)
    if th < 1e-4:
        q = qa + (qb - qa) * t
    else:
        q = (math.sin((1 - t) * th) * qa + math.sin(t * th) * qb) / math.sin(th)
    return quat_matrix(q)


def scene(p):
    """Labelled parts of the whole model in camera space for pose P."""
    rot, pos = p["rot"], p["pos"]
    sword_rot = rot @ twist(GRIP_TWIST)
    out = [(name, [m.transformed(sword_rot, pos) for m in ms]) for name, ms in blade_parts()]
    out += [(name, [m.transformed(rot, pos) for m in ms]) for name, ms in hand_parts(p["cock"])]
    line = cock_matrix(p["cock"])
    wrist = rot @ (line @ WRIST) + pos
    out += arm_parts(wrist, rot @ line[:, 2])
    return out


# --------------------------------------------------------------------------- raster

def project(pts, w, h):
    f = 1 / math.tan(math.radians(VFOV) / 2)
    zv = -pts[..., 2]
    sx = (f * pts[..., 0] / zv * h / w + 1) * 0.5 * w
    sy = (1 - f * pts[..., 1] / zv) * 0.5 * h
    return sx, sy, zv


NEAR = 0.05


def clip_near(tri, nrm):
    """Cut triangle TRI (3, 3) with vertex normals NRM against the near plane. Returns
    the triangles in front of it, 0 to 2, as (points, normals) pairs."""
    front = -tri[:, 2] >= NEAR
    if front.all():
        return [(tri, nrm)]
    if not front.any():
        return []
    pts, nos = [], []
    for i in range(3):
        j = (i + 1) % 3
        if front[i]:
            pts.append(tri[i])
            nos.append(nrm[i])
        if front[i] != front[j]:
            t = (-NEAR - tri[i, 2]) / (tri[j, 2] - tri[i, 2])
            pts.append(tri[i] + t * (tri[j] - tri[i]))
            nos.append(nrm[i] + t * (nrm[j] - nrm[i]))
    return [(np.array([pts[0], pts[k], pts[k + 1]]), np.array([nos[0], nos[k], nos[k + 1]]))
            for k in range(1, len(pts) - 1)]


def rasterize(parts, w, h):
    """Z-buffer PARTS (list of (id, Part)). Returns inverse depth, normals, part ids."""
    invz = np.zeros((h, w))
    nbuf = np.zeros((h, w, 3))
    ibuf = np.full((h, w), -1, int)
    for pid, part in parts:
        v, fc = part.verts, part.faces
        tri = v[fc]
        fn = np.cross(tri[:, 1] - tri[:, 0], tri[:, 2] - tri[:, 0])
        if part.smooth:
            vn = np.zeros_like(v)
            for k in range(3):
                np.add.at(vn, fc[:, k], fn)
            tn = normalize(vn[fc] + 1e-12)
        else:
            tn = np.repeat(normalize(fn + 1e-12)[:, None], 3, 1)
        for t in range(len(fc)):
            for pts, nos in clip_near(tri[t], tn[t]):
                draw_triangle(pts, nos, pid, invz, nbuf, ibuf, w, h)
    return invz, nbuf, ibuf


def draw_triangle(pts, nos, pid, invz, nbuf, ibuf, w, h):
    xs, ys, zv = project(pts, w, h)
    x0, x1 = max(int(xs.min()), 0), min(int(xs.max()) + 1, w - 1)
    y0, y1 = max(int(ys.min()), 0), min(int(ys.max()) + 1, h - 1)
    if x0 > x1 or y0 > y1:
        return
    area = (xs[1] - xs[0]) * (ys[2] - ys[0]) - (xs[2] - xs[0]) * (ys[1] - ys[0])
    if abs(area) < 1e-9:
        return
    px, py = np.meshgrid(np.arange(x0, x1 + 1) + 0.5, np.arange(y0, y1 + 1) + 0.5)
    b0 = ((xs[1] - px) * (ys[2] - py) - (xs[2] - px) * (ys[1] - py)) / area
    b1 = ((xs[2] - px) * (ys[0] - py) - (xs[0] - px) * (ys[2] - py)) / area
    b2 = 1 - b0 - b1
    inside = (b0 >= 0) & (b1 >= 0) & (b2 >= 0)
    if not inside.any():
        return
    iz = b0 / zv[0] + b1 / zv[1] + b2 / zv[2]
    region = invz[y0:y1 + 1, x0:x1 + 1]
    win = inside & (iz > region)
    if not win.any():
        return
    region[win] = iz[win]
    ibuf[y0:y1 + 1, x0:x1 + 1][win] = pid
    n = (b0[..., None] * nos[0] / zv[0] + b1[..., None] * nos[1] / zv[1]
         + b2[..., None] * nos[2] / zv[2])
    nbuf[y0:y1 + 1, x0:x1 + 1][win] = n[win]


def shade(invz, nbuf, ibuf, materials, w, h, line):
    img = np.zeros((h, w, 3), np.uint8)
    img[:] = MAGENTA
    solid = ibuf >= 0
    f = 1 / math.tan(math.radians(VFOV) / 2)
    px, py = np.meshgrid(np.arange(w) + 0.5, np.arange(h) + 0.5)
    view = np.stack([(px / w * 2 - 1) * w / h / f, (1 - py / h * 2) / f, -np.ones_like(px)], -1)
    view = normalize(view)
    n = normalize(nbuf + 1e-12)
    flip = (n * view).sum(-1) > 0
    n[flip] *= -1
    diff = np.clip((n * LIGHT).sum(-1), 0, 1)
    half = normalize(LIGHT - view)
    spec = np.clip((n * half).sum(-1), 0, 1) ** 28
    sky = 0.5 + 0.5 * n[..., 1]
    for pid, mat in enumerate(materials):
        sel = ibuf == pid
        if not sel.any():
            continue
        ramp = RAMPS[mat]
        t = 0.12 + 0.55 * diff[sel] + 0.18 * sky[sel] + SHINE[mat] * spec[sel]
        k = np.clip((t * (len(ramp) - 1) + 0.5).astype(int), 0, len(ramp) - 1)
        img[sel] = np.array(ramp, np.uint8)[k]
    edge = np.zeros_like(solid)
    for dy in range(-line, line + 1):
        for dx in range(-line, line + 1):
            if dx * dx + dy * dy > line * line or (dx, dy) == (0, 0):
                continue
            ni = np.roll(np.roll(ibuf, dy, 0), dx, 1)
            nz = np.roll(np.roll(invz, dy, 0), dx, 1)
            edge |= solid & ((ni < 0) | ((ni != ibuf) & (nz > invz)))
    img[edge] = OUTLINE
    return img, solid


def draw_trail(img, solid, prev, cur, w, h, steps=24, fade=0.8):
    """Fill the screen area the blade swept from PREV to CUR, under the model: a
    crescent, white where the blade is now, yellowing and narrowing toward the tip
    as it ages, gone after FADE of the way back."""
    layer = Image.new("RGB", (w, h), MAGENTA)
    mask = Image.new("L", (w, h), 0)
    dl, dm = ImageDraw.Draw(layer), ImageDraw.Draw(mask)
    lines = []
    for s in range(steps + 1):
        t = s / steps
        age = 1 - t
        inner = 0.30 + 0.42 * min(1.0, age / fade)
        ys = np.linspace(inner, 0.76, 8)
        local = np.stack([np.zeros_like(ys), ys, np.zeros_like(ys)], 1)
        rot = slerp(prev["rot"], cur["rot"], t) @ twist(GRIP_TWIST)
        pos = prev["pos"] + (cur["pos"] - prev["pos"]) * t
        sx, sy, _ = project(local @ rot.T + pos, w, h)
        lines.append((age, list(zip(sx, sy))))
    for (age, a), (_, b) in zip(lines, lines[1:]):
        if age > fade:
            continue
        col = TRAIL[min(len(TRAIL) - 1, int(age / fade * len(TRAIL)))]
        for j in range(len(a) - 1):
            quad = [a[j], a[j + 1], b[j + 1], b[j]]
            dl.polygon(quad, fill=col)
            dm.polygon(quad, fill=255)
    trail = np.asarray(layer)
    m = (np.asarray(mask) > 0) & ~solid
    img[m] = trail[m]


def render(p, prev, w, h, line):
    labelled = scene(p)
    parts, materials = [], []
    for name, meshes in labelled:
        materials.append(meshes[0].material)
        parts += [(len(materials) - 1, m) for m in meshes]
    invz, nbuf, ibuf = rasterize(parts, w, h)
    img, solid = shade(invz, nbuf, ibuf, materials, w, h, line)
    if p["trail"] and prev is not None:
        draw_trail(img, solid, prev, p, w, h)
    return img


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path)
    ap.add_argument("--cell", default="800x600", help="frame size in output pixels (default 800x600)")
    ap.add_argument("--pixel", type=int, default=1,
                    help="render at cell/PIXEL and upscale by PIXEL, nearest-neighbour (default 1)")
    ap.add_argument("--frames", help="comma-separated frame indices to render (default all)")
    args = ap.parse_args()
    cw, ch = (int(x) for x in args.cell.split("x"))
    w, h = cw // args.pixel, ch // args.pixel
    line = max(1, round(min(w, h) / 300))
    args.out.mkdir(parents=True, exist_ok=True)
    which = range(len(POSES)) if not args.frames else [int(x) for x in args.frames.split(",")]
    frames = {}
    for i in which:
        img = render(POSES[i], POSES[i - 1] if i > 0 else None, w, h, line)
        im = Image.fromarray(img).resize((w * args.pixel, h * args.pixel), Image.NEAREST)
        im.save(args.out / f"frame_{i:02d}.png")
        frames[i] = im
        print(f"frame {i:2d}")
    if len(frames) == len(POSES):
        cols, rows = 4, (len(POSES) + 3) // 4
        sw, sh = cols * cw + cols + 1, rows * ch + rows + 1
        sheet = Image.new("RGB", (sw, sh), CYAN)
        for i, im in frames.items():
            sheet.paste(im, (1 + (i % cols) * (cw + 1), 1 + (i // cols) * (ch + 1)))
        sheet.save(args.out / "sheet.png")
        print(args.out / "sheet.png")


if __name__ == "__main__":
    main()
