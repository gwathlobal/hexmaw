#!/usr/bin/env python3
"""Compose an exploration loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_explore_5.py audio/music/explore-5 data/music/explore-5.ogg

The piece is written out below as notes: 32 bars of 4/4 in B minor at 0.72 s a beat (83 BPM),
tense where the other exploration loops are calm. Contrabasses pulse in eighths like slow
footsteps, a half step up and down off the root, and a bass drum beats a heartbeat on 1 and 3.
Over them a solo cello plays a searching theme full of half steps, a low flute and a muted
trumpet trade the second section, the trumpet has the third, and the cello comes back for the
last. Each section keeps to one colour beside the pulse, so the texture stays thin: under the
cello, pizzicato violas ticking on the off-beats and tremolo violins swelling and falling on
chords with a half step clashing in them; under the trade, soft string chords changing every
bar; under the trumpet, low brass swelling in and a timpani roll creeping up. A reverse cymbal
draws into each section. (A first version stacked these from the second section on, with a
pizzicato cluster struck every eight bars, and turned into a din.) The chords are B minor's with
C major (the Neapolitan) and the major dominant F#, a G over it in the third section; every
phrase ends on F#, the last into the loop's first bar.

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-14 LUFS, the
exploration loops' level) and encoded to OUT. --preview writes the join, --seed changes the
small velocity variations. 0.72 s a beat makes the loop 92.16 s, 4064256 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 720000  # 0.72 s a beat, 83 BPM
BARS = 32

# --- The piece ---------------------------------------------------------------------------

CHORDS = ("Bm Bm C  Bm G  F# Bm F# "   # A: the cello's theme
          "Em C  Bm G  Em C  F# F# "   # B: the flute and the muted trumpet trade
          "G  G  C  C  Bm Bm F# F# "   # C: the trumpet over low brass, the timpani creeping
          "Bm Bm C  Bm G  C  F# F#").split()  # A': the cello again

# Melodies: per bar, (note, beat, beats long), beats counted from 1.
THEME = [
    [("F#3", 1, 1.5), ("G3", 2.5, .5), ("F#3", 3, 1), ("B3", 4, 1)],
    [("A#3", 1, 1), ("B3", 2, 1), ("D4", 3, 1.5), ("C#4", 4.5, .5)],
    [("C4", 1, 2), ("B3", 3, .5), ("C4", 3.5, .5), ("E4", 4, 1)],
    [("D4", 1, 1.5), ("C#4", 2.5, .5), ("B3", 3, 2)],
    [("B3", 1, 1), ("D4", 2, 1), ("G4", 3, 1.5), ("F#4", 4.5, .5)],
    [("E4", 1, 1), ("D4", 2, .5), ("C#4", 2.5, .5), ("A#3", 3, 2)],
    [("B3", 1, 1), ("C4", 2, 1), ("B3", 3, .5), ("A#3", 3.5, .5), ("B3", 4, 1)],
    [("F#3", 1, 2), ("G3", 3, 1), ("A#3", 4, 1)],
]
TRADE = [  # (who, phrase): two bars each
    ("flute", [("B4", 1, 1.5), ("C5", 2.5, .5), ("B4", 3, 1), ("G4", 4, 1)]),
    ("flute", [("E4", 1, 1), ("G4", 2, 1), ("B4", 3, 1.5), ("A4", 4.5, .5)]),
    ("trumpet", [("F#4", 1, 1.5), ("G4", 2.5, .5), ("F#4", 3, 1), ("D4", 4, 1)]),
    ("trumpet", [("B3", 1, 1), ("D4", 2, 1), ("G4", 3, 2)]),
    ("flute", [("E5", 1, 1.5), ("D#5", 2.5, .5), ("E5", 3, 1), ("B4", 4, 1)]),
    ("flute", [("C5", 1, 1), ("B4", 2, .5), ("A4", 2.5, .5), ("G4", 3, 1), ("E4", 4, 1)]),
    ("trumpet", [("A#3", 1, 1), ("C#4", 2, 1), ("F#4", 3, 1.5), ("E4", 4.5, .5)]),
    ("trumpet", [("D4", 1, 1), ("C#4", 2, 1), ("A#3", 3, 2)]),
]
TRUMPET = [
    [("D4", 1, 2), ("E4", 3, 1), ("F#4", 4, 1)],
    [("G4", 1, 3), ("F#4", 4, 1)],
    [("E4", 1, 2), ("G4", 3, 1), ("C5", 4, 1)],
    [("B4", 1, 3), ("G4", 4, 1)],
    [("F#4", 1, 2), ("D4", 3, 1), ("B3", 4, 1)],
    [("C4", 1, 2), ("B3", 3, 1), ("A#3", 4, 1)],
    [("C#4", 1, 2), ("E4", 3, 1), ("G4", 4, 1)],
    [("F#4", 1, 4)],
]
THEME_END = [  # the theme's second half, turned toward the loop's return
    [("B3", 1, 1), ("D4", 2, 1), ("G4", 3, 1), ("B4", 4, 1)],
    [("C5", 1, 1.5), ("B4", 2.5, .5), ("G4", 3, 1), ("E4", 4, 1)],
    [("F#4", 1, 1), ("E4", 2, .5), ("C#4", 2.5, .5), ("A#3", 3, 1), ("C#4", 4, 1)],
    [("F#3", 1, 2), ("G3", 3, 1), ("A#3", 4, 1)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "cello":     dict(channel=0, program=42, volume=104, pan=56, reverb=80),
    "flute":     dict(channel=1, program=73, volume=92, pan=74, reverb=85),
    "trumpet":   dict(channel=2, program=59, volume=92, pan=48, reverb=85),
    "basses":    dict(channel=3, program=43, volume=100, pan=64, reverb=55),
    "violas":    dict(channel=4, program=45, volume=80, pan=84, reverb=70),
    "tremolo":   dict(channel=5, program=44, volume=70, pan=40, reverb=90),
    "strings":   dict(channel=6, program=49, volume=64, pan=64, reverb=90),
    "brass":     dict(channel=7, program=57, volume=84, pan=60, reverb=85),
    "tuba":      dict(channel=8, program=58, volume=88, pan=64, reverb=80),
    "drums":     dict(channel=9, program=0, volume=96, pan=64, reverb=55),
    "timpani":   dict(channel=10, program=47, volume=90, pan=64, reverb=75),
    "cymbal":    dict(channel=11, program=119, volume=64, pan=64, reverb=80),
}
BASS_DRUM = 35


def low(chord):
    """The chord's root between A#1 and A2, the contrabasses' octave, and its triad."""
    root, triad = chord_tones(chord)
    return 34 + (root - 34) % 12, triad


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, beat, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-5, 5)))
        notes.append((part, bar * 4 + beat - 1, length, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, beat, length in phrase:
            add(part, bar, beat, length * 0.94, pitch(name) + shift, velocity + (8 if beat == 1 else 0))

    def swell(bar, tones, top):
        """Tremolo violins struck again every half beat, rising to TOP and falling back."""
        for i in range(8):
            v = round(36 + (top - 36) * (1 - abs(i - 4.5) / 4.5))
            for n in tones:
                add("tremolo", bar, 1 + i * 0.5, 0.55, n, v)

    for bar, chord in enumerate(CHORDS):
        section, i8 = bar // 8, bar % 8
        root, triad = low(chord)

        # The melody.
        if section == 0:
            melody("cello", bar, THEME[i8], 92)
        elif section == 1:
            who, phrase = TRADE[i8]
            melody(who, bar, phrase, 90 if who == "flute" else 86)
        elif section == 2:
            melody("trumpet", bar, TRUMPET[i8], 90)
        else:
            melody("cello", bar, THEME[i8] if i8 < 4 else THEME_END[i8 - 4], 94)

        # The footsteps: contrabasses in eighths on the root, a half step up on the and of 2
        # and down on the and of 4, the beats louder.
        for i, step in enumerate((0, 0, 0, 1, 0, 0, 0, -1)):
            add("basses", bar, 1 + i * 0.5, 0.42, root + step, 96 if i % 2 == 0 else 72)

        # The violas' nervous ticks on the off-beats, under the cello: the fifth and the minor
        # sixth above the octave, in turn.
        if section in (0, 3):
            for i, beat in enumerate((1.5, 2.5, 3.5, 4.5)):
                add("violas", bar, beat, 0.3, root + 12 + (7 if i % 2 == 0 else 8), 78 if i % 2 else 70)

        # The heartbeat on 1 and 3.
        for beat in (1, 3):
            add("drums", bar, beat, 0.25, BASS_DRUM, 92)
            add("drums", bar, beat + 0.28, 0.25, BASS_DRUM, 66)

        # Tremolo violins swell under the cello on the chord with a half step clashing in it:
        # the second and third bars of each phrase of four, high.
        if section in (0, 3) and i8 % 4 in (1, 2):
            swell(bar, [root + 36 + t for t in triad] + [root + 36 + 1], 72)

        # Soft string chords every bar under the trade.
        if section == 1:
            for t in triad:
                add("strings", bar, 1, 3.9, root + 24 + t, 56)

        # Low brass swelling in under the trumpet, the root and then its fifth.
        if section == 2 and i8 % 2 == 0:
            add("tuba", bar, 1, 7.8, root + 12, 60)
            add("brass", bar, 3, 5.8, root + 19, 54)

        # The timpani: a stroke at each section's start, and in the third section's last three
        # bars a roll creeping up and dying away.
        if i8 == 0:
            add("timpani", bar, 1, 2, root + 12, 90)
        if section == 2 and i8 >= 5:
            for i in range(16):
                k = (i8 - 5) * 16 + i
                v = round(40 + 50 * k / 31) if k < 32 else round(90 - 40 * (k - 32) / 15)
                add("timpani", bar, 1 + i * 0.25, 0.25, root + 12, v)

        # A reverse cymbal drawing into the next section.
        if i8 == 7:
            add("cymbal", bar, 2, 3, 60, 70)
    return notes


if __name__ == "__main__":
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-14.0)
