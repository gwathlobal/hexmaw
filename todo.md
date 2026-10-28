# To do

## Redo the first-person sword and hands

Both are placeholders that will do for now.

- **Sword** (`data/sprites/sword`): the generated restyle is noisy below its pixel grid, and
  its blade outline is jagged. The idle blade is drawn thin and dark olive, while the slash
  blade is bright steel, so the blade changes colour when the swing returns to idle. The
  generator also shifts details between frames.
- **Hands** (`data/sprites/hands`): sliced from generated sheets the same way, with the same
  limits. Most of the idle row has no palm fire, so `*hands-idle-sequence*` loops the
  cast's rest frames instead. The hands still use wide pixels (`*hands-stretch*`); the
  sword no longer does.

The 3D pipeline (`art/sword.blend`, `tools/blender_sword.py`) gives correct poses. What's
missing is a restyle with a clean pixel grid and a consistent palette across frames.
