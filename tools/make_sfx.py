#!/usr/bin/env python3
"""Turn the chosen takes of the sound effects into what the game plays.

  tools/make_sfx.py            every clip that has takes
  tools/make_sfx.py imp-pain   just these

The clips, and which are positional (P) or loops (L), come from audio/sfx.md's tables. A
clip's takes are audio/sfx/<clip>-<n>.wav (or <clip>.wav for a single one), as
tools/gen_sfx.py writes them. audio/sfx-picks.txt says which to use, one line a clip:

  imp-pain 2              take 2
  player-hurt 1 2 4       three variants, played in turn
  ogre-alert 3 gain=-4    take 3, 4 dB quieter than the rest
  tornado 4 even          take 4 with its slow swells evened out (EVEN_OUT): a steady loop

A clip with takes and no line uses take 1, so every generated clip is in the game until it
is chosen. Each take is trimmed of the silence before and after it (not a loop's: it is cut
to join), faded out over its last 10 ms, brought to one loudness (--level, the loudest
100 ms window's RMS in dBFS, -14 by default, then its gain=), its peaks held under -1 dBFS by
make_loop.py's look-ahead limiter (round the circle for a loop), downmixed to mono if it is
positional (Harmony's :effect mixer is a space mixer and takes only mono), and encoded through
GStreamer to Ogg Vorbis: data/sfx/<clip>.ogg, or <clip>-1.ogg, <clip>-2.ogg ... for variants.

data/sfx/index.lisp lists what was made, one plist a clip, which src/sound.lisp reads:

  (:name "imp-pain" :files ("imp-pain.ogg") :seconds (0.52) :space T :loop NIL)

A run rewrites the index with every clip made so far (it reads the old one), so converting
one clip keeps the rest; a clip no longer in the table leaves it, and its files go. --check only says which clips have takes and what would be used.
"""

import argparse
import re
import subprocess
import sys
import tempfile
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
from make_loop import limit, ogg_length  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "audio/sfx.md"
PICKS = ROOT / "audio/sfx-picks.txt"
TAKES = ROOT / "audio/sfx"
OUT = ROOT / "data/sfx"
INDEX = OUT / "index.lisp"

CEILING = 10 ** (-1 / 20)


def read_table():
    """{clip: (positional, loop)} from audio/sfx.md's rows."""
    clips = {}
    for line in TABLE.read_text().splitlines():
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 6 and re.fullmatch(r"[a-z0-9-]+", cells[0]) and cells[1].isdigit():
            pos = cells[2].split()
            clips[cells[0]] = (pos[0] == "P", "L" in pos[1:])
    return clips


def read_picks():
    """{clip: ([takes], gain dB, even)} from audio/sfx-picks.txt."""
    picks = {}
    if not PICKS.exists():
        return picks
    for n, line in enumerate(PICKS.read_text().splitlines(), 1):
        words = line.split("#")[0].split()
        if not words:
            continue
        takes, gain, even = [], 0.0, False
        for w in words[1:]:
            if w.startswith("gain="):
                gain = float(w[5:])
            elif w == "even":
                even = True
            elif w.isdigit():
                takes.append(int(w))
            else:
                sys.exit(f"{PICKS}:{n}: what is {w!r}?")
        picks[words[0]] = (takes or [1], gain, even)
    return picks


def take_path(clip, n):
    many = TAKES / f"{clip}-{n}.wav"
    if many.exists():
        return many
    one = TAKES / f"{clip}.wav"
    return one if n == 1 and one.exists() else None


def read_wav(path):
    with wave.open(str(path)) as w:
        channels, rate = w.getnchannels(), w.getframerate()
        if w.getsampwidth() != 2:
            sys.exit(f"{path}: need 16-bit PCM")
        data = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    return data.reshape(-1, channels).astype(np.float64) / 32768, rate


def write_wav(path, x, rate):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def trim(x, rate, start_db=-45, end_db=-50, pad=0.005):
    """X without the near-silence before and after it, PAD seconds kept either side."""
    level = np.abs(x).max(1)
    on = np.nonzero(level > 10 ** (start_db / 20))[0]
    if not len(on):
        return x
    first = max(0, on[0] - int(pad * rate))
    tail = np.nonzero(level > 10 ** (end_db / 20))[0]
    last = min(len(x), tail[-1] + int(pad * rate) + 1)
    return x[first:last]


def loudest(x, rate, window=0.1):
    """The RMS of X's loudest WINDOW seconds, in dBFS."""
    w = max(1, min(len(x), int(window * rate)))
    power = (x ** 2).mean(1)
    sums = np.concatenate([[0.0], np.cumsum(power)])
    return 10 * np.log10((sums[w:] - sums[:-w]).max() / w + 1e-12)


