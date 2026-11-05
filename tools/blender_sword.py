"""Blender rig and renderer for the first-person sword: the model and poses of
tools/render_sword.py, set up in a .blend you can pose by hand, rendered toon-shaded
with Freestyle outlines.

  tools/blender -b --python tools/blender_sword.py -- build art/sword/sword.blend
  tools/blender -b --python tools/blender_sword.py -- render art/sword/sword.blend art/sword-blender

build writes the .blend from render_sword.POSES (it won't overwrite one unless given
--force: after the first build the poses live in the .blend). update swaps the meshes
in an existing .blend for render_sword's current model, keeping the rig and its keys:

  tools/blender -b --python tools/blender_sword.py -- update art/sword/sword.blend

reframe adds pixels (at the .blend's resolution) to the frame's left, top, right and
bottom edges, negative to take them away. The picture keeps its scale and everything
in it stays put; only the frame's edges move. In the game the strip's bottom-right
corner sits on the screen's, so growing the right edge moves the hand left on screen,
and growing the left or top only adds room for the swing:

  tools/blender -b --python tools/blender_sword.py -- reframe art/sword/sword.blend 240 400 0 0

render writes, for every frame of the .blend's range (--height H renders H pixels
tall instead of the .blend's resolution, the width in proportion: a quarter of the
.blend's height gives one render pixel per art pixel, as the game wants):

  frame_NN.png  numbered by Blender frame (01 to 12), on magenta, hard-edged
  sheet.png     the frames in a 4-wide grid with cyan separators, the layout
                tools/slice_frames.py reads

The rig. Everything hangs off the camera, so local coordinates are render_sword's
camera space: +X right, +Y up, looking down -Z, in metres.

  Camera
    Grip    empty at the middle of the grip, keyed per frame: the hand's position
            and turn. Pose the arm with this.
      Sword  mesh, turned GRIP_TWIST about the grip
      Fist   mesh: fingers, knuckles, thumb
      Wrist  empty, keyed per frame: X rotation is the wrist's cock, how far the
             blade leans off square to the forearm
        Hand     mesh: back of the hand, cuff
        Forearm  mesh, drawn long enough to leave the frame
    Sun     the key light

The meshes can't be selected in the viewport, so a click picks Grip or Wrist.
"""

import math
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import render_sword as model   # noqa: E402

AMBIENT = 0.2   # world light, linear: the floor of the colour ramps
SUN = 1.75      # irradiance, about 0.55 on a lit face after Lambert's 1/pi
GLOSS = 0.3     # roughness of the specular highlight
FRAME_GROWTH = (240, 400, 267, 0)
"""Pixels added to the left, top, right and bottom of the 800x600 frame the poses were
made in. The strip is drawn 4 screen pixels per render pixel, against the bottom-right
corner, so the grown frame reaches the screen's left and top edges: nothing is cut by
the strip's own edges."""


def linear(c):
    """sRGB 0-255 to scene-linear 0-1."""
    c = np.asarray(c, float) / 255
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


# --------------------------------------------------------------------------- build

def toon_material(name, ramp, shine):
    """Lambert (plus SHINE times a glossy highlight) quantized into RAMP's colours,
    emitted as is: the same bands render_sword computes."""
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nt.nodes.clear()
    nodes, links = nt.nodes, nt.links

    def light(bsdf_type, **inputs):
        bsdf = nodes.new(bsdf_type)
        for key, value in inputs.items():
            bsdf.inputs[key].default_value = value
        rgb = nodes.new("ShaderNodeShaderToRGB")
        links.new(bsdf.outputs[0], rgb.inputs["Shader"])
        bw = nodes.new("ShaderNodeRGBToBW")
        links.new(rgb.outputs["Color"], bw.inputs[0])
        return bw.outputs[0]

    level = light("ShaderNodeBsdfDiffuse", Color=(1, 1, 1, 1))
    if shine:
        gloss = light("ShaderNodeBsdfGlossy" if hasattr(bpy.types, "ShaderNodeBsdfGlossy")
                      else "ShaderNodeBsdfAnisotropic", Color=(1, 1, 1, 1), Roughness=GLOSS)
        scaled = nodes.new("ShaderNodeMath")
        scaled.operation = "MULTIPLY"
        links.new(gloss, scaled.inputs[0])
        scaled.inputs[1].default_value = shine * 0.25
        total = nodes.new("ShaderNodeMath")
        total.operation = "ADD"
        links.new(level, total.inputs[0])
        links.new(scaled.outputs[0], total.inputs[1])
        level = total.outputs[0]
    bands = nodes.new("ShaderNodeValToRGB")
    cr = bands.color_ramp
    cr.interpolation = "CONSTANT"
    n = len(ramp)
    # render_sword rounds t * (n - 1): colour k from (k - 0.5) / (n - 1)
    while len(cr.elements) < n:
        cr.elements.new(0.5)
    for k, (el, col) in enumerate(zip(cr.elements, ramp)):
        el.position = 0.0 if k == 0 else (k - 0.5) / (n - 1)
        el.color = (*linear(col), 1.0)
    links.new(level, bands.inputs["Fac"])
    emit = nodes.new("ShaderNodeEmission")
    links.new(bands.outputs["Color"], emit.inputs["Color"])
    out = nodes.new("ShaderNodeOutputMaterial")
    links.new(emit.outputs[0], out.inputs["Surface"])
    return mat


