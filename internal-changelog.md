# Internal changelog

Every change worth recording, internal ones included: an entry in the commit that earns it,
under `## Unreleased`, given its date and version when a release is cut. The changelog
players get is `CHANGELOG.md`, drafted from this one at each release and approved before it
ships ("Releases" in CLAUDE.md). The history before this file is in `git log`.

## Unreleased

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
