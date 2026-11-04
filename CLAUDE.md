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
It starts on the main menu with the world frozen, the test level behind it. Start game
starts a run of generated levels (`start-game`; see "A run" below); Debug level plays the greybox test level, where the
creatures in development live (`start-debug-level`). `HEXMAW_SKIP_MENU=1 ./run.sh` starts
straight in play on the test level, or run `tools/hd '(game (start-game))'` after launching.
The process exits when the window closes.

Every Lisp session on this project goes through `boot.lisp`:
`sbcl --dynamic-space-size 4096 --no-userinit --load boot.lisp`. Trial needs at
least 2 GB of heap. Dependencies come from the project-local Quicklisp in `.ql/`
(Shirakumo dist, not checked in), and ASDF is limited to this folder because other
projects under `~/common-lisp/` ship conflicting copies of Trial's dependencies.

A git worktree (`.claude/worktrees/<name>`) has no `.ql/` of its own: symlink the main
checkout's, `ln -s "$(git rev-parse --git-common-dir)/../.ql" .ql`, and leave the link there
(`/.ql` in .gitignore covers it; don't delete it when done). Port 7171 is usually the
main checkout's game, and `tools/hd` and the reload hook talk to it by default, so editing
`src/` in a worktree would reload the main checkout's copy of that file into that game. Give
the worktree its own port in `.eval-port` (gitignored): `echo 7191 > .eval-port`, a free one
(`ss -ltnp` shows the taken ones). `run.sh`, `tools/hd` and so the reload hook all read it,
and `HEXMAW_EVAL_PORT` still overrides it.
`tools/hd '(namestring (root))'` says which checkout a game runs from.
When you start the game from a worktree, put this conversation's name in its window title
once it is up, so the user can tell the windows apart:
`tools/hd '(game (setf (title *context*) "hexmaw — <conversation name>"))'`.

## Standalone build

```bash
./build.sh
```

Builds the game into `dist/` (gitignored), about 200 MB: `hexmaw`, the executable,
the native libraries it loads (GLFW, evdev, and for sound libmixed, libvorbis and PipeWire's spa; PulseAudio and ALSA come from the system), and `pool/` with the assets: `pool/hexmaw/`
is `data/` without the blueprints, beside Trial's own pools and the font cache. Copy `dist/`
anywhere and run `dist/hexmaw`; it needs no SBCL, Quicklisp or source tree. It takes
about 2.5 minutes and needs `patchelf` (`apt install patchelf`), which Deploy uses on the
libraries it ships. It builds every block from its blueprint first, so the shipped `.glb`
files are current.

`asdf:make` does the dumping: `hexmaw.asd` sends it to Deploy's `deploy-op`, with
`dist-main` (`src/dist.lisp`) as the entry point. The binary starts on the main menu with no
eval server; `HEXMAW_EVAL_PORT=7272 dist/hexmaw` starts one, so `tools/hd` (given the
same `HEXMAW_EVAL_PORT`) can drive a build. `HEXMAW_FULLSCREEN=1` works as with `run.sh`.
Trial's log, `trial.log`, and F12 screenshots land beside the executable; an error that
escapes shows a message box. Saves go to `$XDG_DATA_HOME/hexmaw/saves/` as in
development; the binary works that folder out when it starts (`dist.lisp`'s boot hook),
since `*save-directory*` was set on the build machine. The 4 GB heap is a limit kept from
the build, not memory used.

A file the game reads at run time goes through `(data-path "sprites/...")`, a path under
`data/`: in the binary it resolves to `pool/hexmaw/`. `root` is the project only in
development (the executable's folder in a build), and ASDF is gone from the binary. In the
binary blocks are never rebuilt (`hexmaw.blueprint:*build-blocks*` is NIL).

The binary is a release version: the build hook sets `*debug-version*` (dev.lisp, T in
development) to NIL, which hides the main menu's Debug level and Settings' Debug minimap.

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
angles, a bolt in flight, the corridor, the imp under a torch, the shrine) to
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
- Changing a `define-gl-struct` that a uniform buffer uses (`lamp-block` and its parts)
  can't be reloaded live: the reload errors and the scene breaks. Restart `./run.sh`.
  Trial only declares the last nested struct type a block uses in the shader, so keep
  `lamp-block` to one array of structs (`lights`) and the rest plain arrays; and
  `slot-offset` on a struct only takes single-value fields, so array offsets come from
  its class (`put-rooms` in lights.lisp).

## Per-frame code

Tick handlers and render methods run 100 times a second. Avoid allocating in them:
no `vec`/`v+`/`list` per frame. Mutate existing vectors with `(setf (vx v) ...)`,
`nv+`, or reuse preallocated ones. SBCL's GC pauses show up as hitches.

Every GL call costs on the CPU: cl-opengl saves and restores the float modes around each
one, and a uniform set by name is a string-hash lookup. An entity is about 20 calls a
frame whatever its size, so the level's block boxes aren't entities (they're batched,
see "Level blocks"), and a uniform that is the same for every entity of a program goes
under `(when (first-this-frame-p program) ...)` in its render method, set by the first
entity drawn with it each frame (greybox.lisp; `main`'s render counts `*render-frame*`).

Measuring: vsync is on, so the frame rate stops at the monitor's (120 Hz here, 8.3 ms).
For the real cost, turn it off for the measurement, `(game (setf (vsync *context*) :off))`
(back with `:on`), and time the GPU with a GL timer query (`gl:begin-query :time-elapsed`
inside one `(game ...)`, `gl:end-query` in a later one, divided by the frames between).
`*show-fps*` shows the frame counter. `sb-sprof` (`(require :sb-sprof)`) profiles the
`render-loop` thread; in `:cpu` mode it only sees CPU time, so time spent waiting on the
driver (a foreign `ioctl`, the swap) shows only in `:time` mode. Frozen world (hit-stop),
12 spots × 2 views, vsync off: seed 38 (no caves, 319 boxes) 3.3 ms a frame, 2.6 of them
GPU; seed 11 (caves, 586 boxes, 38 lava pools) 3.6 ms, 2.9 GPU. Before batching they were
11.9 and 20.0 ms.

## Layout and conventions

- `src/dev.lisp`: eval server, reload, runtime-error guard, screenshots. Dev only.
- `src/greybox.lisp`: level geometry (`greybox` entity, fog, `add-box`, `*solids*`), its
  textures and surfaces (see "Level textures" below), and `lit-entity`, the shader mixin
  whose `light_at` lights the level and billboards from the `lamp-block` uniform buffer.
- `src/lights.lisp`: point lights (`lamp`s in `*lamps*`, which `build-level` empties).
  `add-torch x y z` places a `torch` whose flame stands on y, `*torch-stand-off*` out from
  the nearest square wall within `*torch-wall-reach*` (`wall-near`; a wedge's diagonal
  doesn't count, so keep torches off diagonal rock), with a flickering lamp in the
  flame. The torch is one sprite, torch and flame together, turned about +Y to face the
  camera like a billboard but fullbright like an effect. The stand-off is more than half
  its width, so it never sinks into the wall. `attach-glow` gives an entity a
  lamp that follows it and goes out when it leaves the scene (the bolt and its burst).
  Each frame `gather-lights` (from `main`'s render) drops the lamps that could only light
  fogged-out surfaces (further than `*lamp-fog-end*` plus their radius) and those whose
  light lies wholly outside the view (`sphere-in-view-p`, exact, so nothing on screen
  changes), sorts the rest nearest first, and writes up to `*max-lights*` of them (128, the
  size of `lamp-block`'s array in greybox.lisp) into the `lamp-block` uniform buffer that
  every lit shader reads. A lamp whose room doesn't fit in the rooms sent (`*max-rooms*`) is
  left out, since a lamp with no room lights everything. It writes
  the buffer's memory directly: setting a gl-struct field through `slot-value` allocates.
  Light is ambient (`*ambient-color*`) plus each lamp, down to half at `*light-falloff*`
  metres and fading smoothly to nothing at its radius; the shader skips lamps out of reach.
  Fog (`fog_lit`, in `lit-entity`) treats the two apart: the ambient-lit part of a surface
  fades into `*fog-color*` from `*fog-start*` to `*fog-end*` (3 to 12 m), what lamps add only
  from `*lamp-fog-start*` to `*lamp-fog-end*` (6 to 36 m), so a lit room shows far off down
  a dark corridor. The cost is the lamps sent, since every lit pixel loops over them: on a
  30-room generated level (seed 12345), GPU time per frame is about 3.7 ms with
  `*lamp-fog-end*` at 12, 6.1 at 24 and 7.4 at 36.
  Walls take the angle to the light; sprites ignore it, so the side of the imp nearer a
  torch is brighter. A world grid (`*wall-light-snap*`, `*sprite-light-snap*`) and
  brightness bands (`*wall-light-bands*`, `*sprite-light-bands*`) give a blocky retro look
  instead; 0, the default, turns them off. Torches stop flickering while the world is
  frozen. Rooms keep light from going through walls (`src/rooms.lisp`, below), but there
  are no shadows within a room. Effects and the HUD stay unlit.
- `src/automap.lisp`: the automap's model. Every box the level draws gets a `map-piece` twin
  (`add-map-piece`, from `add-box`, `enter-piece` and `add-liquid`) sharing its vertex array
  and transform, drawn by a map shader: unlit, each storey cut open `*map-cut-height*` (2 m)
  above its floor (`floor((y + 0.49) / 5)` decides a point's storey, so a wall's top under the
  slab above is its own storey's), the storeys above the shown one (`*map-focus-storey*`)
  left out and those below darkened by `*map-depth-fade*` per storey. Cull face is off: the
  inside of a cut box shows its back faces, drawn in `*map-cut-color*` as the cut face, and
  at the depth of the cut plane they're seen through (`gl_FragDepth`, from `*map-eye*` and
  the piece's world box, `piece-low`/`piece-high`, and a wedge's cut corner, `piece-cut`), so
  the floor a pillar stands on can't flicker against it. Map twins are never batched
  (`with-block-batches`): one per piece, drawn only under the map camera. The storey just above the shown one is a ghost: its outside only, in
  `*map-ghost-color*` on 1 pixel in `*map-ghost-stipple*` (no blending, so no draw order).
  Colours come from `*map-colors*` by surface. `place-block` makes a `map-block` (bounds,
  `revealed`) in `*map-blocks*` (placement order; `build-level` empties it) and binds
  `*map-block*` so its pieces and plugs belong to it; pieces of no block (the test level's
  boxes, the gallery's ground) always show. `*map-debug*` is the Settings checkbox;
  `map-debug-p` is it in a debug version only.
- `src/map-view.lisp`: the automap screen. M in play sets `*game-state*` `:map` (frozen) and
  the map view's tick swaps the scene's camera for a `map-camera` orbiting `map-target`
  (`map-yaw`, player convention, so the player's facing is up the screen when it opens;
  `map-pitch`; `map-distance`); Esc or M closes. Trial draws what the active camera's
  `in-view-p` accepts, so under the map camera only `map-drawn-p` things draw (map pieces of
  revealed blocks, `map-overlay`s), and the player's camera never draws map pieces or
  overlays. Overlays are pushed onto the near plane in their vertex shader, so they're on
  top whatever the draw order: the player's arrow, the hint line and, with the debug
  minimap, creature markers (`map-markers`, one entity drawing a cube per creature) and
  block names (`map-label`, projected through the camera's `view-projection` each tick).
  The tick also reveals the block the player stands in (`reveal-map-at`). `reset-run`
  clears the reveals; a save keeps them (`:map`, block indices). Controls: left drag turns
  and tilts, right drag pans, wheel zooms; WASD pan, Q/E turn, R/F tilt, +/- zoom, Page
  Up/Down or Shift+wheel change the storey (`step-map-storey`, within the explored range,
  `map-storey-range`), Space re-centres on the player. The hint line says when there's more
  above or below. To drive it:
  `(game (open-map))`, then `(map-camera *map-view*)`'s accessors and `*map-focus-storey*`.
- `src/rooms.lisp`: rooms and portals, so light stays in its room. A room (`add-room`) is a
  box of air, its walls, floor and ceiling outside it; a portal (`add-portal`) is a box
  joining two rooms, a doorway through a wall's thickness or a flat opening. `build-level`
  empties `*rooms*` and `*portals*` and ends with `link-rooms`, which finds the room on each
  side of every portal along its thinnest axis and drops the portals that don't lead into
  a room on both sides (walled-off doorways). A placed block is one room, its bounds walls
  and all, and each connector is a flat portal its doorway's size; sealing one
  (`seal-connector`) takes its portal away. A lamp lights the rooms it stands in
  (one room, or both rooms of a portal it's in; a lamp with a source is found again each
  frame) and the rooms beyond up to 4 portals within its radius, but only along lines that
  pass through the opening: within the portal's thickness, the line must stay inside it.
  `gather-lights` sends the rooms and portals the lit lamps need (up to `*max-rooms*` and
  `*max-portals*`, 32 each), and each lamp gets a room mask and portal list. The shader
  finds a wall's room just off it on the side it's seen from, and a sprite's at the middle
  of its body (`light_probe`), so the whole sprite is lit alike. A surface in no room is lit
  only by lamps in no room, and those light everything, so a level without rooms is lit as
  before. Rooms shouldn't overlap. To check for leaks, put a strong lamp in one room
  (`(add-lamp (vec x y z) (vec 4 0 0) 6.0)`) and look from the next; turning rooms off
  (`(setf (fill-pointer *rooms*) 0)` and `(setf (located lamp) nil)` on every lamp) shows
  what it would leak. `tools/hd reset` restores them.
- `src/nav.lisp`: the nav grid, where creatures can stand and how they get around; see
  "Creature movement" below.
- `src/sprite.lisp`: Doom-style `billboard` sprites (view by angle, mirroring, tint, lit), and
  frame animations from `tools/slice_frames.py` strips (`define-fx-animation`).
  Assets live in `data/` (Trial pool `hexmaw`, defined at the top of greybox.lisp,
  the first file with an asset).
- `src/creature.lisp`: `creature` (health, hit reaction: flash, flinch, knockback, hit-stop;
  death, and revival after `*revive-time*`, on the test level only (`*level*`, defined here); wandering, hunting and attacking the player, and the walk and attack
  animations), `*creatures*` for hit tests, and bodies (collision between actors). A creature's
  `death-animation` plays once on death, front view from every angle, and its last frame
  stays as the corpse until revival; without one it collapses into the floor. Every hit
  flashes, knocks back and hit-stops, but only a pain roll makes it flinch and break off
  its walk or attack (`pain-roll-p`, from `*roll-random*`): its `pain-chance` (percent:
  knight 8, ogre 9, riftwalker 11, skeleton 20, acolyte and harpy 25, imp and wraith 30, necromancer 35) plus the weapon's
  bonus (`*sword-pain-bonus*` 0; a spell's `:pain-bonus`, the bolt's 10), at most
  `*max-pain-chance*` (75), so nothing can be held in its flinch. Knockback carries a creature
  whatever the pain roll: while its `momentum` is over `*shove-hold-speed*` (1.5 m/s; `shoved-p`,
  not on ice) it neither walks nor lunges, so a hunter doesn't walk straight back through a push. A killing blow and
  `always-pained-p` (a harpy mid-dive) always interrupt. The `acolyte`
  is the ranged one (`attack-spell`), with a cast, flinch and death but no walk: it glides
  in the standing pose, its robe hiding its feet. Its death burns, so it has a `death-glow`:
  a lamp that rises and fades with the fire on `death-glow-times`, then leaves `*lamps*`.
  The `knight` is slow and heavy (`knockback-scale`), behind a tower shield: `shield-views`
  is the last billboard view (0 front .. 4 back) the shield covers, so what the player sees
  decides it. A spell whose flight comes from a covered view (`shielded-p`, the same
  `billboard-view` that picks the sprite) is deflected in the projectile's tick
  (`deflects-p`, `deflect` in spells.lisp) before any effect applies: mirrored off the
  shield's face and sent back as the knight's own (`shield-reflects`; NIL just stops it),
  with `block-hit` (a faint flash, the `block-animation` pose for `*block-time*`, a brace).
  The block strip has only the covered views. The sword isn't stopped, but a shield bash
  from a covered view glances off (`bash-hit`): no harm to the knight, its block pose, and
  the player thrown back `*bash-recoil*` with the shield knocked down. A creature's
  `guard-break` (knight 0.8 s, ogre 1.2) is how long its blow knocks a blocking player's
  shield aside (`break-guard`, player.lisp). `turn-speed`
  (radians per second, NIL for instant) is what lets the player get behind it: `turn-to`
  limits every facing change, in walks, idle hunting and an attack's wind-up.
  **Impacts**: an actor stopped faster than `*impact-speed*` (8 m/s) by a wall, a ceiling or
  another body is hurt, whatever sent it (a tornado's throw, the ogre's quake or slam, a gust), and
  so is the body it hit, at the same speed, with no shove. Onto a floor that holds for one
  `flung` by a tornado; the player's own falls hurt only past `*fall-impact-speed*` (13 m/s, a
  4 m drop; `:by :fall`), and not into deep water. Damage is `*impact-per-speed*` (2.5) a m/s
  over, at least 1, at most `*impact-max*` (20), and no shield helps. `hit-surface` hurts one
  actor (`hurt`, the blood thrown onto what it hit; `hurt-player ... :shove NIL` plus `hit-stop`,
  `:by` `:tornado` while thrown or held, else `:impact`, or the creature thrown into them);
  `hit-across` takes what a move lost and `strike-body` finds the body it ran into. Creatures
  check in `slide` (knockback, not their own walk on ice) and `fly-thrown`, the player in
  `note-impacts` after each move (walls not while grounded on ice). Running (7 m/s) stays under
  it. A whole tornado hold costs a creature about 12 in the wind, up to 20 from a wall and 5 to 10
  landing.
- `src/flyer.lisp`: `flyer`, a creature that keeps to the air, and the `harpy`. See "Flyers"
  under "Creature movement" below. Creature code reaches it through generics with a
  walker's default: `keep-height` (settle, or hover, dive and fall), `move-lift`,
  `ranged-p` (hunt from range) and `attack-step` (the blow, or the dive).
- `src/necromancer.lisp`: the `necromancer` and the skeletons it raises (`skeleton-warrior`:
  Trial already has a `skeleton`, for skeletal animation). See "The necromancer" under
  "Creature movement" below. A creature with several attacks is an `ability-user`, listed before
  `creature` or a subclass of it in its superclasses, with `ability` objects (frame
  times, hit frame, animation, spell, pause, cooldown); its attack readers
  (`attack-frame-times`, `attack-animation` and the rest) are methods answering for the
  current one, so `attack` runs any of them, and `release-attack` (what lands on the hit
  frame), `face-attack-target` (what it turns to through the wind-up) and `hunt-from-range`
  are generics with the caster's behaviour as the default.
- `src/ogre.lisp`: the `ogre`, the big one (2.7 m, `body-radius` 1.0), which leaps and pushes
  the player around. See "The ogre" under "Creature movement" below.
- `src/imp.lisp`: the `imp`, a `leaper` that pounces, springs back after its claw, breaks and
  shrieks when its courage fails, steals, and comes in packs. See "The imp" under "Creature
  movement" below.
- `src/blocks.lisp`: level blocks from glTF (`find-block`, `place-block`, `attach-block`,
  `seal-connector`); see "Level blocks" below.
- `src/blueprint.lisp`: builds blocks from text blueprints (`data/blueprints/*.txt`), in its own
  system `hexmaw-blueprints` (no Trial) so `tools/blueprint` starts in a second; see
  "Blueprints" below.
- `src/kit.lisp`: the kit (`kit-blocks`, every `.glb` in `data/blocks/`) and the gallery level
  that lays it out (`build-kit-gallery`, `kit-goto`).
- `src/generate.lisp`: the level generator (`generate-level`); see "Generated levels" below.
- `src/run.lisp`: a run's levels and what carries between them; see "A run" below.
- `src/save.lisp`: saving and loading generated runs, one file per slot in `*save-directory*`
  (`$XDG_DATA_HOME/hexmaw/saves/`, usually `~/.local/share/hexmaw/saves/`:
  `slot-1.sav` .. `slot-3.sav`, `quick.sav`). A save doesn't store the level: it keeps the
  seed and the generator's settings (`*saved-generator-settings*`), and the level's cells
  (`level-layout`) to check that the rebuild is the same level; one built from changed blocks
  isn't, and its save then starts fresh, with a warning. What it stores is everything that
  changes in play, so a load is the moment of the save, nothing in flight lost: the player,
  every creature by its index in `*creatures*` (raised skeletons recreated), every effect in
  the scene (projectiles, circles, impacts, with their glows), the blood pool's arrays,
  which pickups are taken and what imps dropped (`:drops`, `dropped-pickups`: pickups past
  `*built-pickups*`, which the seed doesn't place), `*hit-stop*` and the random states. Damage and knockback roll from their own state
  (`*roll-random*`, spells.lisp), since blood and wandering draw from `random` a number of
  times a frame that varies with the frame rate: so a reload rolls the same as before it.
  An object saves the slots `saved-slots` names (an `append` generic; a name with no slot
  is an accessor, as `location` is), so **a new slot that changes in play needs adding
  there**. Values go through `encode-value`: vecs as `(:vec ...)`, references to the player,
  creatures, spells, abilities and animations as tagged lists, anything else an error that
  stops the save. `load-game` starts a run as `start-level` does with `*pending-load*` set;
  `build-level` builds the saved seed and `setup-scene` ends with `restore-run`, which leaves
  the game paused. Reloading save.lisp resets `*save-directory*`; to test without touching
  real saves, `(setf *save-directory* #p"/some/dir/")` after each reload.
- `src/liquids.lisp`: liquids, lava and water. A liquid is a box of volume in `*liquids*`
  (`build-level` empties it), never a solid. Lava fills a sunken pit
  whose floor is an ordinary solid `*lava-depth*` (0.4 m, under a step) below the floor
  around it, its surface `*lava-surface*` (0.1 m) below, so walking in and out is a step
  down and up and the feet sink. Everything else asks `liquid-at x y z`. `*liquid-kinds*`
  says what a kind does: `:damage` per second, paid on stepping in and then every
  `*lava-tick*` (`burn-due`) by the player (`hurt-player ... :shove NIL`: the pain flash,
  no shove or hit-stop) and by creatures (`burn`: a flash, no flinch or blood; one standing
  idle in it walks to the nearest dry cell, `escape-liquid`, which looks up to 6 m off for
  one mid-stream), `:speed` on the player's walk (kept
  through a jump from it until it lands outside, `wading`), `:jump` on the speed of a jump
  from it (lava's 0.7 halves its height), and `:glow`, the lamps `add-liquid` hangs
  `*glow-height*` over it, one per `:glow-spacing` of the pool's length. One nearer
  than that to a lamp already hung over the same kind is left out and its colour added to
  that lamp's: an irregular pool is many boxes, every lamp sent costs every lit pixel, and
  lamps that close lit like one brighter one anyway. The nav grid flags each cell under lava (`nav-hazard`), and
  `*nav-hazards*` says what the nav questions make of it: `:avoid`, the default, keeps out
  (so wandering, retreat and `show-nav` stay dry); `check-reachable` wades, since a stream
  is lava wall to wall and the only way past it is through; `:wade` lets a path through at `*nav-wade-cost*` (3) times the
  cost per step but no straight walk across, so it takes the short way over; `:ignore`
  is any floor. A creature thinks under its `nav-hazards`: `:avoid` for walkers, whose
  chase falls back to `:wade` only when no dry way reaches the player within
  `*chase-max-walk*` (`chase-path`), and `:ignore` for flyers, which hover over it.
  Projectiles burst on its surface; blood drops and
  gibs that fall in are gone. The surface is a `liquid-surface` quad, fullbright and fogged
  as lamp light, its texture (`data/textures/lava-flow.png`, from
  `art/prompts/texture-lava.txt` like the other textures) swirled by crossed waves. On
  the test level, `add-lava` digs a pit in the hall's south-west (x −9 to −6, z 3 to 7),
  its floor slab left with a hole there; the hall's room reaches down to the slab's
  underside so the glow lights the pit's rim.

  Water is deep only: a pit can sink no further than the 0.5 m slab, so water fills the lower
  storey of a two-storey block (a pool, a canal) up to `*water-surface*` (0.3 m, blueprint.lisp)
  under the floor above, or a flooded passage to its roof. `:swim` in its kind marks it;
  `swim-liquid-at` asks for it. Its surface is a `water-surface` (not lava's fullbright
  `liquid-surface`; both are `liquid-sheet`s): lit through `light_at` like a floor, from below
  as a ceiling, see-through (`*water-alpha*`), no depth written and both faces drawn. So it
  must be drawn after everything it covers: its `late-rank` is 0, and the game's pass
  (`game-pass`, main.lisp) moves what has one to the end of each frame, by rank, since Trial
  draws in hash-table order. The underwater tint (hud.lisp) is rank 1, after it. A water box whose top meets a ceiling gets no surface. With the camera
  in water (`*eye-underwater*`, set by `place-camera`) the fog and clear colour are the
  water's (`*underwater-fog-color*` and the rest; `fog-color`, greybox.lisp), and the whole
  view, the hands too, is multiplied by `*underwater-tint*` (a blue; `underwater-tint`,
  hud.lisp, a quad like the pain flash drawn with `:dst-color :zero` blending). The texture is
  `data/textures/water.png` (`art/prompts/texture-water.txt`, made like the other textures:
  `tools/make_texture.py art/textures/water-1.png data/textures/water --metres 4`).
  The nav grid makes deep water's surface a floor (`water-surfaces`), so a walker shoved in
  settles onto it like any floor. Afloat (`afloat-p`; never a flyer, `floats-p`) it is drawn
  sunk by `*float-sink*` of its height (in `apply-transforms`, so the surface covers the
  rest), doesn't think but flounders (`flounder`, `escape-liquid`) toward the nearest dry
  floor at `*flounder-speed*`, losing `*creature-drown-damage*` a second (`burn`), and walks
  out up the step onto the ledge. A projectile bursts on entering a liquid from outside: one
  cast under water (`submerged`) flies on. The necromancer draws no grave circle under a
  swimmer. On the test level the `pool` hangs off the shrine's west doorway.
- `src/footing.lisp`: moving on a slippery footing, Hexen's ice. A footing (`*footings*`,
  greybox.lisp, beside `*surfaces*`) belongs to a surface: whatever is drawn with surface
  `:ice` (a blueprint's `ice` material, `add-box :surface :ice`) is slippery, a box, floor slab
  or wedge alike. The solid carries it as an 8th value (`make-solid`'s FOOTING, after a cut of
  0 for a box; `solid-footing`), and `floor-footing x y z radius` asks what the floor at Y under
  a point is (the point decides, as in Hexen, unless the body stands on a ledge's edge with
  nothing under its centre). The nav grid keeps each cell's footing (`nav-footing-at`, the
  floor within `*footing-reach*` under a point), and `show-nav` tints ice cells blue. On ice
  `footing-drag` takes `:friction` (0.97) of the speed away per second, as an exponential, and
  `footing-push` pushes toward `:top-speed` (1.7) times the speed it would walk at: Hexen's
  `FRICTION_LOW` and halved thrust. So the player takes about 1 s to reach a run, slides about as
  many metres as m/s when they let go, and tops out near 12 m/s; in the air, holding a direction
  keeps their speed (air control steers but never brakes below it, on any floor; with no key held
  it does brake, at 12 m/s², unless a vortex threw them), so a run-up on ice jumps further. Creatures skid too: their `momentum` (a blow's knockback, and on ice their
  walk) slides them in `slide`, with the footing's drag on ice and `*knockback-friction*`
  elsewhere, and on ice `walk-path` hands over to `skid-path`, which only turns and pushes: a
  point is reached within `*skid-arrive*` or once passed (`*skid-pass*`), and it is stuck when it
  stays under a quarter of its walk speed. A melee creature slides on through its wind-up, so
  its blow can miss. Stepping onto ice mid-walk carries the walk's speed over
  (`update-footing`); hovering flyers have no footing. `tools/hd status` shows the player's
  footing and speed and each creature's footing. Nothing in pathing knows about ice yet.
- `src/fx.lisp`: animated camera-facing effect sprites (`fx-sprite`, `spawn-fx`); fullbright,
  no fog. Projectiles are effect sprites.
- `src/gore.lisp`: blood. `hurt` takes `:from`, the point the blow came from (the sword
  passes the player's feet, a projectile its flight; NIL means the player), and `bleed`
  sprays drops from the wound away from it, `*blood-back-spray*` of them back toward the
  attacker, `*blood-per-damage*` per point within `*blood-drops*`. A death adds `bleed-out`,
  a burst every way (`death-blood`, 0 for the acolyte, which burns; `bleeds` NIL for no
  blood at all). Drops fly under `*blood-gravity*` and stick where they cross a solid's face
  as splats, flat on the floor or a wall (a ceiling only stops their rise; a drop that goes
  in through a wedge's diagonal is gone, since a splat lies on a square face only, and a gib
  bounces off one, `diagonal-entry-p`, `reflect-off-diagonal`). `lay-splat`
  picks the splat: a drop faster than `*streak-speed*` across the floor smears into a streak
  pointing the way it went (snapped to a quarter turn), a bigger drop on a wall may run down
  it (`*drip-chance*`), and the rest are one of three round variants, turned and mirrored at
  random. A drop landing on a round splat on the same face (closer than
  `*splat-merge-reach*` of their radii together) pours into it instead: the splat keeps its
  blood as an area, grows by `*merge-spread*` of the drop's and takes the size that area
  fills, up to four puddle sizes past any one drop's splat. Sprays scatter too widely to
  pool, so the pools come from dripping: a hit leaves the wound dripping, nearly straight
  down, for `*bleed-per-damage*` seconds a point (a puddle under a creature that stands, a
  trail behind one that walks), and a corpse bleeds into a pool under it for
  `*corpse-bleed-time*` (`drip-blood`, from the creature's tick). A level keeps
  `*max-splats*` splats; past that the oldest dissolve, art pixel by art pixel, over
  `*splat-dissolve-time*` (`*splat-lifetime*` dissolves them by age as well; NIL, the
  default, keeps them). Every drop and splat is a slot in one `blood-pool` (`*blood-pool*`,
  entered by `setup-scene`): plain arrays (`*max-blood*` slots), written each frame into one
  stream-draw vertex buffer and drawn in one call. Drops face the camera plane, offset in
  view space by the shader; splats lie on their face, lit and shaded like it. `reset-run`
  clears it (`clear-blood`). `(spray-blood (vec x y z) dx dz count)` throws drops by hand.
  The frames are `data/sprites/blood/blood`, drawn by `tools/draw_blood.py` (drops, round
  splats and puddles, streaks, drips; its docstring has the layout), at the monsters' 64 px
  per metre. Its `ROUND_RADII` must match `*splat-radii*`.
  Gibs: a killing blow that leaves health below 0 by `*gib-overkill*` of the most (0.3; a
  creature's own `gib-overkill` overrides it: the knight's 0.15, since no one blow overkills
  60 by 18, the skeleton's 0.1) tears a creature with `gibs` apart instead (`gib-p`,
  `tear-apart`, `burst-gibs`): it vanishes (`gibbed`, until revival; its wound stops
  dripping) and its pieces fly out with a burst of blood, tumbling a quarter turn at a time
  and trailing drops, bounce off what they hit (`*gib-bounce*`, leaving a splat), and come
  to rest on the floor once slower than `*gib-rest-speed*`, standing upright and turned to
  face the camera like a billboard. They are slots in the same pool; a level keeps
  `*max-gibs*` at rest and dissolves the oldest. A creature's `gibs` is a list of groups,
  each a set's name in the blood strip and a piece number per gib, `(:head n)` for the one
  that flies from the top of the body. Sets are shared: `:flesh` (arm, leg, ribs, spine,
  organ, three chunks; no skin, so it suits any flesh-and-bone creature) serves the imp,
  knight, harpy and necromancer, the imp adding its own head and tail from `:imp`; the
  skeleton's `:bones` are its own. `gib-scale` draws a creature's pieces bigger or smaller
  (the knight 1.3), and the gibs of a creature that doesn't `bleed` leave no blood. The
  acolyte has none: it burns. A set starts as a generated sheet of pieces, each
  lying on the ground (`art/gibs/flesh-gibs-2.png`, from `art/prompts/flesh-gibs.txt` with the
  imp's turnaround and death sheet as references), sliced by `tools/slice_frames.py` into
  `art/gibs/strips/<set>`, which `tools/draw_blood.py --gibs <set>=<strip>` appends to the
  blood strip with the turned frames; cells grow to fit the biggest piece. Every run
  rebuilds the strip, so pass every set. The generator draws the pieces bigger than asked,
  so `--pixel` is set by eye to the imp's scale (the head about 30 px across); the strip
  holds 256 frames at most, 4 a piece:

  ```bash
  python3 tools/slice_frames.py art/gibs/flesh-gibs-2.png art/gibs/strips --pixel 9 --filter box --colors 32 flesh:8
  tools/draw_blood.py data/sprites/blood/blood --gibs imp=art/gibs/strips/imp --gibs flesh=art/gibs/strips/flesh --gibs bones=art/gibs/strips/bones
  ```
- `src/spells.lisp`: the composable spell model (`define-spell`, effects, `spell-cost`),
  projectile delivery, the player's `bolt` and `heal`, the acolyte's `cinder` and the necromancer's
  `grave-skull` and `grave-spikes`. An effect has a kind, a magnitude range, a duration, an area, a
  target type (`:self`, the caster; `:target`, what the delivery hits) and, for damage, an
  `element`. `*effect-kinds*` says what each kind the spellforge offers is (its base cost, how its
  duration counts: `:instant`, `:over-time` (magnitude per second) or `:status`, who it may strike,
  and the forge's caps); `effect-cost` is base (by element for damage, `*element-costs*`) times the
  average magnitude, times the duration's factor, times 1 + area, times `*touch-cost-scale*` for a
  touch spell. The bolt is 14 (fire 7-9 and knockback 3-4, "Fire Bolt" by its `:title`; `spell-title`),
  heal 17 (14-20), and the creatures' spells cost what they did. The player's starting spells must be
  ones the forge makes, ranges, cost, flight and all (`forgeable-p` and `check-starting-spells`,
  forge.lisp, which warns as it loads: a forged range is `*magnitude-spread*` of its top up to it, and
  damage always has an element). An effect with an area
  bursts where its spell strikes (`burst-spell`, over `burst-victims` in magic.lisp: every body
  within it with a clear line, but the caster and those it spares), the impact drawn that much
  bigger (`play-impact`, `*burst-size*`); a strike without a projectile (a touch, an enchanted
  blow) goes through `strike-with-spell` and a `strike` source. A spell the player forged isn't in
  `*spells*`: `spell-spec` and `spec-spell` turn one into plain data and back (a save keeps it so),
  and its look is its element's or first effect's (`*spell-looks*`: the bolt's frames recoloured
  into `data/sprites/spells/` by `tools/recolor_hue.py ... --from 30 --reach 60 --hue H --spread
  0.5`; frost 200, shock 58 with `--spread 0.25`, drain 345, heal 110, arcane 285), each preloaded
  by `preload-spells`. A new effect kind is a method on `apply-effect`, for a
  `creature` target and (in player.lisp or magic.lisp, loaded later) a `player` one; where the effect came
  from and which way it pushes are `effect-origin` and `effect-direction` of its source (the
  projectile, or the circle), and `effect-unblockable-p` whether the player's shield counts
  (the circle's comes up from the floor). A projectile hits any live creature or the player except its
  `caster` and those the caster `spares-p` (a necromancer, its undead). A spell's `homing`
  (radians a second) turns a creature's projectile after the player's chest (`steer`), so a
  late sidestep still dodges a slow one; a shield that turns it aside ends it. `lifetime`
  overrides `*projectile-lifetime*`.
  The `:circle` delivery (`grave-spikes`, `spell-circle`) is drawn round a point on the floor:
  its sign (`circle-animation`, lying flat, drawn in over `*circle-draw-in*` of the wind-up,
  then pulsing), an `aurora` round its rim, and a lamp that brightens to
  `*circle-light-color*`. The aurora is a curtain like the northern lights, rising to
  `*aurora-height*`: a ring of `*aurora-segments*` quads that its vertex shader sways into
  drifting folds above the foot (the foot stays on the rim), and its fragment shader fills
  with soft vertical streaks of many heights (smooth noise that repeats round the ring, so
  it meets itself), a glowing band along the foot, the colour wandering through the
  necromancer's greens (emerald, acid, sea-green) round the ring and deepening toward the
  top. It is added
  over what is behind it (`gl:blend-func :one :one`, no depth written), so it needs no
  sorting against other glows; it draws both faces. `:arc` (radians either side of
  `aurora-arc-middle`, an angle from +X toward +Z) spreads the same ring over a sector only,
  fading at its ends; pi, the default, is the whole ring. Every
  aurora shares one ring (`*aurora-vao*`), staged by `preload-spells`: a vertex array made
  mid-game is never loaded onto the GPU. After its `windup` it strikes, once, everything living with feet in
  it (the effects' `area` is the radius, within `*circle-reach-height*` of the floor) except
  its caster and the `undead`, wrenching `*harvest-blood*` drops straight up out of each
  (`harvest`), and its `strike-animation` bursts up in `*strike-rings*` from the middle out.
  Once cast it goes on alone: hitting or killing the caster doesn't stop it, and it spares
  no one's allies. `tools/draw_grave_circle.py data/sprites/grave` draws the sign; the
  skull and the bone spikes are generated sheets (`art/spells/`, from
  `art/prompts/grave-skull.txt` with the bolt sheet, and `bone-spikes.txt`):

  ```bash
  python3 tools/slice_frames.py art/spells/grave-skull-2.png data/sprites/grave --pixel 5 --filter box flight:5 burst:7
  python3 tools/slice_frames.py art/spells/bone-spikes-1.png data/sprites/grave --pixel 3.5 --filter box --colors 32 --anchor bottom spikes:8
  ```

  To look at one: `tools/hd '(game (cast-spell (find-spell (quote grave-spikes)) (v+ (feet *player*) (vec 0 0 -4)) (vec 0 0 1) (scene +main+)))'`.
- `src/vortex.lisp`: the tornado, the spell `tempest`, delivery `:vortex` (`spell-vortex`, an
  `fx-sprite` that draws nothing itself, like `spell-circle` for saves and resets). It takes
  everyone, its caster too. Each actor runs its part in its own tick (`whirl-step` from the
  creature's, `whirl-transitions`, `orbit-player` and `end-player-flight` from the player's, so
  the camera can't lag), on the slots of the `whirlable` mixin (creature.lisp, on both). **Pull:**
  within `*vortex-pull-radius*`, on its storey (`vortex-reaches-p`, as `clear-path-p` looks across
  at one height) with a clear line (looked for 10 times a second), an actor is dragged, as a
  displacement rather than a velocity since a walk would cancel that (`move-pulled`, the `pull`
  slot), up to `*vortex-pull-speed*` (5.5 m/s, so a walk loses near the middle and a run escapes).
  **Catch:** within the spell's `:area` plus half its body's radius (`catch-actor`; `note-caught`,
  and `break-flight` for an ogre's leap or a flyer's dive). **Whirl** for `*whirl-hold*`
  (`orbit-point`): round the moving centre, spinning up over `*whirl-spin-up*`, carried up to
  `*whirl-lift*` or under the ceiling (one `nav-room-around` per vortex per tick, `ceiling-above`
  being far too slow), its body no longer solid (`body-solid-p`), losing the spell's `:magnitude`
  a second through `burn` and `burn-due`, which don't hit-stop. Walls narrow an orbit
  (`note-orbit-miss`), and `*whirl-stuck-limit*` off it ends the hold. An orbit moves an actor at
  most `*whirl-step*` a tick (`orbit-step`): a move is only tested where it ends, so a jump to an
  orbit point beyond a wall would land there. A creature shows its
  flinch frame with its `facing` spinning, so its views cycle. **Throw** (`throw-actor`): along
  the orbit and a little out, at `*fling-speed*` and `*fling-lift*`, both scaled down by
  `knockback-scale`, when its hold ends or the vortex dies away; `spat-timer` keeps it from being
  pulled for `*spat-time*`. A creature flies on `flight` (`fly-thrown`), stopped by walls and bodies,
  and lands on `nav-floor-at` or where `fits-at-p` fails below, its speed going into `momentum` and
  `land-thrown` staggering it (a flyer lies downed). The player flies on `velocity` through
  `walk`, which keeps their speed while `flung` with no key held. What a thrown actor hits
  hurts it (`hit-surface`, see "Impacts" under `src/creature.lisp`): walls, bodies, the ceiling
  and, while `flung`, the floor, and the orbit dashing it against a wall (`note-orbit-miss`, once
  each time walls start keeping it off its orbit, at the orbit's speed). **Struggle:** the
  player's wish, as far as it points away from the centre, widens their orbit against
  `*whirl-draw*`; past `*whirl-escape*` they drop out at `*struggle-fling*` of a throw. The
  vortex paths on the nav grid under `*nav-hazards*` `:ignore`: a creature's after the player, the
  player's after the nearest creature it sees (`vortex-target`), keeping its heading once its
  quarry is inside. `vortex-aim-point` places the player's where their aim meets the floor, 3 to 8 m
  off. It shows as a `funnel` (a shared mesh, `*funnel-vao*`, staged by `preload-vortex`; spiral
  bands snapped to whole cells, premultiplied, no depth written, `late-rank` 0.5) with `ogre-dust`
  puffs round its foot; from inside, `whirl-streaks` (hud.lisp) rush across the view. To look at
  one: `tools/hd '(game (cast-spell (find-spell (quote tempest)) (vec 0 0.5 1) (vec 0 0 1) (scene +main+)))'`.
- `src/wraith.lisp`: the `gale-wraith`, a `flyer` and an `ability-user` (necromancer.lisp) that
  floats `*wraith-hover*` off the floor, in sword reach. Its tornado takes a `*tempest-cast-time*`
  (1.5 s) cast: `begin-tempest` lays a `gale-sign` (`sign-frame`, a lamp, a thin funnel and, round
  its rim, the necromancer's `aurora` in `*sign-aurora-colors*`, its streaks leaning and running
  round it, `*sign-aurora-spin*` and `*sign-aurora-twist*`) on the
  floor under the player, and `release-attack` raises the tornado there. The sign despawns itself once
  `casting-tempest-p` is false, so a flinch (`hurt`'s `stop-walking`), a timed bash, its death or
  being caught all end the cast at one stroke. A broken cast may be tried again after
  `*tempest-retry*`, a released one after `*tempest-cooldown*`, and only one of its tornadoes is up
  at a time. Otherwise it throws `gust`s: a `:gust` effect throws the player, toward its tornado
  if one is near, and with lift, since a shove on the floor dies at once. It has no walk.
  `casting-tempest-p` is a generic, so a boss's tornado cast keeps its sign up too.
- `src/riftwalker.lisp` (after boss.lisp, whose `free-spot` and `same-arena-side-p` it uses): the
  `riftwalker`, a masked assassin, an `ability-user` and a melee hunter (`ranged-p` is true only
  while a cast of its runs, so the cast turns after the player as a caster's does) that flanks.
  Its stab is its only damage. Its other abilities move things, chosen in `special-attack`:
  `:call` (cd 14 s) brings the live ally nearest it (within `*call-reach*`, at least
  `*call-min-distance*` from the player, no boss) to stand to the player's front quarter on the
  side away from the riftwalker (`call-spot`), a 1 s cast
  marked by a `rift-sign` on the floor (`tools/draw_rift_sign.py data/sprites/rift`) that a flinch
  breaks; `:push` (cd 12 s) with the player on top of it while it is under half health or their
  shield is up; else `:pull` (cd 8, 6 to 16 m) or `:swap` (cd 10, 5 to 14 m), 50/50 when both are
  ready. The three are projectiles at 10 m/s (`rift-pull` violet, `rift-swap` gold, `rift-push`
  cyan by their light), with effects `:teleport-to`, `:swap` and `:teleport-away`. They pass
  through every creature (`spares-p`): a rift that struck the ally it had just called stood in
  its line swapped the two. A sidestep dodges them and a raised shield facing them stops them
  (`rift-stopped-p`); a knight's shield sends one back as its own, which moves whatever it then
  strikes (the effects are methods on `apply-effect` for any target). A pull puts the target in front of the caster (`spot-around`), turned to it, and
  the stab follows; a swap trades places, the player keeping their facing, and `*pounce-delay*`
  later it blinks in right behind them (`pounce`); a push sends the target to `spot-away`, a dry
  cell `*rift-away-walk*` (10 to 25 m) of walking off and within `*rift-away-within*`
  (`nav-reachable-spot`'s `:test`), so the way back is always on foot. Every destination keeps to
  its side of the arena's walls. **Blink**: every `*blink-interval*` (4 to 8 s) of hunting it steps
  through a rift to a random spot `*blink-range*` (3 to 6 m) off in sight of the player
  (`blink-spot`), and, past `*blink-cooldown*`, `*blink-dodge-chance*` (35%) after a hit it lives
  through (`react-to-hit`, a generic `hurt` asks) and `*blink-evade-chance*` (50%) when the
  player's projectile is about to reach it (`evade-projectile`, asked once per projectile from its
  tick, `*evade-look-ahead*` ahead, spells.lisp). Moving goes through `teleport-actor` (the
  player's is `teleport-player`, player.lisp: stopped, out of a vortex, the eye snapped, the view
  flashing `*rift-flash-color*`) and `rift-move`, a `rift-flash` at both ends. Rolls use
  `*roll-random*`. As a boss it is the Rift Lord (`riftwalker-boss`, defined here), denied the
  boss's `:blink`, and an elite as `elite-riftwalker`. It spawns from level 2 of a run on (weight 1,
  then 2 on level 3). On the test level it stands by the hall's west wall. To try it:
  `(setf (alert riftwalker) 30.0)` with the player 6 to 16 m off for a pull, and `(cooldowns
  riftwalker)` to hold the others back (`(list :pull 0.0 :swap 100.0 :push 100.0 :call 100.0)`).
- `src/boss.lisp`: the boss at the end of a run, in the `arena` block the run's last level ends in. It is an
  empowered form of one of the eight monsters (`*boss-kinds*`: kind, class such as `imp-boss`
  `(boss leaper imp)`, base class, title such as "Imp Overlord", scale, traits), every kind as
  likely, with three powers (`boss-powers`): two from the start, the third when it enrages at
  `*boss-enrage-at*` (half) health (`active-powers`). `make-boss`, from a `spawn boss` in a
  blueprint, draws the kind and powers (`pick-boss-powers`, at most one passive) from
  `*block-random*`, so a seed always gives the same boss. `*boss-override*`, as `'("ogre" :summon
  :blink :haste)`, forces them for testing (a `defparameter`: reloading boss.lisp clears it, so set
  it again after). Empowered: drawn `scale` times bigger (`size-scale` on
  `creature`, which every strip's `:size` is multiplied by), about 3 m, `*boss-health*` (500),
  `*boss-pain-chance*` (1, the weapon's bonus still added), melee × `*boss-damage-scale*`, knockback at most `*boss-max-knockback*`,
  never gibbed, flyers hovering `*boss-hover*` so the sword reaches them, step `*nav-tall-lift*`
  since it is taller than `*nav-clearance-height*`. No vortex pulls or catches it (`vortex-proof-p`).
  It glows: `rim-glow`, a shader mixin the boss and elites (`src/elite.lisp`) share, multiplies it
  by its `rim-shade` (the boss's `*boss-shade*`) and draws a pulsing rim on every opaque texel
  beside a see-through one (on that class's program only), in `*boss-glow-color*`, with a lamp of
  its own (`light-rim`). Warded shows as an arc of violet `aurora` on the floor round its
  front (`update-ward`, `*ward-colors*`), over exactly the sector its reflection covers
  (`ward-arc`: the billboard views `shield-views` covers, a quarter of pi each, so 135°), turning
  with its facing. Powers are
  `boss-power`s (`define-boss-power`: cooldown, frame times on the kind's `power-animation`, the
  4-frame attack or cast strip, `usable`, `start`, `release`, and `deny`, the kinds and traits that
  never get it). `special-attack` starts the first ready, usable one, then waits `*boss-power-gap*`
  so its own attacks get a turn; while `boss-power` names one, the attack readers and
  `release-attack` answer for it. Haste and enrage speed its attacks by running `attack-step` on a
  scaled `dt`, and its walk through methods on `walk-speed` and `chase-speed`.

  | Power | What | Denied to |
  | --- | --- | --- |
  | `:fire-volley` | 5 cinders fanned over 0.6 rad | |
  | `:skull-barrage` | 3 homing grave skulls | |
  | `:grave-circle` | `grave-spikes` under the player | necromancer |
  | `:leap` | the ogre's (`try-leap`, `leaper`) | flyers, casters, ogre |
  | `:shockwave` | a 0.9 s crouch, then `quake` round itself out to `*boss-quake-radius*` | flyers |
  | `:tornado` | the wraith's cast, sign and tornado; one up at a time | gale wraith |
  | `:summon` | 2 of its kind at normal size (3 enraged), `summoned`, while fewer than `*boss-max-minions*` live: a `summon-sigil` draws itself in on the floor at each spot through the 1.1 s cast (`begin-summon`, `summon-spots`), and at the release flame bursts up from each (an `aurora` in `*sigil-flame-colors*`) and a minion rises out of it; a broken cast takes its sigils with it | |
  | `:blink` | a ranged kind 9 m off a close player, a melee kind behind a far one | riftwalker |
  | `:warded` (passive) | its front turns spells back (`shield-views`) | knight |
  | `:haste` (passive) | walk and attacks × `*haste-speed*` | |

  Casters are the acolyte, necromancer and wraith; flyers the harpy and wraith. It sleeps
  (`dormant-p`, creature.lisp: it neither thinks nor takes harm, a hit only flashes) until the
  player is `*arena-trigger-depth*` inside the arena's doorway. Then `seal-arena` drops the gate
  (a `gate-sprite`, an ornate iron portcullis, that `add-arena-gate` makes in `setup-scene`: a
  `billboard` lit like the monsters but turned for good to face into the arena, its own tick
  replacing the billboard's, standing in the middle of the doorway's wall and hidden up in it while
  open; its gaps are see-through, and its solid, `gate-box`, is added to `*solids*` and indexed
  again) and the boss hunts for good. `*arena*` (an `arena`:
  its map-block, doorway, boss, gate) is noted by `place-block` for a block tagged `arena`. Enraged
  (`enrage`): the third power, a roar, moves × `*boss-enrage-speed*`, pauses × `*boss-enrage-pause*`,
  cooldowns × `*boss-enrage-cooldown*`. Its summons die with it, nothing hurts the player once it
  is dead (`run-won-p`, asked by `hurt-player`), and `*victory-delay*` after its death animation
  `win-run` puts up the victory screen; on any other level (the test level) the gate goes up
  again instead and the boss stays dead (`stays-dead-p`), so a reset brings another. Only a
  generated level's dead boss makes the player unhurtable. `reset-run` raises the gate and puts it back to sleep
  (`unseal-arena`, `reset-boss`). A save keeps its powers, sleep, enrage and cooldowns
  (`saved-slots`) and the seal (`:arena`). The boss bar across the top of the HUD (hud.lisp) shows
  its title, health with a mark at half, and its powers, from the seal until it dies.
  `tools/hd status` shows the arena and boss. The debug level has an arena of its own down a
  corridor south of the hall (see `src/level.lisp`). `(start-boss-fight)` (the main menu's Boss fight in a
  debug version) starts a run on its last level with the player outside the arena's doorway and every
  other monster taken out of the level; a save made there doesn't load (its monsters don't match),
  so test saves on `(progn (start-level :generated) (setf *run-depth* (run-length)))`. To enrage it,
  `(game (hurt (arena-boss *arena*) 255))`.
- `src/settlement.lisp`: the settlement, a level of its own once a run (see "The settlement"
  below): the `settlement` class (`*settlement*`, defined in run.lisp, NIL on any other level),
  `*factions*`, `*conditions*`, prices (`price`, `*base-prices*`) and reputation
  (`faction-reputation`, `adjust-reputation`).
- `src/townsfolk.lisp`: the townsfolk, the E key (`interact-target`, `interact`), the watch's
  crimes (`report-crime`), sacking (`sack-town`) and the `settlement-director`. See "The settlement".
- `src/dialogue.lisp`: talking to the townsfolk (`dialogue-panel`, `*game-state*` `:talk`) and
  what they offer: the shop, the priest, the trainer, fines and bribes, and the quest. See "The settlement".
- `src/magic.lisp`: what the forge's effects do, and statuses. An effect with a duration leaves a
  `status` on an actor (the `afflicted` mixin, creature.lisp, on creatures and the player; `afflict`):
  damage or health a second (`:damage`, `:heal`, dealt every `*status-tick*` through `burn` or
  `hurt-player ... :shove NIL`, `status-blow`), a `:slow` (percent, `slow-factor` in `walking-speed`
  and the player's walk, at most down to `*slowest*`), a `:ward` (points `hurt-player` takes off a
  blow after the shield, `absorb-ward`). One of each kind; a second keeps the stronger and the longer.
  `update-statuses` runs in each actor's tick and allocates nothing. A creature takes on its
  status's element colour (`status-tint`, `*element-tints*`). Elements: frost also chills
  (`*frost-chill*`), shock adds `*shock-pain-bonus*`; `*element-resistances*` halves an element for a
  class (acolyte fire, skeleton frost, gale wraith shock). Drain heals its caster `*drain-share*` of
  what it took. Statuses are `saved-slots` (`(:status ...)` in a save). A status keeps its
  `duration`, the time it was put on or last renewed for (`afflict` resets it when a re-cast lasts
  longer than what is left), for the HUD's time bar. Damage over time shows on a creature as a
  `status-aura` (its `status-aura` slot, on `afflicted`): its element's loop of small pieces scattered
  over and round the body (`*status-auras*`: burn, wisps of flame and embers, with a flickering
  orange lamp; frost, snowflakes and ice crystals drifting off it, no lamp; shock, crackling arcs, a
  dim blue-white lamp; and for healing over time, `:heal`, green pluses rising off it with a faint
  green lamp, though no creature heals itself so yet, in a slot of its own, `heal-aura`, so a creature
  under both shows both, the heal's a little further back, `*heal-aura-pull*`, so they never
  flicker; `aura-key`, `sync-aura`), an effect sprite standing at `*aura-rise*` of the body, its height the
  entry's SIZE times the body's (fire 1.25 and frost 1.15, so they reach past its outline: wisps on
  a red imp were lost in it; shock 0.85), drawn in proportion (stretched, the pixel art smeared), so
  a boss burns bigger, and pulled `*aura-pull*` toward the camera so it draws in front of the
  billboard. The colour tint (`status-tint`) is left to the slow and the frost chill. The creature's tick
  spawns and ends it (`update-status-aura`): gone when the status runs out or the creature dies.
  A save leaves it out (`level-effects`), and it comes back from the status; `preload-status-auras`
  stages the strips. The frost chill keeps its tint only. To look at one:
  `(game (afflict (aref *creatures* 0) :damage 1 8.0 :element :fire :caster *player*))`.
- `src/forge.lisp`: the spellforge, used at an altar (`add-altar`, pickups.lisp; `near-altar-p`, within
  `*altar-reach*` across and `*altar-height*` of its top; the HUD's prompt line says "[E] Spellforge"
  there, the altar being one of E's targets, `interact-target`, townsfolk.lisp). E opens it (`open-forge`, `*game-state*`
  `:forge`, frozen; Esc or Leave closes it; `*forge-anywhere*` opens it anywhere in a debug version).
  Making costs arcane dust (an item, `:dust`): a spell `*dust-per-mana*` (1) a point of its mana per
  cast (`spell-dust`), an enchantment `*enchant-dust-scale*` (3) a point of its mana per blow
  (`enchant-dust`); destroying one gives back `*dust-refund*` (0.5) of that (`refund-dust`). Two tabs
  (`*forge-tab*`, `forge-tab`): **Spells** lists "New spell" and every rune in the bag (`player-runes`,
  `*forge-list-rows*` a page, `forge-page`), **Enchant** the weapons carried (`carried-weapons`: every
  sword and spear in the bag, each a stack, its sink, and the shield, `:shield`, with a sword;
  `weapon-sink-p`, `sink-weapon`, `(setf sink-spell)`; `(forge-select :sword)` from the REPL takes the
  first sword). The forge is on one of them (`*forge-sink*`,
  `forge-select`): a new spell or a plain weapon has a draft to make (`*forge-draft*`, kept per sink in
  `*forge-drafts*` while the forge is left: a `forge-draft` of a delivery and `effect-draft`s), made by
  `forge-make` into a rune in the bag on the first free key (`give-rune`) or the weapon's enchantment;
  a rune or an enchanted weapon is only shown (`shown-spell-lines`) with Unweave or Disenchant
  (`forge-destroy`, two clicks: the first arms it, `*forge-armed*`). Nothing is changed in place: make
  another, or destroy it; spells are limited only by free bag cells. Effects and elements are those the
  player knows (`known-effects`: `*starting-effects*`, damage, heal, knockback and fire, plus what glyphs
  taught; `:area` unlocks area), and of those only the ones that land where the draft does (`draft-kinds`): a
  spell cast on yourself takes heal and ward, a projectile, a touch or a weapon damage, knockback, slow
  and drain. Changing the delivery turns the effects that no longer fit into the first kind that does
  (`fit-effects`). A run starts knowing only fire, so with one element (or one kind for the delivery)
  known, the Element or Effect button doesn't change it but says so in the note, naming the glyphs
  that teach the rest (`forge-cycle-element`, `forge-cycle-kind`). `draft-problem` says why a draft can't be made (self delivery with something to
  strike, a delivery with nothing to, more than `*max-mana*`, a weapon's more than
  `*max-enchant-effects*` or `*max-enchant-cost*` a blow, too little dust, a full bag). A draft's name
  is made from its effects (`draft-name`, "Frost Burst"). The screen is `forge-panel`, a `menu-panel`
  that lays itself out (`build-panel`, menu.lisp): the tabs and sinks down the left, labels cut to
  `*forge-label-width*` (`fit-label`), each a `forge-choice` (a `menu-button` that draws the chosen
  one with a gold border, a warm fill and a gold label, `*forge-selected-color*` and the rest, apart
  from the hover's orange), the work on the right, its sliders `forge-slider`s (a
  `menu-slider` with its own range and value text), under each effect its explanation (`effect-about`,
built from the parameters: the kind's rule, the element's quirk, who resists it from
`*element-resistances*`, what time and area change; a `forge-about`, smaller and dimmer), and its
text `forge-note`s, which wrap (Alloy's
  `:wrap`) in rows as tall as `note-lines` guesses. A structural command bumps `*forge-revision*` and
  the menu controller remakes the panel (`panel-stale-p`); a slider only changes the draft and the
  readout and note (`alloy:value-data`s the panel keeps). From the REPL: `(game (setf
  *forge-anywhere* t) (open-forge))`, then `(forge-tab :enchant)`, `(forge-select :sword)`,
  `(forge-make)`, `(forge-destroy)` twice.
- `src/elite.lisp`: elites, a deeper level's stronger monsters. A spawn on a generated level is
  one with the level's `*elite-chance*` (`:elite-chance` in `*run-levels*`): `elite-roll`, from
  `place-block`, draws from `*elite-random*`, a state of its own seeded from the level's, twice for
  every spawn whatever it decides, so elites never move the layout or another spawn. An elite is
  its kind's class with the `elite` mixin first (`elite-imp` .. `elite-wraith`, `elite-riftwalker`
  in riftwalker.lisp, `*elite-kinds*`):
  `*elite-health-scale*` (1.75) its health, drawn `*elite-size-scale*` (1.15) bigger but never past
  `*nav-clearance-height*` (the ogre not at all), its body as its kind's, so it goes wherever its
  kind goes, and a rim and lamp (`rim-glow`, boss.lisp) in its trait's colour, `*elite-glow-colors*`,
  none of them the boss's orange. Its one trait (`elite-trait`): `:haste` (cyan, walk and attacks ×
  `*elite-haste*`), `:warded` (violet, its front turns spells back, `shield-views`; never the
  knight's) or `:tough` (bone-white, half the pain chance and the knockback). Summoned and raised
  creatures and the boss never are. A save needn't keep the trait: the rebuild draws it again.
  `*elite-override*` (`:all`, or a trait) makes every block spawn an elite, on any level (on the test
  level, the blocks attached to it: the shrine and the pool). `tools/hd status` shows `elite:<trait>`.
- `src/pickups.lisp`: pickups, which the player takes by touching them. `*pickup-kinds*` has the
  amounts: `:herbs` +15 health and `:shard` +28 mana (2 bolts) restore at once; at full one stays
  where it is, below full it is taken and any excess lost (`restore-resource`). `:health-potion`
  (+40) and `:mana-potion` (+50) have an `:item`, and go into the inventory (`give-item`,
  inventory.lisp) whatever the health, staying only if there's no room. A `pickup` is an upright, fullbright, unfogged effect sprite with no lamp, bobbing
  `*pickup-hover*` over its floor (`pickup-ground`), touched within `*pickup-reach*` across and
  with the feet from `*pickup-below*` under that floor to `*pickup-above*` over it, so one on a
  0.8 m sarcophagus takes a jump. Only the player touches them. Taken (`taken`), it stays in the
  scene undrawn, so `reset-run` only clears the flag, and a save keeps the taken ones' places in
  `*pickups*` (`:pickups`; none in an older save). It flashes the view (`restore-flash`, hud.lisp,
  a `pain-flash` with its own `flash-color`). The blocks say where one may go (`pickup` in a
  blueprint, `*pickup-spots*`), and `place-pickups`, last in `build-level`, fills a generated level
  (`scatter-pickups`) until they restore `*health-per-monster*` (10) and `*mana-per-monster*` (15)
  per monster, every `*pickup-potion-every*`th (2nd) of a resource a potion, on a reward spot if one
  is free in a block with no pickup yet and otherwise anywhere. It skips
  the start block and spots the player can't reach (`spot-reached-p`: a floor spot's own cell, or
  for a reward spot a floor up to `*jump-reach*` under it within 2 m), keeps to one a block until
  blocks run out, and likes rooms `*pickup-room-weight*` times as much as corridors. It draws from
  a random state of its own seeded with the level's, so a seed always places the same ones. A save
  names the taken ones by place, so changing how they're scattered makes an older save mark the wrong
  ones taken. Over seeds 1 to 30, on a run's first level: 42 monsters (27 to 63), about half of them imps
  (imp packs, imp.lisp), and 32 pickups; since then 45 monsters (29 to 65), measured once its pool kept
  out the high quarter's ogres. Before packs it was 33 monsters and 26 pickups (half of each
  resource potions, 5 to 8 of each, restoring 343 health and 509 mana), on its second 40 and 32, on its
  third 48 and 38. Mana doesn't regenerate, so they are its only source in a run. A new kind of pickup is a
  method on `collect-pickup`. To try one: `(setf (health *player*) 50)` and
  stand on `(location (aref *pickups* 0))`.
  **Glyphs** are pickup kinds with `:teaches` (`:glyph-frost` .. `:glyph-area`): touched, they teach
  the player an effect for the forge (`learn-glyph`: `known-effects`, a gold flash, a message), and
  one already known stays. Each level of a run has `*glyphs-per-level*` (2), the run's six shuffled by
  the run seed alone (`run-glyphs`), so the first three levels teach them all and the last has none,
  placed after the other pickups (`place-glyphs`, from a random state of their own) on free spots, a
  reward spot first, so the other pickups keep their places. `scatter-pickups` leaves them their spots
  (`:reserve`, the level's glyphs and loot, `src/loot.lisp`, and the settlement's relic): the settlement's small wing ran out and
  lost a glyph for the run. The town's shopkeeper sells the ones the player doesn't know (see "The
  settlement"). The test level has one of each along the hall's south wall, west of the pickups. **Arcane dust**
  (`:dust`, an `:item` with `:count`: the pile's `pickup-count`) is placed last (`place-dust`, from a
  random state of its own, on spots `free-pickup-spots` leaves) until a generated level holds
  `*dust-per-monster*` (2) for each monster (`monster-p`: not the townsfolk), in piles of `*dust-pile*`
  (8 to 20; bigger where few spots are left, so a level gets its whole budget while it has a spot:
  about 60 to 120, three to six spells). Sprites:
  `tools/draw_glyphs.py data/sprites/pickups` (a rune tablet per glyph, and `altar-sigil`).
  **Altars**: `add-altar` notes a point in `*level-altars*` (blocks.lisp; a blueprint's `altar`) and
  hangs an `altar-sigil` over it with a lamp; `reset-run` keeps it. The test level has one on a dais
  in the hall's north-west corner.
- `src/loot.lisp`: found weapons and runes. A run starts with the sword, the fire bolt and heal; the
  rest is loot. Each level's `:loot` (`*run-levels*`, run.lisp; `loot-property`, which takes the
  settlement's own `(:weapons 0 :runes 1)` before the level it borrows the rest from) gives its
  `:weapons` (level 1 a plain spear, `:first-weapon`) and `:runes`. A weapon is a sword or spear with
  the usual stats; only its enchantment varies: `:enchant-chance` (0, 0.5, 0.8) of one costing
  `:enchant-cost` a blow (2-3 on level 2, 3-6 on level 3) with up to `:enchant-effects`
  (`loot-enchantment`). A rune (`make-loot-rune`) is a generated spell made as the forge makes one,
  from a `forge-draft` (`loot-rune-draft`: a delivery from `*loot-deliveries*`, kinds from
  `*loot-strike-kinds*` or `*loot-self-kinds*`, up to `:rune-effects`, elements, times
  (`*loot-durations*`) and, with `:area-chance`, a burst), its magnitudes sized by bisection
  (`size-draft`) to a cost in `:rune-mana` (10-18, 16-28, 24-40), drawn again while `draft-fault`
  (forge.lisp, the forge's checks without the dust and bag) refuses it or it falls more than
  `*rune-mana-slack*` short. Or it is one of `*loot-spells*` (the tornado, `tempest`), which the forge
  can't make: once a run at most, on the first level whose `:authored-chance` (0.35, 0.5) roll from the
  run seed comes up (`authored-loot`); 13 of run seeds 1 to 15 had it. `place-loot` (after the glyphs,
  before gold and dust; `scatter-pickups` reserves the spots, `loot-count`) stands each as a
  `loot-pickup` (its `loot-stack`, given as a copy so a reset hands out the same) on a reward spot
  first, from a random state of the level's seed, so a load builds the same items; taken, it goes
  into the bag on the next free key with "Found a sword: Frost Edge, on key 4." Its sprite is
  `loot-sword`, `loot-spear` or `loot-rune-<look>` by its spell's look (`tools/draw_loot.py
  data/sprites/pickups`). An enchanted weapon's pickup has the outline it has in hand: `loot-pickup` is a `rim-glow`
  (boss.lisp), its rim in the enchantment's colour, pulsing as the weapon's in hand (never dimmed). A
  rune's stone shows its look, not its first effect as its icon does. The debug level has
  a spear, an enchanted sword and two runes east of the dust (`place-test-loot`, from seed 7 and the
  last level's `:loot`). `tools/hd status` shows an enchanted weapon as `sword[frost-edge]`. A
  stranded ogre's hoard (`place-hoards`, after the dust) is one more item; see "The ogre".
- `src/inventory.lisp`: the inventory, the hotbar, the quickslot and the panel. `*item-kinds*` says
  what an item is (name, frame in `data/sprites/icons/items`, what it restores, how many fit in a
  stack); a pickup's `:amount` must match its item's, since a level's budget counts it. Potions stack
  5; arcane dust (`:dust`, the forge's, forge.lisp) and gold (`:gold`, nothing uses it yet) 999.
  Weapons and spells are items too: `:sword` and `:spear` (`:weapon`, what they put in hand), a stack
  `(:sword 1 enchantment)` (`stack-enchantment`, each weapon its own; `(:sword 1)` is plain), and
  `:rune`, a spell the hands cast, its stack `(:rune 1 spell)` (`stack-spell`; not `:spell`, a save's
  tag for a spell reference); none of them stack. `give-stack` puts one in the first free cell, bound
  to the first free key (`give-rune` makes a rune's). A stack is a list `(kind count)`. **The bag holds
  every item** (the player's `inventory`, `*inventory-size*`, 20 cells); the hotbar and the quickslot
  only point into it, so binding a key frees no room: a hotbar slot (`*hotbar-slots*`, `:hot-1` ..
  `:hot-9`, the player's `hotbar`, `*hotbar-size*` long) holds a stack in the bag (`eq`), the quickslot
  a potion kind. A slot is a cell's index, a hotbar slot or `:quick` (`slot-stack`, which shows the
  quickslot as `*quick-view*`, its kind and the bag's total of it, `kind-total`). A drag
  (`move-stack`): between bag cells it moves, merges or swaps, and the keys bound to the stack follow;
  a bag weapon or rune onto a hotbar slot binds that key (`bind-stack`, off any other), a potion onto
  Q binds Q; two hotbar slots swap; a hotbar slot or Q dropped anywhere else is unbound. A stack that
  leaves the bag is unbound (`prune-bindings`, from `sync-wanted` every tick, and `destroy-stack`).
  Bag cells mark the key bound to their stack. A run starts with `give-starting-kit` (player.lisp's
  `initialize-instance`, `reset-player`): `*starting-hotbar*`'s items in the first cells, bound to
  keys 1 to 3 (sword, fire bolt, heal), slot `*starting-slot*` (the sword) in hand; the rest is found
  (`src/loot.lisp`). The debug level starts with `*debug-starting-hotbar*` instead, keys 1 to 5
  (sword, bolt, spear, tempest, heal), so the recipes below that use keys 3 and 4 work there. The hotbar draws in
  rows of `*hotbar-columns*` (5) over the bars (`hot-position`; in one row of nine the hands covered the
  last), each slot with its key, the one asked for framed in gold, the others' icons dimmed in play, an
  enchanted weapon's border in its spell's colour. A rune's icon is its spell's look's (`stack-icon`:
  weapons and runes from the weapon icons, sword.lisp, `swap-animation` when the strip changes). A save
  and the stairs keep the hotbar as bag cells (`hotbar-cells`, an accessor in `saved-slots` after
  `inventory`), and `migrate-bindings` brings an older save's held stacks into the bag. `give-item
  player kind count` puts items onto their stacks, then into empty cells (how many went in), and binds
  an unbound Q to the first potion; `take-item` takes from the smallest stacks. Q (`use-quickslot`)
  drinks one of its kind from the smallest stack, not at full; at none it stays bound, dimmed, and
  shows 0. The mouse wheel in play (`cycle-quickslot`) binds Q to the next potion kind the bag holds. I
  opens the panel (`*game-state*` `:inventory`, frozen as `:map` is), I or Esc closes it. Parts of the
  panel are `inventory-part`s (`hud-shown-p` only in `:inventory`) with a `late-rank`, so its
  see-through back never covers world drawn after it. The quickslot has a row of its own above the
  hotbar (`quick-position`), the spell in hand right of it (`spell-label`), the panel right above it
  (`panel-box`). The hint (`*inventory-hint*`) is wrapped to the panel's width (`hint-lines`, up to three
  `panel-hints`; `panel-box` grows to hold them) and goes blank while the pointer is on a stack, and a
  tooltip beside it (`update-tooltip`, up and right of the pointer, kept on screen; not while dragging)
  gives it in detail, one line each in `stack-details`, wrapped to `*tooltip-width*` (`wrap-text`,
  hud.lisp) up to `*tooltip-lines*`: a rune's delivery, cost and every effect (`spell-lines`,
  `effect-lines`: magnitude, time, area, an element's chill or stagger); a weapon's damage, reach,
  swing time and its enchantment (`enchantment-lines`; the sword's shield too); a potion's restore,
  this stack and the bag's total; dust's and gold's use (`:about`). Its parts are `tooltip-part`s with
  the highest `late-rank`s, at depths in front of the hotbar's and quickslot's labels (which sit at
  -0.08 for it). A new item is an `*item-kinds*` entry and a frame in `tools/draw_item_icons.py`
  (potions, dust, gold, the reliquary). To try it: `(game (give-item *player* :health-potion 3))` and `(game
  (open-inventory))`; `tools/hd status` shows the hotbar (the slot asked for starred), the quickslot
  and the bag.
- `src/status-icons.lisp` (after inventory.lisp, whose cell size it shares): the player's statuses
  as a row of icons in the top-left corner, under the frame counter while it shows. One cell per
  status in `*status-order*` (damage, slow, heal, ward; one of each kind at most, so four cells,
  and a fifth, `:bless`, for the priest's blessing, which isn't a status but shows as one, from
  the player's `blessed` over `*bless-time*`; the unneeded ones not drawn), like a hotbar slot: its border and time bar in the status's colour
  (`*status-colors*`, by element for damage), its icon (`*status-icon-frames*`, a frame of
  `data/sprites/icons/statuses`, drawn by `tools/draw_status_icons.py data/sprites/icons/statuses`:
  burn, frost, shock, regen, slow, ward, bless), the seconds left (a ward's points instead, which run out
  first) over the bottom-right corner, re-uploaded only when they change, and a bar along the
  bottom for `left` over `duration`. In its last `*status-warn-time*` (3 s) the icon blinks. An
  instant heal or ward-less spell leaves no status and so no icon; its flash is the feedback.
  To look at them: `(game (afflict *player* :ward 12 20.0) (afflict *player* :slow 30 6.0))`.
- `src/hud.lisp`: HP, mana and stamina (SP) bars in the lower-left corner, an AIR bar over them while
  breath is short (`breath-element`; `hud-top` moves up a row with it), and the red pain flash over
  the view (`pain-flash`, from the player's `pain`). HUD pieces are `hud-element`
  entities drawn in pixel coordinates (origin bottom left) at the near plane; place them
  on whole pixels, since a half-pixel position drops an edge row. Overlapping elements
  take a depth in `place` (below 0 is further back). `hud-top` is where the bars end.
  `hud-shown-p` decides whether an element draws (by default, not on the main menu). The
  frame counter (`fps-display`) sits in the upper-left corner while `*show-fps*` is on,
  on every screen, counting frames in its render and updating every `*fps-interval*`.
  Right of the quickslot: the spell in hand (`spell-label`, inventory.lisp). The hands, like the
  sword, draw at `*weapon-depth*` (hands.lisp), behind every HUD element. The player's statuses are icons (`src/status-icons.lisp`). The purse
  (`gold-text`) is in the lower-right corner.
  `show-message` puts a line across the view for `*message-time*` (a glyph's, a gold find, the
  watch's warnings; `hud-say` formats one), and `*interact-prompt*` under it says what E does with
  what the player looks at or stands at (`prompt-line`; a new string only when it changes, so the
  tick tells by EQ). A pickup of a
  counted item (dust's pile) puts "+25 arcane dust" just above
  the crosshair for `*pickup-note-time*` (`note-pickup`, the `pickup-banner`; the item's `:note`,
  else its name), pickups of one kind in quick succession adding up.
- `src/menu.lisp`: the main menu and the Esc pause menu, built with Alloy (Trial's UI
  toolkit) in their own pass, blended over the game in `setup-scene`. `*game-state*`
  (`:title`, `:playing`, `:paused`, `:map`, `:inventory`, `:talk`, `:dead`, `:victory`, defined in creature.lisp) decides which is up;
  anything but `:playing` makes `frozen-p` true, which stops everything that moves.
  Transitions: `start-game` and `start-debug-level` (both `start-level`: set `*level*`
  to `:generated` or `:test`, put the loading screen up (`:loading`) for
  `*loading-frames*` ticks, then rebuild the scene; `*new-run*` tells `setup-scene` to put
  the new player at the spawn point, fresh, and start play), `descend` (the next level of the run:
  the same loading screen and rebuild, by `load-level`, see "A run"), `pause-game`, `resume-game`, `show-title`,
  `exit-to-title` (the pause menu's and death screen's exit: back to the main menu, with the
  level put back in place by `reset-run`, no scene rebuild)
  and `exit-game` (quits; main menu only).
  Zero health on a generated level sets `:dead` (`player-dies`, player.lisp; every other level
  still queues `reset-run`): the world freezes, the pain flash holds, and `fall-dead` drops the
  eye to `*death-eye-height*`, rolls the view (`*death-roll*`, the player's `project-view`) and
  sinks the weapons. After `*death-panel-delay*` the `death-screen` comes up with the mouse
  released: `death-stats` (killed by, time survived, monsters slain, areas explored, damage
  taken, the seed) and a button back to the main menu. Esc, F5 and F9 do nothing there: death
  ends the run, with no quickload back into it. `hurt-player`'s `:by` says what killed the player (a creature, `:lava`,
  `:drowning`, `:tornado`): a new source of damage passes it. `run-time` and `damage-taken` are saved.
  Killing the boss sets `:victory` (`win-run`, boss.lisp) and the `victory-screen` comes up:
  `victory-stats` (the boss slain, then `run-stat-lines`, the rows it shares with the death
  screen) over the `victory` splash, and the same button back. Esc and F5 do nothing there.
  A new menu is a `menu-panel` subclass with `panel-title` and `panel-buttons` (the
  loading screen is one with no buttons). A `panel-buttons` row is `(label action)`, a
  button, `(label :toggle variable)`, a checkbox (`menu-toggle`) that sets that special
  variable, or `(label :slider variable)`, a slider from 0 to 1 (`menu-slider`: the whole row,
  filled from the left, the percentage at its right, `*menu-slider-step*` a key or wheel notch);
  an action may also be a closure. Hovering a row gives it the keyboard focus, so
  one row is lit at a time. `panel-width` is the column's width (`*menu-width*`; the slot
  panels' is wider, for their labels). `panel-lines` adds `(label value)` rows of text
  between the title and the buttons (`menu-stat`, `*menu-stat-height*`; the death screen's stats).
  The panel works out its column's height from its rows, a `*menu-row-gap*` per row and
  `*menu-slack*`; too short, the last button hangs out of the column, and Alloy sends no click on
  that strip to it (the death screen's button lost its bottom 18 px, the main menu's 8). After
  changing row sizes, check no element sticks out of its parent's bounds.
  Settings (`open-settings`, on both menus) covers the menu it came from while
  `*settings-open*` is true; Back or Esc (`close-settings`) returns to it. It has Music and
  Sound volume (`*music-volume*`, `*sound-volume*`, music.lisp), Show
  FPS (`*show-fps*`, in memory only, kept across reloads) and, in a debug version
  (`*debug-version*`), Debug minimap (`*map-debug*`: the automap shows every block, creature
  markers and block names). The main menu's Debug level and Boss fight are also debug-version only.
  Load game (both menus) and Save game (the pause menu, on a generated level only) cover it
  the same way while `*slot-menu*` is `:load` or `:save`: a row per slot in `*save-slots*`
  (1 to 3, then the quicksave), labelled by `slot-info`, and Back (`close-slot-menu`). After
  a save the pause menu's title says where it went (`*save-note*`). F5 quicksaves and F9
  quickloads (`quicksave`, `quickload`, from the menu controller). See `src/save.lisp`.
  `panel-splash` names a picture in `data/splash/` to cover the screen with (the main
  menu's `title`, the loading screen's `loading`, the death screen's `death`, the victory screen's `victory`, and Settings' over the main menu; see
  "Splash screens" below); NIL, the pause menu's, dims the game behind it instead. `panel-top` places the menu from the top
  of the screen (T, the default, centres it; the main menu's `*title-menu-top*` keeps it
  off the dagger in its splash).
- `src/music.lisp`: music, through Harmony (`trial-harmony`; `main` is its `main`, which starts
  the sound server: PulseAudio here). In play the `music-director` (entered by `add-music` in
  `setup-scene`, which stages every track's voice) plays the level's playlist at random
  (`music-playlist`, from `*music-moods*`: the three exploration and five combat loops, assets
  `music-explore-1` to `-3`, `music-combat-1` to `-5`, `data/music/<name>.ogg`, on Harmony's
  `:music` mixer; exploration only in the settlement, combat only on a run's level with the
  boss's arena, both elsewhere, the debug level too), crossfading over `*music-fade-time*` to
  another (`pick-track`, from `*music-random*`, never the one playing) every `*music-track-time*`
  (3 min) of play. `*screen-music*` gives the main menu `music-title` (composed, see "Sound and
  music"), the death screen `music-death` (the first explore-2, a drone) and the victory screen
  combat-4; a screen's track starts from the top whenever its screen comes up (`restart-track`,
  which seeks in the mixing thread). `music-wanted` says which track the game state wants and
  `music-target` how loud: `*music-pause-volume*` under the pause menu, silent on the loading
  screen, full everywhere else. A playlist track faded out pauses and picks up there when it comes
  round again. (Music that followed the fighting, combat while a monster hunted the player, was
  dropped: monsters notice and lose the player every few seconds, so it swapped back and forth.)
  `*music-volume*` and `*sound-volume*` (Settings, in memory only like Show FPS) are the
  `:music` and the `:effect` and `:speech` mixers' volumes (`apply-volumes`). **Every track is
  started once and then only paused and unpaused** (`connected-voice`, `*connected-voices*`, which
  outlives rebuilds; `harmony:paused-p` is a flag on the voice's unpacker: paused, its source stops
  decoding and it outputs silence). Never `harmony:stop` and `play` again: `play` only queues the
  voice's connection for the mixing thread, while `stop` decides on the game thread, from whether
  it is connected yet, to do nothing. A rebuild that picked a fresh exploration track and then hit a
  fight at once stopped it before it was connected, and its next start left it silent for good,
  though it read as playing and its position advanced. To check what really reaches the speakers,
  record the game's own PulseAudio stream: `parec --monitor-stream=<its sink-input index>` (`pactl
  list sink-inputs`, application name `trial`). An error in Harmony's mixing thread doesn't reach the
  runtime-error guard: it waits in the debugger (seen in `./run.sh`'s output), the queue stops, and
  every later start, stop and `harmony:with-server :synchronize T` hangs (connecting a stereo voice
  to the `:effect` mixer, a space mixer, does it).
  To watch it, `(levels (node :music-director (scene +main+)))`, `(current ...)` and `(wanted ...)`. See "Sound and
  music".
- `src/sound.lisp`: sound effects, through Harmony like the music. `audio/sfx.md` lists every
  sound the game needs and where its hook goes. `(play-sound :clip at)` plays a one-shot at a
  vec (positional clips; without AT, at the listener) or unplaced (first-person clips);
  `start-loop` holds a loop's voice, `move-loop` moves it each tick (allocating nothing) and
  `stop-loop` gives it back, returning NIL for the holder's slot: a projectile, circle, vortex,
  sign or channel keeps its loop in a slot and stops it in its `leave :after`. Clips are
  keywords from `data/sfx/index.lisp`; a clip not made yet plays nothing. Each clip keeps
  voices of its own (Trial's sound assets play one copy at a time): `*sfx-voices*` per file,
  taken in turn, the oldest cut short when all are busy, and `*loop-voices*` per loop, made
  once by `add-sounds` (from `setup-scene`) and kept in `*sounds*` across rebuilds;
  `(reload-sounds)` then a reset picks up re-made files. **The game thread never touches a
  voice's connection**: `play-sound` pushes a request, and the `sound-director`'s tick hands
  Harmony's mixing thread one function, `sound-frame`, that starts them, moves the listener
  (`*listener-location*`, the player's eye) and the loops, and pauses the loops whenever
  `*game-state*` isn't `:playing` (not under hit-stop). Harmony's queue holds 64 jobs, and an
  error in its thread stops all sound for good, so `sound-frame` keeps its errors in
  `*sound-error*`. The space mixer's axes are the other hand to the game's, so `copy-into`
  mirrors Z (checked by recording: a sound on the player's left plays in the left channel);
  a positional sound is at full volume within `*sound-min-distance*` (4 m) and then fades as
  (distance / min)^-`*sound-rolloff*` (0.75: 4.5 dB a doubling; at 1 and 2 m, as it was, sounds
  were barely heard across a room), no quieter past `*sound-max-distance*` (50 m). A big sound keeps
  full volume further out (`*clip-min-distances*`: the tornado and the ogre's leap roar 12 m, its
  landing 10, its footsteps 8). `tune-voice` sets them on a voice as it connects;
  `(game (retune-sounds))` re-tunes those connected already after a change.
  A creature's clips are `define-creature-sounds` (creature.lisp; `creature-noise` plays one),
  a spell's `*spell-sounds*` (spells.lisp), a weapon's `*weapon-sounds*` (sword.lisp).
  `hold-loop`, called every tick, keeps a holder's loop in a slot while it is wanted (the
  player's slide on ice, the water and the wind, a creature floundering, the boss's ward).
  The player's footsteps and strokes are `body-sounds` (player.lisp); the torches', lava's and
  water's loops and the room tone are `update-ambience` (liquids.lisp, `*ambient-sources*`),
  holding `ambient-voice`s on the nearest few sources. `audio/sfx.md` says where each clip
  plays and how the hooks differ from its tables.
  To hear one: `tools/hd '(game (play-sound :imp-pain (v+ (location *player*) (vec -3 0 0))))'`.
  To find which sound misbehaves, `tools/hd '(game (mute :ambience))'` silences a clip or a group of
  `*sound-groups*` (`:music`, `:effects` for every clip), loops already playing too, and `(unmute)`
  brings everything back.
- `src/hands.lisp`: the first-person casting hands, sunk Hexen-style below the bottom
  edge (idle loop, cast, walking sway). Each hand is its own entity drawing half the
  frame, spread apart and closing up where they meet (`*hands-together*`). Scales are
  whole numbers, wider than tall (`*hands-stretch*`). The cast's release frame is timed
  to `*cast-release*`. Their fire takes the look of the spell in them (`*hand-looks*`, by
  `spell-look`: a tornado's `:storm`, else its effects'), one strip per look, each the fire strip
  recoloured, `tools/recolor_strip.py data/sprites/hands/hands data/sprites/hands/<look> --hue H`
  (storm 268, frost 205, shock 58 `--saturation 0.65`, drain 345, heal 115, arcane 295); `add-hands`
  preloads them all, since `swap-animation` changes the strip mid-game. The recipes (the hotbar's
  defaults) work as before: `(select-weapon *player* :1)` is hotbar key 1, the sword at the start.
- `src/sword.lisp` also has **enchantments**: a weapon's spell (a sword's or spear's its own stack's,
  `stack-enchantment`, so two swords differ; the shield's in the player's `enchantments` plist under
  `:shield`; `weapon-spell` asks for the one in hand, `held-weapon-stack`; made at the forge or found,
  `src/loot.lisp`; `migrate-enchantments` moves an older save's `:sword`/`:spear` entries onto the
  bag's first such weapon, after a load and the stairs) goes with every blow of it that lands
  (`enchant-strike`, from `swing-hit` and the bash), for `enchant-cost` mana (`*enchant-cost-scale*`
  of the spell's cost) out of the pool; with too little left the blow is plain, and a miss costs
  nothing. Its self effects land on the player. The weapon's border on the hotbar and in the bag takes
  the spell's colour, dimmed while mana can't pay (`weapon-enchantment`, `spell-tint`), and so does its
  sprite on screen: `sword` (and so the spear and the shield) is a `rim-glow` (boss.lisp), whose rim
  `rim-weapon`'s enchantment colours each tick, pulsing on `*light-clock*` (`*weapon-rim-strength*`,
  `*weapon-rim-pulse*`) and dimmed by `*enchant-dim*`; `*weapon-rim-width*` (2 texels, `rim-width`)
  since the weapons' art is fine-grained. The shield's rim is the shield's own enchantment.
- `src/sword.lisp`: the sword and weapon switching. The player holds one weapon: whatever the hotbar
  slot asked for holds (`wanted-slot`; keys 1 to 9, `select-slot`, or `select-weapon` with the key
  `:1` .. `:9`): the sword, the spear, or the casting hands with a rune's spell (`weapon` `:hands`,
  `held-spell`), or nothing for an empty slot. `sync-wanted` (every tick of `update-weapons`) reads
  `wanted-weapon` and `wanted-spell` off the slot, so a drag in the inventory changes what is in hand:
  a weapon or rune dragged off the slot leaves the player empty-handed. Switching lowers one off
  screen and raises the next, from one spell to another too; `settle-held` takes it in hand at once
  (after a load, the stairs or a reset).
  The sword is a single sprite against the bottom-right corner (its arm runs off that edge,
  so `*sword-overhang*` must exceed the sway). The slash plays `*swing-frame-times*` and the
  blow lands on `*swing-hit-frame*`: the nearest creature within `*sword-reach*` and
  `*sword-arc*`, not behind a wall. The sword's slash and the spear's thrust are both swings,
  through the same `swing-time`: generics on the weapon's keyword give each its timing and blow
  (`swing-frame-times`, `swing-hit-frame`, `swing-reach`, `swing-arc`, `swing-damage`,
  `swing-knockback`, `swing-pain-bonus`), and generics on the sprite which weapon it draws
  for and how its strip is laid out (`held-weapon`, `idle-frames`, `swing-first`, and
  `weapon-aim`, NIL to keep it against the bottom-right corner). The mouse wheel is the
  quickslot's (inventory.lisp). Weapon and rune icons are frames of `data/sprites/icons/weapons.png`
  (`*weapon-icons*`; a rune's by its spell's first effect, `spell-icon-key` into `*spell-icons*`:
  damage by element, a flame, a snowflake, a lightning bolt; drain a drop of blood, heal a cross, ward a
  shield, slow an hourglass, knockback a shockwave; a vortex the tornado), drawn by
  `tools/draw_weapon_icons.py data/sprites/icons/weapons`; a new weapon or effect kind needs a frame
  there.
  The left hand holds a shield, a sprite of its own (`shield`, a subclass of `sword`) against
  the bottom-left corner, at the sword's art pixel size (`sword-scale`), so it doesn't slide
  off on screens whose whole-number scale shows fewer art pixels across. It drops and sways
  with the sword. Both draw at `*weapon-depth*`, behind the bars, the hotbar and the
  pain flash. Holding the right button raises the shield over `*block-raise-time*`
  (`block-raise`, 0 to 1; not during a swing, and it comes down before a weapon switch);
  fully raised, a blow from within `*block-arc*` of the view (`shield-blocks-p`, player.lisp,
  asked by `hurt-player`, so it covers creatures' spells too) does `*block-damage-scale*` of
  its damage and shoves `*block-shove-scale*` as far, for `*block-stamina-scale*` stamina a point
  of the blow's damage; a blow with `:guard-break` (the knight's,
  the ogre's slam) also knocks it aside (`break-guard`: down at once, and `guard-broken`
  keeps it down), a blow with more cost than the stamina left goes through in full and knocks
  it aside for at least `*stamina-guard-break*`,
  and `:unblockable` ones (the ogre's shockwave, the grave circle) ignore it. Raised, it slows
  the player to `*block-speed-scale*` of a walk, no running. A left click with it raised bashes
  (`player-bash`, `*bash-frame-times*`): on `*bash-hit-frame*` the nearest creature within
  `*bash-reach*` and `*bash-arc*` takes `*bash-damage*` and is pushed `*bash-knockback*`.
  It rolls for pain with `*bash-pain-bonus*` only if the creature is winding up an attack
  (`winding-up-p`, creature.lisp), and never otherwise: a timed interrupt, not a stunlock.
  Every bash that lands leaves the creature poised (`bash-poise`, `*bash-poise-time*`), when
  another bash can't stagger it and shoves it only `*poised-bash-knockback*` as far
  (`bash-hit`, `swing-target` with the bash's reach and arc). `shield-frame` picks the strip
  frame: idle, `*shield-raise-frames*` rising, the block held, then the bash's.
- `src/spear.lisp`: the spear, held in both hands, so no shield (the right button does
  nothing with it; block and bash ask for `:sword`). Against the sword it reaches further
  (`*spear-reach*` 3.5 m against 2) in a narrower arc (`*spear-arc*` 0.3 rad), staggers more
  (`*spear-pain-bonus*` 35) and is slower: the thrust plays `*thrust-frame-times*` (0.68 s
  against 0.53) and lands at full extension, `*thrust-hit-frame*` (0.24 s in, against 0.23).
  Its sprite (`spear`) is a subclass of the sword's, drawn from `data/sprites/spear/spear`,
  at the sword's art pixel size (`sword-scale`) and sunk as far (`*sword-drop*`), but placed
  by its aim (`weapon-aim`, `*spear-aim*`: the point at full extension) on the screen's
  middle rather than against the right edge, so the thrust goes where the player looks on any
  screen width. A re-made strip whose extended point moves needs `*spear-aim*` measured again
  (`art/spear/spear-frames.txt` says how).
- `src/player.lisp`: first-person controller and box collision. Walking backward keeps
  `*backpedal-scale*` (0.75) of the speed. Mana doesn't regenerate:
  only a pickup, a new run or a load refills it. `stamina` (`*max-stamina*`) comes back at
  `*stamina-regen*` except while running, which costs `*run-stamina*` a second, on foot or
  swimming with Shift (`update-stamina`); running it empty leaves the player `winded`, walking,
  until it is back to `*winded-recover*`. A jump costs `*jump-stamina*` and needs it, and a blow
  on the raised shield costs stamina too (`hurt-player`, see `src/sword.lisp`). In water to the waist
  (`*swim-waist*`) the player swims, Quake-style (`swim`): W and S along the view, A and D
  level, Space up and C or Ctrl down, at `*swim-speed*` (`*swim-run-speed*` with Shift)
  against `*water-drag*`, sinking at `*swim-sink*` when swimming nowhere below the surface and
  floating with the eye `*float-eye*` over it. Pushing forward into a ledge at the surface no
  more than `*climb-out-height*` over the water climbs out (`climb-out`). `breath`
  (`*breath-time*`, 20 s) runs down while the eye is under water and comes back at
  `*breath-refill*`; with none left the player drowns, `*drown-damage*` a second
  (`update-breath`, through `burn-due`).
- `src/level.lisp`: `build-level`, which builds the level `*level*` names (`:test`, `:gallery`
  or `:generated`), then links rooms and builds the nav grid; and the greybox test level
  (`build-test-level`). A new room or doorway in it needs its `add-room` / `add-portal`, or
  torches light through its walls. Its corridor ends in the `shrine` block, and the `pool`
  (deep water, liquids.lisp) hangs off the shrine's west doorway, `attach-block` by its
  `connector_east` facing `:east`, the two doorways sharing one portal (`drop-portal`) and the
  pool's others plugged. Its hall is empty of monsters unless `*debug-hall-monsters*` is on (then one of each,
  `debug-spawn`, and a second imp beside the first, spawned after the ogre so the others keep their
  places in `*creatures*`: a pack), and has along its south wall one of each pickup and a pile of 60 arcane dust;
  `*debug-level-monsters*` (a list of kinds, NIL for all) keeps only those in the hall and leaves out
  the annex's imp, the blocks' monsters and the boss.
  A doorway in the middle of that wall leads down a 12 m corridor to the `arena` (`build-boss-wing`)
  and a boss of a random kind with random powers, a new one at every build (`tools/hd reset`);
  `*boss-override*` fixes them. To try a block with one kind only,
  bind `*spawn-override*` (blocks.lisp) around its `attach-block`. The debug `ice-rink` block
  (an ice field, a raised ice step, a stone strip, a dry pit to slide into, an imp and a
  knight on the ice; no tags, so never generated) is retired for now, the pool in its place;
  `(kit-goto "ice-rink")` in the gallery still reaches it. A doorway
  also needs floor under its wall's thickness: without it the nav grid has no cell there,
  and no creature can path through it (the player just steps over the gap), and
  `check-reachable` warns.
- `src/main.lisp`: `main`, `setup-scene`, `status`, `launch`, `dev-launch`.
- `src/dist.lisp`: the standalone build's entry point (`dist-main`) and its Deploy hooks; see
  "Standalone build" above.

Units are metres, +Y is up, and the player spawns at `*spawn-point*` facing −Z
(north). Collision is axis-aligned boxes in `*solids*`, resolved one axis at a time, and
wedges: a solid with a 7th value is a box with one vertical corner cut away along the
diagonal between the corners beside it (`make-solid`'s `cut`: 1 north-east, 2 north-west,
3 south-west, 4 south-east; `corner-cut`), a 45° wall when the box is square. Every
question about solids goes through greybox.lisp: `solid-overlapping` (an upright box),
`solid-at` (a point, gore.lisp), `solid-covers-p` (heights over a point); all of them
apply the diagonal (`%wedge-depth`). Moving into a diagonal stops flush against it
(`solid-flush`) and turns the stopped part of the move along the wall (`slide-along`;
the player's `move-flat`, `move-creature`), so walking straight at a 45° wall slides along
it as in Doom. Once a level is built, `index-solids` files every solid under the 4 m
columns it reaches into, and a question looks only in the columns it touches
(`do-solids-near`): a body question takes about 0.2 µs and a 10 m `clear-path-p` 0.07 ms on
seed 11, against 75 µs and 5 ms when they walked all 586 solids with untyped arithmetic.
When `*solids*` isn't the vector indexed (the nav grid binds it to the solids near a tile)
or has grown since (a box added from the REPL), they walk it whole, typed.
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
(`*nav-cell*`), measured a tile of `*nav-tile*` cells at a time against only the solids
near it, and records for each its floor height, headroom and clearance (the widest
body that fits, to 0.125 m, up to 2 m; solids less than 0.45 m above the floor don't count,
so steps aren't walls, nor more than 2 m above it, `*nav-clearance-height*`). A body taller
than that (the ogre) asks a second clearance instead, `tall-clearance`, measured from
`*nav-tall-lift*` (0.9 m) up to `*nav-tall-height*` (2.7 m), and must have a `step-height` of
0.9: a body 1 m out from its centre on a stair reaches over the next two steps, 0.83 m up,
so with the usual 0.45 a stair was a wall to it. Measuring everyone's clearance to 2.7 m
instead let the lintel of every 2.5 m `narrow` doorway close the cells in front of it to the
player. A creature fits a cell when clearance ≥ its `body-radius` and
headroom ≥ its `sprite-height`, and moves to a neighbour when the floors differ by at most
its `step-height`, so one grid serves every size. The grid is layered: each 0.5 m column
keeps every floor with room above it, lowest first (a room and the room above it, or a
hall and its roof), so a cell is `i j k`, and stairs join the layers because neighbouring
floors are a step apart. Deep water's surface is a floor too, a step below the ledge round
it, and each cell's `nav-water` says whether it is such a surface (1) or a floor under deep
water (2): walkers' paths keep out of both, a flyer's (`:ignore`) go over the surface, and
`*nav-hazards*` `:swim` (the player's reachability) goes through both and dives from a
surface to the bottom under it (`nav-dives`). `show-nav` tints surface cells teal. A point
is in the layer under it, the highest floor at most
`*nav-layer-above*` above its feet (`nav-layer`, `nav-floor-at x y z`), so anything that
asks about a place passes its height too. A straight walk (`nav-line-clear-p`) must also end
on the floor its target is on, not the one above or below. The geometry questions
go through `floor-candidates`, `ceiling-above` and `fits-at-p`, which ask the solid questions
above, so wedges' diagonals shape the grid like any wall. The test level's annex, east of the hall through its east doorway, is a lower room
with an upper room right on top of it and a stair shaft joining them; an imp lives upstairs.

A creature wanders: it stands for `*wander-pause*` seconds, then `nav-reachable-spot` picks
a random cell it can walk to within `wander-radius` of its home (or of itself, if knocked
too far away), and it follows the smoothed path at `walk-speed`, facing the way it goes.
`settle` eases it onto the floor under it. A hit stops it for `*hurt-pause*`, then it plans
afresh. It slides along any body in its way (`move-creature`, which also moves knockback);
stopped dead by another creature's body (`body-ahead`), it steps round it for
`*sidestep-time*`, mostly across the way it walked (`*sidestep-across*`), on the side away
from the other's centre, and the other side if that one is shut too (`walk-path`); blocked
for `*stuck-time*`, it gives up the path and plans another after `*stuck-pause*`.
The nav grid ignores bodies, so a wanderer's paths run through them. A hunter's don't run
through bodies that stand still: while it plans (`chase-path`, `flank`) it binds
`*nav-bodies*` (nav.lisp) to `standing-bodies`, the player and every other live creature not
walking, within `*body-avoid-range*` and level with it, but not one it already touches. Each
is a disc of the two bodies' radii that shuts the cells whose centre it covers
(`nav-layer-near`) and every point of a straight walk (`nav-line-clear-p`, which ignores one
its start or end lies in, so it may walk out of one or up to the player).
`*nav-body-mask*` (`nav-body-mask`) stamps the columns the discs may shut into a small
bit array when the plan starts, so the search asks the bodies only there: a flood over
25 m of the test hall takes 7 ms with or without them (10.8 ms with them and no mask). Walking bodies don't count, since they have
moved by the next replan; a hunter that walks into a body that stopped after its plan
replans at once, round it, instead of stepping round it (`walk-path`). With bodies in
the way and no way round, it finds no path and waits its turn: five imps down the test
level's 3 m corridor, two attack side by side and three stand 2 to 3.5 m back. Over three
runs of five imps hunting a strafing player, contacts between imps fell from about 45 to
11.

A creature with `attack-damage` also hunts (`think`). It notices the player in front of it
within `*sight-range*` with nothing solid between them, or anywhere within `*hearing-range*`,
and whenever it's hit; it stays alert for `*alert-time*` after the last time. While alert it
runs at `chase-speed`, straight at the player when the nav grid allows a straight walk, else
along `nav-path-to`, replanned every `*chase-replan*`, as long as the walk is at most
`*chase-max-walk*` (25 m: a room overhead is a long way round by the stairs). Within
`*slot-range*` (6 m) a melee hunter makes for its `attack-slot` instead of the player, so
a pack surrounds the player rather than queuing behind its leader. It claims a direction
round the player (`slot-yaw`, kept while it hunts in range, so a hunter shoved out of reach
steps back to the same spot): the free one nearest the way it comes from, looking a quarter
of `*slot-spacing*` (0.8 rad, two imps side by side) at a time either side
(`nearest-open-spot`), at least that far from every other claim and from every hunter
already standing within its reach of the player. A spot is open when its body fits on the floor there, a step from
the player's height and not in lava, with no wall between it and the player (`open-spot-p`;
not a walk from the player's feet, which against a wall it doesn't fit). Starting an attack
moves its claim to where it stands, unless that crowds another's claim. It yields its claim to
a nearer hunter that claimed close to it or one standing on it, and gives up (`ban-slot`, off it for `*slot-ban-time*`) one it has no path to (the player and
the standing pack are in the way of its path) and one it got stuck on the way to. With no spot free (the player's back to a wall leaves two or three)
it waits: within `*slot-wait-radius*` (2.5 m) plus 1.5 it stands, from further off it comes
in to that radius and from a metre inside it backs out to it, clear of the others waiting. A path search
costs a few milliseconds in an open hall, so keep the limit no longer than levels need. Within `*attack-start-reach*` of its
`attack-reach` it stops and attacks: the frames run on `attack-frame-times` (it turns to
follow the player through the first), and on `attack-hit-frame` the blow lands if the player
is still within `attack-reach`, inside `attack-arc` and not behind a wall (`hurt-player`:
damage, a shove, the pain flash, hit-stop). Until the blow lands it lunges: steps in along
its facing at `lunge-speed` (imp 3.5 m/s, skeleton and knight 3, ogre 2.5; not a boss's power)
until within `*lunge-stop*` of its reach, so backing off at a walk doesn't escape it; running
back does, and so does a sidestep from a slow turner once its facing is set (the imp turns at
once, so it follows a sidestep through its wind-up). A hit breaks the attack off. Then it stands `attack-pause` and hunts on.

A creature that `flanks` (the imp, the skeleton) doesn't attack into a raised shield: within
`*flank-range*` and in front of it (`shield-facing-p`, the shield's arc plus `*flank-margin*`)
it walks an arc round the player (`flank`, `*flank-steps*` points) to just past the arc, on
the side it is on, or the other if another creature already makes for that spot (with both
taken it doesn't flank), and attacks from there. While `flanking` it neither attacks nor
replans; the flank ends as soon as the shield no longer faces it (lowered, or got past). After one flank it waits
`*flank-cooldown*` before the next, so a player who keeps turning to face it takes the blow
on the shield.

A caster (a creature with `attack-spell`, the acolyte) hunts from range instead
(`hunt-from-range`): within `attack-range` and with a clear line to the player it stops and
casts, turning to follow the player until `attack-hit-frame`, when the spell leaves aimed at
where the player stands then (no leading, so a sidestep dodges it), from `cast-offset` to the
right of its centre line, where the casting hand is. Closer than `keep-away` it backs off
`*retreat-step*` metres along a straight walk the nav grid allows (`retreat`), and casts
point-blank when cornered; out of range or sight it closes in as a melee creature does. At zero health the player dies on a generated level (the death screen, see `src/menu.lisp`), and elsewhere the run starts over (`reset-run`).

### Flyers

A `flyer` (flyer.lisp; the harpy) plans on the same nav grid from the floor under it
(`ground-point`, which every planner uses), but hovers `hover-height` (2 m) above that floor,
bobbing, and lower where the ceiling is: `nav-room-around` gives the lowest ceiling within
`*hover-look-ahead*` (1.25 m), so it ducks under a lintel before reaching it. Its `step-height`
(1.3 m for the harpy) only decides where it paths; moving, it ignores no ledges
(`move-lift` 0.05), since low solids pass under it. In a 4 m hall the hovering harpy's talons
are above the player's 1.8 m, out of the sword's reach (`swing-target` needs the body level
with the player's); in the 3 m corridor it flies at 1.1 m, in reach. Bolts reach it anywhere.

It hunts as a caster does (`ranged-p`, `hunt-from-range`: back off within `keep-away`, attack
within `attack-range` with a clear line), but its attack is a dive (`attack-step`): it hangs
and rises `dive-rise` for `dive-windup` (0.5 s, the warning), then flies a straight line at
`dive-speed` toward the player's head (`strike-height` above the feet) as it was when the dive
left, `dive-overshoot` beyond, skimming the floor. The talons strike once, `attack-damage`, if
the player comes within `attack-reach`; a sidestep makes it miss. It then stands
`attack-pause`, climbing back at `climb-speed`, low enough for a swing. A hit during the dive
itself always downs it, whatever the pain roll (`always-pained-p`; `downed`): it falls, lies on the floor for `*downed-time*` and climbs back
before it hunts again. Dead, it falls under `*flyer-gravity*`.

It flaps (`flap-animation`, four frames per view) one beat per bob, the bottom of the stroke
where the bob is highest, and shows `dive-animation`'s wind-up frame, then its dive frame,
through the attack (`show-own-pose`, the hook `update-creature-look` asks after the flinch,
block and attack). Downed, it plays `downed-animation`, front view only like a death
(`show-front-frame`), timed by `downed-frame`: tumbling while it falls, the crash for
`*crash-time*` on landing, sprawled, stirring (head up) from `*stir-time*` before it gets up,
pushing up on its wings from `*push-time*`, and launching for `*launch-time*` as it leaves the
floor. To look at one, under hit-stop set `(downed harpy)` and `(landed harpy)` (or
`(launching harpy)`) on a harpy at the floor. It dies the same way, through the same hook
(`update-creature-look` asks `show-own-pose` before its collapse): tumbling as it falls, the
crash as it lands, then sprawled, head down, as the corpse (`dead-frame`, `landed-dead`). Hit
in the air it plays its `hurt-animation` like any creature (jolt, then stagger); hit while it
lies downed or launches it keeps its knockdown frame, squashed (`flinch-p`, which
`creature-hurting-p` asks).

### The necromancer

The `necromancer` (necromancer.lisp) hunts from range as the acolyte does, backing off within
`keep-away` (5 m), but it has three abilities, and its `hunt-from-range` picks one, in order:

- **Raise** (cooldown 7 s): the nearest corpse within `*raise-range*` it can see that is
  `raisable-p` (dead past its `death-duration`, not gibbed, with `gibs`; so not the acolyte,
  which burns). It turns to the corpse and channels for 2 s (the cast's held frame), the
  corpse twitching (`stirring`) under a growing green lamp; a hit that pains it breaks the
  channel, and it tries again later. Released, it tears the corpse apart (`tear-apart`, the gibs as a blow
  would) and stands a `skeleton-warrior` up out of it (`spawn-raised-skeleton`): `summoned`,
  `rising` for its death strip played backwards (`show-rising`, no thinking meanwhile), then
  alert. There's no cap on how many: kill them fast or go for the necromancer. A skeleton cut
  down leaves a pile of bones that can be raised again; one shattered (gibbed, which its low
  `gib-overkill` makes likely) is gone, so the supply is finite.
- **Grave circle** (cooldown 14 s): the player within `*nova-range*` and in sight. A short
  cast, then `grave-spikes` is drawn on the floor under the player as they stand at release
  (spells.lisp). It strikes 2.5 s later whatever happens to the necromancer, for 14 to 22 and a
  shove away from its centre (back from where they face, if they never moved), and no shield
  stops it, so it makes the player move; and it hurts the necromancer's own living allies.
- **Grave skull**, otherwise: homing, 6 m/s, turning 1 rad/s.

Its cooldowns run in its tick (`cooldowns`, by name), from when an ability takes effect. Its
spells spare the undead (`spares-p`, `undead`). `reset-run` takes summoned creatures out of
`*creatures*` instead of reviving them, and the test level's revival skips them. On the
test level the necromancer stands at the back of the hall, behind the imp; set
`(setf *revive-time* nil)` so corpses stay down for it, kill the imp with
`(hurt (aref *creatures* 0) 30)` (no overkill: a corpse, not gibs) and set it hunting with
`(setf (alert necromancer) 30.0)`.

### The imp

The `imp` (imp.lisp) is the monster met most (`*spawn-pool*` weight 3), small, quick and craven.
Every trick has a tell and an answer. `skittish-p` is NIL for an imp boss, which keeps only the
pounce.

- **Pounce** (`special-attack`, `start-pounce`): from `*pounce-min*` to `*pounce-max*` (3 to 7 m) it
  crouches `*pounce-windup*` (0.45 s, attack frame 0) and leaps, the leaper's arc with the imp's
  numbers (0.7 m up under `*pounce-gravity*` 22: 0.5 s for 5 m), every `*pounce-cooldown*` (5 s).
  Coming within `*pounce-reach*` of the player in the air it claws (`pounce-strike`, from its
  `keep-height :after`: `*pounce-damage-scale*` of its claw) and bounces off. The raised shield takes
  the claw and throws it down (`knocked`, then `downed` for `*imp-downed-time*`, the flinch's stagger
  frame pressed flat), and so does any blow that lands while it flies (`knock-down`, from
  `react-to-hit`). A bash in the crouch interrupts it like any wind-up. `hurt-player` returns
  whether the shield took the blow.
- **Hit and run** (`release-attack`): after every claw it springs back `*imp-spring-speed*`
  (6 m/s, about 1.3 m) on its `momentum`, `*imp-spring-angle*` to one side, and gives up its spot
  (`ban-slot`), so it comes in again from elsewhere. Its `attack-pause` is 0.35 s.
- **Morale** (`courage`, `test-courage`, from `react-to-hit` and a packmate's `creature-died`): its
  share of health plus `*imp-pack-courage*` (0.3) a live imp within `*imp-pack-radius*` (8 m).
  Below `*imp-break-courage*` (0.5), once a life (`shrieked`), it stands `*shriek-time*` throbbing
  pale (attack frame 1), then `raise-alarm`: every creature that fights within `*shriek-range*`
  (15 m) on its storey hunts for `*shriek-alert-time*`. It then runs (`fleeing`, `*imp-flee-time*`, at
  `*imp-flee-speed*` its chase speed): `flee-path` floods `*flee-walk*` for the cell furthest from
  the player along a walk that comes no nearer them, else a `retreat` step; past
  `*flee-safe-distance*` it stands and watches. With nowhere to go it fights (`cornered`). A lone
  imp breaks below half health; one with a packmate below a fifth, or when the mate dies.
- **Thief**: a claw that lands unblocked, with `*imp-steal-chance*` (35 percent, on
  `*roll-random*`), takes one potion (`steal-item`, inventory.lisp: of the quickslot's kind first) and the view
  flashes `*stolen-flash-color*`; a wandering imp goes for a pickup of `*stealable-kinds*` (herbs, shards, potions) within `*thief-sniff-range*`
  (`wander`, `seek-loot`, `reach-loot`) and takes it (`taken`), but only with the player within
  `*thief-witness-range*` (15 m) on its storey: left to wander unseen, 13 of a level's imps had
  carried off its pickups in three minutes. `stolen` is the pickup kind it
  carries, shown over its head by a `carried-loot` (pickups.lisp, `*loot-scale*`). Carrying, it
  holds back (`holds-back-p`, which `think` asks before striking) and runs from a player within
  `*thief-keep-away*`, fighting only when cornered. Dead (`creature-died`, from `hurt` and `burn`), it
  drops it as a new pickup (`drop-loot`), past `*built-pickups*`; `reset-run` takes those away
  (`restore-pickups`) and a save keeps them (`:drops`).
- **Packs**: `place-block` notes each imp it spawns in `*pack-leaders*`, and `spread-packs`, in
  `build-level` after the nav grid, gives `*imp-pack-chance*` (0.6) of them one more imp, or two
  (`*imp-pack-three*`), `*pack-spacing*` to their sides (`pack-spot`), drawn from the level's seed by
  a state of its own, so layouts and saves stay put.

To try it on the test level (with `*debug-hall-monsters*` on, the hall imp is `(aref *creatures* 0)`, its packmate `(aref *creatures* 8)`): stand 5 m
off and `(setf (alert imp) 10.0 (idle-timer imp) 0.0)` for a pounce (`*leap-debug*` logs it), with
`(setf (block-held *player*) t)` to see it thrown down; `(hurt imp 18)` on a lone one for the
shriek and flight; `(setf *imp-steal-chance* 100)` and `(give-item *player* :health-potion)` for a
theft. `tools/hd status` shows each imp's brain.

### The ogre

The leap belongs to the `leaper` mixin (its slots, `keep-height`, `attack-step`, `show-own-pose`,
`try-leap`), so a knight boss leaps too, and the imp pounces with it; a leaper with no
`leap-animation` poses with the first three frames of its attack strip. Its limits and timing are
generics whose defaults are the ogre's parameters (`leap-min-distance`, `leap-max-distance`,
`leap-max-rise`, `leap-max-drop`, `leap-rise`, `leap-min-rise`, `leap-max-speed`, `leap-gravity`,
`leap-windup`, `leap-recover-time`, `leap-cooldown-time`), and what a landing does is `leap-landed`
(the ogre's quake by default). `*leap-debug*` logs every leaper, by class.

The `ogre` (ogre.lisp) is the big one: 2.7 m tall, a body 1 m out from its centre, 120
health, slow, barely moved by knockback (0.15). It fits the 3 m doorways, corridors and
stairs, not `narrow` doorways, 2 m stair shafts or the narrow passages of caves, so it is the
creature that can't follow the player everywhere; with no path it stands facing the player
and tries again (`chase`'s fallback). Nor can it climb the kit's `stair`: one tread up from
the 3 m doorway at its foot, its head is above that doorway's 3 m ceiling, which its 1 m
reach still overlaps. The high quarter's stairs are made for it (see "Blueprints"). Two attacks:

- **Leap** (`special-attack`, which `hunt` asks before anything else; cooldown
  `*leap-cooldown*`, 6 s): with the player 4 to 12 m away across, at most 2.5 m up or 6 m down
  and in sight, `plan-leap` takes the cell under the player its body fits
  (`nav-nearest-fitting`) and an arc to it under `*leap-gravity*`, its top `*leap-apex*` (2 m)
  over the higher end, lowered under the lowest ceiling along the way, and refused under
  `*leap-min-apex*` or faster than `*leap-max-speed*`; then it sweeps its body along the arc
  (`arc-clear-p`), so a leap never passes through a wall or ceiling. In a 4 m room its feet
  rise 1.2 m; in a 3 m corridor it can't leap. It crouches for `*leap-windup*` (the warning),
  then flies (`fly-leap`, from its `keep-height`, which runs every tick, so a hit can't leave
  it hanging), aimed at where the player stood. A wall or body in its way (the player's)
  cuts it short, and it drops (`drop-ogre`). Landing (`land-leap`) it `quake`s: everything
  with its feet within `*quake-reach-height*` (0.4 m) of that floor and within
  `*quake-radius*` (3.5 m), the player and its own allies alike, takes `*quake-damage*` and is
  thrown away, full against its body and nothing at the rim; the player is thrown up as
  well (`*quake-player-lift*`), since a shove on the ground dies in a tenth of a second.
  Jumping as it lands dodges it all; the shield doesn't (`:unblockable`). It stands
  `*leap-recover*` (1.2 s) after.
- **Slam** up close: the timed blow, and a hit throws the player back and up (blocked, it
  knocks the shield aside for its `guard-break`)
  (`hurt-player`'s `:shove` speed and `:lift`; `shove-player` does it without damage). The
  maul's impact, `*slam-impact*` in front, shoves everything within `*slam-quake-radius*`
  (no damage), so a near miss still shoves the player.

It sees `sight-rise` (6.5 m) up and down, not 3. `*leap-debug*` logs every leap, every refusal
and why, and what each shockwave hits. On the test level it stands in the hall's east, by
the annex doorway (it fits the lower room, not the stair shaft). Generated levels have it
from level 2 on (level 1's pool has none, which keeps out the high quarter too: see `:pool` under
"A run"), from `any`, the `hall`'s choice and the high quarter's own spawns; the `cavern`, `balcony`,
`ice-cavern` and `ice-grotto` spawn `any-ogre`, since one there couldn't reach its own
doorways (`check-kit` with `*spawn-pool*` set to only ogres checks every block for it).
Each block fits it, but the way to the start may not (a `stair`, a cave passage, a `narrow`
doorway, the far bank of a river): one stranded there guards its part of the level, and
`check-reachable` warns. It guards a hoard too (`place-hoards`, loot.lisp): `build-level` passes
`check-reachable`'s stranded ogres (`hoard-guard-p`: elites too, not bosses or the summoned) to
`place-pickups`, which, last of all the pickups so the others keep their places in `*pickups*`, lays
a found item that is never plain (an enchanted sword or spear, or a generated rune;
`make-hoard-loot`) and a pile of `*hoard-gold*` coins on the floor `*hoard-behind*` (1.5 m) behind
its spawn point, by its facing then, `*hoard-spread*` apart (`hoard-points`: nearer or turned toward
its side where a wall is in the way, never in front, on the spawn point at last; floor the player
fits on and can get to). Its 2 m wander keeps it by the hoard. Each hoard logs a line ("OGRE at ...
guards a sword: Shock Edge and 104 gold."). Over run seeds 1 to 8 on the last level, 8 hoards. Over seeds 1 to 30 at each of a run's three depths, 109 of 347 ogres
were stranded, and no other creature.
`*ogre-dust*` names the effect animation puffed round a landing and the slam's impact
(`ogre-dust`, preloaded by `setup-scene`; NIL for none).

`tools/hd '(game (show-nav))'` lays green tiles on the cells within 8 m of the player that
an imp-sized body fits; `(show-nav :radius 1.0 :height 2.5)` shows a bigger one, and
`(hide-nav)` or a reset clears them; `(show-nav :radius 1.0 :height 2.7)` shows the ogre's. `tools/hd status` shows each creature's `brain`
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

## Level textures

Level faces are textured in world space: the greybox shader lays a texture flat on each
face (floors and ceilings by x and z, walls by the distance along the wall and y, which on
an X wall is z and on a Z wall x, and on a 45° wall its diagonal; `face_texel`). The wall's
direction is snapped to the nearest 45°: the face normal comes from screen-space derivatives,
and its slight noise times a world position 100 m out scattered a diagonal's texture by texels
from pixel to pixel. A wall at any other angle would need that snap changed. Textures are laid at `*texels-per-metre*` (64, the monsters' density). A texture's
pixel size is the ground it covers (256 px, 4 m), its rows start at y = 0, and walls line up
across boxes and blocks without UVs. A **surface** (`*surfaces*`) is three textures: the
sides, the top and the underside, as floors and ceilings are flats in Doom; `add-box` takes
`:surface :wall` (or `:floor`, `:ceiling`, `:pillar`, `:platform`, `:dais`, `:stair`, `:stone`,
`:beam`, `:sarcophagus`, `:rock`, `:cave-floor`, `:ice`, `:ice-rock`, `:snow`, `:descent-arch`), tinted by
`:color` (white by default). A box without one is flat colour with the 1 m grid, as before.

A texture is one `define-asset` image in greybox.lisp (nearest filtering, repeat wrapping)
from `data/textures/<name>.png`. It starts as a generated square:
`art/prompts/texture-common.txt` (seamless, flat-on, flat lighting) plus
`texture-<name>.txt`, the imp's turnaround as the style reference, a few candidates each,
one at a time (parallel runs hit "model at capacity"):

```bash
tools/gen_image.py art/textures/wall-stone.png --prompt "$(cat art/prompts/texture-common.txt art/prompts/texture-wall-stone.txt)" --ref "Pixel Demon Character Turnaround.png" --size 1024x1024 -n 2
```

`tools/make_texture.py` crops it square, box-filters it to `--metres` × 64 px, flattens it
to one palette (`--colors`, 32) and writes a 3 × 3 tiled preview beside the source to check
the seams. The generator's 1254 px squares have art pixels about 5 px wide, so 4 m
(256 px) keeps their detail; a small-patterned one (pillar blocks, planks) is 2 m. Asked
for seamless, they mostly tile; `--blend PX` cross-fades the edges when they don't, but
ghosts joints, so a fresh image is often better.

```bash
tools/make_texture.py art/textures/floor-flags-2.png data/textures/floor-flags --metres 4
tools/make_texture.py art/textures/ceiling-1.png data/textures/ceiling-stone --metres 4
tools/make_texture.py art/textures/pillar-stone-1.png data/textures/pillar-stone --metres 2
tools/make_texture.py art/textures/platform-top-1.png data/textures/planks --metres 2
tools/make_texture.py art/textures/stair-side-2.png data/textures/stair-side --metres 2
tools/make_texture.py art/textures/stair-tread-1.png data/textures/stair-tread --metres 2
tools/make_texture.py art/textures/stone-2.png data/textures/dressed-stone --metres 2 --brightness 0.78
tools/make_texture.py art/textures/beam-2.png data/textures/timber --metres 2
tools/make_texture.py art/textures/sarcophagus-side-3.png data/textures/sarcophagus-side --metres 2 --strip 0.8 --brightness 0.78
tools/make_texture.py art/textures/sarcophagus-lid-1.png data/textures/sarcophagus-lid --metres 2 --brightness 0.78
tools/make_texture.py art/textures/rock-1.png data/textures/rock --metres 4
tools/make_texture.py art/textures/cave-floor-2.png data/textures/cave-floor --metres 4
```

The `ice` surface (`data/textures/ice.png`, dark clear ice with white crack planes; its sides
too, stone under it) is the common prompt plus `art/prompts/texture-ice.txt` (ice only, nothing
showing through) plus a look: `texture-ice-dark.txt`, the one used, `-frosted` or `-glacier`.
`ice-1` and `ice-2` are an earlier ice-over-flagstones version, dropped.
`tools/make_texture.py art/textures/ice-dark-2.png data/textures/ice --metres 4`.
The ice caves' walls are `ice-rock` (faceted glacier ice with dark rock locked in it,
`texture-ice-rock.txt`) and their floor `snow` (trodden snow and hoarfrost with rock showing
through, `texture-snow.txt`, snow on its sides too); both took the floor ice, `ice-dark-2.png`,
as a second reference for the palette:

```bash
tools/make_texture.py art/textures/ice-rock-3.png data/textures/ice-rock --metres 4
tools/make_texture.py art/textures/snow-1.png data/textures/snow --metres 4
```

The caves' `rock` is fractured bedrock with no courses, for their walls and ceilings;
`cave-floor` is bedrock, pebbles and packed earth, under rock sides.

The stair's treads (`stair-tread`) are a straight 4 × 4 grid of slabs on 2 m, so their joints
fall on the 0.5 m treads the stair pieces have; its risers and flanks are `stair-side`, small
courses that don't need to meet the risers. `stone` is one plain dressed face, no courses,
`--brightness 0.78` so the pale stone doesn't glare in the dark.

A face made for one size of box is a **strip**: `sarcophagus` (the crypt's, 0.8 m tall) has
a side that is plinth, four carved panels and the lid's edge, generated alone as a 2.5:1
band on magenta (`texture-sarcophagus-side.txt`, not `texture-common.txt`, with
`art/textures/stone-2.png` as a second reference for the stone). `--strip 0.8` crops the
band and stands it on the bottom of a 1 m texture (PNG rows run top down, from y = 1 m to
y = 0). The 1 m repeat divides the 5 m storeys, so it fits a box standing on any storey's
floor, and the 0.5 m panels meet a box's ends, which always lie on the 0.5 m grid. The lid
is 4 × 4 coffers on 2 m, so 0.5 m too.

A face can also be a **panel**, one picture on a wall: `descent-arch`, the way on at the bottom of
the `descent` block (a blueprint's `wall descent-arch`), a stone arch with its stair falling away
into black, as in the loading splash. It is generated alone on magenta
(`art/prompts/descent-door.txt`, the splash and `wall-stone-1` as references), and `--panel` scales
it to 2.8 m wide and stands it on `wall-stone` in a texture 4 × 5 m. So it only fits a wall one
storey tall, standing on a floor, across a whole cell (it is centred where the cell's middle
falls, x or z of 2 mod 4): 5 m is the storey, so it stays put on any storey, and the cell keeps it centred
whichever way the block is turned. It is a picture: there is nothing behind it.

```bash
tools/gen_image.py art/descent/door.png --prompt-file art/prompts/descent-door.txt --ref art/splash/loading-2.png --ref art/textures/wall-stone-1.png --size 1024x1024 -n 3
tools/make_texture.py art/descent/door-1.png data/textures/descent-arch --metres 4 --panel 2.8 --on data/textures/wall-stone.png --period 5 --colors 48
```

`beam` (`timber`) has its grain running along x: a beam turned to run along z shows the
grain across its underside.

A re-made PNG is picked up by reloading greybox.lisp (`tools/hd reload src/greybox.lisp`),
not by `tools/hd reset`.

## Sound and music

Sounds and music are generated with ElevenLabs (a paid plan: the free one refuses music), the
key in `~/.config/elevenlabs/api_key`. `tools/gen_sfx.py` makes sound effects (0.5 to 30 s,
about 10 credits a second) and `tools/gen_music.py` instrumental tracks (10 to 300 s, about 12 a
second), each writing a `.prompt.json` beside its output like `gen_image.py`. Both save `.wav`
(the API's PCM is stereo) or `.mp3`. Sources and prompts live under `audio/` (`audio/prompts/`,
`audio/sfx/`, `audio/music/`), as `art/` holds the pictures; what the game plays goes in `data/`.

`audio/sfx.md` lists every sound effect the game needs: the moment, the code where it starts,
its clip (prompt `audio/prompts/sfx-<clip>.txt`, ending in a shared style line), duration, takes,
whether it loops and whether it is positional (a mono file on the `:effect` space mixer) or
first-person. Work from it and keep it current.

Sound effects: each clip's takes are `audio/sfx/<clip>-<n>.wav` (`tools/gen_sfx.py`, with the
duration, takes and `--loop` from `audio/sfx.md`), gitignored like the music's. The chosen take
of each goes in `audio/sfx-picks.txt` (`imp-pain 2`; several takes are variants played in
turn, `gain=-3` evens one out, `even` flattens a loop that swells and fades within itself,
`lowcut=120` rolls off the sub-bass of a heavy thud before leveling, which otherwise counts it and
leaves the part speakers play tiny; take 1 without a line), and `tools/make_sfx.py [CLIP...]` trims,
levels (the loudest 100 ms at -14 dBFS RMS, peaks under -1 through make_loop.py's limiter),
downmixes positional clips to mono (the `:effect` space mixer takes only mono) and encodes them
to `data/sfx/<clip>.ogg` (`<clip>-1.ogg` ... for variants), listing them in
`data/sfx/index.lisp`. Then `tools/hd '(reload-sounds)'` and `tools/hd reset`. Generated takes
often clip: pick one that doesn't. To try a clip again, rewrite its prompt and `gen_sfx.py ... --add`,
which numbers the new takes on from the last (`<clip>-4.wav`, recorded in `<clip>-4.prompt.json`)
and keeps the old ones; `--influence 0.5` keeps closer to the prompt than the default 0.3. A take
borrowed from another clip is a copy under the next number with a `.prompt.json` saying where it
came from (`cinder-flight-3.wav` is `bolt-flight-2.wav`). A clip taken out of `audio/sfx.md`
leaves the index and `data/sfx/` at the next `make_sfx.py`.

The picker does all that from a page, with the game running: `tools/sfx_picker.py` (or the
`sfx-picker` config in `.claude/launch.json`) serves http://127.0.0.1:8765/, every clip of
`audio/sfx.md` with its takes to hear in the browser (marked when they clip or are quiet).
**Use** on a take, **+**/**−** for variants or the gain buttons rewrite that clip's line in
`audio/sfx-picks.txt`, run `make_sfx.py` on it and have the game swap it in at once
(`reload-sound`, which frees the clip's old voices in the mixing thread and makes new ones,
no reset) and play it 3 m in front of the player (`audition-sound`; a loop for 2 s, even with the
game paused). **▶ In game** converts and loads a clip the game doesn't have yet. Switch as
often as you like. It talks to the game `tools/hd` would (`.eval-port`). Its Ogg files differ
byte for byte each run (Vorbis stream serials), the sound not.

Each track is `audio/music/<name>.wav`, generated from `audio/prompts/music-<name>.txt`: three
minutes for exploration, two for combat. A prompt ends asking for one even texture with no intro
or ending (`music-explore-1` is `music-explore-loop.txt`), which keeps the loop easy to find, and
all share the 1990s General MIDI wavetable style line. `tools/make_loop.py` cuts the loop (its
docstring says how it finds the join): the two ends match in harmony and sound, the first 4 s
crossfaded from what follows the end, so the loop's end runs on into its start. It writes
`<name>-loop.wav` beside the source and, through GStreamer (no ffmpeg or sox here), Ogg Vorbis
into `data/music/`, about a tenth of the size, checking that the Ogg says it holds the same sample
count (`ogg_length`, its last page's granule position, which the game's decoder trims to). Decoding
it back through GStreamer is no check: its timestamps are nanoseconds, and at some lengths it
comes out a sample or two long. Loops come out at whole bars (72.0, 88.6, 60.0, 64.0 s), between 1 and
2 minutes:

```bash
tools/gen_music.py audio/music/combat-6.wav -f audio/prompts/music-combat-6.txt -l 120
tools/make_loop.py audio/music/combat-6.wav data/music/combat-6.ogg --min-loop 50 --loudness -11 --preview /tmp/join.wav
```

then a `define-asset` for it in music.lisp and its name in `*music-moods*`. `--preview` writes the
join, 8 s either side, to listen to; `--pick 2` takes the next-best join, and `--start` keeps the
loop to a later part of a track.

`--loudness` evens out what the generator made: its takes came 5 dB apart (a drum section as
loud as combat). Exploration loops are -14 LUFS, combat -11, so a fight comes in a little louder;
a gain that would clip goes through a look-ahead limiter. They were cut with: explore-1
`--min-loop 100`, explore-3 `--min-loop 90`, combat `--min-loop 50`.

What exploration wants, from listening: an instrument always playing a melody over a moving
part (explore-1's strings, harp and bell). Drones and pads with little over them (the first
explore-2 and -3, kept as `*-drone.wav`) were off-putting, and flute, lute and harp arpeggios
(`music-explore-2-pastoral.txt`) came out pastoral, a meadow rather than a crypt. Asked for
"unobtrusive", the generator gave drones; "something is always moving: no drones, no long held
notes on their own" fixed that. explore-3 is take 2 of `music-explore-3.txt` (dulcimer and
marimba ostinato, horn and clarinet, frame drum; rather jolly, kept for its curious undertone).

**Composed music.** Music can also be written out as notes: `tools/compose_explore.py` and
`tools/compose_combat.py` are pieces, each a function returning its notes plus its General MIDI
instruments, and `tools/midi_music.py` (the shared part) writes them as MIDI, renders that through
GStreamer's FluidSynth element and the TimGM6mb soundfont in `/usr/share/sounds/sf2/` (a small GM
set, the sound of a 1990s wavetable card: "this is Daggerfall"), and finishes the loop with
make_loop.py's loudness and encoding. It renders the piece twice and keeps the second pass, which
opens with the first's reverb tails, so the join needs no crossfade; the beat is chosen so the
loop is a whole number of samples and of FluidSynth's 64-sample blocks, and the two passes then
correlate at 1.0000. A dense piece clips inside FluidSynth before the limiter can act, so a piece
passes its own synth `gain` (combat 0.4, exploration 0.8) and the run warns of any clipped samples.
No credits, 17 s a render. `compose_title.py` is the main menu's: C minor at 75 BPM, 102 s, a
horn theme, a choir, the theme on brass over an organ, a solo cello, all over a harp's arpeggio.
The current explore-2 is `compose_explore.py`: D minor at 80 BPM, horn
and low clarinet over dulcimer, bass, frame drum, timpani and bell, with no C or F major (a first
version with them, and an octave higher, was right but too bright for a dungeon):

```bash
tools/compose_explore.py audio/music/explore-2 data/music/explore-2.ogg --preview /tmp/join.wav
tools/compose_combat.py audio/music/combat-5 data/music/combat-5.ogg --preview /tmp/join.wav
tools/compose_title.py audio/music/title data/music/title.ogg --preview /tmp/join.wav
```

`compose_combat.py` is combat-5, a battle piece after combat-3: E minor at 160 BPM, 64 bars, a
96 s loop, cellos grinding over contrabasses, drums, taiko and timpani on every beat, brass stabs,
a tremolo string figure, a horn theme, choir and orchestra hits, the Phrygian F major for menace;
its four sections come twice, scored anew the second time. At 120 BPM it lacked energy: combat-3,
asked for 110, plays at about 160 (a tempo estimate from onset autocorrelation finds half of it,
0.75 s), and once at 160, 32 bars (48 s) was too short.

Harmony picks a decoder by the file's extension, and quickloads its system when it isn't loaded;
the binary has no Quicklisp, so each format the game plays is a dependency in the .asd
(`cl-mixed-vorbis` for `.ogg`; a `.wav` would need `cl-mixed-wav`, not there yet). A changed `main` class or new
dependency needs a restart of `./run.sh`. In this version, `trial:seek` on a voice fails
(`mixed:seek` takes no `:by`); seek its source by frames instead. A vorbis source's
`frame-count` reads twice the real length, though it ends and loops where it should.

## Splash screens

The main menu, the loading screen, the death screen and the victory screen draw a picture over the whole window
(`splash-backdrop` in menu.lisp), cropped to cover it, with nearest filtering and a dark
veil (`*splash-dim*`, 0.6) so it stays in the background. Each is a generated 1536 × 1024 picture: `art/prompts/splash-common.txt`
(16:9 crop, no text, a calm dark centre for the menu) plus `splash-title.txt`,
`splash-loading.txt` or `splash-death.txt`. The title references the four monsters' turnarounds, the loading
screen the imp's turnaround, the stone wall and the torch, and the death screen those three
and the shield and sword (`art/sword-shield/ref-shield-a2.png`, `ref-sword-idle.png`):

```bash
P=art/prompts; tools/gen_image.py art/splash/title.png --prompt "$(cat $P/splash-common.txt $P/splash-title.txt)" --ref "Pixel Demon Character Turnaround.png" --ref art/acolyte/turnaround-2.png --ref art/knight/runic-turnaround-3.png --ref art/harpy/turnaround-2.png --size 1536x1024 -n 2
```

`tools/make_splash.py` crops it to 16:9 (`--shift` -1 keeps the top, 1 the bottom) and
box-filters it to 640 × 360, 2 screen pixels per splash pixel at 1280 × 720. It keeps every
colour by default: a 64-colour palette turned the knight's blue runes yellow.

```bash
tools/make_splash.py art/splash/title-2.png data/splash/title --shift -0.6
```

The menu pass caches the picture by path and outlives scenes, so a re-made one shows after a
restart of `./run.sh`.

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

The harpy's sheet is `art/harpy/turnaround-2.png` (`art/prompts/harpy-turnaround.txt`, the imp's,
acolyte's and knight's sheets as style references), drawn hovering with its wings raised.
Sliced at `--height 116` for its 1.8 m, wingtips to talons, with `--filter box`: averaging
keeps the yellow eyes and rust claws that nearest-neighbour speckles away (`--colors` merges
them into the browns, so leave it off). No views needed mirroring.

```bash
python3 tools/slice_turnaround.py art/harpy/turnaround-2.png data/sprites/harpy/turnaround --height 116 --filter box
```

Its dive (wind-up, then the dive) is made like the knight's animations: one sheet per view
opening with a copy of the hovering pose, `harpy-dive-common.txt` plus `harpy-view-<view>.txt`,
the turnaround and `art/harpy/stand-<view>.png` (its cells, cut from the turnaround) as
references, the side and back views adding `harpy-follow.txt` with the front,
`dive-front-2.png`, as the third; the front-quarter takes `harpy-view-front-quarter-strict.txt`
and no front instead. Its wingbeat can't be a row: at full spread the wings cross into the
next cell however small the reference draws the harpy. So `harpy-flap-common.txt` asks for a
2 x 2 grid of the four frames (top, downstroke, bottom, upstroke) with no hovering copy, the
top frame being the hovering pose, and `--grid` makes `slice_views.py` read each sheet as one
row; the other views follow `flap-front-c-1.png` with `harpy-flap-follow.txt`. The grid's two
rows are drawn apart, so each frame stands on its own lowest pixel: the bottom of the stroke,
whose wingtips hang below the talons, lifts the body a little.

```bash
python3 tools/slice_views.py data/sprites/harpy dive:10 art/harpy/dive-front-2.png art/harpy/dive-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box
python3 tools/slice_views.py data/sprites/harpy flap:20 art/harpy/flap-front-c-1.png art/harpy/flap-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --grid --pixel 8 --anchor bottom --filter box
```

Its flinch (`harpy-hurt-common.txt`, jolt then stagger) is made like the dive, the side and back
views following `hurt-front-1.png`:

```bash
python3 tools/slice_views.py data/sprites/harpy hurt:10 art/harpy/hurt-front-1.png art/harpy/hurt-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box
```

Knocked down (`harpy-downed.txt`, front only, `downed-2.png`) is a 2 x 4 grid whose first cell is
a copy of the hovering pose, to set the scale: it is 494 px tall, so `--pixel 4.26` makes it
116 px. It is sliced as an animation of its own and deleted:

```bash
python3 tools/slice_frames.py art/harpy/downed-2.png data/sprites/harpy --pixel 4.26 --anchor bottom --filter box scale:1 downed:6 && rm data/sprites/harpy/scale.*
```

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

The shield started as generated pictures of both hands from behind
(`art/prompts/sword-shield-common.txt` plus `sword-shield-idle-<a..d>.txt`, the sword's idle
frame as the reference, `art/sword-shield/idle-*.png`). Only the a-1 grip on the straps was
right; `sword-shield-merge-rim.txt` put that hand and its straps (`ref-hand-a1.png`, cut from
it) on a-2's steel-rimmed shield (`ref-shield-a2.png`) drawn bigger, `merge-1.png` giving the
size, into `art/sword-shield/merge-rim-1.png`. Every frame is that one picture moved and
scaled, so the grip is the same in all of them: `tools/extend_arm.py` lengthens its forearm
past the picture's edges along the rays from the arm's vanishing point (so a raised shield
shows no cut-off arm), and `tools/make_shield.py` places, darkens and palettes the frames
listed in `art/sword-shield/shield-frames.txt` (scale and where the fist goes on screen,
counted from the bottom-left corner) into the strip:

```bash
tools/extend_arm.py art/sword-shield/merge-rim-1.png art/sword-shield/merge-rim-1-arm.png --vanish 234,720 --edge 0,866 --edge 200,1010 --pad 600,500
tools/make_shield.py art/sword-shield/shield-frames.txt data/sprites/sword/shield
```

The picture's bottom edge cuts the shield, so no frame may lift it on screen (the frames file
says how far is safe), and the shield can't turn: the bash is a push straight out.

The spear (`art/spear/`) is one generated picture per pose, the whole 1536 × 1024 canvas
being the screen, both gauntlets on the shaft, their forearms running off the bottom edge so
the one sprite can stand against the bottom-right corner: `art/prompts/spear-common.txt` plus
`spear-<pose>.txt` (idle, drawback, thrust, extend, recover), with the sword's idle frame
(`art/sword-shield/ref-sword-idle.png`) as the reference, the other poses adding
`spear-follow.txt` and the chosen idle picture as the second. `tools/make_shield.py
--corner right` places them against the bottom-right corner, as the sword sits, from
`art/spear/spear-frames.txt` (4 idle entries, then the 8 of the thrust):

```bash
tools/gen_image.py art/spear/extend.png --prompt "$(cat art/prompts/spear-{common,extend,follow}.txt)" --ref art/sword-shield/ref-sword-idle.png --ref art/spear/idle-2.png --size 1536x1024 -n 2
tools/make_shield.py --corner right art/spear/spear-frames.txt data/sprites/spear/spear
```

Generators can't keep a motion sequence across a grid of first-person poses, and they draw
a depth move (pulling a weapon back toward the viewer) badly. Ask for one pose per image,
attach the first as the design reference, and describe each pose in screen positions.

Most of that idle row has no palm fire, so `*hands-idle-sequence*` loops the cast's rest
frames instead. A re-sliced PNG isn't picked up by `tools/hd reset` (loaded assets stay);
`tools/hd reload src/<file that defines it>.lisp` reloads it and rebuilds the scene.

A monster's walk is one strip of 4 frames per view, in the turnaround's view order. It
comes as one generated sheet per view (`art/imp/*walk*.png`, view number in the name), each
drawing the imp at its own size. `tools/slice_views.py` scales every sheet to one sprite
height, mirrors the views that face right frame by frame (here the back-quarter), stacks
them and slices the stack; `--pixel` = height / 96 makes the imp as tall as a turnaround
cell. It is `tools/stack_views.py` and `tools/slice_frames.py` in one step: the stacked sheet
(10 MB or so) stays in memory, since it rebuilds exactly from the per-view sheets, and
`.gitignore` keeps any written one (`*-sheet.png`) out of git. To look at it, run
`stack_views.py` with the same stacking options:

```bash
python3 tools/slice_views.py data/sprites/imp walk:20 "art/imp/Four-frame pixel imp walk cycle (frame 1).png" "art/imp/Four-Frame Imp Walk Cycle (frame 2).png" "art/imp/Side-Profile Imp Walk Cycle (frame 3).png" "art/imp/Rear Three-Quarter Imp Walk Cycle (frame 4).png" "art/imp/Pixel-art imp rear-view walk cycle (frame 5).png" --height 768 --mirror 4 --pixel 8 --anchor bottom --filter box
```

The creature's `walk-animation` names it. The billboard picks the view as for standing,
and the frame follows the distance walked (`stride` metres per frame), so the feet keep
pace with `walk-speed`.

The attack (a claw swipe: wind-up, lunge, strike, recover) is built the same way from
`art/imp/Red Imp Four-Frame Claw Attack (frame N).png`. The front two were made by hand;
the other three came from `tools/gen_image.py` with `art/prompts/imp-attack-common.txt`
plus the view's file, referencing the turnaround, that view's walk sheet and the two
finished attack sheets. `slice_views.py` scales by the tallest frame, here the raised
claw, which stands about 1.15 times the imp's height, so the stack is taller than the
walk's to keep the standing imp at 96 px (cells come out 110 px tall):

```bash
python3 tools/slice_views.py data/sprites/imp attack:20 "art/imp/Red Imp Four-Frame Claw Attack (frame "{1,2,3,4,5}").png" --height 880 --mirror 4 --pixel 8 --anchor bottom --filter box
```

The flinch on a hit is 2 frames per view (jolt, then stagger), played over
`*stagger-time*` instead of the old squash: `art/imp/hurt-<view>-N.png`, generated per view
with `art/prompts/imp-hurt-common.txt`, `imp-hurt-layout.txt` and `imp-hurt-<view>.txt`
(the other views add `imp-hurt-follow.txt` and reference the finished front,
`hurt-front-3.png`). The generator draws every sheet about the same height whatever
the reference's scale, so a sheet's scale can't be taken from its walk sheet; the
buckled jolt frame is about 0.83 of standing height, hence `--height 640`:

```bash
python3 tools/slice_views.py data/sprites/imp hurt:10 art/imp/hurt-front-3.png art/imp/hurt-front-quarter-2.png art/imp/hurt-side-2.png art/imp/hurt-back-quarter-2.png art/imp/hurt-back-2.png --height 640 --mirror 4 --pixel 8 --anchor bottom --filter box
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
python3 tools/slice_views.py data/sprites/acolyte cast:20 art/acolyte/cast-front-3.png art/acolyte/cast-front-quarter-1.png art/acolyte/cast-side-2.png art/acolyte/cast-back-quarter-1.png art/acolyte/cast-back-1.png --height 920 --frame 4 --mirror 4 --pixel 8 --anchor bottom --filter box
```

Its flinch is made the same way (`acolyte-hurt-common.txt`, `-follow.txt`, `-<view>.txt`,
the other views referencing `hurt-front-2.png`), but a pain pose has no frame that is the
same in every view to scale by. So each sheet opens with a copy of the standing pose:
`--frame 1` scales by it and `--blank 1` drops it before slicing:

```bash
python3 tools/slice_views.py data/sprites/acolyte hurt:10 art/acolyte/hurt-{front,front-quarter,side,back-quarter,back}-2.png --height 920 --frame 1 --blank 1 --mirror 4 --pixel 8 --anchor bottom --filter box
```

Its death (`art/prompts/acolyte-death.txt`, front only, 2 × 4 like the imp's) burns the
acolyte away and leaves its empty robe as the corpse. Frame 1, the jolted acolyte, is
407 px tall in `death-1.png`, so `--pixel 3.54` makes it 115 px:

```bash
python3 tools/slice_frames.py art/acolyte/death-1.png data/sprites/acolyte --pixel 3.54 --anchor bottom --filter box death:8
```

The knight (horned helm, blackened plate, a steel tower shield carved with glowing runes) is
`art/knight/runic-turnaround-3.png` (`art/prompts/knight-turnaround.txt`, the imp's and
acolyte's sheets as style references), sliced at `--height 125` for its 1.95 m, horns
included. The `art/knight/` files without `runic-` are an earlier crusader design, dropped.
Its views needed no mirroring. Its block (impact, then brace) exists only for the front and
front-quarter, the views its shield covers, made like the acolyte's flinch: the prompt is
`knight-block-common.txt` plus `knight-block-<view>.txt` (the quarter adds
`knight-block-follow.txt` and references `runic-block-front-2.png`), passed as
`--prompt "$(cat ...)"`, with the turnaround and `art/knight/runic-stand-<view>.png` (its
standing cells) as references. The generator turns the quarter view only a little.

```bash
python3 tools/slice_views.py data/sprites/knight block:4 art/knight/runic-block-front-2.png art/knight/runic-block-front-quarter-2.png --height 1000 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box
```

Its walk, attack (the mace over the shield, which stays up) and flinch are made the same way,
one sheet per view opening with a copy of the standing pose: `knight-<anim>-common.txt` plus
`knight-view-<view>.txt`, and for the side and back views `knight-follow.txt` with the front
sheet (`runic-<anim>-front-1.png`) as the third reference. The front-quarter can't take the
front sheet as a reference: the generator copies it and draws a front view. It is
`knight-view-front-quarter.txt` plus `knight-view-front-quarter-strict.txt` with only the
turnaround and its standing cell (`runic-<anim>-front-quarter-b-1.png`). The death
(`knight-death.txt`, front only, `runic-death-b-2.png`) kneels, topples onto its hands and
crashes down; frame 1 is 409 px tall, so `--pixel 3.27` makes it 125 px. The stacked
sheets are big: `--filter box` takes a minute or two each.

```bash
K=art/knight; for a in walk:20 attack:20 hurt:10; do n=${a%:*}; python3 tools/slice_views.py data/sprites/knight $a $K/runic-$n-front-1.png $K/runic-$n-front-quarter-b-1.png $K/runic-$n-side.png $K/runic-$n-back-quarter.png $K/runic-$n-back.png --height 1000 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
python3 tools/slice_frames.py art/knight/runic-death-b-2.png data/sprites/knight --pixel 3.27 --anchor bottom --filter box death:8
```

The necromancer (gaunt, bald, a long white beard, ragged robes in black and moss green, a
staff topped with a horned skull, green-glowing eyes) is `art/necromancer/turnaround-3.png`
(`art/prompts/necromancer-turnaround.txt`, the imp's, acolyte's, knight's and harpy's sheets
as style references), sliced at `--height 128` for its 2 m, staff included. The skeleton it
raises (yellowed bone, a leather kilt and bracer, a notched rusty sword) is
`art/skeleton/turnaround-1.png` (`skeleton-turnaround.txt`), at `--height 115` for its 1.8 m.
Both slice with `--filter box`, and neither needed mirroring. Their animations are made the
knight's way, and `tools/gen_monster_views.sh` makes one animation's views in a row (run it in
the background, front and front-quarter first, then the rest with the chosen front sheet after
`--`): `<who>-<anim>-common.txt` plus `<who>-view-<view>.txt`, `<who>-follow.txt` and
`<who>-view-front-quarter-strict.txt`, with `art/<who>/stand-<view>.png` cut from the
turnaround. The necromancer has a walk, a cast (staff raised, the free hand flaring green: the
raise and the grave circle), a thrust (the staff's skull swung forward: the grave skull) and a
flinch; the skeleton a walk, an attack (an overhead chop) and a flinch. The deaths are front
only, 2 × 4: the necromancer falls face down beside its staff, the skeleton collapses into the
pile of bones that is its corpse (and, played backwards, its rising).

```bash
tools/gen_monster_views.sh necromancer walk art/necromancer/turnaround-3.png front front-quarter
tools/gen_monster_views.sh necromancer walk art/necromancer/turnaround-3.png side back-quarter back -- art/necromancer/walk-front.png
V="front front-quarter side back-quarter back"
for a in walk:20 cast:20 thrust:20 hurt:10; do python3 tools/slice_views.py data/sprites/necromancer $a $(for v in $V; do echo art/necromancer/${a%:*}-$v.png; done) --height 1024 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
for a in walk:20 attack:20 hurt:10; do python3 tools/slice_views.py data/sprites/skeleton $a $(for v in $V; do echo art/skeleton/${a%:*}-$v.png; done) --height 920 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
python3 tools/slice_frames.py art/necromancer/death.png data/sprites/necromancer --pixel 3.72 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/skeleton/death.png data/sprites/skeleton --pixel 3.94 --anchor bottom --filter box death:8
```

The ogre (hunched, grey-green hide, tusks, iron bands and hide wrappings, a two-handed stone
maul) is `art/ogre/turnaround-2.png` (`art/prompts/ogre-turnaround.txt`, the imp's, acolyte's,
knight's and harpy's sheets as style references), sliced at `--height 173` for its 2.7 m.
Its walk, slam (wind-up overhead, swing, the maul in the floor, recover), leap (crouch, in the
air with the maul raised, landed with it driven down) and flinch are made the necromancer's
way with `tools/gen_monster_views.sh ogre <anim> ...`; the walk front, `walk-front.png`, is
`walk-front-c-1.png` with `walk-front-c-2.png`'s third cell. The death (`ogre-death.txt`)
falls face down beside the maul, and the dust (`ogre-dust.txt`) is a burst of grit standing
on the floor.

Generated frames don't keep to their cells: its maul crossed the cyan lines in many sheets,
cut off in its own frame and showing as a stray piece in the next. `tools/respace_cells.py`
fixes that, rewriting a sheet with wider cells and every piece back in its frame, each frame
keeping its centre, so run it on a new sheet before slicing, and compare the frames with what
was drawn. The ogre's walk, slam, leap and flinch sheets have been through it. Two pieces were
drawn by hand on top: the flinch's front and side jolt frames had the maul's head cut flat
against the line by the generator, with nothing across it to bring back, so its left end is
rebuilt from its own right end; and the leap's side and back got the crouch's maul back from a
half-size copy, its full-size pieces having been painted out in an earlier fix. The leap's
back-quarter, whose landing had its toes to the viewer, was drawn again with
`ogre-leap-back-quarter-feet.txt` added to the prompt (`leap-back-quarter-b-2.png` is the
other try).

```bash
python3 tools/slice_turnaround.py art/ogre/turnaround-2.png data/sprites/ogre/turnaround --height 173 --filter box
V="front front-quarter side back-quarter back"
for a in walk:20 slam:20 leap:15 hurt:10; do python3 tools/slice_views.py data/sprites/ogre $a $(for v in $V; do echo art/ogre/${a%:*}-$v.png; done) --height 1384 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
python3 tools/slice_frames.py art/ogre/death.png data/sprites/ogre --pixel 2.6 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/ogre/dust.png data/sprites/ogre --pixel 4.3 --anchor bottom --filter box dust:6
```

Its `define-fx-animation` sizes are the strips' cell heights over the turnaround's 173 px.

The gale wraith (a hood with no face, two pale violet eyes, long wind-swept strips of storm grey,
slate and dusty violet rag with nothing behind them, bandaged arms, no legs) is
`art/wraith/turnaround-1.png` (`art/prompts/wraith-turnaround.txt`, the imp's, acolyte's, knight's
and necromancer's sheets as style references), sliced at `--height 115` for its 1.8 m, rag tips
included. Its back-quarter faces right, so the turnaround takes `--mirror back-quarter`, and
`art/wraith/stand-back-quarter.png`, cut from it, is mirrored so that view's sheets need none.
It has a cast (gather, both arms raised with lightning on the hands, the frame the tornado's cast
holds, release, recover) and a flinch, made with `tools/gen_monster_views.sh wraith <anim> ...`,
and a front-only death (`wraith-death.txt`) that settles into an empty heap of rags. It has no walk.
The sign under its tornado's cast is drawn: `tools/draw_gale_sign.py data/sprites/gale`. So is the
boss's summoning sigil (embers: a double ring, an inverted triangle, flame tongues):
`tools/draw_summon_sigil.py data/sprites/summon`.

```bash
python3 tools/slice_turnaround.py art/wraith/turnaround-1.png data/sprites/wraith/turnaround --height 115 --filter box --mirror back-quarter
V="front front-quarter side back-quarter back"
for a in cast:20 hurt:10; do python3 tools/slice_views.py data/sprites/wraith $a $(for v in $V; do echo art/wraith/${a%:*}-$v.png; done) --height 920 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box --violet; done
python3 tools/slice_frames.py art/wraith/death.png data/sprites/wraith --pixel 3.82 --anchor bottom --filter box --violet death:8
```

Its strips need `--violet`: without it the slicer takes blue above green for a blend with the
magenta background, so it keys out the violet rags, eyes and lightning and greys what's left.

The riftwalker (a lean knife fighter in a low crouch, a close charcoal hood over a featureless
mask of polished brass, wrappings of charcoal and deep indigo cracked with pale silver-blue light,
a curved dagger in the right hand, a shard of light over the left palm) is
`art/riftwalker/turnaround-2.png` (`art/prompts/riftwalker-turnaround.txt`, the imp's, acolyte's,
knight's, necromancer's and wraith's sheets as style references), sliced at `--height 115` for its
1.8 m. No view needed mirroring. Its walk, stab (wind-up, lunge, strike, recover), cast (the rift
gathered in the left hand, held up as a jagged diamond, flung, recover: every rift and the call)
and flinch are made with `tools/gen_monster_views.sh riftwalker <anim> ...`, and its front-only
death (`riftwalker-death.txt`) cracks the mask and folds it face down beside the dagger. Its
strips take `--violet` too, which keeps the indigo and the blue cracks the plain keying greys.

```bash
python3 tools/slice_turnaround.py art/riftwalker/turnaround-2.png data/sprites/riftwalker/turnaround --height 115 --filter box
V="front front-quarter side back-quarter back"
for a in walk:20 stab:20 cast:20 hurt:10; do python3 tools/slice_views.py data/sprites/riftwalker $a $(for v in $V; do echo art/riftwalker/${a%:*}-$v.png; done) --height 920 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box --violet; done
python3 tools/slice_frames.py art/riftwalker/death.png data/sprites/riftwalker --pixel 3.54 --anchor bottom --filter box --violet death:8
```

Its rifts are one generated sheet, `art/spells/rift-orb.png` (`art/prompts/rift-orb.txt`, the bolt
sheet as reference: a void diamond rimmed in cold light, then its burst into shards), whose blue
flight is recoloured into the three rifts; the flash where something steps through is
`art/spells/rift-flash.png` (`rift-flash.txt`, a crack as tall as a body tearing open and
snapping shut). Both take `--cold`, which keeps the blues the usual keying takes for magenta
spill. The orb sheet's bottom cyan line runs under its last row, where no separator bounds the
cells, so the burst's last two frames keep a strip of it: the last command clears it.

```bash
python3 tools/slice_frames.py art/spells/rift-orb.png data/sprites/rift --pixel 10 --cold flight:5 burst:7
for r in pull:285 swap:45 push:188; do tools/recolor_hue.py data/sprites/rift/flight data/sprites/rift/${r%:*} --from 230 --reach 50 --hue ${r#*:}; done; rm data/sprites/rift/flight.*
python3 tools/slice_frames.py art/spells/rift-flash.png data/sprites/rift --pixel 6 --cold flash:6
python3 -c "from PIL import Image; p='data/sprites/rift/burst.png'; im=Image.open(p).convert('RGBA'); im.putdata([(0,0,0,0) if a and r<90 and g>170 and b>170 and abs(g-b)<50 else (r,g,b,a) for r,g,b,a in im.getdata()]); im.save(p)"
```

The status auras (magic.lisp) are 8-frame loops in `data/sprites/status/`, each a generated 2 × 4
sheet on magenta of small separate pieces over a body-sized area, the middle left open. Shock came
first (`art/prompts/status-shock.txt`, the bolt sheet and the torch's flame sheet as references);
it set the look, so fire (`status-burn.txt`, wisps of flame) and frost (`status-snow.txt`,
snowflakes) take its sheet as their first reference, with the bolt sheet for fire's colours and the
first frost try (`art/status/frost-1.png`, `-2`, rime round the body's outline, dropped) for
frost's. Ice and lightning are keyed with `--cold` to keep their blues:

```bash
tools/gen_image.py art/status/burn.png --prompt-file art/prompts/status-burn.txt --ref art/status/shock-2.png --ref "Bolt Spell Sheet.webp" --size 1536x1024 -n 2
tools/gen_image.py art/status/regen.png --prompt-file art/prompts/status-regen.txt --ref art/status/shock-2.png --ref art/status/snow-2.png --size 1536x1024 -n 2
python3 tools/slice_frames.py art/status/regen-1.png data/sprites/status --pixel 5 --filter box regen:8
python3 tools/slice_frames.py art/status/burn-1.png data/sprites/status --pixel 5 --filter box burn:8
python3 tools/slice_frames.py art/status/snow-2.png data/sprites/status --pixel 5 --filter box --cold frost:8
python3 tools/slice_frames.py art/status/shock-2.png data/sprites/status --pixel 5 --filter box --cold shock:8
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

The shard and health potion come from one generated sheet, `art/pickups/sheet-2.png`
(`art/prompts/pickups.txt`, the imp's turnaround as the reference), a row per kind and a 4-frame
glint across, at the monsters' 64 px per metre; its vial and crystal rows are out of use. The usual
keying takes blue for magenta spill and eats the crystals, so `--cold` keys only magenta and its
blends. The mana potion is the health potion's flask with its liquid recoloured, so the two share a
silhouette. The herbs are their own sheet, and the inventory's icons are drawn by a script:

```bash
tools/gen_image.py art/pickups/sheet.png --prompt-file art/prompts/pickups.txt --ref "Pixel Demon Character Turnaround.png" --size 1536x1024 -n 2
python3 tools/slice_frames.py art/pickups/sheet-2.png data/sprites/pickups --pixel 6.5 --filter box --colors 32 --anchor bottom --cold vial:4 flask:4 shard:4 crystal:4 && rm data/sprites/pickups/{vial,crystal}.*
tools/recolor_hue.py data/sprites/pickups/flask data/sprites/pickups/mana-potion --hue 222 --below 13 --reach 60
tools/gen_image.py art/pickups/herbs.png --prompt-file art/prompts/healing-herbs.txt --ref "Pixel Demon Character Turnaround.png" --ref art/pickups/sheet-2.png --size 1536x1024 -n 3
python3 tools/slice_frames.py art/pickups/herbs-3.png data/sprites/pickups --pixel 12 --filter box --colors 32 --anchor bottom herbs:4
tools/draw_item_icons.py data/sprites/icons/items
tools/gen_image.py art/pickups/dust.png --prompt-file art/prompts/pickup-dust.txt --ref "Pixel Demon Character Turnaround.png" --ref art/pickups/sheet-2.png --size 1536x1024 -n 2
python3 tools/slice_frames.py art/pickups/dust-2.png data/sprites/pickups --pixel 14 --filter box --anchor bottom --violet dust:4
```

The arena's gate is one generated picture, an ornate iron portcullis flat-on with magenta in its
gaps (`art/prompts/gate-portcullis.txt`, the imp's turnaround and the stone wall as references),
filling the square edge to edge so the sprite is the doorway's width; `--pixel 6.3` gives the
monsters' 64 px per metre at its 3.1 m. Leave off `--colors`: a 32-colour palette greyed the
skull plate's ember eyes.

```bash
tools/gen_image.py art/gate/portcullis.png --prompt-file art/prompts/gate-portcullis.txt --ref "Pixel Demon Character Turnaround.png" --ref art/textures/wall-stone-2.png --size 1024x1024 -n 3
python3 tools/slice_frames.py art/gate/portcullis-2.png data/sprites/gate --pixel 6.3 --filter box gate:1
```

The wall torch is two generated images: `art/torch/unlit-2.png` (the unlit torch in its
iron collar, front view, from `art/prompts/torch-unlit.txt`) and `art/torch/flame-2.png`
(an 8-frame flame loop, 2 × 4, from `torch-flame.txt`). The flame references the imp's
turnaround and the bolt sheet for style. The torch references the turnaround and
`sconce-2.png`, an earlier sconce with a backplate (`torch-sconce.txt`), for the torch's
look. Drop the plate: the sprite floats off the wall. Each is sliced into
`art/torch/strips/`, then `tools/overlay_strip.py` lays the flame on the torch head
(`--sink`: how far into it) as the game's 8-frame strip. The index's `:overlay-bottom`,
the flame's base row, is what `add-torch` stands on y. The `--pixel` values give both about
135 art pixels per metre at `*torch-size*` 0.96 m. That's twice the monsters' density: any
coarser and the collar and rag wrapping turn to mush.

```bash
python3 tools/slice_frames.py art/torch/unlit-2.png art/torch/strips --pixel 14 --filter box --colors 32 --anchor bottom unlit:1
python3 tools/slice_frames.py art/torch/flame-2.png art/torch/strips --pixel 9 --filter box --colors 16 --anchor bottom flame:8
tools/overlay_strip.py art/torch/strips/unlit art/torch/strips/flame data/sprites/torch/torch --sink 0.11
```

## Level blocks

Blocks are pieces of dungeon, one `.glb` each in `data/blocks/`, drawn with the greybox
shader in their material colours. Most are built from text blueprints (next section); a
Blender export that keeps the conventions works the same. Conventions:

- Metres, +Y up, the block's origin at its centre on the floor.
- The grid: a block is whole 4 m cells across (`*cell-size*`) and whole 5 m storeys tall
  (`*storey-height*`, in `hexmaw.blueprint`). Storey k's floor is at 5k, on a slab
  from 5k − 0.5. A corridor is one cell: a 3 m doorway and two 0.5 m walls.
- Every mesh object is drawn and its bounding box is a solid, unless its name starts
  with `deco_` (drawn, no collision), `plug_`, or `lava_` (not drawn: its bounding box is
  a lava volume, its top the surface, in a pit whose floor is a solid). Model collision as boxes: a sloped or
  L-shaped object's bounding box is the whole box around it. One named `wedge_<n>_<rest>`
  is that box with corner n cut away (1 north-east, 2 north-west, 3 south-west, 4
  south-east, as the block lies; turned with it): its mesh must be that prism, unrotated.
- Empties named `connector_<rest>` mark doorways, on the block's outer face, at the middle
  of a cell edge, on a storey's floor. A connector faces out through the face it lies on.
  Its kind is in its name: `connector_narrow_north` is `narrow` (2 × 2.5 m),
  `connector_river_north` a `river` (7 × 3.5 m, two cells, 3 m of lava down its middle
  between 2 m banks), `connector_stream_north` a `stream` (3 × 3.5 m, all lava, no
  banks), `connector_high_north` a `high` (7 × 9 m, two cells: the high blocks', floor to ceiling),
  `connector_ice_north` an `ice` (3 × 3 m, the ice caves': see "Generated levels"),
  anything else a `door` (3 × 3 m); `*connector-kinds*` lists them (a river's
  fourth value is its lava width, a stream's its whole width: `flooded-kind-p`),
  `connector_underwater_north` an `underwater` (3 × 3 m, full of water: a flooded passage's
  and a cistern's), `connector_canal_north` a `canal` (a river's with deep water: 7 × 3.5 m,
  its middle 3 m open down to the water filling the storey below, which runs on through the
  wall under it, so its plug reaches down there too), and each kind joins only itself. A doorway two cells
  wide is centred on the boundary between them. Light
  passes between blocks only through connectors: a block is one room for lighting, so its
  walls stop light from a block stacked above, below or beside it.
- Meshes named `plug_<rest>` fill the doorway of `connector_<rest>`, flush with the wall.
  They're left out when the block is placed; `seal-connector` puts them in, and takes the
  doorway's portal away, to shut a doorway nothing is attached to. A block without one
  is walled off outside instead, into the next cell, with a warning.
- Empties named `spawn_<monster>` (e.g. `spawn_imp`) place a monster facing the
  empty's −Z, `spawn_skip30_<monster>` with a 30% chance of none (`spawn-skipped-p`);
  empties named `torch_<anything>` a torch whose flame stands there
  (`add-torch` stands it off the nearest wall). Empties named `pickup_floor_<n>` and
  `pickup_reward_<n>` are spots a pickup may stand on (`src/pickups.lisp`).
- The scene's glTF extras may give `tags` (`room`, `corridor`, `stair`, `start`) and a
  `weight`, for the generator. Blender exports a scene's custom properties there.
- A material named after a surface (`wall`, `floor`, `ceiling`, `dais`, ...; see "Level
  textures") draws that surface; any other material is flat in its base colour. The
  .glb's own textures and UVs aren't read. Blender's duplicate suffix (`.001`) is ignored
  in every name.

`(attach-block 'shrine container "connector_south" :at point :facing :south)` places a
block so that connector sits at `point`, opening toward `:south`, and returns the block's
doorways as `connector` objects (`connector-name`, `-location`, `-direction`, `-kind`,
`-storey`), all open, for the next block or `(seal-connector container c)`. `place-block`
places one by its origin and quarter turns (`:spawns NIL` leaves its monsters out);
`attach-placement`, `block-world-bounds` and `block-cells` say where a block would go
before placing it. Blocks turn in quarter turns only. Re-saving a `.glb` and running
`tools/hd reset` picks up the new version.

While `build-level` runs (`with-block-batches`), placed pieces don't become entities:
`enter-piece` adds each piece's triangles, turned into world space, to a batch per look
(surface textures and colour), and `flush-block-batches` enters each batch as one
`block-piece`, so a level is a handful of draws instead of hundreds. The greybox shader
works in world space, so the picture is the same; what's lost is Trial's culling of each
box against the view, which costs the GPU a little (0.4 ms on seed 38, 0.7 on seed 11). A piece
placed outside `build-level` is entered on its own as before. `*blocks*` (the read
blocks) outlives reloads, and pieces read before batching existed have no `:mesh`, so
they are entered on their own too; `(clrhash *blocks*)` and a reset re-read them.

## Blueprints

A blueprint, `data/blueprints/<name>.txt`, draws a block top-down in text; `tools/blueprint`
builds it into `data/blocks/<name>.glb` (`tools/blueprint chamber stair` builds those,
`--check` only checks), and the game builds a block whose blueprint is newer when it
loads it, so after editing one `tools/hd reset` shows it. It builds with the blueprint code loaded in it: after changing src/blueprint.lisp, `tools/hd reload-system` first, or a blueprint using something new fails to build in the game (a runtime error every frame, and an empty level) even though `tools/blueprint` builds it. Errors give `file:line:col`.
`chamber.txt`:

```
; The general-purpose room. Its doorways plug, so it is any 1- to 4-door room.
cells 3 3              ; footprint in cells, west-east then north-south
tags room start        ; for the generator; weight 4 makes it 4 times as likely as 1
weight 4
legend                 ; this file's characters, indented: char action[, action...]
  i spawn imp south

plan 0                 ; storey 0, north up, to the next blank line
#########nnnnnn#########
#......................#
T......................T
#......................#
#......................#
w......................e
w..........ii..........e
w......................e
#......................#
#......................#
T......................T
#......................#
#########ssssss#########
```

A column is 0.5 m wide; a row is 1 m deep, except the first and last, the 0.5 m walls. So
a plan is 8 columns and 4 rows per cell, plus one row: a doorway is 6 columns on a north
or south wall and 3 rows on an east or west one. A narrow doorway is 4 columns, on a north or
south wall only: 2 rows can't be centred on a cell's edge. Nothing inside a block can be thinner
than 1 m north to south. Other header lines: `storeys N` (one `plan K` each, K from 0),
`ceiling H` (inside height of the top storey, default 4; corridors use 3), `material NAME
R G B` (defaults `floor`, `wall`, `ceiling`, `stair`; a material named after a surface in
`*surfaces*` is drawn with its textures, the rest flat in their colour, so a material
still waiting for its texture stands out), `mirror yes` (also builds
`<name>-mirror`, flipped west to east, for pieces a turn can't make: `cell`, `tower`),
`remap FROM TO` (draws material TO wherever the block would draw FROM, built-in pieces
included: `remap wall rock` makes every `#`, door lintel and plug rock, `remap floor
cave-floor` the floor slab; not `lava`) and `grid free` (skips the grid checks).

Built-in characters: `#` wall (from the storey's floor to the next storey's, or to the
ceiling; on storey 0 down through the floor slab), `.` floor, space open (no floor slab: a drop to the storey below), `n e s w` a
door-kind doorway, which must be on that side's border, `^` a doorway from the plan below going
on up through this storey (only a `high` doorway is taller than a storey, and the check asks for
`^` over it: no wall or slab here, just a lintel if it stops short of the storey's top), `T` a torch at 2.4 m (on a
border wall it goes just inside the room), and `/` and `\` a 45° wall: always a pair, `//`
or `\\`, a 1 m square cut along the diagonal the character draws, rock on the side whose
neighbours (the cells above and beside the pair) are more wall, floor on the other, and
an error when it can't tell. A staircase of pairs moving 2 columns a row is one straight
45° wall; each pair is a `wedge_` prism of the `wall` material (remapped like walls),
standing on the cell's floor slab. The legend action `diagonal DIR [material] [Y0 Y1]
[SIDE]` (DIR `/` or `\`) is the same with any character and any extent: Y0 Y1 as `box`'s
(default: the cell's floor, a pit's or lava's in one, an `open` cell's slab bottom, to
the top), so besides rock it draws the 45° edges of pits and pools (`diagonal / floor
-0.4 0, lava`: floor on one half, lava filling the other; `, pit` for a dry pit), shelves
(`diagonal / cave-floor 0 0.4`), hanging rock (`diagonal \ rock 3 top`) and drops (`diagonal
/ floor -0.5 0, open`, half a slab). Its solid half is the side whose neighbours are solid
over the whole Y0..Y1 (a wall, a box, the floor slab up to its top, a pit's to its floor;
a diagonal neighbour doesn't count), or SIDE (`ne`, `nw`, `se`, `sw`) for what the
neighbours can't decide, such as a 2 × 2 m diamond column of four pairs with no core.
Combined with `lava`, a full-height diagonal stands in the pit and the lava fills its open
half (the caves' `<` and `>`). A pool's lava box runs under the floor half too, hidden
under it; standing there doesn't burn, since liquid checks look just above the feet. Legend actions: `wall [material]`, `floor [material]` (the cell's floor slab in that
material, `floor ice` for ice; `.` is plain `floor`),
`open`, `box Y0 Y1 [material]` (solid from Y0 to Y1 above the storey's floor; `top` is the
storey's top), `deco Y0 Y1 [material]` (no collision), `door KIND`, `stairs DIR Y0 Y1
[material]` (the region of that character climbs toward DIR, in risers of at most 0.45 m),
`lava [DEPTH SURFACE]` (that cell's floor slab sinks to DEPTH below the floor, 0.4 by
default, and lava fills it to SURFACE below, 0.1; it can't touch the border), `pit
[DEPTH]` (the same sunken slab, 0.4 by default and less than the slab's 0.5, with no
lava: a dry dip, under a step so it is walked through), `water [Y]` (deep water from the
cell's floor up to Y, `top` for the storey's top, by default `*water-surface*` (0.3 m) under
the next storey's floor; never above the slab over the cell or a doorway's lintel; on the
border only under a canal doorway's open channel), `torch Y`
and `spawn MONSTER FACING [SKIP] [when:COND|COND]`, where `when:` limits it to those settlement
conditions (see "The settlement") and SKIP is a percent chance of no monster (every room
has its guaranteed spawns and two `m spawn ... 30`, or `m` and `M` where it has two kinds of
spawn; a generated level rolls them, the test level leaves them out, and the gallery and
`check-kit` place them all), and MONSTER may be a choice, `imp|knight` (on a generated level only
those of it in the level's pool, and a block with a named spawn the pool has none of is left out,
`block-fits-pool-p`: so the high quarter's `spawn ogre` rooms wait for a level with the ogre), or `any`
(one of `*spawn-pool*` by weight: imp 3, acolyte, knight, harpy, necromancer, ogre, gale wraith and
riftwalker 1 each, though each level of a run has its own pool, its `:pool`), or `any-ogre` (the pool without those after the dash, `|` between them: a block too
tight for them, as the `cavern` and `balcony` are for the ogre), or `boss` (`make-boss`, boss.lisp), picked as the
block is placed (`spawn-choice`, from `*block-random*`, which the generator binds to its
own state; one float draw whatever the weights, so changing a pool's weights never changes the layout,
though adding or removing a kind some block names does). They combine with commas: `I box 0 0.8 dais, spawn acolyte south` stands the
acolyte on the dais. Each connected group of one spawn character
is one monster at its centre, so `ii` centres one on a 1 m spot. `pickup floor` or `pickup
reward` is a spot where a level may put a pickup, one per group like a spawn, on top of a `box` in
the cell or down in its `pit` (`& box 0 0.8 sarcophagus, pickup reward`, `& water, pickup reward` on
the bottom of a pool). The kit's use `$` and `&`. A floor spot holds a small pickup and must be walked to from a
doorway; a reward spot holds a large one first and may take a jump (up to 1 m), a swim or a
risk. `(check-kit)` reports one that can't be reached. No spots in flooded passages, streams or
on `high-hall`'s perch, which the player can't jump to. `exit` is where the player leaves the
level (`*level-exits*`, one per group like a spawn, on the storey's floor), which `(check-kit)`
reports if no doorway reaches it. `altar` is a spellforge altar (`*level-altars*`, forge.lisp), one
per group, on top of the `box` in its cells (`A box 0 0.9 dais, altar`; the town's blueprint uses it
too). Characters with the same
column merge into as few boxes as possible. No two faces may lie in one plane facing one
way, or they flicker: so a wall gets no floor slab under it, and a wall or full-height box
under a floor slab of the storey above stops 0.5 m short, under the slab. A doorway gets `connector_[<kind>_]<side>`,
numbered `_2` and on when a side has several, lower storey first, and its plug; its lintel
and plug are the material of the border wall nearest it (`border-wall`), so an ice gate's ice
doorway is shut with ice-rock and its rock one with rock. A doorway
is the border cells of one kind side by side, whatever their characters, so a river's is
lava cells (`= door river, lava`) between bank cells (`R door river`); its middle lava
width must be lava and the rest bank, so any river doorway meets any other (a stream's is
lava wall to wall, `- door stream, lava`). Wide, it is 14 columns on a north or south face
and 7 rows on an east or west one, centred on a cell boundary.

The kit: corridors `corridor`, `corridor-long`, `corner`, `tee`, `cross`, `dead-end` (a
niche 2 m wide: a 1 m one was too tight for a creature's nav cell, so it never left; no tags,
so the generator leaves it out),
`arch` (beams and torches, the way into a room), `narrow` and `narrowing` (to a narrow
doorway); stairs `stair` (one storey, 1 × 2 cells) and `tower` (a switchback, 2 × 2);
rooms `cell`, `chamber`, `vestry` (2 × 2, narrow doorways only, in opposite cells, between two
stone benches), `reliquary` (a front room with full doorways, a stone screen with two 2 m gaps,
a sanctum behind it with a narrow doorway out: an ogre stops at the screen), `shrine` (dais), `hall` (pillars, a knight, acolyte, harpy, necromancer or ogre), `crypt`
(sarcophagi), `forge` (a lava channel across it, 3 m: a running jump clears it, with a
bridge and banks to every doorway), `ice-hall` (a sheet of ice ringed by a stone rim, pillars on
the ice) and `balcony` (two storeys, a ledge all round over an open floor, and a stair
up to it); caves `cave` (wavy 45° walls, an octagonal pillar, an octagonal shelf and
hanging rock, a lava pool against the rock and a dry pit, both with 45° shores), `lava-lake`
(a causeway with 45° edges across lava, a bridge east) and
`cave-passage` (a corridor at 45°, 2 × 2 cells), `grotto` (small, a diamond column),
`cavern` (4 × 3: two pillars, a shelf, hanging rock), `lava-chasm` (a 3 m band of lava, a
running jump or a 45° causeway) and `magma-pool` (an island on a causeway), and the cave
connectors `cave-bend` and `cave-fork`; and the lava rivers (below): wide `river`,
`river-ford` (bridged, doorways on both banks), `river-bend` and `river-cavern` (a room the
river runs through, bridged), narrow `stream` and `stream-bend` (lava wall to wall, no bank: the only way along is
wading, and it burns), `river-narrows` (wide to narrow: the banks run out and its last cell
is all lava), and the ends `lava-spring`, `lava-sink` and `stream-spring`; most with a mirror;
the water blocks: `pool` (a ledge 2 m wide round deep water filling the storey below, 4
doorways on the ledge), `cistern` (a pool with an underwater doorway at the bottom of its
west wall: the end of a flooded run), the flooded passages `flooded-passage`, `flooded-bend`
and `flooded-tee` (full of water to the roof, swum on one breath, no torches), and the canal:
`canal`, `canal-bend` (mirrored), `canal-ford` (a bridge, doorways onto both banks) and the
end `canal-end` (the banks joined round the channel's head);
and the high quarter (below), for the ogre's leaps: rooms `vault` (the end: a 9 m vault, a
2.5 m terrace and a 5 m walkway with a doorway out at the top), `high-hall` (six pillars the
full 9 m, a 2.5 m dais with no steps, a perch) and `terrace` (climbs a storey, 14 m tall),
and galleries `gallery`, `gallery-corner`, `gallery-steps` (climbs a storey) and
`gallery-chasm` (4 m of lava, a 1.5 m ledge for the player), all 7 m wide.
The settlement's `town` (8 × 6 cells, two storeys; tagged `town`, never grown into; see "The
settlement"). The run's ends, tagged so growth never picks them: `descent` (the way down) and `arena` (4 × 4
cells, 9 m tall, one doorway on the south, four full-height pillars, the boss, `spawn boss`, at
the north end, and a reward spot on a 0.8 m block in each corner by the door; see `src/boss.lisp`).
The stone caves (`cave`, `grotto`, `cavern`, `cave-passage`, `cave-bend`, `cave-fork`,
`lava-lake`, `lava-chasm`, `magma-pool`) are tagged `cave`, and the last three `lava` too. The ice caves have walls of
`ice-rock` and a floor of `snow` (both grip), frozen ponds of slippery ice sunk 0.2 m
(`pit 0.2, floor ice`, 45° shores of snow) and icicles (`box 3 top ice-rock` in octagons,
or diamonds down to 2.2 m in the 3 m corridors), and all their doorways are `ice` (`+ door ice`): `ice-grotto` (a pond
with a diamond column), `ice-lake` (nearly all rink, icicles over it), `ice-cavern` (4 × 3:
pillars, one in a pond, a slippery ice shelf, icicles), `frost-shrine` (octagonal: an acolyte on an octagonal dais of ice, a pond, two columns), `ice-niche` (1 × 1, a monster on ice; what fits behind a gate when nothing bigger
does), and the corridors `ice-passage` (45°), `ice-bend` and `ice-chute` (three cells of
ice, winding 45° at a time). The ice gates, `ice-gate` and `ice-gate-bend` (tagged `corridor ice-gate`), are half
rock cave and half ice cave, with a `door` on the rock side and an `ice` doorway on the
other: rock gives way to ice along a 45° line across the passage, walls and floor alike,
under a drift of snow 0.1 m high with 45° edges (`frost_line`), since a change along a row
or column reads as a slab laid across a cave. Nothing in a cave is a rectangle: the chute
winds, the niche and the shrine are chamfered, hanging ice is octagonal or a diamond
(`hang_diamond`, in the 3 m corridors), and ponds and shelves have 45° edges.
`tools/cave_plans.py` draws every ice block (`POND`, `pond_rock`, `hang_over`,
`hang_diamond`, `frost_line`). `ice-hall` is an ordinary dungeon room with an ice
floor, outside all this. Ice never meets lava: `ice-bridge` (the forge frozen, ice up to its
lava channel) has no tags, so the generator leaves it out, until water can fill its channel.
Every piece must let the player walk between all its doorways (drops don't
count), or the generator builds places that are a one-way trip. `(check-kit)` checks it, for
every block or a list of names: it builds each alone (`*level*` `:block`, `*check-block*`)
and reports what's wrong (`block-problems`): ordinary doorways that don't reach each other,
a doorway or bank that leads to no other doorway, a river end that doesn't join both banks,
a monster that can't reach the first doorway, a high block the ogre can't walk between all
its doorways at `*high-body*` (radius 1.0, 2.7 m, step 0.45: its leaps are shortcuts, never
its only way), a pickup spot the player can't get to. A block with a stream doorway is checked wading (it can't be crossed dry),
one with an underwater doorway swimming (`*nav-hazards*` `:swim`), the rest dry, so a wide
river's or canal's banks still walk dry; a check starts at a doorway on dry floor. Leave passages at least 1.5 m wide: the nav
grid's 0.5 m cells need a cell centre 0.3 m clear of rock for the player, and a 1 m gap
beside a column had none.

High blocks are at least two storeys (`storeys 2`, plan 1 open but for its walls, 9 m
inside), so whatever a high doorway opens onto has the height. The doorway is 9 m too, so two
joined blocks open floor to ceiling with no wall across the join; it is drawn `H` in its own plan
and `^` in the plan above. Its plug is 9 m as well. The `terrace` and `gallery-steps` are taller
than that (14 m), so their lower doorway has a lintel from 9 m, in `^`'s plan. Their tiers rise 2.5 m, the ogre's highest leap. A pillar the full height is `box 0
top pillar` in plan 0 and `wall pillar` in plan 1 (a wall there has no slab under it, so no
floor-coloured band at 5 m). A stair the ogre can walk is 3 m wide with 1 m treads (6 rows
for 2.5 m), and 2 m of floor before its foot, under a ceiling its head clears a tread up
(the kit's `stair`, rising from under a 3 m doorway, has neither). A tall body's clearance is
a box over 0.9 m above the floor (`*nav-tall-lift*`), so two 0.42 m steps within its 1 m
reach don't block it, but floor beside a flight sees its upper treads as one, so a big body
only gets on a flight head-on. `*high-body*`'s step of 0.45 is stricter than the ogre's 0.9.

Caves are blueprints like the rest: rock is wall characters inside the rectangle (every
`#` is rock under `remap wall rock`), 45° rock is `/` and `\` pairs, or `<` and `>` where it
stands in lava, shelves are `box 0 H cave-floor`, low rock `box H top rock`, dips `pit` or
`lava`, and each has 45° edges through `diagonal` with its heights. Every edge in every cave
block runs at 0° or 45°. Their plans are drawn by `tools/cave_plans.py` (`tools/cave_plans.py
NAME` redraws one, `--check` says which differ), one spec per block: the room's outline as
the first open and first rock column at each row boundary (a line moving 2 columns makes a
diagonal pair), then regions inside it (pools, pits, shelves, hanging rock, causeways),
each with its own pair characters, rock in lava, and doorway strings; the header and legend
stay hand-written in the blueprint, and the tool rewrites the rows after `plan 0`. A pair
can't tell its side when both outer sides are other diagonals: move it, or give it a SIDE.
So walls and pools are octagonal, not round, floors and ceilings stay flat and terraced,
dips go no deeper than the slab (deeper hollows need the floor
raised round them), their mouths are ordinary doorways on the grid, and each is one room
for lighting: a passage that doubles back inside one block lights through the rock
between, so keep a cave one open space. Shaped pools merge into fewer lava boxes than
stepped ones (seed 11: 23 lava surfaces against 33, 3.0 ms a frame against 4.1, vsync off).
A cave is 80 to 90 boxes and wedges, about four times a chamber: that many solids for collision, but drawn in the level's batches. Keep
shelves clear of doorways: one 0.8 m shelf a column inside a doorway left 0.5 m of floor,
too narrow for the player, and `check-reachable` found whole regions cut off.

To walk the kit: `tools/hd '(progn (setf *level* :gallery) (reload-scene))'` lays every
block out in two rows, corridors and stairs in front, rooms behind, each with one doorway
open toward the spawn and the rest plugged, on ground that stops at each block's walls
(`add-ground`; under a block it would fill its lava pits), and `(game (kit-goto "chamber"))`
stands the player outside one. Upper storeys are only reachable by moving the player there. Every pickup spot holds a pickup
in the gallery, to look them over.

## Generated levels

The main menu's Start game builds the first of a run (see "A run" below);
`(setf *level* :generated)` and a reset do too (`generate-level`):
it starts in a block tagged `start` (the player and `*spawn-point*` at its centre, and no
monster spawns within `*start-clearance*`, 16 m, of it: a neighbour's monster looking
through the start room's doorway charged the player the moment the level began;
`*spawn-clearance*` holds the point while the level is built, and the spawn's random
choice is still made, so a seed builds the same level), keeps a frontier of open doorways, and picks one at a time:
from a room it adds a corridor or stair, from a corridor another corridor (less likely the
longer the run, `*corridor-run*`) or a room, by weight, trying each of the block's
doorways of the same kind turned to face it until one fits in free grid cells
(`*generator-storeys*` bounds how high and low). A doorway that meets an open one joins
it, which makes loops; one that runs into another block's wall is plugged. `*generator-rooms*`
(16) is how many rooms it aims for: growth stops when the rooms in and the corridors still open
add up to it, since each open corridor then gets a room (`finish`; no network room, whose arms
would be plugged), and a plug only if no room fits. So a corridor ends in a room wherever one
fits, but it can't be taken back: 2.1 of a level's 35 blocks still lead nowhere. Few rooms have
a `narrow` doorway and a stair has to arrive somewhere, so those take one more corridor piece
when no room fits there, finished in turn. If that leaves the level short, growth goes on from
the rooms' doorways. Every doorway still open at the end is plugged. A level has 16 rooms on
172 of 200 seeds and 17 or 18 on the rest, 4 of them a network's. `*level-seed*` fixes
the run's seed (NIL picks one, see "A run"); `*last-level-seed*` is the last level's, and
`(level-map)` prints its cells a storey at a time. The generator draws from its own random
state, since monsters use `random` as they spawn. `*generator-blocks*` limits the blocks it
uses (NIL: every block with tags). A doorway left opening onto nothing is a bug and logs a
warning. Two doorways that meet share one portal (`drop-portal` removes the other), since
the shader takes only 32.

Networks: a network is the blocks joined through doorways ordinary blocks don't have; each
family is an entry in `*networks*` (its doorway kinds, piece and end tags, and the variables
for its length and how many a level may have). There are four: rivers, below; high
quarters, galleries and high rooms joined through `high` doorways (`high`, ends `high-end`:
the vault), `*high-length*` (3 to 6) blocks long, `*max-high-networks*` (1) a level; flooded
runs, passages joined through `underwater` doorways (`flooded`, ends `cistern`), a cistern at
each end, `*flooded-length*` (2 to 4 blocks, the first cistern included: short, swum on one
breath), `*max-flooded-networks*` (1); and canals (`canal`, ends `canal-end`),
`*canal-length*` (3 to 6), `*max-canals*` (1). All grow the same way, with `network` in place
of `river` throughout. A cistern has one underwater doorway, so a run ends at it; one reached
through its ledge starts a run.
`*level-networks*` holds the last level's (`network-family`, `-pieces`, `-target`, `-ends`),
the log line says how each ended, and `(level-map)` draws a high quarter's blocks as `^`, a
flooded run's as `=` and a canal's as `-`. Over 200 seeds, 60% of levels had a canal (4 blocks on
average), 11% a flooded run (3) and 24% a high quarter (4), and a level had 0.8 network arms
end in a plug. The vault, 4 × 4 cells and two storeys, is the high quarter's only end and often
doesn't fit.

Rivers: a river is the blocks joined through `river` and `stream` doorways. The first river
block comes in like any corridor or room, through an ordinary doorway (river pieces are
tagged `river` as well as `corridor` or `room`, ends `river-end` and `room`), and starts a
river with a target length of `*river-length*` blocks (5 to 9) shared by its arms. Its open
river doorways are tried before any other (`next-door`): with pieces until the river has
its length, then only ends (one river doorway and ordinary doorways onward), an end still
tried ahead of a plug when no piece fits, and at the room quota every open arm gets its end.
So an arm ends in an end block, in a join with another river doorway, in another room with
its doorway if no end fits, or, if nothing fits, in a plug, and the dungeon carries on from the ends and the pieces' side doorways. After
`*max-rivers*` (1) rivers, river blocks leave the ordinary choices. `(level-map)` draws
river blocks as `~`. A river's two banks meet only at its
ends and crossings (fords, the cavern's bridge), so ends join both banks; a stream has
no banks, so a river that narrows is waded from there on, and the dungeon past it is
reached through lava. Over 200 seeds, 99% of levels had a river,
of 9 blocks on average.

Ice: the ice caves are a frozen wing of the caves. Their doorways are all of kind `ice`, so
they join only each other and the ice gates, and a gate's rock side joins only a block tagged
`cave` and not `lava` (`gate-allowed-p`: in `try`, and when two doorways meet face to face),
so the way into the ice is always a rock cave, a gate, then ice. An ice doorway that fits no corridor tries the rooms too
(few blocks have one), the first piece through a gate isn't another gate, and a gate doorway
still open at the room quota gets a room, ice or cave. `check-ice-joins` warns about any join
against the rule after every generated level. Over seeds 1 to 100, 20 levels had an ice gate,
and 29 of their 30 gates led into the ice. The generator asks every block's tags and weight
thousands of times a level, so `build-level` binds `*block-memo*`, which keeps each
definition `find-block` gives (half a millisecond each, since it checks the files): a level
generated in 5 to 10 s before it, under one after.

Every level is checked once built (`check-reachable`, after `build-nav-grid`): the
player must be able to walk from the spawn point to every placed block's doorways (both
banks of a river's: `doorway-probes`; a stream's middle, in the lava), on the
nav grid with the player's size and step, wading and swimming where it must (`:swim`) (`nav-reached`, which is both ways, since steps
go up as well as down), and every creature must be able to walk to the spawn point at its
own size and step from a cell its body fits where it lives (`stranded-creatures`, wading
too, as a chase does when there's no dry way, and through deep water: no creature swims,
but one beyond a flooded run or across a canal waits there for the player, who does). Each
doorway or creature that fails logs a warning.

## A run

A run is the generated levels of `*run-levels*` (`src/run.lisp`) one after another: 16, 19 and 22
rooms. Each entry says how many rooms the generator aims for (over `*generator-rooms*`,
`level-settings`) and which block it puts on the doorway furthest from the start (`:exit`, a name or
a list tried in order): the `descent` on levels 1 and 2, the boss's `arena` on level 3 (see
`src/boss.lisp`), whose boss ends the run. `run-levels` puts the settlement's level
(`*settlement-level*`) among them at depth 2 or 3, so a run is 4 levels and the ones from there on
are a depth further down (see "The settlement"); everything that asks about a depth goes through
`run-levels`, `run-length` and `run-level-property`. The settlement's level is as hard as the level
after it, whose keys it takes. The kit is the same on each, but the monsters get
harder going down, by keys in each entry (none are flat stat multipliers):

- built into the level (`level-settings` sets their variables for the generator, so a save keeps
  them, through `*level-setting-keys*`): `:pool`, what `any` picks from (`*spawn-pool*`: no ogre,
  wraith or riftwalker on level 1, and more heavy monsters on level 3; leave a kind out rather than give it 0),
  which also limits named spawns: a choice keeps the kinds in the pool, and a block naming only kinds
  outside it isn't used (`block-fits-pool-p`; on level 1 the high quarter's rooms, which spawn ogres,
  and so the whole high quarter; the log says which),
  `:skip-scale`, which scales the chance of an empty `spawn ... 30` (`*spawn-skip-scale*`: 1, 0.75,
  0.5), and `:elite-chance` (0, 0.12, 0.2; see `src/elite.lisp`);
- asked in play (`depth-scale`, 1 off a generated level): `:sight` and `:hearing` scale
  `*sight-range*` and `*hearing-range*` in `sees-player-p`, `:alert` the hunt's `alert-time`,
  `:pause` the pause after an attack, `:cooldown` the necromancer's, wraith's and riftwalker's
  abilities and the ogre's leap (not the boss's powers). 1, 1.15 and 1.3 the sight; pauses 1, 0.85 and 0.7.

Each level's `:loot` says what weapons and runes it hands out (see `src/loot.lisp`). Pickups stay
budgeted per monster, so more monsters bring more, and an elite counts as one. `*run-depth*` is the level the player is on, from 1,
and `*run-seed*` the run's seed: `(level-seed run-seed depth attempt)` gives each level's, the first
try at level 1 being the run seed itself, so `*level-seed*` still reproduces a level 1 and a whole
run. A reset on a generated level rebuilds the same level, since the run keeps its seed; a new one
needs `(setf *run-seed* NIL)` first.

The way down is the `descent` block (1 × 2 cells, two storeys: a doorway at the top, a flight down,
a landing in front of a painted arch, its stair going on into the dark; see "Level textures"). It is tagged only `descent`, so growth never picks it; `generate-level`
puts its `:exit` on the deepest doorway still open when growth stops, by blocks from the start
(`door-depth`, since there is no nav grid yet), just before the rest are plugged. After it, with the level's
`:altar-chance` (1 on level 1, 0.4 below), the `shrine-altar` (`*altar-block*`: a 2 × 2 sanctum, a
spellforge altar on a 0.9 m slab, tagged only `altar`) goes on a doorway between 30% and 70% of the
deepest depth. That roll is the generator's last draw, so a level that doesn't roll one is the level
it was. The town (another branch) has the run's own altar. Then `build-level` asks
`level-needs-rebuilding-p`, which says why the level won't do: `level-goal-reached-p` (an exit, or
else the arena's doorway, wading and swimming where they must) failing, the settlement's wing too
small, or, at an `:altar-chance` of 1, no altar the player can walk up to (`altar-reached-p`, the
floor round its stone in reach of `near-altar-p`). Then it empties the scene (`clear`) and tries
the next seed, up to `*max-level-attempts*`; a loaded level is never retried, its seed having
passed. So the first level always has a spellforge: over run seeds 1 to 100 its altar fit, and could
be reached, on the first seed every time.
`level-settings` and the seed are what a save keeps, so a save needs only the level it's on.

Standing on the landing (`at-level-exit-p`: within `*exit-reach*` across and `*exit-height*` of its
floor, which leaves out the stair's last step and the room next door) runs `descend`. It adds a
`level-record` to the player's `level-records` (monsters, slain, blocks, explored, seed), keeps
`carried-state` (`*carried-slots*`: **a new slot that should survive the stairs needs adding there**,
as well as to `saved-slots`; what the player knows, the hotbar, the slot in hand and the
enchantments are there), and rebuilds through `load-level`; `setup-scene` lays that state over
the fresh player. It is one-way: the old level goes with its scene, along with anything in flight. No
key or clearing is needed. `run-totals` adds the records to the level in play, for the death screen.
On arriving, `level-banner` (hud.lisp) says "Level 2 of 3" for `*level-banner-time*` seconds of play,
and the automap labels a revealed exit "Stairs down" (`exit-label`). `tools/hd status` gives the level
and the exit's position. To go down at once: `(game (v<- (feet *player*) (car (aref *level-exits* 0))))`;
to walk the stair, stand at the `descent` connector in `*level-doorways*` and hold W.

Over seeds 1 to 200 at each size, every exit fit on the first seed and could be reached, and the
rooms always reached their target (16.1, 19.1, 22.1 on average; 16 to 18 at the lowest size, 22 to 24
at the highest). Monsters: 15.9 (11 to 21), 19.2 (13 to 27) and 22.7 (16 to 29), so about 58 a run
(an older count: over run seeds 1 to 20, `*creatures*` held 33.0, 42.3 and 54.3 after the depth
scaling, against 31.9, 40.3 and 48.9 before it, with 10% elites on level 2 and 19% on level 3;
all before imp packs, which add a quarter or so);
pickups 13.2, 15.7, 18.3. A level takes 0.4 to 0.5 s to build, 0.8 s at most. Over seeds 1 to 100 on
levels 1 and 2 the walk to the exit is 136 m on average against 143 m for the level's longest walk,
with a median at 99.6% of it and the lowest tenth under 81%: blocks from the start are a good stand-in.
It can be close in a straight line (20 m away, but a 91 m walk). 6 of those 200 exits lie behind a
flooded run, so the only way there is a swim. Frames (seed 12345, 12 spots, frozen, vsync off) cost
5.9 ms on level 1, 6.4 on 2 and 6.1 on 3: the lamps sent decide the cost, not the level's size.
Over run seeds 1 to 100, level 3's arena fit on the first seed every time and could be reached, the
level building in 1.8 s on average through `reload-scene` (2.4 s at most). It can lie close to the
start in a straight line (seed 27: 6.7 m, a storey up), so the boss's spawn ignores the start's
clearance. Bosses (before the riftwalker joined `*boss-kinds*`, which changed every seed's draw):
necromancer 20, gale wraith 19, knight 17, ogre 12, imp 11, acolyte 11, harpy 10.

Controls: click the window to capture the mouse, Esc to pause (release the mouse, open
the pause menu) and Esc again to resume. WASD, Shift to run,
Space to jump, C or Ctrl to crouch (in water: W swims where you look, Space up, C or Ctrl
down; swim into a ledge at the surface to climb out), 1 to 9 for what the hotbar holds (at the
start 1 the sword, 2 the fire bolt, 3 heal; whatever is found goes on the next free key), the mouse wheel to change the
quickslot's potion, left click to attack (swing, thrust, or cast the spell in hand), right button
held to raise the shield (sword only; a left click while it's up bashes), Q to drink from the
quickslot, I for the inventory (everything lives in the bag; drag a weapon or rune onto 1-9, or a
potion onto Q, to bind a key; see `src/inventory.lisp`), M for the automap (see `src/map-view.lisp`), F5 to
quicksave and F9 to quickload (generated levels only), F12 for a screenshot, and E to talk to the
townsperson looked at (see "The settlement") or, at an altar, to open the spellforge (see
`src/forge.lisp`).

To test combat without the mouse (the hall's monsters below need
`(setf *debug-hall-monsters* t)` and a fresh debug level): `tools/hd '(game (player-cast *player* (quote bolt)))'`
starts a cast, and the bolt leaves from the player's view `*cast-release*` (0.2 s) later,
on the hands' release frame; `(select-weapon *player* :1)` then `(player-attack *player*)` swings the sword (the blow lands
0.23 s in; stand within 2 m of the imp, facing it), and with `:3` thrusts the spear (0.24 s in, within 3.5 m); `(setf (block-raise *player*) 1.0)` under hit-stop
shows the raised shield, and with it raised `(player-attack *player*)` bashes (`block-held`
is what the right button sets; without it the shield comes down again once the world runs); `(hurt (aref *creatures* 0) 0)` triggers a hit reaction and a spray of blood (100 kills, and tears an imp apart; `:from point` aims the spray); to look at one death
frame, `(setf *hit-stop* 1000.0)` freezes the world and `(setf (dead imp) 0.35)` shows the
frame at that time; likewise `(setf (brain imp) :attacking (attack-time imp) 0.6)` shows an
attack frame (the blow lands 0.5 s in), and `(setf (alert imp) 6.0)` sets an imp hunting (the acolyte on the platform the same way);
`tools/hd status` shows mana, stamina and each creature's health. On a generated level,
`(game (hurt-player *player* 1000 (feet *player*) :by (aref *creatures* 0)))` kills the player, and the death screen follows. The knight stands by the west
pillars; a bolt at its front comes back at the player, one at its back hurts it, and
`(setf (brace knight) 0.25)` (impact) or `0.1` (brace) under hit-stop shows a block frame.
The harpy hovers over the hall's south-east, by the east doorway: `(setf (alert harpy) 6.0)`
sets it hunting, and `(dive-left harpy)` is non-NIL while it dives (hurt it then to down it).
The ogre stands in the hall's east: `(setf *leap-debug* t)` and `(setf (alert ogre) 30.0)` with
the player 4 to 12 m from it, and the log says where it leaps and what the shockwave hits;
`(airborne ogre)` is true in the air, and `*hit-stop*` 1000 then freezes it there.
The gale wraith floats at the back of the hall, east of the necromancer: `(setf (alert wraith) 30.0)`
with the player in its sight sets it casting, `(casting-tempest-p wraith)` is true until the
release, and a `(setf (stagger wraith) 0.3)` with `(stop-walking wraith 0.2)` is the flinch that breaks
it. `(select-weapon *player* :4)` then `(player-attack *player*)` casts the player's tornado, and
`(whirl *player*)` is the vortex holding them. Right after several level builds in a row, time
runs fast for a few seconds as Trial's fixed step catches up, so a vortex's age is no measure then.
`(issue (scene +main+) 'mouse-scroll :delta -1.0 :pos (vec2 0 0))` inside `(game ...)` turns
the wheel one notch down (the next kind into the quickslot).

## The settlement

Once a run, at depth 2 or 3 (`settlement-depth`, from the run's seed; `*settlement-depths*`), a
level is grown from the town (`data/blueprints/town.txt`) instead of a start block: `generate-level`'s
`:core`, placed first with its townsfolk and monsters, the player arriving at its `arrive` point.
The town counts as a room for the generator (`room-block-p`), so its two gates (west and east)
grow corridors into a small wing, the undercroft: `*settlement-level*` asks for 6 rooms, the town
included, with no networks and crypts, cells and corridors only (`:settings`, laid over the level's
generator settings by `level-settings`), and `level-needs-rebuilding-p` tries another seed when the
wing has fewer than `:min-wing` rooms (`*last-wing-rooms*`). The way on is the town's own `exit`,
at the back of the recess north of the plaza, before a painted `descent-arch`. Over run seeds 21 to
32 the wing had 5 to 7 rooms and 10 to 19 monsters, and no level warned.

`make-settlement` draws its faction, condition and name from the level's seed when it is built
(`*settlement-override*`, as `'(:depth 1 :faction :deepwardens :condition :besieged)`, fixes them for
testing; reloading run.lisp clears it). The faction (`*factions*`) decides the watch's rule, which
crimes count, prices and whether its guards take bribes:

| Faction | Rule | Crimes | Cheap | Bribable |
| --- | --- | --- | --- | --- |
| `:ashen-temple` | no spell cast in town (`player-cast`) | rule, assault, murder | healing, mana | no |
| `:deepwardens` | no sword or spear drawn in the `market` and `temple` zones (`check-drawn-blade`) | rule, assault, murder | training | no |
| `:free-company` | none | murder | goods (and a random extra in stock) | yes |

The player learns it on arriving: the level banner names the town and who holds it ("Level 2 of 4:
Cinderhold, held by the Deepwardens", `level-banner-text`), and the message line gives the watch's
rule for `*arrival-message-time*` (`announce-settlement`, hud.lisp, from `setup-scene`), or, sacked,
that the watch is dead. A guard's greeting names the faction too (its `*townsfolk-greetings*` are
format strings), and its panel shows the rule.

The condition (`*conditions*`, weights 3, 2, 1) decides who is there, through the blueprint's npc
and spawn conditions (`condition-excluded-p`, which rolls whatever the condition, so a seed builds
the same level): **thriving**, everyone; **besieged**, everyone but some commoners, and the wing
raids the gates; **sacked**, no watch, a few survivors, each service there half the time, monsters
from the pool in the streets and loot on the town's four `pickup` spots (`place-settlement-pickups`).

**Townsfolk** (`townsfolk`, a creature: `commoner`, `shopkeeper`, `priest`, `trainer`,
`quest-giver`, `guard`). Those who stand at their posts to be talked to (the shopkeeper, priest,
trainer and quest-giver) are one front-facing picture each: a billboard whose atlas has one view
shows it from every side. Those who walk about, the guard and the commoners (a `townsman` and a
`townswoman`), have a monster's full set (`define-townsfolk-set`, `*townsfolk-sets*`, by sprite
name): a turnaround, a walk, a flinch, a death to a corpse and, for the guard, a spear thrust, the
guard's one set recoloured per faction (`guard-<faction>`). Guards step in armour, commoners lightly;
none of them has a voice. They keep to their posts (`wander-radius` 0; a commoner 3 m, a guard 1.5)
and while calm (`calm-p`, not `provoked`) never notice the player, even if they could fight
(`attacker-p`). `place-npc` makes one from a blueprint's npc by role (`*roles*`: class and sprite,
the guard's per faction), with a name and greeting from `*townsfolk-names*` and
`*townsfolk-greetings*`. They aren't monsters (`monster-p`): no kill gold, not counted by
`run-summary` or `scatter-pickups`.

**E** (`player-interact`) uses what `interact-target` gives: the nearest `interactable-p`
townsperson within `*interact-reach*` and `*interact-arc*` (`looked-at-creature`, the sword's
test), else `:altar` at an altar (`near-altar-p`, forge.lisp), whose `interact` opens the
spellforge; the director keeps `*interact-prompt*` ("[E] Talk to ...", "[E] Spellforge").
Talking (`start-talk`) sets `*game-state*` `:talk` and puts up a `dialogue-panel`; Esc or Leave
ends it (a guard asking a fine has no Leave, and Esc there refuses it, `escape-talk`). A click acts and sets `*menu-refresh*`, which makes the menu controller build the panel
again (an Alloy panel lays itself out once). Services refuse while the watch is hostile or once the
player has sacked the town (`refusing-p`):

- **Shopkeeper**: buys and sells `*shop-goods*` (health and mana potions; the stock, 1 + depth of
  each, is on the settlement), selling at `*sell-share*`. A page of its own (`*talk-page*` `:glyphs`,
  `show-talk-page`) sells every glyph whose effect the player doesn't know (`shop-glyphs`, `buy-glyph`,
  `price :glyph`, priced as goods): bought, it is learnt at once (`learn-glyph`), so it takes no room
  and needs no stock. Dead, its stall can be searched (`loot-item`), for potions only.
- **Priest**: heals and restores mana to full, a fee per point, and blesses (`blessed`, a player
  slot: `*bless-time*` seconds of play in which blows do `*bless-scale*`, `blessing-scale` in
  `hurt-player`; carried down the stairs). Its button says what it does, and while it lasts the
  HUD shows it among the status icons (`src/status-icons.lisp`), a gold cross with the seconds left.
- **Trainer**: raises the player's `max-health`, `max-mana` and `max-stamina` (player slots that
  replaced the globals, which are now their starting values), `*training-steps*` at a time,
  `*training-limit*` steps each, each dearer by `*training-step-cost*`.
- **Quest-giver**: one quest into the wing, drawn the first time asked (`ensure-quest`): bring back
  the relic (a `quest-pickup` on the wing's furthest free spot, placed before the glyphs so they
  can't take the wing's last ones, hidden until the quest is taken; touched, it goes into the bag
  as the `:relic` item, the reliquary, and the claim takes it back out),
  a bounty on the wing's commonest monster (`bounty-target`, progress counted from the dead), or,
  besieged, hold the gates through `*gate-raids*` raids. Claimed back in town for gold and
  `*quest-reputation*`.

`price` is `*base-prices*`, `*price-depth-step*` dearer per depth, by the faction's multiplier and
`(1 - standing / 400)`. **Gold** (`gold`, a player slot) comes from `:gold` pickups, which
`place-gold` scatters on the spots health, mana, the relic and the glyphs left (`*gold-per-monster*`,
on at most `*gold-spot-share*` of them but one at least, since arcane dust comes after and its piles
grow to fill fewer spots), in piles of `*gold-pile*` coins (`pickup-count`, as dust's; bigger where its
share of spots is too few, so a level gets its whole budget: 200 to 370), and from
kills (`*kill-gold*` by class, straight into the purse through `creature-died`), both
`*gold-depth-step*` more per depth (`gold-scale`). **Reputation** (`reputation`, a plist by faction,
-100 to 100) moves prices, greetings and the watch's patience (`*patient-reputation*`).

**The watch** (`report-crime`): `hurt` and `burn` take `:by` (who struck, through `harmed` and
`creature-died`), so a blow by the player at one of the townsfolk is an assault and a killing a
murder (blows at one of them within `*assault-window*` of the last, a burn's ticks among them, are
one assault: `last-assault`). Crimes weigh 1 (a broken rule), 2 (assault) and 3 (murder) toward `settlement-strikes`: from 1
the watch warns (`hud-say`), from 2 it fines (`*fine-base*` a strike, by depth) and the nearest guard
walks over to ask (`send-for-fine`; pay, refuse, or bribe the Free Company at `*bribe-share*`), and
from 3, a murder, a refusal or `*fine-time*` unpaid, every guard turns on the player
(`watch-turns-hostile`) until paid or bribed off (`calm-watch`; E on a hostile Free Company guard).
The last guard dying sacks the town (`sack-town`): by the player, `*sack-reputation*` off and the
trainer fights; by monsters, nothing worse.

**Fighting a foe** (creature.lisp): a creature with a `foe` (a creature) and not hunting the player
walks to it and attacks it with its own blow or spell (`fight-foe`; `release-attack` and
`face-attack-target` have `:around` methods, and a foe attack never lunges). A monster struck by
one of the townsfolk takes it as its foe, and a townsperson who can fight takes the monster that
struck it. The `settlement-director` (on every level, for the prompt; the rest only in the
settlement, at `*director-step*`) has free guards take on monsters up to something in town
(`guards-watch`), and while besieged sends 2 or 3 of the wing's nearest `*raid-classes*` at the
guards every `*raid-interval*` (`start-raid`, `run-siege`; `raids-held` counts the ones beaten off).
Only plain fighters raid: a flyer's, caster-boss's or leaper's attack assumes the player.

A save keeps the settlement's build (faction and condition, `:settlement :built`), its state
(`saved-slots`: strikes, fine, stock, training, quest, raids, ...), the townsfolk's `provoked`,
every creature's `foe`, and the level's entry in the run (`:level`), so a load builds the same town.
To try it: `(progn (setf *settlement-override* (list :depth 1)) (game (start-game)))`, then
`(game (start-talk (find-if (lambda (c) (typep c 'priest)) *creatures*)))`, `(game (setf (raid-timer
*settlement*) 0.05))` for a raid, `(game (hurt <commoner> 3 :by *player*))` for the watch.
`tools/hd status` shows the settlement.

The town's plans are drawn by `tools/town_plan.py` (its quarters, townsfolk, spawns and loot spots;
it rewrites the blueprint from `plan 0` on, the legend staying hand-written), and a passage in it
must stay 1.5 m wide, as in caves: the barracks' beds once left 1 m gaps and stranded the guard
between them. The temple's dais carries the Spellforge's altar (`a`, 0.7 m over the dais so E
reaches it from the step in front, within `*altar-height*`), and E there opens the forge; using it
is never a crime, the Ashen Temple's rule hooking `player-cast` only. The settlement's level has no
altar room (`:altar-chance` NIL in `*settlement-level*`).

The townsfolk are one generated lineup, `art/townsfolk/lineup-1.png` (`art/prompts/townsfolk-lineup.txt`,
the imp's and acolyte's turnarounds as references), sliced at the monsters' 64 px per metre (each
sprite's height is its cell's, `/ 64`); only the four who stand are used from it now. The walkers
were made the monsters' way (see "Monster sprites") from their lineup cells (`art/<who>/design.png`,
`<who>` being `guard`, `townsman`, `townswoman`): a turnaround (`art/prompts/<who>-turnaround.txt`,
the design, the imp's and acolyte's turnarounds as references), its standing cells cut by
`tools/cut_stands.py`, then `tools/gen_monster_views.sh <who> <anim> ...` for the walk, flinch and the
guard's attack, and a front-only death. Sliced so the standing figure is 118 px (the townsman), 114
(the townswoman) and 124 with the spear's tip (the guard, whose tabard is pure green until it is
recoloured per faction: every strip, into `data/sprites/guard/<faction>/`). A strip's height in
metres is its cells' over 64 (`strip-height`). The image service refused the townsman's flinch as
"self-harm" while it said he clutched his middle. The relic is `art/relic/relic.png`
(`art/prompts/relic.txt`), and the gold pile is drawn (`tools/draw_gold.py data/sprites/pickups/gold`):

```bash
python3 tools/slice_frames.py art/townsfolk/lineup-1.png data/sprites/townsfolk --pixel 3.9 --filter box --anchor bottom shopkeeper:1 priest:1 trainer:1 quest-giver:1 && rm data/sprites/townsfolk/{commoner-*,guard}.*
tools/cut_stands.py art/guard/turnaround-2.png art/guard    # and townsman/turnaround-2, townswoman/turnaround-1
python3 tools/slice_turnaround.py art/guard/turnaround-2.png data/sprites/guard/turnaround --height 124 --filter box
python3 tools/slice_turnaround.py art/townsman/turnaround-2.png data/sprites/townsman/turnaround --height 118 --filter box
python3 tools/slice_turnaround.py art/townswoman/turnaround-1.png data/sprites/townswoman/turnaround --height 114 --filter box
V="front front-quarter side back-quarter back"
for spec in guard:992:walk:20 guard:992:attack:20 guard:992:hurt:10 townsman:944:walk:20 townsman:944:hurt:10 townswoman:912:walk:20 townswoman:912:hurt:10; do IFS=: read who h a n <<< "$spec"; python3 tools/slice_views.py data/sprites/$who $a:$n $(for v in $V; do echo art/$who/$a-$v.png; done) --height $h --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
python3 tools/slice_frames.py art/guard/death.png data/sprites/guard --pixel 3.5 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/townsman/death.png data/sprites/townsman --pixel 3.73 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/townswoman/death.png data/sprites/townswoman --pixel 3.86 --anchor bottom --filter box death:8
G=data/sprites/guard; for f in ashen-temple:30:0.25:0.55 deepwardens:212:0.7:0.55 free-company:355:0.75:0.6; do IFS=: read n h s v <<< "$f"; mkdir -p $G/$n; for strip in turnaround walk attack hurt death; do tools/recolor_hue.py $G/$strip $G/$n/$strip --from 120 --reach 30 --hue $h --saturation $s --value $v; done; done
python3 tools/slice_frames.py art/relic/relic.png data/sprites/pickups --pixel 14 --filter box --colors 32 --anchor bottom relic:4
```

Not yet: the trainer, who fights once the town is sacked, has no walk, attack, flinch or death
strips (it glides, strikes standing and sinks into the floor), townsfolk have no voices, there are no faction banners, the town is one lighting room, and nothing is
stolen but from a dead shopkeeper.
