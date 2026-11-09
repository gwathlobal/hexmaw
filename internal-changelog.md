# Internal changelog

Every change worth recording, internal ones included: an entry in the commit that earns it,
under `## Unreleased`, given its date and version when a release is cut. The changelog
players get is `CHANGELOG.md`, drafted from this one at each release and approved before it
ships ("Releases" in CLAUDE.md). The history before this file is in `git log`.

## Unreleased

- **A frozen river in the ice caves.** A fifth network, `:frozen`: the lava river made of ice, a
  3 m channel of slick ice sunk 0.4 m between 2 m snow banks under icicles, and the rill, ice wall
  to wall. Its doorway kinds are `frozen` (7 × 3.5 m) and `rill` (3 × 3.5 m), and its banks open
  onto the ice caves through `ice` doorways, so it lives wholly in the ice wing and never meets
  lava. It burns nothing; its risk is control. The channel is the fastest road in the game, but
  it stops only on snow: bends carry a sliding player into the outer rock, and a monster struck
  on it skates into the walls. Ten blocks drawn by `tools/cave_plans.py`, nine with mirrors:
  `frozen-river`, `frozen-ford`, `frozen-bend`, `frozen-cavern`, `frozen-narrows`, `rill`,
  `rill-bend`, and the ends `frozen-spring`, `frozen-sink`, `rill-spring`. `*frozen-length*`
  (4 to 7) and `*max-frozen-rivers*` (1). `check-kit` is clean on all of them, with ogres too.
  Over run seeds 1 to 150, every level (601), 132 levels had an ice wing and 35 of them a frozen
  river, 4.5 blocks on average (1 to 9), with no unreachable doorway, bad ice join, stranded
  creature but ogres, or doorway opening onto nothing.
- **The network code is more general.** A banked doorway kind names what fills its middle (a
  5th element in `*connector-kinds*`: `:lava`, `:open`, `:ice`; `middle-cell-p`), and each
  `*networks*` entry names its `(level-map)` character (`network-char`), so a new family needs
  no new branches.
- **Walkers keep off ice when they can.** `nav-flood` charges a step onto a slippery footing
  `*nav-ice-cost*` (1.5) times its length for walkers (`*nav-hazards*` `:avoid` and `:wade`), so
  paths keep to a frozen river's banks and cross it the short way. Straight walks and flyers are
  unchanged.
- New kit blocks change what each seed grows, so an older save on a generated level starts fresh
  with the usual warning.

- **Music from a composition plan.** `tools/gen_music.py --plan FILE` sends ElevenLabs a plan of
  timed sections (`music_v2_5`'s chunks, each its text, styles and length) in place of a prompt,
  so a track can be written to a cut: `audio/prompts/music-trailer-plan.json` is the trailer's,
  six sections on its join cards and cuts at 160 BPM, and its take 2 is the trailer's score.
- **The rift's sound lands on its flash.** `rift-blink` (take 14) is a low hum swelling for half
  a second into a bright burst at 0.55 s, while the flash where something steps through a rift
  lasts 0.43 s, so the burst came after it was gone. It now starts 0.42 s in (`start=0.42` in
  `audio/sfx-picks.txt`, a new flag of `tools/make_sfx.py`, faded in over 30 ms; the picker keeps
  it), 0.4 s long with its burst 0.1 to 0.3 s in.
- **A new ice cave, `ice-sheet`.** Every other ice cave sinks its frozen pond 0.2 m inside a
  snow shore, which stops a skating monster at its ledge; this one, 2 × 3 cells and narrow, has
  its ice flush to the rock, snow only at its four doorways (north and south on opposite cells)
  and icicles over it, so a blow sends a monster sliding into the walls. Drawn by
  `tools/cave_plans.py` (`ice_sheet`), tagged `room`, weight 0.5; `check-kit` is clean, with
  ogres too. A new block changes what seeds grow: seed 12345's last level no longer has the hall
  the trailer's knight and ogre were filmed in (the trailer's takes leave it out,
  `*generator-blocks*`).
