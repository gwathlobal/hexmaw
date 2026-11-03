#!/usr/bin/env python3
"""Compose a combat loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_combat.py audio/music/combat-5 data/music/combat-5.ogg

The piece is written out below as notes: 64 bars of 4/4 in E minor at 0.375 s a beat (160
BPM, combat-3's real tempo; at 120 it lacked combat-3's energy), after combat-3, the generated
track that worked best: cellos grinding an eighth-note ostinato over contrabasses, a bass drum, taiko and timpani on every beat, low brass stabs, a
tense tremolo string figure circling the fifth, a horn theme in the second section and long
horn lines over choir stabs and orchestra hits in the third. F major over E minor (the
Phrygian bII) gives it its menace, and every phrase ends on B major, which drives back into
the next and, at the end, into the loop's first bar. Its four 8-bar sections come twice, the
second time scored anew: the string figure an octave up with syncopated stabs and a choir, the
theme on the brass an octave over the horns, the long lines over the running figure and taiko
eighths, and a crash every two bars into the return. (A first version was the four once, 48 s.)

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-11 LUFS, the combat
loops' level) and encoded to OUT. --preview writes the join, --seed changes the small velocity
variations. 0.375 s a beat makes the loop 96 s, 4233600 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 375000  # 0.375 s a beat, 160 BPM
BARS = 64

# --- The piece ---------------------------------------------------------------------------

CHORDS = ("Em Em C  B  Em Em Am B "   # A: the ostinato, stabs and the string figure
          "Em C  Am B  Em F  Em B "   # B: the horn theme
          "C  D  Em Em F  F  B  B "   # C: long horn lines, choir, orchestra hits
          "Em Em C  B  Em F  Am B").split() * 2  # A': everything, the theme's second form
# Then the four again, scored anew.

# Melodies: per bar, (note, beat, beats long), beats counted from 1.
THEME = [
    [("E4", 1, 1.5), ("B3", 2.5, .5), ("E4", 3, 1), ("G4", 4, 1)],
    [("G4", 1, 1.5), ("E4", 2.5, .5), ("C4", 3, 2)],
    [("A4", 1, 1), ("G4", 2, .5), ("F#4", 2.5, .5), ("E4", 3, 1), ("C4", 4, 1)],
    [("B3", 1, 2), ("D#4", 3, 1), ("F#4", 4, 1)],
    [("G4", 1, 1.5), ("F#4", 2.5, .5), ("E4", 3, 1), ("B4", 4, 1)],
    [("C5", 1, 1.5), ("A4", 2.5, .5), ("F4", 3, 2)],
    [("B4", 1, 1), ("G4", 2, 1), ("E4", 3, 1), ("G4", 4, 1)],
    [("F#4", 1, 2), ("D#4", 3, 1), ("B3", 4, 1)],
]
LONG_LINES = [
    [("G4", 1, 3), ("E4", 4, 1)],
    [("F#4", 1, 3), ("A4", 4, 1)],
    [("B4", 1, 4)],
    [("G4", 1, 2), ("A4", 3, 1), ("B4", 4, 1)],
    [("C5", 1, 3), ("A4", 4, 1)],
    [("F4", 1, 2), ("A4", 3, 1), ("C5", 4, 1)],
    [("B4", 1, 4)],
    [("D#5", 1, 2), ("B4", 3, 1), ("F#4", 4, 1)],
]
THEME_2 = [
    [("E4", 1, 1.5), ("B3", 2.5, .5), ("E4", 3, 1), ("G4", 4, 1)],
    [("B4", 1, 1.5), ("A4", 2.5, .5), ("G4", 3, 1), ("F#4", 4, 1)],
    [("G4", 1, 1.5), ("E4", 2.5, .5), ("C5", 3, 2)],
    [("B4", 1, 2), ("A4", 3, 1), ("F#4", 4, 1)],
    [("G4", 1, 1.5), ("F#4", 2.5, .5), ("E4", 3, 1), ("B4", 4, 1)],
    [("C5", 1, 1.5), ("A4", 2.5, .5), ("F4", 3, 2)],
    [("E5", 1, 1), ("C5", 2, 1), ("A4", 3, 1), ("C5", 4, 1)],
    [("B4", 1, 2), ("F#4", 3, 1), ("D#4", 4, 1)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "cellos":    dict(channel=0, program=42, volume=100, pan=50, reverb=40),
    "basses":    dict(channel=1, program=43, volume=100, pan=64, reverb=35),
    "brass":     dict(channel=2, program=61, volume=88, pan=72, reverb=45),
    "trombones": dict(channel=3, program=57, volume=96, pan=58, reverb=45),
    "horns":     dict(channel=4, program=60, volume=112, pan=64, reverb=55),
    "tremolo":   dict(channel=5, program=44, volume=78, pan=84, reverb=55),
    "choir":     dict(channel=6, program=52, volume=86, pan=64, reverb=70),
    "hits":      dict(channel=7, program=55, volume=72, pan=64, reverb=60),
    "timpani":   dict(channel=8, program=47, volume=100, pan=64, reverb=50),
    "drums":     dict(channel=9, program=0, volume=100, pan=64, reverb=40),
    "taiko":     dict(channel=10, program=116, volume=104, pan=64, reverb=45),
}
BASS_DRUM, SNARE, LOW_FLOOR_TOM, HIGH_FLOOR_TOM, CRASH = 36, 38, 41, 43, 49


def low(chord):
    """The chord's root between E2 and D#3, the cellos' octave, and its triad."""
    root, triad = chord_tones(chord)
    return 40 + (root - 40) % 12, triad


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, beat, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-5, 5)))
        notes.append((part, bar * 4 + beat - 1, length, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, beat, length in phrase:
            add(part, bar, beat, length * 0.92, pitch(name) + shift, velocity + (8 if beat == 1 else 0))

    for bar, chord in enumerate(CHORDS):
        section, i8, again = bar // 8 % 4, bar % 8, bar >= 32
        root, triad = low(chord)

        # The ostinato: root, root, octave, root, fifth, root, octave, and a half step up
        # that grinds into the next bar. Contrabasses on the beats an octave down.
        for i, step in enumerate((0, 0, 12, 0, 7, 0, 12, 1)):
            add("cellos", bar, 1 + i * 0.5, 0.42, root + step, (102, 72, 88, 72, 98, 72, 88, 80)[i])
        for beat in (1, 2, 3, 4):
            add("basses", bar, beat, 0.8, root - 12, 100 if beat in (1, 3) else 86)

        # Low brass stabs: on 1, the and of 2, and 4; softer under the theme; syncopated
        # the second time round the first section.
        stab = 70 if section == 1 else 92
        rhythm = ((1, 0.5), (1.75, 0.5), (2.5, 0.4), (3.5, 0.4), (4, 0.75)) if again and section == 0 \
            else ((1, 0.75), (2.5, 0.4), (4, 0.75))
        for beat, length in rhythm:
            for t in triad:
                add("brass", bar, beat, length, root + 12 + t, stab)
            add("trombones", bar, beat, length, root, stab + 6)
            add("trombones", bar, beat, length, root + 7, stab)

        # The horns.
        if section == 1:
            melody("horns", bar, THEME[i8], 100)
            if again:  # the brass takes the theme an octave over the horns
                melody("brass", bar, THEME[i8], 86, shift=12)
            else:
                melody("trombones", bar, THEME[i8], 70, shift=-12)
        elif section == 2:
            melody("horns", bar, LONG_LINES[i8], 104)
        elif section == 3:
            melody("horns", bar, THEME_2[i8], 104)
            melody("brass", bar, THEME_2[i8], 74, shift=-12)

        # The string figure circling the fifth over an E pedal, D sharpened on B major, an
        # octave up the second time round the first section; held tremolo chords in the
        # third section the first time instead.
        if section == 2 and not again:
            for t in triad:
                add("tremolo", bar, 1, 3.95, root + 24 + t, 78)
        else:
            figure = ["B4", "C5", "B4", "A4", "B4", "C5", "D#5" if chord == "B" else "D5", "C5"]
            up = 12 if again and section == 0 else 0
            for i, name in enumerate(figure):
                add("tremolo", bar, 1 + i * 0.5, 0.48, pitch(name) + up, 80 if i % 2 == 0 else 68)

        # The choir holds the chord under the first section's second time.
        if again and section == 0:
            for t in triad:
                add("choir", bar, 1, 3.9, root + 12 + t, 76)

        # Choir and orchestra hits in the third section; a hit at every fourth bar elsewhere.
        if section == 2:
            for t in triad:
                add("choir", bar, 1, 2.9, root + 24 + t, 92)
                add("choir", bar, 4.5, 0.45, root + 24 + t, 84)
            add("hits", bar, 1, 0.5, root + 24, 96)
            add("hits", bar, 2.5, 0.5, root + 24, 80)
        elif bar % 4 == 0:
            add("hits", bar, 1, 0.5, root + 24, 92)

        # Drums: bass drum on every beat, taiko and timpani on 1 and 3, toms off the beat.
        for beat in (1, 2, 3, 4):
            add("drums", bar, beat, 0.25, BASS_DRUM, 112 if beat in (1, 3) else 94)
        for beat in (1, 3):
            add("taiko", bar, beat, 0.5, 48, 108)
            add("timpani", bar, beat, 0.9, root if beat == 1 else root + 7, 100)
        add("taiko", bar, 4.5, 0.4, 48, 84)
        if again and section == 2:  # taiko eighths under the long lines' second time
            for beat in (1.5, 2, 2.5, 3.5, 4):
                add("taiko", bar, beat, 0.3, 48, 76)
        add("drums", bar, 2.5, 0.25, HIGH_FLOOR_TOM, 84)
        add("drums", bar, 4.5, 0.25, LOW_FLOOR_TOM, 88)
        if section in (1, 3):  # toms on the other off-beats too, under the themes
            add("drums", bar, 1.5, 0.25, LOW_FLOOR_TOM, 72)
            add("drums", bar, 3.5, 0.25, HIGH_FLOOR_TOM, 76)
        if bar % 8 == 0 or (again and section == 3 and bar % 2 == 0):
            add("drums", bar, 1, 2, CRASH, 96)
        if bar % 4 == 3:
            # A snare roll into the next phrase, and at a section's end a timpani roll too.
            start = 3 if bar % 8 == 7 else 4
            for i in range(int((5 - start) * 4)):
                add("drums", bar, start + i * 0.25, 0.2, SNARE, 60 + 5 * i)
            if bar % 8 == 7:
                for i in range(8):
                    add("timpani", bar, 3 + i * 0.25, 0.25, root, 64 + 5 * i)
    return notes


if __name__ == "__main__":
    # Dense enough to clip FluidSynth at the usual 0.8.
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-11.0, gain=0.4)
