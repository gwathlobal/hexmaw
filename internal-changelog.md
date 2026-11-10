# Internal changelog

Every change worth recording, internal ones included: an entry in the commit that earns it,
under `## Unreleased`, given its date and version when a release is cut. The changelog
players get is `CHANGELOG.md`, drafted from this one at each release and approved before it
ships ("Releases" in CLAUDE.md). The history before this file is in `git log`.

## Unreleased

- **The maul, a third weapon.** Two-handed, no shield (src/maul.lisp). The left button held charges
  the blow (15 stamina a blow, paid as it rises, and none without it; 0.4 s up, full at 1.35 s, 30
  stamina a second past the least, landing 0.19 s after the release and done 0.4 s later, the player slowed to 0.6
  of a walk with no run, jump or stamina coming back), and letting go strikes one creature: 18-24
  to 34-44, knockback 8 to 15 m/s with heft (the square root of `knockback-scale`, so knights and
  ogres move too, and what it throws into walls, bodies, lava, water or across ice pays there). A
  full blow always flinches (a boss rolls), knocks a shield or ward aside for 1.2 s (`reel` on
  creatures: the stagger frame held, no thinking, `shielded-p` false, so spells reach the front),
  and its kills gib from 0.1 overkill, the undead's always, so its skeletons can't be raised. A
  blow on no one living pulps a raisable corpse. The right button is the earthshake: 30 stamina,
  3-6 and a sure flinch (unless poised; bosses roll) to everything standing within 3 m all round,
  a 5 m/s shove out with heft, unblockable, nothing off the floor feels it, and it shares the
  bash's poise. Regular loot from level 2 on (`*loot-weapons*`, a third as likely as each other
  kind; level 1's first weapon stays the spear; ogre hoards too), so a seed's found weapon may be
  another kind than before. New: `attack-held` (the left button, set and cleared by
  `player-press`/`player-release`), `charge-time` and `blow-charge` on the player (saved, not
  `attack-held`, so a loaded charge comes down on resume), `push-creature :heft`, `hurt
  :gib-overkill`, the `swing-miss` generic, and the tooltip's `weapon-lines` generic in place of
  `(eq weapon :spear)` branches. Its strip is the renders of a 3D model built by script
  (`tools/render_maul.py`, `tools/blender_maul.py`, `art/maul/maul.blend`), each redrawn as pixel art
  by the image generator with the render as its first reference (`art/maul/restyle/`), since image generators
  couldn't keep its head upright in the plane of the blow (broadside, end-on and mace-like tries are
  in the art attic); `blender_sword.py` runs its `main` only when called, for its helpers. Also a hotbar icon and a loot sprite drawn, eight clips in
  `audio/sfx.md`, picked by ear (draw-maul 6, earthshake 6 at +10 dB, maul-crush 6, maul-hit 6,
  maul-swing 5, maul-charge 17, maul-full 6, maul-guard-break 6; draw-maul 5 is the spear's draw).
  The charge's cry is a one-shot, not a loop (a loop held while the charge grew sounded for good
  once stamina stopped it short of full), started once the button has been held `*maul-cry-delay*`
  (0.2 s, so a click has none) and cut off as the blow comes down: `cut-sound` (sound.lisp) pauses a
  one-shot `play-sound` returned until it is next played. Setting its volume to 0 instead left the
  voice silent at full volume after. `make_sfx.py` given clip names checks only their picks, since a worktree has only its own
  takes. The debug level's hotbar has it on key 6. The `:block`
  action reads "Block, alt attack" (the longer label ran into its key on Controls), and the Deepwardens' rule "No weapon is drawn".
