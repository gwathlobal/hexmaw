# Hexmaw

A first-person, real-time roguelike: Daggerfall's dungeons with Hexen's combat. Levels are
assembled from hand-made blocks, spells are built at a spellforge, a settlement waits partway
down, and a boss waits at the bottom. Written in Common Lisp on
[Trial](https://shirakumo.github.io/trial). Linux only for now.

## Running

You need SBCL. The project keeps its own Quicklisp in `.ql/` (not in the repository), with
the Shirakumo dist for Trial. To set it up once, with the two dist versions the game is
developed against:

```bash
curl -O https://beta.quicklisp.org/quicklisp.lisp
sbcl --non-interactive --no-userinit --load quicklisp.lisp --eval '(quicklisp-quickstart:install :path ".ql/" :dist-url "http://beta.quicklisp.org/dist/quicklisp/2026-01-01/distinfo.txt")' --eval '(ql-dist:install-dist "http://dist.shirakumo.org/shirakumo/2026.10.16-12.49.03/shirakumo.txt" :prompt nil)'
rm quicklisp.lisp
```

The first `./run.sh` then downloads the libraries.

Then start the game:

```bash
./run.sh
```

It opens the game on the main menu, plus an eval server on `127.0.0.1:7171` that `tools/hd`
uses to drive the running game.

## Building

```bash
./build.sh
```

This builds a standalone game into `dist/`, which runs without SBCL or the source tree. It
needs `patchelf`.

## Art and Git LFS

The source art under `art/`, the record of how every sprite and texture was made, is stored
in Git LFS. The game itself only needs `data/`, which is plain git. To clone without
downloading the pictures:

```bash
GIT_LFS_SKIP_SMUDGE=1 git clone <url>
```

Use `git lfs pull` later to fetch them.

## More

`CLAUDE.md` is the engineering reference: how the code is laid out, how assets are made,
and the conventions the work follows.
