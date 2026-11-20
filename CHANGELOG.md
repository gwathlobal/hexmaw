# Changelog

What changed in each version, for players. A version's entry is written when it is
released; the first one comes with the first public build.

## November 21, 2026 v0.1.2

- Saves from 0.1.1 still load, but loading a save on a generated level restarts that level. The new rooms and monsters change what each seed generates.
- Added the rime hag. She throws frost shards, freezes the floor ahead of you and releases a frost nova when you get close. On the last level, she also summons a blizzard that deflects your projectiles and slows you.
- Added the arc votary, found from the second level onward. It fires a sustained lightning beam, electrifying the floor and any water around the impact. It turns slowly while firing, so circle it or break its line of sight. On the last level, damage it takes builds towards a shock burst.
- Added the bloodroot on the last level. It stays in place while its roots spread across floors and walls, draining and snaring you. Spilt blood heals it. Fire and frost stop the roots, and any attack breaks you free.
- Killing a monster whose element you haven't learnt now drops that element's glyph.
- From the second level onward, acolytes summon a firestorm that follows you. Absorbing their fire makes them cast it sooner.
- From the second level onward, knights charge behind their shields. Dodge the charge to make them crash into a wall, leaving them open to attack, or brace your spear to stop them.
- From the second level onward, imps in packs leap past or over you to attack from the side or behind.
- Added stained-glass windows that shatter when hit by attacks or shockwaves. Some hide rewards. Added three rooms with these windows: a chapel, an outpost and a treasury. The town's temple and barracks are now buildings with windows.
- Aiming at an elite now shows its name, health and an explanation of its glow.
- Missed melee attacks now hit walls, throwing sparks, dust or splinters.
- Fixed the town trainer's movement, combat, flinch and death animations after the town is sacked.
- Fixed the thumb placement on the fire spell casting hands and oversized pixels on distant lightning effects.
- Fixed Quicksave and Quickload failing when bound to mouse buttons.
- Fixed shop buttons sometimes buying or selling the wrong potion.
- Fixed quickloading during a weapon switch or swing sometimes leaving the wrong weapon in hand.
- Fixed absorbed projectiles restoring the wrong amount of mana after a quickload.

## November 16, 2026 v0.1.1

- Saves from 0.1.0 still load, but a save on a generated level starts that level over: the new level pieces change what each seed builds.
- Spells now cost by their strength: weak ones are free (the starting Fire Bolt among them), stronger ones cost stamina, and the strongest, and every heal, cost mana. The Spellforge shows what a spell costs and why.
- Hold a stamina or mana attack spell to overcharge it. A full charge breaks through a shield and always staggers.
- New spell: Absorb Projectiles. You start with it, and while you hold it, enemy projectiles are turned into mana.
- Every rune slot on the hotbar can hold a second rune, cast with the right button.
- New at the Spellforge: Seeker, Beam and Nova spells.
- The casting hands are steel gauntlets now, and heal, ward and Absorb show their own magic instead of fire.
- A new weapon, the maul: hold the left button to charge a blow, and the right button slams the floor.
- The spear's thrust skewers a pouncing imp, a leaping ogre or a diving harpy, and the right button sweeps the haft.
- Blows on steel and stone throw sparks and grit, and embers rise from torches and lava.
- Heavy blows shake the view; Settings → Screen shake turns it off.
- Monsters fight the town's guards and townsfolk with everything they have. Monsters leave each other alone unless one keeps hitting another of a different kind: three blows within 12 seconds and the one struck fights back.
- New places: creeks (cave rivers of water, with fords and waterfalls), frozen rivers in the ice caves, and a new ice cave.
- A monster knocked across ice slides into the wall and is hurt.
- Four new music tracks: two more for exploring (five in all) and two more for fights (seven in all).
- The art shares one palette, and effects, the hands and the HUD keep the monsters' pixel size.
- Far fewer potions, and every level has gold and arcane dust. Gold is an item in the bag.
- The Spellforge greys out Make and says in red why, when you lack the dust or the spell can't be made.
- Area spells burst in a ball and no longer hit through floors and ceilings.
- Spells and other effects no longer tip over when you look up or down.
- The town's way down is lit and marked on the map, and a besieged town's "hold the gates" quest can always be finished.
- You can climb out of water onto a ledge just under the surface.
- Fixed: falling out of the world beside a slanted wall or after a jump, a gap beside the frost shrine's dais, the game seeming to freeze after a quickload in town, the mouse cursor flickering over menu buttons, and a sleeping boss's hum heard across its level.

## November 6, 2026 v0.1.0

The first public build, for playtesting: a first-person, real-time dungeon crawl.

- A run is four generated levels, one of them a town, ending in a boss's arena. Die and the run is over.
- Fight with sword and shield (raise it to block, click to bash) and cast spells: the fire bolt and heal to start. More weapons and spells are found as loot.
- Nine kinds of monsters, from imps that pounce and steal your potions to an ogre that leaps across the room. Deeper levels have tougher ones, and glowing elites.
- Spellforge altars: make your own spells and enchant your weapons with arcane dust. Glyphs you find teach new elements and effects.
- The town has a shop, a priest, a trainer and a quest. Its watch keeps the rules of whoever holds it.
- Lava, ice, deep water to swim through, tornadoes, blood and gibs.
- An automap (M), three save slots and a quicksave (F5, F9).
- Settings: fullscreen, render scale (draws the world at a lower resolution, for slow computers and machines with no 3D graphics), mouse sensitivity, music and sound volume, and rebindable keys.
- Windows, Linux and macOS (Apple silicon) builds. Every build needs OpenGL 3.3. The Mac build is completely untested.