- **The spear counters and sweeps.** A thrust that lands on a creature charging through the air
  (`charging-p`: an imp's pounce or ogre's leap in flight, a harpy's dive) is a counter
  (`swing-strike`'s spear method, `spear-counter`): 18 to 26, a sure flinch (a boss only a bonus),
  the jolt frame, the spear's enchantment, and a leaper dropping out of the air with no quake. The
  right button with the spear sweeps the haft through every creature in a 1.4 rad arc (the bash's
  rules, no enchantment, 15 stamina) to clear space. A first try held the right button to set the
  spear and skewered whatever came onto it every tick, walkers too: in play it stunlocked imps
  (the reset and the stamina came back faster than they did) and read as a bug against casters,
  which never walked onto it; it is gone, with its set frames and the `spear-set` sound. The
  shield's guard and bash became generics on the weapon (`guard-raise-time`, `bash-frame-times`,
  `bash-strike`), `looked-at-creature`'s test `blow-reaches-p`, and the sprite's frame
  `weapon-frame`. Four new poses (the jolt, the sweep's three, the wind-up and follow-through
  drawn again at the spear's full length, both their hafts lengthened by `tools/extend_shaft.py`,
  and the follow-through moved right, its spearhead off the screen's edge: `make_shield.py
  --side-margin` and the index's `:overhang`) and two sounds (`spear-impale`, `haft-sweep`). The
  `:block` action reads "Raise shield, sweep with spear".
- **A new footstep for the skeleton.** `step-bone` was take 3, a thin hiss of a click ringing
  0.29 s (a chasing skeleton steps every 0.23 s). It is now take 18: take 2, a quick dry
  clack-clack-clack of three bone clicks, pitched 1.5 semitones down (`step-bone-18.prompt.json`
  says how), picked by ear over fifteen takes from two newer prompts, kept in
  `step-bone-4`, `-8`, `-11` and `-14.prompt.json`.
- **Gold and dust on every level, and far fewer potions.** Gold and arcane dust are placed after the
  health and mana pickups, on the spots they leave, and over run seeds 1 to 30 half of a run's first
  levels had neither (run seed 5's first among them), the settlement's two thirds. `scatter-pickups`
  now leaves `*pile-spots*` (3) of them, and piles grow to hold the whole budget, so every one of
  the 120 levels gets all its gold and dust. Health and mana pickups were budgeted per monster (10
  and 15), which imp packs had doubled, and half of them were potions: a run handed out 66 potions,
  1,780 health and 2,670 mana to a 100-health, 50-mana player, who reached the boss with the bag
  full. They now restore `*health-per-monster-health*` (0.09) and `*mana-per-monster-health*` (0.18)
  of the monsters' total health (`monster-health`), and every 3rd is a potion: a run has 25 potions,
  810 health and 1,590 mana, the health about half of what a rough estimate of the fights takes. A
  save keeps the built pickups' kinds (`:pickup-kinds`), and one whose pickups differ, an older save
  too, starts its level fresh rather than marking the wrong ones taken, so `*save-version*` stays 4.
- **Level sweeps without a window.** `tools/levelcheck` builds generated levels and kit blocks in
  plain SBCL processes, with no window, GL, music or sound, several at once: `build-level` already
  needed no context, so `build-level-alone` (new `src/levelcheck.lisp`) builds into a bare scene,
  and the levels are a live game's (run seeds 1 to 10, 40 levels: layout, counts, creatures,
  pickups and warnings all matched). It prints a line per level and each depth's averages, or JSON
  records (`--json`), checks the kit (`--kit`, `check-kit` headless: 143 blocks in 5 s), and with
  `--strict` fails on the findings that are bugs. Runs 1 to 10 take 24 s with 4 workers against
  80 s through `reload-scene`. `build-level` keeps what its checks found in
  `*last-level-checks*`; `tools/blueprint --stale` builds only blueprints newer than their block.
  CI sweeps runs 1 to 3 and the kit on every push.
- **Holding the gates can always be finished.** A besieged town raids only with the wing's
  monsters, and once none were left `start-raid` set the raid timer to 0, which stopped the raids
  for good: a player who cleared the wing before two raids had come could never finish the
  quest. Now a wing with no raiders left breaks the siege (`siege-broken-p`, saved): no more
  raids, "The undercroft falls quiet", and the quest counts as held. A town whose siege is
  already broken doesn't offer the quest.
- **The town's way down is easier to find.** The recess north of the plaza had no light of its
  own, so its arch read as a dark gap between two walls; a torch now stands on each side wall in
  front of the landing (`tools/town_plan.py`). The automap's "Stairs down" was drawn at its
  block's middle, which in the town is the plaza where the player arrives; it now stands over the
  exit itself (`label-point`).
- **A frozen river in the ice caves.** A sixth network, `:frozen`: the lava river made of ice, a
  3 m channel of slick ice sunk 0.4 m between 2 m snow banks under icicles, and the slide, ice wall
  to wall. Its doorway kinds are `frozen` (7 × 3.5 m) and `slide` (3 × 3.5 m), and its banks open
  onto the ice caves through `ice` doorways, so it lives wholly in the ice wing and never meets
  lava. It burns nothing; its risk is control. The channel is the fastest road in the game, but
  it stops only on snow: bends carry a sliding player into the outer rock, and a monster struck
  on it skates into the walls. Ten blocks drawn by `tools/cave_plans.py`, nine with mirrors:
  `frozen-river`, `frozen-ford`, `frozen-bend`, `frozen-cavern`, `frozen-narrows`, `frozen-slide`,
  `frozen-slide-bend`, and the ends `frozen-spring`, `frozen-sink`, `frozen-slide-spring`
  (`frozen-slide*` rather than `rill`, which the creek took first). `*frozen-length*`
  (4 to 7) and `*max-frozen-rivers*` (1). `check-kit` is clean on all of them, with ogres too.
  Over run seeds 1 to 150, every level (601), 132 levels had an ice wing and 35 of them a frozen
  river, 4.5 blocks on average (1 to 9), with no unreachable doorway, bad ice join, stranded
  creature but ogres, or doorway opening onto nothing.
  Merged with the creek: over run seeds 1 to 60 (240 levels), 15 frozen rivers (4.1 blocks), no
  warnings.
- **Ice is a doorway's third liquid.** `kind-liquid` (the 5th element of `*connector-kinds*`) may
  be `:ice` beside `:lava` and `:water`: a pit floored with ice, which `middle-cell-p` checks in a
  doorway's middle and whose depth its plug reaches down to. `(level-map)` draws a frozen river's
  blocks as `*`.
- **Walkers keep off ice when they can.** `nav-flood` charges a step onto a slippery footing
  `*nav-ice-cost*` (1.5) times its length for walkers (`*nav-hazards*` `:avoid` and `:wade`), so
  paths keep to a frozen river's banks and cross it the short way. Straight walks and flyers are
  unchanged.
- New kit blocks change what each seed grows, so an older save on a generated level starts fresh
  with the usual warning.
- **Gold is an item in the bag.** The spellforge branch added a `:gold` item kind and the
  settlement, built beside it, a purse slot on the player; their merge kept the purse, so the item
  was never given. Gold is now the bag's `:gold`, in stacks of 999: pickups and kill gold go in
  with `give-item`, prices take it with `take-item`, and the purse label in the HUD's lower-right
  corner is gone (the talk panel still says how much). A pile the bag can't hold all of leaves a
  pile of the rest (dust's too, which lost it), kill gold that doesn't fit falls where the monster
  died, and a sale or quest reward with no room for its coins is refused. Piles are scaled to
  their depth as they're placed (`gold-coins`), not on taking, so a dropped pile holds what it
  says, and a save's `:drops` keep their counts. An older save's purse comes into the bag through
  `(setf gold)`, so `*save-version*` stays 4.
- **A waterfall made of the water's own texture.** Its white streaks were hashed lanes of solid
  white an eighth of a metre wide, crude beside the textured water around them, and the texture
  stretched eight times was still blocky. The sheet is now two layers of the water texture,
  only twice as long down its length and rippling across like the surface, pouring at two speeds
  and averaged, their brightest texels softly whitened, more toward the foot: the surface's grain.
- **Climbing out onto a ledge just under the water.** A swimmer climbed out only onto a ledge
  standing over the surface, so a creek ford's sill (0.15 m under it) and a waterfall's lip
  stopped them dead, and only the banks could be climbed. `ledge-ahead-p` now also takes a ledge
  up to `*climb-out-depth*` (0.3 m) under the surface.
- **No gap at the top of a waterfall.** The sheet hung in the middle of the metre-wide opening it
  pours through, so from above the dark drop showed either side of it and the lip was bare rock.
  `add-waterfall` now finds the pool it pours from (within `*spill-reach*`), stands the sheet at
  the opening's far edge, and lays a spill of water at the pool's height from the pool over the
  lip to the sheet's top.
- **The creek, a cave river of water.** A fifth network (`:creek`, doorways `creek` and `rill`,
  `*creek-length*` 4 to 8, `*max-creeks*` 1, `%` in `(level-map)`): rock caves with deep water a
  storey down between 45° banks, built like the lava river but two storeys (three for the falls).
  Twelve blocks, all drawn by `tools/cave_plans.py`, which now writes a plan per storey: `creek`,
  `creek-bend`, `creek-ford`, `creek-cavern`, `creek-narrows`, `creek-falls`, `rill`,
  `rill-sump`, and the ends `creek-spring`, `rill-spring`, `creek-sink` and `creek-sink-sump`,
  whose underwater doorway starts a flooded run. No creature swims, so walkers cross only at the
  fords' **shallows**, a new liquid kind (`:shallows`, a blueprint's `shallow`): a hand of water
  level with the deep water beside it, waded by everything. **Waterfalls**
  (`src/waterfall.lisp`, a blueprint's `falls`): a sheet of water pouring in lanes, foam churning
  at its foot and a looping roar (`waterfall`, a new clip). `*connector-kinds*` gives each kind
  with a middle its liquid (`kind-liquid`), which replaces the canal's special cases
  (`under-channel-p`), and `check-kit` swims a block with a rill's doorway. A block may now have
  doorways of two networks' kinds: the generator keeps a network per family, and leaves out a
  block that would start another of a family already full. `check-kit` is clean.
- **A level has a creek 56% of the time.** Its weights decided little (every level at full weight,
  94% at half), so a network may carry a chance a level has one at all, rolled from the level's
  seed on a random state of its own (`network-barred`): `*creek-chance*` 0.6, the creek's weights
  halved. Over run seeds 1 to 100 (300 levels): 6.4 creek blocks on average, never two, every
  doorway reachable, only ogres stranded; flooded runs on 27% of levels (11% before), the sink
  starting them. Creek blocks cost 6.1 ms of GPU a frame against the canal's 6.5 (seed 17, level 4).
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
