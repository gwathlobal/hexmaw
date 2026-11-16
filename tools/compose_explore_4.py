#!/usr/bin/env python3
"""Compose an exploration loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_explore_4.py audio/music/explore-4 data/music/explore-4.ogg

The piece is written out below as notes: 32 bars of 12/8 in F sharp minor, a dotted quarter
at 0.9 s (67 a minute, its eighths at 200), so it lilts where the other exploration loops walk
in 4/4. A harpsichord breaks the chords in eighths that never stop, over a plucked bass on the
beats; an English horn has the theme, a bassoon answers it low, a solo viola takes the middle
section over a celesta's figures, and the theme returns on the English horn with the viola
under it. A soft bass drum and a tambourine keep the pulse in the second and last sections.
The harmony is a lament: the bass falls F#, E, D, C# under the theme, G major is the
Neapolitan, and every phrase ends on C# major, the last into the loop's first bar. None of
the other tracks' instruments lead: no horn, clarinet, dulcimer, marimba, harp or hand drums.

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-14 LUFS, the
exploration loops' level) and encoded to OUT. --preview writes the join, --seed changes the
small velocity variations. 0.9 s a beat makes the loop 115.2 s, 5080320 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 900000  # a dotted quarter, 0.9 s
BARS = 32

# --- The piece ---------------------------------------------------------------------------

# One chord a bar, with its bass after a slash where that isn't the root.
CHORDS = ("F#m F#m/E D   C#  Bm G   C# C# "   # A: the English horn's theme
          "Bm  Bm/A  G   F#m D  G   C# C# "   # B: the bassoon answers
          "G   G     Bm  Bm  D  D   C# C# "   # C: the viola over the celesta
          "F#m F#m/E D   C#  Bm G   C# C#").split()  # A': the theme again, the viola under it

# Melodies: per bar, (note, eighth from 0 to 11, eighths long).
THEME = [
    [("C#4", 0, 3), ("F#4", 3, 2), ("G#4", 5, 1), ("A4", 6, 4), ("G#4", 10, 1), ("F#4", 11, 1)],
    [("A4", 0, 2), ("G#4", 2, 1), ("F#4", 3, 3), ("C#4", 6, 6)],
    [("D4", 0, 2), ("F#4", 2, 1), ("A4", 3, 3), ("B4", 6, 2), ("A4", 8, 1), ("F#4", 9, 3)],
    [("E#4", 0, 3), ("G#4", 3, 3), ("C#5", 6, 4), ("B4", 10, 1), ("A4", 11, 1)],
    [("B4", 0, 3), ("A4", 3, 2), ("G#4", 5, 1), ("F#4", 6, 3), ("D4", 9, 3)],
    [("G4", 0, 3), ("B4", 3, 3), ("D5", 6, 2), ("B4", 8, 1), ("G4", 9, 3)],
    [("G#4", 0, 2), ("E#4", 2, 1), ("G#4", 3, 3), ("B4", 6, 3), ("A4", 9, 1), ("G#4", 10, 1),
     ("E#4", 11, 1)],
    [("C#4", 0, 6)],
]
# The English horn's reply under the bassoon's last bar.
REPLY = {15: [("G#4", 6, 1), ("A4", 7, 1), ("G#4", 8, 1), ("E#4", 9, 3)]}
# Its pickup into the bassoon's first bar.
PICKUP = {7: [("G#3", 9, 1), ("A3", 10, 1), ("B3", 11, 1)]}
ANSWER = [  # the bassoon, low
    [("B3", 0, 3), ("A3", 3, 2), ("B3", 5, 1), ("D4", 6, 3), ("C#4", 9, 2), ("B3", 11, 1)],
    [("C#4", 0, 2), ("B3", 2, 1), ("A3", 3, 3), ("F#3", 6, 3), ("D3", 9, 3)],
    [("G3", 0, 3), ("B3", 3, 2), ("D4", 5, 1), ("E4", 6, 2), ("D4", 8, 1), ("B3", 9, 3)],
    [("C#4", 0, 3), ("A3", 3, 3), ("F#3", 6, 4), ("G#3", 10, 1), ("A3", 11, 1)],
    [("A3", 0, 2), ("B3", 2, 1), ("D4", 3, 3), ("F#4", 6, 3), ("E4", 9, 2), ("D4", 11, 1)],
    [("D4", 0, 3), ("B3", 3, 3), ("G3", 6, 2), ("A3", 8, 1), ("B3", 9, 3)],
    [("E#3", 0, 3), ("G#3", 3, 3), ("B3", 6, 3), ("C#4", 9, 2), ("D4", 11, 1)],
    [("C#4", 0, 6)],
]
VIOLA = [
    [("D4", 0, 6), ("B3", 6, 3), ("G4", 9, 3)],
    [("F#4", 0, 3), ("G4", 3, 3), ("A4", 6, 3), ("B4", 9, 3)],
    [("D5", 0, 6), ("C#5", 6, 3), ("B4", 9, 3)],
    [("A4", 0, 3), ("F#4", 3, 3), ("D4", 6, 6)],
    [("F#4", 0, 3), ("A4", 3, 3), ("D5", 6, 4), ("C#5", 10, 2)],
    [("B4", 0, 3), ("A4", 3, 3), ("F#4", 6, 3), ("E4", 9, 3)],
    [("E#4", 0, 6), ("G#4", 6, 6)],
    [("C#5", 0, 4), ("B4", 4, 1), ("A4", 5, 1), ("G#4", 6, 6)],
]
# The bassoon's short figures in the viola's long notes.
COUNTER = {
    16: [("G3", 6, 1), ("A3", 7, 1), ("B3", 8, 1)],
    18: [("F#3", 6, 1), ("E3", 7, 1), ("D3", 8, 1)],
    20: [("A3", 6, 1), ("B3", 7, 1), ("C#4", 8, 1)],
    22: [("G#3", 6, 1), ("A3", 7, 1), ("B3", 8, 1), ("C#4", 9, 3)],
}
THEME_END = [  # the theme's second half, turned toward the loop's return
    [("D5", 0, 3), ("C#5", 3, 2), ("B4", 5, 1), ("A4", 6, 3), ("F#4", 9, 3)],
    [("B4", 0, 3), ("A4", 3, 2), ("G4", 5, 1), ("D5", 6, 4), ("B4", 10, 2)],
    [("C#5", 0, 3), ("B4", 3, 2), ("G#4", 5, 1), ("E#4", 6, 3), ("G#4", 9, 3)],
    [("G#4", 0, 5), ("A4", 5, 1), ("G#4", 6, 3), ("E#4", 9, 3)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "cor":         dict(channel=0, program=69, volume=100, pan=58, reverb=80),
    "bassoon":     dict(channel=1, program=70, volume=104, pan=74, reverb=75),
    "viola":       dict(channel=2, program=41, volume=96, pan=50, reverb=85),
    "harpsichord": dict(channel=3, program=6, volume=72, pan=44, reverb=70),
    "celesta":     dict(channel=4, program=8, volume=62, pan=86, reverb=90),
    "bass":        dict(channel=5, program=45, volume=110, pan=64, reverb=55),
    "strings":     dict(channel=6, program=49, volume=50, pan=64, reverb=95),
    "drums":       dict(channel=9, program=0, volume=80, pan=64, reverb=60),
}
BASS_DRUM, TAMBOURINE, OPEN_TRIANGLE = 35, 54, 81


def parse(chord):
    """A chord such as "F#m/E" as its root in the bass's octave, its triad, and its bass."""
    name, _, bass = chord.partition("/")
    root, triad = chord_tones(name)
    root = 40 + (root - 40) % 12  # E2 to D#3
    low = 40 + (pitch(bass + "2") - 40) % 12 if bass else root
    return root, triad, low


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, eighth, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-6, 6)))
        notes.append((part, bar * 4 + eighth / 3, length / 3, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, eighth, length in phrase:
            accent = 8 if eighth == 0 else 4 if eighth % 3 == 0 else 0
            add(part, bar, eighth, length * 0.94, pitch(name) + shift, velocity + accent)

    for bar, chord in enumerate(CHORDS):
        section = bar // 8
        root, triad, low = parse(chord)
        _, _, next_low = parse(CHORDS[(bar + 1) % BARS])

        # The melody.
        if section == 0:
            melody("cor", bar, THEME[bar], 86)
            melody("bassoon", bar, PICKUP.get(bar, []), 74)
        elif section == 1:
            melody("bassoon", bar, ANSWER[bar - 8], 92)
            melody("cor", bar, REPLY.get(bar, []), 76)
        elif section == 2:
            melody("viola", bar, VIOLA[bar - 16], 86)
            melody("bassoon", bar, COUNTER.get(bar, []), 72)
        else:
            phrase = THEME[bar - 24] if bar < 28 else THEME_END[bar - 28]
            melody("cor", bar, phrase, 86)
            melody("viola", bar, phrase, 66, shift=-12)  # under it, an octave down

        # The harpsichord breaks the chord in eighths, up and down over an octave and a half:
        # root, fifth, octave, tenth, octave, fifth, then root, fifth, octave, twelfth, tenth,
        # octave. Thinner (every other eighth louder) under the viola.
        tones = [root + 12 + t for t in triad] + [root + 24 + t for t in triad]
        for i, k in enumerate((0, 2, 3, 4, 3, 2, 0, 2, 3, 5, 4, 3)):
            v = (70, 50, 54)[i % 3] - (8 if section == 2 else 0)
            add("harpsichord", bar, i, 0.9, tones[k], v)

        # The bass, plucked: the bass note on 1 and 3, its fifth on 2, and on 4 a step
        # toward the next bar's bass (or its octave when that is the same note).
        add("bass", bar, 0, 2.5, low, 104)
        add("bass", bar, 3, 2, low + 7 if low + 7 < 58 else low - 5, 82)
        add("bass", bar, 6, 2.5, low, 94)
        if next_low == low:
            step = low + 12
        else:
            step = next_low + (1 if next_low < low else -1)
            step = step if abs(step - low) <= 5 else next_low - 2
        add("bass", bar, 9, 2, step, 84)

        # Soft strings hold the chord under the bassoon and the return.
        if section in (1, 3):
            for t in triad:
                add("strings", bar, 0, 11.6, root + 12 + t, 58)

        # The celesta's figures in the middle section: the triad rising in the second half
        # of each beat after the first, high.
        if section == 2:
            high = [root + 36 + t for t in triad]
            for eighth in (4, 7, 10):
                for j, note in enumerate(high[:2] if eighth == 4 else high):
                    add("celesta", bar, eighth + j * 0.5, 0.5, note, 56 - 4 * j)

        # The pulse: a soft bass drum on 1 and 3, the tambourine on the last eighth of each
        # beat, in the second and last sections; a triangle at each section's start.
        if section in (1, 3):
            add("drums", bar, 0, 1, BASS_DRUM, 70)
            add("drums", bar, 6, 1, BASS_DRUM, 60)
            for eighth in (2, 5, 8, 11):
                add("drums", bar, eighth, 0.5, TAMBOURINE, 44 if eighth in (5, 11) else 34)
        if bar % 8 == 0:
            add("drums", bar, 0, 3, OPEN_TRIANGLE, 52)
    return notes


if __name__ == "__main__":
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-14.0)
