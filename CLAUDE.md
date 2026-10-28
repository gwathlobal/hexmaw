# hexmaw

POC for a first-person, real-time roguelike (Daggerfall dungeons, Hexen combat), in
Common Lisp on [Trial](https://shirakumo.github.io/trial). The brief is at
https://claude.ai/artifact/MikuSfUo5bY4Au8CHie4XG. The current goal is the 2-week
engine spike: first-person controller, one imported block, the imp as a billboard,
one bolt spell with a hit reaction.

## Running

```bash
./run.sh
```

Opens the game window and an eval server on `127.0.0.1:7171` (`HEXMAW_EVAL_PORT` to
change it). `HEXMAW_SWANK_PORT=4005 ./run.sh` also starts Swank for an editor.
The game opens in a 1280×720 window; `HEXMAW_FULLSCREEN=1 ./run.sh` starts it fullscreen.
It starts on the main menu with the world frozen; `HEXMAW_SKIP_MENU=1 ./run.sh` starts
straight in play, or run `tools/hd '(game (start-game))'` after launching.
The process exits when the window closes.

Every Lisp session on this project goes through `boot.lisp`:
`sbcl --dynamic-space-size 4096 --no-userinit --load boot.lisp`. Trial needs at
least 2 GB of heap. Dependencies come from the project-local Quicklisp in `.ql/`
(Shirakumo dist, not checked in), and ASDF is limited to this folder because other
projects under `~/common-lisp/` ship conflicting copies of Trial's dependencies.

## Live reload: how changes reach the game

A PostToolUse hook (`.claude/settings.json` → `tools/claude-reload-hook.sh`) reloads
every file you edit under `src/` into the running game. You don't need to restart.

- Success: you get `Hot reload: Reloaded src/<file>.` in context.
- Compile failure (errors or full WARNINGs such as undefined variables): nothing is
  loaded, the game keeps the previous code, and the hook reports the compiler output.
  Fix it before moving on.
- Runtime failure: the new code is loaded, but some event handler now signals errors.
  The game skips the failing event every frame instead of crashing, and the hook
  reports the error with a backtrace. Fix it or revert.
- Game not running: the hook stays silent. Start `./run.sh` if you need to check
  behaviour.

When one change spans several files, an intermediate reload may fail, for example
because the call site is edited before the function exists. That's expected; the
next edit's reload tells you whether the whole change works.

`tools/hd` talks to the game directly:

| Command | What it does |
| --- | --- |
| `tools/hd status` | Game state (menu, paused, playing), player position and view, runtime errors firing now |
| `tools/hd screenshot` | Saves the current frame, prints the PNG path. Read it to check visual changes |
| `tools/hd errors` | Recent runtime errors with backtraces |
| `tools/hd reset` | Rebuilds the scene from `setup-scene` and waits until it has drawn; the player keeps position and view |
| `tools/hd reload-system` | Reloads everything through ASDF (after changing a macro or the .asd), then rebuilds the scene |
| `tools/hd '(form)'` | Evaluates a form in package `hexmaw` on the server thread |

Wrap anything that changes the scene, entities or GL state in `(game ...)` so it
runs on the game thread between frames, for example
`tools/hd '(game (respawn *player*))'`. Reads such as `(feet *player*)` don't need it.

`tools/compare_shots.sh DIR` saves a fixed set of views (spawn, the imp from several
angles, a bolt in flight, the corridor, the imp under a torch, the test room) to
`DIR/<shot>.png`, for comparing
rendering changes; `SHOTS="spawn bolt"` limits it. It leaves the game paused.

**Verify visual work with a screenshot, not just a clean reload.** A shader can
compile and render garbage. If `screenshot` says the window is minimised, run
`tools/hd '(show-window)'` first.

If reloads time out ("the game is probably frozen"), an error escaped into the render
thread. Check the game's output, then restart `./run.sh`.

## Writing code that survives reloading

- Use `defclass`/`define-shader-entity`, never `defstruct`, for anything you may
  change. Redefined classes update live instances; a redefined struct breaks them.
- Tuning values go in `defparameter` so a reload picks up the new value. `defvar` is
  for state that must survive reloads (`*player*`, `*solids*`, the error log).
- `defconstant` can't be redefined. Don't use it for anything you might change.
- Changes to `build-level`, `setup-scene` or an entity's initforms only affect objects
  created afterwards. Run `tools/hd reset` to see them.
- A slot added to a live class gets its `:initform`, but `initialize-instance :after`
  doesn't run again, so slots it fills stay unbound on existing objects (expect
  "slot is unbound" runtime errors). Run `tools/hd reset`.
