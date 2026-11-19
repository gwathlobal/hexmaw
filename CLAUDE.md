# Hexmaw

Hexmaw, a first-person, real-time roguelike (Daggerfall dungeons, Hexen combat), in
Common Lisp on [Trial](https://shirakumo.github.io/trial). The brief is at
https://claude.ai/artifact/MikuSfUo5bY4Au8CHie4XG; what is done and what comes next is in
`ROADMAP.md` (working notes, gitignored, so only in the main checkout), which supersedes the
brief where they differ.

## Running

```bash
./run.sh
```

Opens the game window and an eval server on `127.0.0.1:7171` (`HEXMAW_EVAL_PORT` to
change it). `HEXMAW_SWANK_PORT=4005 ./run.sh` also starts Swank for an editor.
The game opens in a 1280×720 window, or fullscreen when Settings says so;
`HEXMAW_FULLSCREEN=1 ./run.sh` starts it fullscreen. The settings (and so the key bindings)
are read from `settings.lisp` beside the saves (`src/settings.lisp`), which a run of
`./run.sh` shares with every checkout and the build; `XDG_DATA_HOME=/some/dir ./run.sh`
gives it settings and saves of its own, for tests that change them.
It starts on the main menu with the world frozen, the test level behind it. Start game
starts a run of generated levels (`start-game`; see "A run" below); Debug level plays the greybox test level, where the
creatures in development live (`start-debug-level`). `HEXMAW_SKIP_MENU=1 ./run.sh` starts
straight in play on the test level, or run `tools/hd '(game (start-game))'` after launching.
The process exits when the window closes.

Every Lisp session on this project goes through `boot.lisp`:
`sbcl --dynamic-space-size 4096 --no-userinit --load boot.lisp`. Trial needs at
least 2 GB of heap. Dependencies come from the project-local Quicklisp in `.ql/`
(Shirakumo dist, not checked in; `tools/setup-ql` sets it up, with the two dists' versions
pinned there), and ASDF is limited to this folder because other
projects under `~/common-lisp/` ship conflicting copies of Trial's dependencies.

A git worktree (`.claude/worktrees/<name>`) checks out the art from the main checkout's LFS
store (`.git/lfs/` is shared), about 500 MB; `GIT_LFS_SKIP_SMUDGE=1 git worktree add ...`
leaves pointer files in place of the pictures (48 MB in all), for work that doesn't touch art,
and `git lfs checkout art/ogre` there fills in one folder later. It has no `.ql/` of its own: symlink the main
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
`tools/hd '(game (setf (title *context*) "Hexmaw — <conversation name>"))'`.

## Standalone build

```bash
./build.sh
```

Builds the game into `dist/` (gitignored), about 240 MB, on Linux, Windows (under git-bash)
or macOS (`tools/build-dist`): the executable (`hexmaw`, `hexmaw.exe`, or `Hexmaw.app` on
macOS), the native libraries it loads, `pool/` with the assets (`pool/hexmaw/` is `data/`
without the blueprints, beside Trial's own pools and the font cache), and the player's
documents. Copy `dist/` anywhere and run the game from it; it needs no SBCL, Quicklisp or
source tree. It takes about 2.5 minutes, needs `patchelf` on Linux (`apt install patchelf`),
which Deploy uses on the libraries it ships, and builds every block from its blueprint
first, so the shipped `.glb` files are current. The native libraries come prebuilt with
their Lisp libraries, for every platform: GLFW, libmixed (with libsamplerate and pffft in
it), cl-vorbis's decoder (stb_vorbis, though its file is `libvorbis-*`), and on Linux evdev
and cl-mixed's PipeWire plugin; on Windows libmixed brings the MinGW runtime's two DLLs. The
sound server, OpenGL and the gamepad interfaces are the system's. With no sound device Trial
falls back to a dummy output, and the game runs silent.

`asdf:make` does the dumping: `hexmaw.asd` sends it to Deploy's `deploy-op`, with
`dist-main` (`src/dist.lisp`) as the entry point. On macOS `tools/build-dist` runs Deploy's
`macos-app-deploy-op` instead, which copies the SBCL runtime unchanged into
`Contents/MacOS/Hexmaw` and dumps the image beside it as `sbcl.core` (libraries in
`Contents/Frameworks/`, pools in `Contents/Resources/`), then signs the bundle ad hoc
(`codesign -s -`), which Apple silicon needs; there is no developer signature or
notarization. On Windows it builds under a copy of `sbcl.exe` with `data/icon/hexmaw.ico`
written into it (`tools/exe-icon/`, Malgorod's), since `save-lisp-and-die` writes the running
runtime and the icon can't be added after. `data/icon/` is made by `tools/make_icon.py` from
the chosen take in `art/icon/` (`art/prompts/icon.txt`): the `.ico`, the bundle's `.icns`,
and the window's 64 px PNG, set once the window is up (`set-window-icon`, main.lisp, around
two bugs in this Trial's icon setting):

```bash
tools/gen_image.py art/icon/icon.png --prompt-file art/prompts/icon.txt --ref art/splash/maw-1.png --ref art/imp/turnaround.png --size 1024x1024 -n 3
tools/make_icon.py art/icon/icon-2.png data/icon
```

The binary starts on the main menu with no eval server; `HEXMAW_EVAL_PORT=7272 dist/hexmaw`
starts one, so `tools/hd` (given the same `HEXMAW_EVAL_PORT`) can drive a build.
`HEXMAW_FULLSCREEN=1` works as with `run.sh`. With arguments it is Trial's command line
instead (`command-line-toplevel`): `hexmaw version` (`0.1.0-<commit>`, `game-version`),
`hexmaw check` (the critical files under `data/` and every library the build ships can be
opened; `installation-problems`), `hexmaw selftest [--directory DIR]` (the window, the main
menu, a generated level on seed `*selftest-seed*`, a screenshot into DIR, a clean quit; exit
1 on a failure, 2 after `*selftest-timeout*`), and Trial's own `system` and `paths`. `check`
and `selftest` print and save their report as `check.txt` and `selftest.txt` in the user
directory, since `hexmaw.exe` has no console. Trial's own `help` errors in this version
(deploy-command-line's console class).

The user directory (`user-directory`, dev.lisp) is `~/.local/share/hexmaw/` on Linux and
macOS and `%LOCALAPPDATA%\hexmaw\` on Windows (`uiop:xdg-data-home`). A build keeps
everything it writes there: saves (`saves/`), F12 screenshots (`screenshots/`), the reports
and `trial.log` (the boot hook sets `TRIAL_LOGFILE`; Trial would write it beside the
executable, where a player may not be allowed to). In development they stay in the project.
The boot hook works these out on the player's machine, since `*save-directory*` was set on
the build machine. When running a build to test it, set `XDG_DATA_HOME` to a temporary
folder (on Windows too, where uiop reads it first) so it doesn't touch the real one, and start
it from another directory. An error that escapes shows a message box. The 4 GB heap is a
limit kept from the build, not memory used. dev.lisp sets Trial's app name
(`+app-system+`, "hexmaw") as it loads, so Trial's version and paths are Hexmaw's.

A file the game reads at run time goes through `(data-path "sprites/...")`, a path under
`data/`: in the binary it resolves to `pool/hexmaw/`. `root` is the project only in
development (the executable's folder in a build), and ASDF is gone from the binary. In the
binary blocks are never rebuilt (`hexmaw.blueprint:*build-blocks*` is NIL).

The binary is a release version: the build hook sets `*debug-version*` (dev.lisp, T in
development) to NIL, which hides the main menu's Debug level and Settings' Debug minimap.

**What a build ships besides the game** (`*player-documents*`, `hexmaw-documents` deploy hook
in dist.lisp, beside the executable or `Hexmaw.app`): `README.txt` (from
`README-PLAYERS.txt`: running on each system, the controls, where files go, what to send
back), `EULA.txt` (the player's licence: the assets licence's terms in a player's words,
the code's zlib licence left whole, and the LGPL libraries' rights kept), `CHANGELOG.md`,
`THIRD-PARTY-NOTICES.txt`, and `licenses/`: the code's zlib licence, `ASSETS-LICENSE.md`,
the GPL, LGPL, OFL and GCC runtime exception texts, SBCL's `COPYING`, and `lgpl-source/`
with the source of the three LGPL libraries (`*lgpl-systems*`), copied from the versions
dumped. Never the repository's `README.md`, `CLAUDE.md` or `LICENSE` at the top: the release
workflow fails an archive that has them.

**`THIRD-PARTY-NOTICES.txt` is generated**: `tools/notices` writes it from the dependency
tree (every `.asd`'s dependencies, `(:feature ...)` branches included, so one file covers all
three platforms), one entry per release in the pinned dists with its licence text, after
`notices/head.txt` (SBCL, the native libraries, the fonts, the LGPL libraries: written by
hand) and before `notices/native/` (the native libraries' upstream licence texts). A release
with no licence file of its own gets an entry in `notices/overrides.lisp` (copyright and a
standard text, checked by hand). `tools/notices --check`, which CI runs on every platform,
fails when the file is out of date, a release has no licence text, the image loaded a
release the file lacks, or a release is copyleft and not in `*copyleft-allowed*`
(tools/notices.lisp). Three are: text.editing and utilities.print-items (LGPLv3) and
flexichain (LGPL 2.1 or later), which come with Alloy's text input (a hard dependency of
Alloy's core); the build meets their terms by shipping their source and the notices'
rebuild instructions, and the EULA says so. **A new dependency means `tools/notices` again
and a commit of the file; a copyleft one is refused** unless it is added to the allowlist,
`*lgpl-systems*` and `head.txt` with what it requires. Native libraries are in no `.asd`:
one that changes needs `head.txt` and `notices/native/` by hand.

## Releases

`.github/workflows/ci.yml` runs on every push to master and every pull request, on Linux:
the game's own compile (failing on any full warning or error except variables used in a
file loaded before the one that defines them, which it names in a notice), `tools/notices
--check`, `tools/build-dist`, and the build's `version`, `check` and `selftest` under Xvfb
with Mesa. `release.yml` builds all three platforms (`ubuntu-22.04` for an old enough glibc,
`windows-2022`, `macos-15`, Apple silicon), archives each as
`hexmaw-<version>-<platform>.{tar.gz,zip}` (`linux-x86_64`, `windows-x86_64`, `macos-arm64`),
unpacks it elsewhere and runs `version` and `check` from a third folder, and checks the
documents are there and the repository's files aren't (and on Windows the exe's icon). The
self-test must pass on Linux (Xvfb and Mesa) and on Windows, where a runner has only GDI's
OpenGL 1.1, with Mesa's software OpenGL copied beside the exe in the test's copy only (the
MinGW package of `pal1000/mesa-dist-win`: in 26.2.x the MSVC one has no OpenGL driver). On
macOS a runner offers no OpenGL at all, so there it is tried and reported without failing.
The same Mesa files beside `hexmaw.exe` (`opengl32.dll`, `libgallium_wgl.dll`, and
`GALLIUM_DRIVER=llvmpipe`) run the game in a Windows VM with no 3D driver, such as QEMU/KVM's,
slowly; without that variable this Mesa crashes a few seconds in. A build ends its process
with TerminateProcess (`terminate-process`, dist.lisp), after the quit hooks and the log:
any exit through ExitProcess runs every DLL's shutdown, and Mesa's hung there waiting for a
thread already killed, leaving a process Task Manager can't end. With no sound device the game plays silent (`start-sound`, main.lisp), and at quit
the sound server's thread is stopped but its memory isn't freed (`finalize` on
`harmony:server`): freeing it corrupted libmixed's heap on Windows after XAudio2 had failed. Both workflows set up
through `.github/actions/setup-lisp`: SBCL 2.4.10 on Linux, 2.6.9 for the Windows release
(`SBCL_VERSION_WINDOWS`: 2.4.10's image dump there crashed on some commits and not others,
whatever they changed, and 2.6.9's Linux binary needs a newer glibc than ubuntu-22.04's), and
Homebrew's current on macOS, then
`tools/setup-ql` and a cache over `.ql/` and the fasl cache. Checkouts take no LFS: the build
reads only `data/`, and CI fails if the source art isn't pointer files. Third-party actions
are pinned to commits.

**Cutting a release: the version, the changelog and the tag are one act.** `:version` in
`hexmaw.asd` is the source of truth, and a release needs all three to agree:

1. `:version "X.Y.Z"` in `hexmaw.asd`;
2. `CHANGELOG.md`'s newest heading reads `## <Month D, YYYY> vX.Y.Z`;
3. a `vX.Y.Z` tag on that commit, pushed.

`release.yml` fires on `v*` and checks the first two against the tag, failing the run before
it builds on a mismatch. So: draft the player changelog and get it approved (below), then
bump, write the entry, commit, `git tag vX.Y.Z`, `git push origin master`, then `git push
origin vX.Y.Z` (master first, or the release builds a commit the remote doesn't have; the tag
by name, since lightweight tags don't go with `--follow-tags`). The publish job makes a GitHub
Release named "Hexmaw X.Y.Z" with the three archives, its notes the CHANGELOG entry plus
`.github/release-install-notes.md`. **The repository is public, so a tag is public at once**,
and a dispatch run's artifacts can be downloaded by anyone signed in to GitHub: run
`release.yml` by hand (workflow_dispatch: everything but publishing) to get the three builds,
play the Windows one on real Windows hardware before anything is tagged (ROADMAP Phase 1), and
tag after.

**The same tag pushes to itch.io**: the `itch` job, after the release, pushes each archive
unpacked to the `windows-x86_64`, `linux-x86_64` and `macos-arm64` channels of
`gwathlobal/hexmaw` with butler (pinned, fetched from itch's own host), `--userversion` the
version, so butler sends only what changed. Its key, `BUTLER_API_KEY`, is an account-wide
itch API key (its own, not Malgorod's, so either can be revoked alone), in the repository's
`itch` environment, limited to `v*` tags with the author as required reviewer, so each push
waits for approval; only that job uses the environment. Without the secret the job skips
with a notice. Never add a `pull_request_target` workflow: it would hand secrets to forked
code.

**A save that stops loading is a minor version.** A release that bumps `*save-version*`
(save.lisp) bumps the second number (`0.1.x` to `0.2.0`), never the third, and its CHANGELOG
entry says, in a line of its own near the top, that saves from earlier builds won't load.

**Two changelogs.** `internal-changelog.md` records every change worth recording, internal
ones too, an entry in the commit that earns it under `## Unreleased`; cutting a release gives
that section the release's date and version. It is never shipped. `CHANGELOG.md` is the
player's: it ships in every build and is the release notes, so it holds only what a player
would notice (fixes, gameplay, art and interface, running the game; not CI, tools, docs or
refactors), short bullets in what the player can now do. At release time, draft its entry
from the internal changelog's `## Unreleased` and `git log vPREV..HEAD`, **show it to the
author and wait for approval before anything is bumped, committed, tagged or pushed**. A
release with nothing for players still needs an entry ("Fixes and improvements behind the
scenes"), since the workflow refuses a tag without one.

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

The frame counter also splits a frame: "tick 1.3 ms x5.0" is the time in ticks and how many
ran before the frame, "draw" the time in `main`'s render, swap included (`*frame-timing*`,
kept by `main`'s `update` and `render`).

**Passes.** A frame is three passes (`setup-scene`, main.lisp): `game-pass`, the world, at the
render scale's share of the window (`render-size`, settings.lisp); `menu-ui`, Alloy's, which
draws only while a panel is up (`main`'s update sets its `active-p`); and `hud-pass`, at the
window's size and what reaches the screen. It draws the world pass's picture as its background
(`world-backdrop`, nearest filtering, `late-rank` -1, so first), every `hud-element` (they draw
there only, `object-renderable-p`; the hands and weapons with them, so they stay sharp), and
the menu pass's picture over all (`menu-overlay`, rank 100). Both are `layer-quad`s, which
must be `renderable` or the pass never sets their samplers. A pass that reads full-window
pictures back costs: the compose pass that once laid three of them over each other cost 40 ms
a frame under software OpenGL.

**Slow machines.** A Windows VM with no 3D driver runs Mesa's software OpenGL (llvmpipe); so can
this machine, which has Mesa beside NVIDIA's driver:

```bash
__GLX_VENDOR_LIBRARY_NAME=mesa LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe LP_NUM_THREADS=4 taskset -c 0-3 ./run.sh
```

There drawing every pixel is the whole cost (the lamps sent matter less: 128 to none took 190
ms to 118), so Settings' Render scale is the lever. At 1280×720 on seed 12345: 4 fps before
these changes (190 ms drawing and 27 ticks, 80 ms, catching up each frame); now 11 fps at full
scale, 28 at ½, 37 at ⅓, 44 at ¼. Trial's loop runs every tick a frame took before it draws, up
to 10 s of them, so a slow frame brought more ticks and the next was slower: past
`*max-ticks-per-frame*` (5) the rest are dropped (`main`'s update) and the game runs slower than
real time instead.

## Layout and conventions

- `src/dev.lisp`: eval server, reload, runtime-error guard, screenshots. Dev only.
- `src/input.lisp`: key bindings. Every key and mouse button the game reacts to is an
  action's input in `*bindings*` (a `defvar`, so a reload keeps a rebinding; the defaults and
  each action's label and contexts are `*actions*`). An input is a key's keyword as Trial
  names it, or `:mouse-left`, `:mouse-right`, `:mouse-middle`, `:mouse-4` and on. Handlers
  ask `(input-action key :play)` (or `:map`, or `:global` for quicksave, quickload and the
  screenshot) what a press means, and ticks ask `(held-p :forward)`. What is held is
  `*held*`, kept by a Trial mapping function (`note-input`) from every event, not Trial's
  `retained`, which files the arrow key `:left` and the mouse button `:left` together.
  `rebind` binds an action to one input and takes it from any action in an overlapping
  context (`contexts-overlap-p`: `:global` overlaps everything, so Q can be Drink in play and
  Turn on the map). Esc, the mouse wheel, Shift + wheel and the map's mouse drags are fixed.
  `*bindings-revision*` counts the changes, so the HUD's key names (the hotbar's corners,
  the quickslot's, the inventory's hint, the map's hint, the "[E]" prompt) follow them:
  `key-label` names an input in full ("Left Shift", "Mouse left"), `key-short-label` and
  `action-key` for the HUD ("LShift", "LMB"). A new key the game reacts to is an action in
  `*actions*`, a row in `*controls-pages*` (settings.lisp), and a handler asking for it.
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
  knight 8, ogre 9, bloodroot 10, riftwalker 11, skeleton and arc votary 20, acolyte and harpy 25, imp, wraith and rime hag 30, necromancer 35) plus the weapon's
  bonus (`*sword-pain-bonus*` 0; a spell's `:pain-bonus`, the bolt's 10), at most
  `*max-pain-chance*` (75), so nothing can be held in its flinch. Knockback carries a creature
  whatever the pain roll: while its `momentum` is over `*shove-hold-speed*` (1.5 m/s; `shoved-p`;
  on ice, over what its walk reaches there, `walk-top-speed`) it neither walks nor lunges, so a hunter doesn't walk straight back through a push. A killing blow and
  `always-pained-p` (a harpy mid-dive) always interrupt. The `acolyte`
  (`src/acolyte.lisp`) is the ranged one, with a cast, flinch and death but no walk: it glides
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
- `src/imp.lisp`: the `imp`, a `leaper` that pounces, leaps round the player when its pack holds
  their front, springs back after its claw, breaks and shrieks when its courage fails, steals, and
  comes in packs. See "The imp" under "Creature
  movement" below.
- `src/blocks.lisp`: level blocks from glTF (`find-block`, `place-block`, `attach-block`,
  `seal-connector`); see "Level blocks" below.
- `src/blueprint.lisp`: builds blocks from text blueprints (`data/blueprints/*.txt`), in its own
  system `hexmaw-blueprints` (no Trial) so `tools/blueprint` starts in a second; see
  "Blueprints" below.
- `src/kit.lisp`: the kit (`kit-blocks`, every `.glb` in `data/blocks/`) and the gallery level
  that lays it out (`build-kit-gallery`, `kit-goto`).
- `src/generate.lisp`: the level generator (`generate-level`); see "Generated levels" below.
- `src/levelcheck.lisp`: building levels and blocks with no window, for `tools/levelcheck`
  (`build-level-alone`, `sweep-levels`, `kit-report`); see "Level sweeps" under "Generated levels".
- `src/run.lisp`: a run's levels and what carries between them; see "A run" below.
- `src/save.lisp`: saving and loading generated runs, one file per slot in `*save-directory*`
  (`$XDG_DATA_HOME/hexmaw/saves/`, usually `~/.local/share/hexmaw/saves/`:
  `slot-1.sav` .. `slot-3.sav`, `quick.sav`). A save doesn't store the level: it keeps the
  seed and the generator's settings (`*saved-generator-settings*`), and the level's cells
  (`level-layout`) to check that the rebuild is the same level; one built from changed blocks
  isn't, and its save then starts fresh, with a warning. So does one whose pickups were scattered
  another way (`:pickup-kinds`, `built-pickup-kinds`: the taken ones are named by index), and one
  older than that key. What it stores is everything that
  changes in play, so a load is the moment of the save, nothing in flight lost: the player,
  every creature by its index in `*creatures*` (raised skeletons recreated), every effect in
  the scene (projectiles, circles, impacts, with their glows), the blood pool's arrays, the skins
  over floors and walls (`:skins`, skins.lisp),
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
  `art/prompts/texture-lava.txt` like the other textures, `tools/make_texture.py
  art/textures/lava-2.png data/textures/lava-flow --metres 4 --palette art/style/palette.txt`) swirled by crossed waves. On
  the test level, `add-lava` digs a pit in the hall's south-west (x −9 to −6, z 3 to 7),
  its floor slab left with a hole there; the hall's room reaches down to the slab's
  underside so the glow lights the pit's rim.

  Water is deep only: a pit can sink no further than the 0.5 m slab, so water fills the lower
  storey of a two-storey block (a pool, a canal) up to `*water-surface*` (0.3 m, blueprint.lisp)
  under the floor above, or a flooded passage to its roof. `:swim` in its kind marks it;
  `swim-liquid-at` asks for it. Its surface is a `water-surface` (not lava's fullbright
  `liquid-surface`; both are `liquid-sheet`s): lit through `light_at` like a floor, from below
  as a ceiling, see-through (`*water-alpha*`), no depth written and both faces drawn. So it
  must be drawn after everything it covers: its `late-rank` is 0, and the game's passes
  (`layer-pass`, main.lisp) move what has one to the end of each frame, by rank (below 0 to its
  start), since Trial draws in hash-table order. The underwater tint (hud.lisp) is rank 1, after it. A water box whose top meets a ceiling gets no surface. With the camera
  in water (`*eye-underwater*`, set by `place-camera`) the fog and clear colour are the
  water's (`*underwater-fog-color*` and the rest; `fog-color`, greybox.lisp), and the whole
  view, the hands too, is multiplied by `*underwater-tint*` (a blue; `underwater-tint`,
  hud.lisp, a quad like the pain flash drawn with `:dst-color :zero` blending). The texture is
  `data/textures/water.png` (`art/prompts/texture-water.txt`, made like the other textures:
  `tools/make_texture.py art/textures/water-1.png data/textures/water --metres 4 --contrast 1.3 --palette art/style/palette.txt`).
  The nav grid makes deep water's surface a floor (`water-surfaces`), so a walker shoved in
  settles onto it like any floor. Afloat (`afloat-p`; never a flyer, `floats-p`) it is drawn
  sunk by `*float-sink*` of its height (in `apply-transforms`, so the surface covers the
  rest), doesn't think but flounders (`flounder`, `escape-liquid`) toward the nearest dry
  floor at `*flounder-speed*`, losing `*creature-drown-damage*` a second (`burn`), and walks
  out up the step onto the ledge. A projectile bursts on entering a liquid from outside: one
  cast under water (`submerged`) flies on. The necromancer draws no grave circle under a
  swimmer. On the test level the `pool` hangs off the shrine's west doorway.

  Shallows (`:shallows`, a blueprint's `shallow`, mesh prefix `shallows_`) are a ford's water: a
  pit 0.45 m into the slab holding 0.15 m, its surface level with deep water's beside it, so the
  two meet without a seam. Water's look (a `water-surface`), no `:swim`, no damage: the nav grid
  takes it for floor, so walkers cross a creek there and nowhere else, and the player wades at
  its `:speed`. A kind's `:step-sound` is what the player's step into it plays (lava's
  `:lava-step`, the shallows' `:splash-out`). The ambient loops (`*ambient-sources*`) take a
  liquid kind or a list of them (`water-lap` sounds over water and shallows), and `:falls`, the
  waterfalls' feet (`*falls-points*`, which `clear-level` empties).
- `src/waterfall.lisp`: waterfalls, where a creek drops a storey (a blueprint's `falls Y0 Y1`,
  empties `falls_<n>_lo` and `_hi`, `add-waterfall` from `place-block`). The sheet is a
  `waterfall`, a `liquid-sheet` standing across the drop's longer side: two layers of the water
  texture, twice as long down its length and rippling across as the surface does, pouring down at
  `*falls-speed*` and 1.37 times it, averaged, their brightest texels softly whitened (more
  toward its foot), so it has the surface's grain: hashed lanes of solid white, and then the
  texture stretched eight times, looked blocky beside the water around it, lit on the side it is seen from, see-through
  (`*falls-alpha*`), `late-rank` 0.2. `add-waterfall` looks within `*spill-reach*` either side
  of the drop for the pool it pours from, stands the sheet at the drop's far edge from it, and
  lays a spill (a `water-surface` at the pool's height) from the pool's edge over the lip to the
  sheet's top: without it the sheet hung mid-opening, rock showing on the lip and the dark drop
  either side of it. At its foot a `falls-foam` lies on the pool, churning
  blobs out to `*foam-reach*`, rank 0.1. It is a picture: the water is the two pools' liquids,
  and swimming over the lip drops into the pool below. Its roar is the `waterfall` loop at the
  foot (`*falls-points*`, full volume to 8 m). A `render :before` on a `liquid-sheet` subclass
  mustn't ask `first-this-frame-p`: the shared method after it asks too, and the texture and fog
  uniforms go unset (it drew black).
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
  footing and speed and each creature's footing. Pathing knows ice only as a cost: a walker's
  path search (`nav-flood`, under `*nav-hazards*` `:avoid` or `:wade`) charges a step onto a
  slippery cell `*nav-ice-cost*` (1.5) times its length, so routes keep to the snow beside a
  frozen river and cross it the short way; a straight walk still goes straight over it, skidding.
  Ice laid in play is a skin (`src/skins.lisp`, a rime hag's rime): `floor-footing` asks
  `skin-footing` first, and a creature's `update-footing` does unless `slips-on-rime-p` says no (the
  hag on her own ice); the nav arrays don't change, so paths don't cost it.
- `src/fx.lisp`: animated camera-facing effect sprites (`fx-sprite`, `spawn-fx`); fullbright,
  no fog. Projectiles are effect sprites. `face-camera` turns a sprite parallel to the view
  plane: about X by the pitch, then about +Y by the yaw (`nq*` turns by its first quaternion
  first, so the pitch's goes first).
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
  imp's turnaround and death sheet as references; the `:imp` set's is `art/gibs/imp-gibs-1.png`,
  the `:bones` set's `art/gibs/bone-gibs.png`), sliced by `tools/slice_frames.py` into
  `art/gibs/strips/<set>`, which `tools/draw_blood.py --gibs <set>=<strip>` appends to the
  blood strip with the turned frames; cells grow to fit the biggest piece. Every run
  rebuilds the strip, so pass every set. The generator draws the pieces bigger than asked,
  so `--pixel` is set by eye to the imp's scale (the head about 30 px across); the strip
  holds 256 frames at most, 4 a piece:

  ```bash
  python3 tools/slice_frames.py art/gibs/flesh-gibs-2.png art/gibs/strips --pixel 9 --filter box --colors 32 flesh:8
  tools/draw_blood.py data/sprites/blood/blood --gibs imp=art/gibs/strips/imp --gibs flesh=art/gibs/strips/flesh --gibs bones=art/gibs/strips/bones
  ```
- `src/sparks.lisp`: sparks, embers and grit, simulated like the blood (`spark-pool`,
  `*spark-pool*`, entered by `add-spark-pool` in `setup-scene`): plain arrays of `*max-sparks*`
  (2048, for a blizzard's flakes) slots, written each frame into one stream-draw vertex buffer and drawn in one call, nothing
  allocated a frame. They draw no art: each is a quad in the view plane on which the shader lays
  whole texels of the 64-a-metre grid, at least a pixel each (`view_rows`), in three colours of the
  house palette (`*spark-ramps*`: `:steel`, `:ward`, `:fire`, `:lava`, `:dust`, the novas' `:frost`,
  `:shock`, `:drain`, and a wall struck's `:wood` and `:snow`), fullbright,
  unfogged and opaque. A **spark** is a streak, its tail as far behind its head as it moves across
  the view in `*spark-streak-time*`, 1 to `*spark-max-streak*` (9) texels, the first third its
  ramp's hotter colour; it falls under `*spark-gravity*`, bounces off solids (`bounce-spark`, on
  gore's `crossed-face`, `move-to-face` and `reflect-off-diagonal`), lies on a floor it strikes
  slower than `*spark-rest-speed*`, cools down its ramp over `*spark-life*` and goes. An **ember**
  climbs to the rise it left at, wanders on two crossed waves, keeps its heat longer and blinks
  out over the last `*ember-blink*` of its life; rock or a liquid puts it out. A **flake** (state 7)
  goes where the winds carry it (`wind-carry` over `*winds*`, which this file defines), fluttering up
  and down `*flake-flutter*`, a streak as long as its speed; out of every wind it slows and falls at
  `*flake-fall*`, and rock, a liquid or its life's end takes it (the rime hag's blizzard). **Grit** (a texel,
  or a 2 × 2 chip lit from the upper left, `*grit-big-chance*`) falls, bounces once, settles for
  `*grit-rest*` and dissolves a texel at a time. A liquid swallows any of them.
  `(spray-sparks at dir count &key kind ramp speed spread)` throws them (DIR NIL: up, any way above
  level); the hooks are `shield-sparks` (off a shield's face, its ward's violet for anyone but a
  knight: `block-hit`, so a spell, bash or sweep glancing off, and a sword or spear blow on a
  covered view, `swing-strike`), `strike-sparks` (the spear's counter, `*counter-sparks*`; the
  maul's blow, `*maul-sparks*` 6 to 26 by charge, faster too), `floor-sparks` (the earthshake, in
  front of the player; the ogre's landing and slam, where its maul comes down), `kick-grit`,
  from `kick-dust` (ogre.lisp), `*grit-per-puff*` round every dust puff, and `wall-sparks`, a
  melee blow that found no one striking a wall or floor (`wall-strike`, sword.lisp): off the face
  about its normal, glancing the way the blow came in (`*wall-spark-glance*`), the sparks and grit
  the surface's share of the weapon's (`*wall-strike-kinds*`: stone sparks and throws dust, ice-rock
  fewer sparks and frost chips, slick ice and snow only chips and a puff, wood only pale
  splinters). Embers rise from
  `*ember-sources*` (`add-torch-embers` from `add-torch`, `add-lava-embers` from `add-liquid` for a
  surface that glows, as many as its area, `*lava-ember-area*`; `clear-level` empties them), each on
  its own timer, only within `*ember-reach*` of the player (`send-up-embers`), and only while the
  world runs; they never take a slot from a blow's sparks (`spark-slot`'s AMBIENT). A save leaves
  them out, as status auras are, and `reset-run` clears the pool (`clear-sparks`). `map-hot-sparks`
  hands a glow layer every spark and ember (place, heat, ramp); nothing calls it yet.
  `tools/spark_shots.sh DIR` stages a shot of each hook (`BEFORE=1` without the pool), stepping the
  pool by hand while the world is frozen. Cost, 495 particles in the middle of the view, world
  frozen, vsync off: GPU 2.32 ms a frame against 2.30 with none, writing the buffer 0.07 ms of CPU
  and a tick of `step-sparks` 0.08 ms; under llvmpipe ("Slow machines") 120.4 against 119.3–119.8
  ms at full scale and 41.4–41.6 against 40.9–41.3 at ½.
  **Lightning** lives here too (`bolt-lines`, `*bolt-lines*`, entered by `add-bolt-lines` in
  `setup-scene`): `bolt-line` adds a jagged bolt between two points, midpoints moved across it
  `depth` times (on a `:sphere` each is put back on it, so the bolt runs over its surface), with
  forks (`:branch`) and segments left out (`:drop`, a bolt breaking up), every segment lasting
  `:life` seconds, so whatever makes bolts draws them anew to make them crackle. They are plain
  arrays (`*max-bolt-segments*`, 2048) written into one stream-draw buffer and drawn in one call:
  each segment a quad facing the view, its ends snapped to the art's pixel grid on screen (a 240th
  of the rows), a yellow edge `width` art pixels wide and a white core one wide (`*bolt-edge*`,
  `*bolt-core*`), added over what is behind it. Only the shock nova uses it so far.
- `src/spells.lisp`: the composable spell model (`define-spell`, effects, `spell-power`, tiers,
  `spell-cost`), the deliveries (projectile, seeker, beam, nova, circle), the player's `bolt`, `absorb`
  and `heal`, the acolyte's `cinder` and the necromancer's `grave-skull` and `grave-spikes`. An effect
  has a kind, a magnitude range, a duration, an area, a target type (`:self`, the caster; `:target`,
  what the delivery hits) and, for damage, an `element`. `*effect-kinds*` says what each kind the
  spellforge offers is (its base, how its duration counts: `:instant`, `:over-time` (magnitude per
  second) or `:status`, who it may strike, and the forge's caps).
  **Power** (`spell-power`) is a spell's strength as one number: for each effect, `effect-cost`, the
  base (by element for damage, `*element-costs*`: fire 1.5, frost and shock 1.7; heal 1, knockback 0.5,
  slow 0.12, drain 2, ward 0.4, absorb 0.2) times the average magnitude, times the duration's factor
  (instant 1, over time duration × 0.6, status 1 + duration / 5), times 1 + area, times the delivery's
  `*delivery-cost-scales*` (touch 0.75, seeker 1.3, beam 1.4, nova 1.5); summed, rounded up. Dust
  (`spell-dust`), enchantments (`enchant-cost`, half the power a blow) and found runes are priced by it.
  **Tiers** (`spell-tier`): a spell's tier follows from what it is, the first whose rules it meets
  (`tier-fault`), and `tier-reason` says why it isn't the one below. **Free**: a projectile, touch or
  seeker; one damage effect, plus knockback of at most `*free-max-knockback*` (4); nothing lasting, no
  area; power at most `*free-max-power*` (14, the Fire Bolt's). An Absorb is always stamina (below). **Stamina**: any
  delivery but self (`*stamina-deliveries*`); at most `*stamina-max-effects*` (2) of damage, knockback
  and slow (`*stamina-kinds*`); `*stamina-max-duration*` (4 s) and `*stamina-max-area*` (1.5 m) at
  most; power at most `*stamina-max-power*` (40), a beam `*stamina-max-beam-power*` (20). **Mana**:
  anything else, every heal, ward and drain, and the spells the forge doesn't make (the tornado, the
  creatures'). A cast takes `spell-price` (player.lisp): nothing, `spell-stamina` (its power) or
  `spell-cost`, the mana: the power, its striking effects at `*cast-strike-scale*` (0.5, what the same
  spell costs a blow as an enchantment), its self effects whole; one the forge doesn't make, its whole
  power. So the Fire Bolt (14) is free, a fire projectile of 21-30 (power 39) costs 39 stamina, heal
  (17) 17 mana, and a fire burst of power 50, 25 mana. The player's starting spells must be ones the
  forge makes, ranges, power, flight and all (`forgeable-p` and `check-starting-spells`, forge.lisp,
  which warns as it loads, and also if the bolt, `*free-starting-spells*`, isn't free: a
  forged range is `*magnitude-spread*` of its top up to it, and damage always has an element).
  **Overcharge**: a striking stamina or mana spell (`overchargeable-p`, player.lisp: projectile, touch,
  seeker, nova) held is cast as `overcharged-spell`, a copy (`scaled-spell`) with magnitudes × (1 +
  `*overcharge-strength*` (0.6) × its charge) and `spell-overcharge`; a full one (`full-overcharge-p`)
  isn't turned back by a shield or ward (`deflects-p`) but knocks it aside (`overcharge-breaks-guard`,
  `knock-guard-aside` in maul.lisp), and its damage always flinches (`:force-pain`; a boss rolls with
  `*overcharge-pain-bonus*`). **Seeker**: a projectile that picks the live creature nearest the aim
  (`seeker-mark`, within `*seeker-cone*` and `*seeker-range*`, in sight) and turns after it at
  `*seeker-turn*`. **Beam**: no flight; it strikes the first body or wall along the aim within
  `*beam-range*` (12 m) at once (`beam-end`, `beam-strike`; a covering shield stops it; for any
  caster but the player it reaches the player's body too), its light a
  `beam` (a shared ribbon, `*beam-vao*`, staged by `preload-spells`, texel-stepped, added light). The
  player holds a beam (player.lisp): every `*beam-pulse*` a `pulse-spell` with
  `beam-pulse-share` of its instant effects, for that share of its price; a creature holds one too
  (the arc votary, votary.lisp), each strike a `beam-pulse` source: on the player, no shove or hit-stop
  (`effect-shove`), the shield meeting it anyway (`hurt-player`'s `:blockable`) for its own stamina
  (`effect-block-cost`, `:block-cost`). **Nova**: a sphere growing
  from the caster's chest out to its `spell-nova-radius` (`:nova-radius`, by default `*nova-radius*`,
  5 m; the rime hag's 5, the Winter Crone's 7) plus its effects' area over `*nova-grow-time*`
  (0.4 s), from `*nova-start-radius*` and slowing as it goes (`spell-nova`, `place-nova`; its camera
  kick `*nova-camera-shake*`). It spares its caster; the bodies it reaches (`burst-victims` at the
  cast, nearest first, by `nova-distance` to their upright cylinder) are struck as the sphere reaches
  each (`nova-strike-body`), every striking effect whose reach covers it, pushing away from the
  centre. Its look is its element's (`nova-style`, `*nova-styles*`: the first damage effect's fire,
  frost or shock, else `:drain` for a drain, else `:force`). All but shock grow a dome (`nova-dome`, a
  shared sphere `*nova-dome-vao*`, added light like the aurora, its curtains sized in metres on its
  surface so that from inside they recede as it grows): fire's streaks lick and climb with ragged
  tops, frost's are hard pointed shards that barely move, drain's hang from the top, force's are the
  aurora's; a slow in the spell halves their pace and adds a sinking haze. Shock's is a cage of
  lightning instead (`nova-lightning`, `bolt-line` in sparks.lisp): `*nova-cage-bolts*` bolts over the
  sphere, most on the side the player looks, drawn anew every `*nova-crackle*`, breaking up in the
  second half of its growth, and at each body struck a bolt in from the cage, bolts crawling round it
  for 0.15 s and a jump to the nearest other creature within 3.5 m. The newest nova keeps the
  `*nova-sweep-...*` variables (greybox.lisp) that the lit shaders' `nova_sweep` reads: a bright band
  `*nova-band-width*` wide where the sphere meets the level and the monsters, a dithered trail behind
  it, and after fire a scorch, after frost a rime, in soft patches, fading over `*nova-trail-time*`
  (1.2 s). Each look throws its particles while it grows (`*nova-particles*`, `emit-nova-particles`:
  fire's embers, frost's glitter and chips, shock's sparks, force's grit; drain's motes stream from
  each body struck back to the caster). A save keeps one in flight (`saved-slots`). Measured with one
  frozen mid-growth in the test hall, vsync off: GPU 2.84 ms a frame with fire's dome, 2.37 with
  shock's lightning, 2.12 with none. A projectile remembers who first fired it
  (`launcher`); the player's free ones fly `*free-projectile-lifetime*` (1 s, 20 m;
  `projectile-lifetime`). A projectile that reaches a body that `absorbs-p` it (the player's Absorb,
  magic.lisp) is swallowed (`absorb-projectile`) before its effects. An effect with an area
  bursts where its spell strikes (`burst-spell`, over `burst-victims` in magic.lisp: every body
  the ball of that radius reaches, `burst-reaches-p`, sphere against the body's upright cylinder,
  with a clear line to it, `clear-line-p` in gore.lisp, up, down or across, so no burst reaches
  through a floor or ceiling; but the caster and those it spares), the impact drawn over the same
  ball (`play-impact`: itself at most `*burst-scale-limit*` bigger, then `burst-shells`, copies at
  their own size on shells `*burst-shell-step*` apart, Fibonacci spheres, at most
  `*burst-max-copies*`, none in a solid or behind one from the middle: a dome on a floor, half a
  ball on a wall); a strike without a projectile (a touch, an enchanted
  blow) goes through `strike-with-spell` and a `strike` source. A spell the player forged isn't in
  `*spells*`: `spell-spec` and `spec-spell` turn one into plain data and back (a save keeps it so),
  and its look is its element's or first effect's (`*spell-looks*`: the bolt's frames recoloured
  into `data/sprites/spells/` by `tools/recolor_hue.py ... --from 30 --reach 60 --hue H --spread
  0.5`; frost 200, shock 58 with `--spread 0.25`, drain 345, heal 110, arcane 285; a ward's and an
  Absorb's, `:ward` and `:absorb`, only colour the hands, borrowing heal's and arcane's frames), each
  preloaded by `preload-spells`. A new effect kind is a method on `apply-effect`, for a
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
  puffs round its foot; from inside, `whirl-streaks` (hud.lisp) rush across the view. It is a
  **wind** (`*winds*`, spells.lisp): a projectile passing through its funnel, within
  `*vortex-deflect-margin*` of its wall, any caster's, is turned `*vortex-deflect*` (9 rad/s) the way
  it spins (`wind-turn`), so a Fire Bolt crossing it goes off about 45 degrees. To look at
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
- `src/acolyte.lisp` (after wraith.lisp, before boss.lisp; it needs the abilities and the circle):
  the `acolyte`, an `ability-user` with the cinder (`:cinder`, its first) and the firestorm
  (`:firestorm`), the `firestorm` entity (a `spell-circle`) and its `falling-cinder`s. See "The
  acolyte" under "Creature movement" below.
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
- `src/hag.lisp` (after riftwalker.lisp): the `rime-hag`, the frost caster, with her elite and
  boss (`elite-hag`, `hag-boss`, the Winter Crone). See "The rime hag" under "Creature movement".
- `src/votary.lisp` (after hag.lisp): the `arc-votary`, a blind storm-priest that holds a shock beam,
  its elite (`elite-votary`) and its boss (`votary-boss`, the Arc Hierophant). See "The arc votary"
  under "Creature movement" below.
- `src/bloodroot.lisp` (after votary.lisp): the `bloodroot`, the last level's new monster, a
  rooted heart-bulb whose roots spread over the floor and walls; see "The bloodroot" under "Creature
  movement" below. Also the `root-floor` that draws every carpet, and its elite and boss.
- `src/boss.lisp`: the boss at the end of a run, in the `arena` block the run's last level ends in. It is an
  empowered form of one of the nine monsters (`*boss-kinds*`: kind, class such as `imp-boss`
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
  with its facing (`ward-arc-mixin`, which a warded elite has too: `ward-up-p` says whether it
  shows, `ward-hum-p` whether it hums). Powers are
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
  its title, health with a mark at half, and its powers, from the seal until it dies; an elite the
  player aims at takes its place meanwhile (see `src/elite.lisp`).
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
  (`*frost-chill*`), shock adds `*shock-pain-bonus*`; `*element-resistances*` takes a share of an element off
  a class (acolyte fire, skeleton frost, gale wraith shock: half; the rime hag's frost and the arc votary's
  shock: three quarters; the bloodroot's drain, treated as an element, half and its frost a quarter), and a
  negative share adds to it (the rime hag and the bloodroot take half again of fire); the forge says who
  takes less and who more (`resisters`). Drain heals its caster `drain-share` of what its target lost
  (`*drain-share*`, all of it for a bloodroot; `heal-caster`): a creature's drain strikes the player too
  (`apply-effect :drain` on the player). Statuses are `saved-slots` (`(:status ...)` in a save). A status keeps its
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
  **Absorb**: a spell holding `:absorb` alone, cast on yourself, is held (`hold-channel`, player.lisp)
  on stamina (`spell-tier` makes it `:stamina` whatever its power): its power a second while held
  (`update-channel`), no stamina coming back meanwhile, and `*absorb-take-stamina*` (1) a point of the
  mana each projectile gives (`absorb-stamina`); out of stamina it drops, and a projectile it can't pay
  for strikes. Free, a live acolyte was a mana spring. While it is held, a hostile projectile that carries damage and comes at the player from
  within `*block-arc*` of their view (`absorbs-p`, `facing-point-p`) is swallowed before it strikes
  (`absorb-projectile`): no damage, no burst, the view flashes `*absorb-flash-color*`, the hum it holds
  (`absorb-channel`, a loop in `update-channel`) swoops up and down (`absorb-take`: that hum resampled
  at a bent rate, the recipe in its take's `.prompt.json`), and the player
  gains `absorb-mana`, the effect's top magnitude's percent (`absorb-share`) of the spell's power, or,
  for the player's own spell sent back by a shield (its `launcher`, spells.lisp), of the mana it cost,
  so a free one returned gives none. Rifts and gusts carry no damage and still strike; nothing that
  isn't a projectile is taken. The starting Absorb Projectiles takes 35-50 (50%, power 9, so 9 stamina a
  second): a cinder gives 5 mana for 5 stamina, a grave skull 6.
- `src/skins.lisp` (after magic.lisp): **skins**, something laid over the level's floors and walls in
  play for a while and drawn on them in world space: so far the rime hag's rime. A kind
  (`define-skin-kind`, `*skin-kinds*`: an image of the hexmaw pool, its rim and inner colours, the
  footing it is underfoot or NIL for a look only; `:ice` is the ice caves' `ice` texture, footing
  `:ice`) is drawn by a `skin-floor` of its own (`add-skin-floors`, `setup-scene`), every skin of it in
  one call from a stream buffer, `*max-skin-cells*` (2400) a kind: quads a hair off each cell,
  the texture laid at 64 texels a metre on the face, texels under half alpha see-through, lit as the
  face, the skin's circle its edge in jagged steps of whole texels frosted in the rim colours, and on
  walls a jagged top. A `skin` (class; `lay-skin`) covers the nav grid's 0.5 m cells within its
  radius whose floors are within `*patch-climb*` (1 m) of the floor it was laid on and under no
  liquid (`skin-floor-cells`: steps, pits and ledges, never lava or water), and the walls round it
  (`skin-wall-cells`: square boxes' upright faces turned to its middle, in clear sight from a metre
  over it, from its floor up `*skin-wall-height*` (2.5 m), 0.5 m cells on the world's grid; a
  wedge's diagonal stays bare). Its entry in `*skin-patches*` (greybox.lisp: centre, the radius drawn
  now, the cell grid and each cell's floor height, footing, wall cells, kind) is what `skin-footing`
  and the drawer read; set a cell's height to lay it. It lasts `time`, shrinking away over its last
  second (`skin-tick`), and is saved (`:skins`, `skin-record` and `restore-skin`, its cells worked out
  again) and cleared by a reset (`clear-skins`). An element striking near one reaches it through
  `strike-skins` (from `burst-spell`, `place-nova`, a projectile's and a beam's impact, at least
  `*impact-skin-reach*` round, and the firestorm's pulses), which asks `skin-struck` of each: fire
  melts a `frost-patch` (`lay-frost-patch`: a radius, a time, renewing its caster's within
  `*patch-renew-reach*`; with no floor within `*patch-reach*` under the point, only the walls ice
  over), which as it forms freezes (`freeze`: the `:freeze` status, ice blue, thinking stopped, a
  creature's `thaw` guarding it for `*freeze-guard*` after; a boss half as long) the creatures on it
  its caster is `hostile-p` to, never its side. The frost patch and its ice floor were ported from
  the spell-secondary branch. A spell's own landing hook is `spell-impact` (spells.lisp), on its name.
  To look at one: `(game (lay-frost-patch (vec -8.5 0.5 2.0) (scene +main+) :radius 3.5 :time 60.0))`
  on the debug level, by the hall's west wall.
- `src/forge.lisp`: the spellforge, used at an altar (`add-altar`, pickups.lisp; `near-altar-p`, within
  `*altar-reach*` across and `*altar-height*` of its top; the HUD's prompt line says "[E] Spellforge"
  there, the altar being one of E's targets, `interact-target`, townsfolk.lisp). E opens it (`open-forge`, `*game-state*`
  `:forge`, frozen; Esc or Leave closes it; `*forge-anywhere*` opens it anywhere in a debug version).
  Making costs arcane dust (an item, `:dust`): a spell `*dust-per-mana*` (1) a point of its power
  (`spell-dust`, `spell-power`), an enchantment `*enchant-dust-scale*` (3) a point of its mana per blow
  (`enchant-dust`); destroying one gives back `*dust-refund*` (0.5) of that (`refund-dust`). Two tabs
  (`*forge-tab*`, `forge-tab`): **Spells** lists "New spell" and every rune in the bag (`player-runes`,
  `*forge-list-rows*` a page, `forge-page`), **Enchant** the weapons carried (`carried-weapons`: every
  sword, spear and maul in the bag, each a stack, its sink, and the shield, `:shield`, with a sword;
  `weapon-sink-p`, `sink-weapon`, `(setf sink-spell)`; `(forge-select :sword)` from the REPL takes the
  first sword). The forge is on one of them (`*forge-sink*`,
  `forge-select`): a new spell or a plain weapon has a draft to make (`*forge-draft*`, kept per sink in
  `*forge-drafts*` while the forge is left: a `forge-draft` of a delivery and `effect-draft`s), made by
  `forge-make` into a rune in the bag on the first free key (`give-rune`) or the weapon's enchantment;
  a rune or an enchanted weapon is only shown (`shown-spell-lines`) with Unweave or Disenchant
  (`forge-destroy`, two clicks: the first arms it, `*forge-armed*`). Nothing is changed in place: make
  another, or destroy it; spells are limited only by free bag cells. Effects and elements are those the
  player knows (`known-effects`: `*starting-effects*`, damage, heal, knockback, fire and absorb, plus what
  glyphs taught; `:area` unlocks area), and of those only the ones that land where the draft does
  (`draft-kinds`): a spell cast on yourself takes heal, ward and absorb, a projectile, a seeker, a beam, a
  nova, a touch or a weapon damage, knockback, slow and drain (`*forge-deliveries*`). There is no tier
  to choose: the readout gives the one the draft comes to (`spell-tier`, spells.lisp), its cost
  (`spell-cost-text`, inventory.lisp: "Free, every 0.5 s", "39 SP a cast", "36 SP a second", "17 MP a
  cast") and why it isn't free (`tier-line`: "Stamina: power 39 is over 14"), as a dial moves. Changing the delivery turns the effects that no longer fit into the first kind that does
  (`fit-effects`). A run starts knowing only fire, so with one element (or one kind for the delivery)
  known, the Element or Effect button doesn't change it but says so in the note, naming the glyphs
  that teach the rest (`forge-cycle-element`, `forge-cycle-kind`). `draft-problem` says why a draft can't be made (self delivery with something to
  strike, a delivery with nothing to, an Absorb beside another effect, a mana cast over the pool, a weapon's more than
  `*max-enchant-effects*` or `*max-enchant-cost*` a blow, too little dust, a full bag), and while it
  objects the screen shows it: the note says so in `*forge-warning-color*` (a `forge-status-note`),
  and the Make button (a `forge-make-button`) is greyed, with no orange on hover; a click on it
  only plays `:refused`.
  `refresh-readout` keeps all of it current as a slider moves, with no remake. A draft's name
  is made from its effects (`draft-name`, "Frost Burst"). The screen is `forge-panel`, a `menu-panel`
  that lays itself out (`build-panel`, menu.lisp): the tabs and sinks down the left, labels cut to
  `*forge-label-width*` (`fit-label`), each a `forge-choice` (a `menu-button` that draws the chosen
  one with a gold border, a warm fill and a gold label, `*forge-selected-color*` and the rest, apart
  from the hover's orange), the work on the right, its sliders `forge-slider`s (a
  `menu-slider` with its own range and value text), under the effects one explanation (`effect-about`,
  built from the parameters: the kind's rule, the element's quirk, who resists it from
  `*element-resistances*`, what time and area change; a `forge-about`, smaller and dimmer) of the
  effect in hand, `*forge-about-index*`: the one whose controls last had the focus (each is an
  `effect-control`, and a hover gives the focus) or that was last added or changed, its Effect button
  drawn chosen (`forge-effect-button`). Three effects with an explanation under each didn't fit a
  1280×720 screen. Its text `forge-note`s wrap (Alloy's `:wrap`) in rows as tall as `note-lines`
  counts, breaking at spaces (`wrap-text`); **a row too short for its text draws none of it**, so the
  explanation's box is as tall as the longest its effects can need with every dial at its top
  (`about-lines`, `*forge-about-line*` a line), and the readout has two lines. A structural command
  bumps `*forge-revision*` and the menu controller remakes the panel (`panel-stale-p`); a slider only
  changes the draft and the readout, note and explanation (`alloy:value-data`s the panel keeps). From the REPL: `(game (setf
  *forge-anywhere* t) (open-forge))`, then `(forge-tab :enchant)`, `(forge-select :sword)`,
  `(forge-make)`, `(forge-destroy)` twice.
- `src/elite.lisp`: elites, a deeper level's stronger monsters. A spawn on a generated level is
  one with the level's `*elite-chance*` (`:elite-chance` in `*run-levels*`): `elite-roll`, from
  `place-block`, draws from `*elite-random*`, a state of its own seeded from the level's, twice for
  every spawn whatever it decides, so elites never move the layout or another spawn. An elite is
  its kind's class with the `elite` mixin first (`elite-imp` .. `elite-wraith`, `elite-riftwalker`
  in riftwalker.lisp, `elite-hag` in hag.lisp, `elite-votary` in votary.lisp, `*elite-kinds*`):
  `*elite-health-scale*` (1.75) its health, drawn `*elite-size-scale*` (1.15) bigger but never past
  `*nav-clearance-height*` (the ogre not at all), its body as its kind's, so it goes wherever its
  kind goes, and a rim and lamp (`rim-glow`, boss.lisp) in its trait's colour, `*elite-glow-colors*`,
  none of them the boss's orange. Its one trait (`elite-trait`): `:haste` (cyan, walk and attacks ×
  `*elite-haste*`), `:warded` (violet, its front turns spells back, `shield-views`; never the
  knight's) or `:tough` (bone-white, half the pain chance and the knockback). Summoned and raised
  creatures and the boss never are. A save needn't keep the trait: the rebuild draws it again.
  **What the glow means** shows where the boss bar goes: while the player aims at an elite
  (`aimed-elite`: the creature under the crosshair, `aimed-creature`, is one: the nearest live body
  the line of sight from the eye meets, as an upright cylinder of its body radius plus
  `*elite-aim-margin*` from its feet to its sprite's top, `ray-body-hit`, within `*elite-aim-range*`
  (15 m) and with no wall before it, so a monster in front of an elite hides it; asked every
  `*elite-aim-step*` from the HUD's tick. A cone round the aim, as the seeker's, caught elites a
  metre off at range and missed their heads and feet up close), a bar half the boss's (`*elite-bar-width*`)
  shows its health, its name over it as the boss's title is (`elite-title`: "Elite Gale Wraith")
  and its trait's name under it in the glow's colour (`*elite-trait-labels*`: Haste, Warded, Tough). It stays `*elite-bar-linger*` (0.25 s) after the
  crosshair leaves it, goes when the elite dies, and covers the boss's bar while shown (`shown-foe`, `shown-elite`,
  hud.lisp; the half mark is a `boss-only-element`). A warded elite also shows the boss's
  violet arc round its front (`ward-arc-mixin`, boss.lisp), humming only within
  `*elite-ward-hum-range*` (12 m) of the player, since a sound gets no quieter past 50 m.
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
  (`scatter-pickups`) until they restore `*health-per-monster-health*` (0.09) and
  `*mana-per-monster-health*` (0.18) of the level's monsters' health (`monster-health`, their
  `max-health` as built, elites' and the boss's raised: by health, not number, so an imp pack is
  paid for as imps), every `*pickup-potion-every*`th (3rd) of a resource a potion, on a reward spot if one
  is free in a block with no pickup yet and otherwise anywhere. It skips
  the start block and spots the player can't reach (`spot-reached-p`: a floor spot's own cell, or
  for a reward spot a floor up to `*jump-reach*` under it within 2 m), keeps to one a block until
  blocks run out, and likes rooms `*pickup-room-weight*` times as much as corridors. It draws from
  a random state of its own seeded with the level's, so a seed always places the same ones. A save
  names the taken ones by place, so changing how they're scattered would make an older save mark the
  wrong ones taken; it starts its level fresh instead (`save-matches-level-p`). Over run seeds 1 to 30
  (`tools/levelcheck --runs 1-30`), 45 monsters on a run's first level (34 to 60), about half of them
  imps (imp packs, imp.lisp), 54 on the second and third and 64 on the last, and 17 in the settlement:
  15 health and mana pickups on the first (4.6 potions, 152 health, 296 mana), 22 on the second and
  third (7 potions, 225 health, 440 mana), 36 on the last (11 potions, 354 health, 710 mana) and 8 in
  the settlement; a run 25 potions, 810 health and 1,590 mana. At 10 health and 15 mana a monster and
  a potion every 2nd it was 66 potions, 1,780 health and 2,670 mana a run, and the bag came to the
  boss full of potions. Mana doesn't regenerate, so they are its only source in a run. A new kind of pickup is a
  method on `collect-pickup`. To try one: `(setf (health *player*) 50)` and
  stand on `(location (aref *pickups* 0))`.
  **An elemental foe teaches its element**: a creature whose `taught-effect` (creature.lisp; the rime
  hag's `:frost`) the player doesn't know, killed by them on a generated or the test level, drops that
  glyph where it fell (`drop-taught-glyph`, from `creature-died`), once a level per glyph; the run's
  placed glyphs stay as they are, and a save keeps the drop (`:drops`).
  **Glyphs** are pickup kinds with `:teaches` (`:glyph-frost` .. `:glyph-area`): touched, they teach
  the player an effect for the forge (`learn-glyph`: `known-effects`, a gold flash, a message), and
  one already known stays. Each level of a run has `*glyphs-per-level*` (2), the run's six shuffled by
  the run seed alone (`run-glyphs`), so the first three levels teach them all and the last has none,
  placed after the other pickups (`place-glyphs`, from a random state of their own) on free spots, a
  reward spot first, so the other pickups keep their places. `scatter-pickups` leaves them their spots
  (`:reserve`, the level's glyphs and loot, `src/loot.lisp`, the settlement's relic, a sacked town's
  `*sacked-town-loot*`, and `*pile-spots*` (3) for gold and dust): the settlement's small wing ran out and
  lost a glyph for the run, and before the gold and dust had spots kept, half of a run's first levels
  had neither (run seed 5's first among them). The town's shopkeeper sells the ones the player doesn't know (see "The
  settlement"). The test level has one of each along the hall's south wall, west of the pickups. **Arcane dust**
  (`:dust`, an `:item` with `:count`: the pile's `pickup-count`) is placed last (`place-dust`, from a
  random state of its own, on spots `free-pickup-spots` leaves) until a generated level holds
  `*dust-per-monster*` (2) for each monster (`monster-p`: not the townsfolk), in piles of `*dust-pile*`
  (8 to 20; bigger where few spots are left, so a level gets its whole budget while it has a spot:
  about 60 to 120, three to six spells). Over run seeds 1 to 30 every level got its whole gold and
  dust; one that can't logs "No spot for ...". Sprites:
  `tools/draw_glyphs.py data/sprites/pickups` (a rune tablet per glyph, and `altar-sigil`).
  **Altars**: `add-altar` notes a point in `*level-altars*` (blocks.lisp; a blueprint's `altar`) and
  hangs an `altar-sigil` over it with a lamp; `reset-run` keeps it. The test level has one on a dais
  in the hall's north-west corner.
- `src/loot.lisp`: found weapons and runes. A run starts with the sword, the fire bolt (with Absorb
  Projectiles in its off hand) and heal; the rest is loot. Each level's `:loot` (`*run-levels*`, run.lisp; `loot-property`, which takes the
  settlement's own `(:weapons 0 :runes 1)` before the level it borrows the rest from) gives its
  `:weapons` (level 1 a plain spear, `:first-weapon`) and `:runes`. A weapon is a sword, spear or maul
  (`*loot-weapons*`, each as likely) with
  the usual stats; only its enchantment varies: `:enchant-chance` (0, 0.5, 0.8) of one costing
  `:enchant-cost` a blow (2-3 on level 2, 3-6 on level 3) with up to `:enchant-effects`
  (`loot-enchantment`). A rune (`make-loot-rune`) is a generated spell made as the forge makes one,
  from a `forge-draft` (`loot-rune-draft`: a delivery from `*loot-deliveries*`, projectile, seeker,
  beam, nova, touch or self, kinds from `*loot-strike-kinds*` or `*loot-self-kinds*` (an Absorb drawn
  with others is drawn again), up to `:rune-effects`, elements, times (`*loot-durations*`) and, with
  `:area-chance`, a burst for a projectile or seeker), its magnitudes sized by bisection (`size-draft`)
  to a power in `:rune-power` (10-18, 16-28, 24-40), drawn again while `draft-fault` (forge.lisp, the
  forge's checks without the dust and bag) refuses it or it falls more than `*rune-power-slack*` short.
  Its tier follows from what it is: over run seeds 1 to 30, level 1's runes were 11 free, 7 stamina and
  12 mana, deeper ones about two thirds mana (`tools/levelcheck`'s "rune tiers"). Or it is one of `*loot-spells*` (the tornado, `tempest`), which the forge
  can't make: once a run at most, on the first level whose `:authored-chance` (0.35, 0.5) roll from the
  run seed comes up (`authored-loot`); 13 of run seeds 1 to 15 had it. `place-loot` (after the glyphs,
  before gold and dust; `scatter-pickups` reserves the spots, `loot-count`) stands each as a
  `loot-pickup` (its `loot-stack`, given as a copy so a reset hands out the same) on a reward spot
  first, from a random state of the level's seed, so a load builds the same items; taken, it goes
  into the bag on the next free key with "Found a sword: Frost Edge, on key 4." Its sprite is
  `loot-sword`, `loot-spear`, `loot-maul` or `loot-rune-<look>` by its spell's look (`tools/draw_loot.py
  data/sprites/pickups`). An enchanted weapon's pickup has the outline it has in hand: `loot-pickup` is a `rim-glow`
  (boss.lisp), its rim in the enchantment's colour, pulsing as the weapon's in hand (never dimmed). A
  rune's stone shows its look, not its first effect as its icon does. The debug level has
  a spear, an enchanted sword and two runes east of the dust (`place-test-loot`, from seed 7 and the
  last level's `:loot`). `tools/hd status` shows an enchanted weapon as `sword[frost-edge]`. A
  stranded ogre's hoard (`place-hoards`, after the dust) is one more item; see "The ogre".
- `src/inventory.lisp`: the inventory, the hotbar, the quickslot and the panel. `*item-kinds*` says
  what an item is (name, frame in `data/sprites/icons/items`, what it restores, how many fit in a
  stack); a pickup's `:amount` must match its item's, since a level's budget counts it. Potions stack
  5; arcane dust (`:dust`, the forge's, forge.lisp) and gold (`:gold`, the settlement's coin) 999.
  Weapons and spells are items too: `:sword`, `:spear` and `:maul` (`:weapon`, what they put in hand), a stack
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
  **Off hands**: each hotbar slot whose stack is a rune may also hold an off-hand rune (the player's
  `offhands`, as long as `hotbar`; slots `:off-1` .. `:off-9`, `*offhand-slots*`, `offhand-index`),
  which the right button casts while that slot's rune is in hand (`offhand-spell`; a weapon's slot has
  none, and `prune-bindings` drops one under a slot that no longer holds a rune). A rune is in one
  place at a time, a slot's or an off hand's: binding it moves it (`unbind-stack`, from `bind-stack`
  and `bind-offhand`). It is set only by a drag in the panel: each rune slot shows its off-hand cell,
  small in its top-right corner (`offhand-position`, `offhand-cell-shown-p`, an `offhand-frame`), over
  which a rune binds it and from which a drag unbinds or moves it; in play the cell shows only while
  it holds one. Bag cells mark the key bound to their stack, or with a ' the key whose off hand holds
  it. A save and the stairs keep them as bag cells (`offhand-cells`, after `hotbar-cells`); an older
  save has none. A rune's cell border is its tier's colour (`*tier-colors*`: green stamina, blue mana,
  plain free). A run starts with `give-starting-kit` (player.lisp's `initialize-instance`,
  `reset-player`): `*starting-hotbar*`'s items in the first cells, bound to keys 1 to 3 (sword, fire
  bolt with Absorb Projectiles in its off hand, heal; an entry is a weapon, a spell or a list of a
  slot's and its off hand's, a spell a name or a spec, `kit-entry`, `kit-spell`), slot
  `*starting-slot*` (the sword) in hand; the rest is found (`src/loot.lisp`). The debug level starts
  with `*debug-starting-hotbar*` instead, keys 1 to 9 (sword, bolt with Absorb, spear, tempest, heal,
  maul, a stamina projectile "Flame Lance", a mana beam "Fire Ray", a stamina "Force Nova"), so the
  recipes below that use keys 3, 4 and 6 work there. The hotbar draws in
  rows of `*hotbar-columns*` (5) over the bars (`hot-position`; in one row of nine the hands covered the
  last), each slot with its key, the one asked for framed in gold, the others' icons dimmed in play, an
  enchanted weapon's border in its spell's colour. A rune's icon is its spell's look's (`stack-icon`:
  weapons and runes from the weapon icons, sword.lisp, `swap-animation` when the strip changes). A save
  and the stairs keep the hotbar as bag cells (`hotbar-cells`, an accessor in `saved-slots` after
  `inventory`), and `migrate-bindings` brings an older save's held stacks into the bag, and
  `migrate-known-effects` teaches an older save what a run now starts knowing (Absorb). `give-item
  player kind count` puts items onto their stacks, then into empty cells (how many went in), and binds
  an unbound Q to the first potion; `take-item` takes from the smallest stacks. Q (`use-quickslot`)
  drinks one of its kind from the smallest stack, not at full; at none it stays bound, dimmed, and
  shows 0. The mouse wheel in play (`cycle-quickslot`) binds Q to the next potion kind the bag holds. I
  opens the panel (`*game-state*` `:inventory`, frozen as `:map` is), I or Esc closes it. Parts of the
  panel are `inventory-part`s (`hud-shown-p` only in `:inventory`) with a `late-rank`, so its
  see-through back never covers world drawn after it. The quickslot has a row of its own above the
  hotbar (`quick-position`), the panel right above it
  (`panel-box`). The hint (`*inventory-hint*`) is wrapped to the panel's width (`hint-lines`, up to three
  `panel-hints`; `panel-box` grows to hold them) and goes blank while the pointer is on a stack, and a
  tooltip beside it (`update-tooltip`, up and right of the pointer, kept on screen; not while dragging)
  gives it in detail, one line each in `stack-details`, wrapped to `*tooltip-width*` (`wrap-text`,
  hud.lisp) up to `*tooltip-lines*`: a rune's delivery, cost and every effect (`spell-lines`,
  `effect-lines`: magnitude, time, area, an element's chill or stagger); a weapon's damage, reach,
  swing time and its enchantment (`enchantment-lines`; the sword's shield too); a potion's restore,
  this stack and the bag's total; dust's and gold's use (`:about`). A rune's says what it costs and,
  unless it is free, why (`tier-line`), and whether it overcharges. Its parts are `tooltip-part`s with
  the highest `late-rank`s, at depths in front of the hotbar's and quickslot's labels (which sit at
  -0.08 for it). A new item is an `*item-kinds*` entry and a frame in `tools/draw_item_icons.py`
  (potions, dust, gold, the reliquary). To try it: `(game (give-item *player* :health-potion 3))` and `(game
  (open-inventory))`; `tools/hd status` shows the hotbar (the slot asked for starred), the quickslot
  and the bag.
- `src/status-icons.lisp` (after inventory.lisp, whose cell size it shares): the player's statuses
  as a row of icons in the top-left corner, under the frame counter while it shows. One cell per
  status in `*status-order*` (damage, slow, heal, ward; one of each kind at most, so four cells,
  and a fifth, `:bless`, for the priest's blessing, which isn't a status but shows as one, from
  the player's `blessed` over `*bless-time*`, and a sixth, first in the row, `:snare`, while a
  bloodroot's roots close on or hold the player, from their `snare`; the unneeded ones not drawn), like a hotbar slot: its border and time bar in the status's colour
  (`*status-colors*`, by element for damage), its icon (`*status-icon-frames*`, a frame of
  `data/sprites/icons/statuses`, drawn by `tools/draw_status_icons.py data/sprites/icons/statuses`, then `tools/restyle.py --house data/sprites/icons/statuses.png`:
  burn, frost, shock, regen, slow, ward, bless, snare), the seconds left (a ward's points instead, which run out
  first) over the bottom-right corner, re-uploaded only when they change, and a bar along the
  bottom for `left` over `duration`. In its last `*status-warn-time*` (3 s) the icon blinks. An
  instant heal or ward-less spell leaves no status and so no icon; its flash is the feedback.
  To look at them: `(game (afflict *player* :ward 12 20.0) (afflict *player* :slow 30 6.0))`.
- `src/hud.lisp`: HP, mana and stamina (SP) bars in the lower-left corner, an AIR bar over them while
  breath is short (`breath-element`; `hud-top` moves up a row with it), and the red pain flash over
  the view (`pain-flash`, from the player's `pain`). HUD pieces are `hud-element`
  entities drawn in pixel coordinates (origin bottom left) at the near plane, in the HUD pass at
  the window's size whatever the render scale (see "Passes" under "Per-frame code"); place them
  on whole pixels, since a half-pixel position drops an edge row. Overlapping elements
  take a depth in `place` (below 0 is further back). `hud-top` is where the bars end.
  `hud-shown-p` decides whether an element draws (by default, not on the main menu). The
  frame counter (`fps-display`) sits in the upper-left corner while `*show-fps*` is on,
  on every screen, counting frames in its render and updating every `*fps-interval*`.
  The hands, like the
  sword, draw at `*weapon-depth*` (hands.lisp), behind every HUD element. The player's statuses are icons (`src/status-icons.lisp`),
  and a ward, the priest's blessing and healing over time also show as **veils** at the screen's
  edges (`status-veil`, one each, `update-veils`): a ward's honeycomb along the left and right
  edges, the blessing's rays in the corners (blinking over its last `*veil-warn-time*`), healing's
  motes rising along the bottom, each `*veil-band*` deep and fading inward in four steps, faint at
  rest and flaring for `*veil-flare-time*` when the effect acts (`flare-veil`: from `absorb-ward`,
  `hurt-player`'s blessing and the heal tick). They are tiles of `data/sprites/veils/veils.png`,
  drawn by `tools/draw_status_veils.py data/sprites/veils`, repeated by the fragment shader at the
  HUD's art pixel size. To see them: `(game (afflict *player* :ward 20 30.0) (afflict *player* :heal 2
  20.0) (setf (blessed *player*) 100.0))`. Gold has
  no label of its own: it is stacks in the bag.
  `show-message` puts a line across the view for `*message-time*` (a glyph's, kill gold the bag
  had no room for, the watch's warnings; `hud-say` formats one), and `*interact-prompt*` under it says what E does with
  what the player looks at or stands at (`prompt-line`; a new string only when it changes, so the
  tick tells by EQ). A pickup of a
  counted item (dust's pile, gold's, a kill's gold) puts "+25 arcane dust" just above
  the crosshair for `*pickup-note-time*` (`note-pickup`, the `pickup-banner`; the item's `:note`,
  else its name), pickups of one kind in quick succession adding up.
- `src/menu.lisp`: the main menu and the Esc pause menu, built with Alloy (Trial's UI
  toolkit) in their own pass, which draws only while a panel is up, laid over the game by the
  HUD pass (`menu-overlay`, main.lisp). Their font is Jersey 15
  (OFL, `data/fonts/`, `*menu-font*`): the menu pass answers Alloy's `:default` request, which is
  Arial in Alloy, with its MSDF atlas, and the build's `hexmaw-fonts` hook (dist.lisp) deletes the
  Arial atlas Trial and Alloy copy in. Alloy scales a font by its baseline, so Jersey 15 draws
  about 1.24 times as wide as Arial did at a size: the character counts that guess where text
  wraps (`*forge-note-chars*`, `*forge-about-chars*`, `*forge-label-width*`, `*dialogue-wrap*`)
  are set for it, and change with the font. To make the atlas again from the TTF:
  `tools/hd '(org.shirakumo.alloy.renderers.opengl.msdf::cache-font (data-path "fonts/Jersey15.ttf") :cache-file (data-path "fonts/Jersey15.json"))'`.
  `*game-state*`
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
  **A panel's column is never sized from its rows.** Alloy sends a pointer event only to the
  children of a layout that contains it, so a row hanging out of its column is drawn but can't be
  clicked, and text measures taller than any guess (Jersey 15 at 20 is 35 px, at 32 is 55): the
  old guessed height left the death screen's button 7 px of its 48 to click. So
  `panel-backdrop` gives the column (`panel-column`, a `menu-column`) the screen's whole height,
  and the column lays its rows in it at their real sizes: centred, or from `panel-top` down as far
  as they leave room, so a panel too tall for its top rises instead of hanging off the screen
  (Settings over the main menu at 1280 × 720). The forge's two columns share one grid row as tall
  as the taller, centred so. After changing a panel, open it and run `tools/hd '(game (menu-layout-problems))'`
  (every element sticking out of its parent, and how much of a row can still be clicked) and
  `tools/hd '(game (menu-click-problems))'` (the pointer moved over a 5 × 3 grid on each row,
  through the menu pass, and the points Alloy doesn't call that row hovered at); NIL from both
  means every row clicks wherever it is drawn. Check at 1280 × 720 and at a bigger window, where
  Alloy's scale changes (`(game (trial:resize *context* 1920 1080))`: 1.25 from 1920 px across).
  **The menu pass owns the mouse cursor, not Alloy.** Alloy set the hand on every move over a
  button and then, since nothing in it takes a pointer move, the arrow, so the cursor flickered
  while the mouse moved. `menu-ui` drops Alloy's sets (`(setf alloy:cursor)`), and after each move
  `set-menu-cursor` makes it the hand over any row (`menu-focusable`, sliders and toggles too) and
  the arrow elsewhere, only when that changes; hiding the last panel puts the arrow back. The third
  check, `tools/hd '(game (menu-cursor-problems))'`, moves the pointer over the same grid and off
  the rows after each, records every cursor set (`*cursor-trace*`), and lists the moves that set it
  other than once on entering or leaving a row; NIL when it is right.
  Settings (`open-settings`, on both menus) covers the menu it came from while
  `*settings-open*` is true; Back or Esc (`close-settings`, which writes the settings file)
  returns to it. It has Fullscreen (`*fullscreen*`), Render scale (`*render-scale-setting*`: the
  world drawn at a whole fraction of the window, full to a quarter, `render-divisor`), Mouse sensitivity
  (`*mouse-sensitivity-setting*`, shown as `sensitivity-text` writes it), Music and Sound
  volume (`*music-volume*`, `*sound-volume*`, music.lisp), Screen shake (`*screen-shake*`, player.lisp), Show FPS (`*show-fps*`), Controls
  (`open-controls`) and, in a debug version (`*debug-version*`), Debug minimap (`*map-debug*`:
  the automap shows every block, creature markers and block names, not kept in the file).
  The rows' variables are in `src/settings.lisp`. A toggle or slider row calls
  `setting-changed` with its variable after each change (Fullscreen's method switches the
  window), and a slider row's optional fourth element is a function writing its value
  (`describe`; a percentage without). The main menu's Debug level and Boss fight are also debug-version only.
  Load game (both menus) and Save game (the pause menu, on a generated level only) cover it
  the same way while `*slot-menu*` is `:load` or `:save`: a row per slot in `*save-slots*`
  (1 to 3, then the quicksave), labelled by `slot-info`, and Back (`close-slot-menu`). After
  a save the pause menu's title says where it went (`*save-note*`). F5 quicksaves and F9
  quickloads (`quicksave`, `quickload`, from the menu controller). See `src/save.lisp`.
  `panel-splash` names a picture in `data/splash/` to cover the screen with (the main
  menu's `title`, the loading screen's `loading`, the death screen's `death`, the victory screen's `victory`, and Settings' over the main menu; see
  "Splash screens" below); NIL, the pause menu's, dims the game behind it instead. `panel-top` places the menu from the top
  of the screen (T, the default, centres it; the main menu's `*title-menu-top*` puts it
  in the maw's throat, under the upper fangs of its splash).
- `src/settings.lisp` (after forge.lisp, whose row helpers it uses): the settings file and the
  Controls screen. **The settings file** is `settings.lisp` in the folder above
  `*save-directory*` (`settings-file`: `$XDG_DATA_HOME/hexmaw/`, `%LOCALAPPDATA%\hexmaw\` on
  Windows; it follows `*save-directory*`, so the build's boot hook covers it), a plist written
  by `save-settings-file` (on closing Settings or Controls, after each rebinding or reset) and
  read by `load-settings-file`, which `launch` (main.lisp) calls before the window opens. It
  keeps `*settings-variables*` (fullscreen, mouse sensitivity, the volumes, screen shake, Show FPS; a new
  setting is a `defvar` there and a row in `settings-menu`) and `:bindings`. A value of the wrong
  kind is ignored with a warning, an action the file doesn't name keeps its default
  (`merge-bindings`), and a file that can't be read leaves the defaults. Trial's own settings file
  isn't used: every Trial game shares it. **Fullscreen** (`apply-fullscreen`) is Trial's `show`
  on the context: the monitor's own resolution, or a `*window-size*` window. The window always
  opens as a window and goes fullscreen once it is up (`main`'s `initialize-instance`); a resize
  has the menu controller make the panel again, since Alloy left its rows uneven.
  **Mouse sensitivity** (`mouse-sensitivity`, what the player's `mouse-move` turns a pixel) is
  `*mouse-sensitivity*` times `*mouse-sensitivity-span*` (4) to the power of 2u − 1, u the
  slider: ¼× to 4×, 1× at the middle. **Controls** (`controls-menu`, while `*controls-open*`,
  over Settings; Back or Esc, `close-controls`) has a page of `*controls-pages*` at a time, two
  columns of `binding-row`s, a note line and Reset to defaults (`reset-controls`). A click on a
  row queues `begin-capture`, so `*capturing*` (input.lisp) holds the action; the next key or
  mouse press reaches `capture-input` (from the menu controller's `key-press` and
  `mouse-press`), which binds it (`rebind`; the note says what was taken from what) or, for Esc,
  cancels. `*capturing*` stays `:done` until every input is let go (`update-capture`, from the
  controller's tick): meanwhile `input-action` answers NIL and the panel's buttons ignore
  clicks, so the press bound does nothing else. To drive it: `(game (open-settings)
  (open-controls) (begin-capture :jump))`, then `(game (issue (scene +main+) 'key-press :key :q))`.
- `src/music.lisp`: music, through Harmony (`trial-harmony`; `main` is its `main`, which starts
  the sound server: PulseAudio here). In play the `music-director` (entered by `add-music` in
  `setup-scene`, which stages every track's voice) plays the level's playlist at random
  (`music-playlist`, from `*music-moods*`: the five exploration and seven combat loops, assets
  `music-explore-1` to `-5`, `music-combat-1` to `-7`, `data/music/<name>.ogg`, on Harmony's
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
  sign or channel keeps its loop in a slot and stops it in its `leave :after`. `cut-sound` silences a one-shot
  `play-sound` returned (the maul's cry, `charge-voice`, cut as its blow comes down). Clips are
  keywords from `data/sfx/index.lisp`; a clip not made yet plays nothing. Each clip keeps
  voices of its own (Trial's sound assets play one copy at a time): `*sfx-voices*` per file,
  taken in turn, the oldest cut short when all are busy, and `*loop-voices*` per loop, made
  once by `add-sounds` (from `setup-scene`) and kept in `*sounds*` across rebuilds;
  `(reload-sounds)` then a reset picks up re-made files. Freeing voices (`free-voices`) frees
  their unpackers too: Harmony keeps a freed voice's for the next voice made, ended and still
  paused if it was, and a clip swapped in on those (after its paused loop or a cut cry was freed)
  played nothing until it was swapped in again. **The game thread never touches a
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
  landing and the firestorm's roar 10, the ogre's footsteps and the blizzard 8). `tune-voice` sets them on a voice as it connects;
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
- `src/hands.lisp`: the first-person casting hands, the weapons' steel gauntlets with fire burning
  behind the fingers, sunk Hexen-style below the bottom edge (idle loop, cast, walking sway). Each
  frame is both hands, drawn at `sword-scale` like the weapons and placed by its aim (`*hands-aim*`,
  the pictures' middle) on the screen's middle; each hand is its own entity drawing its half
  (`hands-split`), `*hands-spread*` (28) art pixels out from the middle, closing up for the frames
  where the fire joins between them (`*hands-together*`: the gather, the fireball held, the release,
  the Absorb void, the ward's honeycomb). The cast's release frame is timed to `*cast-release*`.
  **Motifs** (`*hand-motifs*`, `hand-motif`): a spell cast on yourself shows its own magic, never fire,
  by its first effect. **Absorb**: at rest a small black void in each palm ringed in pale blue; held,
  a void as big as a head between the hands, streaks of light spiralling into it (its `:stance`).
  **Healing**: at rest a band of pale green light running up ribbons round the forearms; cast, the
  ribbons unwind and rise, wrap the forearms tight as it lands, then come apart into motes. **Ward**:
  at rest three gold hexagons over each palm, one above two, each bold in turn; cast, the hands push
  forward, gold lines join the fingertips into a honeycomb pane as it lands, which breaks up. Everything else is **fire**: its idle flicker and the attack's cast. Each
  motif has an idle loop (`:idle`, 4 frames, the ward's 3, `*hands-idle-time*` a frame), a cast (`:cast`, `:cast-frames`,
  `:release`) and Absorb its stance. Each hand shows its own rune's idle (`hand-idle-spell`: the left
  the slot's, cast with the left button, the right its off hand's, cast with the right), so a hand of
  fire and a hand of void sit side by side; a cast or a held spell takes both (`last-cast`,
  `cast-position`, `hands-frame`). A held beam lowers them (`channel-ease`, `*channel-hands-drop*`)
  round the cupped frames, and an overcharge holds the cupped fireball (`*overcharge-hands-frames*`),
  trembling at full (`*overcharge-tremble-rate*`). Each hand's fire takes the look of its spell
  (`hand-look-spell`). A look's strip is `*hand-looks*`, by `spell-look`: a tornado's `:storm`, else
  its effects', one strip per look, each the fire strip recoloured, `tools/recolor_strip.py
  data/sprites/hands/hands data/sprites/hands/<look> --hue H` (storm 268, frost 205, shock 58
  `--saturation 0.65`, drain 345, arcane 295); healing, ward and Absorb, which show no fire, take the
  strip as drawn. Then
  `tools/restyle.py --palette art/style/palette.txt data/sprites/hands/<look>.png`; `add-hands`
  preloads them all, since `swap-animation` changes the strip mid-game. The recipes (the hotbar's
  defaults) work as before: `(select-weapon *player* :1)` is hotbar key 1, the sword at the start.
- `src/sword.lisp` also has **enchantments**: a weapon's spell (a sword's or spear's its own stack's,
  `stack-enchantment`, so two swords differ; the shield's in the player's `enchantments` plist under
  `:shield`; `weapon-spell` asks for the one in hand, `held-weapon-stack`; made at the forge or found,
  `src/loot.lisp`; `migrate-enchantments` moves an older save's `:sword`/`:spear` entries onto the
  bag's first such weapon, after a load and the stairs) goes with every blow of it that lands
  (`enchant-strike`, from `swing-hit` and the bash), for `enchant-cost` mana (`*enchant-cost-scale*`
  of the spell's power, `spell-power`) out of the pool; with too little left the blow is plain, and a miss costs
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
  `tools/draw_weapon_icons.py data/sprites/icons/weapons`, then `tools/restyle.py --house
  data/sprites/icons/weapons.png` (the palette; Absorb's whirlpool is frame 12); a new weapon or effect kind needs a frame
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
  of the blow's damage (a beam pulse's own, `*arc-block-stamina*`, see "The arc votary"); a blow with `:guard-break` (the knight's,
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
  `block-raise` is the shield's guard (`guard-raise-time`, by keyword: NIL for a weapon with
  none), and the guard's blow runs on `bash-time` through generics on the weapon's keyword
  (`bash-frame-times`, `bash-hit-frame`, `bash-strike`: the bash, or the spear's sweep). A swing
  that lands goes through `swing-strike` (player, weapon, target), whose spear method makes a
  counter. `blow-reaches-p` is the test every melee blow makes of one creature (reach, arc,
  height, a clear line), `looked-at-creature` the nearest that passes it. The sprite's tick asks
  `weapon-frame` for its strip frame.
  **A blow that finds no one strikes the wall**: the slash and thrust (`swing-miss`'s default
  method), the maul when there is no corpse to pulp, the bash (`bash-hit`) and the spear's sweep
  (`sweep-hit`) call `wall-strike` with their reach. The line goes from the eye through where the
  weapon's tip is on screen in its hit frame (`weapon-tip-direction`: `*weapon-tips*`, an art pixel
  of the strip's cell, through the sprite's placement, `*weapon-sprites*`, and the camera's fov), so
  the sparks start at the tip at any window size: the sword's blade tip low right, the spear's
  point, the maul head's top, the shield's upper rim, the sweep's spearhead. REACH is how far
  ahead, so an off-centre line reaches as deep a wall. A re-made strip whose hit frame moves needs
  its tip measured again (the topmost opaque pixel of that frame; the sweep's rightmost).
  `wall-strike-point` (gore.lisp) finds where the line first meets a solid, floors and ceilings
  too, and nothing past a liquid: 0.05 m steps of `solid-at`, bisected to the face, the face's
  normal (`strike-normal`; a wedge's diagonal has its own). About 20 µs a blow, and it allocates
  nothing.
  The solid's `solid-strike` (its surface's, `*surface-strikes*`) says what it throws
  (`wall-sparks`, sparks.lisp) and sounds like: `blade-hit-stone` or `maul-hit-stone`,
  `blade-hit-wood`, `footstep-snow`; the bash plays `shield-block`, the haft `bone-hit`. Each
  blow's counts, speed, sound and feel are `*wall-strikes*`, kept below a hit's: the maul kicks
  the view 0.2 to 0.4 and hit-stops 0.02 to 0.04 s by charge (`(:charge least full)`,
  `wall-strike-value`), the bash shoves the player back 1.5 m/s; the sword, the spear and the haft
  have none (the spear's jolt frame pulled its point away from the sparks). `tools/spark_shots.sh`'s
  `wall-*` shots stage each at its hit frame.
- `src/spear.lisp`: the spear, held in both hands, so no shield. Against the sword it reaches further
  (`*spear-reach*` 3.5 m against 2) in a narrower arc (`*spear-arc*` 0.3 rad), staggers more
  (`*spear-pain-bonus*` 35) and is slower: the thrust plays `*thrust-frame-times*` (0.68 s
  against 0.53) and lands at full extension, `*thrust-hit-frame*` (0.24 s in, against 0.23).
  Its sprite (`spear`) is a subclass of the sword's, drawn from `data/sprites/spear/spear`,
  at the sword's art pixel size (`sword-scale`) and sunk as far (`*sword-drop*`), but placed
  by its aim (`weapon-aim`, `*spear-aim*`: the point at full extension) on the screen's
  middle rather than against the right edge, so the thrust goes where the player looks on any
  screen width. A re-made strip whose extended point moves needs `*spear-aim*` measured again
  (`art/spear/spear-frames.txt` says how).
  **The counter**: a thrust whose blow lands on a creature `charging-p` (creature.lisp: hunting the
  player and coming at them through the air, a leaper `airborne`, the imp's pounce or the ogre's
  leap, or a flyer with `dive-left`, the harpy; not a crouch, nor a melee blow's lunge, which stops
  a moment into its wind-up) skewers it (`spear-counter`): `*counter-damage*` (18 to 26),
  `*counter-knockback*`, a flinch whatever the roll (`hurt`'s `:force-pain`; a boss rolls with
  `*counter-pain-bonus*`), the jolt frame for `*spear-jolt-time*` (`spear-jolt`), the enchantment,
  and `impale`: a leaper drops out of the air where it is (`falling`, `impaled`) and lands with no
  quake (an imp's own `react-to-hit` throws it down; a diving harpy is downed as by any hit). A
  knight from a view its shield covers takes it as a plain thrust. The thrust lands 0.24 s after
  the click, so a click late in the crouch or early in the flight meets a pounce or leap, and one
  a little into a dive meets the harpy as it comes down within the player's height.
  **The sweep**: a press of the right button (`:block`, `player-press`, player.lisp; it holds
  nothing up, so the player isn't slowed) swings the haft across (`player-sweep`, `*sweep-stamina*`,
  none without it, nor during a thrust) on `*sweep-frame-times*`, landing on `*sweep-hit-frame*`
  (`sweep-hit`) on every creature within `*sweep-reach*` (1.8 m) and `*sweep-arc*` (1.4 rad):
  `*sweep-damage*`, `*sweep-knockback*`, and the bash's rules for the rest (a stagger only in a
  wind-up and not poised, `bash-poise`; a covered knight glances and the player reels back once).
  No enchantment goes with it. The strip: 4 idle frames, the 8 of the thrust, the jolt
  (`*spear-jolt-frame*`), then the sweep's 4 (`*spear-sweep-first*`).
- `src/maul.lisp`: the maul, two-handed, no shield: the slowest weapon, its blow charged. **The
  charge**: a press of the left button (`player-maul`, from `player-attack`) pays `*maul-blow-stamina*`
  (15; with less, nothing happens) and starts `charge-time`;
  the maul rises for `*maul-min-charge*` (0.4 s, the least charge, whatever the button does), and
  while `attack-held` (a player slot `player-press` sets and `player-release` clears, so a quick
  click is a least-charge blow) it winds on to `*maul-full-charge*` (1.35 s from the press) for
  `*maul-charge-stamina*` (30) a second past the least, about 29 for a full one; with no stamina it
  stops growing. Full, it trembles between two strip frames (`*maul-tremble-rate*`). While it charges
  and through the earthshake (`maul-heaving-p`) the player walks at `maul-speed-scale`
  (`*maul-charge-speed*` 0.6, `*shake-speed*` 0.3), with no run, no jump and no stamina coming back
  (`update-stamina`). Let go once it is up, `update-maul-charge` (from `update-weapons`) puts the
  charge, 0 to 1 (`maul-charge`), in `blow-charge` and starts the swing (`player-swing`, so
  `swing-time` and the swing generics, `*maul-frame-times*`, landing 0.19 s after the release and done 0.4 s later: a quick click
  takes 1 s in all, a full blow 1.95).
  **The blow** (`swing-strike` on `:maul`): one creature within `*maul-reach*` (2.2 m) and
  `*maul-arc*` (0.6 rad); damage, knockback, pain bonus and hit-stop run from the least charge's to
  the full one's by the charge (`maul-lerp`: 18-24 to 34-44, 8 to 15 m/s, 10 to 60, 0.06 to 0.12 s).
  Its knockback has **heft** (`push-creature`'s `:heft`, the square root of `knockback-scale`: the
  knight 0.59, the ogre 0.39; not a boss's, whose cap stands), so it throws things into walls, other
  bodies, lava, deep water and across ice ("Impacts", `src/creature.lisp`): an imp hit full a metre
  from a wall takes about 16 more from it. A full blow always flinches (`:force-pain`; a boss only
  rolls), and on a shield or ward that covers it (`shielded-p`) knocks the guard aside
  (`knock-guard-aside`): the creature's `reel` (creature.lisp, `*maul-reel-time*` 1.2 s, a boss's
  `*maul-boss-reel-time*` 0.5) holds its flinch's stagger frame (`creature-hurting-p`), stops it
  thinking, and makes `shielded-p` false, so a spell reaches its front. Its kills gib from
  `*maul-gib-overkill*` (0.1; `hurt`'s `:gib-overkill`, `gib-p`), the undead's from any overkill, so a
  skeleton it kills always shatters and can't be raised. A blow that finds no one living
  (`swing-miss`, sword.lisp, a generic) pulps a corpse in its reach that `raisable-p` says could be
  raised (`tear-apart`). The enchantment goes with every blow that lands. **The earthshake**: the right
  button (`:block`, `player-earthshake`, `*shake-stamina*` 30, none without it, nor while charging or
  swinging) runs on `bash-time` (`*shake-frame-times*`, landing 0.3 s in, 0.8 s in all):
  `earthshake-hit` puffs `ogre-dust` round the player (`kick-dust`, ogre.lisp) and reaches every live
  creature whose feet are within `*shake-reach-height*` (0.4 m) of the player's and its body within
  `*shake-radius*` (3 m) all round, with no wall between (`shaken-p`): `*shake-damage*` (3-6), a flinch
  whatever the roll unless poised (a boss rolls with `*shake-boss-pain-bonus*`), and a shove out at
  `*shake-knockback*` (5 m/s, with heft). No shield stops it, and nothing off the floor feels it (a
  hovering flyer, a leap or pounce in the air). It shares the bash's poise (`bash-poise`, set to
  `*shake-poise-time*`, 2 s), so the shake, a bash and a sweep never flinch one creature twice running.
  The strip (`data/sprites/maul/maul`): 4 idle frames, the charge's 3 (`*maul-charge-first*`: raised,
  wound up, wound up a pixel aside), the blow's 4 (`*maul-swing-first*`) and the earthshake's 5
  (`*maul-shake-first*`: lifted, coming over, the slam, held, recovery), placed by its aim, `*maul-aim*` (the impact's head on the view's middle).
  The tooltip's weapon lines are `weapon-lines` (inventory.lisp), a generic on the weapon's keyword.
  To try it on the debug level: `(select-weapon *player* :6)`, then `(setf (attack-held *player*) t)
  (player-attack *player*)`, and `(setf (attack-held *player*) NIL)` 1.35 s later for a full blow;
  `(player-press *player* :mouse-right)` shakes the floor.
- `src/player.lisp`: first-person controller and box collision. Walking backward keeps
  `*backpedal-scale*` (0.75) of the speed. A vertical move (`move-axis`) stops short of a solid
  and never passes where it started, so a solid the body is already inside can't drop it through
  the floor. Below `*kill-height*` the player goes back to the start (`respawn`), and the log gets
  the last 2 s of movement, each tick that jumped or ended inside a solid (`report-fall`,
  `*fall-trace*`): send it with a fall. Mana doesn't regenerate:
  only a pickup, a new run or a load refills it, or an Absorb (magic.lisp).
  **Casting** (`player-cast`): what a spell takes is its tier's (`spell-price`: nothing, stamina or
  mana, spells.lisp; `can-pay-p`, `pay`), and with too little it fizzles. A free spell's next cast is
  `*free-cast-cooldown*` (0.5 s) off, the rest `*cast-cooldown*` (0.35). Each hand casts (`cast-hand`,
  `:main` on the left button, `:off`, the off hand's rune, on the right; `hand-spell`, `hand-held-p`),
  but one cast at a time (`busy-casting-p`): the hands share the cooldown, and a held spell or an
  overcharge occupies both. A beam or an Absorb is held (`held-spell-p`, `hold-channel`,
  `update-channel`): a beam strikes every `*beam-pulse*` from the release, paying `beam-pulse-share` of
  its price a strike (`update-beam`), only every `*beam-pain-every*`th strike rolling for a flinch, its
  light from low between the hands (`channel-light-start`); an Absorb strikes nothing. Either ends when
  its button is let go, what it draws on runs out, or the slot changes; the player walks at
  `*channel-speed-scale*` with no run, and a stamina beam or an Absorb stops stamina coming back. A button held
  down with a held spell in its hand starts it as soon as the hands are free (`start-held-casts`,
  every tick): a press during a cast's cooldown or a weapon switch isn't lost, and Absorb held
  through a Fire Bolt's 0.5 s comes up after it; silent while it can't be paid for. **Overcharge**: a
  striking stamina or mana spell (`overchargeable-p`) still held when the hands reach the release stays
  in them (`overcharging-p`, `overcharge-step`), its `overcharge` growing from `*overcharge-delay*`
  (0.25 s) after the press to 1 at `*overcharge-full*` (1.35 s), paying its price again over that
  (stopping when it can't), and goes on release, as `overcharged-spell` (`release-spell`); meanwhile the
  player walks at `*overcharge-speed*` with no run or jump and no stamina back, as with the maul's
  charge. A full one strikes past a shield or ward (`knock-guard-aside`) and makes its target flinch.
  A nova bursts from `*nova-height*` over the feet. `stamina` (`*max-stamina*`) comes back at
  `*stamina-regen*` except while running, which costs `*run-stamina*` a second, on foot or
  swimming with Shift (`update-stamina`); running it empty leaves the player `winded`, walking,
  until it is back to `*winded-recover*`. A jump costs `*jump-stamina*` and needs it, and a blow
  on the raised shield costs stamina too (`hurt-player`, see `src/sword.lisp`). In water to the waist
  (`*swim-waist*`) the player swims, Quake-style (`swim`): W and S along the view, A and D
  level, Space up and C or Ctrl down, at `*swim-speed*` (`*swim-run-speed*` with Shift)
  against `*water-drag*`, sinking at `*swim-sink*` when swimming nowhere below the surface and
  floating with the eye `*float-eye*` over it. Pushing forward into a ledge at the surface no
  more than `*climb-out-height*` over the water, or no more than `*climb-out-depth*` (0.3 m) under it
  (a ford's sill, a waterfall's lip), climbs out (`climb-out`, `ledge-ahead-p`). `breath`
  (`*breath-time*`, 20 s) runs down while the eye is under water and comes back at
  `*breath-refill*`; with none left the player drowns, `*drown-damage*` a second
  (`update-breath`, through `burn-due`). **Camera shake** for heavy blows: `(kick-camera strength)`
  (0 to 1; a kick weaker than what is left of the running one does nothing) jerks the view's pitch and
  yaw up to `*camera-shake-angle*` (0.045 rad, about 21 screen pixels at 720 rows) and its roll up to
  `*camera-shake-roll*` (0.03 rad), to and fro `*camera-shake-rate*` (15) times a second, each swing at
  least `*camera-shake-swing*` (0.6) of the most, falling evenly to nothing over `*camera-shake-time*`
  (0.5 s), unless Settings' Screen shake is off (`*screen-shake*`, a toggle, saved). Moving the eye a few centimetres
  instead shifted nothing past a metre or two by more than a pixel, and a fade eased out (squared) with
  swings down to 0.4 was one nod and some wiggles: an ogre's slam seemed to shake the view once. `kick-camera-from`
  scales a kick by distance (full within 2 m, nothing past its reach). It turns only the view matrix
  (`project-view`), never `location` or `rotation`, so aim, hearing and hit tests stay put; it runs in the
  player's tick (`update-camera-shake`, allocating nothing), so it holds through hit-stop and starts after
  it, shows only in `:playing`, draws from `random` and isn't saved. Kicks: the maul's blow
  (`*maul-camera-shake*` 0.45 to 0.8 by charge, `*maul-full-camera-shake*` 1 full), the earthshake
  (`*shake-camera-shake*` 0.7), the ogre's landing (`*quake-camera-shake*` 1, to 16 m) and slam (0.7, to
  10 m), the boss's Shockwave (1, to 20 m), a crash (`hit-surface`, `*camera-shake-impact*` 0.4 to 1 by
  damage) and a shoved blow taken of `*camera-shake-hurt-from*` (8) or more (`hurt-shake`, 0.3 to 0.9 at
  25: an ogre's slam that lands, 14 to 22, is 0.5 to 0.8). Not the sword or spear.
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
- `src/main.lisp`: `main`, `setup-scene` and its passes, the tick cap, `status`, `launch`,
  `dev-launch`.
- `src/dist.lisp`: the standalone build's entry point (`dist-main`) and its Deploy hooks; see
  "Standalone build" above.

Units are metres, +Y is up, and the player spawns at `*spawn-point*` facing −Z
(north). Collision is axis-aligned boxes in `*solids*`, resolved one axis at a time, and
wedges: a solid with a 7th value is a box with one vertical corner cut away along the
diagonal between the corners beside it (`make-solid`'s `cut`: 1 north-east, 2 north-west,
3 south-west, 4 south-east; `corner-cut`), a 45° wall when the box is square. Its 8th
value is its footing (`src/footing.lisp`) and its 9th its strike kind (`surface-strike`, from
`*surface-strikes*`: `:wood`, `:ice-rock`, `:ice`, `:snow`; none is stone, `solid-strike`),
what a melee blow on it throws; a 0 stands in for a value before one given. Every
question about solids goes through greybox.lisp: `solid-overlapping` (an upright box),
`solid-at` (a point, gore.lisp), `solid-covers-p` (heights over a point); all of them
apply the diagonal (`%wedge-depth`). Moving into a diagonal stops flush against it
(`solid-flush`) and turns the stopped part of the move along the wall (`slide-along`;
the player's `move-flat`, `move-creature`), so walking straight at a 45° wall slides along
it as in Doom. Once a level is built, `index-solids` files every solid under the 4 m
columns it reaches into, and a question looks only in the columns it touches
(`do-solids-near`): a body question takes about 0.08 µs, a point (`solid-at`) 0.06 µs and a
10 m `clear-path-p` 0.025 ms on seed 11, against 75 µs and 5 ms when they walked all 586 solids
with untyped arithmetic. The column arithmetic is typed (`column-index`, the specials read with
`the single-float`): left generic it took twice as long (0.12 µs a point or body). None of them
allocates. To measure allocation, run the loop inside `(game ...)`: `sb-ext:get-bytes-consed`
counts every thread, so measured from the eval thread it adds the frames drawn meanwhile.
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
`tools/hd '(game (setf (vy (rotation *player*)) 0.0 (input-held :w) t))'`, wait, then
`(setf (input-held :w) nil)` and check `tools/hd status`. Yaw 0 faces −Z, π/2 faces +X. Hold
the input the action is bound to (input.lisp): W while Forward is W. A press goes through the
event: `(issue (scene +main+) 'key-press :key :e)` and `'key-release`.

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

### Targets and sides

A creature hunts a **target**, the player or any other actor, and everything below that says "the
player" means its target: attack slots, flanks, lunges, retreats and every monster's specials (the
imp's pounce, the ogre's leap, the harpy's dive, the necromancer's circle and skulls, the wraith's
sign and tornado, the riftwalker's rifts, a boss's powers) aim at it, so an ogre leaps at a guard as
at the player. `hunt-target` is the creature's `quarry`, else the player when it is hostile to them,
so off the settlement it is always the player. What a hunt asks of a target is a small protocol
with a method for the player (player.lisp) and one for a creature (creature.lisp): the body's
`body-feet`, `body-radius` and `body-height`, and `aim-height` (the chest), `target-facing`,
`target-live-p`, `target-guarding-p` (a raised shield: only the player's, so flanking is theirs),
`target-swimming-p`, `strike-target` (the player's `hurt-player`, with the shield, block, guard
break, shove and lift; a creature's `hurt` and a shove, `*creature-blow-shove*`) and `shove-target`.
The helpers read `hunt-target`: `target-within-p`, `target-angle`, `target-distance`, `face-target`,
`target-bearing`, `sees-target-p`. Spells, circles, quakes and rifts strike any actor already; a
homing projectile follows its `homing-target`, what its caster hunted as it cast. What stays the
player's: the shield, block, bash and guard break, theft from the bag (an imp steals only from the
player), the HUD, the spear's counter, the arena's trigger and the watch's crimes.

**Sides.** `hostile-p a b` says who fights whom, from each actor's `allegiance`: `:player`,
`:monsters`, or a faction (the settlement's townsfolk); a summoned creature (a raised skeleton, a
boss's summons) is on its `summoner`'s side. Monsters are hostile to every other side, townsfolk to
the player only while `provoked`, any other faction's people to the player at standing
`*hostile-reputation*` (-50) or under, and none of a side to another of it, unless one bears the
other a **grudge**: three blows (`*grudge-strikes*`, `hurt` only, not burn ticks) within
`*grudge-window*` (12 s) from a creature of another kind (`same-kind-p`: an elite or boss is of its
kind) turn it on that one (`note-grudge`), so a stray ogre landing doesn't set the level fighting.
`*spectating*` (debug) makes nothing hostile to the player, to watch a fight. `notice-targets` every
`*look-interval*` keeps what it hunts while it still sees it, else takes the nearest hostile actor it
sees (`look-for-target`; off the settlement only the player is ever a candidate), and gives up one
dead, at peace with it or out of its reach (`keeps-target-p`: a townsperson goes no further than
`*town-leash*`, 20 m, from its post). Struck by a hostile actor, a creature turns on it unless
what it hunts is in its reach (`harmed`). Attack spots are claimed round each hunter's own target,
among the hunters of that target; a new target starts its spots afresh (`set-target`). A creature
`sent` at its quarry (a raid) keeps after it unseen and walks up to `*sent-max-walk*` (60 m). A blow
between two creatures doesn't hit-stop: only one the player deals or takes, or one from no one (lava).
`(stage-fight a b)` (level.lisp) sets two fighting on the test level, a class, a townsfolk role
(`"guard"`, preloaded there) or a creature each; a class takes a creature of it the level has, so
set `*debug-level-monsters*` to the kinds wanted first.

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

A creature that `flanks` (the imp, the skeleton, the riftwalker) doesn't attack into a raised
shield: within `*flank-range*` and in front of it (`shield-facing-p`, the shield's arc plus
`*flank-margin*`) it walks an arc round the player (`flank`, `*flank-steps*` points) to just past the arc, on
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

### The acolyte

The `acolyte` (acolyte.lisp) hunts from range: it backs off within `keep-away` (4 m) and throws
`cinder`s (fire, 5-8, 9 m/s). Since Absorb Projectiles (magic.lisp) turns hostile projectiles into
mana, a lone acolyte was a mana spring: the player stood holding Absorb and swallowed its cinders
without end. So, from the second level of a run on (`:abilities` in `*run-levels*`,
`level-ability-p`, run.lisp: never on level 1; always off a generated level, the debug level
included), it also calls down a **firestorm**, an ability (`:firestorm`, necromancer.lisp's
`ability`) on `*firestorm-cooldown*` (16 s × `(depth-scale :cooldown)`, starting at
`*firestorm-first*`, 4 s). Its `hunt-from-range` takes it when it is ready, none of its own is up
(`acolyte-storm`), the target is within `*firestorm-range*` (10 m), in sight, on a floor and
neither swimming nor whirled (`firestorm-ready-p`), and one of: the player holds Absorb with the
acolyte in front of them (`absorbing-at-p`), the player has swallowed `*firestorm-swallow-trigger*`
(2) of its cinders since its last storm (`swallowed`, counted by `note-absorbed`, which
`absorb-projectile` calls on the projectile's `launcher`), or a `*firestorm-chance*` (30%) roll on
`*roll-random*` each time it would throw a cinder (`wants-firestorm-p`).

`begin-firestorm` lays a `firestorm` (a `spell-circle` of the spell `firestorm`, radius 2.5 m) at
`floor-under` the target's feet and starts the ability, whose frames are `(0.35 1.25 8.0 0.4)` on
the cast strip, hit frame 2: the raised fireball through the **telegraph** (`*firestorm-telegraph*`,
1.6 s: the sign, `tools/draw_fire_sign.py data/sprites/firestorm`, draws itself in, a fire `aurora`
in `*firestorm-aurora-colors*` rises round it and a lamp brightens), then the release frame held
while it **burns** (`*firestorm-time*`, 8 s; `storming-p`). The storm follows its caster's state as
the gale sign does: a flinch or death in the telegraph takes the sign away (`casting-firestorm-p`;
`*firestorm-retry*`, 4 s, before it tries again), and once it burns, the moment the acolyte stops
holding it (a flinch, its death, the 8 s over) it dies down over `*firestorm-fade*` (1 s). While it
holds a storm, its pain chance is `*firestorm-pain-bonus*` (20) higher. Burning
(`ignite-firestorm`, `burn-storm`), every `*firestorm-pulse*` (0.5 s) it strikes everything with feet
in it but its caster (`storm-pulse`): the player through `hurt-player ... :shove NIL :unblockable T
:by` the acolyte, a creature through `burn` (fire resisted; no flinch or grudge), and both an
afterburn status (`*firestorm-afterburn*`, 2 a second for 2 s) that shows the burn aura and icon:
about 9 a second standing in it. Its centre drifts after the target at `*firestorm-drift*` (2.5 m/s,
`drift-storm`) along the floor, never up or down more than 0.5 m, onto deep water or into a solid:
a walk (4 m/s) outruns it, a walk holding Absorb (2 m/s) doesn't. No shield stops it and Absorb
can't take it. In its middle a column of fire whirls like a tornado (`fire-column`, on the tornado's
`funnel-vao` with shaders of its own: bands of flame spiralling up it over a glowing body, ragged
at the top, hot at the foot, stepped and added light like the aurora's, `late-rank` 0.5), from
`*fire-column-foot*` (0.35 m) to `*fire-column-mouth*` (1.1 m), `*fire-column-height*` (4.5 m) or
under the ceiling, growing up out of the floor over `*fire-column-grow*` as the storm comes down
and sinking as it dies; from inside it shows `*fire-column-inside-fade*` less. Round it the storm
turns (`*firestorm-whirl*`, 1.4 rad/s): two more fire auroras
spin round within the rim, opposite ways (`*firestorm-swirls*`, `storm-swirls`, rising in its flash
and sinking as it dies); flame wisps flare up all over its floor and go round the centre
(`storm-flame`, an `upright-fx` on the burn aura's strip, `*firestorm-flames*` 14 a second, each
`*firestorm-flame-life*`); embers and `:lava` sparks whirl round inside (`storm-whirl`,
`*firestorm-whirl-sparks*`); and cinders fall on it, `*firestorm-cinders*` (5) a second, slanting
with the swirl (`falling-cinder`, the cinder's strip, from `*firestorm-cinder-height*` or under the
ceiling, `nav-room-around` once a second), bursting on the floor with `:lava` sparks; embers rise
round its rim. A save leaves the flames and cinders out, as it does auras. Its sounds are
`firestorm-sign`, `-ignite` and `-roar` (`*spell-sounds*`). A save keeps the storm (`target`,
`burning`, `fading`, `pulse-timer`) and the acolyte's `swallowed`; the storm relinks to its caster on
its first tick. The High Acolyte (boss.lisp) storms too, its pain chance 21 while it holds one.
Measured frozen in the shrine's corridor, vsync off: GPU 2.31 ms a frame looking at a storm from
6 m against 1.82 without, and about 3.2 standing in it against 1.45 (the curtains and the column fill
the view).

To try it on the debug level: `(setf *debug-hall-monsters* t *debug-level-monsters* (list 'acolyte))`,
Debug level, then with the player 4 to 10 m from it
`(let ((a (aref *creatures* 0))) (setf (getf (cooldowns a) :firestorm) 0.0 (swallowed a) 2 (alert a) 30.0))`.
`(acolyte-storm a)` is the storm, `(burning storm)` how long it has burnt; `(hurt a 1 :force-pain t)`
breaks it. With slot 2 in hand, `(setf (block-held *player*) t)` holds Absorb.

### The arc votary

The `arc-votary` (votary.lisp) is a caster, an `ability-user` with one ability, `:arc-beam`, whose
attack is held rather than thrown (a blind storm-priest in storm teal under a crown of lightning rods): the first monster that makes cover, circling and the shield's
stamina matter more than a sidestep. It backs off within `keep-away` (4 m) and starts a beam with its
target within `*votary-range*` (11 m) and in sight. Its frames are `(0.3 0.6 2.0 0.4)` on
`votary-cast`, hit frame 2:

- **The charge** (`*votary-charge*`, 0.9 s; `charging-arc-p`, so a bash or the earthshake breaks it):
  an arc crackling between its hands (`crackle`, through `hand-arc` every `*votary-crackle-time*`,
  closer together and fiercer as it grows), a lamp swelling at them
  (`votary-glow`, `*votary-light-color*`), the `votary-charge` crackle, and a ranging line: faint lightning
  (`ranging-bolt`, every `*votary-aim-time*`), one thread an art pixel wide from the knot between its
  hands to where the beam would stop, broken up and only drawn now and then, firming as the charge
  grows. It turns at its `turn-speed`, `*votary-turn*`
  (2.5 rad/s).
- **The hold** (`holding-beam-p`, up to `*votary-hold*`, 2 s, the release frame held; 3 s, tried first, made a hold
  that wasn't countered about 42 damage): every
  `*beam-pulse*` (0.25 s) `votary-pulse` strikes what `beam-end` reaches along `votary-aim` (from
  its hands, across the way it faces, tipped to its target's chest) with `arc-beam` whole, 3 to 4
  shock a pulse, about 14 a second, through a `beam-pulse` source (spells.lisp): on the player a
  flash, no shove or hit-stop, and a raised shield meets it at `*arc-block-stamina*` (12) a pulse,
  so a full bar lasts about 2.3 s, a whole hold; less, and the pulse goes through and the guard is
  knocked aside. Absorb does nothing: it isn't a projectile. While it holds, its turn is
  `*votary-beam-turn*` (0.9 rad/s, `turn-speed :around`), so running round it within about 8 m
  leaves the beam behind (at 1.2, within 6), and its pain chance is `*votary-pain-bonus*` (20) higher. After
  `*votary-lost-time*` (0.75 s) of pulses striking nothing hostile (behind a pillar, circled), or
  with its target dead, it lets go (`end-hold`) and recovers.
- **What it reaches takes it**, its own allies too, with their flinch and pain: a body in the way
  blocks the beam (and three of its hits from another kind give an ally a grudge against it,
  `note-grudge`). **The floor round what it strikes is electrified** (`floor-strike`, `floor-live`,
  `floor-point`): every other live body standing on that floor (feet within 0.4 m of it, so a jump
  clears it; not in water, which the water rule has; not the votary) within `floor-reach`
  (`*arc-floor-reach*` 3.5 m, the Hierophant's 5) of it, in a clear line, is struck with
  `floor-spell`, the beam at `*arc-floor-scale*` (half, 2 a pulse), through a `floor-pulse` source: it
  comes up from below, so no shield meets it (`effect-unblockable-p`). The body the beam strikes isn't
  struck again by its floor, so a shield that takes the beam still covers the player. Shown as the
  shock nova's bolts with no circle (`floor-bolts`, redrawn with the beam): `*votary-floor-bolts*` a
  redrawing at random spots thinning out toward its reach, so no edge is drawn, most rising off the
  floor and the rest crawling over it, none through a wall from the middle or within 0.9 m of the
  player's eye. Each bolt's foot throws a spark or two (`spray-sparks`, so it stands in the room and
  not on the screen), and a flash lights the floor: one lamp a votary while its floor is live
  (`flash-floor`, `floor-lamp`, `*votary-floor-flash*`), jumping to a bolt's foot at a flickering
  strength each redrawing and put out with the floor (`douse-floor`). A lamp with no source is placed
  in its room once (`update-lamps`), so a votary's lamps are marked to be placed again
  (`located` NIL) whenever they move. Half its pulses play `arc-zap` there. A first try, the beam
  jumping from an ally to the nearest foe and sparing the ally, read as the beam passing through it,
  however it was drawn.
- **Water** (`in-water-p`: feet in `:water` or `:shallows`, or afloat): a body struck in water takes
  `*arc-water-scale*` (1.5) times as much (`wet-spell`, a `scaled-spell` made once), and so does
  every other body in water within `*arc-water-reach*` (6 m) of it, in a clear line, the votary's
  allies too (`water-strike`). A beam that stops on a water surface (`water-beyond-p`) strikes the
  water there, so a swimmer can't duck under it. While it does, the water is electrified as the floor
  is (`water-live`, `water-point` on the surface, `water-surface-at`), redrawn with the beam
  (`water-bolts`): `*votary-water-bolts*` bolts skating over the surface at random spots out to
  `*arc-water-reach*`, thinning toward it, only where there is water under them, none through a wall
  from the middle or by the player's eye, a few spiking up off it; an arc over the surface to each
  other body it strikes (`water-bodies`); and a flash jumping between them (`water-lamp`,
  `*votary-water-flash-radius*`, `flash-lamp`). No sparks: water puts them out.

At rest it crackles, as the shock nova's bolts do (`votary-sparks`, `idle-arcs`, every
`*votary-arc-time*` while the player is within `*votary-arc-reach*`): an arc between its hands
(`*votary-hand-arc-chance*`; not while it charges, whose crackle is there) and arcs between the tips
of its crown's five rods (`*votary-crown-arc-chance*` each pair, the head 8 cm toward its face), sized
by its `sprite-height` so the Hierophant's are bigger. Both lie in the plane its sprite is drawn in.
Creature sprites don't hide bolt lines behind them (the lines are added light and write no depth), so an
arc placed round its body in the world showed through it from behind: the hands' arc, and the charge's
crackle with it (`hand-arc`), go where the view its sprite shows draws its hands (`billboard-view`,
`*votary-hand-spots*`, measured on its turnaround: across, either side, height; mirrored with the
view), and from straight behind, where its body hides them, there is none. Its lamp, at its hands
(`*votary-hand-height*` of its height, where the beam starts), is lit while it lives: at rest at
`*votary-idle-glow*` of its strength in its lightning's yellow (`*votary-light-color*`), so its idle
lightning lights it and what is round it, rising through the charge to full while it holds; dead, it
goes out (`douse-votary`). The held beam is lightning, not the player's ribbon (`beam-bolts`, every
`*votary-bolt-time*`): a broad bolt with a white core and a thinner one forking about it, as the shock
nova's, from its palms where its hold pose draws them (`palm-point`, `*votary-palm-spots*`, as the hand
arcs' spots) to where the beam stops (`bolt-end`), straying `*votary-bolt-roughness*` of its length. On a
creature it ends in the middle of its body at the height struck (`aim-bolt-end`), where its sprite is
drawn: the beam touches a body at the edge of its reach, an imp's 0.55 m and an ogre's 1.2 m short of
the sprite. A bolt ending at the player's eye has no forks and its jagged part stops
`*votary-bolt-clearance*` (1.5 m) short of it (near the camera perspective blew its jitter and forks
up across the whole view); a short, nearly straight stretch carries it on into the bottom of their
view, where their chest is (`last-stretch`, `*votary-bolt-chest*`). The charge's ranging
line is lightning too, but faint (`ranging-bolt`), and ends the same ways (`bolt-span`). The beam's
burst plays where it stops, but not within `*votary-burst-clearance*`
(2.5 m) of the player's eye (on them, or on the water they swim in), where sparks stand in for it.
A hold cost about 0.4 ms of GPU a frame with its first, straight ribbon (seen from 7 m); its lightning, about 150 bolt segments alive at once, isn't measured. Over run seeds 1 to
60 there were 3.3 votaries and 0.6 elite votaries a level from depth 2 on, none on level 1, and the
Hierophant was 4 of the 60 bosses. A save keeps `pulse-timer`, `lost-timer`, `static-charge` and `recoil`; the light, lamp and loop come back in its tick.

**Static recoil**, from level 3 of a run (`(level-ability-p :static-recoil)`), for the player who has
learnt to close in on it: the damage it takes, from anyone, is stored (`harmed :after`,
`static-charge`; it holds for `*recoil-hold*`, 3 s, after the last damage stored, `charge-idle`, then
dissipates at `*recoil-drain*`, 12 a second, its sparks scattering out of it and the whine stopping), and at `*recoil-charge*` (18: a sword blow
leaves it part of the way, the next sets it off; two or three Fire Bolts) it goes off. The tell is
that it goes dark, since a brighter glow would be lost in its own lamp and lightning: as the charge
fills (`recoil-k`) its lamp dims by up to `*recoil-dim*` (`votary-glow`), its idle arcs and the charge's
crackle die away, its sprite darkens toward `*recoil-tint*` (`darken-votary`, every tick, even frozen,
under any stronger hit flash), sparks stream in from `*recoil-ring*` round it into its chest
(`*recoil-motes*`, 130 a second at full and a third of that from the first blow stored, fast enough to
draw as streaks, `*recoil-mote-speed*`) and the `votary-whine` loop rises in volume. Full (`begin-recoil`), it
lets go of its beam and stands `*recoil-beat*` (0.5 s) dark and silent, hands together on a dead knot
(`show-own-pose`), unflinching (`react-to-hit :after`). Then `discharge-static` bursts the
`static-recoil` nova round its chest (`:nova-radius` 4 m, 6 to 9 shock and knockback 8; it spares only
itself), with a `shock-burst` flash, `votary-recoil` and a camera kick, and blinks along a bolt to
`recoil-spot`, `*recoil-blink*` (6 to 9 m) off, away from its target first, in its sight and beyond its
`keep-away` (`teleport-actor`, riftwalker.lisp). `*recoil-cooldown*` (14 s, × `:cooldown`) before it stores
again (`:static-recoil` in its `cooldowns`). The Hierophant's is `hierophant-recoil` (5.5 m, 8 to 12),
and it stays in its arena. To see it: `(setf (static-charge v) 12.0)` for the tell, `17.9` and a blow for
the burst.
It resists shock 0.75 and teaches it (`taught-effect`): killed by a player who doesn't
know shock, it drops the shock glyph. Kill gold 10. It spawns from level 2 of a run on (weight 1 in
both pools), and the 30% spawn of the `pool`, `cistern`, `canal-end`, `creek-cavern`,
`creek-spring`, `creek-sink` and `creek-sink-sump` is `arc-votary|acolyte`, so it stands on their
ledges and banks from level 2 on (an acolyte on level 1). As a boss it is the Arc Hierophant
(`votary-boss`: `hierophant-beam`, 4 to 6 a pulse, its floor electrified 5 m round; a power in play stops its beam).
On the debug level it stands behind the hall's north-west pillar.

To try it on the debug level: `(setf *debug-hall-monsters* t *debug-level-monsters* (list
'arc-votary 'imp) *revive-time* NIL)`, Debug level, then with the player 5 to 11 m off and in its
sight `(let ((v (find-if (lambda (c) (typep c 'arc-votary)) *creatures*))) (stop-walking v 0.0)
(setf (alert v) 30.0))`. The debug level's `pool` (deep water, x -15.5 to -8.5, z -34.5 to -27.5)
has a ledge to stand it on for the water rule.

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
- **Flank leap** (`start-flank-leap`, asked before the pounce in `special-attack`): an imp in
  front of the player (within `*flank-leap-front*`, 1.1 rad, of their facing, `*flank-leap-min*` to
  `*flank-leap-max*`, 1.5 to 7 m) leaps past or over them to a free spot at their side or back,
  with no claw in the air. Only when the front is held (`front-taken-p`: a packmate in reach there,
  claiming a spot there, or pouncing) or the raised shield faces it; only in a pack
  (`*flank-leap-courage*` 1.1, more than a lone imp's whole health); one imp of a pack at a time;
  on the pounce's cooldown, so it is one or the other; never a boss, a thief or a fleeing imp; and
  from level 2 of a run on (`(level-ability-p :flank-leap)`, the run level's `:abilities`; always
  off a generated level). `*imp-flank-leaps*` NIL turns it off. `plan-flank-leap` tries the back, the
  back quarter on its own side, the other, then the sides, each free in `attack-slot`'s sense
  (`slot-free-test`, creature.lisp), at the attack spot's radius, then `*flank-leap-radii*` (1.6
  and 2.4 m); the spot must be `open-spot-p` with no body on it. Its arc is the pounce's low one
  where that misses every body, else a vault `*vault-rise*` up (2.4 in a 4 m room, capped under the
  ceiling, `leap-apex-under`): `arc-clear-p`'s `:bodies` sweeps its box past the player and its
  packmates. Over the head it must come down 1.6 to 2.4 m behind them (it reaches the 1.9 m it
  needs there only 0.25 s from the ground). In a 3 m corridor it can't vault (its feet reach
  1.4 m), and the player fills too much of it to leap past, so it doesn't leap there. In flight it passes packmates that moved into its way since (`leap-passes-bodies-p`, in
  `fly-leap`) but drops if the player steps into it. The tell: the crouch is longer
  (`*flank-leap-windup*`, 0.55 s), lower (`*flank-leap-crouch*`, `attack-squash`), turned to where
  it will land, and screeches (`:vault`, `imp-alert`, not the pounce's `imp-claw`); the landing
  thumps (`step-light`). It claims the spot it lands on (`slot-yaw`), stands `*flank-leap-recover*`
  (0.25 s), and within `*flank-leap-strike-reach*` (1.8 m between bodies) goes straight into its
  claw, lunging in: about 0.6 s from landing to the blow. `flank-leaping` is the landing's yaw from
  the crouch, `:landed` until it sets off again, and is saved: a quicksave with an imp 2.2 m up
  over the player's head (run seed 6, level 2) loaded with it at the same point of its arc, and it
  landed and clawed as the unsaved game went on to, blow for blow. The spear's counter and any blow in
  the air knock it down as they do a pounce; over the head nothing reaches it.
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
theft. For the flank leap, on the debug level (any level but a generated one allows it) stand 4 m in
front of the two hall imps with `*leap-debug*` on and set both hunting with
`(leap-cooldown imp) 0.0`: one pounces or comes in, and the log says where the other leaps ("flank
leap 3.14 rad round, 2.4 m off, apex 2.40"), or why not. `tools/hd status` shows each imp's brain.

`tools/imp_surround.sh [TRIALS] [MODES]` measures how a pack of three surrounds the player
(`tools/imp_surround.lisp`, loaded into the running game): on the debug level with only its imps,
the player, health topped up, either tracks the nearest imp (`track`: turning to it at 3 rad/s and
backing off 2 s in 4) or faces north and strafes (`strafe`), 20 s a trial, with the flank leap off
and on and the shield down and up. It prints the seconds imps stood in reach in front, at the flank
and at the back, the claws from each and those blocked, the flank leaps and those cut short, touches
between imps, and when an imp first stood at the flank or back.
Over 5 trials of each, the flank leap made 4.2 leaps a trial against a tracking player with the
shield down, 5.2 with it up, 1.6 and 3.4 against a strafing one; 6 of those 72 were cut short. With
it, the share of the time imps stood in reach at the flank or back rose from 37% to 43% against the
tracking player with the shield down (claws from the back 0 to 0.8 a trial, the first flank or
back contact 3.8 to 2.9 s), from 79% to 86% and 79% to 84% against the strafing one, and fell from
51% to 48% against the tracking player with the shield up, where it turns to each imp as it lands.
Walking round already put the pack at the player's flank: the leap gets there about a second
sooner, more than it changes where the pack ends up. Touches between imps: 3.0 to 6.0, 10.8 to 5.0,
5.4 to 7.0 and 8.0 to 8.8 a trial.

### The bloodroot

The `bloodroot` (bloodroot.lisp) is a heart-bulb 1.4 m tall, rooted in the floor (`rooted-p`): it never
walks (`wander` only waits, its hunt never closes in or backs off), its `momentum` is zeroed every tick,
no vortex takes it, a riftwalker never calls it (`callable-p`), and it turns to what it would hunt, so it
notices all round. 110 health, pain 10. It spawns on the third `*run-levels*` entry only: its pool, and
the `hall`'s and `crypt`'s named spawns (`bloodroot|...`, which the pool filter drops on earlier
levels, so their picks stay); a settlement before the last level borrows that level's pool without it
(`*last-level-kinds*`, `settlement-keys`, run.lisp). It isn't in `*spawn-pool*`: the debug hall
spawns one by name, west of the middle, after every other `debug-spawn`. Its body (0.6 m) can stand in
a way, on a cistern's 2 m ledge or between a vestry's benches: `build-level` takes out every one whose
body alone cuts a doorway off from the spawn point (`uproot-blockers`, kit.lisp, after `spread-packs`;
it draws nothing, so the layout stays), and `tools/levelcheck --strict` fails a level where one still
does. Over run seeds 1 to 60 it was 183 bloodroots on 57 of the 60 last levels before uprooting, 4 of
them in a way; none on any other level or in the settlement. Its sounds are `bloodroot-*`,
`seed-impact` (its root diving into the floor), `bloom-swell`, `bloom`, `root-drink`, `snare-*`,
`roots-burn`, `burrow-rumble` (a loop at the burrowing root's head, `burrow-sound`) and `burrow-erupt`
(`audio/sfx.md`). Its lamp (`update-bloodroot-light`) is a dim red glow at rest, swelling to
`*bloom-light*` through a Bloom's tell, and out once it is dead.

**Its roots.** A `root-carpet` (not an entity: the bloodroot owns it) is a window of the nav grid's
cells round where it grew from, every layer, each empty, rooted or burnt (and a rooted one frosted
for a while). It grows a ring every `*root-ring-time*` (0.4 s, halved in Glut, faster for a haste
elite; `root-speed`) while the bulb hunts, from its frontier through `nav-step` at a thin body
(`*root-body*`), so never through a plugged doorway, over lava or into water, out to `*root-reach*`
(10 m; the Mother Root's 20). Each ring its edge, a circle round where it grew from
(`carpet-spread`, saved), moves out `*root-spread*` (0.1 m, 0.25 m/s), and a frontier cell grows only into
neighbours inside it, so it spreads round rather than in the squares a cell's eight neighbours make;
toward its target or a floor splat within `*root-lean-reach*` the circle bulges, up to twice as far
straight toward one (`lean-factor`), and a burst of rings (its first three, a Bloom's surge, a seed's)
moves it twice as far all round. A rooted cell beside a wall
notes the wall's face and how high it goes (`find-walls`), and the roots climb it to `*root-climb*`
(2.5 m) over `*root-climb-time*`, a look only. The arena's gate, a solid the nav grid doesn't know,
is checked by `solid-at`. `roots-at x y z` is the bulb whose live roots a point stands on.

**Underfoot** (`feed-on`, only its target: monsters cross unharmed). Grounded on its roots, the
player is slowed `*root-slow*` (a `:slow` status) and drained `*root-drain*` (3) a second, taken
every `*root-drain-tick*` as whole points (`hurt-player ... :shove NIL :unblockable T`), the bulb
healing what they lost. `*snare-stand*` (1 s) on them, unless `snare-guard` still runs, starts the
**snare** (the player's `snare`, player.lisp): a `*snare-tell*` (1.1 s) tell, `*snare-sprites*` (6)
`snare-sprite`s, 1.4 m roots, shooting up out of the floor in `*snare-rise*` and writhing in a ring
`*snare-sprite-ring*` (1.1 m) round the feet, far enough out that they reach the lower third of the
view looking straight ahead (closer in, they stood under the view). Off the floor at any moment of
the tell (a jump) or more than `*snare-reach*` from where it started, the roots close on nothing.
Otherwise they hold (`snared-p`: no walk, run or jump, on ice too; hands and casts work) for
`*snare-hold*` (1.5 s) at `*snare-drain*` (8) a second, taller roots (2.2 m, `snare-grip`) surging up
in the tell's place, arching over and coiling, over half the view's height. Any blow of the player's
as it lands, not as it is pressed (`break-snare`: the swing's hit frame, `swing-hit` in
`update-weapons`, so a slash, a thrust and the maul's blow; a bash's, a sweep's and the earthshake's,
`bash-strike`; a spell's release, `release-spell`, and a beam's first strike), the earthshake also
tearing up the roots within its reach (`tear-roots`), fire or frost reaching the cell, or the bulb's
death free the player; each starts `snare-guard` (`*snare-guard*`,
2.5 s). The status icons show it (`:snare`, first in the row, a red border): blinking through the tell,
steady while it holds, with its seconds left.

**Drinking** (`drink-splats`), made to be seen: dark blood on the red carpet was lost even drawn over
it (the roots lie `*root-floor-lift*`, 2.5 mm, under the splats). Every `*drink-scan*` a splat lying
on its live roots (a floor splat over a cell, a wall splat beside one below the roots' climb) starts to
glow (`set-splat-glow`, bit 6 of the splat's side, which the blood shader draws lit from within in
bright crimson, pulsing `*splat-glow-rate*` a second). After `*drink-delay*` (1 s) glowing it is drunk
(`start-splat-drink`, `start-drink`): for `*drink-time*` it sends up `*drink-motes*` blood motes and
`root-drink` plays, then the splat itself, made round (`flow-splat`, gore.lisp: bit 7 of its side,
which the roots' scan leaves alone), slides along the floor straight to the bulb at
`*drink-flow-speed*` (4 m/s; `carry-splat`, `move-splat`), and dissolves as it arrives. A wall splat
dissolves where it is and a flowing one of its blood sets off from the floor at its foot
(`spawn-flowing-splat`). Under it the roots and tufts glow: round drops, the leading one
`*drink-flow-width*` across its radius and two smaller ones trailing it within `*drink-flow-tail*`,
hot pink at the head, stepped in whole texels (`drink_glow` in both root shaders, from uniform arrays
of `*max-drink-lanes*`, `set-drink-uniforms`). A bulb dying or reviving dissolves the splats it was
carrying (`spill-drinks`). As it arrives (`drink-arrives`) the bulb
flushes red for `*gulp-time*` (`own-tint`) and heals `*drink-per-area*` of the blood's area, at most
`*drink-max*`. A splat drunk within `*drink-merge*` of one not yet on its way joins it, and a bulb has
`*max-drinks*` under way. Its `drinks` and `gulp` are saved. `*glut-drink*` (15) arriving within a second
sets off Glut. Its own wounds spray sap (`:drain` embers), not blood (`bleeds` NIL), or it would heal
off every hit.

**The burrowing root**, its attack (`:burrow`, cooldown `*burrow-cooldown*` 3 s, 1.5 in Glut, first
after `*burrow-first*`; `attack-damage` its harm, so it hunts): at a target in sight between
`*burrow-min*` (2 m) and `*burrow-range*` (20 m), on the spit strip's frames, a root runs under the
floor at `*burrow-speed*` (9 m/s) toward where they stood (`start-burrow`, `update-burrow`), throwing up
grit, sparks and dust as it goes and leaving a trail of roots bursting up behind it (`sprout-trail`,
`burrow-root`: every `*burrow-trail-step*` a tuft of the `root-tendrils` strip within
`*burrow-trail-jitter*` of its line, every `*burrow-spike-every*`th a tall thorned root of the snare's
strip, each rising over `*burrow-rise-time*`, standing and sinking back over `*burrow-sink-time*`;
a save leaves them out). It erupts there (`end-burrow`, `burrow-erupt`): a patch of roots grown at once
(`plant-seed`, `*burrow-rings*`, `*seed-patch-radius*` 1.25 m) that drains and snares as the main
carpet does and lasts `*seed-patch-time*` (12 s), shrinking over its last second (a bulb keeps
`*max-seed-patches*`, 4); its harm (5 to 8, no shield) to a player within `*burrow-reach*` (1.2 m) on
the floor, and the snare's tell under them. A sidestep or a jump dodges it; a wall, a gap, a step or a
liquid stops it. It is saved (`burrow`). So it fights at every range with one attack, and its patches
are how its roots reach a player who stands off. **Bloom** (`:bloom`, cooldown 20 s, first after `*bloom-first*`): with the target within
8 m in sight, or `*bloom-crowd*` (4) bodies in reach past `*bloom-crowd-gap*`, a 1.2 s tell (the
clench held, its lamp swelling red, motes drawn in, `bloom-swell`; a flinch breaks it), then `bloom`,
a drain nova of `:nova-radius` 8 m (`*bloom-radius*`) that spares only the bulb and no shield stops
(`*unblockable-spells*`). It heals the bulb all it drains (`drain-share` 1), its own side's too; then
its roots surge `*bloom-surge*` rings and it gluts. **Glut** (`*glut-time*`, 6 s): roots twice as
fast, burrowing twice as often, and the sprite washed red, pulsing 0.35 to 0.5 twice a second
(`own-tint`, creature.lisp, after the flash and status tint, only where stronger).

**Fire, frost and the maul.** `touch-roots at radius element`, from `strike-skins` (skins.lisp:
bursts, novas, a projectile's impact at 1 m at least, a beam's end, the firestorm's pulses): fire
burns the rooted cells there (burnt, regrowing from their neighbours after `*root-burn-hold*`), frost
holds them for `*root-frost-time*` (no growth, drain or snare; drawn rimed), `:tear` (the earthshake)
as fire. A rime patch over a carpet holds the cells under it (`frost-under-rime`, each ring). Its
death withers every carpet over `*root-wither-time*`.

**Drawing.** One `root-floor` (`add-root-floor`, `setup-scene`) draws every carpet from one buffer:
a quad per rooted cell on its floor and one up each wall beside it, as high as the wall goes. Each
corner carries its cover, the share of the four cells round it that are rooted, and the shader cuts
the edge where cover falls short of a hashed threshold in clumps of texels, so it is ragged rather
than square; each vertex carries when its cell rooted, and the shader spreads it in over
`*root-grow-in*` and climbs its wall from then on `*root-clock*`. So the cells are written only when a
carpet changes (`*roots-dirty*`), 0.2 ms for a full carpet of 1032 cells (each cell's floor is kept,
`carpet-floors`, and the loops are typed). The texture is `bloodroot-roots` (`data/textures/bloodroot.png`,
keyed to see-through), lit as floors and walls are. Measured with 1032 cells and their walls
filling the view, world frozen, vsync off: GPU 3.69 ms a frame against 2.40 without the root floor.
Lying flat, dark red-brown on a brown floor, the carpet was easy to miss, so it stands up and glows.
**Tufts** (`root-tufts`, `*root-tufts*`, entered with the floor and written with it, `write-tufts`):
on `*root-tuft-share*` (0.55) of the rooted floor cells one of the eight tufts of the `root-tendrils`
strip (`data/sprites/bloodroot/tendrils`, 25 to 50 cm), picked, placed within `*root-tuft-jitter*` of
the cell's middle and sized within `*root-tuft-scale*` by a hash of the cell (`tuft-hash`, so a rewrite
puts it back where it was), turned about +Y to face the camera plane as a billboard is, its tip
swaying by whole art pixels; it rises out of the floor over `*root-tuft-grow*` once its cell roots
(staggered by up to `*root-tuft-stagger*`) and sinks back as its carpet withers, the floor hiding the
rest. 599 tufts on a full carpet, rewritten in 0.12 ms with nothing allocated; GPU 4.9 ms a frame
against 4.2 without them, the whole carpet in view. **The heartbeat**: in both shaders the veins (the
texture's saturated reds, `root_beat`) glow unlit, fogged as lamp light, at `*root-vein-glow*` and
flare by `*root-beat-glow*` as a lub-dub every `*root-beat-period*` (1.3 s) runs out from the bulb at
`*root-beat-speed*` (6 m/s; each vertex carries its distance from its bulb), stepped in quarters;
frost puts it out.

**Saving.** `root-state` turns its carpets into plain data (cells by window index, how long ago they
rooted, burn and frost left) and back, finding their walls and frontier again on the rebuilt nav grid;
the player's `snare` and `snare-guard` are saved too. **Elite and boss**: `elite-bloodroot` (haste
grows its roots faster; never `:warded`, since it always faces the player); the Mother Root,
`bloodroot-boss` (traits `:caster :rooted`: no leap, blink, tornado or ward), its roots over the whole
arena. Kill gold 18; it teaches drain (`taught-effect`).

The debug level lays puddles of blood round each bloodroot as it is built and whenever one revives
(`lay-debug-blood`, `*debug-blood-spots*`, 2.5 to 7 m off), which its roots reach and drink one after
another. To try it on the debug level: `(setf *debug-hall-monsters* t *debug-level-monsters* (list 'bloodroot))`,
Debug level, then `(setf (alert root) 30.0)` with `root` the bloodroot in `*creatures*`;
`(rooted-count (carpet root))`, `(patches root)`, `(snare *player*)`; `(start-ability root :bloom)` for a
Bloom, `(start-glut root)`, and `(strike-skins :fire (vcopy (feet *player*)) 1.5 nil)` to burn.

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
a found item that is never plain (an enchanted sword, spear or maul, or a generated rune;
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

### The rime hag

The `rime-hag` (hag.lisp) is the frost caster, an `ability-user` that hunts from range: 1.7 m, 30
health, pain 30, a slow hobble (`walk-speed` 1.0, `chase-speed` 1.7), `keep-away` 3.5 m. She is
the first caster that punishes a player who closes in. Her `hunt-from-range` takes, in order:

- **Frost nova** (`:frost-nova`, `hag-nova`, cooldown `*hag-nova-cooldown*`, 9 s): her target
  within `*hag-nova-trigger*` (3 m), on a floor and not swimming. The tell is a 1.0 s gather
  (frames `(0.3 0.7 0.25 0.4)`, hit frame 2, the nova strip's hunched frames): `hag-gather` plays,
  a cold lamp swells (`*hag-gather-light*`), frost motes are drawn in toward her chest
  (`update-gather`), and her pain chance is `*hag-gather-pain-bonus*` (20) higher. Then a frost nova
  bursts round her chest, reaching 5 m (the spell's `:nova-radius`): 8 to 12 frost, a 35% slow for
  3 s and knockback 4, striking her allies too, and a rime patch round her feet. A run (7 m/s) from
  3 m is out of reach in the gather; a walk barely. A raised shield takes the damage but not the
  slow. A bash in the gather interrupts it three times in four (`winding-up-p`: her 30, the gather's 20
  and the bash's 50, at most `*max-pain-chance*`), and the earthshake's flinch always does.
  The spear's 3.5 m reaches her from outside the trigger.
- Backing off a target within `keep-away` (`retreat`).
- **Rime field** (`:rime-field`, cooldown `*rime-field-cooldown*`, 12 s, from `*rime-field-first*`;
  `(level-ability-p :rime-field)`, so from level 2 of a run): a slower ball (`rime-field`, 9 m/s,
  2 to 4 frost over 1.5 m) at the floor `*rime-field-lead-time*` of its movement ahead of the target,
  at most `*rime-field-lead*` (1.5 m; `rime-field-point`), within `*rime-field-range*` (11 m). Where it
  bursts, on a body (round its feet), the floor or a wall, `spell-impact` lays a rime patch
  (`lay-frost-patch`, skins.lisp): `*rime-patch-radius*` (3.5 m) for `*rime-patch-time*` (10 s),
  freezing her foes on it for `*rime-freeze*` (1 s), and icing the walls round it. Absorb takes it
  only if the player walks into it.
- **Rime shard** (`:shard`, `rime-shard`): a frost projectile, 10 m/s, 4 to 6 and frost's chill, on
  the player's frost look. Absorb swallows it for mana, once: then she **shuns** the player
  (`shuns-target-p`).

Before all but the nova, from level 3 of a run (`(level-ability-p :blizzard)`), with her target 3 m
off or more: the **blizzard** (`:blizzard`, cooldown `*blizzard-cooldown*`, 18 s from its cast, from
`*blizzard-first*`; the cast strip's 0.75 s to the raise). A storm round her, `*blizzard-radius*`
(6 m; a boss's 1.25 times it) across and `*blizzard-height*` (3.5 m) up, for `*blizzard-time*` (10 s),
rising over `*blizzard-form*` and dying down over `*blizzard-fade*`, at once when she dies. It is a
**wind** (`*winds*`, spells.lisp: `wind-turn`, `wind-slow`, `add-wind`; the tornado is one too): every
projectile but hers flying through it turns `*blizzard-turn*` (1.2 rad/s) about +Y the way it blows,
times its own `gust` (`*wind-gust*`, 0.6 to 1.4, drawn from `*roll-random*` as it leaves and saved, so
a long shot can't be aimed off for it; `blow-projectile`). So the Fire Bolt at her middle strikes from
3 m every time, from 4 m about four in ten, and from 5 m or the rim never (measured, 10 shots each).
Her foes inside it walk at `*blizzard-slow*` (0.6) of their speed (`slow-factor`, magic.lisp, takes the
winds with the statuses, down to `*slowest*`), and the player hears the tornado's rushing wind,
quieter (`*wind-volume*`). While it blows and her nova is ready, a target it holds back draws her in
(`chase`) instead of a shard or a retreat: close in to hit her and she walks in with the nova. A beam
isn't bent, nor a touch or a blow. Each cast turns it clockwise or counterclockwise at random
(`blizzard-sense`, saved), its flakes and the way it bends projectiles alike. All that shows of it is
snow, with no edge drawn: `*blizzard-flakes*` (1200) a second, each `*blizzard-flake-life*`, so up to
about a thousand at once in the open (590 by the debug hall's north wall, where rock takes many) in the spark pool, flake
particles (`blow-snow`; sparks.lisp) that its wind carries round her (`wind-carry`, an exact turn
about her feet at `*blizzard-flake-speed*` times each flake's own, `*blizzard-flake-speeds*`), drawn
as white and pale-blue streaks as long as their speed (the `:snow` ramp). They start thinning out
toward its edge (`*blizzard-flake-spread*`) and out to `*blizzard-flake-reach*` (1.2) times it, so it
fades off rather than ends. Its sound is its own loop, `blizzard`, a roar of driving snow and icy
wind (`*blizzard-volume*`, full within 8 m, `*clip-min-distances*`). Her
`blizzard` (seconds left) is saved; the rest comes back from it (`light-blizzard`). To see one on the debug level: `(setf (blizzard hag) 9.0)`.

**Shunning Absorb.** A lone caster throwing nothing but projectiles was a mana spring for Absorb, as
the acolyte was. So for `*hag-wary-time*` (10 s, her `wary`, saved) after Absorb swallows one of her
shards (`note-absorbed`), or while she sees it held at her (`absorbing-at-p`, acolyte.lisp, renewing
it), she throws no shards: one in its wind-up when Absorb comes up is kept (`release-attack`). She
throws the rime field where she may, dropped `*rime-field-short*` (1.3 m) short of the target toward
her (`rime-field-short-point`), so it bursts on the floor and not on them, and otherwise comes in to
`*hag-wary-reach*` (2.5 m), inside the nova's trigger, and waits there facing them for the nova. So a
player holding Absorb at her gets one shard's mana (about 4.5) and her nova, and one timing Absorb to
her shards' flight one shard every 10 s.

Her rime is ice underfoot for the player and every creature but her (`slips-on-rime-p`), so imps
skid on it and are knocked into walls; fire melts it (`strike-skins`: the Fire Bolt's impact, a
fire burst or nova, the firestorm). No rime lies on lava, water or shallows; a swimming target gets
shards only. She takes a quarter of frost and half again of fire (`*element-resistances*`), and
killed by a player who doesn't know frost she drops its glyph (`taught-effect`). Her pools: levels 1
and 2 of a run (`("rime-hag" 1)`), and the ice caves name her on any level (`frost-shrine`'s
`acolyte|!rime-hag`, a `spawn !rime-hag south 30` in `ice-cavern` and `ice-grotto`). Kill gold 9. As
an elite, `elite-hag`; as a boss, the Winter Crone (scale 1.7, traits `(:caster)`), her nova
`hag-nova-boss`, 7 m. Over run seeds 1 to 60 (`tools/levelcheck --runs 1-60`), 1.85 a level on the
first level (52 of 60 had one), 2.3 to 2.7 on the second, 9 on the 60 last levels (the ice caves'),
8 in the 60 settlements (which take the second level's pool), none stranded. A rime patch filling
half the view cost about 0.9 ms of GPU a frame in the test hall (2.5 to 2.9 ms without, vsync off,
world frozen), her nova over it 0.6 more. On the debug level she stands by the north wall between the necromancer and the
wraith (`(setf *debug-level-monsters* (list 'rime-hag))`). To try her:
`(setf (alert hag) 30.0)` with the player 8 m off for shards, within 3 m for the nova, and
`(setf (getf (cooldowns hag) :rime-field) 0.0)` for a field.

## Generating art

`tools/gen_image.py` generates images with OpenAI's image models, so prompts don't need
to go through ChatGPT by hand. With `--ref` images (a design reference, a turnaround,
a Blender render) it restyles or extends them; without, it generates from the prompt alone.
Output lands at full resolution where you name it, with a `<stem>.prompt.json` beside it
recording the prompt, references and options:

```bash
tools/gen_image.py art/imp/attack-1.png --prompt-file art/prompts/imp-attack.txt --ref art/imp/walk-front.png --size 1536x1024
```

By default it goes through the Codex CLI (`codex exec`, signed in with the ChatGPT
account), whose built-in image tool counts against the ChatGPT plan instead of being
billed. Codex runs locked down (no shell, plugins or browser) in a temp folder. One image
per run, about 45 s, so run it in the background; `-n 3` makes three runs. Size and
background are requests in the prompt (1536x1024 came back exact), and `--quality` does
nothing there. `--backend api` calls the paid Image API instead (key in `$OPENAI_API_KEY`
or `~/.config/openai/api_key`), which honours size, quality and `--mask` exactly.

**Waiting for a background job: never loop on `pgrep -f PATTERN` (or `pkill -f`, `ps | grep`)
whose PATTERN is in the waiting command's own text.** The waiting shell's command line contains
the pattern, so it matches itself and the loop never ends: `while pgrep -f "gen_image.py art/x"; do
sleep 2; done` hung for an hour after a 93 s generation, and not for the first time. Run the job
itself as the background command and be told when it exits, or wait on its PID (`wait $pid`, or
`while kill -0 $pid`), or wait for its output file; if a pattern is unavoidable, bracket a
character so it can't match itself (`pgrep -f '[g]en_image.py art/x'`).

Neither keeps a conversation the way ChatGPT does: every call carries the full prompt and
every reference it needs, so a follow-up pose attaches the earlier result as a `--ref`.
Keep prompts worth repeating as files under `art/prompts/`, and `--dry-run` a new command
line to see what will be sent.

## Where art lives

`art/` holds the record of how every asset was made: the prompts (`art/prompts/`), each
generated image's `.prompt.json`, frames files, and the source images themselves. The
generators don't give the same picture twice, so the chosen take is the only copy of it.
Images under `art/` are in **Git LFS**
(`.gitattributes`): a commit holds a small pointer, the picture lives in `.git/lfs/objects/`
and, once pushed, in the LFS store of the private repository `gwathlobal/hexmaw-art`, not the
public one (`.lfsconfig`'s `lfs.url`). `.lfsconfig` also has `lfs.fetchexclude = /art/**`, so a
stranger's clone keeps the pointers and downloads nothing: public downloads would count against
the account's 10 GiB a month. The author's checkout overrides it once, `git config
lfs.fetchexclude ""` (worktrees share that config), and then fetches and checks out art as ever.
`data/`, what the game ships, is plain git: the build reads it. git-lfs
must be installed (`apt install git-lfs`, then `git lfs install` once); after that `git add`,
`commit` and `checkout` work as ever, and the files on disk are real PNGs.

Nothing pushed to GitHub's LFS can be deleted short of deleting the repository, so **commit
only the take chosen for an asset**, and whatever its `.prompt.json` lists as `refs` (what the
chosen take was made from). Name it where it is used: the command line in this file, or a
frames file. Commit every `.prompt.json` and prompt. Never commit the other takes, stacked
sheets (`*-sheet.png`, rebuilt by `tools/stack_views.py`) or `make_texture.py`'s `*-tiled.png`
previews (both ignored). `tools/art_refs.py` lists which images something names (KEEP) and
which nothing does (ATTIC, the candidates); `tools/art_refs.py --check` fails on a tracked or
staged candidate, or on a group of takes none of which is named (UNDECIDED: write down which
was chosen). Run it before committing art. Candidates go to
`../hexmaw-art-attic/` beside the main checkout, under the same paths (`MANIFEST.txt` there lists the
first lot), or are deleted. A folder whose files are all untracked is taken as work in
progress and left alone.

## House style

The art comes from many generations and scripts; these rules keep it reading as one set. A viewer
of the first trailer called it "amalgamated": the art pixels of an area burst were five times the
monsters', the hands' wider than tall, the walls soft and low in contrast beside sharply outlined
sprites, each asset on colours of its own. The before and after shots are in
`../hexmaw-art-attic/consistency/`.

- **Density.** World art is 64 art pixels a metre (`*texels-per-metre*`), 48 to 96 at most: a
  strip's `define-fx-animation :size` is its cell height over 64. The torch (135) and the grave
  skull's flight (100) are the accepted exceptions (`tools/art_audit_allow.txt`). An effect that
  grows (an area burst, an aura on a boss) adds copies at its own size rather than scaling one
  (`burst-shells`, filling the burst's ball, and the aura's copies).
- **Screen scale.** First-person art draws at `sword-scale` (3 screen pixels an art pixel at 720
  rows, 5 at 1080), with square pixels; the HUD's art at `hud-pixel-scale` (2 and 3); HUD text is
  Jersey 15 at its own 27 px grid, 1:1 (`tools/make_hud_font.py`). The casting hands draw at
  `sword-scale` too.
- **One palette.** Every sprite and texture is on `art/style/palette.txt`, 128 colours in ramps,
  made by `tools/make_palette.py` from the art itself; splash screens keep every colour. A slicer's
  or recolour's output goes through `tools/restyle.py --house` (below); a texture through
  `make_texture.py --palette art/style/palette.txt`, with the stones at `--contrast 1.6` and the
  off-family ones moved into the wall's warm grey-brown with `--tone 3 8`.
- **Shading.** Lit from the upper left with a few hard tones, no gradients finer than the pixels,
  no part-transparent pixels (the shader cuts at half alpha). Solid things (creatures, townsfolk,
  pickups, the gate, the torch, the hands and weapons) have selective outlines: the black outline
  turned into a dark tone of what it borders (`pixelart.selout`). Effects keep theirs.
- **Script-drawn art** finishes each frame with `pixelart.house_finish` (`relief`: bevel, a
  rounding gradient, grooves round glowing strokes, seeded grain; then sel-out and the palette), as
  `draw_glyphs.py`, `draw_loot.py` and `draw_gold.py` do.
- **Shaders** that draw over the art keep to its grid: the funnel, the aurora and the liquids'
  waves work in whole texels of the 64-a-metre grid, and the aurora steps its light
  (`*aurora-light-steps*`). The hit flash peaks at 0.5 and the rim glow is a lit edge (`*rim-mix*`).
  The light itself stays smooth (`*wall-light-snap*` and the bands at 0): stepped, texel-snapped
  light was tried and not taken.

After slicing or recolouring a strip:

```bash
tools/restyle.py --house data/sprites/imp/walk.png
```

(the house rule by path: the palette for every strip, sel-out for the solid things; run it once on
fresh output.) Every command line in "Monster sprites" and the sections after it that writes into
`data/sprites/` is followed by this. New prompts attach `art/style/anchor.png` (the imp, knight,
wall, floor, flask and sword together, made by `tools/art_sheets.py --anchor art/style/anchor.png`)
as a style reference and include `art/prompts/style-common.txt`; the palette step holds the colours
whatever the generator does.

Checking: `tools/art_audit.py` measures every shipped image (art pixels a metre, colours off the
palette, part-transparent pixels, outline share, lightness range, screen scale) and `--check` fails
on a broken rule not in the allowlist; CI runs it. `tools/art_sheets.py DIR` makes contact sheets
(the world at a distance and screen size, first-person, monsters, textures, drawn art, the
palette), and `tools/art_shots.sh DIR` staged in-game shots (`ROWS=1080`, `SHOTS="burst hands"`).
Run the audit and look at the sheets before committing art.

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
tools/gen_image.py art/textures/wall-stone.png --prompt "$(cat art/prompts/texture-common.txt art/prompts/texture-wall-stone.txt)" --ref art/imp/turnaround.png --size 1024x1024 -n 2
```

`tools/make_texture.py` crops it square, box-filters it to `--metres` × 64 px, flattens it
(`--colors`, 32 of its own, or with `--palette` the master palette, as every shipped texture
is: see "House style"), raises or moves its tone (`--contrast`, `--tone`, `--chroma`) and writes a 3 × 3 tiled preview beside the source to check
the seams. The generator's 1254 px squares have art pixels about 5 px wide, so 4 m
(256 px) keeps their detail; a small-patterned one (pillar blocks, planks) is 2 m. Asked
for seamless, they mostly tile; `--blend PX` cross-fades the edges when they don't, but
ghosts joints, so a fresh image is often better.

```bash
tools/make_texture.py art/textures/wall-stone-2.png data/textures/wall-stone --metres 4 --contrast 1.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/floor-flags-2.png data/textures/floor-flags --metres 4 --contrast 1.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/ceiling-1.png data/textures/ceiling-stone --metres 4 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/pillar-stone-1.png data/textures/pillar-stone --metres 2 --contrast 1.6 --chroma 0.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/platform-top-1.png data/textures/planks --metres 2 --contrast 1.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/stair-side-2.png data/textures/stair-side --metres 2 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/stair-tread-1.png data/textures/stair-tread --metres 2 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/stone-2.png data/textures/dressed-stone --metres 2 --brightness 0.78 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/beam-2.png data/textures/timber --metres 2 --contrast 1.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/sarcophagus-side-3.png data/textures/sarcophagus-side --metres 2 --strip 0.8 --brightness 0.78 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/sarcophagus-lid-1.png data/textures/sarcophagus-lid --metres 2 --brightness 0.78 --contrast 1.6 --tone 3 8 --palette art/style/palette.txt
tools/make_texture.py art/textures/rock-1.png data/textures/rock --metres 4 --contrast 1.6 --palette art/style/palette.txt
tools/make_texture.py art/textures/cave-floor-2.png data/textures/cave-floor --metres 4 --contrast 1.6 --palette art/style/palette.txt
```

The `ice` surface (`data/textures/ice.png`, dark clear ice with white crack planes; its sides
too, stone under it) is the common prompt plus `art/prompts/texture-ice.txt` (ice only, nothing
showing through) plus a look: `texture-ice-dark.txt`, the one used, `-frosted` or `-glacier`.
`ice-1` and `ice-2` are an earlier ice-over-flagstones version, dropped.
`tools/make_texture.py art/textures/ice-dark-2.png data/textures/ice --metres 4 --palette art/style/palette.txt`.
The ice caves' walls are `ice-rock` (faceted glacier ice with dark rock locked in it,
`texture-ice-rock.txt`) and their floor `snow` (trodden snow and hoarfrost with rock showing
through, `texture-snow.txt`, snow on its sides too); both took the floor ice, `ice-dark-2.png`,
as a second reference for the palette:

```bash
tools/make_texture.py art/textures/ice-rock-3.png data/textures/ice-rock --metres 4 --palette art/style/palette.txt
tools/make_texture.py art/textures/snow-1.png data/textures/snow --metres 4 --palette art/style/palette.txt
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
tools/make_texture.py art/descent/door-1.png data/textures/descent-arch --metres 4 --panel 2.8 --on data/textures/wall-stone.png --period 5 --contrast 1.2 --palette art/style/palette.txt
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
leaves the part speakers play tiny, `start=0.42` starts a take that far in, for one whose burst
comes after a swell, late on what the game shows; take 1 without a line), and `tools/make_sfx.py [CLIP...]` trims,
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
tools/gen_music.py audio/music/combat-8.wav -f audio/prompts/music-combat-8.txt -l 120
tools/make_loop.py audio/music/combat-8.wav data/music/combat-8.ogg --min-loop 50 --loudness -11 --preview /tmp/join.wav
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

Two later tries were turned down (`music-explore-waltz.txt`, `music-combat-macabre.txt`, takes
in `audio/music/explore-waltz-*.wav` and `combat-macabre-*.wav`): a music-box waltz on celesta,
violin and bassoon was too peaceful ("there should be some tension, we are in a dungeon"), and a
danse macabre in 6/8 on xylophone and solo violin wasn't combat music at all. Combat should be in
the trailer's vein (`music-trailer-plan.json`: driving drums, low brass stabs, a tense high string
figure, a dark theme). Their replacements, `music-explore-tense-plan.json` and
`music-combat-battle-plan.json` (`music_v2_5` plans, three and two 60 s sections of one texture),
were never sent: the account's credits ran out (2026-11-16). Each line of a plan's text must be at
most 200 characters. Composed, they became explore-5 and combat-7 (below).

**Composed music.** Music can also be written out as notes: `tools/compose_*.py` are pieces,
each a function returning its notes plus its General MIDI instruments, and `tools/midi_music.py` (the shared part) writes them as MIDI, renders that through
GStreamer's FluidSynth element and the FluidR3_GM soundfont, `/usr/share/sounds/sf2/FluidR3_GM.sf2`
(`apt install fluid-soundfont-gm`, MIT), and finishes the loop with
make_loop.py's loudness and encoding. It renders the piece twice and keeps the second pass, which
opens with the first's reverb tails, so the join needs no crossfade; the beat is chosen so the
loop is a whole number of samples and of FluidSynth's 64-sample blocks, and the two passes then
correlate at 1.0000 (the title at 0.9959: its tails differ a little from pass to pass). The tracks were
first rendered with TimGM6mb, a smaller set with the sound of a 1990s wavetable card, and moved to
FluidR3_GM on 2026-11-05 because TimGM6mb is GPL-2 and whether a rendering is bound by that is
unsettled; GeneralUser GS was tried too. A dense piece clips inside FluidSynth before the limiter can act, so a piece
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
tools/compose_explore_4.py audio/music/explore-4 data/music/explore-4.ogg --preview /tmp/join.wav
tools/compose_explore_5.py audio/music/explore-5 data/music/explore-5.ogg --preview /tmp/join.wav
tools/compose_combat_6.py audio/music/combat-6 data/music/combat-6.ogg --preview /tmp/join.wav
tools/compose_combat_7.py audio/music/combat-7 data/music/combat-7.ogg --preview /tmp/join.wav
```

`compose_combat.py` is combat-5, a battle piece after combat-3: E minor at 160 BPM, 64 bars, a
96 s loop, cellos grinding over contrabasses, drums, taiko and timpani on every beat, brass stabs,
a tremolo string figure, a horn theme, choir and orchestra hits, the Phrygian F major for menace;
its four sections come twice, scored anew the second time. At 120 BPM it lacked energy: combat-3,
asked for 110, plays at about 160 (a tempo estimate from onset autocorrelation finds half of it,
0.75 s), and once at 160, 32 bars (48 s) was too short.

The four after it were made to sound unlike every track before them, in keys none of those use:

- explore-4, `compose_explore_4.py`: a lament in 12/8 in F# minor, a dotted quarter at 0.9 s, 115 s;
  a harpsichord breaking the chords in eighths over a plucked bass falling F#, E, D, C#, the theme
  on English horn, a bassoon's answer, a solo viola over a celesta.
- explore-5, `compose_explore_5.py`: tense, B minor at 83 BPM, 92 s; contrabasses pulsing in eighths
  a half step off the root like footsteps, a heartbeat bass drum, a solo cello's theme full of half
  steps, a low flute and a muted trumpet. Each section keeps to one colour beside the pulse: with
  every layer playing from the second section on it was a din, and a pizzicato cluster struck every
  eight bars stood out as a noise.
- combat-6, `compose_combat_6.py`: a war dance in 7/8 (2 + 2 + 3) in C# Phrygian dominant, an eighth
  at 0.18 s, 81 s; a modal riff on bassoon, basses and pizzicato on every eighth, tuba and trombones
  on the accents, hand drums, the theme on oboe and shanai, a choir chanting. `run`'s `beats` is the
  beats a bar (7 eighths here; the beat is whatever note the piece counts in).
- combat-7, `compose_combat_7.py`: G minor at 150 BPM, 102 s, in the trailer's vein; a violin figure
  in sixteenths circling each chord's fifth by half steps, cellos and basses hammering eighths, bass
  drum, taiko and timpani on every beat, bare fifths stabbed by trombones and tuba, a creeping low
  horn theme, a chanting choir. Only G minor, C minor, A flat and D: its first version, the theme on
  trumpets climbing over full brass chords in B flat, E flat and F, was too triumphant.

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
and the shield and sword (`art/sword-shield/ref-shield-a2.png`, `ref-sword-idle.png`).
The title is the maw: the hall's far end is a mouth hewn in the rock, fangs above and
below, its black throat the calm centre the menu sits in (`art/splash/maw-1.png`; the
`title-*.png` before it had a ritual dagger in an altar):

```bash
P=art/prompts; tools/gen_image.py art/splash/maw.png --prompt "$(cat $P/splash-common.txt $P/splash-title.txt)" --ref art/imp/turnaround.png --ref art/acolyte/turnaround-2.png --ref art/knight/runic-turnaround-3.png --ref art/harpy/turnaround-2.png --size 1536x1024 -n 2
```

`tools/make_splash.py` crops it to 16:9 (`--shift` -1 keeps the top, 1 the bottom) and
box-filters it to 640 × 360, 2 screen pixels per splash pixel at 1280 × 720. It keeps every
colour by default: a 64-colour palette turned the knight's blue runes yellow.

```bash
tools/make_splash.py art/splash/maw-1.png data/splash/title --shift -0.3
tools/make_splash.py art/splash/loading-1.png data/splash/loading
tools/make_splash.py art/splash/death-1.png data/splash/death
tools/make_splash.py art/splash/victory-2.png data/splash/victory --shift 0.3
```

The menu pass caches the picture by path and outlives scenes, so a re-made one shows after a
restart of `./run.sh`.

## Monster sprites

A monster starts as a 5-view turnaround sheet (front, front-quarter, side,
back-quarter, back; magenta background, cyan separators). `tools/slice_turnaround.py`
keys and slices it into `data/sprites/<monster>/turnaround.png` plus a `.lisp` index:

```bash
python3 tools/slice_turnaround.py art/imp/turnaround.png data/sprites/imp/turnaround --height 96 --mirror back-quarter
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
python3 tools/slice_frames.py art/spells/bolt.webp data/sprites/bolt --pixel 5 flight:5 burst:7
```

The casting hands are made the spear's way (below): one generated picture per pose, the whole
1536 × 1024 screen, both gauntlets with their backs to the camera and the fire behind the fingers
(`art/prompts/hands-common.txt`, which says so for every pose, plus `hands-<pose>.txt`; the sword's
idle frame and the spear's rest pose as references, the other poses adding `hands-follow.txt` and
the chosen rest pose, `art/hands/idle-2.png`; the rest pose took the old bare-handed sheet,
`art/hands/fire-hands.png`, as a third reference for how the hands are held). The common file
also says the thumbs are on the inner edges, toward each other, as they must be with the backs to
the camera: asked only for the backs, the generator drew a pose's hands swapped now and then,
thumbs on the outside (the release and the hands flung open were drawn again for it, their
`-thumbs` takes). A pose that turns the palms up to the camera, as healing's rise does, has them
on the outside. The idle flicker
is the rest pose's hands over two other takes' fire (`tools/swap_fire.py`, each frame the other
take's fire alone), since a take asked for only other flames moved the hands too. The motifs
(Absorb, healing, ward; `*hand-motifs*`) have no fire: `hands-common-magic.txt` in place of the common
file (no fire, the magic as the pose says) and `hands-follow-magic.txt`, plus `hands-absorb-idle`,
`-absorb-void`, `-heal-idle`, `-heal-rise`, `-heal-wrap`, `-heal-fade`, `-ward-idle`, `-ward-push`,
`-ward-pane` and `-ward-fade` (`art/hands/gen-motifs.sh` makes them all). Each idle's frames are made
from one picture by `tools/animate_idle.py` (its docstring has the command lines), changing only the
magic's pixels so the hands stay still: the void's specks orbit and its ring pulses, the specks that
would sit still taken out (`spin`), and both voids' rims are redrawn over the spun and turned frames
(`rim`: a navy outer ring, a deep blue one and an ice inner edge lit from the upper left with a glint,
pale dashes round it turning half their spacing a frame, and on the held void the streaks shaded navy
to ice as they reach it); those spun and turned frames are made afresh by the commands in the frames
file, not kept; only a band of light running up the healing ribbons is drawn, over
the ward's rest pose's gauntlets with its hexagon taken out (`flow --hands`: the generator drew no steel
under the ribbons, and the rest poses' gauntlets lie within a few pixels of each other); the ward's hexagon and rune give way to three
hexagons drawn in code, one above two, each frame one of them bold (`hexes`). The Absorb void's loop is one
picture turned a quarter at a time by `tools/turn_spiral.py --all`, the void drawn clear of the hands:
asked for it turned, the generator moved the hands too. Their lines in the frames file end in
`magic`, so `make_shield.py` keys only magenta (the void's blue would go with the old keying) and,
with `--glow`, keeps every bright colour light, not only fire's, and keeps its own colours instead of
sharing the strip's `--colors` (squeezed in with the fire, the void's few blues went grey and yellow).
What `animate_idle.py` draws in art pixels it lays on exactly the boxes `make_shield.py` averages, the
picture mirrored for `--corner right` (`ArtGrid`): drawn on a plain 5-pixel grid, a one-pixel ring
straddled two boxes and blended into mud.
`art/hands/hands-frames.txt` places them, 3 idle frames and the 8 of the cast, then each motif's (4
idle (the ward's 3), Absorb's 4 of its stance, healing's and ward's 6 of their cast), at 0.2 art pixels a source pixel (the spear's 0.254 drew them so big
they hid the middle of the view), and `--glow` keeps the fire out of the darkening
(darkened, white fire went grey and the palette made it pale blue):

```bash
tools/gen_image.py art/hands/gather.png --prompt "$(cat art/prompts/hands-{common,gather,follow}.txt)" --ref art/sword-shield/ref-sword-idle.png --ref art/spear/idle-2.png --ref art/hands/idle-2.png --size 1536x1024 -n 2
tools/swap_fire.py art/hands/idle-2.png art/hands/flicker-1.png art/hands/flicker-1-fire.png
tools/swap_fire.py art/hands/idle-2.png art/hands/flicker-2.png art/hands/flicker-2-fire.png
tools/turn_spiral.py art/hands/absorb-void-1.png art/hands/absorb-void-turn --centre 767,593 --radius 182 --all
tools/make_shield.py --corner right --glow art/hands/hands-frames.txt data/sprites/hands/hands
tools/restyle.py --house data/sprites/hands/hands.png
```

The sword is one 12-frame strip (4 idle, then an 8-frame slash), each cell about 326 × 250
art pixels (the height `*sword-height*` expects), drawn with square pixels
(`*sword-stretch*` 1.0, unlike the hands). It starts as a 3D
model posed in Blender: `art/sword/sword.blend`, rigged and rendered by `tools/blender_sword.py`
(its docstring covers build, update, reframe and render; `tools/blender` runs the flatpak on
the NVIDIA GPU). Close the Blender window, or File → Revert, after a script changes the
.blend, or the window's next save undoes it. The render at art scale is a 4 × 3 sheet,
which an image generator restyles; `art/sword/restyle.png` is that
restyle. Save the generator's download into the project: an image pasted into chat arrives
shrunk and recompressed.

```bash
tools/blender -b --python tools/blender_sword.py -- render art/sword/sword.blend art/sword-pixel --height 250
python3 tools/slice_frames.py art/sword/restyle.png data/sprites/sword --pixel 1.25 --margin 2 --filter box --colors 48 sword:12
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
`spear-<pose>.txt` (idle, drawback, thrust, extend, recover; jolt, sweep, sweep-windup-long,
sweep-follow-long for the counter and the sweep; the jolt, the set pose driven back, adds
`art/spear/set-2.png`, from `spear-set.txt`, as a third reference, and the sweep's wind-up and
follow-through add `spear-sweep-length.txt` and `art/spear/sweep-2.png`, so the spear stays its
length: asked without it, they drew it half as long), with the sword's idle frame
(`art/sword-shield/ref-sword-idle.png`) as the reference, the other poses adding
`spear-follow.txt` and the chosen idle picture as the second. `tools/make_shield.py
--corner right` places them against the bottom-right corner, as the sword sits, from
`art/spear/spear-frames.txt` (4 idle entries, the 8 of the thrust, the jolt and the sweep's 4). The strip is placed by its aim, so its side edges show on screen: nothing may reach a
picture's left or right edge (the sweep's wind-up, whose spearhead did, is moved left):

```bash
tools/gen_image.py art/spear/extend.png --prompt "$(cat art/prompts/spear-{common,extend,follow}.txt)" --ref art/sword-shield/ref-sword-idle.png --ref art/spear/idle-2.png --size 1536x1024 -n 2
tools/make_shield.py --corner right --side-margin 80 art/spear/spear-frames.txt data/sprites/spear/spear
```

A pose whose shaft came out short is lengthened by `tools/extend_shaft.py`, which lays a plain
stretch of the shaft again along its line past the end and puts the end's cap back on: the sweep's
wind-up and follow-through (its docstring has the command; the frames file says how far each went).
The follow-through is moved right so its butt end stays near the view's middle, which puts its
spearhead past the strip's corner: `--side-margin 80` keeps 80 art pixels past the corner
instead of the bottom's 6, the index says so (`:overhang`), and `layout-sword` sits the strip that
far past, so the screen's edge cuts the spearhead, never the strip's.

The maul (`art/maul/`) is a 3D model built by script, its renders redrawn as pixel art: image
generators couldn't draw its head the right way round (it lies in the plane of the blow, so on
screen it stands up and down, broad side to the player, and strikes end first; asked for that,
they drew it broadside, end-on, or carried on along the haft like a mace; the tries are in the art
attic). `tools/render_maul.py` is the model (an ash haft, grip and bands, a 38 cm forged-steel
head, the sword's gauntlet in both hands, the left mirrored) and its eight poses in camera space
(`POSES`: idle, raise, charged, strike, impact, recover, shake-lift, shake-swing, shake-slam), each the head's
place and the haft's way, the head's axis `cross(+X, haft)`, and each hand's grip and elbow, the
way the back of the hand faces (`right_back`, `left_back`: outward, the right hand's to the right
and the left's to the left, the fingers round the inside of the haft and under it), a roll of hand
and forearm together about the haft (`right_roll`), and `right_open` for an open hand, the haft
resting on the palm and the fingers closed only to `OPEN_CURL`, about its middle as the player sees
it (the rest pose's far hand: a fist there wrapped the whole haft, and turning only the hand bent
the wrist into a hook). The wrist never bends: hand and forearm are one line. A forearm running back
toward its elbow turns its hand however that runs, and where the haft points away from low hands
that put the hand under the haft, palm up; a hand whose back then faces more than 60° from its
BACK (`BACK_TURN`) is turned to it, its forearm running back nearly along the haft instead. The
left hand grips higher there (`CLOSE_GRIP`), or only its cuff showed at the screen's edge. The
gauntlets are render_sword's with a thumb of their own (`thumb_parts`) hugging the thicker grip, as far
as `THUMB_REACH` round it, about the haft's middle as the player sees it (further, it crossed it).
It previews them in seconds with render_sword's rasterizer. A head stands upright only with the haft
running nearly level, forward from low hands (perspective makes it rise on screen); tipped up, the
head tips back with it. A head driven into the floor at the player's feet is below the screen, so
the slam shows the hands and haft only, and the dust shows the impact. Coming down in front, the
haft points at the camera and shows only its end cap, so the frame between the lift and the slam
(shake-swing) swings the head down and out to the right, the haft's length showing. `tools/blender_maul.py`
builds `art/maul/maul.blend` from it (a `Maul` empty and a grip per hand, keyed per pose and constant
between, each hand with both fists and which shows keyed too: pose them by hand there) and renders it toon-shaded with blender_sword's materials into
`art/maul/renders/frame_01.png` .. `09`, the whole 1536 × 1024 screen each. The image generator
then redraws each in the spear's and sword's style (`art/prompts/maul-restyle.txt`, the render as
the first reference, the spear's idle and the sword's as the style), into `art/maul/restyle/<pose>-N.png`:
traced over a render, it keeps the composition to a pixel or two. Handed a whole restyled frame as a
fourth reference it copied that frame's pose instead, so the gauntlets' look comes from a close-up cut
from the recover frame (`restyle/recover-detail.png`, with `maul-restyle-detail.txt`), which it can't
copy as a pose, and on the slam it drew the butt end's cap as a
second head until told the head is out of sight (`maul-restyle-butt.txt`). `art/maul/maul-frames.txt`
places the chosen takes as the spear's pictures are, at its scale, 14 art pixels low so what runs off a
picture's top is cut above the screen's (the idle 50, so at rest the hands and head hide less of the view); `*maul-aim*` is measured from the impact frame's head.

```bash
tools/render_maul.py /tmp/maul-preview --pixel 4
tools/blender -b --python tools/blender_maul.py -- build art/maul/maul.blend --force
tools/blender -b --python tools/blender_maul.py -- render art/maul/maul.blend art/maul/renders
tools/gen_image.py art/maul/restyle/strike.png --prompt-file art/prompts/maul-restyle.txt --ref art/maul/renders/frame_04.png --ref art/spear/idle-2.png --ref art/sword-shield/ref-sword-idle.png --size 1536x1024 -n 2
tools/make_shield.py --corner right art/maul/maul-frames.txt data/sprites/maul/maul
```

Generators can't keep a motion sequence across a grid of first-person poses, and they draw
a depth move (pulling a weapon back toward the viewer) badly. Ask for one pose per image,
attach the first as the design reference, and describe each pose in screen positions.

A re-sliced PNG isn't picked up by `tools/hd reset` (loaded assets stay);
`tools/hd reload src/<file that defines it>.lisp` reloads it and rebuilds the scene.

A monster's walk is one strip of 4 frames per view, in the turnaround's view order. It
comes as one generated sheet per view (`art/imp/walk-<view>.png`), each
drawing the imp at its own size. `tools/slice_views.py` scales every sheet to one sprite
height, mirrors the views that face right frame by frame (here the back-quarter), stacks
them and slices the stack; `--pixel` = height / 96 makes the imp as tall as a turnaround
cell. It is `tools/stack_views.py` and `tools/slice_frames.py` in one step: the stacked sheet
(10 MB or so) stays in memory, since it rebuilds exactly from the per-view sheets, and
`.gitignore` keeps any written one (`*-sheet.png`) out of git. To look at it, run
`stack_views.py` with the same stacking options:

```bash
python3 tools/slice_views.py data/sprites/imp walk:20 art/imp/walk-{front,front-quarter,side,back-quarter,back}.png --height 768 --mirror 4 --pixel 8 --anchor bottom --filter box
```

The creature's `walk-animation` names it. The billboard picks the view as for standing,
and the frame follows the distance walked (`stride` metres per frame), so the feet keep
pace with `walk-speed`.

The attack (a claw swipe: wind-up, lunge, strike, recover) is built the same way from
`art/imp/attack-<view>.png`. The front two were made by hand; the other three, which keep
their takes' names (`attack-side-1`, `attack-back-quarter-1`, `attack-back-b-2`), came from `tools/gen_image.py` with `art/prompts/imp-attack-common.txt`
plus the view's file, referencing the turnaround, that view's walk sheet and the two
finished attack sheets. `slice_views.py` scales by the tallest frame, here the raised
claw, which stands about 1.15 times the imp's height, so the stack is taller than the
walk's to keep the standing imp at 96 px (cells come out 110 px tall):

```bash
python3 tools/slice_views.py data/sprites/imp attack:20 art/imp/attack-front.png art/imp/attack-front-quarter.png art/imp/attack-side-1.png art/imp/attack-back-quarter-1.png art/imp/attack-back-b-2.png --height 880 --mirror 4 --pixel 8 --anchor bottom --filter box
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
`ogre-leap-back-quarter-feet.txt` added to the prompt (the other try is in the art attic,
see "Where art lives").

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

The rime hag (a stooped crone in shaggy grey fur stiff with hoarfrost, a mantle of icicles, blue-white
skin, a staff of black ice with a frozen lantern in her left hand) is `art/hag/turnaround-1.png`
(`art/prompts/hag-turnaround.txt`, the imp's, acolyte's, necromancer's and wraith's sheets and
`art/style/anchor.png` as style references), sliced at `--height 109` for her 1.7 m, staff included.
No view needed mirroring. Her walk (a hobble on the staff), cast (the staff swung forward, a shard at
its lantern: the shard and the rime field), nova (the gather, hunched with rime crawling up her: what
the tell holds, deeper, the burst, recover) and flinch are made with `EXTRA_REFS=art/style/anchor.png
tools/gen_monster_views.sh hag <anim> ...` (`EXTRA_REFS` attaches images after the others), from her
standing cells (`tools/cut_stands.py art/hag/turnaround-1.png art/hag`); the death (`hag-death.txt`,
front only) cracks the icicle mantle and sinks her into a heap of frosted fur, the staff across the
floor: the corpse. Every strip takes `--cold`, which keeps her icicles and skin blue: the usual
keying's despill turned them grey. A few back-quarter frames have the staff in the other hand.

```bash
python3 tools/slice_turnaround.py art/hag/turnaround-1.png data/sprites/hag/turnaround --height 109 --filter box
V="front front-quarter side back-quarter back"
for a in walk:20 cast:20 nova:20 hurt:10; do python3 tools/slice_views.py data/sprites/hag $a $(for v in $V; do echo art/hag/${a%:*}-$v.png; done) --height 872 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box --cold; done
python3 tools/slice_frames.py art/hag/death.png data/sprites/hag --pixel 4.32 --anchor bottom --filter box --cold death:8
for s in turnaround walk cast nova hurt death; do tools/restyle.py --house data/sprites/hag/$s.png; done
```

The arc votary (a gaunt storm-priest in a ragged robe of deep storm teal over black, copper wire
stitched down it in zig-zags, a riveted brass collar plate with a lightning sigil, eyes sewn shut and
blazing yellow-white, a crown of five iron lightning rods with arcs between their tips, a knot of
lightning between its clawed hands) is `art/votary/turnaround-teal-1.png`
(`art/prompts/votary-turnaround-teal.txt`: `art/style/anchor.png` and the acolyte's, riftwalker's,
necromancer's and imp's sheets as references, the acolyte's rendering asked for most closely), sliced
at `--height 128` for its 2 m, crown included; no view needed mirroring. Its first design, a beige
linen habit (`../hexmaw-art-attic/art/votary/linen/`), was the dungeon walls' own colour with no hard
outline, and read as a pilgrim: the prompts now say no brown cloth, a near-black outline round the
whole figure as the acolyte has, one saturated colour no other monster uses, and light only from the
lightning. Its walk (slow and measured), cast (four frames: the hands wide with an arc between them;
brought together on a blazing knot, the charge's held frame; thrust forward, the hold's frame, only a
stub of the beam drawn, since the game draws the beam; recover) and flinch are made with
`tools/gen_monster_views.sh votary <anim> ...` after `tools/cut_stands.py
art/votary/turnaround-teal-1.png art/votary`, and its front-only death (`votary-death.txt`) burns along
the wire, knocks off the crown and lays it face down beside it. Yellow lightning on magenta comes out
of the slicers salmon and the palette snaps that to pink, so every strip goes through
`tools/yellow_sparks.py` (bright, red-led pixels with too much blue for yellow made yellow; white
cores kept) before `restyle.py`:

```bash
python3 tools/slice_turnaround.py art/votary/turnaround-teal-1.png data/sprites/votary/turnaround --height 128 --filter box
V="front front-quarter side back-quarter back"
for a in walk:20 cast:20 hurt:10; do python3 tools/slice_views.py data/sprites/votary $a $(for v in $V; do echo art/votary/${a%:*}-$v.png; done) --height 1024 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box --violet; done
python3 tools/slice_frames.py art/votary/death.png data/sprites/votary --pixel 4.1 --anchor bottom --filter box --violet death:8
for s in turnaround walk cast hurt death; do tools/yellow_sparks.py data/sprites/votary/$s.png; tools/restyle.py --house data/sprites/votary/$s.png; done
```

The bloodroot (a heart-bulb of knotted root and wet flesh, split by a thorn-ringed maw, ember-red
veins, roots splaying into the floor) is one view: near-symmetric, so its atlas has `:views
(:front)` (`bloodroot-atlas`) and it looks the same from every side. Its design is
`art/bloodroot/design-2.png` (`art/prompts/bloodroot-design.txt`, the anchor, the imp's and the
necromancer's turnarounds as references), and every sheet is drawn from it
(`art/bloodroot/gen-strips.sh`: `bloodroot-<sheet>.txt` plus `bloodroot-common.txt` and
`style-common.txt`, the design and the anchor as references). The idle sheet opens with a copy of
the bulb at rest, which is its turnaround frame; the attacks sheet opens with one too, sliced as a
throwaway `scale` animation. `--pixel` is that frame's height in the sheet over 90 (1.4 m at 64 px a
metre). The tufts standing on its roots (`art/prompts/bloodroot-tendrils.txt`, the snare sheet as a
third reference) are sliced at `--pixel 13`, the tallest about half a metre. The snare's roots take their own scale:

```bash
D=data/sprites/bloodroot
python3 tools/slice_frames.py art/bloodroot/idle-1.png $D --pixel 4.87 --anchor bottom --filter box turnaround:1 idle:4 hurt:2
python3 tools/slice_frames.py art/bloodroot/attacks-2.png $D --pixel 3.6 --anchor bottom --filter box scale:1 spit:4 bloom:4 && rm $D/scale.*
python3 tools/slice_frames.py art/bloodroot/death-1.png $D --pixel 5.07 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/bloodroot/snare-1.png $D --pixel 5.1 --anchor bottom --filter box snare:6
python3 tools/slice_frames.py art/bloodroot/snare-grip-2.png $D --pixel 5.9 --anchor bottom --filter box snare-grip:4
python3 tools/slice_frames.py art/bloodroot/tendrils-1.png $D --pixel 13 --anchor bottom --filter box tendrils:8
tools/restyle.py --house $D/{turnaround,idle,hurt,spit,bloom,death,snare,snare-grip,tendrils}.png
```

Its roots are a texture with see-through gaps, `data/textures/bloodroot.png` (`art/prompts/texture-bloodroot.txt`:
roots on magenta), which `make_texture.py --key` keys to alpha, the magenta under a root's edge filled
with a dark tone of it:

```bash
tools/make_texture.py art/textures/bloodroot-1.png data/textures/bloodroot --metres 2 --palette art/style/palette.txt --key
```

The status auras (magic.lisp) are 8-frame loops in `data/sprites/status/`, each a generated 2 × 4
sheet on magenta of small separate pieces over a body-sized area, the middle left open. Shock came
first (`art/prompts/status-shock.txt`, the bolt sheet and the torch's flame sheet as references);
it set the look, so fire (`status-burn.txt`, wisps of flame) and frost (`status-snow.txt`,
snowflakes) take its sheet as their first reference, with the bolt sheet for fire's colours and the
first frost try (`art/status/frost-1.png`, `-2`, rime round the body's outline, dropped) for
frost's. Ice and lightning are keyed with `--cold` to keep their blues:

```bash
tools/gen_image.py art/status/burn.png --prompt-file art/prompts/status-burn.txt --ref art/status/shock-2.png --ref art/spells/bolt.webp --size 1536x1024 -n 2
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
python3 tools/slice_frames.py art/imp/death.webp data/sprites/imp --pixel 3.64 --anchor bottom --ground-like 8:7 death:8
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
tools/gen_image.py art/pickups/sheet.png --prompt-file art/prompts/pickups.txt --ref art/imp/turnaround.png --size 1536x1024 -n 2
python3 tools/slice_frames.py art/pickups/sheet-2.png data/sprites/pickups --pixel 6.5 --filter box --colors 32 --anchor bottom --cold vial:4 flask:4 shard:4 crystal:4 && rm data/sprites/pickups/{vial,crystal}.*
tools/recolor_hue.py data/sprites/pickups/flask data/sprites/pickups/mana-potion --hue 222 --below 13 --reach 60
tools/gen_image.py art/pickups/herbs.png --prompt-file art/prompts/healing-herbs.txt --ref art/imp/turnaround.png --ref art/pickups/sheet-2.png --size 1536x1024 -n 3
python3 tools/slice_frames.py art/pickups/herbs-3.png data/sprites/pickups --pixel 12 --filter box --colors 32 --anchor bottom herbs:4
tools/draw_item_icons.py data/sprites/icons/items
tools/gen_image.py art/pickups/dust.png --prompt-file art/prompts/pickup-dust.txt --ref art/imp/turnaround.png --ref art/pickups/sheet-2.png --size 1536x1024 -n 2
python3 tools/slice_frames.py art/pickups/dust-2.png data/sprites/pickups --pixel 14 --filter box --anchor bottom --violet dust:4
```

The arena's gate is one generated picture, an ornate iron portcullis flat-on with magenta in its
gaps (`art/prompts/gate-portcullis.txt`, the imp's turnaround and the stone wall as references),
filling the square edge to edge so the sprite is the doorway's width; `--pixel 6.3` gives the
monsters' 64 px per metre at its 3.1 m. Leave off `--colors`: a 32-colour palette greyed the
skull plate's ember eyes.

```bash
tools/gen_image.py art/gate/portcullis.png --prompt-file art/prompts/gate-portcullis.txt --ref art/imp/turnaround.png --ref art/textures/wall-stone-2.png --size 1024x1024 -n 3
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
  fourth value is its middle's width, a stream's its whole width: `flooded-kind-p`, and its
  fifth what fills the middle, `:lava`, `:water` or `:ice`: `kind-liquid`, `middle-cell-p`),
  `connector_underwater_north` an `underwater` (3 × 3 m, full of water: a flooded passage's
  and a cistern's), `connector_canal_north` a `canal` (a river's with deep water: 7 × 3.5 m,
  its middle 3 m open down to the water filling the storey below, which runs on through the
  wall under it, so its plug reaches down there too; any `:water` kind is so, `under-channel-p`),
  `connector_creek_north` a `creek` (the canal's doorway in the caves, a network of its own),
  `connector_rill_north` a `rill` (3 × 3.5 m, open wall to wall over the water, no banks: the
  creek's narrow kind, swum), `connector_frozen_north` a `frozen` (a river's with a channel of
  ice sunk 0.4 m, `pit 0.4, floor ice`, in place of its lava: the ice caves' river) and
  `connector_slide_north` a `slide` (3 × 3.5 m, that ice wall to wall: the frozen river's narrow
  kind), and each kind joins only itself. A doorway two cells
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
`--check` only checks, `--stale` builds only those newer than their `.glb`), and the game builds a block whose blueprint is newer when it
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
border only under a water doorway's open channel), `shallow [DEPTH]` (a ford: a pit DEPTH
deep, 0.45 by default, `*shallow-depth*`, holding shallows to `*water-surface*` under the floor,
so 0.15 m of water level with deep water's in the storey below; a liquid of kind `:shallows`,
waded by everything, the player at `:speed` 0.75, and no nav hazard or water cell, so walkers
cross there), `falls Y0 Y1` (a waterfall pouring through these cells from Y1 down to Y0 above
the storey's floor: the sheet hangs across the region's longer side, src/waterfall.lisp), `torch Y`
and `spawn MONSTER FACING [SKIP] [when:COND|COND]`, where `when:` limits it to those settlement
conditions (see "The settlement") and SKIP is a percent chance of no monster (every room
has its guaranteed spawns and two `m spawn ... 30`, or `m` and `M` where it has two kinds of
spawn; a generated level rolls them, the test level leaves them out, and the gallery and
`check-kit` place them all), and MONSTER may be a choice, `imp|knight` (on a generated level only
those of it in the level's pool, and a block with a named spawn the pool has none of is left out,
`block-fits-pool-p`: so the high quarter's `spawn ogre` rooms wait for a level with the ogre; a
choice marked `!`, `acolyte|!rime-hag`, is the block's own, placed whatever the pool and never
barring the block, `native-kind-p`: the ice caves' rime hags), or `any`
(one of `*spawn-pool*` by weight: imp 3, acolyte, knight, harpy, necromancer, ogre, gale wraith,
riftwalker, rime hag and arc votary 1 each, though each level of a run has its own pool, its `:pool`), or `any-ogre` (the pool without those after the dash, `|` between them: a block too
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
end `canal-end` (the banks joined round the channel's head); the creek, a cave river of water
(below), all mirrored but the sump: `creek` (undercut under its west bank, a reward in the
hollow), `creek-bend`, `creek-ford` (shallows over a rock sill, where walkers cross),
`creek-cavern` (a room, a rock arch 0.6 m over the banks that a swimmer passes under),
`creek-narrows` (to a rill), `creek-falls` (three storeys: the river falls a storey over a lip
you can walk across, into a plunge pool, a rock stair down the west bank, a ford below), the
narrow `rill` and `rill-sump` (dives 3 m under the rock), and the ends `creek-spring`,
`rill-spring`, `creek-sink` (the river runs on under the walk joining its banks to a dead end
with a reward) and `creek-sink-sump` (the same to an underwater doorway: a flooded run goes on);
the frozen river (below), the ice caves' own: `frozen-river`, `frozen-ford` (a causeway of snow
across, doorways onto both banks), `frozen-bend`, `frozen-cavern` (a room it runs through, a
snow bridge), `frozen-narrows` (wide to a slide), `frozen-slide` and `frozen-slide-bend` (ice wall
to wall, no bank), and the ends `frozen-spring` (out from under a frozen fall of icicles),
`frozen-sink` (a frozen pool) and `frozen-slide-spring`, all but the sink with a mirror;
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
with a diamond column), `ice-lake` (nearly all rink, icicles over it), `ice-sheet` (2 × 3 cells, narrow, its ice flush with the rock, no shore, snow only at the doorways: a blow sends a monster skating into the walls), `ice-cavern` (4 × 3:
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
`hang_diamond`, `frost_line`). The frozen river is the lava river made of ice: a channel of slick
ice sunk 0.4 m (a step, twice a pond's) between 2 m banks of snow, under icicles, with ice-rock
walls and 45° shores (`[ ]`, `diagonal / floor -0.4 0, pit 0.4, floor ice`); its doorways are
`FFFFffffffFFFF` and `FFfffFF` (`F door frozen`, `f door frozen, pit 0.4, floor ice`) and a slide's
`||||||` and `|||`, and its banks open onto the ice caves through `+` ice doorways, so it never
meets lava. It burns nothing: its risk is control. A run along the channel reaches about 12 m/s
and stops only on snow, a bend carries a sliding player into the outer bank's rock (a player on
ice isn't hurt by a wall, but it stops them), and a monster struck on it skates into the rock
and is hurt (see "Impacts"). `ice-hall` is an ordinary dungeon room with an ice
floor, outside all this. Ice never meets lava: `ice-bridge` (the forge frozen, ice up to its
lava channel) has no tags, so the generator leaves it out, until water can fill its channel.
Every piece must let the player walk between all its doorways (drops don't
count), or the generator builds places that are a one-way trip. `(check-kit)` checks it (or,
with no game, `tools/levelcheck --kit`: see "Level sweeps"), for every block or a list of names: it builds each alone (`*level*` `:block`, `*check-block*`)
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
stay hand-written in the blueprint, and the tool rewrites the rows after `plan 0`. A spec may
return a plan per storey (`{0: g0, 1: g1}`), and the tool writes each `plan K` in turn: the
creek's do, the water in the lower storey and the banks above. `channel` draws a channel's
outline in both, open above and water below, each 45° pair below rock standing in the water
(`<`, `>`, `diagonal / cave-floor, water`) up to the bank's floor, so the plan-1 cell over it is
plain open and no two faces share a plane; `carve` cuts water into the lower storey alone
(undercuts under a bank, where it reaches the slab and shows no surface); `water_rock` turns a
plan-1 rock pair beside the channel into rock over the water (`(`, `)`: `diagonal / rock 0 top,
open`), with `<` or `>` under it; `creek_door` draws a creek's or rill's doorway in both. A pair
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
for its length and how many a level may have). There are six: rivers and creeks, below; high
quarters, galleries and high rooms joined through `high` doorways (`high`, ends `high-end`:
the vault), `*high-length*` (3 to 6) blocks long, `*max-high-networks*` (1) a level; flooded
runs, passages joined through `underwater` doorways (`flooded`, ends `cistern`), a cistern at
each end, `*flooded-length*` (2 to 4 blocks, the first cistern included: short, swum on one
breath), `*max-flooded-networks*` (1); and canals (`canal`, ends `canal-end`),
`*canal-length*` (3 to 6), `*max-canals*` (1); and frozen rivers, the ice caves' river,
through `frozen` and `slide` doorways (`frozen-river`, ends `frozen-end`), `*frozen-length*`
(4 to 7: the ice wing is small), `*max-frozen-rivers*` (1). All grow the same way, with `network` in place
of `river` throughout. A cistern has one underwater doorway, so a run ends at it; one reached
through its ledge starts a run. A block may have doorways of two families (`block-families`:
`creek-sink-sump`'s creek doorway and its underwater one): placed, it is in a network of each,
the one it was reached by or a new one (`place`), and while a family is full (`full-p`) no
block that would start another of it is offered, from an ordinary doorway (`tagged`) or a
network's (`fitting`).
`*level-networks*` holds the last level's (`network-family`, `-pieces`, `-target`, `-ends`),
the log line says how each ended, and `(level-map)` draws a high quarter's blocks as `^`, a
flooded run's as `=`, a canal's as `-` and a frozen river's as `*`. Over 200 seeds, 60% of levels had a canal (4 blocks on
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

Creeks: a creek is the lava river's counterpart in water, grown the same way through `creek`
and `rill` doorways (pieces tagged `creek`, ends `creek-end`, all tagged `cave` too),
`*creek-length*` (4 to 8), `*max-creeks*` (1), drawn `%` by `(level-map)`. Every block is two
storeys, the water filling the lower to 0.3 m under the banks (three for `creek-falls`). No
creature swims, so a walker crosses only at a ford's shallows, an arch or round by the dungeon,
while the player swims or jumps the 3 m channel; a rill is swum. From a level's many doorways
some creek block nearly always fits, so weights decide little: at full weight a creek was on
every level, at half on 94%. So a level may have one at all only with `*creek-chance*` (0.6), the
seventh of its `*networks*` entry, rolled from the level's seed on a random state of its own
(`network-barred`); a barred family counts as full. Over run seeds 1 to 100 (300 levels), 56% of
levels have a creek, 6.4 blocks on average (243 arms ending in an end, 93 in a plug), none two;
every doorway could be reached, no ice join was wrong, and the only stranded creatures were
ogres (328, about one a level as before). Flooded runs rose from 11% of levels to 27%, started by
`creek-sink-sump` (seed 16, level 1: sink, `flooded-bend`, `flooded-passage`, `cistern`). On run
seed 17's level 4, two views from the middle of every block, vsync off: creek blocks 6.1 ms of
GPU a frame, the canal's 6.5, the level's 5.9.

Ice: the ice caves are a frozen wing of the caves. Their doorways are all of kind `ice`, so
they join only each other and the ice gates, and a gate's rock side joins only a block tagged
`cave` and not `lava` (`gate-allowed-p`: in `try`, and when two doorways meet face to face),
so the way into the ice is always a rock cave, a gate, then ice. An ice doorway that fits no corridor tries the rooms too
(few blocks have one), the first piece through a gate isn't another gate, and a gate doorway
still open at the room quota gets a room, ice or cave. `check-ice-joins` warns about any join
against the rule after every generated level. Over seeds 1 to 100, 20 levels had an ice gate,
and 29 of their 30 gates led into the ice. The frozen river grows inside the ice wing: its first
piece comes in through an ice doorway like any ice corridor or room, and its banks' doorways lead
on into the ice. Over run seeds 1 to 150, every level of each run (601), 132 levels had an ice
wing and 35 a frozen river, of 4.5 blocks on average (1 to 9), two thirds of its arms (47 of
70) ending in an end block, the rest in a plug. With the creek in the kit too, over run seeds 1
to 60 (240 levels), 46 had an ice wing and 15 a frozen river (4.1 blocks), and none warned. On seed 5's third level a frame at a spot on the river costs what one elsewhere does
(32 to 82 fps there, 32 to 127 at the level's other doorways, vsync off, world frozen). The generator asks every block's tags and weight
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

### Level sweeps

`tools/levelcheck` builds levels and blocks with no window: each worker is a plain SBCL process
(`boot.lisp`, so a worktree needs its `.ql` link) with no context, GL, music or sound, no eval
server, settings or saves, so several run at once, beside any game, and in CI. It works because
`build-level` needs no context: what it enters into its container are objects that only load
onto the GPU when a scene is staged. So `build-level-alone` (levelcheck.lisp) builds into a bare
`trial:scene`, and the levels are the game's for those seeds: over run seeds 1 to 10, every level
of each (40), the layout, every count, the creatures and pickups in order and every warning
matched a live game's. **Keep it so: nothing `build-level` calls may need the context**
(`preload`, GL calls, `+main+`'s scene, sounds belong in `setup-scene` or in ticks and render
methods). CI's sweep fails when one does. The level's state is global, so `build-level-alone`
refuses to run in a game: there a sweep still goes through `tools/hd` and `reload-scene`.

```bash
tools/levelcheck                                   # run seeds 1-10, every level of each
tools/levelcheck --runs 1-100 --depths 1,2 --jobs 6
tools/levelcheck --kit                             # check-kit, every block alone
tools/levelcheck --runs 1-30 --json > /tmp/levels.jsonl
tools/levelcheck --runs 1-3 --kit --strict         # what CI runs
```

A run seed is what `*level-seed*` fixes, so `--runs 5` is the run a game started with seed 5
plays. The report is a line per level (seed, rooms, blocks, monsters and elites, pickups, the
health, mana, gold and dust they hold, its networks, the town or boss, seconds), its warnings
under it (`--notes` adds the generator's info lines: networks, the pickup budget, hoards), then
each depth's averages and ranges (the settlement's level apart) and how often each network
appears, and the findings by class. `--json` prints the records instead, one object a line
(`level-report`: also monster and pickup kinds, `stranded` classes, `unreachable` doorways,
`ice_joins`, `attempts`, a `layout` digest that changes when any cell's block does, and
`creature_order` and `pickup_order` digests), for a script to count from. What the checks found
comes from `*last-level-checks*`, which `build-level` keeps, not from the warnings' text.
`--strict` exits 1 on a worker error, a kit problem, a doorway the player can't walk to, a
stranded creature other than an ogre (they are expected: see "The ogre"), an ice gate joined
wrong, a doorway opening onto nothing, a doorway a rooted creature's body cuts off (`rooted-blocks`,
kit.lisp: the doorways reached again with `*nav-bodies*` bound to every `rooted-p` creature's disc;
`blocked_by_rooted`), or a level kept after `*max-level-attempts*` seeds; other
warnings are reported only.

Use it for every sweep over seeds: the figures in this file (rooms, monsters and pickups per
level, how often each network appears and how its arms end, stranded creatures, the exit and
arena always reachable), pickup and loot budgets, `--kit` after changing blueprints or
`block-problems`, and a sweep of 50 to 100 runs before merging generator or kit work. A worker
takes about 10 s to load the game, then 0.3 to 2 s a level (1.1 on average over 40; the town's
level is the quickest); `--jobs` (4 by default) splits the runs between workers, about 430 MB
each. Run seeds 1 to 10 take 24 s with 4 workers, against 80 s through `reload-scene` in a live
game; `--kit` takes 5 s for 143 blocks. The driver first builds stale blueprints
(`tools/blueprint --stale`), so workers never write blocks (`*build-blocks*` is NIL in them); and
when the fasls are older than the sources it starts one worker and lets it compile before the
others, which would otherwise write the same fasls at once. From Lisp, in a process with no game:
`(sweep-levels :runs '(1 2) :depths '(1))` and `(kit-report)` return the records as hash tables.

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
  wraith, riftwalker or arc votary on level 1, and more heavy monsters on level 3; leave a kind out rather than give it 0),
  which also limits named spawns: a choice keeps the kinds in the pool, and a block naming only kinds
  outside it isn't used (`block-fits-pool-p`; on level 1 the high quarter's rooms, which spawn ogres,
  and so the whole high quarter; the log says which),
  `:skip-scale`, which scales the chance of an empty `spawn ... 30` (`*spawn-skip-scale*`: 1, 0.75,
  0.5), and `:elite-chance` (0, 0.12, 0.2; see `src/elite.lisp`);
- asked in play (`depth-scale`, 1 off a generated level): `:sight` and `:hearing` scale
  `*sight-range*` and `*hearing-range*` in `sees-target-p`, `:alert` the hunt's `alert-time`,
  `:pause` the pause after an attack, `:cooldown` the necromancer's, wraith's, riftwalker's and
  acolyte's abilities and the ogre's leap (not the boss's powers). 1, 1.15 and 1.3 the sight; pauses 1, 0.85 and 0.7.
  `:abilities` names the abilities a level's monsters may use beyond their first (`level-ability-p`):
  none on level 1, the acolyte's `:firestorm`, the pack imp's `:flank-leap` (see "The imp") and the
  rime hag's `:rime-field` on levels 2 and 3 (and so in the settlement), and her `:blizzard` and the
  arc votary's `:static-recoil` on level 3 (and in the settlement when it is at depth 3).

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
and the automap labels a revealed exit "Stairs down" (`exit-label`), over the exit's point rather than its
block's middle (`label-point`: the town's is in a recess off the plaza). `tools/hd status` gives the level
and the exit's position. To go down at once: `(game (v<- (feet *player*) (car (aref *level-exits* 0))))`;
to walk the stair, stand at the `descent` connector in `*level-doorways*` and hold W.

Over seeds 1 to 200 at each size, every exit fit on the first seed and could be reached, and the
rooms always reached their target (16.1, 19.1, 22.1 on average; 16 to 18 at the lowest size, 22 to 24
at the highest). Monsters: 15.9 (11 to 21), 19.2 (13 to 27) and 22.7 (16 to 29), so about 58 a run
(an older count: over run seeds 1 to 20, `*creatures*` held 33.0, 42.3 and 54.3 after the depth
scaling, against 31.9, 40.3 and 48.9 before it, with 10% elites on level 2 and 19% on level 3;
all before imp packs, which add a quarter or so);
pickups 13.2, 15.7, 18.3 (before imp packs and the pickups' rebalance: see `src/pickups.lisp`). A level takes 0.4 to 0.5 s to build, 0.8 s at most. Over seeds 1 to 100 on
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

Controls (the defaults, which Settings → Controls rebinds; `src/input.lisp`): click the window
to capture the mouse, Esc to pause (release the mouse, open the pause menu) and Esc again to
resume. WASD, Shift to run,
Space to jump, C or Ctrl to crouch (in water: W swims where you look, Space up, C or Ctrl
down; swim into a ledge at the surface to climb out), 1 to 9 for what the hotbar holds (at the
start 1 the sword, 2 the fire bolt, 3 heal; whatever is found goes on the next free key), the mouse wheel to change the
quickslot's potion, left click to attack (swing, thrust, or cast the spell in hand; a stamina or mana
spell held overcharges, a beam held keeps on), right button with the casting hands to cast the slot's
off-hand rune (held for Absorb Projectiles), right button
held to raise the shield (a left click while it's up bashes) or, with the spear, pressed to sweep
with the haft (the spear's thrust counters a leap or dive it meets) or, with the maul, pressed to
shake the floor (its left button held charges the blow, let go strikes), Q to drink from the
quickslot, I for the inventory (everything lives in the bag; drag a weapon or rune onto 1-9, a rune onto
a rune slot's corner for its off hand, or a potion onto Q, to bind a key; see `src/inventory.lisp`), M for the automap (see `src/map-view.lisp`), F5 to
quicksave and F9 to quickload (generated levels only), F12 for a screenshot, and E to talk to the
townsperson looked at (see "The settlement") or, at an altar, to open the spellforge (see
`src/forge.lisp`).

To test combat without the mouse (the hall's monsters below need
`(setf *debug-hall-monsters* t)` and a fresh debug level): `tools/hd '(game (player-cast *player* (quote bolt)))'`
starts a cast, and the bolt leaves from the player's view `*cast-release*` (0.2 s) later,
on the hands' release frame; `(select-weapon *player* :1)` then `(player-attack *player*)` swings the sword (the blow lands
0.23 s in; stand within 2 m of the imp, facing it), and with `:3` thrusts the spear (0.24 s in, within 3.5 m); `(setf (block-raise *player*) 1.0)` under hit-stop
shows the raised shield, and with it raised `(player-attack *player*)` bashes (`block-held`
is what the right button sets; without it the shield comes down again once the world runs); with
the spear (`:3`), the imp 5 m in front with `(setf (alert imp) 10.0 (idle-timer imp) 0.0
(leap-cooldown imp) 0.0)` crouches and pounces, and `(player-attack *player*)` 0.4 s later meets it
in the air (`charging-p` is true while it flies), and `(player-press *player* :mouse-right)` sweeps; `(hurt (aref *creatures* 0) 0)` triggers a hit reaction and a spray of blood (100 kills, and tears an imp apart; `:from point` aims the spray); to look at one death
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
at the back of the recess north of the plaza, before a painted `descent-arch`, lit by a torch on each
side wall in front of the landing: unlit, the recess read as a dark gap and was missed. The player
arrives in the plaza facing it, 11 m off. Over run seeds 21 to
32 the wing had 5 to 7 rooms and 10 to 19 monsters, and no level warned.

`make-settlement` draws its faction, condition and name from the level's seed when it is built
(`*settlement-override*`, as `'(:depth 1 :faction :deepwardens :condition :besieged)`, fixes them for
testing; reloading run.lisp clears it). The faction (`*factions*`) decides the watch's rule, which
crimes count, prices and whether its guards take bribes:

| Faction | Rule | Crimes | Cheap | Bribable |
| --- | --- | --- | --- | --- |
| `:ashen-temple` | no spell cast in town (`player-cast`) | rule, assault, murder | healing, mana | no |
| `:deepwardens` | no sword, spear or maul drawn in the `market` and `temple` zones (`check-drawn-blade`) | rule, assault, murder | training | no |
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
`quest-giver`, `guard`). Those who only stand at their posts to be talked to (the shopkeeper, priest
and quest-giver) are one front-facing picture each: a billboard whose atlas has one view
shows it from every side. Those who walk about or fight, the guard, the commoners (a `townsman` and a
`townswoman`) and the trainer, have a monster's full set (`define-townsfolk-set`, `*townsfolk-sets*`, by sprite
name): a turnaround, a walk, a flinch, a death to a corpse and, for the guard, a spear thrust, for the
trainer a two-handed chop with its wooden sword, the
guard's one set recoloured per faction (`guard-<faction>`). Guards step in armour, commoners and the trainer lightly;
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
  besieged, hold the gates through `*gate-raids*` raids, or until the siege is broken (below),
  which counts as held. Claimed back in town for gold and
  `*quest-reputation*`.

`price` is `*base-prices*`, `*price-depth-step*` dearer per depth, by the faction's multiplier and
`(1 - standing / 400)`. **Gold** is the bag's `:gold` item, in stacks of 999 (`gold` is its total,
`kind-total`; `spend` takes it with `take-item`, and a sale or a quest's reward needs `item-room`
for its coins, or is refused). It comes from `:gold` pickups, which
`place-gold` scatters on the spots health, mana, the relic and the glyphs left (`*gold-per-monster*`,
on at most `*gold-spot-share*` of them but one at least, since arcane dust comes after and its piles
grow to fill fewer spots), in piles of `*gold-pile*` coins (`pickup-count`, as dust's; bigger where its
share of spots is too few, so a level gets its whole budget: 200 to 370; `gold-coins` scales a
pile as it is placed), and from kills (`*kill-gold*` by class, straight into the bag through
`creature-died`), both `*gold-depth-step*` more per depth (`gold-scale`). A pile (gold's or dust's)
the bag can't hold all of leaves a pile of the rest, and kill gold that doesn't fit falls where the
monster died (`drop-loot`, kept in a save's `:drops` with its count). An older save's purse, a
player slot of its own, comes back through `(setf gold)` into the bag. **Reputation** (`reputation`, a plist by faction,
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

**Fighting in town**: monsters and townsfolk fight each other with the whole hunt ("Targets and
sides" under "Creature movement"): a monster notices any townsperson on sight, armed or not, and a
guard or the trainer any monster within `*town-leash*` of its post. The `settlement-director` (on
every level, for the prompt; the rest only in the settlement, at `*director-step*`) while besieged
sends 2 or 3 of the wing's nearest `*raid-classes*` at the guards every `*raid-interval*`
(`start-raid`, `sent` at the nearest guard; `run-siege`; `raids-held` counts the ones beaten off,
whoever killed the raiders). Once the wing has no raiders left (`raid-pool` empty with no raid on:
the player cleared it, or the raids used it up) the siege is broken for good (`siege-broken-p`,
"The undercroft falls quiet"): no more raids, a hold-the-gates quest is done, and one not yet drawn
isn't offered. Before, an empty pool stopped the raid timer and the quest could never finish.

A save keeps the settlement's build (faction and condition, `:settlement :built`), its state
(`saved-slots`: strikes, fine, stock, training, quest, raids, ...), the townsfolk's `provoked`,
every creature's `quarry` (and `sent`, `summoner` and grudge), and the level's entry in the run (`:level`), so a load builds the same town.
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
sprite's height is its cell's, `/ 64`); only the three who only stand are used from it now. The walkers
and the trainer were made the monsters' way (see "Monster sprites") from their lineup cells (`art/<who>/design.png`,
`<who>` being `guard`, `townsman`, `townswoman`, `trainer`): a turnaround (`art/prompts/<who>-turnaround.txt`,
the design, the imp's and acolyte's turnarounds as references), its standing cells cut by
`tools/cut_stands.py`, then `tools/gen_monster_views.sh <who> <anim> ...` for the walk, flinch and the
guard's and trainer's attack, and a front-only death. The trainer's sheets came with a cyan frame round
their edges, which `slice_turnaround.py` and `stack_views.py` now skip (its pale blends weren't keyed, so
the views were scaled by the whole sheet's height). Sliced so the standing figure is 118 px (the
townsman and the trainer), 114
(the townswoman) and 124 with the spear's tip (the guard, whose tabard is pure green until it is
recoloured per faction: every strip, into `data/sprites/guard/<faction>/`). A strip's height in
metres is its cells' over 64 (`strip-height`). The image service refused the townsman's flinch as
"self-harm" while it said he clutched his middle. The relic is `art/relic/relic.png`
(`art/prompts/relic.txt`), and the gold pile is drawn (`tools/draw_gold.py data/sprites/pickups/gold`):

```bash
python3 tools/slice_frames.py art/townsfolk/lineup-1.png data/sprites/townsfolk --pixel 3.9 --filter box --anchor bottom shopkeeper:1 priest:1 trainer:1 quest-giver:1 && rm data/sprites/townsfolk/{commoner-*,guard,trainer}.*
python3 -c "from PIL import Image; Image.open('art/townsfolk/lineup-1.png').crop((770, 3, 1150, 510)).save('art/trainer/design.png')"
tools/cut_stands.py art/guard/turnaround-2.png art/guard    # and townsman/turnaround-2, townswoman/turnaround-1, trainer/turnaround-1
python3 tools/slice_turnaround.py art/guard/turnaround-2.png data/sprites/guard/turnaround --height 124 --filter box
python3 tools/slice_turnaround.py art/townsman/turnaround-2.png data/sprites/townsman/turnaround --height 118 --filter box
python3 tools/slice_turnaround.py art/townswoman/turnaround-1.png data/sprites/townswoman/turnaround --height 114 --filter box
python3 tools/slice_turnaround.py art/trainer/turnaround-1.png data/sprites/trainer/turnaround --height 118 --filter box
V="front front-quarter side back-quarter back"
for spec in guard:992:walk:20 guard:992:attack:20 guard:992:hurt:10 townsman:944:walk:20 townsman:944:hurt:10 townswoman:912:walk:20 townswoman:912:hurt:10 trainer:944:walk:20 trainer:944:attack:20 trainer:944:hurt:10; do IFS=: read who h a n <<< "$spec"; python3 tools/slice_views.py data/sprites/$who $a:$n $(for v in $V; do echo art/$who/$a-$v.png; done) --height $h --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box; done
python3 tools/slice_frames.py art/guard/death.png data/sprites/guard --pixel 3.5 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/townsman/death.png data/sprites/townsman --pixel 3.73 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/townswoman/death.png data/sprites/townswoman --pixel 3.86 --anchor bottom --filter box death:8
python3 tools/slice_frames.py art/trainer/death.png data/sprites/trainer --pixel 3.6 --anchor bottom --filter box death:8
G=data/sprites/guard; for f in ashen-temple:30:0.25:0.55 deepwardens:212:0.7:0.55 free-company:355:0.75:0.6; do IFS=: read n h s v <<< "$f"; mkdir -p $G/$n; for strip in turnaround walk attack hurt death; do tools/recolor_hue.py $G/$strip $G/$n/$strip --from 120 --reach 30 --hue $h --saturation $s --value $v; done; done
python3 tools/slice_frames.py art/relic/relic.png data/sprites/pickups --pixel 14 --filter box --colors 32 --anchor bottom relic:4
```

Not yet: townsfolk have no voices, there are no faction banners, the town is one lighting room, and nothing is
stolen but from a dead shopkeeper.