def model_meshes():
    """Each mesh object's parts, by object name."""
    return {"Sword": model.blade_parts(), "Fist": model.fist_parts(), "Hand": model.back_parts(),
            "Forearm": model.arm_parts(model.WRIST, np.array([0.0, 0.0, 1.0]))}


def make_mesh(name, labelled, materials):
    """A mesh from render_sword's (name, [Part]) list."""
    verts, faces, smooth, mat_index = [], [], [], []
    slots = []
    for _, parts in labelled:
        for part in parts:
            if part.material not in slots:
                slots.append(part.material)
            base = len(verts)
            verts += part.verts.tolist()
            faces += (part.faces + base).tolist()
            smooth += [part.smooth] * len(part.faces)
            mat_index += [slots.index(part.material)] * len(part.faces)
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(verts, [], faces)
    mesh.polygons.foreach_set("use_smooth", smooth)
    mesh.polygons.foreach_set("material_index", mat_index)
    for slot in slots:
        mesh.materials.append(materials[slot])
    mesh.validate()
    return mesh


def mesh_object(name, labelled, materials, parent, matrix=None):
    """One object from render_sword's (name, [Part]) list, in PARENT's space."""
    obj = bpy.data.objects.new(name, make_mesh(name, labelled, materials))
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    if matrix is not None:
        obj.matrix_basis = matrix
    obj.hide_select = True
    return obj


def empty(name, parent, display, size):
    obj = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(obj)
    obj.parent = parent
    obj.empty_display_type = display
    obj.empty_display_size = size
    return obj


def setup_render(scene):
    scene.render.engine = "BLENDER_EEVEE"
    scene.render.resolution_x, scene.render.resolution_y = 800, 600
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = True
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGBA"
    scene.view_settings.view_transform = "Standard"
    scene.view_settings.look = "None"
    scene.render.use_freestyle = True
    scene.render.line_thickness_mode = "ABSOLUTE"
    scene.render.line_thickness = 2.0
    fs = bpy.context.view_layer.freestyle_settings
    ls = fs.linesets[0] if fs.linesets else fs.linesets.new("outline")
    ls.select_by_visibility = True
    ls.visibility = "VISIBLE"
    ls.select_by_edge_types = True
    for flag in ("select_silhouette", "select_border", "select_contour",
                 "select_external_contour", "select_material_boundary", "select_crease"):
        setattr(ls, flag, True)
    if ls.linestyle is None:
        ls.linestyle = bpy.data.linestyles.new("outline")
    ls.linestyle.color = linear(model.OUTLINE)
    ls.linestyle.thickness = 2.0
    world = bpy.data.worlds.new("ambient")
    world.use_nodes = True
    bg = world.node_tree.nodes["Background"]
    bg.inputs["Color"].default_value = (AMBIENT, AMBIENT, AMBIENT, 1)
    bg.inputs["Strength"].default_value = 1.0
    scene.world = world


def build(path, force):
    if path.exists() and not force:
        sys.exit(f"{path} exists; its poses may have been edited by hand. Pass --force to rebuild it.")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    setup_render(scene)
    scene.frame_start, scene.frame_end = 1, len(model.POSES)
    scene.render.fps = 12

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(model.VFOV)
    cam_data.clip_start = model.NEAR
    camera = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = (math.pi / 2, 0, 0)   # looks down world +Y, world +Z up
    scene.camera = camera
    grow(scene, *FRAME_GROWTH)

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = SUN
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.parent = camera
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector(model.LIGHT).to_track_quat("Z", "Y")

    materials = {name: toon_material(name, ramp, model.SHINE[name])
                 for name, ramp in model.RAMPS.items()}
    grip = empty("Grip", camera, "ARROWS", 0.06)
    grip.rotation_mode = "QUATERNION"
    wrist = empty("Wrist", grip, "CIRCLE", 0.05)
    wrist.location = (0, 0, 0)
    meshes = model_meshes()
    mesh_object("Sword", meshes["Sword"], materials, grip,
                Matrix(model.twist(model.GRIP_TWIST)).to_4x4())
    mesh_object("Fist", meshes["Fist"], materials, grip)
    mesh_object("Hand", meshes["Hand"], materials, wrist)
    mesh_object("Forearm", meshes["Forearm"], materials, wrist)

    previous = None
    for frame, p in enumerate(model.POSES, 1):
        q = Matrix(p["rot"]).to_quaternion()
        if previous is not None:
            q.make_compatible(previous)
        previous = q
        grip.location = p["pos"]
        grip.rotation_quaternion = q
        wrist.rotation_euler = (math.radians(p["cock"]), 0, 0)
        grip.keyframe_insert("location", frame=frame)
        grip.keyframe_insert("rotation_quaternion", frame=frame)
        wrist.keyframe_insert("rotation_euler", frame=frame)
    scene.frame_set(1)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path.resolve()))
    print(f"wrote {path}")


