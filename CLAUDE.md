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
generates a new level (`start-game`); Debug level plays the greybox test level, where the
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

## Standalone build

```bash
tools/build-dist
```

Builds the game into `dist/` (gitignored), about 200 MB: `hexmaw`, the executable,
the native libraries it loads (GLFW, evdev), and `pool/` with the assets: `pool/hexmaw/`
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
  animations), `*creatures*` for hit tests, bodies (collision between actors), and the `imp`. A creature's
  `death-animation` plays once on death, front view from every angle, and its last frame
  stays as the corpse until revival; without one it collapses into the floor. Every hit
  flashes, knocks back and hit-stops, but only a pain roll makes it flinch and break off
  its walk or attack (`pain-roll-p`, from `*roll-random*`): its `pain-chance` (percent:
  knight 15, ogre 17, skeleton 40, acolyte and harpy 50, imp 60, necromancer 70) plus the weapon's
  bonus (`*sword-pain-bonus*` 0; a spell's `:pain-bonus`, the bolt's 10), at most
  `*max-pain-chance*` (75), so nothing can be held in its flinch. A killing blow and
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
- `src/flyer.lisp`: `flyer`, a creature that keeps to the air, and the `harpy`. See "Flyers"
  under "Creature movement" below. Creature code reaches it through generics with a
  walker's default: `keep-height` (settle, or hover, dive and fall), `move-lift`,
  `ranged-p` (hunt from range) and `attack-step` (the blow, or the dive).
- `src/necromancer.lisp`: the `necromancer` and the skeletons it raises (`skeleton-warrior`:
  Trial already has a `skeleton`, for skeletal animation). See "The necromancer" under
  "Creature movement" below. A creature with several attacks has `ability` objects (frame
  times, hit frame, animation, spell, pause, cooldown); its attack readers
  (`attack-frame-times`, `attack-animation` and the rest) are methods answering for the
  current one, so `attack` runs any of them, and `release-attack` (what lands on the hit
  frame), `face-attack-target` (what it turns to through the wind-up) and `hunt-from-range`
  are generics with the caster's behaviour as the default.
- `src/ogre.lisp`: the `ogre`, the big one (2.7 m, `body-radius` 1.0), which leaps and pushes
  the player around. See "The ogre" under "Creature movement" below.
- `src/blocks.lisp`: level blocks from glTF (`find-block`, `place-block`, `attach-block`,
  `seal-connector`); see "Level blocks" below.
- `src/blueprint.lisp`: builds blocks from text blueprints (`data/blueprints/*.txt`), in its own
  system `hexmaw-blueprints` (no Trial) so `tools/blueprint` starts in a second; see
  "Blueprints" below.
- `src/kit.lisp`: the kit (`kit-blocks`, every `.glb` in `data/blocks/`) and the gallery level
  that lays it out (`build-kit-gallery`, `kit-goto`).
