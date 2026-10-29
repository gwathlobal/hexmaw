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

## Layout and conventions

- `src/dev.lisp`: eval server, reload, runtime-error guard, screenshots. Dev only.
- `src/greybox.lisp`: level geometry (`greybox` entity, fog, `add-box`, `*solids*`), its
  textures and surfaces (see "Level textures" below), and `lit-entity`, the shader mixin
  whose `light_at` lights the level and billboards from the `lamp-block` uniform buffer.
- `src/lights.lisp`: point lights (`lamp`s in `*lamps*`, which `build-level` empties).
  `add-torch x y z` places a `torch` whose flame stands on y, `*torch-stand-off*` out from
  the nearest wall within `*torch-wall-reach*` (`wall-near`), with a flickering lamp in the
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
  stays as the corpse until revival; without one it collapses into the floor. The `acolyte`
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
  The block strip has only the covered views. The sword isn't stopped. `turn-speed`
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
- `src/blocks.lisp`: level blocks from glTF (`find-block`, `place-block`, `attach-block`,
  `seal-connector`); see "Level blocks" below.
- `src/blueprint.lisp`: builds blocks from text blueprints (`data/blueprints/*.txt`), in its own
  system `hexmaw-blueprints` (no Trial) so `tools/blueprint` starts in a second; see
  "Blueprints" below.
- `src/kit.lisp`: the kit (`kit-blocks`, every `.glb` in `data/blocks/`) and the gallery level
  that lays it out (`build-kit-gallery`, `kit-goto`).
- `src/generate.lisp`: the level generator (`generate-level`); see "Generated levels" below.
- `src/liquids.lisp`: liquids, lava for now (water will be another kind). A liquid is a box of
  volume in `*liquids*` (`build-level` empties it), never a solid: it fills a sunken pit
  whose floor is an ordinary solid `*lava-depth*` (0.4 m, under a step) below the floor
  around it, its surface `*lava-surface*` (0.1 m) below, so walking in and out is a step
  down and up and the feet sink. Everything else asks `liquid-at x y z`. `*liquid-kinds*`
  says what a kind does: `:damage` per second, paid every `*lava-tick*` by the player
  (`hurt-player ... :shove NIL`: the pain flash, no shove or hit-stop) and by creatures
  (`burn`: a flash, no flinch or blood; one standing in it walks to the nearest dry cell,
  `escape-liquid`), `:speed` on the player's walk, and `:glow`, the lamps `add-liquid`
  hangs `*glow-height*` over it. The nav grid flags each cell under lava (`nav-hazard`), and
  `*nav-hazards*` says what the nav questions make of it: `:avoid`, the default, keeps out
  (so wandering, retreat, `show-nav` and `check-reachable` stay dry, and a generated level
  always has a dry way); `:wade` lets a path through at `*nav-wade-cost*` (3) times the
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
- `src/fx.lisp`: animated camera-facing effect sprites (`fx-sprite`, `spawn-fx`); fullbright,
  no fog. Projectiles are effect sprites.
