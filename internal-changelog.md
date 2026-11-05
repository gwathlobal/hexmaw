# Internal changelog

Every change worth recording, internal ones included: an entry in the commit that earns it,
under `## Unreleased`, given its date and version when a release is cut. The changelog
players get is `CHANGELOG.md`, drafted from this one at each release and approved before it
ships ("Releases" in CLAUDE.md). The history before this file is in `git log`.

## Unreleased

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