- `src/generate.lisp`: the level generator (`generate-level`); see "Generated levels" below.
- `src/save.lisp`: saving and loading generated runs, one file per slot in `*save-directory*`
  (`$XDG_DATA_HOME/hexmaw/saves/`, usually `~/.local/share/hexmaw/saves/`:
  `slot-1.sav` .. `slot-3.sav`, `quick.sav`). A save doesn't store the level: it keeps the
  seed and the generator's settings (`*saved-generator-settings*`), and the level's cells
  (`level-layout`) to check that the rebuild is the same level; one built from changed blocks
  isn't, and its save then starts fresh, with a warning. What it stores is everything that
  changes in play, so a load is the moment of the save, nothing in flight lost: the player,
  every creature by its index in `*creatures*` (raised skeletons recreated), every effect in
  the scene (projectiles, circles, impacts, with their glows), the blood pool's arrays,
  `*hit-stop*` and the random states. Damage and knockback roll from their own state
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
  many metres as m/s when they let go, and tops out near 12 m/s; in the air nothing slows them
  (air control steers but never brakes below the current speed, on any floor), so a run-up on
  ice jumps further. Creatures skid too: their `momentum` (a blow's knockback, and on ice their
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
  projectile delivery, the player's `bolt`, the acolyte's `cinder` and the necromancer's
  `grave-skull` and `grave-spikes`. A new effect kind is a method on `apply-effect`, for a
  `creature` target and (in player.lisp, loaded later) a `player` one; where the effect came
  from and which way it pushes are `effect-origin` and `effect-direction` of its source (the
  projectile, or the circle). A projectile hits any live creature or the player except its
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
  sorting against other glows; it draws both faces. Every
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
- `src/hud.lisp`: HP and mana bars in the lower-left corner, an AIR bar over them while
  breath is short (`breath-element`; `hud-top` moves up a row with it), and the red pain flash over
  the view (`pain-flash`, from the player's `pain`). HUD pieces are `hud-element`
  entities drawn in pixel coordinates (origin bottom left) at the near plane; place them
  on whole pixels, since a half-pixel position drops an edge row. Overlapping elements
  take a depth in `place` (below 0 is further back). `hud-top` is where the bars end.
  `hud-shown-p` decides whether an element draws (by default, not on the main menu). The
  frame counter (`fps-display`) sits in the upper-left corner while `*show-fps*` is on,
  on every screen, counting frames in its render and updating every `*fps-interval*`.
- `src/menu.lisp`: the main menu and the Esc pause menu, built with Alloy (Trial's UI
  toolkit) in their own pass, blended over the game in `setup-scene`. `*game-state*`
  (`:title`, `:playing`, `:paused`, `:map`, defined in creature.lisp) decides which is up;
  anything but `:playing` makes `frozen-p` true, which stops everything that moves.
  Transitions: `start-game` and `start-debug-level` (both `start-level`: set `*level*`
  to `:generated` or `:test`, put the loading screen up (`:loading`) for
  `*loading-frames*` ticks, then rebuild the scene; `*new-run*` tells `setup-scene` to put
  the new player at the spawn point, fresh, and start play), `pause-game`, `resume-game`, `show-title`,
  `exit-to-title` (the pause menu's exit: back to the main menu, with the level put back
  in place by `reset-run`, no scene rebuild)
  and `exit-game` (quits; main menu only).
  A new menu is a `menu-panel` subclass with `panel-title` and `panel-buttons` (the
  loading screen is one with no buttons). A `panel-buttons` row is `(label action)`, a
  button, or `(label :toggle variable)`, a checkbox (`menu-toggle`) that sets that special
  variable; an action may also be a closure. Hovering a row gives it the keyboard focus, so
  one row is lit at a time. `panel-width` is the column's width (`*menu-width*`; the slot
  panels' is wider, for their labels).
  Settings (`open-settings`, on both menus) covers the menu it came from while
  `*settings-open*` is true; Back or Esc (`close-settings`) returns to it. It has Show
  FPS (`*show-fps*`, in memory only, kept across reloads) and, in a debug version
  (`*debug-version*`), Debug minimap (`*map-debug*`: the automap shows every block, creature
  markers and block names). The main menu's Debug level is also debug-version only.
  Load game (both menus) and Save game (the pause menu, on a generated level only) cover it
  the same way while `*slot-menu*` is `:load` or `:save`: a row per slot in `*save-slots*`
  (1 to 3, then the quicksave), labelled by `slot-info`, and Back (`close-slot-menu`). After
  a save the pause menu's title says where it went (`*save-note*`). F5 quicksaves and F9
  quickloads (`quicksave`, `quickload`, from the menu controller). See `src/save.lisp`.
  `panel-splash` names a picture in `data/splash/` to cover the screen with (the main
  menu's `title`, the loading screen's `loading`, and Settings' over the main menu; see
  "Splash screens" below); NIL, the pause menu's, dims the game behind it instead. `panel-top` places the menu from the top
  of the screen (T, the default, centres it; the main menu's `*title-menu-top*` keeps it
  off the dagger in its splash).
- `src/hands.lisp`: the first-person casting hands, sunk Hexen-style below the bottom
  edge (idle loop, cast, walking sway). Each hand is its own entity drawing half the
  frame, spread apart and closing up where they meet (`*hands-together*`). Scales are
  whole numbers, wider than tall (`*hands-stretch*`). The cast's release frame is timed
  to `*cast-release*`.
- `src/sword.lisp`: the sword and weapon switching. The player holds one weapon (`*weapons*`:
  1 the sword, 2 the casting hands, 3 the spear); switching lowers one off screen and raises the next.
  The sword is a single sprite against the bottom-right corner (its arm runs off that edge,
  so `*sword-overhang*` must exceed the sway). The slash plays `*swing-frame-times*` and the
  blow lands on `*swing-hit-frame*`: the nearest creature within `*sword-reach*` and
  `*sword-arc*`, not behind a wall. The sword's slash and the spear's thrust are both swings,
  through the same `swing-time`: generics on the weapon's keyword give each its timing and blow
  (`swing-frame-times`, `swing-hit-frame`, `swing-reach`, `swing-arc`, `swing-damage`,
  `swing-knockback`, `swing-pain-bonus`), and generics on the sprite which weapon it draws
  for and how its strip is laid out (`held-weapon`, `idle-frames`, `swing-first`, and
  `weapon-aim`, NIL to keep it against the bottom-right corner). Number keys pick a weapon, the mouse wheel cycles
  (`cycle-weapon`). The weapon slots above the HP bar (`weapon-bar`) show one icon per
  weapon in `*weapons*` with its key number, the one asked for framed in gold. Icons are
  frames of `data/sprites/icons/weapons.png` (`*weapon-icons*`), drawn by
  `tools/draw_weapon_icons.py data/sprites/icons/weapons`; a new weapon needs a frame there.
  The left hand holds a shield, a sprite of its own (`shield`, a subclass of `sword`) against
  the bottom-left corner, at the sword's art pixel size (`sword-scale`), so it doesn't slide
  off on screens whose whole-number scale shows fewer art pixels across. It drops and sways
  with the sword. Both draw at `*weapon-depth*`, behind the bars, the weapon slots and the
  pain flash. Holding the right button raises the shield over `*block-raise-time*`
  (`block-raise`, 0 to 1; not during a swing, and it comes down before a weapon switch);
  fully raised, a blow from within `*block-arc*` of the view (`shield-blocks-p`, player.lisp,
  asked by `hurt-player`, so it covers creatures' spells too) does `*block-damage-scale*` of
  its damage and shoves `*block-shove-scale*` as far; a blow with `:guard-break` (the knight's,
  the ogre's slam) also knocks it aside (`break-guard`: down at once, and `guard-broken`
  keeps it down), and `:unblockable` ones (the ogre's shockwave) ignore it. Raised, it slows
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
- `src/player.lisp`: first-person controller and box collision. In water to the waist
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
  pool's others plugged. For now every monster on it is an imp: the hall's six stand where
  the acolyte, knight, harpy, necromancer and ogre did, and the shrine's and pool's are imps
  too (`*spawn-override*`, blocks.lisp, bound around their `attach-block`s). The notes below
  on where those monsters stand describe the level before that. The debug `ice-rink` block
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
damage, a shove, the pain flash, hit-stop). Backing off during the wind-up dodges it, and a
hit breaks the attack off. Then it stands `attack-pause` and hunts on.

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
point-blank when cornered; out of range or sight it closes in as a melee creature does. At zero health the player's run starts over (`reset-run`); there's no death screen yet.

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
and rises `dive-rise` for `dive-windup` (0.7 s, the warning), then flies a straight line at
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
  (spells.lisp). It strikes 2.5 s later whatever happens to the necromancer, so it makes the
  player move, and it hurts the necromancer's own living allies.
- **Grave skull**, otherwise: homing, 6 m/s, turning 1 rad/s.

Its cooldowns run in its tick (`cooldowns`, by name), from when an ability takes effect. Its
spells spare the undead (`spares-p`, `undead`). `reset-run` takes summoned creatures out of
`*creatures*` instead of reviving them, and the test level's revival skips them. On the
test level the necromancer stands at the back of the hall, behind the imp; set
`(setf *revive-time* nil)` so corpses stay down for it, kill the imp with
`(hurt (aref *creatures* 0) 30)` (no overkill: a corpse, not gibs) and set it hunting with
`(setf (alert necromancer) 30.0)`.

### The ogre

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
from `any`, the `hall`'s choice and the high quarter's own spawns; the `cavern`, `balcony`,
`ice-cavern` and `ice-grotto` spawn `any-ogre`, since one there couldn't reach its own
doorways (`check-kit` with `*spawn-pool*` set to only ogres checks every block for it).
Each block fits it, but the way to the start may not (a `stair`, a cave passage, a `narrow`
doorway, the far bank of a river): one stranded there guards its part of the level, and
`check-reachable` warns. On seeds 1 to 20 and 38, 16 levels had ogres, 39 in all, and 3
were stranded.
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
`:beam`, `:sarcophagus`, `:rock`, `:cave-floor`, `:ice`, `:ice-rock`, `:snow`), tinted by
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
`beam` (`timber`) has its grain running along x: a beam turned to run along z shows the
grain across its underside.

A re-made PNG is picked up by reloading greybox.lisp (`tools/hd reload src/greybox.lisp`),
not by `tools/hd reset`.

## Splash screens

The main menu and the loading screen draw a picture over the whole window
(`splash-backdrop` in menu.lisp), cropped to cover it, with nearest filtering and a dark
veil (`*splash-dim*`, 0.6) so it stays in the background. Each is a generated 1536 × 1024 picture: `art/prompts/splash-common.txt`
(16:9 crop, no text, a calm dark centre for the menu) plus `splash-title.txt` or
`splash-loading.txt`. The title references the four monsters' turnarounds, the loading
screen the imp's turnaround, the stone wall and the torch:

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
top frame being the hovering pose, and `--grid` makes `stack_views.py` read each sheet as one
row; the other views follow `flap-front-c-1.png` with `harpy-flap-follow.txt`. The grid's two
rows are drawn apart, so each frame stands on its own lowest pixel: the bottom of the stroke,
whose wingtips hang below the talons, lifts the body a little.

```bash
python3 tools/stack_views.py art/harpy/dive-sheet.png art/harpy/dive-front-2.png art/harpy/dive-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --blank 1
python3 tools/slice_frames.py art/harpy/dive-sheet.png data/sprites/harpy --pixel 8 --anchor bottom --filter box dive:10
python3 tools/stack_views.py art/harpy/flap-sheet.png art/harpy/flap-front-c-1.png art/harpy/flap-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --grid
python3 tools/slice_frames.py art/harpy/flap-sheet.png data/sprites/harpy --pixel 8 --anchor bottom --filter box flap:20
```

Its flinch (`harpy-hurt-common.txt`, jolt then stagger) is made like the dive, the side and back
views following `hurt-front-1.png`:

```bash
python3 tools/stack_views.py art/harpy/hurt-sheet.png art/harpy/hurt-front-1.png art/harpy/hurt-{front-quarter,side,back-quarter,back}.png --height 928 --frame 1 --blank 1
python3 tools/slice_frames.py art/harpy/hurt-sheet.png data/sprites/harpy --pixel 8 --anchor bottom --filter box hurt:10
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
python3 tools/stack_views.py art/knight/runic-block-sheet.png art/knight/runic-block-front-2.png art/knight/runic-block-front-quarter-2.png --height 1000 --frame 1 --blank 1
python3 tools/slice_frames.py art/knight/runic-block-sheet.png data/sprites/knight --pixel 8 --anchor bottom --filter box block:4
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
K=art/knight; for a in walk attack hurt; do python3 tools/stack_views.py $K/runic-$a-sheet.png $K/runic-$a-front-1.png $K/runic-$a-front-quarter-b-1.png $K/runic-$a-side.png $K/runic-$a-back-quarter.png $K/runic-$a-back.png --height 1000 --frame 1 --blank 1; done
python3 tools/slice_frames.py art/knight/runic-walk-sheet.png data/sprites/knight --pixel 8 --anchor bottom --filter box walk:20
python3 tools/slice_frames.py art/knight/runic-attack-sheet.png data/sprites/knight --pixel 8 --anchor bottom --filter box attack:20
python3 tools/slice_frames.py art/knight/runic-hurt-sheet.png data/sprites/knight --pixel 8 --anchor bottom --filter box hurt:10
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
for a in walk cast thrust hurt; do python3 tools/stack_views.py art/necromancer/$a-sheet.png $(for v in $V; do echo art/necromancer/$a-$v.png; done) --height 1024 --frame 1 --blank 1; done
for a in walk:20 cast:20 thrust:20 hurt:10; do python3 tools/slice_frames.py art/necromancer/${a%:*}-sheet.png data/sprites/necromancer --pixel 8 --anchor bottom --filter box $a; done
for a in walk attack hurt; do python3 tools/stack_views.py art/skeleton/$a-sheet.png $(for v in $V; do echo art/skeleton/$a-$v.png; done) --height 920 --frame 1 --blank 1; done
for a in walk:20 attack:20 hurt:10; do python3 tools/slice_frames.py art/skeleton/${a%:*}-sheet.png data/sprites/skeleton --pixel 8 --anchor bottom --filter box $a; done
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
on the floor. In the side, back-quarter and back leap sheets the crouch's maul reached across
the cyan line into the airborne cell, and the airborne frame carried it: the stray pieces
were painted magenta in `art/ogre/leap-{side,back-quarter,back}.png`, so look at a sheet's
cells for a neighbour's pieces before stacking.

```bash
python3 tools/slice_turnaround.py art/ogre/turnaround-2.png data/sprites/ogre/turnaround --height 173 --filter box
V="front front-quarter side back-quarter back"
for a in walk slam leap hurt; do python3 tools/stack_views.py art/ogre/$a-sheet.png $(for v in $V; do echo art/ogre/$a-$v.png; done) --height 1384 --frame 1 --blank 1; done
for a in walk:20 slam:20 leap:15 hurt:10; do python3 tools/slice_frames.py art/ogre/${a%:*}-sheet.png data/sprites/ogre --pixel 8 --anchor bottom --filter box $a; done
python3 tools/slice_frames.py art/ogre/death.png data/sprites/ogre --pixel 2.6 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/ogre/dust.png data/sprites/ogre --pixel 4.3 --anchor bottom --filter box dust:6
```

Its `define-fx-animation` sizes are the strips' cell heights over the turnaround's 173 px.

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
  banks), `connector_high_north` a `high` (7 × 4.5 m, two cells: the high blocks'),
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
  empty's −Z; empties named `torch_<anything>` a torch whose flame stands there
  (`add-torch` stands it off the nearest wall).
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
or south wall and 3 rows on an east or west one. Nothing inside a block can be thinner
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
door-kind doorway, which must be on that side's border, `T` a torch at 2.4 m (on a
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
and `spawn MONSTER FACING`, where MONSTER may be a choice, `imp|knight`, or `any`
(one of `*spawn-pool*` by weight: imp 3, acolyte, knight, harpy, necromancer and ogre 1
each), or `any-ogre` (the pool without those after the dash, `|` between them: a block too
tight for them, as the `cavern` and `balcony` are for the ogre), picked as the
block is placed (`spawn-choice`, from `*block-random*`, which the generator binds to its
own state). They combine with commas: `I box 0 0.8 dais, spawn acolyte south` stands the
acolyte on the dais. Each connected group of one spawn character
is one monster at its centre, so `ii` centres one on a 1 m spot. Characters with the same
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
niche 2 m wide: a 1 m one was too tight for a creature's nav cell, so it never left),
`arch` (beams and torches, the way into a room), `narrow` and `narrowing` (to a narrow
doorway); stairs `stair` (one storey, 1 × 2 cells) and `tower` (a switchback, 2 × 2);
rooms `cell`, `chamber`, `shrine` (dais), `hall` (pillars, a knight, acolyte, harpy, necromancer or ogre), `crypt`
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
its only way). A block with a stream doorway is checked wading (it can't be crossed dry),
one with an underwater doorway swimming (`*nav-hazards*` `:swim`), the rest dry, so a wide
river's or canal's banks still walk dry; a check starts at a doorway on dry floor. Leave passages at least 1.5 m wide: the nav
grid's 0.5 m cells need a cell centre 0.3 m clear of rock for the player, and a 1 m gap
beside a column had none.

High blocks are at least two storeys (`storeys 2`, plan 1 open but for its walls, 9 m
inside), so whatever a high doorway opens onto has the height; at 4.5 m its lintel stays in
storey 0. Their tiers rise 2.5 m, the ogre's highest leap. A pillar the full height is `box 0
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
stands the player outside one. Upper storeys are only reachable by moving the player there.

## Generated levels

The main menu's Start game builds one; `(setf *level* :generated)` and a reset do too
(`generate-level`):
it starts in a block tagged `start` (the player and `*spawn-point*` at its centre, and no
monster spawns within `*start-clearance*`, 16 m, of it: a neighbour's monster looking
through the start room's doorway charged the player the moment the level began;
`*spawn-clearance*` holds the point while the level is built, and the spawn's random
choice is still made, so a seed builds the same level), keeps a frontier of open doorways, and picks one at a time:
from a room it adds a corridor or stair, from a corridor another corridor (less likely the
longer the run, `*corridor-run*`) or a room, by weight, trying each of the block's
doorways of the same kind turned to face it until one fits in free grid cells
(`*generator-storeys*` bounds how high and low). A doorway that meets an open one joins
it, which makes loops; one that runs into another block's wall is plugged, as is every
doorway still open at the end. It stops at `*generator-rooms*` rooms. `*level-seed*` fixes
the seed (NIL picks one); `*last-level-seed*` is the last level's, and
`(level-map)` prints its cells a storey at a time. The generator draws from its own random
state, since monsters use `random` as they spawn. `*generator-blocks*` limits the blocks it
uses (NIL: every block with tags). A doorway left opening onto nothing is a bug and logs a
warning. Two doorways that meet share one portal (`drop-portal` removes the other), since
the shader takes only 32. A stair still open when the rooms are in gets one more piece,
so no stair ends in a plug.

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
flooded run's as `=` and a canal's as `-`. On seeds 1 to 30, 19 levels had a canal and 4 a
flooded run of 4 or 5 blocks. On seeds 1 to 20, 9 levels had a high quarter, of 1 to 6 blocks; 4 of them had an arm end in a
plug, since the vault, 4 × 4 cells and two storeys, is the only end and often doesn't fit.

Rivers: a river is the blocks joined through `river` and `stream` doorways. The first river
block comes in like any corridor or room, through an ordinary doorway (river pieces are
tagged `river` as well as `corridor` or `room`, ends `river-end` and `room`), and starts a
river with a target length of `*river-length*` blocks (5 to 9) shared by its arms. Its open
river doorways are tried before any other (`next-door`): with pieces until the river has
its length, then only ends (one river doorway and ordinary doorways onward), an end still
tried ahead of a plug when no piece fits, and at the room quota every open arm gets its end.
So an arm ends in an end block, in a join with another river doorway, or, if nothing fits,
in a plug, and the dungeon carries on from the ends and the pieces' side doorways. After
`*max-rivers*` (1) rivers, river blocks leave the ordinary choices. `(level-map)` draws
river blocks as `~`. A river's two banks meet only at its
ends and crossings (fords, the cavern's bridge), so ends join both banks; a stream has
no banks, so a river that narrows is waded from there on, and the dungeon past it is
reached through lava. On 20 seeds, before
the high quarter, every level had one river of 7 to 11 blocks, and the player walked seed
11's 92 m along a bank; with it, seed 12's river is one block, ending in a plug.

Ice: the ice caves are a frozen wing of the caves. Their doorways are all of kind `ice`, so
they join only each other and the ice gates, and a gate's rock side joins only a block tagged
`cave` and not `lava` (`gate-allowed-p`: in `try`, and when two doorways meet face to face),
so the way into the ice is always a rock cave, a gate, then ice. An ice doorway that fits no corridor tries the rooms too
(few blocks have one), the first piece through a gate isn't another gate, and a gate doorway
still open at the room quota gets a room, ice or cave. `check-ice-joins` warns about any join
against the rule after every generated level. Over seeds 1 to 100, 17 levels had an ice gate,
and all 25 of their gates led into the ice. The generator asks every block's tags and weight
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

Controls: click the window to capture the mouse, Esc to pause (release the mouse, open
the pause menu) and Esc again to resume. WASD, Shift to run,
Space to jump, C or Ctrl to crouch (in water: W swims where you look, Space up, C or Ctrl
down; swim into a ledge at the surface to climb out), 1 for the sword, 2 for the casting
hands and 3 for the spear (or the mouse wheel to cycle them), left click to
attack (swing, thrust, or cast the bolt), right button held to raise the shield (sword only; a left
click while it's up bashes), M for the automap (see `src/map-view.lisp`), F5 to quicksave
and F9 to quickload (generated levels only), F12 for a screenshot.

To test combat without the mouse: `tools/hd '(game (player-cast *player* (quote bolt)))'`
starts a cast, and the bolt leaves from the player's view `*cast-release*` (0.2 s) later,
on the hands' release frame; `(select-weapon *player* :1)` then `(player-attack *player*)` swings the sword (the blow lands
0.23 s in; stand within 2 m of the imp, facing it), and with `:3` thrusts the spear (0.24 s in, within 3.5 m); `(setf (block-raise *player*) 1.0)` under hit-stop
shows the raised shield, and with it raised `(player-attack *player*)` bashes (`block-held`
is what the right button sets; without it the shield comes down again once the world runs); `(hurt (aref *creatures* 0) 0)` triggers a hit reaction and a spray of blood (100 kills, and tears an imp apart; `:from point` aims the spray); to look at one death
frame, `(setf *hit-stop* 1000.0)` freezes the world and `(setf (dead imp) 0.35)` shows the
frame at that time; likewise `(setf (brain imp) :attacking (attack-time imp) 0.6)` shows an
attack frame (the blow lands 0.5 s in), and `(setf (alert imp) 6.0)` sets an imp hunting (the acolyte on the platform the same way);
`tools/hd status` shows mana and each creature's health. The knight stands by the west
pillars; a bolt at its front comes back at the player, one at its back hurts it, and
`(setf (brace knight) 0.25)` (impact) or `0.1` (brace) under hit-stop shows a block frame.
The harpy hovers over the hall's south-east, by the east doorway: `(setf (alert harpy) 6.0)`
sets it hunting, and `(dive-left harpy)` is non-NIL while it dives (hurt it then to down it).
The ogre stands in the hall's east: `(setf *leap-debug* t)` and `(setf (alert ogre) 30.0)` with
the player 4 to 12 m from it, and the log says where it leaps and what the shockwave hits;
`(airborne ogre)` is true in the air, and `*hit-stop*` 1000 then freezes it there.
`(issue (scene +main+) 'mouse-scroll :delta -1.0 :pos (vec2 0 0))` inside `(game ...)` turns
the wheel one notch down (next weapon).
