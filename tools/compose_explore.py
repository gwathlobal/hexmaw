#!/usr/bin/env python3
"""Compose an exploration loop as MIDI and render it through a General MIDI soundfont.

  tools/compose_explore.py audio/music/explore-2 data/music/explore-2.ogg

The piece is written out below as notes: 32 bars of 4/4 in D minor at 0.75 s a beat (80
BPM), a horn and a clarinet in its low register trading the melody over a dulcimer (and in
the middle a marimba) arpeggio, a plucked bass, soft low strings or a choir under them, a
frame-drum rhythm on GM percussion, and a tubular bell and a timpani stroke at the start of
each section. Its chords are D minor's darkest: minor i and iv, bVI (Bb), bII (Eb) and the
major dominant (A), with no C or F major. It ends on A, so it runs on into its own first bar.
(A first version, at 0.7 s a beat with C and F major and everything an octave higher, sounded
right but too bright for a dungeon.)

tools/midi_music.py renders it: twice in a row through a General MIDI soundfont, the second pass
kept as the loop, which joins without a crossfade, brought to --loudness (-14 LUFS, the
exploration loops' level) and encoded to OUT. --preview writes the join, --seed changes the
small velocity variations. 0.75 s a beat makes the loop 96 s, 4233600 samples at 44.1 kHz.
"""

import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
from midi_music import chord_tones, pitch, run  # noqa: E402

BEAT_US = 750000  # 0.75 s a beat, 80 BPM
BARS = 32

# --- The piece ---------------------------------------------------------------------------

# One chord a bar, as its root and quality. A is major: D harmonic minor's dominant, the dark
# turn at the end of each phrase. Eb is the Neapolitan, bII. No C or F major: they brightened it.
CHORDS = ("Dm Dm Bb A  Dm Dm Gm A "    # A: the horn's theme
          "Dm Bb Gm A  Dm Eb A  A "    # A': the clarinet answers
          "Bb A  Dm Dm Gm Eb A  A "    # B: low horn, choir, marimba
          "Dm Dm Bb A  Gm Bb A  A").split()  # A'': the theme again, both together

