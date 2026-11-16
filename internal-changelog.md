# Internal changelog

Every change worth recording, internal ones included: an entry in the commit that earns it,
under `## Unreleased`, given its date and version when a release is cut. The changelog
players get is `CHANGELOG.md`, drafted from this one at each release and approved before it
ships ("Releases" in CLAUDE.md). The history before this file is in `git log`.

## Unreleased

- **The casting hands' thumbs point inward in the fire cast's release and the hands flung open
  after it** (every striking spell, the nova's too). Both pictures show the backs of the gauntlets,
  so the thumbs can only be on the inner edges, but they had the hands swapped, a right hand on the
  left and a left on the right, thumbs toward the screen's sides. They are drawn again
  (`release-thumbs-1`, `open-thumbs-3` in `art/hands/`), `hands-common.txt` now saying which edge
  the thumbs are on, and the hands strip and its five recoloured looks rebuilt. Healing's rise
  turns the palms up to the camera, so its thumbs rightly stay outside. The code was right:
  `hands-split` cuts each picture in two and mirrors nothing. The old takes are in the art attic.
- **The acolyte calls down a firestorm**, from the second level of a run on (`:abilities` in
  `*run-levels*`, `level-ability-p`) and on the debug level. A lone acolyte had become a mana
  spring: the player stood holding Absorb Projectiles and swallowed its cinders. Now, when the
  player holds Absorb facing it or has swallowed two of its cinders, or on a 30% roll, with its
  16 s cooldown up, it draws a sun-wheel sign under the player (1.6 s to step out), then holds a
  storm of fire for 8 s that drifts after them at 2.5 m/s, faster than a walk with Absorb held,
  burning about 9 a second; a flinch or its death puts it out, and holding it makes it easier to
  flinch. The acolyte moved to `src/acolyte.lisp` as an `ability-user` (`:cinder`, `:firestorm`);
  the storm is a `spell-circle` with a fire aurora on its rim and, inside, a column of fire whirling
  like a tornado in its middle (`fire-column`, on the tornado's funnel mesh), two more auroras turning
  opposite ways, flame wisps (the burn aura's strip) going round its centre, whirling embers and
  sparks, cinders slanting down with the swirl, and a lamp (0.5 ms of GPU seen from outside, about 1.7
  standing in it), and its sign is drawn by `tools/draw_fire_sign.py`. Three new clips:
  `firestorm-sign`, `firestorm-ignite`, `firestorm-roar`.
- **The settlement's trainer has a full sprite set**, so once the town is sacked it walks, chops
  two-handed with its wooden sword, flinches and leaves a corpse like the guard, instead of gliding,
  striking standing and sinking into the floor. Made the walkers' way from its lineup cell
  (`art/trainer/`: a turnaround, then walk, attack, flinch and a front-only death, prompts
  `art/prompts/trainer-*.txt`), sliced into `data/sprites/trainer/` at 118 px and hooked up with
  `define-townsfolk-set trainer ... :attack T`; the old single picture is gone, and a thriving
  town's trainer still stands at its post, now seen from every side, and talks. Its blow is timed to
  its strip (0.4 s raised overhead, 0.9 m reach). Its sheets came with a cyan frame round their
  edges, whose pale blends `slice_turnaround.py` and `stack_views.py` didn't key, scaling each view
  by the whole sheet's height; both now skip such a frame (the guard's and townsman's slices are
  unchanged).

## November 16, 2026 v0.1.1

- **Windows lets the game hold 2048 files open.** Every sound voice keeps its Vorbis file open,
  and with 0.1.1's clips that came to 548 (534 sound voices, 14 tracks) against v0.1.0's 492; the
  Universal C runtime allows 512, so the next voice failed (FILE-OPEN-FAILURE, at
  `water-lap.ogg`, 504 voices in) and the release run's Windows self-test failed on its first
  level. `raise-open-file-limit` (main.lisp, from `start-sound`) calls `_setmaxstdio` with
  `*max-open-files*` in each C runtime loaded (`*c-runtimes*`: ucrtbase.dll, msvcrt.dll), each
  found by its module through GetModuleHandleA and GetProcAddress when the game starts rather
  than linked into the image, and logs the limits it got. Found by name alone, `_setmaxstdio` was
  msvcrt's, and the vorbis DLL's runtime stayed at 512. The self-test's report now carries the
  first runtime error's backtrace, which is how the file was found.
- **CI's art audit updates the package index first.** Its `apt-get install` of Pillow and NumPy
  ran on the runner image's index, which named a Pillow build the mirror no longer had (404), and
  failed CI on the release commit before it built anything. It now runs `apt-get update` first,
  as the build step after it does.
- **Four new music loops.** Two for exploration and two for combat, composed as MIDI and
  rendered through FluidR3_GM, each unlike every track before it (`tools/compose_explore_4.py`,
  `_explore_5.py`, `_combat_6.py`, `_combat_7.py`; `*music-moods*`): explore-4, a harpsichord
  lament in 12/8 in F# minor with English horn, bassoon and viola; explore-5, tense, B minor, a
  footstep pulse and heartbeat under a cello's half-step theme; combat-6, a war dance in 7/8 in C#
  Phrygian dominant on bassoon riff, hand drums, oboe and shanai; combat-7, G minor battle music in
  the trailer's vein, a half-step violin figure over drums on every beat and bare brass fifths.
  `tools/midi_music.py` takes the beats a bar (`beats`) for the 7/8. ElevenLabs takes of a
  music-box waltz and a danse macabre were turned down, and the plans written to replace them
  wait for credits (`audio/prompts/music-*-tense-plan.json`, `-battle-plan.json`). For players'
  CHANGELOG at the next release: "Four new music tracks, two for exploring and two for fights."

- **Effects face the screen at any angle.** `face-camera` (fx.lisp) turned an effect sprite about
  +Y by the yaw and then about world X by the pitch, which is the view's plane only when one of
  them is 0: looking up or down at most headings tipped projectiles, bursts and flashes over (a
  bolt's burst on the ceiling, seen from a stair below). It now turns by the pitch first and then
  the yaw, as the camera does: at pitch ±0.6 and ±0.9, yaw 0.9 to 2.2, the sprite's right and
  facing are the camera's. Taken from `claude/gifted-varahamihira-2db85e` (9b6a04e) without its
  glow-layer half, which this branch doesn't have. For players' CHANGELOG at the next release:
  "Spells and other effects no longer tip over when you look up or down."

- **Fixed falling out of the world beside a 45° wall.** Walking into a monster with a 45° rock
  wall at the player's back (a cave passage, run seed 3269847334651320094) could put the player
  through the rock and out of the level: the push back off the monster left the feet a hair behind
  where the move started, inside the wedge's diagonal, and a wedge pushes a body that moves toward
  its cut corner out of its far face. A sideways move is now never pushed back past where it started
  (`move-axis`, player.lisp), as a vertical one already wasn't, unless the body began it inside a
  solid. Holding Absorb Projectiles no longer logs "No :ABSORB effect" each time.

- **Spell tiers: free, stamina and mana, decided by the spell.** A mage was an enchantment with no
  sword under it: every cast paid all of its price in mana that doesn't regenerate (the Fire Bolt 14 mana
  for 7-9, a full pool three bolts). Now a spell's tier follows from what it is (`spell-tier`,
  spells.lisp), from its power (today's price formula, renamed `spell-power`), delivery, effects,
  durations and area. **Free**: a projectile, touch or seeker of one damage effect (knockback up to 4
  beside it), nothing lasting, no area, power up to 14: the Fire Bolt stays as it was and costs nothing,
  every 0.5 s, its projectile flying 20 m; a free touch of fire 10-14 is the sword's equal. **Stamina**: up
  to two effects of damage, knockback and slow, up to 4 s and 1.5 m, power up to 40 (a beam 20), costing
  its power in stamina. **Mana**: everything else, every heal, ward and drain, at its power with striking
  effects halved (`*cast-strike-scale*`, so a cast costs what the same spell does as an enchantment).
  Dust, enchantments and found runes are priced by power as before. **Overcharge**: a striking stamina or
  mana spell held grows to × 1.6 for twice its price by 1.35 s, slowing the player as the maul's charge
  does; full, it knocks a shield or ward aside and always flinches (the knight took 37 through its shield).
  **Absorb Projectiles** (`:absorb`, magic.lisp): a new self effect, held on stamina (its power a second, no
  stamina back meanwhile, and a stamina a point of the mana it gains: free, a live acolyte was a mana
  spring), that swallows hostile
  projectiles carrying damage from in front for its percent of their power in mana, or of the mana an own
  spell sent back cost (a free one gives none); rifts and gusts still strike. Held, it hums low
  (`absorb-channel`), and a projectile swallowed swoops up and down in pitch (`absorb-take`, the hum
  bent). **Off hands**: each hotbar
  slot holding a rune can hold an off-hand rune, cast with the right button, set by dragging onto the
  slot's corner (`offhands`, `offhand-cells` in saves and the stairs); the left hand's fire shows the
  slot's rune, cast with the left button, the right hand's the off hand's; the hands share one cast at a time,
  and a rune is in one place at a time. A held spell's button held down starts it once the hands are
  free (`start-held-casts`), so a press during a cooldown or a weapon switch isn't lost. The forge's
  Effect button cycles heal, ward and Absorb on a self spell (Absorb had no starting dials in
  `*new-effects*`, and the click errored), and a save from before Absorb learns it on load and on the
  stairs (`migrate-known-effects`). A run starts with the sword, the Fire Bolt with Absorb in its off
  hand, and heal on key 3. **Deliveries**: Seeker and Beam ported from the spell-secondary branch (its
  repricing left out; the beam's first-strike sound now plays, and a beam's self effects land), and Nova,
  a sphere growing from the caster that strikes each body as it reaches it, its look the element's: an
  aurora dome (fire's licking flames, frost's shards, drain's curtains hanging from the top, force's
  plain streaks; a slow halves their pace), or for shock a crackling cage of lightning (`bolt-lines`,
  sparks.lisp, a new renderer of jagged pixel-stepped bolts) with arcs round and between the
  creatures struck; a band where it meets the level (`nova_sweep` in the lit shaders), fire's scorch
  and frost's rime behind it, and each element's particles. **Art**: the hands show Absorb, healing and ward spells as their own magic,
  not fire (`*hand-motifs*`, hands.lisp): Absorb a void in each palm and, held, a void between the hands
  drinking in streaks of blue light (turned by `tools/turn_spiral.py --all`); healing ribbons of light
  round the forearms that rise, wrap them as it lands and fade into motes; ward gold hexagons over
  each palm that become a honeycomb pane. Their idles (4 frames, the ward's 3) move the magic over still
  hands by `tools/animate_idle.py`: the void's specks orbit, and both voids have an ornate rim (a navy,
  deep blue and ice-lit ring with a glint, pale dashes turning round it, the held void's streaks shaded
  navy to ice as they fall in); only a band of light
  running up the ribbons is drawn, the gauntlet showing elsewhere; three gold hexagons, one above two,
  take turns bold. Each hand shows its own rune at rest, so fire in one and a
  void in the other. The heal hand look (green fire) is gone, `make_shield.py`'s frames take a `magic`
  flag for pictures whose light isn't fire, and an Absorb icon and status veils at the
  screen's edges for a ward, the blessing and healing over time (`status-veil`, hud.lisp;
  `tools/draw_status_veils.py`). The forge shows the derived tier, cost and reason, and its magnitude dial
  is "Amount". Found runes over run seeds 1 to 30: level 1, 11 free, 7 stamina, 12 mana; deeper, about two
  thirds mana; the layouts, creatures and health and mana pickups match master, the hoards' items and
  piles move with the runes' draws. No save version change: old runes load as what they are, and an old
  save has empty off hands. For players' CHANGELOG: "Spells now cost by their strength: weak ones are
  free (the Fire Bolt among them), stronger ones cost stamina, and the strongest, and every heal, cost
  mana. Hold a stamina or mana spell to overcharge it; a full charge breaks a shield. New: Absorb
  Projectiles turns enemy spells into mana, every rune slot can hold a second rune for the right button,
  and Seeker, Beam and Nova spells at the Spellforge."

- **Sparks, embers and grit.** Hexmaw's impacts were all strips playing in place; now blows throw
  simulated particles (`src/sparks.lisp`), built as the blood pool is: 512 slots of plain arrays, one
  stream-draw buffer, one draw call, nothing allocated a frame, no art (the shader lays whole
  64-a-metre texels in palette colours, fullbright and opaque). Sparks are two-tone streaks as long as
  their speed across the view, falling, bouncing off solids and cooling down a three-colour ramp:
  off a shield (the knight's steel, a ward's violet) whenever a spell, bash, sweep, sword or spear
  glances off it, from the spear's counter, from the maul's blow (more and faster with the charge)
  and where an earthshake or an ogre's maul hits the floor. Grit flies from every dust puff, bounces
  once, settles and dissolves. Embers rise from torches and lava near the player, each source on its
  own timer, and blink out. Left out of saves. The idea of the kinds is pixelfx's (Patch and Hugo
  Duprez), written anew for 3D; no code was taken. `tools/spark_shots.sh` stages each hook. GPU cost
  is within noise (2.32 ms a frame against 2.30 with 495 particles in view), and about 1% under
  llvmpipe. For players' CHANGELOG at the next release: "Blows on steel and stone throw sparks and
  grit, and embers rise from torches and lava."

