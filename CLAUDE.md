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
| `tools/hd status` | Player position and view, runtime errors firing now |
| `tools/hd screenshot` | Saves the current frame, prints the PNG path. Read it to check visual changes |
| `tools/hd errors` | Recent runtime errors with backtraces |
| `tools/hd reset` | Rebuilds the scene from `setup-scene`; the player keeps position and view |
| `tools/hd reload-system` | Reloads everything through ASDF (after changing a macro or the .asd) |
| `tools/hd '(form)'` | Evaluates a form in package `hexmaw` on the server thread |

Wrap anything that changes the scene, entities or GL state in `(game ...)` so it
runs on the game thread between frames, for example
`tools/hd '(game (respawn *player*))'`. Reads such as `(feet *player*)` don't need it.

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
- Something spawned mid-game (projectiles) needs `(preload 'class scene)` in
  `setup-scene`, or its shader isn't loaded when it first appears.
- A subclass's `define-handler` replaces the parent's handler for that event. Use a
  qualifier, as in `(define-handler (creature tick :after) ...)`, to add to it.
- Changing a macro or an inline function: run `tools/hd reload-system` so callers
  recompile.
- Shader code (`define-class-shader`) refreshes automatically on reload.
- Trial shadows some CL symbols with its own generics, `load` among them. Use
  `cl:load` for files.

## Per-frame code

Tick handlers and render methods run 100 times a second. Avoid allocating in them:
no `vec`/`v+`/`list` per frame. Mutate existing vectors with `(setf (vx v) ...)`,
`nv+`, or reuse preallocated ones. SBCL's GC pauses show up as hitches.

## Layout and conventions

- `src/dev.lisp`: eval server, reload, runtime-error guard, screenshots. Dev only.
- `src/greybox.lisp`: untextured level geometry (`greybox` entity, fog, `add-box`, `*solids*`).
- `src/sprite.lisp`: Doom-style `billboard` sprites (view by angle, mirroring, tint).
  Assets live in `data/` (Trial pool `hexmaw`).
- `src/creature.lisp`: `creature` (health, hit reaction: flash, flinch, knockback, hit-stop;
  death and revival), `*creatures*` for hit tests, and the `imp`.
- `src/spells.lisp`: the composable spell model (`define-spell`, effects, `spell-cost`),
  projectile delivery, and the `bolt`. A new effect kind is a method on `apply-effect`.
- `src/player.lisp`: first-person controller and box collision.
- `src/level.lisp`: the greybox test level.
- `src/main.lisp`: `main`, `setup-scene`, `status`, `launch`, `dev-launch`.

Units are metres, +Y is up, and the player spawns at `*spawn-point*` facing −Z
(north). Collision is axis-aligned boxes in `*solids*`, resolved one axis at a time.
A walking player steps up and down ledges of up to `*step-height*` (0.45 m); anything
taller needs a jump (0.45 m is also the most a block can rise per step in level design).
On a step the camera holds its height and eases to the new one.

To test movement without a mouse or keyboard, hold keys from the eval server:
`tools/hd '(game (setf (vy (rotation *player*)) 0.0 (retained :w) t))'`, wait, then
`(setf (retained :w) nil)` and check `tools/hd status`. Yaw 0 faces −Z, π/2 faces +X.

## Monster sprites

A monster starts as a 5-view turnaround sheet (front, front-quarter, side,
back-quarter, back; magenta background, cyan separators). `tools/slice_turnaround.py`
keys and slices it into `data/sprites/<monster>/turnaround.png` plus a `.lisp` index:

```bash
python3 tools/slice_turnaround.py "Pixel Demon Character Turnaround.png" data/sprites/imp/turnaround --height 96 --mirror back-quarter
```

The game assumes the three turned views face image-left and mirrors them for the
other side. Generated sheets aren't always consistent (the imp's back-quarter faced
right), so look at each view and pass the odd ones to `--mirror`. To check angle
selection in game, orbit the camera around the sprite and screenshot each 45°.
Billboards have no collision yet.

Controls: click the window to capture the mouse, Esc to release. WASD, Shift to run,
Space to jump, C or Ctrl to crouch, left click to cast the bolt, F12 for a screenshot.

To test combat without the mouse: `tools/hd '(game (player-cast *player* (quote bolt)))'`
fires from the player's view; `(hurt (aref *creatures* 0) 0)` triggers a hit reaction;
`tools/hd status` shows mana and each creature's health.
