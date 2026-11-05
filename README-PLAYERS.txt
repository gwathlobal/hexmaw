HEXMAW

A first-person, real-time roguelike: Daggerfall's dungeons with Hexen's combat. Every run
is a new dungeon built from hand-made pieces, a few floors deep, with a settlement partway
down and a boss at the bottom. You fight with sword, spear and shield and spells you make
yourself at a spellforge.

This is a free prototype. Much of it, the art, the sounds and most of the music, was made
with generative AI; the game's page says what and how. Expect rough edges, and please tell
us about them (see TELLING US HOW IT WENT below).


RUNNING THE GAME

You need a graphics card and drivers with OpenGL 3.3, which anything from the last ten
years has.

Windows
  Unzip the archive and run hexmaw.exe. Everything it needs is in the folder. The game is
  not code-signed, so Windows may say it "protected your PC": click "More info" and then
  "Run anyway".

Linux
  Unpack the archive and run ./hexmaw. Everything it needs is in the folder; sound goes
  through PulseAudio or PipeWire, whichever your system has.

macOS (Apple silicon)
  Unpack the archive. The game is not signed, so macOS refuses to open it until you clear
  its quarantine once, from a terminal in the game's folder:
      xattr -dr com.apple.quarantine Hexmaw.app
  Then open Hexmaw.app. Nobody has played it through on a Mac yet.

Keep the files beside the program together. If the game will not start, run it from a
terminal in its folder with "check": it checks that its files and libraries are all there
and names anything missing.
    hexmaw.exe check                            (Windows)
    ./hexmaw check                              (Linux)
    ./Hexmaw.app/Contents/MacOS/Hexmaw check    (macOS)
If it finds everything and the game still will not open, "selftest" opens the window,
starts a game, takes a screenshot and closes again by itself, saying whether all of that
worked. Both also save their answer, as check.txt and selftest.txt, in the game's folder
for your files (see WHERE THINGS GO).


PLAYING

Click the window to take the mouse. Esc pauses and lets the mouse go; Esc again goes back.

  W A S D            move              Shift      run
  Space              jump              C, Ctrl    crouch
  mouse              look              left click attack: swing, thrust, or cast the spell
                                                  in hand
  right button held  raise the shield (with the sword); left click with it raised bashes
  1 to 9             take up what that key holds: at the start 1 is the sword, 2 the fire
                     bolt, 3 heal; whatever you find goes on the next free key
  Q                  drink the potion shown above the keys; the mouse wheel changes which
  I                  the inventory: drag a weapon or rune onto 1 to 9, or a potion onto Q
  M                  the map
  E                  talk to someone, or use the spellforge at an altar
  F5, F9             quicksave, quickload
  F12                screenshot

In water, W swims where you look, Space goes up and C or Ctrl down; swim into a ledge at
the surface to climb out. When you die, the run is over.


WHERE THINGS GO

Saves, screenshots, the log (trial.log) and the check and self-test reports go here, never
into the game's own folder:

  Windows        %LOCALAPPDATA%\hexmaw\
  Linux, macOS   ~/.local/share/hexmaw/


TELLING US HOW IT WENT

Anything you write helps. First, before you read the questions below, say how it played,
in your own words: what you liked, what got in the way, anything at all.

Then, if you would:
  1. Was fighting a single imp, with the sword and the fire bolt, fun on its own?
  2. Did you get lost? If you did, was it frustrating, or tense in a good way?
  3. If you played a second run: did its floors feel like different places from the first?
  4. Where did you hear about the game?

Bugs: say what happened and what you were doing. If the game crashed, send trial.log from
the folder above too.

Write a comment on the game's itch.io page, or open an issue at
https://github.com/gwathlobal/hexmaw/issues


THE OTHER FILES HERE

  EULA.txt                  what you may do with the game (play it, stream it, record
                            it) and what you may not
  CHANGELOG.md              what changed in each version
  THIRD-PARTY-NOTICES.txt   the libraries and fonts the game is built with, and their
                            licences
  licenses/                 the licence texts, and the source of the LGPL libraries

Hexmaw is copyright (c) 2026 Vadim Murin.
https://github.com/gwathlobal/hexmaw
