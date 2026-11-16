#!/usr/bin/env python3
"""Compose a combat loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_combat_6.py audio/music/combat-6 data/music/combat-6.ogg

The piece is written out below as notes: 64 bars of 7/8, grouped 2 + 2 + 3, an eighth at 0.18 s
(a quarter at 167 a minute), in C sharp Phrygian dominant (C# D E# F# G# A B, the fifth mode of
F sharp harmonic minor), a war dance where the other combat loops march in 4/4 minor. A bassoon,
contrabasses and pizzicato strings play a riff in the mode on every eighth, a tuba and trombones
stamp the three accents, and hand drums (low and high congas, bongos), a bass drum, melodic toms
and a tambourine keep the 2 + 2 + 3. An oboe with a shanai over it has the theme, strings in
octaves the second, trombones the third over a choir chanting on the accents, and the theme
comes back a step higher. Its chords are the mode's own: C# major, D major (the bII), F# minor,
B minor; every phrase ends on C#. Its four 8-bar sections come twice, the second time scored
anew: the theme on a muted trumpet over the oboe an octave down, the strings' tune with the choir
holding chords, the chant over tom eighths, and a crash every two bars into the return.

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-11 LUFS, the combat
loops' level) and encoded to OUT. --preview writes the join, --seed changes the small velocity
variations. 0.18 s an eighth makes the loop 80.64 s, 3556224 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import pitch, run  # noqa: E402

BEAT_US = 180000  # an eighth, 0.18 s
BEATS = 7  # eighths a bar
BARS = 64

# --- The piece ---------------------------------------------------------------------------

# The mode, in semitones above C#, and each chord as (degree, minor).
MODE = (0, 1, 4, 5, 7, 8, 10)
CHORD = {"C#": (0, False), "D": (1, False), "F#m": (3, True), "Bm": (6, True)}
CHORDS = ("C# C# D  C#  C#  C# Bm C# "   # A: the riff, the theme on oboe and shanai
          "F#m F#m D D  Bm  Bm D  C# "   # B: the strings' tune in octaves
          "D  D  C# C#  Bm  Bm C# C# "   # C: trombones, the choir's chant
          "C# D  C# D   F#m D  C# C#").split() * 2  # D: the theme a step up
# Then the four again, scored anew.
TONIC = pitch("C#2")
ACCENTS = (0, 2, 4)  # 2 + 2 + 3

# Melodies: per bar, (note, eighth from 0 to 6, eighths long).
THEME = [
    [("G#4", 0, 2), ("A4", 2, 1), ("G#4", 3, 1), ("E#4", 4, 3)],
    [("E#4", 0, 2), ("F#4", 2, 2), ("G#4", 4, 2), ("A4", 6, 1)],
    [("A4", 0, 2), ("G#4", 2, 2), ("F#4", 4, 1), ("E#4", 5, 1), ("F#4", 6, 1)],
    [("E#4", 0, 2), ("D4", 2, 2), ("C#4", 4, 3)],
    [("C#5", 0, 2), ("B4", 2, 1), ("A4", 3, 1), ("G#4", 4, 3)],
    [("A4", 0, 1), ("B4", 1, 1), ("C#5", 2, 2), ("D5", 4, 2), ("C#5", 6, 1)],
    [("B4", 0, 2), ("A4", 2, 2), ("F#4", 4, 2), ("D4", 6, 1)],
    [("E#4", 0, 2), ("D4", 2, 1), ("E#4", 3, 1), ("C#4", 4, 3)],
]
TUNE = [
    [("C#5", 0, 4), ("A4", 4, 3)],
    [("F#4", 0, 2), ("G#4", 2, 2), ("A4", 4, 2), ("C#5", 6, 1)],
    [("D5", 0, 4), ("A4", 4, 3)],
    [("F#4", 0, 2), ("A4", 2, 2), ("D5", 4, 2), ("E#5", 6, 1)],
    [("F#5", 0, 4), ("D5", 4, 3)],
    [("C#5", 0, 2), ("B4", 2, 2), ("A4", 4, 2), ("F#4", 6, 1)],
    [("A4", 0, 2), ("F#4", 2, 2), ("D4", 4, 2), ("F#4", 6, 1)],
    [("E#4", 0, 2), ("G#4", 2, 2), ("C#5", 4, 3)],
]
LOW_LINE = [
    [("F#3", 0, 4), ("A3", 4, 3)],
    [("D4", 0, 7)],
    [("E#3", 0, 4), ("G#3", 4, 3)],
    [("C#4", 0, 7)],
    [("D4", 0, 4), ("C#4", 4, 3)],
    [("B3", 0, 7)],
    [("C#4", 0, 2), ("D4", 2, 2), ("E#4", 4, 3)],
    [("C#4", 0, 7)],
]
# The shanai's runs over the trombones' held notes.
RUN = [("C#5", 0, 1), ("D5", 1, 1), ("C#5", 2, 1), ("B4", 3, 1), ("A4", 4, 1), ("G#4", 5, 2)]
THEME_UP = [
    [("C#5", 0, 2), ("D5", 2, 2), ("C#5", 4, 3)],
    [("D5", 0, 2), ("E#5", 2, 2), ("F#5", 4, 2), ("E#5", 6, 1)],
    [("E#5", 0, 2), ("D5", 2, 1), ("C#5", 3, 1), ("G#4", 4, 3)],
    [("A4", 0, 2), ("B4", 2, 2), ("D5", 4, 3)],
    [("C#5", 0, 2), ("A4", 2, 2), ("F#4", 4, 2), ("G#4", 6, 1)],
    [("A4", 0, 2), ("F#4", 2, 1), ("A4", 3, 1), ("D5", 4, 3)],
    [("C#5", 0, 2), ("B4", 2, 1), ("A4", 3, 1), ("G#4", 4, 2), ("E#4", 6, 1)],
    [("D4", 0, 2), ("E#4", 2, 2), ("C#4", 4, 3)],
]
# The riffs in steps of the mode above the chord's root (7 is its octave).
RIFF = (0, 0, 1, 0, 2, 1, 0)
RIFF_2 = (0, 7, 0, 1, 0, 2, 1)

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "oboe":      dict(channel=0, program=68, volume=104, pan=60, reverb=50),
    "shanai":    dict(channel=1, program=111, volume=70, pan=68, reverb=50),
    "strings":   dict(channel=2, program=48, volume=96, pan=64, reverb=60),
    "trumpet":   dict(channel=3, program=59, volume=96, pan=72, reverb=50),
    "trombones": dict(channel=4, program=57, volume=100, pan=56, reverb=50),
    "tuba":      dict(channel=5, program=58, volume=104, pan=64, reverb=40),
    "bassoon":   dict(channel=6, program=70, volume=100, pan=44, reverb=40),
    "pizz":      dict(channel=7, program=45, volume=92, pan=84, reverb=45),
    "choir":     dict(channel=8, program=52, volume=88, pan=64, reverb=70),
    "drums":     dict(channel=9, program=0, volume=104, pan=64, reverb=40),
    "timpani":   dict(channel=10, program=47, volume=96, pan=64, reverb=50),
    "basses":    dict(channel=11, program=43, volume=96, pan=64, reverb=35),
    "toms":      dict(channel=12, program=117, volume=92, pan=64, reverb=45),
}
BASS_DRUM, TAMBOURINE, CRASH = 36, 54, 49
HIGH_BONGO, LOW_BONGO, MUTE_CONGA, LOW_CONGA = 60, 61, 62, 64


def note_at(degree):
    """The note DEGREE steps of the mode above C#2 (any number of steps, octaves included)."""
    octave, step = divmod(degree, 7)
    return TONIC + 12 * octave + MODE[step]


