# Sound effects

Every moment that makes a sound, where in the code it starts, and the clip for it. Each
clip's prompt is `audio/prompts/sfx-<clip>.txt`; generate its takes with

```bash
tools/gen_sfx.py audio/sfx/<clip>.wav -f audio/prompts/sfx-<clip>.txt -d <s> -n <takes> [--loop]
```

**Pos**: P is positional, at a point in the world: it plays on Harmony's `:effect` space
mixer, which takes only **mono** (a stereo voice there hangs the mixing thread), so the
chosen take is downmixed. 1P is first-person or UI, not placed, stereo on `:speech`.
**L** is a loop (`--loop`). **s** is the `--duration` to ask for, **takes** the `-n`:
more where the game plays variants in turn (hurt grunts, footsteps). Tier 1 is the
combat loop, tier 2 the world and the body, tier 3 polish.

Hooks are `file:line` in `src/` as of this list. "(edge)" means a level the code keeps
and no event: the sound needs the last tick's value to see the change.

129 clips; tier 1: 74 clips, 219 s of takes, tier 2: 29 clips, 72 s of takes, tier 3: 26 clips, 70 s of takes. About 10 credits a second: 361 s, about 3,606 credits for everything.

## Player: weapons and shield

First-person, so stereo is fine (`:speech`).

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| sword-swing | 1 | 1P | 0.5 | 3 | `player-swing` sword.lisp:142, `:sword` |
| spear-thrust | 1 | 1P | 0.6 | 3 | `player-swing` sword.lisp:142, `:spear` |
| blade-hit-flesh | 1 | P | 0.5 | 3 | `swing-hit` sword.lisp:208, target that `bleeds` |
| blade-hit-bone | 1 | P | 0.5 | 3 | `swing-hit` sword.lisp:208, the skeleton |
| shield-raise | 1 | 1P | 0.5 | 3 | `block-raise` leaving 0, sword.lisp:253 (edge) |
| shield-block | 1 | 1P | 0.6 | 3 | `hurt-player` player.lisp:700-702, blocked |
| shield-guard-break | 1 | 1P | 0.8 | 3 | `hurt-player` player.lisp:703-708, `break-guard` 658 |
| shield-bash | 1 | 1P | 0.5 | 3 | `player-bash` sword.lisp:147 |
| bash-hit | 1 | P | 0.5 | 3 | `bash-hit` sword.lisp:217, a target |
| bash-glance | 1 | P | 0.6 | 3 | `bash-hit` sword.lisp:223-226, a covered view (knight, warded boss) |
| draw-sword | 1 | 1P | 0.6 | 2 | `(setf (weapon player))` sword.lisp:270, `:sword` |
| draw-spear | 1 | 1P | 0.6 | 2 | `(setf (weapon player))` sword.lisp:270, `:spear` |
| draw-magic | 1 | 1P | 0.7 | 3 | `(setf (weapon player))` sword.lisp:270, `:hands` and `:tempest` |

## Player: spells

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| bolt-cast | 1 | 1P | 1.2 | 3 | `release-spell` player.lisp:176, bolt |
| bolt-flight | 1 | P L | 2 | 2 | `launch-projectile` spells.lisp:144 until `impact` 157 or despawn 252 |
| bolt-impact | 1 | P | 1.2 | 3 | `impact` spells.lisp:157 |
| bolt-hiss-water | 2 | P | 0.8 | 2 | `impact` from spells.lisp:250, liquid is water |
| cast-fizzle | 1 | 1P | 0.5 | 3 | `player-cast` player.lisp:169 fails for mana |
| tempest-cast | 1 | 1P | 1.2 | 3 | `release-spell` player.lisp:176, tempest |
| tornado | 1 | P L | 4 | 2 | `start-vortex` vortex.lisp:332 until `leave :after` 380; volume by `vortex-strength` |
| whirl-wind | 2 | 1P L | 3 | 2 | `note-caught` vortex.lisp:687 while `(whirl player)` |

## Player: body and movement