- **Knockback on ice carries and hurts.** On ice a creature's walk and a blow's knockback share
  its momentum, so a hunter kept steering through the push (`skid-path`), braking it within a
  metre or two, and counted as walking, so the wall it was thrown into never hurt it. Now it is
  `shoved-p` on ice while faster than its walk reaches there (`walk-top-speed`: walk speed times
  the footing's `:top-speed`), sliding on the ice's drag alone, and a hit faster than its walk
  could carry it is an impact (`slide`). A Force burst at the forge's cap throws an imp about
  4 m across ice against 2 before.
- **A sleeping Warded boss no longer hums across its whole level.** Its ward's loop played from
  the moment the level was built, and past `*sound-max-distance*` (50 m) a sound gets no
  quieter, so on the run's last level the hum was heard from anywhere. `update-ward` (boss.lisp)
  holds it only once the boss is awake (`dormant-p`).
- **Bosses and elites walk with strides their size.** A walk frame came every `stride` metres
  whatever size the creature was drawn, so a boss (1.6 times its kind and more) cycled its legs
  1.6 times too fast in short, skittering steps, and an elite (1.15) a little. `stride-length`
  (creature.lisp) is the stride at `size-scale`, for the walk's frame and the footsteps timed
  from it.

## November 6, 2026 v0.1.0

- **The release publishes the Windows archive.** The archives are uploaded as files of their
  own (`archive: false`), but `download-artifact` unpacks any that is a zip, so the publish job
  found `hexmaw-0.1.0-windows-x86_64` as a folder and failed before making the release; the
  itch job would have failed on it too. Both download steps now pass `skip-decompress`.
  Dispatch runs never reach the publish job, so only the first tag found it.
- **Playable on software OpenGL.** A Windows VM with no 3D driver (Mesa's llvmpipe) ran the
  game at 2 to 3 fps; reproduced here at 4 (llvmpipe, 4 cores, 1280×720). Three causes: drawing
  every pixel; Trial's loop catching up every tick a slow frame took (27 a frame, 80 of 270 ms),
  which made the next frame slower; and two passes the window's size that did little (an empty
  menu pass, 25 ms, and the blend over it). Settings has a Render scale (full to ¼, the world
  scaled up without smoothing; the HUD, hands and menus stay sharp in a pass of their own); a
  frame runs at most `*max-ticks-per-frame*` (5) ticks; the menu pass draws only while a panel is
  up, and the HUD pass, which draws the world as its background and the menus over all, is what
  reaches the screen. Now 11 fps at full scale, 28 at ½, 44 at ¼. The frame counter shows tick
  and draw time.
- **Menu buttons click wherever they are drawn.** A panel's column had a guessed height (48 a
  row, 30 a line of text, a slack of 10 that the grid's cell margins ate), and since Jersey 15 a
  line measures 35 and the title 55, so the last rows hung out of the column, where Alloy sends no
  click: the death and victory screens' only button took clicks on 7 px of its 48, the shop's and
  every townsperson's Leave on about half, Controls' Reset and Back on 21 (a Windows
  playtester's report; it happens on Linux the same, at any window size). The column now gets the
  screen's whole height and centres its rows itself, or lays them from the panel's top as far
  as they fit (`panel-backdrop`, `menu-column`), the forge's two columns in one grid row; Controls' body was also 7 px wider than
  its column. `menu-layout-problems` and `menu-click-problems` (menu.lisp) check the panel on
  screen.
- **A Windows build quits with TerminateProcess.** With Mesa's software OpenGL beside the
  exe (a VM with no 3D driver), the game could hang after its window closed, and Task
  Manager couldn't end it: an exit, even an abort one, goes through ExitProcess, which runs
  every DLL's shutdown after killing the other threads, and `libgallium_wgl.dll`'s waited
  there for one of its own. `quit-process` (dist.lisp) still runs Deploy's quit hooks and
  writes out the log and the streams, then ends the process without any DLL's shutdown
  (`terminate-process`), as do the self-test's watchdog and its start-up error exit.
- **The Windows release builds on SBCL 2.6.9.** Under 2.4.10 its image dump crashed on CI
  ("access violation in dynamic space") on some commits and not others, the same commit
  alike on every re-run, whatever it changed: one that touched only Markdown failed. The same
  commits dumped under 2.6.9. Linux stays on 2.4.10, whose binary runs on ubuntu-22.04's glibc
  (2.6.9's needs 2.38). Release.yml's `SBCL_VERSION_WINDOWS`.
- **The game's `impact` is its own.** The projectile's `impact` (spells.lisp) was Trial's
  symbol, so its DEFUN replaced Trial's physics generic; a macOS build that loaded Trial's
  rigidbody again then failed on it ("TRIAL:IMPACT already names an ordinary function").
  `hexmaw` now shadows it.
- **Builds for Linux, Windows and macOS, and a release pipeline.** The game has a version,
  `:version` in `hexmaw.asd` (0.1.0), which Trial reports with the commit as `0.1.0-<hash>`
  and the death and victory screens show under the seed. A build answers Trial's command
  line: `hexmaw version`, `hexmaw check` (files and shipped libraries, `check.txt`) and
  `hexmaw selftest` (the window, the menu, a generated level, a screenshot, a clean quit,
  `selftest.txt`); with no arguments it plays as before. Its log and F12 screenshots go to
  the user directory with the saves. `tools/setup-ql` pins the two library dists in one
  place. `tools/notices` writes `THIRD-PARTY-NOTICES.txt` from the dependency tree and
  `notices/`, and its `--check` fails on a copyleft library outside the three LGPL ones
  Alloy brings (text.editing, utilities.print-items, flexichain), or a release with no
  licence text. The build ships `README.txt` (from `README-PLAYERS.txt`), `EULA.txt`,
  `CHANGELOG.md`, the notices and `licenses/`, with the LGPL libraries' sources.
- **Settings for the playtest: fullscreen, mouse sensitivity and key bindings, kept in a
  file.** Settings gains Fullscreen (the monitor's own resolution, or the 1280×720 window),
  Mouse sensitivity (¼× to 4× the old speed, 1× in the middle) and Controls, two pages of
  actions to rebind by pressing a key or mouse button (Esc cancels; an input taken from
  another action says so; Reset to defaults). The defaults are the old keys. Every key and
  button now goes through a binding table (`src/input.lisp`), and the HUD's key names follow
  it. Those settings, the volumes and Show FPS are kept in `settings.lisp` in the user
  directory (`src/settings.lisp`), read before the window opens; they used to be lost when
  the game closed.