# Melodies: per bar, (note, beat, beats long), beats counted from 1.
THEME_A = [
    [("A3", 2, 1), ("D4", 3, 1), ("E4", 4, .5), ("F4", 4.5, .5)],
    [("E4", 1, 1.5), ("D4", 2.5, .5), ("A3", 3, 2)],
    [("Bb3", 2, 1), ("D4", 3, 1), ("F4", 4, 1)],
    [("G4", 1, 1.5), ("F4", 2.5, .5), ("E4", 3, 1), ("C#4", 4, 1)],
    [("D4", 1, 1), ("F4", 2, 1), ("A4", 3, 1.5), ("G4", 4.5, .5)],
    [("F4", 1, 1), ("E4", 2, 1), ("D4", 3, 2)],
    [("G4", 1, 1), ("Bb4", 2, .5), ("A4", 2.5, .5), ("G4", 3, 1), ("F4", 4, 1)],
    [("E4", 1, 1), ("C#4", 2, 1), ("A3", 3, 2)],
]
ANSWER = [  # low in the clarinet, its dark chalumeau register
    [("D4", 1, 1.5), ("C4", 2.5, .5), ("A3", 3, 1), ("F3", 4, 1)],
    [("Bb3", 1, 1), ("D4", 2, 1), ("F4", 3, 1.5), ("Eb4", 4.5, .5)],
    [("D4", 1, 2), ("Bb3", 3, 1), ("G3", 4, 1)],
    [("E4", 1, 1), ("C#4", 2, 1), ("A3", 3, 2)],
    [("F4", 1, 1), ("A4", 2, 1), ("D5", 3, 1.5), ("C5", 4.5, .5)],
    [("Bb4", 1, 1), ("G4", 2, 1), ("Eb4", 3, 1), ("Bb3", 4, 1)],
    [("A3", 1, 1.5), ("C#4", 2.5, .5), ("E4", 3, 1), ("G4", 4, 1)],
    [("F4", 1, 1), ("E4", 2, 2)],
]
# The horn's reply under the clarinet's last bar, falling.
ANSWER_HORN = {15: [("A3", 3, .5), ("G3", 3.5, .5), ("F3", 4, .5), ("E3", 4.5, .5)]}
LOW_HORN = [
    [("F4", 1, 2), ("D4", 3, 2)],
    [("E4", 1, 2), ("G4", 3, 2)],
    [("F4", 1, 3), ("E4", 4, 1)],
    [("D4", 1, 4)],
    [("Bb3", 1, 2), ("D4", 3, 2)],
    [("Eb4", 1, 2), ("G4", 3, 1), ("Bb4", 4, 1)],
    [("A4", 1, 2), ("G4", 3, 1), ("E4", 4, 1)],
    [("C#4", 1, 2), ("E4", 3, 2)],
]
COUNTER = {  # the clarinet's short figures in the gaps of the low horn
    17: [("C#4", 3, .5), ("D4", 3.5, .5), ("E4", 4, 1)],
    19: [("A3", 3, .5), ("F3", 3.5, .5), ("D3", 4, 1)],
    21: [("G3", 3, .5), ("Bb3", 3.5, .5), ("Eb4", 4, 1)],
    23: [("E4", 3, .5), ("C#4", 3.5, .5), ("A3", 4, 1)],
}
THEME_END = [  # the theme's second half, turned toward the loop's return
    [("G4", 1, 1), ("Bb4", 2, 1), ("D5", 3, 1.5), ("C5", 4.5, .5)],
    [("Bb4", 1, 1), ("A4", 2, 1), ("F4", 3, 2)],
    [("E4", 1, 1), ("G4", 2, .5), ("F4", 2.5, .5), ("E4", 3, 1), ("C#4", 4, 1)],
    [("A3", 1, 2)],
]

# General MIDI programs (0-based) and channel settings: volume, pan, reverb send.
PARTS = {
    "horn":     dict(channel=0, program=60, volume=96, pan=54, reverb=85),
    "clarinet": dict(channel=1, program=71, volume=96, pan=76, reverb=85),
    "dulcimer": dict(channel=2, program=15, volume=64, pan=40, reverb=75),
    "marimba":  dict(channel=3, program=12, volume=74, pan=46, reverb=75),
    "bass":     dict(channel=4, program=32, volume=100, pan=64, reverb=50),
    "strings":  dict(channel=5, program=48, volume=54, pan=64, reverb=95),
    "choir":    dict(channel=6, program=52, volume=56, pan=64, reverb=100),
    "bell":     dict(channel=7, program=14, volume=52, pan=88, reverb=100),
    "timpani":  dict(channel=8, program=47, volume=84, pan=64, reverb=80),
    "drums":    dict(channel=9, program=0, volume=92, pan=64, reverb=60),
}
LOW_CONGA, MUTE_HI_CONGA, OPEN_HI_CONGA, LOW_FLOOR_TOM, CABASA = 64, 62, 63, 41, 69