- `src/gore.lisp`: blood. `hurt` takes `:from`, the point the blow came from (the sword
  passes the player's feet, a projectile its flight; NIL means the player), and `bleed`
  sprays drops from the wound away from it, `*blood-back-spray*` of them back toward the
  attacker, `*blood-per-damage*` per point within `*blood-drops*`. A death adds `bleed-out`,
  a burst every way (`death-blood`, 0 for the acolyte, which burns; `bleeds` NIL for no
  blood at all). Drops fly under `*blood-gravity*` and stick where they cross a solid's face
  as splats, flat on the floor or a wall (a ceiling only stops their rise). `lay-splat`
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
- `src/hud.lisp`: HP and mana bars in the lower-left corner, and the red pain flash over
  the view (`pain-flash`, from the player's `pain`). HUD pieces are `hud-element`
  entities drawn in pixel coordinates (origin bottom left) at the near plane; place them
  on whole pixels, since a half-pixel position drops an edge row. Overlapping elements
  take a depth in `place` (below 0 is further back). `hud-top` is where the bars end.
  `hud-shown-p` decides whether an element draws (by default, not on the main menu). The
  frame counter (`fps-display`) sits in the upper-left corner while `*show-fps*` is on,
  on every screen, counting frames in its render and updating every `*fps-interval*`.
- `src/menu.lisp`: the main menu and the Esc pause menu, built with Alloy (Trial's UI
  toolkit) in their own pass, blended over the game in `setup-scene`. `*game-state*`
  (`:title`, `:playing`, `:paused`, defined in creature.lisp) decides which is up;
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
  variable. Hovering a row gives it the keyboard focus, so one row is lit at a time.
  Settings (`open-settings`, on both menus) covers the menu it came from while
  `*settings-open*` is true; Back or Esc (`close-settings`) returns to it. It has one
  option so far, Show FPS (`*show-fps*`, in memory only, kept across reloads).
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
- `src/level.lisp`: `build-level`, which builds the level `*level*` names (`:test`, `:gallery`
  or `:generated`), then links rooms and builds the nav grid; and the greybox test level
  (`build-test-level`). A new room or doorway in it needs its `add-room` / `add-portal`, or
  torches light through its walls. Its corridor ends in the `shrine` block. A doorway
  also needs floor under its wall's thickness: without it the nav grid has no cell there,
  and no creature can path through it (the player just steps over the gap), and
  `check-reachable` warns.
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
(`*nav-cell*`), measured a tile of `*nav-tile*` cells at a time against only the solids
near it, and records for each its floor height, headroom and clearance (the widest
body that fits, to 0.125 m, up to 2 m; solids less than 0.45 m above the floor don't count,
so steps aren't walls). A creature fits a cell when clearance ≥ its `body-radius` and
headroom ≥ its `sprite-height`, and moves to a neighbour when the floors differ by at most
its `step-height`, so one grid serves every size. The grid is layered: each 0.5 m column
keeps every floor with room above it, lowest first (a room and the room above it, or a
hall and its roof), so a cell is `i j k`, and stairs join the layers because neighbouring
floors are a step apart. A point is in the layer under it, the highest floor at most
`*nav-layer-above*` above its feet (`nav-layer`, `nav-floor-at x y z`), so anything that
asks about a place passes its height too. A straight walk (`nav-line-clear-p`) must also end
on the floor its target is on, not the one above or below. The geometry questions
go through `floor-candidates`, `ceiling-above` and `fits-at-p`, the only code that knows solids
are boxes. The test level's annex, east of the hall through its east doorway, is a lower room
with an upper room right on top of it and a stair shaft joining them; an imp lives upstairs.

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
along `nav-path-to`, replanned every `*chase-replan*`, as long as the walk is at most
`*chase-max-walk*` (25 m: a room overhead is a long way round by the stairs). A path search
costs a few milliseconds in an open hall, so keep the limit no longer than levels need. Within `*attack-start-reach*` of its
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
itself downs it (`downed`): it falls, lies on the floor for `*downed-time*` and climbs back
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
  corpse twitching (`stirring`) under a growing green lamp; a hit breaks the channel, and it
  tries again later. Released, it tears the corpse apart (`tear-apart`, the gibs as a blow
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

## Level textures

Level faces are textured in world space: every face is axis-aligned, so the greybox shader
lays a texture flat on it by the two world axes in its plane (walls by x or z and y, floors
and ceilings by x and z), at `*texels-per-metre*` (64, the monsters' density). A texture's
pixel size is the ground it covers (256 px, 4 m), its rows start at y = 0, and walls line up
across boxes and blocks without UVs. A **surface** (`*surfaces*`) is three textures: the
sides, the top and the underside, as floors and ceilings are flats in Doom; `add-box` takes
`:surface :wall` (or `:floor`, `:ceiling`, `:pillar`, `:platform`, `:dais`, `:stair`, `:stone`,
`:beam`, `:sarcophagus`), tinted by
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
```

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
  L-shaped object's bounding box is the whole box around it.
- Empties named `connector_<rest>` mark doorways, on the block's outer face, at the middle
  of a cell edge, on a storey's floor. A connector faces out through the face it lies on.
  Its kind is in its name: `connector_narrow_north` is `narrow` (2 × 2.5 m), anything else
  a `door` (3 × 3 m); `*connector-kinds*` lists them, and only one kind joins itself. Light
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

## Blueprints

A blueprint, `data/blueprints/<name>.txt`, draws a block top-down in text; `tools/blueprint`
builds it into `data/blocks/<name>.glb` (`tools/blueprint chamber stair` builds those,
`--check` only checks), and the game builds a block whose blueprint is newer when it
loads it, so after editing one `tools/hd reset` shows it. Errors give `file:line:col`.
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
`<name>-mirror`, flipped west to east, for pieces a turn can't make: `cell`, `tower`) and
`grid free` (skips the grid checks).

Built-in characters: `#` wall (from the storey's floor to the next storey's, or to the
ceiling; on storey 0 down through the floor slab), `.` floor, space open (no floor slab: a drop to the storey below), `n e s w` a
door-kind doorway, which must be on that side's border, and `T` a torch at 2.4 m (on a
border wall it goes just inside the room). Legend actions: `wall [material]`, `floor`,
`open`, `box Y0 Y1 [material]` (solid from Y0 to Y1 above the storey's floor; `top` is the
storey's top), `deco Y0 Y1 [material]` (no collision), `door KIND`, `stairs DIR Y0 Y1
[material]` (the region of that character climbs toward DIR, in risers of at most 0.45 m),
`lava [DEPTH SURFACE]` (that cell's floor slab sinks to DEPTH below the floor, 0.4 by
default, and lava fills it to SURFACE below, 0.1; it can't touch the border), `torch Y`
and `spawn MONSTER FACING`, where MONSTER may be a choice, `imp|knight`, or `any`
(one of `*spawn-pool*` by weight: imp 3, acolyte, knight, harpy and necromancer 1 each), picked as the
block is placed (`spawn-choice`, from `*block-random*`, which the generator binds to its
own state). They combine with commas: `I box 0 0.8 dais, spawn acolyte south` stands the
acolyte on the dais. Each connected group of one spawn character
is one monster at its centre, so `ii` centres one on a 1 m spot. Characters with the same
column merge into as few boxes as possible. No two faces may lie in one plane facing one
way, or they flicker: so a wall gets no floor slab under it, and a wall or full-height box
under a floor slab of the storey above stops 0.5 m short, under the slab. A doorway gets `connector_[<kind>_]<side>`,
numbered `_2` and on when a side has several, lower storey first, and its plug.

The kit: corridors `corridor`, `corridor-long`, `corner`, `tee`, `cross`, `dead-end` (a
niche 2 m wide: a 1 m one was too tight for a creature's nav cell, so it never left),
`arch` (beams and torches, the way into a room), `narrow` and `narrowing` (to a narrow
doorway); stairs `stair` (one storey, 1 × 2 cells) and `tower` (a switchback, 2 × 2);
rooms `cell`, `chamber`, `shrine` (dais), `hall` (pillars, a knight, acolyte, harpy or necromancer), `crypt`
(sarcophagi), `forge` (a lava channel across it, 3 m: a running jump clears it, with a
bridge and banks to every doorway) and `balcony` (two storeys, a ledge all round over an open floor, and a stair
up to it). Every piece must let the player walk between all its doorways (drops don't
count), or the generator builds places that are a one-way trip.

To walk the kit: `tools/hd '(progn (setf *level* :gallery) (reload-scene))'` lays every
block out in two rows, corridors and stairs in front, rooms behind, each with one doorway
open toward the spawn and the rest plugged, on ground that stops at each block's walls
(`add-ground`; under a block it would fill its lava pits), and `(game (kit-goto "chamber"))`
stands the player outside one. Upper storeys are only reachable by moving the player there.

## Generated levels

The main menu's Start game builds one; `(setf *level* :generated)` and a reset do too
(`generate-level`):
it starts in a block tagged `start` (its monsters left out, the player and
`*spawn-point*` at its centre), keeps a frontier of open doorways, and picks one at a time:
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

Every level is checked once built (`check-reachable`, after `build-nav-grid`): the
player must be able to walk from the spawn point to every placed block's doorways, on the
nav grid with the player's size and step (`nav-reached`, which is both ways, since steps
go up as well as down), and every creature must be able to walk to the spawn point at its
own size and step from a cell its body fits where it lives (`stranded-creatures`). Each
doorway or creature that fails logs a warning.

Controls: click the window to capture the mouse, Esc to pause (release the mouse, open
the pause menu) and Esc again to resume. WASD, Shift to run,
Space to jump, C or Ctrl to crouch, 1 for the sword and 2 for the casting hands (or the mouse
wheel to cycle them), left click to
attack (swing, or cast the bolt), F12 for a screenshot.

To test combat without the mouse: `tools/hd '(game (player-cast *player* (quote bolt)))'`
starts a cast, and the bolt leaves from the player's view `*cast-release*` (0.2 s) later,
on the hands' release frame; `(select-weapon *player* :1)` then `(player-attack *player*)` swings the sword (the blow lands
0.23 s in; stand within 2 m of the imp, facing it); `(hurt (aref *creatures* 0) 0)` triggers a hit reaction and a spray of blood (100 kills, and tears an imp apart; `:from point` aims the spray); to look at one death
frame, `(setf *hit-stop* 1000.0)` freezes the world and `(setf (dead imp) 0.35)` shows the
frame at that time; likewise `(setf (brain imp) :attacking (attack-time imp) 0.6)` shows an
attack frame (the blow lands 0.5 s in), and `(setf (alert imp) 6.0)` sets an imp hunting (the acolyte on the platform the same way);
`tools/hd status` shows mana and each creature's health. The knight stands by the west
pillars; a bolt at its front comes back at the player, one at its back hurts it, and
`(setf (brace knight) 0.25)` (impact) or `0.1` (brace) under hit-stop shows a block frame.
The harpy hovers over the hall's south-east, by the east doorway: `(setf (alert harpy) 6.0)`
sets it hunting, and `(dive-left harpy)` is non-NIL while it dives (hurt it then to down it).
`(issue (scene +main+) 'mouse-scroll :delta -1.0 :pos (vec2 0 0))` inside `(game ...)` turns
the wheel one notch down (next weapon).
