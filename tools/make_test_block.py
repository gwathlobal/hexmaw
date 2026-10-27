#!/usr/bin/env python3
"""Generate a test level block as a .glb, laid out the way a Blender export would be.

Stand-in for a hand-modelled block until one exists. The conventions it follows
are the ones the game reads (see src/blocks.lisp and CLAUDE.md):

  - Units are metres, +Y up. The block's origin is its centre at floor level.
  - Every mesh object is drawn, and its bounding box is a solid, unless its
    name starts with "deco_" (drawn, no collision).
  - Empties named "connector_<anything>" mark doorways. A connector faces the
    direction from the block's origin to it, snapped to north/east/south/west.
  - Empties named "spawn_<monster>" mark where a monster stands, e.g. "spawn_imp".
    The empty's -Z axis is the way the monster faces.
  - Each material's base colour is the object's colour.

  tools/make_test_block.py data/blocks/test-room.glb
"""

import json
import struct
import sys
from pathlib import Path

# The room: 10 x 10 m, 4 m tall, walls 0.5 m thick, 3 x 3 m doorways north and
# south to match the corridor, a raised dais at the back and a 0.4 m step up to it.
W, D, H, T = 10.0, 10.0, 4.0, 0.5
DOOR_W, DOOR_H = 3.0, 3.0

MATERIALS = {
    "floor": (0.34, 0.38, 0.33),
    "wall": (0.50, 0.55, 0.47),
    "ceiling": (0.29, 0.31, 0.29),
    "dais": (0.58, 0.47, 0.30),
}

hw, hd = W / 2, D / 2
side = (W - DOOR_W) / 2  # width of the wall on each side of a doorway

BOXES = [
    # name, material, (min x, min y, min z), (max x, max y, max z)
    ("floor", "floor", (-hw, -0.5, -hd), (hw, 0.0, hd)),
    ("ceiling", "ceiling", (-hw, H, -hd), (hw, H + 0.5, hd)),
    ("wall_west", "wall", (-hw - T, 0.0, -hd), (-hw, H, hd)),
    ("wall_east", "wall", (hw, 0.0, -hd), (hw + T, H, hd)),
]
for name, z0, z1 in (("north", -hd - T, -hd), ("south", hd, hd + T)):
    BOXES += [
        (f"wall_{name}_left", "wall", (-hw, 0.0, z0), (-hw + side, H, z1)),
        (f"wall_{name}_right", "wall", (hw - side, 0.0, z0), (hw, H, z1)),
        (f"wall_{name}_lintel", "wall", (-DOOR_W / 2, DOOR_H, z0), (DOOR_W / 2, H, z1)),
    ]
BOXES += [
    ("dais", "dais", (-3.0, 0.0, -4.5), (3.0, 0.8, -2.5)),
    ("dais_step", "dais", (-1.5, 0.0, -2.5), (1.5, 0.4, -1.7)),
]

TURN_AROUND = [0.0, 1.0, 0.0, 0.0]  # quaternion x y z w: 180 degrees about +Y, so -Z faces south

EMPTIES = [
    # name, position, rotation (or None)
    ("connector_north", (0.0, 0.0, -hd - T), None),
    ("connector_south", (0.0, 0.0, hd + T), None),
    ("spawn_imp", (2.0, 0.8, -3.5), TURN_AROUND),
]


def box_mesh(size):
    """24 vertices (4 per face, so normals are flat) and 36 indices for a box centred on 0."""
    sx, sy, sz = (s / 2 for s in size)
    faces = [  # normal, then 4 corners counter-clockwise seen from outside
        ((1, 0, 0), [(sx, -sy, sz), (sx, -sy, -sz), (sx, sy, -sz), (sx, sy, sz)]),
        ((-1, 0, 0), [(-sx, -sy, -sz), (-sx, -sy, sz), (-sx, sy, sz), (-sx, sy, -sz)]),
        ((0, 1, 0), [(-sx, sy, sz), (sx, sy, sz), (sx, sy, -sz), (-sx, sy, -sz)]),
        ((0, -1, 0), [(-sx, -sy, -sz), (sx, -sy, -sz), (sx, -sy, sz), (-sx, -sy, sz)]),
        ((0, 0, 1), [(-sx, -sy, sz), (sx, -sy, sz), (sx, sy, sz), (-sx, sy, sz)]),
        ((0, 0, -1), [(sx, -sy, -sz), (-sx, -sy, -sz), (-sx, sy, -sz), (sx, sy, -sz)]),
    ]
    positions, normals, indices = [], [], []
    for normal, corners in faces:
        base = len(positions)
        positions += corners
        normals += [normal] * 4
        indices += [base, base + 1, base + 2, base, base + 2, base + 3]
    return positions, normals, indices