- Menu panels (Alloy) build their layout when created. After changing a panel class
  or `panel-buttons`, run `tools/hd reset`, which recreates the panel on screen. The
  menu pass itself survives resets (`persistent-menu-ui`): a fresh one re-reads every
  font from disk, about 300 ms. A reset still freezes for about 0.3 s, because Trial
  runs a full GC whenever it swaps scenes.
- Something spawned mid-game (projectiles) needs `(preload 'class scene)` in
  `setup-scene`, or its shader isn't loaded when it first appears.
- A subclass's `define-handler` replaces the parent's handler for that event. Use a
  qualifier, as in `(define-handler (creature tick :after) ...)`, to add to it.
- Changing a macro or an inline function: run `tools/hd reload-system` so callers
  recompile.
- Shader code (`define-class-shader`) refreshes automatically on reload.
- Reloading a file that contains `define-asset` makes Trial reload those assets, which
  stops entities already using them from drawing. The reload tool rebuilds the scene
  automatically for such files and says so ("Scene reloaded because this file defines
  assets"); creatures reset with it. `reload-system` always rebuilds it, since ASDF
  reloads every file after the first changed one. Anything else that loads such a file
  (an editor's compile-file over Swank) leaves the HUD, weapons and creatures invisible
  until `tools/hd reset`. Only a definition at the start of a line counts.
- Trial shadows some CL symbols with its own generics, `load` among them. Use
  `cl:load` for files.

## Per-frame code

Tick handlers and render methods run 100 times a second. Avoid allocating in them:
no `vec`/`v+`/`list` per frame. Mutate existing vectors with `(setf (vx v) ...)`,
`nv+`, or reuse preallocated ones. SBCL's GC pauses show up as hitches.

## Layout and conventions

- `src/dev.lisp`: eval server, reload, runtime-error guard, screenshots. Dev only.
- `src/greybox.lisp`: untextured level geometry (`greybox` entity, fog, `add-box`, `*solids*`),
  and `lit-entity`, the shader mixin whose `light_at` lights the level and billboards from
  the `lamp-block` uniform buffer.
- `src/lights.lisp`: point lights (`lamp`s in `*lamps*`, which `build-level` empties).
  `add-torch` places a flickering lamp and a flame sprite; `attach-glow` gives an entity a
  lamp that follows it and goes out when it leaves the scene (the bolt and its burst).
  Each frame `gather-lights` (from `main`'s render) drops the lamps that could only light
  fogged-out surfaces (further than `*fog-end*` plus their radius), sorts the rest nearest
  first, and writes up to `*max-lights*` of them (128, the size of `lamp-block`'s array in
  greybox.lisp) into the `lamp-block` uniform buffer that every lit shader reads. It writes
  the buffer's memory directly: setting a gl-struct field through `slot-value` allocates.
  Light is ambient (`*ambient-color*`) plus each lamp, down to half at `*light-falloff*`
  metres and fading smoothly to nothing at its radius; the shader skips lamps out of reach.
  Walls take the angle to the light; sprites ignore it, so the side of the imp nearer a
  torch is brighter. A world grid (`*wall-light-snap*`, `*sprite-light-snap*`) and
  brightness bands (`*wall-light-bands*`, `*sprite-light-bands*`) give a blocky retro look
  instead; 0, the default, turns them off. Torches stop flickering while the world is
  frozen. No shadows: light goes through walls. Effects and the HUD stay unlit.
- `src/nav.lisp`: the nav grid, where creatures can stand and how they get around; see
  "Creature movement" below.
- `src/sprite.lisp`: Doom-style `billboard` sprites (view by angle, mirroring, tint, lit), and
  frame animations from `tools/slice_frames.py` strips (`define-fx-animation`).
  Assets live in `data/` (Trial pool `hexmaw`).
- `src/creature.lisp`: `creature` (health, hit reaction: flash, flinch, knockback, hit-stop;
  death and revival; wandering, hunting and attacking the player, and the walk and attack
  animations), `*creatures*` for hit tests, bodies (collision between actors), and the `imp`. A creature's
  `death-animation` plays once on death, front view from every angle, and its last frame
  stays as the corpse until revival; without one it collapses into the floor. The `acolyte`
  is the ranged one (`attack-spell`), with a cast, flinch and death but no walk: it glides
  in the standing pose, its robe hiding its feet. Its death burns, so it has a `death-glow`:
  a lamp that rises and fades with the fire on `death-glow-times`, then leaves `*lamps*`.
- `src/blocks.lisp`: level blocks from glTF (`find-block`, `place-block`, `attach-block`,
  `seal-connector`); see "Level blocks" below.
- `src/fx.lisp`: animated camera-facing effect sprites (`fx-sprite`, `spawn-fx`); fullbright,
  no fog. Projectiles are effect sprites.
- `src/spells.lisp`: the composable spell model (`define-spell`, effects, `spell-cost`),
  projectile delivery, the player's `bolt` and the acolyte's `cinder`. A new effect kind is
  a method on `apply-effect`, for a `creature` target and (in player.lisp, loaded later) a
  `player` one. A projectile hits any live creature or the player except its `caster`.
- `src/hud.lisp`: HP and mana bars in the lower-left corner, and the red pain flash over
  the view (`pain-flash`, from the player's `pain`). HUD pieces are `hud-element`
  entities drawn in pixel coordinates (origin bottom left) at the near plane; place them
  on whole pixels, since a half-pixel position drops an edge row. Overlapping elements
  take a depth in `place` (below 0 is further back). `hud-top` is where the bars end.
- `src/menu.lisp`: the main menu and the Esc pause menu, built with Alloy (Trial's UI
  toolkit) in their own pass, blended over the game in `setup-scene`. `*game-state*`
  (`:title`, `:playing`, `:paused`, defined in creature.lisp) decides which is up;
  anything but `:playing` makes `frozen-p` true, which stops everything that moves.
  Transitions: `start-game`, `pause-game`, `resume-game`, `show-title`,
  `exit-to-title` (the pause menu's exit: back to the main menu, with the level put back
  in place by `reset-run`, no scene rebuild)
  and `exit-game` (quits; main menu only).
  A new menu is a `menu-panel` subclass with `panel-title` and `panel-buttons`.
- `src/hands.lisp`: the first-person casting hands, sunk Hexen-style below the bottom
  edge (idle loop, cast, walking sway). Each hand is its own entity drawing half the
  frame, spread apart and closing up where they meet (`*hands-together*`). Scales are
  whole numbers, wider than tall (`*hands-stretch*`). The cast's release frame is timed
  to `*cast-release*`.
- `src/sword.lisp`: the sword and weapon switching. The player holds one weapon (`*weapons*`:
  1 the sword, 2 the casting hands); switching lowers one off screen and raises the next.
  The sword is a single sprite against the bottom-right corner (its arm runs off that edge,
  so `*sword-overhang*` must exceed the sway). The slash plays `*swing-frame-times*` and the
  blow lands on `*swing-hit-frame*`: the nearest creature within `*sword-reach*` and
  `*sword-arc*`, not behind a wall. Number keys pick a weapon, the mouse wheel cycles
  (`cycle-weapon`). The weapon slots above the HP bar (`weapon-bar`) show one icon per
  weapon in `*weapons*` with its key number, the one asked for framed in gold. Icons are
  frames of `data/sprites/icons/weapons.png` (`*weapon-icons*`), drawn by
  `tools/draw_weapon_icons.py data/sprites/icons/weapons`; a new weapon needs a frame there.
- `src/player.lisp`: first-person controller and box collision.
- `src/level.lisp`: the greybox test level.
- `src/main.lisp`: `main`, `setup-scene`, `status`, `launch`, `dev-launch`.

Units are metres, +Y is up, and the player spawns at `*spawn-point*` facing −Z
(north). Collision is axis-aligned boxes in `*solids*`, resolved one axis at a time.
Actors (the player and live creatures, not corpses) are bodies: upright boxes that block
each other the same way, found by `body-overlapping` rather than kept in `*solids*`,
since they move. A new kind of actor gives methods on `body-feet`, `body-radius`,
`body-height` and `body-solid-p`. An actor already inside another body (a revival on
top of the player, say) may walk out of it; a corpse waits to revive until its spawn point is clear.
A walking player steps up and down ledges of up to `*step-height*` (0.45 m); anything
taller needs a jump (0.45 m is also the most a block can rise per step in level design).
On a step the camera holds its height and eases to the new one.

To test movement without a mouse or keyboard (in play, not on a menu), hold keys from the eval server:
`tools/hd '(game (setf (vy (rotation *player*)) 0.0 (retained :w) t))'`, wait, then
`(setf (retained :w) nil)` and check `tools/hd status`. Yaw 0 faces −Z, π/2 faces +X.

## Creature movement

`build-level` ends with `build-nav-grid`, which cuts the level into 0.5 m cells
(`*nav-cell*`) and records for each its floor height, headroom and clearance (the widest
body that fits, to 0.125 m, up to 2 m; solids less than 0.45 m above the floor don't count,
so steps aren't walls). A creature fits a cell when clearance ≥ its `body-radius` and
headroom ≥ its `sprite-height`, and moves to a neighbour when the floors differ by at most
its `step-height`, so one grid serves every size. Each cell holds one floor, the lowest
with room above it; under a pillar, that's the roof above it. The geometry questions
go through `floor-candidates`, `ceiling-above` and `fits-at-p`, the only code that knows solids
are boxes.

A creature wanders: it stands for `*wander-pause*` seconds, then `nav-reachable-spot` picks
a random cell it can walk to within `wander-radius` of its home (or of itself, if knocked
too far away), and it follows the smoothed path at `walk-speed`, facing the way it goes.
`settle` eases it onto the floor under it. A hit stops it for `*hurt-pause*`, then it plans
afresh. It slides along any body in its way (`move-creature`, which also moves knockback);
blocked for `*stuck-time*`, it gives up the path and plans another after `*stuck-pause*`.
The nav grid ignores bodies, so paths still run through them.

A creature with `attack-damage` also hunts (`think`). It notices the player in front of it
within `*sight-range*` with nothing solid between them, or anywhere within `*hearing-range*`,
and whenever it's hit; it stays alert for `*alert-time*` after the last time. While alert it
runs at `chase-speed`, straight at the player when the nav grid allows a straight walk, else
along `nav-path-to`, replanned every `*chase-replan*`. Within `*attack-start-reach*` of its
`attack-reach` it stops and attacks: the frames run on `attack-frame-times` (it turns to
follow the player through the first), and on `attack-hit-frame` the blow lands if the player
is still within `attack-reach`, inside `attack-arc` and not behind a wall (`hurt-player`:
damage, a shove, the pain flash, hit-stop). Backing off during the wind-up dodges it, and a
hit breaks the attack off. Then it stands `attack-pause` and hunts on.

A caster (a creature with `attack-spell`, the acolyte) hunts from range instead
(`hunt-from-range`): within `attack-range` and with a clear line to the player it stops and
casts, turning to follow the player until `attack-hit-frame`, when the spell leaves aimed at
where the player stands then (no leading, so a sidestep dodges it), from `cast-offset` to the
right of its centre line, where the casting hand is. Closer than `keep-away` it backs off
`*retreat-step*` metres along a straight walk the nav grid allows (`retreat`), and casts
point-blank when cornered; out of range or sight it closes in as a melee creature does. At zero health the player's run starts over (`reset-run`); there's no death screen yet.

`tools/hd '(game (show-nav))'` lays green tiles on the cells within 8 m of the player that
an imp-sized body fits; `(show-nav :radius 1.0 :height 2.5)` shows a bigger one, and
`(hide-nav)` or a reset clears them. `tools/hd status` shows each creature's `brain`
(`idle`, `walking` or `attacking`).

## Generating art

`tools/gen_image.py` generates images with OpenAI's image models, so prompts don't need
to go through ChatGPT by hand. With `--ref` images (a design reference, a turnaround,
a Blender render) it restyles or extends them; without, it generates from the prompt alone.
Output lands at full resolution where you name it, with a `<stem>.prompt.json` beside it
recording the prompt, references and options:

```bash
tools/gen_image.py art/imp/attack-1.png --prompt-file art/prompts/imp-attack.txt --ref "art/imp/Four-frame pixel imp walk cycle (frame 1).png" --size 1536x1024
```

By default it goes through the Codex CLI (`codex exec`, signed in with the ChatGPT
account), whose built-in image tool counts against the ChatGPT plan instead of being
billed. Codex runs locked down (no shell, plugins or browser) in a temp folder. One image
per run, about 45 s, so run it in the background; `-n 3` makes three runs. Size and
background are requests in the prompt (1536x1024 came back exact), and `--quality` does
nothing there. `--backend api` calls the paid Image API instead (key in `$OPENAI_API_KEY`
or `~/.config/openai/api_key`), which honours size, quality and `--mask` exactly.

Neither keeps a conversation the way ChatGPT does: every call carries the full prompt and
every reference it needs, so a follow-up pose attaches the earlier result as a `--ref`.
Keep prompts worth repeating as files under `art/prompts/`, and `--dry-run` a new command
line to see what will be sent.

## Monster sprites

A monster starts as a 5-view turnaround sheet (front, front-quarter, side,
back-quarter, back; magenta background, cyan separators). `tools/slice_turnaround.py`
keys and slices it into `data/sprites/<monster>/turnaround.png` plus a `.lisp` index:

```bash
python3 tools/slice_turnaround.py "Pixel Demon Character Turnaround.png" data/sprites/imp/turnaround --height 96 --mirror back-quarter
```

The acolyte's sheet is `art/acolyte/turnaround-2.png`, generated by `tools/gen_image.py` from
`art/prompts/acolyte-turnaround.txt` with the imp's sheet as the style reference. It is
sliced at `--height 115` (and `--mirror back-quarter`) so that, at `*acolyte-height*` 1.8 m,
its art pixels match the imp's.

The game assumes the three turned views face image-left and mirrors them for the
other side. Generated sheets aren't always consistent (the imp's back-quarter faced
right), so look at each view and pass the odd ones to `--mirror`. To check angle
selection in game, orbit the camera around the sprite and screenshot each 45°.

Effect animations (projectiles, impacts) start as a grid of frames, same magenta and
cyan convention; rows and cell sizes may be uneven, and empty cells are skipped.
`tools/slice_frames.py` writes one strip per animation, `<name>.png` plus `.lisp`, and
also removes the pink glow generators paint into the background. `--pixel` is the size
of one art pixel in the source:

```bash
python3 tools/slice_frames.py "Bolt Spell Sheet.webp" data/sprites/bolt --pixel 5 flight:5 burst:7
```

First-person HUD sprites (the hands) have arms cut off by the screen edge, wherever the
generator happened to cut them; `--anchor bottom` puts each frame's lowest solid row on
the strip's bottom edge instead of keeping the cell centre. The hands are one 12-frame
strip (4 idle, then 8 cast), so every frame shares one crop. Their sheet,
`Fire Hands Sheet.png`, is two generated sheets (idle row, then the cast) stacked with a
cyan line between:

```bash
python3 tools/slice_frames.py "Fire Hands Sheet.png" data/sprites/hands --pixel 4 --anchor bottom hands:12
```

The sword is one 12-frame strip (4 idle, then an 8-frame slash), each cell about 326 × 250
art pixels (the height `*sword-height*` expects), drawn with square pixels
(`*sword-stretch*` 1.0, unlike the hands). It starts as a 3D
model posed in Blender: `art/sword.blend`, rigged and rendered by `tools/blender_sword.py`
(its docstring covers build, update, reframe and render; `tools/blender` runs the flatpak on
the NVIDIA GPU). Close the Blender window, or File → Revert, after a script changes the
.blend, or the window's next save undoes it. The render at art scale is a 4 × 3 sheet,
which an image generator restyles; `art/Armored Gauntlet Sword Sprite Sheet.png` is that
restyle. Save the generator's download into the project: an image pasted into chat arrives
shrunk and recompressed.

```bash
tools/blender -b --python tools/blender_sword.py -- render art/sword.blend art/sword-pixel --height 250
python3 tools/slice_frames.py "art/Armored Gauntlet Sword Sprite Sheet.png" data/sprites/sword --pixel 1.25 --margin 2 --filter box --colors 48 sword:12
```

`--pixel` scales the restyled cells back to the render's size. Generated sheets are noisy
below their pixel grid: `--filter box` averages instead of picking one source pixel, and
`--colors 48` flattens the speckle onto one palette for all frames. To use the raw render instead,
slice `art/sword-pixel/sheet.png` with `--exact --margin 0`; `--exact` keys only pure magenta
and keeps the render's outlines and bluish steel.

Generators can't keep a motion sequence across a grid of first-person poses, and they draw
a depth move (pulling a weapon back toward the viewer) badly. Ask for one pose per image,
attach the first as the design reference, and describe each pose in screen positions.

Most of that idle row has no palm fire, so `*hands-idle-sequence*` loops the cast's rest
frames instead. A re-sliced PNG isn't picked up by `tools/hd reset` (loaded assets stay);
`tools/hd reload src/<file that defines it>.lisp` reloads it and rebuilds the scene.

A monster's walk is one strip of 4 frames per view, in the turnaround's view order. It
comes as one generated sheet per view (`art/imp/*walk*.png`, view number in the name), each
drawing the imp at its own size. `tools/stack_views.py` scales every sheet to one sprite
height, mirrors the views that face right frame by frame (here the back-quarter), and stacks
them; slicing it at `--pixel` = height / 96 makes the imp as tall as a turnaround cell:

```bash
python3 tools/stack_views.py "art/imp/Imp Walk Sheet.png" "art/imp/Four-frame pixel imp walk cycle (frame 1).png" "art/imp/Four-Frame Imp Walk Cycle (frame 2).png" "art/imp/Side-Profile Imp Walk Cycle (frame 3).png" "art/imp/Rear Three-Quarter Imp Walk Cycle (frame 4).png" "art/imp/Pixel-art imp rear-view walk cycle (frame 5).png" --height 768 --mirror 4
python3 tools/slice_frames.py "art/imp/Imp Walk Sheet.png" data/sprites/imp --pixel 8 --anchor bottom --filter box walk:20
```

The creature's `walk-animation` names it. The billboard picks the view as for standing,
and the frame follows the distance walked (`stride` metres per frame), so the feet keep
pace with `walk-speed`.

The attack (a claw swipe: wind-up, lunge, strike, recover) is built the same way from
`art/imp/Red Imp Four-Frame Claw Attack (frame N).png`. The front two were made by hand;
the other three came from `tools/gen_image.py` with `art/prompts/imp-attack-common.txt`
plus the view's file, referencing the turnaround, that view's walk sheet and the two
finished attack sheets. `stack_views.py` scales by the tallest frame, here the raised
claw, which stands about 1.15 times the imp's height, so the stack is taller than the
walk's to keep the standing imp at 96 px (cells come out 110 px tall):

```bash
python3 tools/stack_views.py "art/imp/Imp Attack Sheet.png" "art/imp/Red Imp Four-Frame Claw Attack (frame "{1,2,3,4,5}").png" --height 880 --mirror 4
python3 tools/slice_frames.py "art/imp/Imp Attack Sheet.png" data/sprites/imp --pixel 8 --anchor bottom --filter box attack:20
```

The flinch on a hit is 2 frames per view (jolt, then stagger), played over
`*stagger-time*` instead of the old squash: `art/imp/hurt-<view>-N.png`, generated per view
with `art/prompts/imp-hurt-common.txt`, `imp-hurt-layout.txt` and `imp-hurt-<view>.txt`
(the other views add `imp-hurt-follow.txt` and reference the finished front,
`hurt-front-3.png`). The generator draws every sheet about the same height whatever
the reference's scale, so a sheet's scale can't be taken from its walk sheet; the
buckled jolt frame is about 0.83 of standing height, hence `--height 640`:

```bash
python3 tools/stack_views.py "art/imp/Imp Hurt Sheet.png" art/imp/hurt-front-3.png art/imp/hurt-front-quarter-2.png art/imp/hurt-side-2.png art/imp/hurt-back-quarter-2.png art/imp/hurt-back-2.png --height 640 --mirror 4
python3 tools/slice_frames.py "art/imp/Imp Hurt Sheet.png" data/sprites/imp --pixel 8 --anchor bottom --filter box hurt:10
```

To look at a flinch frame, `(setf *hit-stop* 1000.0)` and `(setf (stagger imp) 0.3)` (jolt)
or `0.1` (stagger).

The acolyte's cast (wind-up, raised hand with the fireball, release, recover) has no walk
sheets to follow, so each view's reference is its standing cell cut from the turnaround
(`art/acolyte/stand-<view>.png`). The front came first, from
`art/prompts/acolyte-cast-common.txt` plus `acolyte-cast-front.txt`; the other views add
`acolyte-cast-follow.txt` and their own file, and reference the chosen front,
`cast-front-3.png`. The fire rises above the cowl in some views and not others, so
`--frame 4` scales each view by its standing recover frame instead of the tallest, and
`--pixel 8` slices that to the turnaround's 115 px (cells come out 125 px tall):

```bash
python3 tools/stack_views.py art/acolyte/cast-sheet.png art/acolyte/cast-front-3.png art/acolyte/cast-front-quarter-1.png art/acolyte/cast-side-2.png art/acolyte/cast-back-quarter-1.png art/acolyte/cast-back-1.png --height 920 --frame 4 --mirror 4
python3 tools/slice_frames.py art/acolyte/cast-sheet.png data/sprites/acolyte --pixel 8 --anchor bottom --filter box cast:20
```

Its flinch is made the same way (`acolyte-hurt-common.txt`, `-follow.txt`, `-<view>.txt`,
the other views referencing `hurt-front-2.png`), but a pain pose has no frame that is the
same in every view to scale by. So each sheet opens with a copy of the standing pose:
`--frame 1` scales by it and `--blank 1` drops it before slicing:

```bash
python3 tools/stack_views.py art/acolyte/hurt-sheet.png art/acolyte/hurt-{front,front-quarter,side,back-quarter,back}-2.png --height 920 --frame 1 --blank 1 --mirror 4
python3 tools/slice_frames.py art/acolyte/hurt-sheet.png data/sprites/acolyte --pixel 8 --anchor bottom --filter box hurt:10
```

Its death (`art/prompts/acolyte-death.txt`, front only, 2 × 4 like the imp's) burns the
acolyte away and leaves its empty robe as the corpse. Frame 1, the jolted acolyte, is
407 px tall in `death-1.png`, so `--pixel 3.54` makes it 115 px:

```bash
python3 tools/slice_frames.py art/acolyte/death-1.png data/sprites/acolyte --pixel 3.54 --anchor bottom --filter box death:8
```

A monster's death is one 8-frame strip, front view only, cut from a 2 × 4 generated sheet
whose last frame is the corpse. `--pixel` is chosen so the standing imp in frame 1 is as
tall as a turnaround cell (96 px), so the strip shares the walking sprite's scale. The
corpse's blood pool reaches below the ground line, so `--ground-like 8:7` puts frame 8 on
frame 7's ground instead of the pool's edge:

```bash
python3 tools/slice_frames.py "Imp Death Sheet.webp" data/sprites/imp --pixel 3.64 --anchor bottom --ground-like 8:7 death:8
```

Hook a strip up with `define-fx-animation` (fps, loop, height in metres) and name it in
a spell's `:projectile-animation` / `:impact-animation`.

## Level blocks

Blocks are hand-authored pieces of dungeon, one `.glb` each in `data/blocks/`, drawn
with the greybox shader in their material colours. Authoring conventions (Blender or
`tools/make_test_block.py`, which generates `test-room.glb` as a stand-in):

- Metres, +Y up, the block's origin at its centre on the floor.
- Every mesh object is drawn and its bounding box is a solid, unless its name starts
  with `deco_` (drawn, no collision). Model collision as boxes: a sloped or L-shaped
  object's bounding box is the whole box around it.
- Empties named `connector_<anything>` mark doorways, on the outer face of the wall.
  A connector faces the direction from the origin to it, snapped to N/E/S/W. Doorways
  are 3 × 3 m (`*doorway-width*`, `*doorway-height*`).
- Empties named `spawn_<monster>` (e.g. `spawn_imp`) place a monster facing the
  empty's −Z.
- A material's base colour is the piece's colour; textures aren't read yet.

`(attach-block 'test-room container "connector_south" :at point :facing :south)` places a
block so that connector sits at `point`, opening toward `:south`, and returns the block's
connectors in world space for the next block or `seal-connector`. Blocks turn in quarter
turns only. Re-saving a `.glb` and running `tools/hd reset` picks up the new version.

Controls: click the window to capture the mouse, Esc to pause (release the mouse, open
the pause menu) and Esc again to resume. WASD, Shift to run,
Space to jump, C or Ctrl to crouch, 1 for the sword and 2 for the casting hands (or the mouse
wheel to cycle them), left click to
attack (swing, or cast the bolt), F12 for a screenshot.

To test combat without the mouse: `tools/hd '(game (player-cast *player* (quote bolt)))'`
starts a cast, and the bolt leaves from the player's view `*cast-release*` (0.2 s) later,
on the hands' release frame; `(select-weapon *player* :1)` then `(player-attack *player*)` swings the sword (the blow lands
0.23 s in; stand within 2 m of the imp, facing it); `(hurt (aref *creatures* 0) 0)` triggers a hit reaction (100 kills); to look at one death
frame, `(setf *hit-stop* 1000.0)` freezes the world and `(setf (dead imp) 0.35)` shows the
frame at that time; likewise `(setf (brain imp) :attacking (attack-time imp) 0.6)` shows an
attack frame (the blow lands 0.5 s in), and `(setf (alert imp) 6.0)` sets an imp hunting (the acolyte on the platform the same way);
`tools/hd status` shows mana and each creature's health.
`(issue (scene +main+) 'mouse-scroll :delta -1.0 :pos (vec2 0 0))` inside `(game ...)` turns
the wheel one notch down (next weapon).