- **Camera shake for heavy blows.** The view jerks up and down and across and rolls, about 21
  screen pixels at 720 rows at full strength, swinging back and forth some seven times as it dies
  away evenly over 0.5 s (eased out, as first made, it was one nod: a slam seemed to shake once), when the maul lands (strongest
  at full charge), the earthshake strikes, an ogre lands or slams nearby, the boss's Shockwave goes
  off, the player crashes into a wall or floor, or takes a blow of 8 or more (`kick-camera`,
  player.lisp). It first moved the eye a few centimetres, which shifted nothing past a metre or two
  by more than a pixel or two: an ogre's slam went unnoticed in play. It turns only the view matrix,
  so aim and hit tests don't shake, holds through hit-stop, shows only in play and is never saved.
  Settings has a Screen shake checkbox (`*screen-shake*`, kept in the settings file) to turn it off.
  The idea is pixelfx's {stop, shake, amp}; no code from it. For players' CHANGELOG at the next
  release: "Heavy blows shake the view; Settings → Screen shake turns it off."
- **The mouse cursor no longer flickers over menu buttons.** Each mouse move over a button had
  Alloy set the hand (the button) and then the arrow (the layout tree and the ui, since nothing in
  Alloy takes a pointer move, so the move counted as unhandled). The cursor rested on the arrow and
  flashed the hand while the mouse moved, on every menu. The menu pass now owns the cursor: it drops
  Alloy's sets and, after each move, shows the hand over any row the player clicks (sliders and
  toggles too, which never had it) and the arrow elsewhere, set only when that changes
  (`set-menu-cursor`, menu.lisp). `menu-cursor-problems` checks it beside the layout and click checks;
  it found every point of every button before the fix and nothing on any menu after, at 1280 × 720
  and 1920 × 1080. For players' CHANGELOG at the next release: "The mouse cursor no longer flickers
  between the arrow and the hand over menu buttons."
