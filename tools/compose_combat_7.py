#!/usr/bin/env python3
"""Compose a combat loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_combat_7.py audio/music/combat-7 data/music/combat-7.ogg

The piece is written out below as notes: 64 bars of 4/4 in G minor at 0.4 s a beat (150 BPM),
battle music in the trailer's vein but menacing, never heroic. Its spine is a tense violin figure
in sixteenths circling each chord's fifth by half steps; cellos and contrabasses hammer eighths
under it, a bass drum, taiko and timpani strike every beat, and trombones and tuba stab bare
fifths on the accents, no full chords. Low horns have a narrow, creeping theme, trombones and
tuba answer it lower still, a choir chants minor chords on the accents over long horn notes in
the third section, and the theme comes back with the strings an octave over the horns. The
chords keep to minor ones and the dark major ones of the key: G minor, C minor, A flat major (the
Neapolitan) and the major dominant D, never B flat, E flat or F, which sounded triumphant. Its
four 8-bar sections come twice, the second time scored anew: a choir holding the chord under the
theme, cellos doubling the answer, taiko sixteenths under the chant, a crash every two bars.
(A first version, with the theme on trumpets climbing to G5 over full brass chords, was too
triumphant.)

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-11 LUFS, the combat
loops' level) and encoded to OUT. --preview writes the join, --seed changes the small velocity
variations. 0.4 s a beat makes the loop 102.4 s, 4515840 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 400000  # 0.4 s a beat, 150 BPM
BARS = 64

# --- The piece ---------------------------------------------------------------------------

CHORDS = ("Gm Gm Ab Gm Cm Ab D  D "   # A: the low horns' theme
          "Gm Ab Gm Ab Cm Cm D  D "   # B: trombones and tuba answer
          "Cm Cm Ab Ab Gm Gm D  D "   # C: the choir's chant, long horn notes
          "Gm Gm Ab Gm Cm Ab D  D").split() * 2  # A': the theme, strings over the horns
# Then the four again, scored anew.

# The violin figure, eight sixteenths played twice a bar, by chord: its fifth, a half step
# above and below, and a drop to its third.
FIGURE = {
    "Gm": ("D5", "Eb5", "D5", "C#5", "D5", "Eb5", "D5", "Bb4"),
    "Ab": ("Eb5", "Fb5", "Eb5", "D5", "Eb5", "Fb5", "Eb5", "C5"),
    "Cm": ("G4", "Ab4", "G4", "F#4", "G4", "Ab4", "G4", "Eb4"),
    "D":  ("D5", "Eb5", "D5", "C#5", "D5", "Eb5", "D5", "A4"),
}

# Melodies: per bar, (note, beat, beats long), beats counted from 1.
THEME = [
    [("G3", 1, 1.5), ("Ab3", 2.5, .5), ("G3", 3, 1), ("D4", 4, 1)],
    [("Eb4", 1, 1), ("D4", 2, 1), ("Bb3", 3, 1.5), ("A3", 4.5, .5)],
    [("Ab3", 1, 1.5), ("C4", 2.5, .5), ("Eb4", 3, 1), ("D4", 4, 1)],
    [("D4", 1, 2), ("Bb3", 3, 1), ("G3", 4, 1)],
    [("C4", 1, 1.5), ("D4", 2.5, .5), ("Eb4", 3, 1), ("G4", 4, 1)],
    [("F4", 1, 1), ("Eb4", 2, 1), ("C4", 3, 1), ("Ab3", 4, 1)],
    [("A3", 1, 1.5), ("Bb3", 2.5, .5), ("A3", 3, 1), ("F#3", 4, 1)],
    [("D4", 1, 2), ("C4", 3, .5), ("Bb3", 3.5, .5), ("A3", 4, 1)],
]
ANSWER = [
    [("G2", 1, 1), ("Bb2", 2, 1), ("D3", 3, 1), ("Eb3", 4, 1)],
    [("D3", 1, 1.5), ("C3", 2.5, .5), ("Ab2", 3, 2)],
    [("G2", 1, 1), ("Bb2", 2, 1), ("D3", 3, 1), ("G3", 4, 1)],
    [("Eb3", 1, 1.5), ("C3", 2.5, .5), ("Ab2", 3, 1), ("G2", 4, 1)],
    [("C3", 1, 1.5), ("Eb3", 2.5, .5), ("G3", 3, 1), ("Ab3", 4, 1)],
    [("G3", 1, 1), ("Eb3", 2, 1), ("D3", 3, 1), ("C3", 4, 1)],
    [("D3", 1, 2), ("Eb3", 3, 1), ("D3", 4, 1)],
    [("F#3", 1, 1), ("A3", 2, 1), ("C4", 3, 1), ("A3", 4, 1)],
]
LONG_NOTES = [
    [("C4", 1, 3), ("B3", 4, 1)],
    [("C4", 1, 2), ("Eb4", 3, 2)],
    [("Eb4", 1, 3), ("D4", 4, 1)],
    [("C4", 1, 4)],
    [("D4", 1, 3), ("Eb4", 4, 1)],
    [("D4", 1, 2), ("Bb3", 3, 2)],
    [("A3", 1, 2), ("C4", 3, 2)],
    [("D4", 1, 4)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "violins":   dict(channel=0, program=48, volume=84, pan=40, reverb=45),
    "cellos":    dict(channel=1, program=42, volume=96, pan=72, reverb=40),
    "basses":    dict(channel=2, program=43, volume=100, pan=64, reverb=35),
    "strings":   dict(channel=3, program=48, volume=90, pan=60, reverb=50),
    "horns":     dict(channel=4, program=60, volume=116, pan=64, reverb=55),
    "trombones": dict(channel=5, program=57, volume=100, pan=56, reverb=45),
    "tuba":      dict(channel=6, program=58, volume=100, pan=64, reverb=40),
    "choir":     dict(channel=7, program=52, volume=86, pan=64, reverb=70),
    "hits":      dict(channel=8, program=55, volume=72, pan=64, reverb=60),
    "drums":     dict(channel=9, program=0, volume=100, pan=64, reverb=40),
    "timpani":   dict(channel=10, program=47, volume=100, pan=64, reverb=50),
    "taiko":     dict(channel=11, program=116, volume=106, pan=64, reverb=45),
}
BASS_DRUM, SNARE, LOW_TOM, MID_TOM, HIGH_TOM, CRASH = 36, 38, 45, 47, 50, 49


def low(chord):
    """The chord's root between F2 and E3, the cellos' octave, and its triad."""
    root, triad = chord_tones(chord)
    return 41 + (root - 41) % 12, triad


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, beat, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-5, 5)))
        notes.append((part, bar * 4 + beat - 1, length, note, v))

    def melody(part, bar, phrase, velocity, shift=0):
        for name, beat, length in phrase:
            add(part, bar, beat, length * 0.9, pitch(name) + shift, velocity + (8 if beat == 1 else 0))

    for bar, chord in enumerate(CHORDS):
        section, i8, again = bar // 8 % 4, bar % 8, bar >= 32
        root, triad = low(chord)
        timpani = root - 12 if root > 50 else root

        # The violin figure in sixteenths, the first of each four leaning.
        for i in range(16):
            add("violins", bar, 1 + i * 0.25, 0.2, pitch(FIGURE[chord][i % 8]), 84 if i % 4 == 0 else 64)

        # Cellos and contrabasses hammer eighths on the root.
        for i in range(8):
            add("cellos", bar, 1 + i * 0.5, 0.4, root, 100 if i % 2 == 0 else 78)
            add("basses", bar, 1 + i * 0.5, 0.4, root - 12, 96 if i % 2 == 0 else 72)

        # Bare fifths stabbed on 1, the and of 2 and 4 by trombones and tuba; the tuba alone
        # under the answer, which is theirs.
        for beat, length in ((1, 0.6), (2.5, 0.4), (4, 0.6)):
            add("tuba", bar, beat, length, root - 12, 98)
            if section != 1:
                add("trombones", bar, beat, length, root, 90)
                add("trombones", bar, beat, length, root + 7, 84)

        # The tunes.
        if section == 0:
            melody("horns", bar, THEME[i8], 104)
        elif section == 1:
            melody("trombones", bar, ANSWER[i8], 110)
            melody("tuba", bar, ANSWER[i8], 84, shift=-12)
            if again:
                melody("cellos", bar, ANSWER[i8], 70, shift=12)
        elif section == 2:
            melody("horns", bar, LONG_NOTES[i8], 100)
            # The choir chants the chord on the accents, low.
            for beat, length in ((1, 0.8), (2.5, 0.4), (4, 0.8)):
                for t in triad:
                    add("choir", bar, beat, length, root + 12 + t, 92 if beat == 1 else 80)
        else:
            melody("horns", bar, THEME[i8], 108)
            melody("strings", bar, THEME[i8], 84, shift=12)

        # The choir holds the chord low under the theme's second time.
        if again and section == 0:
            for t in triad:
                add("choir", bar, 1, 3.9, root + 12 + t, 70)

        # An orchestra hit every fourth bar.
        if bar % 4 == 0:
            add("hits", bar, 1, 0.5, root + 12, 92)

        # Drums: bass drum on every beat, taiko and timpani on 1 and 3 and the taiko on the
        # and of 4, a snare only on that and of 4; a crash every fourth bar (every second in the
        # last section's second time).
        for beat in (1, 2, 3, 4):
            add("drums", bar, beat, 0.25, BASS_DRUM, 114 if beat in (1, 3) else 98)
        add("drums", bar, 4.5, 0.25, SNARE, 84)
        for beat in (1, 3):
            add("taiko", bar, beat, 0.5, 48, 112)
            add("timpani", bar, beat, 0.9, timpani, 100)
        add("taiko", bar, 4.5, 0.4, 48, 88)
        if again and section == 2:  # taiko sixteenths under the chant's second time
            for i in range(16):
                if i % 4:
                    add("taiko", bar, 1 + i * 0.25, 0.2, 48, 62 + (i % 2) * 10)
        if bar % 4 == 0 or (again and section == 3 and bar % 2 == 0):
            add("drums", bar, 1, 2, CRASH, 96)
        if bar % 4 == 3:
            # A tom fill into the next phrase, and at a section's end a timpani roll too.
            for i, tom in enumerate((HIGH_TOM, HIGH_TOM, MID_TOM, MID_TOM, LOW_TOM, LOW_TOM, LOW_TOM, LOW_TOM)):
                add("drums", bar, 3 + i * 0.25, 0.2, tom, 76 + 4 * i)
            if bar % 8 == 7:
                for i in range(8):
                    add("timpani", bar, 3 + i * 0.25, 0.25, timpani, 66 + 5 * i)
    return notes


if __name__ == "__main__":
    # Dense enough to clip FluidSynth at the usual 0.8.
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-11.0, gain=0.4)
