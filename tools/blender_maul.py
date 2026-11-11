"""Blender rig and renderer for the first-person maul: the model and poses of tools/render_maul.py
in a .blend you can pose by hand, rendered toon-shaded with Freestyle outlines, as
tools/blender_sword.py does the sword (whose materials, render settings and PNG helpers it uses):

  tools/blender -b --python tools/blender_maul.py -- build art/maul/maul.blend
  tools/blender -b --python tools/blender_maul.py -- render art/maul/maul.blend art/maul/renders

build writes the .blend from render_maul.POSES, one Blender frame per pose (it won't overwrite
one unless given --force: after the first build the poses live in the .blend). render writes,
for every frame, frame_NN.png, the whole 1536 x 1024 screen on magenta, numbered by Blender frame
(01 to 09: idle, raise, charged, strike, impact, recover, shake-lift, shake-swing, shake-slam).

The rig. Everything hangs off the camera, so local coordinates are render_maul's camera space:
+X right, +Y up, looking down -Z, in metres.

  Camera
    Maul        empty at the haft's end, keyed per frame; its Y is the haft, its Z the head's
                long axis. Pose the maul with this.
      MaulMesh  haft, grip, bands, socket and the steel head
    RightGrip   empty at the middle of the right fist, keyed per frame: keep it on the haft
      RightFist, RightOpenFist (the haft resting on the palm; which one shows is keyed per frame),
      RightWrist (X rotation: the wrist's cock) > RightHand, RightForearm
    LeftGrip    the same for the left, its meshes mirrored
    Sun         the key light

The meshes can't be selected in the viewport, so a click picks an empty.
"""

import math
import shutil
import sys
from pathlib import Path

import bpy
import numpy as np
from mathutils import Matrix, Vector

sys.path.insert(0, str(Path(__file__).resolve().parent))
import blender_sword as bs   # noqa: E402
import render_maul as model   # noqa: E402
import render_sword as rs   # noqa: E402

WIDTH, HEIGHT = 1536, 1024
LINE = 3.0   # outline thickness in pixels at 1024 tall


def hand_meshes(left):
    """The gauntlet's parts by object: the fist, the open fist (render_maul's OPEN_HAND), the back
    of the hand and the forearm, mirrored for LEFT."""
    flip = model.mirrored if left else (lambda parts: parts)
    wrist = rs.WRIST * (model.MIRROR.diagonal() if left else 1)
    return {"Fist": flip(model.fist_parts()), "OpenFist": flip(model.fist_parts(True)),
            "Hand": flip(rs.back_parts()), "Forearm": rs.arm_parts(wrist, np.array([0.0, 0.0, 1.0]))}


def show(obj, shown, frame):
    obj.hide_render = obj.hide_viewport = not shown
    obj.keyframe_insert("hide_render", frame=frame)
    obj.keyframe_insert("hide_viewport", frame=frame)