- **The Spellforge shows when a draft can't be made.** A playtester couldn't tell they lacked the
  dust: the reason was in the note, but in the same cream as every line, and Make looked and lit up
  like any button (a click did nothing visible). Now the note turns ember red while it says why
  (`forge-status-note`, `*forge-warning-color*`), and the Make or Enchant button is greyed, with no
  orange on hover (`forge-make-button`). Every `draft-problem` reason shows the same way (over the mana you hold, a
  weapon's caps, a full bag). A slider that pushes the cost past the dust held, or back under it,
  updates it at once (`refresh-readout`, no remake); a click on the greyed button plays `:refused`.
  For the player changelog: "The Spellforge greys out Make and says in red why, when you lack the
  dust or the spell can't be made."

- **Area bursts are a ball again, in look and in reach.** The copies that fill an area burst at its
  sprite's own size (`burst-rings`, from the art-consistency pass) lay on flat rings at the impact's
  height, a line of flames from the front and a disc from above: `burst-shells` lays them on shells
  1 m apart, Fibonacci spheres, at most `*burst-max-copies*` (120; a 3 m burst has room for 96, about 1.2 ms a
  frame), none in a solid or behind one from the middle, so on a floor it is a dome and on a wall half
  a ball. `burst-victims` reached a cylinder, the area across and above and below the body, with a
  clear line only across at the burst's height, so a burst under a ceiling hit what stood on the
  storey above: it is a sphere against the body's cylinder now (`burst-reaches-p`), with a line up,
  down or across to it (`clear-line-p`, gore.lisp). (Players will see this.)
- `tools/make_palette.py --data DIR` samples art from another folder, so a palette can be made
  again from art not yet on one (an older commit's `data/`, from `git archive`): from master's art
  before the palette, at 128 colours, it gives the shipped palette exactly. A 256-colour palette
  made so halved the colour error (the sword's warm-shifted steel and leather most of all) but
  spent most of its new colours on near-duplicate warm browns and greys; 128 was kept.
- **The casting hands are remade: the weapons' gauntlets, at the weapons' pixel size.** They were
  bare hands in red sleeves at 8 screen pixels an art pixel at 1080 rows, against the weapons' 5,
  in two halves spread apart. Now they are the sword's and spear's steel gauntlets, their backs to
  the camera and the fire burning behind the fingers, one generated picture a pose (rest, gather,
  the fireball held, the release, the hands flung open) placed by `tools/make_shield.py` from
  `art/hands/hands-frames.txt` at 0.2 art pixels a source pixel (the spear's 0.254 hid the middle
  of the view), so they cover about what the old hands did and draw at `sword-scale`, centred by
  their aim (`*hands-aim*`; `*hands-height*`, `*hands-stretch*` and `*hands-drop*` are gone). Each
  hand still draws its half of the frame, `*hands-spread*` (28 art pixels) out from the middle,
  and they close up where the fire joins between them (`*hands-together*`). The idle loop is
  three frames: the rest pose, and its hands over two other takes' fire alone
  (`tools/swap_fire.py`; a first version kept the rest pose's own fire too, and that frame showed
  two flames at once). `make_shield.py --glow` leaves fire out of its darkening. The six spell
  looks are recoloured from the new strip. CLAUDE.md has a rule against waiting on a `pgrep -f`
  loop that matches its own command line. (Players will see these.)
- **House style written down, and checked in CI.** CLAUDE.md's "House style" gives the rules the
  art now keeps (64 art pixels a metre, first-person and HUD screen scales, the master palette,
  upper-left shading with selective outlines and nothing part transparent, shaders on the texel
  grid) and how to keep them: `tools/restyle.py --house` after every slicer or recolour (the palette,
  and sel-out for the solid things, by path), the texture command lines with their `--contrast`,
  `--tone` and `--palette`, `art/style/anchor.png` (`tools/art_sheets.py --anchor`) and
  `art/prompts/style-common.txt` for new prompts. CI runs `tools/art_audit.py --check`. The casting
  hands are allowlisted at 8 screen pixels an art pixel until they are made again.
- **The script-drawn pickups are shaded as the generated ones are.** `pixelart.house_finish`
  (relief, sel-out, the palette) gives every frame `draw_glyphs.py`, `draw_loot.py` and
  `draw_gold.py` draw a light from the upper left (`relief`: a bevel on the edges, a gradient that
  rounds the shape, a groove cut round each glowing stroke with its lip lit, seeded grain for wear,
  the same pixels in every frame), selective outlines and the master palette, with nothing part
  transparent: the glyphs' and runes' soft halos and the altar sigil's glow, which the game's
  alpha test cut away anyway, are gone. (Players will see these.)
- **Shader effects in whole texels and few tones.** The aurora (the grave circle, the boss's ward
  and summoning flames, the gale sign) is laid on the world's 64-a-metre grid round its ring and up
  it, its light stepped into `*aurora-light-steps*` (10) levels and its colour into a few hues, as the
  funnel already was. Lava's and water's waves move whole texels (one offset per texel of the grid),
  so their texture no longer smears finer than its pixels. The hit flash peaks at 0.5 (was 0.85,
  which turned a close sprite into a flat cream shape) and leans warmer. The rim of bosses, elites
  and enchanted weapons goes `*rim-mix*` (0.85) of the way to its colour and never darker than the
  lit texel under it, a lit edge rather than a neon line. `tools/art_shots.sh` has `flash` and
  `lava` shots. (Players will see these.)
- **One palette for all the art; textures with the sprites' contrast; selective outlines.** Every
  shipped sprite and texture is quantized onto `art/style/palette.txt`, 128 colours in 16 ramps that
  `tools/make_palette.py` clusters (Lab k-means) from the art itself, each group given a share
  (`quantize_to_palette` in `tools/pixelart.py`; `--palette` on `make_texture.py`, `tools/restyle.py`
  for strips). The textures were rebuilt from their sources with their contrast raised to the
  sprites' (`--contrast`, 1.6 for the stones), the cool and off-family stones (stair, dressed stone,
  sarcophagus, ceiling) shifted into the wall's warm grey-brown (`--tone`) and the pillar's orange
  brick muted (`--chroma`). The creatures, townsfolk, pickups, gate, torch, hands and weapons have
  their black outline turned into a dark tone of what it borders (`selout`, `restyle.py --house`), so
  they no longer look cut out against the walls. Splash screens keep every colour (allowlisted). Of
  three variants tried in a test room, this one: the light stays smooth (texel-snapped, banded light
  was the third). (Players will see these.)
- **The HUD's text is Jersey 15, the menus' typeface, and its art is drawn in whole art pixels.**
  Trial's 9 × 17 font is gone from the HUD: `hud-text` draws a bitmap of Jersey 15
  (`data/fonts/hud-font`, made by `tools/make_hud_font.py`) at 27 px, where its outlines fall on
  whole pixels, one screen pixel per font pixel, with a one-pixel shadow; text is laid out by its
  advances (`text-width`), so `+glyph-height+` is now `*glyph-height*` (23). The bars, slots, icons
  and the status time bar are in HUD art pixels, `hud-pixel-scale` screen pixels across
  (`round(rows / *hud-pixel-rows*)`: 2 at 720 rows, 3 at 1080), so they no longer stay 2 px at any
  window size; `*weapon-icon-scale*` is gone, and `*weapon-slot-padding*` and `*weapon-slot-gap*` are
  art pixels (`slot-padding`, `slot-gap`). The bars are 64 × 7 art pixels in a dark frame, each fill
  three tones of a darker, less saturated ramp. The rift burst is drawn at 0.6 m (48 px a metre, was
  36). (Players will see these.)
- **Effects keep the monsters' pixel size.** An area spell's impact was one burst scaled up to the
  area, its art pixels growing coarse (12 px a metre at a 2 m radius, against the monsters' 64): now
  it is scaled at most `*burst-scale-limit*` (1.5) and rings of bursts at their own size fill the
  rest (`burst-rings`). A status aura was one strip stretched to its creature's height (46 px a metre
  on an imp, about 23 on a boss): now it is copies at `*aura-texels-per-metre*` (64) up the body,
  each scaled at most `*aura-stretch-limit*`, the first with the lamp. The casting hands' pixels are
  square (`*hands-stretch*` 1.0, was 1.25), as every other art pixel is. (Players will see these.)
- **Art audit tools.** `tools/art_audit.py` measures every shipped image (art pixels per metre from
  the `define-fx-animation` sizes, colours, part-transparent pixels, outline share, lightness range,
  the first-person and HUD screen scale) and `--check` fails on a house-style rule broken that
  `tools/art_audit_allow.txt` doesn't excuse. `tools/art_sheets.py` makes contact sheets of the art at
  the size it reaches the screen, and `tools/art_shots.sh` staged screenshots on the debug level where
  groups of art meet (a monster at a wall, a torch, an area burst, the hands, the circle, pickups).
- **The boss's Blink is `boss-blink`.** boss.lisp and riftwalker.lisp both defined `blink`, so
  reloading boss.lisp (the live-reload hook, after an edit there) put the boss's in the
  riftwalker's place: its tick then errored every blink ("FX-SPRITE is not of type BOOLEAN", since
  the riftwalker's returns T) and its walk got a NIL path point. Every frame that errored, the runtime-error guard also skipped the tick of each entity
  after the riftwalker in the scene's queue, so the creatures spawned before it stopped turning to
  the camera and only caught up on frames without a blink.
- **A blow between two creatures never hit-stops.** The world-wide 0.06 s freeze stays on blows the
  player deals or takes and on harm from no one (lava); a fight between creatures doesn't freeze the
  game wherever it is (`felt-hit-p` and `*hit-stop-reach*`, its 10 m limit, are gone).
- **A vertical move can't push the player through a solid, and a fall out of the world is
  logged.** `move-axis` put the feet under the bottom of whatever a rise overlapped, and on top of
  whatever a fall overlapped, even a solid the body was already inside: a jump from inside a
  ledge put them under the floor (the slab under it next, then the void), and a fall beside a tall
  45° wall could put them on top of it. Now the feet never pass where the move started. The player
  fell out of the world after jumping on ice by the frost shrine, but its cause wasn't found:
  600,000 random moves through that level's geometry around the shrine left no one inside a solid
  or moved them more than 0.6 m. So `report-fall` logs the last 2 s of movement
  (`*fall-trace*`, kept by `note-fall-trace` every tick, no allocation) when the player drops
  below `*kill-height*` and goes back to the start.
- **No slot to fall into beside the frost shrine's dais.** Where the rock's 45° wall met the dais's
  45° edge they ran parallel 1 m apart, leaving a slot of floor 0.8 m down between them (and a
  triangle 0.4 m down beside the step); the player fell in. The rock pairs there now stand on ice
  filled up to the dais's or step's height, and the dais runs square up to them (`tools/cave_plans.py`,
  new legend characters `a` to `d`). `tools/levelcheck --kit --strict` is clean.
- **A creature's standing picture is always loaded with its scene.** A creature was staged with
  only the picture it showed at that moment plus its strips, so one restored from a save mid-walk
  left its turnaround out of the scene's staging area, and Trial unloaded it if the scene before
  had loaded it fresh: once that creature stood still, every frame with it in view failed to draw
  and the game looked frozen (seen after a quickload in a town, on a commoner). `stage :after` on
  `creature` now stages its `body-texture` too. Reproduced on 1 in 4 tries of a quickload with a
  commoner walking, none in 6 after.
- **One combat for every actor: `fight-foe` is gone.** Every monster, boss power and townsperson
  fights a creature with the same hunt it uses on the player ("Targets and sides" in CLAUDE.md), so
  `fight-foe`, its `:around` methods, `foe-attack` and the conversion gate are removed. Fights against
  the player are unchanged: scripted fights of every kind against a standing player matched a
  baseline recorded before the work, and run seeds 1 to 10 build the same levels, creatures and
  pickups. For the player changelog at release: "Monsters fight the town's guards and townsfolk with
  everything they have (an ogre leaps at a guard, a harpy dives at one, a necromancer draws its
  circle under one), and a monster struck again and again by another kind turns on it."
- **A boss's powers aim at its target.** Fire volleys, skull barrages, the grave circle, the
  shockwave's reach, the tornado's sign and the blink read `hunt-target` (`boss-sees-target-p`), and
  its summons are on its side and hunt its target. Waking it and sealing the arena stay the
  player's.
- **The riftwalker fights creatures too.** Its pulls, swaps and pushes are aimed at its target,
  the push's "shield up" asks `target-guarding-p`, the swap's pounce lands behind any target, its
  blinks keep the target in sight, and its call brings only allies of its own side, set on its
  target.
- **The gale wraith fights creatures too.** Its sign is laid under its target and a creature's
  tornado chases what its caster hunts (`vortex-target`), so a wraith's tornado takes a guard.
- **The necromancer fights creatures too.** Its grave circle is drawn under its target, its skulls
  home on what it hunted as it cast (a projectile's `homing-target`, saved; NIL is the player), and
  a skeleton it raises is on its side (`summoner`) and hunts its target.
- **The harpy dives at creatures too.** Its dive aims at its target's head (`strike-height`, or a
  shorter target's chest, `aim-height`) and its talons strike through `strike-target`.
- **The imp and the ogre fight creatures as they fight the player.** The leap (`plan-leap`,
  `try-leap`) aims at the leaper's target, so an imp pounces and an ogre leaps at a guard, and an
  ogre's quake shakes it as it does anyone; the claw, the pounce's claw and the slam go through
  `strike-target`, the imp springs back from its target (`spring-from-target`) and flees from it,
  and its shriek sets its allies on its target. A slam's victim isn't shoved again by the slam's
  own shake (`quake`'s `:spare`). Theft stays the player's: an imp steals only from them.
- **Creatures hunt a target, and `hostile-p` says who fights whom.** A creature's `quarry` (the
  player or a creature) replaces `foe`; `hunt-target` falls back to the player when it is hostile
  to them, so off the settlement nothing changes. Sides (`allegiance`): the player, the monsters,
  the settlement's faction, a summoned creature its `summoner`'s. Monsters are hostile to every
  other side, townsfolk to the player while provoked, any other faction's people to the player at
  standing -50 or under (`*hostile-reputation*`). `notice-targets` (was `notice-player`) looks for
  the nearest hostile actor it sees, so monsters notice townsfolk on sight and guards notice
  monsters (`guards-watch` is gone), within 20 m of their post (`*town-leash*`). Struck by a hostile
  actor, a creature turns on it unless its target is in reach. **Grudges**: three blows within 12 s
  from a creature of another kind it isn't hostile to turn it on that one (`note-grudge`), so a
  stray ogre landing doesn't set the level fighting. Attack spots are claimed round each hunter's
  own target. A raid sends its monsters (`sent`: kept after their guard unseen, a 60 m walk). A blow
  between creatures hit-stops only within 10 m of the player. The acolyte, knight, skeleton and the
  townsfolk hunt creatures with the full hunt; the rest still use `fight-foe` until converted.
- **A creature's hunt asks about its target, not the player.** The first step toward one combat
  for every actor: the hunt's helpers (`target-within-p`, `target-angle`, `target-distance`,
  `face-target`, `target-bearing`, `sees-target-p`, attack slots, flanks, retreats, the plain
  blow and spell) read `hunt-target`, still always the player, through a small protocol with a
  method for the player and one for a creature (`aim-height`, `target-facing`, `target-live-p`,
  `target-guarding-p`, `target-swimming-p`, `strike-target`, `shove-target`). No change in play.
- **A clip swapped into the running game no longer comes up silent.** `reload-sound` (the sfx
  picker's swap) freed the clip's old voices, and Harmony kept their unpackers for the next voices
  made, ended and, for a stopped loop or a cut one-shot, still paused: the new voices played
  nothing, until a second swap happened to get clean ones. `free-voices` now frees the unpackers
  too (Harmony's internal `free-unpackers` pool), so new voices get fresh ones.
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
  one-shot `play-sound` returned until it is next played. `make_sfx.py` given clip names checks only their picks, since a worktree has only its own
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