def compose(rng):
    """Every note of the loop: (part, beat from 0, beats long, MIDI note, velocity)."""
    notes = []

    def add(part, bar, beat, length, note, velocity):
        v = max(1, min(127, velocity + rng.randint(-6, 6)))
        notes.append((part, bar * 4 + beat - 1, length, note, v))

    def melody(part, bar, phrase, velocity):
        for name, beat, length in phrase:
            add(part, bar, beat, length * 0.95, pitch(name), velocity + (8 if beat == 1 else 0))

    for bar, chord in enumerate(CHORDS):
        section = bar // 8
        root, triad = chord_tones(chord)
        next_root, _ = chord_tones(CHORDS[(bar + 1) % BARS])

        # The melody.
        if section == 0:
            melody("horn", bar, THEME_A[bar], 88)
        elif section == 1:
            melody("clarinet", bar, ANSWER[bar - 8], 92)
            melody("horn", bar, ANSWER_HORN.get(bar, []), 78)
        elif section == 2:
            melody("horn", bar, LOW_HORN[bar - 16], 84)
            melody("clarinet", bar, COUNTER.get(bar, []), 80)
        else:
            phrase = THEME_A[bar - 24] if bar < 28 else THEME_END[bar - 28]
            melody("horn", bar, phrase, 88)
            # The clarinet doubles the theme an octave down from its second half.
            if bar >= 28:
                for name, beat, length in phrase:
                    add("clarinet", bar, beat, length * 0.95, pitch(name) - 12, 72)

        # The arpeggio, in eighths, low: root, fifth, octave, fifth, tenth, fifth, octave, third.
        tones = [root + 12 + t for t in triad] + [root + 24, root + 24 + triad[1]]
        pattern = [0, 2, 3, 2, 4, 2, 3, 1]
        arp = "marimba" if section == 2 else "dulcimer"
        for i, k in enumerate(pattern):
            add(arp, bar, 1 + i * 0.5, 0.45, tones[k], 66 if i % 2 == 0 else 52)
        if section == 3:  # the marimba joins the dulcimer for the last section, off the beat
            for i in (1, 3, 5, 7):
                add("marimba", bar, 1 + i * 0.5, 0.4, tones[pattern[i]], 48)

        # The bass: root, root again off the beat, the fifth, then a step toward the next root.
        add("bass", bar, 1, 1.4, root, 98)
        add("bass", bar, 2.5, 0.4, root, 72)
        add("bass", bar, 3, 0.9, root + 7, 86)
        approach = next_root + (2 if next_root % 12 != root % 12 else -1)
        add("bass", bar, 4, 0.9, approach if abs(approach - root) < 9 else root + 12, 80)

        # Low strings under the answer and the return; the choir under the low horn.
        pad = "choir" if section == 2 else "strings" if section in (1, 3) else None
        if pad:
            for t in triad:
                add(pad, bar, 1, 3.9, root + 24 + t - (12 if t == 7 else 0), 60)

        # A timpani stroke on the root at the start of each section, and a roll on the
        # dominant leading into the next.
        if bar % 8 == 0:
            add("timpani", bar, 1, 2, root, 92)
        if bar % 8 == 7:
            for i, beat in enumerate((3, 3.25, 3.5, 3.75, 4, 4.25, 4.5, 4.75)):
                add("timpani", bar, beat, 0.25, root, 44 + 6 * i)

        # The frame drum: dum on 1, tek on the and of 1 and on the and of 2, dum on 3, tek
        # on 4; the cabasa's eighths, soft, in the last section; a fill at each section's end.
        add("drums", bar, 1, 0.25, LOW_CONGA, 100)
        add("drums", bar, 1.5, 0.25, MUTE_HI_CONGA, 66)
        add("drums", bar, 2.5, 0.25, MUTE_HI_CONGA, 72)
        add("drums", bar, 3, 0.25, LOW_CONGA, 90)
        add("drums", bar, 4, 0.25, MUTE_HI_CONGA, 70)
        if bar % 8 == 7:
            for i, beat in enumerate((3.5, 4, 4.25, 4.5, 4.75)):
                add("drums", bar, beat, 0.2, OPEN_HI_CONGA if i % 2 else MUTE_HI_CONGA, 64 + 6 * i)
            add("drums", bar, 4.5, 0.4, LOW_FLOOR_TOM, 88)
        else:
            add("drums", bar, 4.5, 0.25, OPEN_HI_CONGA, 58)
        if section == 3:
            for i in range(8):
                add("drums", bar, 1 + i * 0.5, 0.2, CABASA, 34 if i % 2 else 42)

        # A bell on the root at the start of each section, an octave lower than it was.
        if bar % 8 == 0:
            add("bell", bar, 1, 3, root + 36, 60)
    return notes


if __name__ == "__main__":
    run(__doc__, compose, PARTS, BARS, BEAT_US, loudness=-14.0)
