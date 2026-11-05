# Generative AI in Hexmaw

Hexmaw is an experiment in making a game with generative AI doing as much of the work as it can.
Here is what was made how.

- **Pictures.** Every monster, texture, splash screen, pickup, effect and townsperson, the torch,
  the gate, and the sword, shield and spear in hand were generated with OpenAI's image models,
  through the Codex CLI on a ChatGPT plan and through the OpenAI Image API (`tools/gen_image.py`).
  The scripts in `tools/` then cut, scale and palette them into the strips in `data/sprites/` and
  `data/textures/`. Some sprites are drawn by code instead: the blood, the glyph tablets, the item,
  weapon and status icons, the gold, and the spell signs and sigils. The sword's poses were
  rendered from a Blender model built by script.
- **Sound effects.** Generated with ElevenLabs on a paid plan (`tools/gen_sfx.py`), then trimmed
  and levelled by `tools/make_sfx.py`.
- **Music.** Seven tracks were generated with ElevenLabs on a paid plan (`tools/gen_music.py`)
  and looped by `tools/make_loop.py`. Three (the title theme, `explore-2` and `combat-5`) were
  composed as code (`tools/compose_*.py`) and rendered through FluidSynth with a General MIDI
  soundfont.
- **Code and text.** Written with coding agents (Claude Code), directed and reviewed by the
  author. `CLAUDE.md` holds the instructions they work from.
- **Levels.** Assembled at run time from blocks drawn as text blueprints (`data/blueprints/`).

**The records.** Every generated picture and sound has a `.prompt.json` beside it, with its
prompt, its references and its options. The prompts are in `art/prompts/` and `audio/prompts/`.
The generated source pictures under `art/` are kept privately for now, so a clone has them as
pointer files only. What the game uses is all in `data/`.

**Copyright.** In the US, material generated from prompts alone has no author, and so probably no
copyright; other countries differ. `ASSETS-LICENSE.md` claims rights in the assets to the extent
they exist, and in full for what people made.