def grow(scene, left=0, top=0, right=0, bottom=0):
    """Add pixels to each edge of the frame (negative to take them away), keeping the
    picture's scale and everything in it where it is: the field of view grows with
    the frame and the camera shift recentres it. With a vertical sensor fit, shifts
    are in frame heights."""
    r, cam = scene.render, scene.camera.data
    assert cam.sensor_fit == "VERTICAL"
    w0, h0 = r.resolution_x, r.resolution_y
    focal = (h0 / 2) / math.tan(cam.angle_y / 2)   # in pixels, unchanged
    # the frame's edges in pixels from the optical axis, +y up
    l, rt = cam.shift_x * h0 - w0 / 2 - left, cam.shift_x * h0 + w0 / 2 + right
    b, t = cam.shift_y * h0 - h0 / 2 - bottom, cam.shift_y * h0 + h0 / 2 + top
    w, h = round(rt - l), round(t - b)
    r.resolution_x, r.resolution_y = w, h
    cam.angle_y = 2 * math.atan((h / 2) / focal)
    cam.shift_x = (l + rt) / 2 / h
    cam.shift_y = (b + t) / 2 / h


def reframe(path, left, top, right, bottom):
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    scene = bpy.context.scene
    grow(scene, left, top, right, bottom)
    bpy.ops.wm.save_mainfile()
    cam = scene.camera.data
    print(f"{path}: frame {scene.render.resolution_x}x{scene.render.resolution_y}, "
          f"vertical fov {math.degrees(cam.angle_y):.2f}, shift {cam.shift_x:.4f} {cam.shift_y:.4f}")


def update(path):
    """Swap the meshes in the .blend at PATH for render_sword's current model, keeping
    the rig, the keys and everything else."""
    bpy.ops.wm.open_mainfile(filepath=str(path.resolve()))
    materials = {m.name: m for m in bpy.data.materials}
    for name, labelled in model_meshes().items():
        obj = bpy.data.objects[name]
        old = obj.data
        obj.data = make_mesh(name, labelled, materials)
        bpy.data.meshes.remove(old)
        obj.data.name = name
    bpy.ops.wm.save_mainfile()
    print(f"updated the model in {path}")


# --------------------------------------------------------------------------- render

def read_png(path):
    img = bpy.data.images.load(str(path), check_existing=False)
    w, h = img.size
    px = np.empty(w * h * 4, np.float32)
    img.pixels.foreach_get(px)
    bpy.data.images.remove(img)
    return np.flipud(px.reshape(h, w, 4))   # top row first


def write_png(path, rgb):
    h, w = rgb.shape[:2]
    img = bpy.data.images.new(path.stem, w, h, alpha=True)
    rgba = np.concatenate([rgb, np.ones((h, w, 1), np.float32)], 2)
    img.pixels.foreach_set(np.flipud(rgba).ravel())
    img.filepath_raw = str(path)
    img.file_format = "PNG"
    img.save()
    bpy.data.images.remove(img)


def render(blend, out, height):
    bpy.ops.wm.open_mainfile(filepath=str(blend.resolve()))
    scene = bpy.context.scene
    r = scene.render
    if height:
        r.resolution_x = round(r.resolution_x * height / r.resolution_y)
        r.resolution_y = height
        r.line_thickness = max(1.0, round(height / 300))
    out = out.resolve()
    raw = out / "rgba"
    raw.mkdir(parents=True, exist_ok=True)
    magenta = np.array(model.MAGENTA, np.float32) / 255
    frames = []
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
        scene.render.filepath = str(raw / f"frame_{f:02d}.png")
        bpy.ops.render.render(write_still=True)
        rgba = read_png(raw / f"frame_{f:02d}.png")
        rgb = np.where(rgba[..., 3:] >= 0.5, rgba[..., :3], magenta)
        write_png(out / f"frame_{f:02d}.png", rgb)
        frames.append(rgb)
        print(f"frame {f:2d}")
    h, w = frames[0].shape[:2]
    cols, rows = 4, (len(frames) + 3) // 4
    sheet = np.empty((rows * h + rows + 1, cols * w + cols + 1, 3), np.float32)
    sheet[:] = np.array(model.CYAN, np.float32) / 255
    for i, rgb in enumerate(frames):
        y, x = 1 + (i // cols) * (h + 1), 1 + (i % cols) * (w + 1)
        sheet[y:y + h, x:x + w] = rgb
    write_png(out / "sheet.png", sheet)
    print(out / "sheet.png")


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv[:1] == ["build"] and len(argv) >= 2:
        build(Path(argv[1]), "--force" in argv)
    elif argv[:1] == ["update"] and len(argv) >= 2:
        update(Path(argv[1]))
    elif argv[:1] == ["reframe"] and len(argv) >= 6:
        reframe(Path(argv[1]), *(int(x) for x in argv[2:6]))
    elif argv[:1] == ["render"] and len(argv) >= 3:
        height = int(argv[argv.index("--height") + 1]) if "--height" in argv else None
        render(Path(argv[1]), Path(argv[2]), height)
    else:
        sys.exit(__doc__)


main()
