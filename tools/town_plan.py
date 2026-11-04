#!/usr/bin/env python3
"""Draw the settlement's town (data/blueprints/town.txt): its plan 0 and plan 1, 64 columns by 25
rows, from the quarters below. The header and legend stay hand-written in the blueprint; this
rewrites everything from `plan 0` on.

    tools/town_plan.py          rewrite the plans
    tools/town_plan.py --print  print them instead
"""
import sys
from pathlib import Path

W, H = 64, 25
g = [['.'] * W for _ in range(H)]
for c in range(W):
    g[0][c] = '#'; g[H-1][c] = '#'
for r in range(H):
    g[r][0] = '#'; g[r][W-1] = '#'
def fill(ch, r0, r1, c0, c1):
    for r in range(r0, r1+1):
        for c in range(c0, c1+1):
            g[r][c] = ch
# Gates, west and east, rows 9..11.
fill('w', 9, 11, 0, 0); fill('e', 9, 11, W-1, W-1)
# Temple (NW): floor zone, east wall shared with the recess, dais at the back.
fill('q', 1, 7, 1, 20)
fill('%', 1, 2, 4, 17); fill(':', 3, 3, 4, 17); fill('a', 1, 2, 10, 11)
for c0 in (2, 10, 18):
    fill('o', 8, 8, c0, c0+1)
# Descent recess: walls either side, exit at the back before the painted arch.
fill('#', 1, 5, 21, 24); fill('#', 1, 5, 31, 34)
fill('A', 0, 0, 25, 30); fill('X', 1, 2, 25, 30)
# Hall (NE): tables, pillars along its front.
# Both tables are one row deep and 3 m across, so the player can talk to the quest-giver across
# the first from anywhere in front.
fill('t', 3, 3, 41, 46); fill('t', 3, 3, 51, 56)
for c0 in (38, 46, 54):
    fill('o', 8, 8, c0, c0+1)
# Yard (SW): a low fence with a gap, dummies.
fill('f', 15, 15, 1, 19); fill('.', 15, 15, 8, 11); fill('f', 15, 23, 19, 19)
for (r, c0) in ((19, 5), (19, 13), (21, 9)):
    fill('d', r, r, c0, c0+1)
# Market (centre south): zone floor, a U-shaped counter.
fill('m', 15, 23, 20, 42)
fill('k', 19, 19, 26, 37); fill('k', 20, 21, 26, 27); fill('k', 20, 21, 36, 37)
# Barracks (SE): a wall with a doorway, beds.
fill('#', 15, 15, 43, 62); fill('.', 15, 15, 50, 55); fill('#', 15, 23, 43, 43)
# Beds against the south wall and in a row with wide aisles: a passage under 1.5 m has no nav cell.
for c0 in (46, 52, 58):
    fill('b', 23, 23, c0, c0+3)
for c0 in (46, 56):
    fill('b', 18, 18, c0, c0+3)
# Townsfolk: the priest beside the dais, the shopkeeper inside the counter, the trainer in the
# yard, the quest-giver behind the hall's first table, guards at the gates and the recess, the
# barracks' off-duty guard, commoners about the plaza, and the sacked town's survivors.
fill('p', 4, 4, 18, 19)
fill('S', 20, 20, 31, 32)
fill('R', 17, 17, 9, 10)
fill('Q', 2, 2, 43, 44)
fill('G', 8, 8, 4, 5); fill('H', 12, 12, 4, 5)
fill('J', 8, 8, 58, 59); fill('K', 12, 12, 58, 59)
fill('L', 6, 6, 22, 23); fill('M', 6, 6, 32, 33)
fill('N', 20, 20, 52, 53)
fill('c', 10, 10, 26, 27); fill('c', 13, 13, 44, 45); fill('c', 17, 17, 38, 39)
fill('v', 16, 16, 30, 31); fill('v', 5, 5, 10, 11)
# Monsters in a sacked town's streets.
fill('x', 10, 10, 16, 17); fill('x', 11, 11, 48, 49); fill('x', 21, 21, 12, 13); fill('x', 6, 6, 50, 51)
# Where a sacked town's loot lies.
fill('$', 22, 22, 22, 23); fill('$', 2, 2, 60, 61); fill('$', 20, 20, 60, 61); fill('$', 22, 22, 2, 3)
# Arrival in the plaza.
fill('@', 12, 13, 31, 32)
# Torches: on the outer walls and either side of the recess.
for (r, c) in ((0, 4), (0, 17), (0, 42), (0, 56), (6, 0), (14, 0), (6, W-1), (14, W-1),
               (H-1, 6), (H-1, 14), (H-1, 24), (H-1, 39), (H-1, 52)):
    g[r][c] = 'T'
g[5][20] = 'T'          # temple side of the recess wall, inside the temple
g[3][35] = 'T'          # hall side of the recess wall
plan0 = [''.join(row) for row in g]
p1 = [[' '] * W for _ in range(H)]
for c in range(W):
    p1[0][c] = '#'; p1[H-1][c] = '#'
for r in range(H):
    p1[r][0] = '#'; p1[r][W-1] = '#'
for r in range(H):
    for c in range(W):
        if g[r][c] == 'o':
            p1[r][c] = 'P'
plan1 = [''.join(row) for row in p1]
text = 'plan 0\n' + '\n'.join(plan0) + '\n\nplan 1\n' + '\n'.join(plan1) + '\n'
if '--print' in sys.argv:
    print(text, end='')
else:
    path = Path(__file__).resolve().parent.parent / 'data' / 'blueprints' / 'town.txt'
    head = path.read_text()
    path.write_text(head[:head.index('plan 0')] + text)
