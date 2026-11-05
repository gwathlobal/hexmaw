"""Shared machinery for music composed as notes (tools/compose_explore.py, compose_combat.py).

A piece is a function from a random state to its notes, (part, beat from 0, beats long, MIDI
note, velocity), its parts (General MIDI program and channel settings), its length in bars of
4/4 and its beat in microseconds. RUN writes it as a format 1 MIDI file played twice in a row,
renders that through GStreamer's FluidSynth element and a GM soundfont (FluidR3_GM, MIT, from
Debian's fluid-soundfont-gm), and keeps the second pass as the loop: it opens with the
first pass's reverb and release tails, just what the loop's own end leaves sounding, so it
joins without a crossfade. The beat must make the loop a whole number of samples and of
FluidSynth's 64-sample blocks (0.75 s or 0.5 s a beat with 32 bars, say), so both passes are
timed alike; RUN checks that they line up. Then, as tools/make_loop.py does, the loop is brought
to its loudness and written to <stem>-loop.wav and an Ogg checked to hold its own length.
"""

import argparse
import random
import struct
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).parent))
from make_loop import encode_loop, set_level, write_join  # noqa: E402

PPQ = 480
RATE = 44100
SOUNDFONT = "/usr/share/sounds/sf2/FluidR3_GM.sf2"

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}
TRIADS = {"m": (0, 3, 7), "": (0, 4, 7)}


def pitch(name):
    """MIDI note of a name such as "C#4" or "Bb3" (C4 = 60)."""
    n = NOTE[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        n += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return n + 12 * (int(rest) + 1)


def chord_tones(chord, octave=2):
    """A chord such as "Dm" or "Bb" as its root in OCTAVE and its triad's intervals."""
    root = chord.rstrip("m")
    return pitch(root + str(octave)), TRIADS["m" if chord.endswith("m") else ""]


def vlq(n):
    out = [n & 0x7F]
    n >>= 7
    while n:
        out.append(0x80 | (n & 0x7F))
        n >>= 7
    return bytes(reversed(out))


def track(events):
    """A track chunk from (tick, bytes) events, sorted, note-offs before note-ons at a tick."""
    data = bytearray()
    now = 0
    for tick, msg in sorted(events, key=lambda e: (e[0], e[1][0] & 0xF0 != 0x80)):
        data += vlq(tick - now) + msg
        now = tick
    data += vlq(0) + b"\xFF\x2F\x00"
    return b"MTrk" + struct.pack(">I", len(data)) + bytes(data)


def write_midi(path, notes, parts, bars, beat_us, passes, tail_beats):
    """A format 1 file playing NOTES PASSES times in a row, then TAIL_BEATS of silence."""
    loop = bars * 4 * PPQ
    tempo = [(0, b"\xFF\x51\x03" + beat_us.to_bytes(3, "big")),
             (0, b"\xFF\x58\x04\x04\x02\x18\x08"),
             (passes * loop + tail_beats * PPQ, b"\xFF\x01\x01 ")]  # holds the end open
    tracks = [track(tempo)]
    for name, part in parts.items():
        ch = part["channel"]
        events = [(0, bytes([0xC0 | ch, part["program"]])),
                  (0, bytes([0xB0 | ch, 7, part["volume"]])),
                  (0, bytes([0xB0 | ch, 10, part["pan"]])),
                  (0, bytes([0xB0 | ch, 91, part["reverb"]])),
                  (0, bytes([0xB0 | ch, 93, 0]))]
        for p in range(passes):
            for who, beat, length, note, velocity in notes:
                if who != name:
                    continue
                on = p * loop + round(beat * PPQ)
                off = on + max(1, round(length * PPQ))
                events += [(on, bytes([0x90 | ch, note, velocity])), (off, bytes([0x80 | ch, note, 0]))]
        tracks.append(track(events))
    header = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks), PPQ)
    Path(path).write_bytes(header + b"".join(tracks))


def render(midi, wav, soundfont, gain):
    """MIDI through FluidSynth at GAIN, which a dense piece needs low enough not to clip: the
    synth clips at full scale before anything after it can catch a peak."""
    subprocess.run(["gst-launch-1.0", "-q", "filesrc", f"location={midi}", "!", "midiparse", "!",
                    "fluiddec", f"soundfont={soundfont}", f"synth-gain={gain}", "synth-reverb=true",
                    "synth-chorus=false", "!", "audioconvert", "dithering=none", "!",
                    "audioresample", "!", f"audio/x-raw,format=S16LE,rate={RATE},channels=2", "!",
                    "wavenc", "!", "filesink", f"location={wav}"], check=True)
    with wave.open(str(wav)) as w:
        data = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    return data.reshape(-1, 2).astype(np.float64) / 32768


def passes_match(audio, period):
    """How alike the two passes are past their first seconds: the correlation of a stretch of
    the second with the same stretch of the first, which should be 1."""
    k, n = 5 * RATE, 8192
    a, b = audio[k:k + n].mean(1), audio[period + k:period + k + n].mean(1)
    return float(np.dot(a, b) / (np.linalg.norm(a) * np.linalg.norm(b) + 1e-12))


def run(doc, compose, parts, bars, beat_us, loudness, gain=0.8):
    ap = argparse.ArgumentParser(description=doc, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("stem", type=Path, help="where the .mid, the render and the loop .wav go")
    ap.add_argument("out", type=Path, help="the game's loop, .ogg")
    ap.add_argument("--soundfont", default=SOUNDFONT)
    ap.add_argument("--loudness", type=float, default=loudness)
    ap.add_argument("--seed", type=int, default=1, help="for the small velocity variations")
    ap.add_argument("--preview", type=Path, help="write the join, 8 s either side, here")
    args = ap.parse_args()

    period, rest = divmod(bars * 4 * beat_us * RATE, 1_000_000)
    if rest or period % 64:
        sys.exit(f"{bars} bars at {beat_us} us a beat isn't a whole number of 64-sample blocks")
    notes = compose(random.Random(args.seed))
    stem = args.stem
    stem.parent.mkdir(parents=True, exist_ok=True)
    midi = stem.with_suffix(".mid")
    write_midi(midi, notes, parts, bars, beat_us, passes=2, tail_beats=8)
    audio = render(midi, stem.with_name(f"{stem.name}-render.wav"), args.soundfont, gain)
    clipped = int((np.abs(audio) >= 32767 / 32768).sum())
    if clipped:
        print(f"warning: {clipped} samples clip in the render; lower the piece's gain ({gain})")
    if len(audio) < 2 * period:
        sys.exit(f"the render is {len(audio)} frames, short of two passes ({2 * period})")
    print(f"{len(notes)} notes, {bars} bars, loop {period / RATE:.1f} s; "
          f"the passes correlate {passes_match(audio, period):.4f}")
    loop = set_level(audio[period:2 * period].copy(), RATE, args.loudness)
    wav = stem.with_name(f"{stem.name}-loop.wav")
    loop, frames = encode_loop(loop, RATE, wav, args.out)
    if args.preview:
        write_join(args.preview, loop, RATE)
    print(f"{wav}; {args.out}: {args.out.stat().st_size / 1e6:.1f} MB, holds the same {frames} frames")