def build(path, force):
    if path.exists() and not force:
        sys.exit(f"{path} exists; its poses may have been edited by hand. Pass --force to rebuild it.")
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    bs.setup_render(scene)
    scene.render.resolution_x, scene.render.resolution_y = WIDTH, HEIGHT
    scene.render.line_thickness = LINE
    bpy.context.view_layer.freestyle_settings.linesets[0].linestyle.thickness = LINE
    scene.frame_start, scene.frame_end = 1, len(model.POSES)
    scene.render.fps = 12

    cam_data = bpy.data.cameras.new("Camera")
    cam_data.sensor_fit = "VERTICAL"
    cam_data.angle_y = math.radians(rs.VFOV)
    cam_data.clip_start = rs.NEAR
    camera = bpy.data.objects.new("Camera", cam_data)
    scene.collection.objects.link(camera)
    camera.rotation_euler = (math.pi / 2, 0, 0)   # looks down world +Y, world +Z up
    scene.camera = camera

    sun_data = bpy.data.lights.new("Sun", "SUN")
    sun_data.energy = bs.SUN
    sun = bpy.data.objects.new("Sun", sun_data)
    scene.collection.objects.link(sun)
    sun.parent = camera
    sun.rotation_mode = "QUATERNION"
    sun.rotation_quaternion = Vector(rs.LIGHT).to_track_quat("Z", "Y")

    materials = {name: bs.toon_material(name, ramp, model.SHINE[name]) for name, ramp in model.RAMPS.items()}
    maul = bs.empty("Maul", camera, "ARROWS", 0.08)
    maul.rotation_mode = "QUATERNION"
    bs.mesh_object("MaulMesh", model.maul_parts(), materials, maul)
    grips, wrists = [], []
    for side, left in (("Right", False), ("Left", True)):
        grip = bs.empty(f"{side}Grip", camera, "ARROWS", 0.06)
        grip.rotation_mode = "QUATERNION"
        wrist = bs.empty(f"{side}Wrist", grip, "CIRCLE", 0.05)
        meshes = hand_meshes(left)
        fists = (bs.mesh_object(f"{side}Fist", meshes["Fist"], materials, grip),
                 bs.mesh_object(f"{side}OpenFist", meshes["OpenFist"], materials, grip))
        bs.mesh_object(f"{side}Hand", meshes["Hand"], materials, wrist)
        bs.mesh_object(f"{side}Forearm", meshes["Forearm"], materials, wrist)
        grips.append(grip)
        wrists.append((wrist, fists))

    previous = [None, None, None]
    for frame, p in enumerate(model.POSES, 1):
        targets = [(maul, p["end"], p["rot"], None)] + [
            (grip, hp["pos"], hp["rot"], (wrist, hp["cock"], fists, hp["open"]))
            for (hp, _), grip, (wrist, fists) in zip(p["hands"], grips, wrists)]
        for k, (obj, pos, rot, wrist) in enumerate(targets):
            q = Matrix(rot).to_quaternion()
            if previous[k] is not None:
                q.make_compatible(previous[k])
            previous[k] = q
            obj.location = pos
            obj.rotation_quaternion = q
            obj.keyframe_insert("location", frame=frame)
            obj.keyframe_insert("rotation_quaternion", frame=frame)
            if wrist:
                wrist[0].rotation_euler = (math.radians(wrist[1]), 0, 0)
                wrist[0].keyframe_insert("rotation_euler", frame=frame)
                fist, open_fist = wrist[2]
                show(fist, not wrist[3], frame)
                show(open_fist, wrist[3], frame)
    # Every pose is its own picture, held until the next: no in-betweens.
    for action in bpy.data.actions:
        for fc in getattr(action, "fcurves", []):
            for kp in fc.keyframe_points:
                kp.interpolation = "CONSTANT"
    scene.frame_set(1)
    path.parent.mkdir(parents=True, exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(path.resolve()))
    print(f"wrote {path}")


def render(blend, out):
    bpy.ops.wm.open_mainfile(filepath=str(blend.resolve()))
    scene = bpy.context.scene
    out = out.resolve()
    raw = out / "rgba"
    raw.mkdir(parents=True, exist_ok=True)
    magenta = np.array(rs.MAGENTA, np.float32) / 255
    for f in range(scene.frame_start, scene.frame_end + 1):
        scene.frame_set(f)
        scene.render.filepath = str(raw / f"frame_{f:02d}.png")
        bpy.ops.render.render(write_still=True)
        rgba = bs.read_png(raw / f"frame_{f:02d}.png")
        rgb = np.where(rgba[..., 3:] >= 0.5, rgba[..., :3], magenta)
        bs.write_png(out / f"frame_{f:02d}.png", rgb)
        print(f"frame {f:2d} {model.POSES[f - 1]['name']}")
    shutil.rmtree(raw)   # Blender's own RGBA renders, keyed to magenta above


def main():
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    if argv[:1] == ["build"] and len(argv) >= 2:
        build(Path(argv[1]), "--force" in argv)
    elif argv[:1] == ["render"] and len(argv) >= 3:
        render(Path(argv[1]), Path(argv[2]))
    else:
        sys.exit(__doc__)


main()