First-person unless marked.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| player-hurt | 1 | 1P | 0.5 | 4 | `hurt-player` player.lisp:684, a blow (`shove`) |
| player-burn | 2 | 1P | 0.6 | 2 | `hurt-player`, `:by :lava` or `:tornado` (no shove) |
| player-death | 1 | 1P | 1.5 | 3 | `player-dies` player.lisp:672 |
| body-impact | 2 | 1P | 0.6 | 3 | player `hit-surface` player.lisp:551 |
| footstep-stone | 2 | 1P | 0.5 | 4 | new stride counter in `walk` player.lisp:576, grounded |
| footstep-snow | 3 | 1P | 0.5 | 4 | the same counter, on a `snow` floor |
| ice-slide | 3 | 1P L | 2 | 2 | `walk` player.lisp:582-585 while `footing` and moving |
| jump | 2 | 1P | 0.5 | 2 | `walk` player.lisp:602 |
| land | 2 | 1P | 0.5 | 3 | `note-impacts` player.lisp:567, above a minimum `vy0` |
| winded | 3 | 1P | 1.5 | 2 | `update-stamina` player.lisp:448, `winded` set |
| splash-in | 2 | 1P | 0.8 | 2 | `(setf (swimming player))` player.lisp:521, NIL to T |
| splash-out | 2 | 1P | 0.8 | 2 | `(setf (swimming player))` player.lisp:521, T to NIL |
| swim-stroke | 3 | 1P | 0.6 | 3 | `swim` player.lisp:347, throttled |
| climb-out | 3 | 1P | 0.6 | 2 | player.lisp:391, `climbing` set |
| underwater | 2 | 1P L | 4 | 2 | `*eye-underwater*` edge, `place-camera` player.lisp:325 |
| surface-gasp | 3 | 1P | 0.8 | 2 | `update-breath` player.lisp:413, surfacing with breath low |
| drowning | 3 | 1P | 0.8 | 2 | drown damage, player.lisp:424 |
| lava-step | 2 | 1P | 0.6 | 2 | `wading` becomes `:lava`, player.lisp:503 |

## Creatures