def even_out(x, rate, loop, window=0.4, most=12.0):
    """X with its slow swells taken out: its loudness, smoothed over WINDOW seconds (round the
    circle for a loop), brought to its median by at most MOST dB either way. A wind loop that
    rises and falls within itself then roars steadily."""
    hop = max(1, int(0.01 * rate))
    n = len(x) // hop
    blocks = (x[:n * hop] ** 2).mean(1).reshape(n, hop).mean(1)
    k = max(1, int(window / 0.01))
    kernel = np.hanning(k + 2)[1:-1]
    kernel /= kernel.sum()
    if loop:
        padded = np.concatenate([blocks[-k:], blocks, blocks[:k]])
        smooth = np.convolve(padded, kernel, "same")[k:-k]
    else:
        smooth = np.convolve(blocks, kernel, "same")
    level = np.sqrt(np.maximum(smooth, 1e-12))
    gain = np.clip(np.median(level) / level, 10 ** (-most / 20), 10 ** (most / 20))
    centres = (np.arange(n) + 0.5) * hop
    at = np.arange(len(x))
    if loop:
        gain = np.interp(at, centres, gain, period=len(x))
    else:
        gain = np.interp(at, centres, gain)
    return x * gain[:, None]


def make_clip(path, positional, loop, level, gain, even=False):
    x, rate = read_wav(path)
    if not loop:
        x = trim(x, rate)
        fade = min(len(x), int(0.01 * rate))
        x[-fade:] *= np.linspace(1, 0, fade)[:, None]
    if positional and x.shape[1] > 1:
        x = x.mean(1, keepdims=True)
    if even:
        x = even_out(x, rate, loop)
    x = x * 10 ** ((level + gain - loudest(x, rate)) / 20)
    if loop:
        x, _ = limit(x, rate, CEILING)
    else:
        # The limiter treats X as a circle; pad it with silence so the end doesn't pull
        # the start down.
        pad = int(0.02 * rate)
        y = np.concatenate([np.zeros((pad, x.shape[1])), x, np.zeros((pad, x.shape[1]))])
        x = limit(y, rate, CEILING)[0][pad:-pad]
    return x, rate


def encode(x, rate, out, quality=0.5):
    with tempfile.TemporaryDirectory() as tmp:
        wav = Path(tmp) / "clip.wav"
        write_wav(wav, x, rate)
        subprocess.run(["gst-launch-1.0", "-q", "filesrc", f"location={wav}", "!", "wavparse",
                        "!", "audioconvert", "!", "vorbisenc", f"quality={quality}", "!",
                        "oggmux", "!", "filesink", f"location={out}"], check=True)
    frames = ogg_length(out)
    if frames != len(x):
        sys.exit(f"{out} holds {frames} frames, not {len(x)}")


def read_index():
    """{clip: line} from an earlier run's index."""
    if not INDEX.exists():
        return {}
    return {m.group(1): line for line in INDEX.read_text().splitlines()
            if (m := re.match(r'\(:name "([^"]+)"', line))}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("clips", nargs="*", help="clips to convert (default: every one with takes)")
    ap.add_argument("--level", type=float, default=-14.0,
                    help="RMS of the loudest 100 ms, dBFS (default -14)")
    ap.add_argument("--check", action="store_true", help="say what would be made, make nothing")
    args = ap.parse_args()

    table, picks = read_table(), read_picks()
    for clip in list(args.clips) + list(picks):
        if clip not in table:
            sys.exit(f"{clip}: not in {TABLE}")
    for clip, (takes, _, _) in picks.items():
        for n in takes:
            if not take_path(clip, n):
                sys.exit(f"{clip}: no take {n} in {TAKES}")
    wanted = args.clips or [c for c in table if take_path(c, 1)]

    index = read_index()
    if not args.check:
        for clip in [c for c in index if c not in table]:
            for old in OUT.glob(f"{clip}*.ogg"):
                if re.fullmatch(rf"{re.escape(clip)}(-\d+)?\.ogg", old.name):
                    old.unlink()
            del index[clip]
            print(f"{clip}: no longer in {TABLE.name}, removed")
    OUT.mkdir(parents=True, exist_ok=True)
    for clip in wanted:
        positional, loop = table[clip]
        takes, gain, even = picks.get(clip, ([1], 0.0, False))
        paths = [take_path(clip, n) for n in takes]
        if None in paths:
            print(f"{clip}: no takes", file=sys.stderr)
            continue
        kind = ("positional" if positional else "first-person") + (", loop" if loop else "") + (", evened" if even else "")
        if args.check:
            print(f"{clip}: takes {' '.join(map(str, takes))}, {kind}")
            continue
        for old in OUT.glob(f"{clip}*.ogg"):
            if re.fullmatch(rf"{re.escape(clip)}(-\d+)?\.ogg", old.name):
                old.unlink()
        files, seconds = [], []
        for i, path in enumerate(paths, 1):
            name = f"{clip}.ogg" if len(paths) == 1 else f"{clip}-{i}.ogg"
            x, rate = make_clip(path, positional, loop, args.level, gain, even)
            encode(x, rate, OUT / name)
            files.append(name)
            seconds.append(round(len(x) / rate, 3))
        print(f"{clip}: {', '.join(files)} ({kind}; {', '.join(f'{s:.2f} s' for s in seconds)})")
        index[clip] = (f'(:name "{clip}" :files ({" ".join(f"{chr(34)}{f}{chr(34)}" for f in files)})'
                       f' :seconds ({" ".join(map(str, seconds))})'
                       f' :space {"T" if positional else "NIL"} :loop {"T" if loop else "NIL"})')
    if not args.check:
        INDEX.write_text(";;; Written by tools/make_sfx.py: the sound effects in this folder.\n"
                         + "\n".join(index[c] for c in sorted(index)) + "\n")


if __name__ == "__main__":
    main()
