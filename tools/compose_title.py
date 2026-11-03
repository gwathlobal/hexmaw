#!/usr/bin/env python3
"""Compose the main menu's loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_title.py audio/music/title data/music/title.ogg

The piece is written out below as notes: 32 bars of 4/4 in C minor at 0.8 s a beat (75 BPM),
in four 8-bar sections over a harp's arpeggio and a contrabass: a horn theme over soft
strings; a choir taking the melody, with timpani; the theme again on brass over an organ and
full strings, a reverse cymbal swelling into it; and a solo cello, quiet, over the harp. The
chords are C minor's (i, iv, bVI, bVII, the major dominant G, and the Neapolitan Db), and the
last bar is G7, which runs on into the first bar's C minor.

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-14 LUFS, the
exploration loops' level) and encoded to OUT. --preview writes the join, --seed changes the
small velocity variations. 0.8 s a beat makes the loop 102.4 s, 4515840 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 800000  # 0.8 s a beat, 75 BPM
BARS = 32

# --- The piece ---------------------------------------------------------------------------

CHORDS = ("Cm Ab Fm G  Cm Eb Ab G "   # A: the horn's theme over soft strings
          "Ab Bb Eb Cm Fm Db G  G "   # B: the choir's melody, timpani
          "Cm Ab Bb Eb Fm Ab G  G "   # C: the theme on brass, organ, full strings
          "Cm Fm Ab G  Cm Ab Db G").split()  # D: a solo cello, quiet; G7 into the loop

# Melodies: per bar, (note, beat, beats long), beats counted from 1.
THEME = [
    [("G4", 1, 2), ("C5", 3, 1.5), ("Bb4", 4.5, .5)],
    [("Ab4", 1, 1.5), ("G4", 2.5, .5), ("Eb4", 3, 2)],
    [("F4", 1, 1), ("Ab4", 2, 1), ("C5", 3, 1.5), ("Bb4", 4.5, .5)],
    [("B4", 1, 2), ("D5", 3, 1), ("B4", 4, 1)],
    [("C5", 1, 1.5), ("D5", 2.5, .5), ("Eb5", 3, 1.5), ("D5", 4.5, .5)],
    [("Bb4", 1, 2), ("G4", 3, 2)],
    [("Ab4", 1, 1), ("C5", 2, 1), ("Eb5", 3, 1), ("C5", 4, 1)],
    [("B4", 1, 1), ("G4", 2, 1), ("D4", 3, 2)],
]
CHOIR = [
    [("C5", 1, 2), ("Eb5", 3, 2)],
    [("D5", 1, 2), ("F5", 3, 1), ("D5", 4, 1)],
    [("Eb5", 1, 3), ("Bb4", 4, 1)],
    [("C5", 1, 2), ("G4", 3, 2)],
    [("Ab4", 1, 2), ("C5", 3, 1), ("F5", 4, 1)],
    [("F5", 1, 2), ("Ab4", 3, 1), ("Db5", 4, 1)],
    [("D5", 1, 2), ("B4", 3, 2)],
    [("G4", 1, 4)],
]
BRASS = [
    [("G4", 1, 2), ("C5", 3, 1.5), ("Bb4", 4.5, .5)],
    [("Ab4", 1, 1.5), ("G4", 2.5, .5), ("Eb4", 3, 2)],
    [("F4", 1, 1), ("Bb4", 2, 1), ("D5", 3, 1.5), ("C5", 4.5, .5)],
    [("Bb4", 1, 2), ("G4", 3, 1), ("Eb4", 4, 1)],
    [("F4", 1, 1), ("Ab4", 2, 1), ("C5", 3, 1.5), ("Bb4", 4.5, .5)],
    [("Ab4", 1, 1), ("C5", 2, 1), ("Eb5", 3, 2)],
    [("D5", 1, 1.5), ("C5", 2.5, .5), ("B4", 3, 1), ("G4", 4, 1)],
    [("B4", 1, 2), ("D5", 3, 2)],
]
CELLO = [
    [("C4", 1, 1), ("Eb4", 2, 1), ("G4", 3, 2)],
    [("F4", 1, 1.5), ("Eb4", 2.5, .5), ("C4", 3, 2)],
    [("Ab3", 1, 1), ("C4", 2, 1), ("Eb4", 3, 1.5), ("D4", 4.5, .5)],
    [("D4", 1, 2), ("B3", 3, 2)],
    [("G3", 1, 1), ("C4", 2, 1), ("Eb4", 3, 1.5), ("F4", 4.5, .5)],
    [("Eb4", 1, 1), ("C4", 2, 1), ("Ab3", 3, 2)],
    [("F4", 1, 1.5), ("Eb4", 2.5, .5), ("Db4", 3, 2)],
    [("B3", 1, 1), ("D4", 2, 1), ("G4", 3, 1), ("F4", 4, 1)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "horn":     dict(channel=0, program=60, volume=100, pan=56, reverb=85),
    "choir":    dict(channel=1, program=53, volume=96, pan=64, reverb=100),
    "brass":    dict(channel=2, program=61, volume=92, pan=70, reverb=80),
    "trombone": dict(channel=3, program=57, volume=88, pan=58, reverb=80),
    "cello":    dict(channel=4, program=42, volume=100, pan=60, reverb=85),
    "harp":     dict(channel=5, program=46, volume=84, pan=40, reverb=85),
    "strings":  dict(channel=6, program=48, volume=64, pan=72, reverb=95),
    "basses":   dict(channel=7, program=43, volume=86, pan=64, reverb=70),
    "timpani":  dict(channel=8, program=47, volume=90, pan=64, reverb=80),
    "drums":    dict(channel=9, program=0, volume=80, pan=64, reverb=70),
    "organ":    dict(channel=10, program=19, volume=58, pan=64, reverb=100),
    "bell":     dict(channel=11, program=14, volume=60, pan=90, reverb=100),
    "swell":    dict(channel=12, program=119, volume=80, pan=64, reverb=60),
}
BASS_DRUM = 35


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, beat, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-5, 5)))
        notes.append((part, bar * 4 + beat - 1, length, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, beat, length in phrase:
            add(part, bar, beat, length * 0.95, pitch(name) + shift, velocity + (6 if beat == 1 else 0))

    for bar, chord in enumerate(CHORDS):
        section, i8 = bar // 8, bar % 8
        root, triad = chord_tones(chord)
        root = 36 + (root - 36) % 12  # C2 to B2

        # The melody.
        if section == 0:
            melody("horn", bar, THEME[i8], 92)
        elif section == 1:
            melody("choir", bar, CHOIR[i8], 90)
        elif section == 2:
            melody("brass", bar, BRASS[i8], 96)
            melody("trombone", bar, BRASS[i8], 80, shift=-12)
        else:
            melody("cello", bar, CELLO[i8], 90)

        # The harp's arpeggio in eighths, up and back: root, fifth, octave, tenth, octave,
        # fifth, root an octave up, fifth. Quieter under the cello.
        tones = [root + 12, root + 12 + triad[2], root + 24, root + 24 + triad[1],
                 root + 24, root + 12 + triad[2], root + 24, root + 12 + triad[2]]
        harp = 60 if section == 3 else 70
        for i, note in enumerate(tones):
            add("harp", bar, 1 + i * 0.5, 0.9, note, harp + (8 if i % 4 == 0 else 0))

        # Contrabasses on the root, half notes; the fifth on 3 in the brass section.
        add("basses", bar, 1, 1.9, root, 84)
        add("basses", bar, 3, 1.9, root + (7 if section == 2 else 0), 76)

        # Strings: soft under the horn and the cello, fuller under the choir and the brass.
        strings = {0: 52, 1: 66, 2: 80, 3: 48}[section]
        for t in triad:
            add("strings", bar, 1, 3.9, root + 24 + t - (12 if t == 7 else 0), strings)

        # The organ under the brass.
        if section == 2:
            for t in (0, *triad[1:]):
                add("organ", bar, 1, 3.9, root + 24 + t, 70)
            add("organ", bar, 1, 3.9, root + 12, 64)

        # Timpani: a stroke at each section's start, strokes on 1 and 3 under the choir and
        # the brass, and a roll into the next section.
        if i8 == 0 or section in (1, 2):
            add("timpani", bar, 1, 1.5, root, 96 if i8 == 0 else 76)
        if section == 2:
            add("timpani", bar, 3, 1.5, root + 7, 70)
            add("drums", bar, 1, 0.5, BASS_DRUM, 70)
        if i8 == 7 and section != 3:
            for i in range(8):
                add("timpani", bar, 3 + i * 0.25, 0.25, root, 50 + 6 * i)

        # A low bell at the start of the theme and of its return on brass.
        if i8 == 0 and section in (0, 2):
            add("bell", bar, 1, 4, root + 36, 64)

        # A reverse cymbal swelling across the choir's last bar into the brass.
        if bar == 15:
            add("swell", bar, 1, 4, 60, 96)
    return notes


if __name__ == "__main__":
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-14.0)