def triad(degree, minor):
    """The chord on DEGREE (which is minor or not) above C#3, built in thirds of the mode, with
    its third set to the quality asked for."""
    root = note_at(degree + 7)
    return [root, root + (3 if minor else 4), root + 7]


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, eighth, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-5, 5)))
        notes.append((part, bar * BEATS + eighth, length, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, eighth, length in phrase:
            add(part, bar, eighth, length * 0.9, pitch(name) + shift,
                velocity + (8 if eighth == 0 else 4 if eighth in ACCENTS else 0))

    for bar, chord in enumerate(CHORDS):
        section, i8, again = bar // 8 % 4, bar % 8, bar >= 32
        degree, minor = CHORD[chord]
        chord_notes = triad(degree, minor)
        root = note_at(degree)

        # The riff on every eighth: bassoon and contrabasses together, pizzicato an octave up.
        riff = RIFF_2 if section in (1, 3) else RIFF
        for i, step in enumerate(riff):
            v = 100 if i in ACCENTS else 78
            low = note_at(degree + step)
            add("bassoon", bar, i, 0.8, low + 12, v)
            add("basses", bar, i, 0.8, low, v - 6)
            add("pizz", bar, i, 0.6, low + (36 if again and section == 0 else 24), v - 14)

        # The accents stamped by tuba and trombones (on the first only under a melody of theirs).
        for i, eighth in enumerate(ACCENTS):
            length = 1.6 if i < 2 else 2.6
            add("tuba", bar, eighth, length * 0.6, root, 104 if i == 0 else 90)
            if section != 2:
                for n in chord_notes:
                    add("trombones", bar, eighth, length * 0.5, n, (88, 74, 80)[i] - (14 if section == 1 else 0))

        # The melodies.
        if section == 0:
            if again:
                melody("trumpet", bar, THEME[i8], 96)
                melody("oboe", bar, THEME[i8], 80, shift=-12)
            else:
                melody("oboe", bar, THEME[i8], 98)
                melody("shanai", bar, THEME[i8], 76)
        elif section == 1:
            melody("strings", bar, TUNE[i8], 98)
            melody("strings", bar, TUNE[i8], 84, shift=-12)
            if again:
                for n in chord_notes:
                    add("choir", bar, 0, 6.8, n + 12, 70)
        elif section == 2:
            melody("trombones", bar, LOW_LINE[i8], 104)
            if i8 % 2 == 1:
                melody("shanai", bar, RUN, 80)
            # The choir chants the chord on the accents.
            for eighth in ACCENTS:
                for n in chord_notes:
                    add("choir", bar, eighth, 0.8 if eighth < 4 else 1.6, n + 12, 90 if eighth == 0 else 78)
        else:
            melody("oboe", bar, THEME_UP[i8], 100)
            melody("shanai", bar, THEME_UP[i8], 70)
            melody("strings", bar, THEME_UP[i8], 82, shift=-12)
            if again:
                melody("trumpet", bar, THEME_UP[i8], 84, shift=-12)

        # Drums: bass drum and low conga on the accents, the rest of the eighths on bongos and
        # the muted conga, the tambourine on every eighth, melodic toms on the first and the
        # long group, a timpani stroke on the root each bar.
        for i in range(BEATS):
            if i in ACCENTS:
                add("drums", bar, i, 0.5, BASS_DRUM, 116 if i == 0 else 100)
                add("drums", bar, i, 0.5, LOW_CONGA, 104)
            else:
                add("drums", bar, i, 0.5, HIGH_BONGO if i % 2 else MUTE_CONGA, 82)
            add("drums", bar, i, 0.4, TAMBOURINE, 70 if i in ACCENTS else 50)
        add("drums", bar, 5.5, 0.4, LOW_BONGO, 66)
        add("toms", bar, 0, 1, pitch("C#3"), 104)
        add("toms", bar, 4, 1, pitch("G#2"), 96)
        if again and section == 2:  # tom eighths under the chant's second time
            for i in (1, 3, 5, 6):
                add("toms", bar, i, 0.5, pitch("C#3") + (0 if i < 5 else -5), 80)
        add("timpani", bar, 0, 1.5, root + 12 if root < pitch("A2") else root, 100)
        if bar % 8 == 0 or (again and section == 3 and bar % 2 == 0):
            add("drums", bar, 0, 3, CRASH, 100)
        if i8 == 7:
            # A fill into the next section: bongos and congas in sixteenths over the long group,
            # and a timpani roll.
            for i in range(6):
                add("drums", bar, 4 + i * 0.5, 0.4, (HIGH_BONGO, LOW_BONGO, MUTE_CONGA)[i % 3], 70 + 7 * i)
            for i in range(6):
                add("timpani", bar, 4 + i * 0.5, 0.5, root + 12 if root < pitch("A2") else root, 70 + 6 * i)
    return notes


if __name__ == "__main__":
    # Dense enough to clip FluidSynth at the usual 0.8.
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-11.0, gain=0.4, beats=BEATS)