def main():
    out = Path(sys.argv[1] if len(sys.argv) > 1 else "data/blocks/test-room.glb")
    material_index = {name: i for i, name in enumerate(MATERIALS)}
    gltf = {
        "asset": {"version": "2.0", "generator": "hexmaw tools/make_test_block.py"},
        "scene": 0,
        "scenes": [{"name": "block", "nodes": []}],
        "nodes": [], "meshes": [], "accessors": [], "bufferViews": [], "buffers": [],
        "materials": [{"name": name, "pbrMetallicRoughness": {"baseColorFactor": [*rgb, 1.0],
                                                              "metallicFactor": 0.0, "roughnessFactor": 1.0}}
                      for name, rgb in MATERIALS.items()],
    }
    blob = bytearray()

    def add_view(data, target):
        while len(blob) % 4:
            blob.append(0)
        gltf["bufferViews"].append({"buffer": 0, "byteOffset": len(blob), "byteLength": len(data), "target": target})
        blob.extend(data)
        return len(gltf["bufferViews"]) - 1

    def add_accessor(view, component, count, kind, **extra):
        gltf["accessors"].append({"bufferView": view, "componentType": component, "count": count, "type": kind, **extra})
        return len(gltf["accessors"]) - 1

    for name, material, lo, hi in BOXES:
        size = [h - l for l, h in zip(lo, hi)]
        centre = [(l + h) / 2 for l, h in zip(lo, hi)]
        positions, normals, indices = box_mesh(size)
        pos = add_accessor(add_view(b"".join(struct.pack("<3f", *p) for p in positions), 34962), 5126,
                           len(positions), "VEC3",
                           min=[min(p[i] for p in positions) for i in range(3)],
                           max=[max(p[i] for p in positions) for i in range(3)])
        nrm = add_accessor(add_view(b"".join(struct.pack("<3f", *n) for n in normals), 34962), 5126,
                           len(normals), "VEC3")
        idx = add_accessor(add_view(struct.pack(f"<{len(indices)}H", *indices), 34963), 5123,
                           len(indices), "SCALAR")
        gltf["meshes"].append({"name": name, "primitives": [{
            "attributes": {"POSITION": pos, "NORMAL": nrm}, "indices": idx,
            "material": material_index[material]}]})
        gltf["nodes"].append({"name": name, "mesh": len(gltf["meshes"]) - 1, "translation": centre})

    for name, position, rotation in EMPTIES:
        node = {"name": name, "translation": list(position)}
        if rotation:
            node["rotation"] = rotation
        gltf["nodes"].append(node)

    gltf["scenes"][0]["nodes"] = list(range(len(gltf["nodes"])))
    while len(blob) % 4:
        blob.append(0)
    gltf["buffers"].append({"byteLength": len(blob)})

    js = json.dumps(gltf, separators=(",", ":")).encode()
    js += b" " * (-len(js) % 4)
    out.parent.mkdir(parents=True, exist_ok=True)
    with open(out, "wb") as f:
        f.write(struct.pack("<III", 0x46546C67, 2, 12 + 8 + len(js) + 8 + len(blob)))
        f.write(struct.pack("<II", len(js), 0x4E4F534A) + js)
        f.write(struct.pack("<II", len(blob), 0x004E4942) + bytes(blob))
    print(f"{out}: {len(BOXES)} meshes, {len(EMPTIES)} empties, {12 + 16 + len(js) + len(blob)} bytes")


if __name__ == "__main__":
    main()