All positional. Generic hooks, one per event with a sound slot per class: **alert** `notice-player` creature.lisp:873 (and the other alert setters, `hurt` 481, `burn` 511, `block-hit` 544, when alert was 0); **wind-up** `start-attack` creature.lisp:1043; **release** `release-attack` 1256 (the class's method); **pain** `hurt` 482-488 when it flinches and lives; **death** `hurt` 490 and `burn` 512; **step** `walk-distance` crossing a stride (walk frame 0 or 2, creature.lisp:762, 1427), walkers only. A boss uses its kind's clips pitched down by `size-scale`.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| imp-alert | 1 | P | 1 | 3 | alert: imp |
| imp-pain | 1 | P | 0.5 | 3 | pain: imp |
| imp-death | 1 | P | 1.2 | 3 | death: imp |
| imp-claw | 1 | P | 0.5 | 3 | wind-up: imp (hit at 0.5 s) |
| acolyte-alert | 1 | P | 1.2 | 3 | alert: acolyte |
| acolyte-pain | 1 | P | 0.5 | 3 | pain: acolyte |
| acolyte-death | 1 | P | 1.8 | 3 | death: acolyte (it burns: `update-death-glow` creature.lisp:1483) |
| acolyte-cast | 1 | P | 0.8 | 3 | wind-up: acolyte (flame kindles, 0.75 s held) |
| cinder-flight | 1 | P L | 2 | 2 | `launch-projectile` spells.lisp:144, `cinder` |
| cinder-impact | 1 | P | 0.8 | 3 | `impact` spells.lisp:157, `cinder` |
| knight-alert | 1 | P | 1.2 | 3 | alert: knight |
| knight-pain | 1 | P | 0.6 | 3 | pain: knight |
| knight-death | 1 | P | 2 | 3 | death: knight (kneels, topples, crashes) |
| knight-mace | 1 | P | 0.7 | 3 | wind-up: knight (hit at 0.75 s) |
| shield-deflect | 1 | P | 0.8 | 3 | `block-hit` creature.lisp:540, from `deflect` spells.lisp:187 |
| harpy-alert | 1 | P | 1 | 3 | alert: harpy |
| harpy-pain | 1 | P | 0.5 | 3 | pain: harpy |
| harpy-death | 1 | P | 1.2 | 3 | death: harpy |
| harpy-flap | 1 | P | 0.5 | 3 | flap downstroke, `show-own-pose` flyer.lisp:117 |
| harpy-dive | 1 | P | 1 | 3 | `aim-dive` flyer.lisp:206 |
| harpy-crash | 2 | P | 0.6 | 2 | `lie-downed` flyer.lisp:161, `landed` set |
| necro-alert | 1 | P | 1.5 | 3 | alert: necromancer |
| necro-pain | 1 | P | 0.6 | 3 | pain: necromancer |
| necro-death | 1 | P | 1.8 | 3 | death: necromancer |
| skull-cast | 1 | P | 0.8 | 3 | release: necromancer's grave skull |
| skull-flight | 1 | P L | 2 | 2 | `launch-projectile` spells.lisp:144, `grave-skull` |
| skull-impact | 1 | P | 0.8 | 3 | `impact` spells.lisp:157, `grave-skull` |
| raise-channel | 1 | P L | 2 | 2 | `update-raise-glow` necromancer.lisp:283-301 (stops on a broken channel) |
| raise-release | 1 | P | 1.5 | 3 | `raise-corpse` necromancer.lisp:245 |
| grave-cast | 1 | P | 0.8 | 2 | `cast-grave-circle` necromancer.lisp:254 |
| grave-circle | 1 | P L | 2.5 | 2 | `place-circle` spells.lisp:604 until it strikes |
| grave-spikes | 1 | P | 1 | 3 | `strike-circle` spells.lisp:523 |
| skeleton-alert | 1 | P | 0.8 | 3 | alert: skeleton |
| skeleton-pain | 1 | P | 0.5 | 3 | pain: skeleton |
| skeleton-collapse | 1 | P | 1.2 | 3 | death: skeleton (falls into a pile of bones) |
| skeleton-chop | 1 | P | 0.6 | 3 | wind-up: skeleton |
| skeleton-rise | 1 | P | 1.2 | 3 | `spawn-raised-skeleton` necromancer.lisp:118 |
| ogre-alert | 1 | P | 1.5 | 3 | alert: ogre |
| ogre-pain | 1 | P | 0.7 | 3 | pain: ogre |
| ogre-death | 1 | P | 2 | 3 | death: ogre |
| ogre-slam | 1 | P | 1.2 | 3 | `release-attack` ogre.lisp:284 (the maul's impact) |
| ogre-leap | 1 | P | 0.8 | 3 | `launch-leap` ogre.lisp:260 |
| ogre-land | 1 | P | 2 | 3 | `land-leap` ogre.lisp:351 (the quake) |
| wraith-alert | 1 | P | 1.5 | 3 | alert: gale wraith |
| wraith-pain | 1 | P | 0.6 | 3 | pain: gale wraith |
| wraith-death | 1 | P | 2 | 3 | death: gale wraith (the rags settle) |
| tempest-sign | 1 | P L | 1.5 | 2 | gale-sign tick wraith.lisp:174-197 (also the boss's tornado cast) |
| gust-cast | 1 | P | 0.8 | 3 | release: the wraith's gust |
| gust-hit | 2 | P | 0.6 | 2 | `apply-effect :gust` wraith.lisp:204 |
| step-light | 2 | P | 0.5 | 3 | step: imp, necromancer |
| step-armour | 2 | P | 0.5 | 3 | step: knight |
| step-heavy | 2 | P | 0.6 | 3 | step: ogre |
| step-bone | 2 | P | 0.5 | 3 | step: skeleton |
| creature-sizzle | 2 | P | 0.6 | 2 | `burn` creature.lisp:505 (lava tick) |
| flounder | 3 | P L | 2 | 2 | afloat, creature.lisp:1519-1535 |

## Gore

No sound per splat or drip: one burst lands 20 to 40 drops.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| flesh-wet | 1 | P | 0.5 | 3 | `bleed` gore.lisp:207, once a hit |
| gib-burst | 1 | P | 1 | 3 | `burst-gibs` gore.lisp:524 |
| bone-shatter | 1 | P | 1 | 3 | `burst-gibs` gore.lisp:524, dry (skeleton) |
| gib-bounce | 3 | P | 0.5 | 3 | `step-gib` gore.lisp:622, above 1.5 m/s, throttled |

## Boss and arena

The volley, barrage, grave circle, leap, shockwave and tornado powers reuse the cinder, skull, grave, ogre and tornado clips.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| gate-drop | 1 | P | 1.5 | 3 | `seal-arena` boss.lisp:150 (silent with `:instant`) |
| gate-rise | 2 | P | 2 | 2 | `unseal-arena` boss.lisp:165, after the boss dies (not on a reset) |
| boss-enrage | 1 | P | 1.8 | 3 | `enrage` boss.lisp:694 |
| summon-sigil | 2 | P L | 1.5 | 2 | sigil tick boss.lisp:400-404 (stops when the cast breaks, 416) |
| summon-burst | 2 | P | 1 | 3 | `summon-minions` boss.lisp:335 |
| blink-out | 2 | P | 1.2 | 2 | `blink` boss.lisp:464 |
| blink-in | 2 | P | 1.2 | 2 | `blink` boss.lisp:469 |
| ward-hum | 3 | P L | 2 | 2 | the ward's glow, boss.lisp:733 |

## World ambience

Loops on many sources: play only the nearest few of each kind.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| torch-crackle | 2 | P L | 4 | 2 | `add-torch` lights.lisp:102 |
| lava-bubble | 2 | P L | 4 | 2 | lava glow lamps, `add-liquid` liquids.lisp:199-222 |
| water-lap | 3 | P L | 4 | 2 | water surfaces, liquids.lisp |
| dungeon-drips | 3 | 1P L | 8 | 2 | room tone under everything |

## Pickups and inventory

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| pickup-herbs | 2 | 1P | 0.5 | 2 | `pickup` tick :after pickups.lisp:104, `:herbs` |
| pickup-shard | 2 | 1P | 0.8 | 2 | same, `:shard` |
| pickup-potion | 2 | 1P | 0.5 | 2 | same, either potion |
| potion-drink | 2 | 1P | 0.8 | 3 | `use-quickslot` inventory.lisp:71 |
| item-pick | 3 | 1P | 0.5 | 2 | `mouse-press` inventory.lisp:262, `dragging` set |
| item-drop | 3 | 1P | 0.5 | 2 | `mouse-release` inventory.lisp:266 |
| bag-open | 3 | 1P | 0.5 | 2 | `open-inventory` inventory.lisp:232 |
| bag-close | 3 | 1P | 0.5 | 2 | `close-inventory` inventory.lisp:240 |

## UI and transitions

Death and victory screens have their music; F12 needs nothing.

| Clip | Tier | Pos | s | Takes | Hook |
|---|---|---|---|---|---|
| menu-hover | 3 | 1P | 0.5 | 2 | `(setf alloy:hovered-p) :after` menu.lisp:97 |
| menu-select | 3 | 1P | 0.5 | 2 | `queue-menu-action` menu.lisp:335 |
| menu-back | 3 | 1P | 0.5 | 2 | `close-settings` menu.lisp:611, `close-slot-menu` 622, `resume-game` 594 |
| menu-slider | 3 | 1P | 0.5 | 2 | slider setter menu.lisp:330 |
| game-saved | 3 | 1P | 1 | 2 | `save-game` save.lisp:288 returns T |
| refused | 3 | 1P | 0.5 | 2 | a refused save, load or quickslot |
| map-open | 3 | 1P | 0.8 | 2 | `open-map` map-view.lisp:253 |
| map-close | 3 | 1P | 0.6 | 2 | `close-map` map-view.lisp:259 |
| map-storey | 3 | 1P | 0.5 | 2 | `step-map-storey` map-view.lisp:243, the storey changes |
| level-gong | 3 | 1P | 3 | 2 | the level banner, main.lisp:31 |

## In the game

`audio/sfx-picks.txt` says which takes each clip plays (take 1 when it has no line), and
`tools/make_sfx.py` turns them into `data/sfx/` (mono for P clips, Ogg, one loudness) and its
`index.lisp`; `src/sound.lisp` plays them. `tools/sfx_picker.py` is a page to choose takes on,
swapping each into the running game. Every clip is hooked. Where the hooks differ from the
tables above:

- A creature's clips are its class's `define-creature-sounds` (a boss shares its kind's):
  `:windup` plays as `start-attack` starts any attack (the imp's claw, the knight's mace, the
  skeleton's chop, the acolyte's kindling), so a boss's powers play its kind's wind-up too.
  The necromancer's and wraith's casts sound from their abilities instead.
- A spell's clips are `*spell-sounds*` (spells.lisp): its creature cast, flight loop, impact,
  and a circle's loop and strike. A weapon's are `*weapon-sounds*` (sword.lisp).
- `player-hurt` plays for a blow or a crash, not each tick of a burn or drowning.
- `flesh-wet` plays with every wound that bleeds, so a sword hit is `blade-hit-flesh` and it.
- The boss's shockwave plays `ogre-land`; its leap is the ogre's.
- The player's footsteps, strokes and loops are `body-sounds` (player.lisp): a footstep every
  `*footstep-stride*` metres on foot, `footstep-snow` where the floor's tread is snow
  (`floor-tread`, greybox.lisp: snow is in `*footings*` with no friction, so it is no slipperier),
  none while sliding on ice, which plays `ice-slide` instead; a stroke every `*swim-stroke-stride*`.
- A creature's footstep is its `:step` clip, every two walk frames (`creature-steps`), so it
  follows the walk animation; the acolyte glides and the flyers flap, so they have none.
- `player-burn` and `drowning` play for each tick of a burn or of drowning; `gate-rise` only on
  the test level, the one place the gate goes up after a fight.
- Torches, lava and water are `*ambient-sources*` (liquids.lisp): each loop on its nearest few
  sources in reach, chosen again every `*ambience-interval*`, a lava or water box heard from the
  nearest point of its surface. `dungeon-drips` is the room tone, quiet under water.
- `menu-hover` plays for the mouse only, not for the keyboard moving the focus; a Back or Resume
  button plays `menu-back`, not `menu-select`.

Nothing fires on frame changes: a sound tied to a frame (a footstep) watches the frame index
change, as the harpy's flap watches its bob.
