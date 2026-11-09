#!/usr/bin/env python3
"""Draw the cave blocks' plans, every edge at 0 or 45 degrees, into their blueprints.

    tools/cave_plans.py                 redraw every cave block's plan
    tools/cave_plans.py cave grotto     redraw these
    tools/cave_plans.py --check         only say which plans differ from their blueprints

A blueprint's header and legend are written by hand; this replaces the rows after its
`plan 0` line. Each spec below starts from rock and draws, in order:

- the room's outline: OUTLINE(L, R), the first open and first rock column at each row
  boundary (rows 1 to the last but one). Where a line moves 2 columns from one boundary to
  the next, that row gets a 45-degree pair, `/` or `\\`; it can't move 1, or 3.
- regions inside it: REGION(top row, L, R, fill, pairs), the same for a pool, pit, shelf,
  hanging rock, causeway or bridge, with its own pair characters. Rock already there stays.
- rock in lava: LAVA_ROCK turns a rock pair with lava beside it into `<` or `>`, which stand
  in the lava.
- doorways: put strings on the border. A wide river doorway is `RRRR======RRRR` on a north or
  south face and `RR===RR` on an east or west one; a stream's, all lava, `------` and `---`;
  an ice cave's `++++++` and `+++`; a frozen river's `FFFFffffffFFFF` and `FFfffFF` (bank, then
  its sunken ice), a slide's `||||||` and `|||`.
- pickup spots: put `$$` (floor) or `&&` (reward) where the blueprint's legend says what they are.

Ice caves: their floor is snow, and a frozen pond (`_`) is sunk 0.2 m into it, a REGION with
POND's shore pairs. POND_ROCK turns rock pairs beside it into `<` and `>`, standing in it,
HANG_OVER hangs icicles that keep the pond under them, HANG_DIAMOND hangs a diamond of ice
from a corridor's ceiling, and FROST_LINE turns an ice gate from rock to ice along a 45-degree
line across the way, a drift of snow over the join. Nothing in a cave is a rectangle.

Water caves (the creek, a cave river of water) are two storeys, so their specs return a plan
per storey, `{0: g0, 1: g1}`: the water fills the lower one, the banks are the upper one's
floor. CHANNEL draws the river's outline in both, open (` `) above and water (`~`) below, each
45-degree pair below rock standing in the water (`<`, `>`) whose top is the bank's floor; CARVE
cuts water into the lower storey's rock alone, under a bank; WATER_ROCK turns a rock pair above
with the channel beside it into rock over water (`(`, `)` above, `<`, `>` below). CREEK_DOOR
and RILL_DOOR draw a doorway in both: its banks and open middle above, the water through the
wall under it.

Then `tools/blueprint NAME` builds the block, and in the game `(check-kit '("NAME"))` checks
its doorways and monsters reach each other.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROCK = set('#<>/\\AB1234PQ%79HJKLqpbd')

POOL = {'/': '(', '\\': ')'}
PIT = {'/': '[', '\\': ']'}
SHELF = {'/': '{', '\\': '}'}
HANG = {'/': 'A', '\\': 'B'}
POND = {'/': '[', '\\': ']'}
WIDE_NS, WIDE_EW = 'RRRR======RRRR', 'RR===RR'
NARROW_NS, NARROW_EW = '------', '---'


WATER_ROCK = {'/': '<', '\\': '>'}
OPEN = {'/': ' ', '\\': ' '}
CREEK_NS, CREEK_EW = ('BBBBCCCCCCBBBB', '####~~~~~~####'), ('BBCCCBB', '##~~~##')
RILL_NS, RILL_EW = ('------', '~~~~~~'), ('---', '~~~')
FROZEN_NS, FROZEN_EW = 'FFFFffffffFFFF', 'FFfffFF'
SLIDE_NS, SLIDE_EW = '||||||', '|||'


def blank(wide, deep):
    """A plan of WIDE by DEEP cells, all rock."""
    return [['#'] * (wide * 8) for _ in range(deep * 4 + 1)]


def edges(L, R, r0):
    """Per row from R0: (row, first open column, first rock column, left pair, right pair)."""
    out = []
    for i in range(len(L) - 1):
        lt, lb, rt, rb = L[i], L[i + 1], R[i], R[i + 1]
        if abs(lt - lb) not in (0, 2) or abs(rt - rb) not in (0, 2):
            raise ValueError("row %d: an edge moves %d or %d columns; only 0 or 2" % (r0 + i, lb - lt, rb - rt))
        left = lt if lt == lb else min(lt, lb) + 2
        right = rt if rt == rb else max(rt, rb) - 2
        lp = None if lt == lb else (min(lt, lb), '/' if lb < lt else '\\')
        rp = None if rt == rb else (min(rt, rb), '\\' if rb > rt else '/')
        out.append((r0 + i, left, right, lp, rp))
    return out


def outline(g, L, R, fill='.'):
    for r, a, b, lp, rp in edges(L, R, 1):
        for c in range(a, b):
            g[r][c] = fill
        for p in (lp, rp):
            if p:
                g[r][p[0]] = g[r][p[0] + 1] = p[1]


def region(g, r0, L, R, fill, pairs):
    for r, a, b, lp, rp in edges(L, R, r0):
        for c in range(a, b):
            if g[r][c] not in ROCK:
                g[r][c] = fill
        for p in (lp, rp):
            if p and g[r][p[0]] not in ROCK and g[r][p[0] + 1] not in ROCK:
                g[r][p[0]] = g[r][p[0] + 1] = pairs[p[1]]


def put(g, r, c, s):
    for k, ch in enumerate(s):
        g[r][c + k] = ch


def down(g, c, r, s):
    for k, ch in enumerate(s):
        g[r + k][c] = ch


def fill(g, rows, cols, ch):
    for r in rows:
        for c in cols:
            g[r][c] = ch


def lava_rock(g):
    for r in range(len(g)):
        c = 0
        while c < len(g[0]) - 1:
            ch = g[r][c]
            if ch in '/\\' and g[r][c + 1] == ch:
                east = g[r][c + 2] if c + 2 < len(g[0]) else '#'
                west = g[r][c - 1] if c > 0 else '#'
                if '~' in (east, west):
                    g[r][c] = g[r][c + 1] = '<' if ch == '/' else '>'
                c += 2
            else:
                c += 1


def pond_rock(g):
    """Rock pairs beside the frozen pond stand in it: `<` and `>`, ice in their open half."""
    for r in range(len(g)):
        c = 0
        while c < len(g[0]) - 1:
            ch = g[r][c]
            if ch in '/\\' and g[r][c + 1] == ch:
                east = g[r][c + 2] if c + 2 < len(g[0]) else '#'
                west = g[r][c - 1] if c > 0 else '#'
                if '_' in (east, west):
                    g[r][c] = g[r][c + 1] = '<' if ch == '/' else '>'
                c += 2
            else:
                c += 1


def hang_over(g, r0, L, R):
    """Icicles hanging over a region as REGION draws one, `v A B`; over the pond `x P Q`,
    which keep its sunken ice under them."""
    for r, a, b, lp, rp in edges(L, R, r0):
        for c in range(a, b):
            if g[r][c] not in ROCK:
                g[r][c] = 'x' if g[r][c] == '_' else 'v'
        for p in (lp, rp):
            if p and g[r][p[0]] not in ROCK and g[r][p[0] + 1] not in ROCK:
                pond = g[r][p[0]] == '_' and g[r][p[0] + 1] == '_'
                g[r][p[0]] = g[r][p[0] + 1] = ('PQ' if pond else 'AB')[0 if p[1] == '/' else 1]


def frost_line(g, k, w=4):
    """Rock gives way to ice along a 45-degree line across the way, the cells where c + 2r is
    K: before it rock walls and cave floor, beyond it ice-rock walls (`%`, `7`, `9`) and an
    ice floor (`_`), and across it a drift of snow W columns wide (`~`) with 45-degree edges,
    `{` on the rock side and `}` on the ice side, so nothing meets in a straight row. A 45-degree
    wall shows the floor of its cell in its open half, so each takes its zone's: cave floor
    before the drift, snow beside it (`q p` rock, `b d` ice-rock), ice beyond it."""
    for r in range(len(g)):
        a = k - 2 * r
        c = 0
        while c < len(g[0]):
            ch = g[r][c]
            if ch in '#/\\':
                n = 2 if ch in '/\\' and c + 1 < len(g[0]) and g[r][c + 1] == ch else 1
                ice = c + 2 * r >= k + w // 2
                if n == 2 and c + 1 < a - 2:
                    new = ch
                elif n == 2 and c >= a + w + 2:
                    new = {'/': '7', '\\': '9'}[ch]
                elif n == 2:
                    new = {('/', False): 'q', ('\\', False): 'p', ('/', True): 'b', ('\\', True): 'd'}[(ch, ice)]
                else:
                    new = '%' if ice else '#'
                for i in range(n):
                    g[r][c + i] = new
                c += n
                continue
            if ch == '.':
                if a - 2 <= c < a:
                    g[r][c] = '{'
                elif a <= c < a + w:
                    g[r][c] = '~'
                elif a + w <= c < a + w + 2:
                    g[r][c] = '}'
                elif c >= a + w + 2:
                    g[r][c] = '_'
            c += 1
    # An edge cut short by a wall, half a pair, is drift.
    for r in range(len(g)):
        for c in range(len(g[0])):
            if g[r][c] in '{}' and not ((c + 1 < len(g[0]) and g[r][c + 1] == g[r][c]) or
                                         (c > 0 and g[r][c - 1] == g[r][c])):
                g[r][c] = '~'


def hang_diamond(g, r, c):
    """A diamond of ice hanging from a 3 m ceiling, 2 m across, low enough to pass under."""
    put(g, r, c, 'HHJJ')
    put(g, r + 1, c, 'KKLL')


def octagon_pillar(g, r, c):
    for k, s in enumerate(('//##\\\\', '######', '\\\\##//')):
        put(g, r + k, c, s)


def diamond(g, r, c):
    put(g, r, c, '1122')
    put(g, r + 1, c, '3344')


def carve(g, r0, L, R, fill, pairs):
    """REGION's shape cut into anything, rock too: every cell in it FILL, its pairs PAIRS."""
    for r, a, b, lp, rp in edges(L, R, r0):
        for c in range(a, b):
            g[r][c] = fill
        for p in (lp, rp):
            if p:
                g[r][p[0]] = g[r][p[0] + 1] = pairs[p[1]]


def channel(g0, g1, r0, L, R):
    """A creek's channel: open in the upper plan G1, water in the lower plan G0."""
    region(g1, r0, L, R, ' ', OPEN)
    carve(g0, r0, L, R, '~', WATER_ROCK)


def water_rock(g0, g1):
    """Rock pairs in G1 with the open channel beside them stand in the water: rock over the
    water above (`(`, `)`), rock in it below (`<`, `>`)."""
    rows, cols = len(g1), len(g1[0])
    for r in range(rows):
        c = 0
        while c < cols - 1:
            ch = g1[r][c]
            if ch in '/\\' and g1[r][c + 1] == ch:
                around = [g1[r][c - 1] if c > 0 else '#', g1[r][c + 2] if c + 2 < cols else '#']
                around += [g1[rr][cc] for rr in (r - 1, r + 1) if 0 <= rr < rows for cc in (c, c + 1)]
                if ' ' in around:
                    g1[r][c] = g1[r][c + 1] = '(' if ch == '/' else ')'
                    g0[r][c] = g0[r][c + 1] = WATER_ROCK[ch]
                c += 2
            else:
                c += 1


def creek_door(g0, g1, r, c, down=False, rill=False):
    """A creek's doorway (or a rill's) at row R, column C, across or (DOWN) along the border."""
    above, below = (RILL_EW if down else RILL_NS) if rill else (CREEK_EW if down else CREEK_NS)
    (down_ if down else put)(g1, r, c, above)
    (down_ if down else put)(g0, r, c, below)


def down_(g, r, c, s):
    down(g, c, r, s)


# The caves. Each returns its plan.

def cave():
    g = blank(3, 3)
    put(g, 0, 9, 'nnnnnn'); put(g, 12, 9, 'ssssss'); down(g, 0, 5, 'www'); down(g, 23, 5, 'eee')
    outline(g, L=[7, 5, 5, 3, 1, 1, 1, 1, 3, 3, 5, 7], R=[17, 19, 21, 21, 23, 23, 23, 23, 21, 19, 19, 17])
    region(g, 3, L=[5, 3, 3, 5, 7], R=[10, 12, 12, 12, 10], fill='~', pairs=POOL)
    region(g, 7, L=[7, 5, 5, 7], R=[9, 11, 11, 9], fill='o', pairs=PIT)
    region(g, 2, L=[15, 13, 13, 15], R=[17, 19, 19, 17], fill=',', pairs=SHELF)
    region(g, 5, L=[17, 15, 15, 17], R=[19, 21, 21, 19], fill='v', pairs=HANG)
    octagon_pillar(g, 8, 11)
    put(g, 6, 12, 'ii'); put(g, 2, 9, 'mm'); put(g, 6, 21, 'mm'); g[0][8] = 'T'; g[12][15] = 'T'
    put(g, 3, 15, '&&'); put(g, 10, 7, '$$'); put(g, 9, 17, '$$')
    lava_rock(g)
    return g


def lava_lake():
    g = blank(3, 3)
    put(g, 0, 9, 'nnnnnn'); put(g, 12, 9, 'ssssss'); down(g, 23, 5, 'eee')
    outline(g, L=[7, 5, 3, 3, 1, 1, 3, 3, 1, 3, 5, 7], R=[17, 19, 21, 21, 23, 23, 23, 23, 21, 21, 19, 17], fill='~')
    region(g, 1, L=[9, 9, 7, 7, 9, 9, 9, 11, 11, 11, 9, 9], R=[15, 15, 13, 13, 15, 15, 15, 15, 15, 15, 15, 15],
           fill='.', pairs=POOL)
    fill(g, [6], range(15, 23), '.')
    region(g, 5, L=[21, 19, 19, 21], R=[23, 23, 23, 23], fill='.', pairs=POOL)
    put(g, 4, 9, 'vv'); put(g, 6, 16, 'ii'); put(g, 3, 9, 'mm'); put(g, 10, 12, 'mm')
    put(g, 1, 11, '$$'); put(g, 8, 12, '&&')
    g[0][8] = 'T'; g[12][15] = 'T'; g[5][0] = 'T'
    lava_rock(g)
    return g


def cave_passage():
    g = blank(2, 2)
    put(g, 0, 1, 'nnnnnn'); put(g, 8, 9, 'ssssss')
    outline(g, L=[1, 1, 3, 5, 7, 9, 9, 9], R=[7, 9, 11, 13, 15, 15, 15, 15])
    put(g, 3, 7, 'vv'); put(g, 4, 8, 'vv'); put(g, 6, 11, ',,')
    return g


def grotto():
    g = blank(2, 2)
    put(g, 0, 9, 'nnnnnn'); down(g, 0, 5, 'www')
    outline(g, L=[5, 3, 1, 1, 1, 1, 1, 1], R=[15, 15, 15, 15, 15, 15, 13, 11])
    diamond(g, 3, 6)
    put(g, 6, 9, 'ii'); put(g, 5, 2, 'mm'); put(g, 2, 12, 'mm')
    put(g, 3, 12, '$$'); put(g, 6, 3, '$$')
    return g


def cavern():
    g = blank(4, 3)
    put(g, 0, 9, 'nnnnnn'); put(g, 12, 17, 'ssssss'); down(g, 0, 5, 'www'); down(g, 31, 5, 'eee')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[23, 25, 27, 29, 31, 31, 31, 31, 29, 27, 25, 23])
    octagon_pillar(g, 3, 8)
    octagon_pillar(g, 7, 19)
    region(g, 2, L=[17, 15, 15, 17], R=[21, 23, 23, 21], fill=',', pairs=SHELF)
    region(g, 7, L=[9, 7, 7, 9], R=[11, 13, 13, 11], fill='v', pairs=HANG)
    put(g, 6, 15, 'ii'); put(g, 9, 13, 'jj'); put(g, 3, 24, 'mm'); put(g, 6, 4, 'MM')
    put(g, 3, 18, '&&'); put(g, 4, 3, '$$'); put(g, 8, 26, '$$')
    return g


def cave_bend():
    g = blank(2, 2)
    put(g, 0, 1, 'nnnnnn'); down(g, 15, 5, 'eee')
    outline(g, L=[1, 1, 1, 3, 5, 7, 7, 7], R=[7, 9, 11, 13, 15, 15, 15, 15])
    return g


def cave_fork():
    g = blank(2, 2)
    put(g, 0, 1, 'nnnnnn'); put(g, 8, 9, 'ssssss'); down(g, 15, 1, 'eee')
    outline(g, L=[1, 1, 1, 3, 5, 7, 9, 9], R=[15] * 8)
    # In the wide part: beside it every way through is at least 1.5 m, which the nav
    # grid's 0.5 m cells need to fit a body through.
    diamond(g, 2, 8)
    return g


def lava_chasm():
    g = blank(3, 3)
    put(g, 0, 9, 'nnnnnn'); put(g, 12, 9, 'ssssss'); down(g, 0, 1, 'www'); down(g, 23, 9, 'eee')
    outline(g, L=[1, 1, 1, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[17, 19, 21, 23, 23, 23, 23, 23, 23, 23, 23, 23])
    region(g, 5, L=[1, 1, 1, 1], R=[23, 23, 23, 23], fill='~', pairs=POOL)
    region(g, 5, L=[9, 11, 13, 15], R=[13, 15, 17, 19], fill='.', pairs=POOL)
    put(g, 9, 17, 'ii'); put(g, 3, 13, 'mm'); put(g, 10, 9, 'mm')
    put(g, 2, 3, '$$'); put(g, 8, 4, '&&')
    lava_rock(g)
    return g


def magma_pool():
    g = blank(3, 3)
    put(g, 0, 9, 'nnnnnn'); down(g, 0, 5, 'www'); down(g, 23, 5, 'eee')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[17, 19, 21, 23, 23, 23, 23, 23, 21, 19, 17, 15])
    region(g, 3, L=[9, 7, 5, 5, 5, 5, 7, 9], R=[15, 17, 19, 19, 19, 19, 17, 15], fill='~', pairs=POOL)
    region(g, 5, L=[11, 9, 9, 11], R=[13, 15, 15, 13], fill='.', pairs=POOL)
    fill(g, [1, 2, 3, 4], [11, 12], '.')
    put(g, 6, 11, 'ii'); put(g, 6, 20, 'mm'); put(g, 10, 11, 'mm')
    put(g, 7, 11, '&&'); put(g, 4, 2, '$$'); put(g, 4, 20, '$$')
    lava_rock(g)
    return g


def river():
    g = blank(2, 2)
    put(g, 0, 1, WIDE_NS); put(g, 8, 1, WIDE_NS); down(g, 0, 5, 'www')
    outline(g, L=[1] * 8, R=[15, 15, 15, 13, 13, 15, 15, 15])
    fill(g, range(1, 8), range(5, 11), '~')
    put(g, 2, 2, '$$')
    return g


def river_ford():
    g = blank(2, 3)
    down(g, 0, 5, WIDE_EW); down(g, 15, 5, WIDE_EW); put(g, 0, 1, 'nnnnnn'); put(g, 12, 9, 'ssssss')
    outline(g, L=[1] * 12, R=[7, 9, 11, 13, 15, 15, 15, 15, 15, 15, 15, 15])
    fill(g, (7, 8, 9), range(1, 15), '~')
    fill(g, (7, 8, 9), range(6, 10), '.')
    put(g, 2, 2, '$$')
    return g


def river_bend():
    g = blank(3, 3)
    put(g, 12, 9, WIDE_NS); down(g, 23, 1, WIDE_EW); down(g, 0, 5, 'www')
    outline(g, L=[9] * 12, R=[23] * 12)
    fill(g, (5, 6, 7), range(1, 9), '.')
    region(g, 3, L=[17, 15, 13, 13, 13, 13, 13, 13, 13, 13], R=[23, 23, 23, 23, 21, 19, 19, 19, 19, 19],
           fill='~', pairs=POOL)
    return g


def river_cavern():
    g = blank(3, 4)
    put(g, 0, 9, WIDE_NS); put(g, 16, 9, WIDE_NS); down(g, 0, 5, 'www'); down(g, 23, 9, 'eee')
    outline(g, L=[9, 7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9, 9, 9, 9], R=[23] * 16)
    region(g, 1, L=[13, 13, 13, 13, 11, 11, 11, 11, 13, 13, 13, 13, 13, 13, 13, 13],
           R=[19, 19, 19, 19, 17, 17, 17, 17, 19, 19, 19, 19, 19, 19, 19, 19], fill='~', pairs=POOL)
    fill(g, (11, 12), range(13, 19), '.')
    put(g, 4, 5, 'ii'); put(g, 13, 20, 'jj'); put(g, 9, 7, 'mm'); put(g, 4, 20, 'MM')
    return g


def stream():
    # Lava wall to wall: no bank to walk, so wading it is the only way along.
    g = blank(1, 2)
    put(g, 0, 1, NARROW_NS); put(g, 8, 1, NARROW_NS); down(g, 0, 5, 'www')
    outline(g, L=[1] * 8, R=[7] * 8, fill='~')
    return g


def stream_bend():
    g = blank(2, 2)
    put(g, 8, 9, NARROW_NS); down(g, 0, 1, NARROW_EW)
    outline(g, L=[1] * 8, R=[15] * 8, fill='~')
    fill(g, range(4, 8), range(1, 9), '#')
    # 45-degree rock on the bend's outer and inner corners.
    put(g, 1, 13, '\\\\'); put(g, 4, 7, '\\\\')
    lava_rock(g)
    return g


def river_narrows():
    g = blank(2, 3)
    # A one-cell doorway sits in one cell, so the river narrows toward the east one: the
    # banks run out and its last cell is lava wall to wall.
    put(g, 12, 1, WIDE_NS); put(g, 0, 9, NARROW_NS)
    outline(g, L=[9, 9, 9, 9, 9, 7, 5, 3, 1, 1, 1, 1], R=[15] * 12)
    region(g, 1, L=[9, 9, 9, 9, 9, 7, 5, 5, 5, 5, 5, 5], R=[15, 15, 15, 15, 15, 13, 11, 11, 11, 11, 11, 11],
           fill='~', pairs=POOL)
    lava_rock(g)
    put(g, 7, 3, '//')  # the west bank's tip, dry
    return g


def lava_spring():
    g = blank(3, 3)
    put(g, 12, 9, WIDE_NS); put(g, 0, 9, 'nnnnnn'); down(g, 0, 5, 'www')
    # The east bank runs straight up into the room, 2 m wide, so both banks join here.
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[19, 21, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23])
    region(g, 3, L=[13, 11, 11, 11, 11, 13, 13, 13, 13, 13], R=[17, 19, 19, 19, 19, 19, 19, 19, 19, 19],
           fill='~', pairs=POOL)
    put(g, 6, 5, 'ii'); put(g, 2, 12, 'mm'); put(g, 9, 20, 'mm')
    lava_rock(g)
    return g


def lava_sink():
    g = blank(3, 3)
    put(g, 0, 9, WIDE_NS); down(g, 0, 5, 'www'); down(g, 23, 5, 'eee')
    outline(g, L=[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 5], R=[23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 21, 19])
    region(g, 1, L=[13, 13, 13, 11, 9, 7, 7, 9, 11], R=[19, 19, 19, 21, 21, 21, 21, 21, 19], fill='~', pairs=POOL)
    lava_rock(g)
    return g


def stream_spring():
    g = blank(2, 2)
    put(g, 8, 9, NARROW_NS); put(g, 0, 1, 'nnnnnn'); down(g, 0, 5, 'www')
    outline(g, L=[1] * 8, R=[11, 13, 15, 15, 15, 15, 15, 15])
    # The stream comes in wall to wall for 3 m before the pool opens out.
    region(g, 2, L=[9, 7, 7, 9, 9, 9, 9], R=[13, 15, 15, 15, 15, 15, 15], fill='~', pairs=POOL)
    fill(g, (5, 6, 7), [8], '#')
    lava_rock(g)
    return g


# Ice caves: walls of ice, a floor of snow, frozen ponds. Their doorways are all ice, so
# they join only each other and the ice gates, half rock and half ice, that lead to caves.

def ice_grotto():
    g = blank(2, 2)
    put(g, 0, 9, '++++++'); down(g, 0, 5, '+++')
    outline(g, L=[5, 3, 1, 1, 1, 1, 1, 1], R=[15, 15, 15, 15, 15, 15, 13, 11])
    region(g, 2, L=[8, 6, 4, 4, 6], R=[10, 12, 14, 14, 12], fill='_', pairs=POND)
    diamond(g, 3, 8)
    put(g, 6, 9, 'ii'); put(g, 1, 12, 'mm'); put(g, 3, 2, 'mm')
    put(g, 4, 5, '&&'); put(g, 6, 3, '$$')
    return g


def ice_lake():
    g = blank(3, 3)
    put(g, 0, 9, '++++++'); put(g, 12, 9, '++++++'); down(g, 0, 5, '+++'); down(g, 23, 5, '+++')
    outline(g, L=[7, 5, 3, 3, 1, 1, 1, 1, 3, 3, 5, 7], R=[17, 19, 21, 21, 23, 23, 23, 23, 21, 21, 19, 17])
    region(g, 2, L=[9, 7, 5, 5, 5, 5, 5, 7, 9], R=[15, 17, 19, 19, 19, 19, 19, 17, 15], fill='_', pairs=POND)
    hang_over(g, 4, L=[9, 7, 7, 9], R=[11, 13, 13, 11])
    hang_over(g, 5, L=[15, 13, 13, 15], R=[17, 19, 19, 17])
    put(g, 8, 11, 'kk'); put(g, 3, 14, 'mm'); put(g, 5, 5, 'mm'); g[0][8] = 'T'; g[12][15] = 'T'
    put(g, 7, 8, '&&'); put(g, 9, 4, '$$'); put(g, 9, 18, '$$')
    return g


def ice_sheet():
    # One sheet of ice from wall to wall, snow only at each doorway to stop on: no shore, so
    # what is knocked across it slides into the rock. Narrow, 2 by 3 cells, so its side walls
    # are near, its north and south doorways on opposite cells; icicles hang over it.
    g = blank(2, 3)
    put(g, 0, 1, '++++++'); put(g, 12, 9, '++++++'); down(g, 0, 5, '+++'); down(g, 15, 5, '+++')
    outline(g, L=[1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 5, 7], R=[9, 11, 13, 15, 15, 15, 15, 15, 15, 15, 15, 15], fill='_')
    fill(g, [1], range(1, 7), '.'); fill(g, [11], range(9, 15), '.')
    fill(g, [5, 6, 7], [1, 2], '.'); fill(g, [5, 6, 7], [13, 14], '.')
    hang_over(g, 2, L=[9, 7, 7, 9], R=[11, 13, 13, 11])
    hang_over(g, 7, L=[5, 3, 3, 5], R=[7, 9, 9, 7])
    put(g, 6, 7, 'kk'); put(g, 3, 4, 'mm'); put(g, 9, 11, 'mm'); g[0][7] = 'T'; g[12][8] = 'T'
    put(g, 9, 3, '&&'); put(g, 1, 2, '$$'); put(g, 11, 11, '$$')
    pond_rock(g)
    return g


def ice_cavern():
    g = blank(4, 3)
    put(g, 0, 9, '++++++'); put(g, 12, 17, '++++++'); down(g, 0, 5, '+++'); down(g, 31, 5, '+++')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[23, 25, 27, 29, 31, 31, 31, 31, 29, 27, 25, 23])
    octagon_pillar(g, 3, 6)
    region(g, 5, L=[17, 15, 13, 13, 15, 17], R=[23, 25, 25, 25, 25, 23], fill='_', pairs=POND)
    octagon_pillar(g, 6, 17)
    region(g, 2, L=[17, 15, 15, 17], R=[21, 23, 23, 21], fill=',', pairs=SHELF)
    region(g, 7, L=[7, 5, 5, 7], R=[9, 11, 11, 9], fill='v', pairs=HANG)
    put(g, 4, 12, 'ii'); put(g, 3, 19, 'jj'); put(g, 10, 12, 'mm'); put(g, 5, 27, 'MM'); g[0][20] = 'T'; g[12][11] = 'T'
    put(g, 3, 16, '&&'); put(g, 4, 2, '$$'); put(g, 8, 26, '$$')
    pond_rock(g)
    return g


def ice_passage():
    g = blank(2, 2)
    put(g, 0, 1, '++++++'); put(g, 8, 9, '++++++')
    outline(g, L=[1, 1, 3, 5, 7, 9, 9, 9], R=[7, 9, 11, 13, 15, 15, 15, 15], fill='_')
    hang_diamond(g, 3, 7)
    return g


def ice_bend():
    g = blank(2, 2)
    put(g, 0, 1, '++++++'); down(g, 15, 5, '+++')
    outline(g, L=[1, 1, 1, 3, 5, 7, 7, 7], R=[7, 9, 11, 13, 15, 15, 15, 15], fill='_')
    return g


def ice_gate():
    g = blank(2, 2)
    put(g, 0, 1, 'nnnnnn'); put(g, 8, 9, '++++++')
    outline(g, L=[1, 1, 3, 5, 7, 9, 9, 9], R=[7, 9, 11, 13, 15, 15, 15, 15])
    frost_line(g, 14)
    hang_diamond(g, 6, 10)
    return g


def ice_gate_bend():
    g = blank(2, 2)
    put(g, 0, 1, 'nnnnnn'); down(g, 15, 5, '+++')
    outline(g, L=[1, 1, 1, 3, 5, 7, 7, 7], R=[7, 9, 11, 13, 15, 15, 15, 15])
    frost_line(g, 12)
    hang_diamond(g, 5, 9)
    return g


def ice_chute():
    # Three cells of ice that wind a little, 45 degrees at a time, snow at each doorway.
    g = blank(1, 3)
    put(g, 0, 1, '++++++'); put(g, 12, 1, '++++++')
    outline(g, L=[1, 1, 1, 3, 3, 3, 1, 1, 1, 1, 1, 1], R=[7, 7, 7, 7, 7, 7, 7, 5, 5, 5, 7, 7], fill='_')
    fill(g, [1, 11], range(1, 7), '.')
    return g


def ice_niche():
    g = blank(1, 1)
    put(g, 0, 1, '++++++')
    outline(g, L=[1, 1, 1, 3], R=[7, 7, 7, 5], fill='_')
    fill(g, [1], range(1, 7), '.')
    put(g, 2, 3, 'kk'); put(g, 1, 1, 'mm'); put(g, 1, 5, 'mm')
    return g


def frost_shrine():
    # An octagonal hall in the ice: a dais of ice, octagonal, on a step, a frozen pond
    # before it, and two ice columns either side of the pond.
    g = blank(3, 3)
    put(g, 12, 9, '++++++'); down(g, 0, 5, '+++'); down(g, 23, 5, '+++')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 1, 3, 5, 7], R=[17, 19, 21, 23, 23, 23, 23, 23, 23, 21, 19, 17])
    region(g, 1, L=[7, 5, 5, 7], R=[17, 19, 19, 17], fill=':', pairs={'/': '[', '\\': ']'})
    region(g, 1, L=[9, 7, 7, 9], R=[15, 17, 17, 15], fill='%', pairs={'/': '(', '\\': ')'})
    put(g, 2, 11, 'II'); put(g, 7, 3, 'mm'); put(g, 7, 19, 'mm')
    put(g, 2, 8, '&&'); put(g, 2, 14, '&&'); put(g, 10, 7, '$$'); put(g, 10, 15, '$$')
    region(g, 5, L=[11, 9, 7, 7, 9, 11], R=[13, 15, 17, 17, 15, 13], fill='_', pairs={'/': '{', '\\': '}'})
    diamond(g, 4, 4); diamond(g, 4, 16)
    g[4][0] = g[8][0] = g[4][23] = g[8][23] = 'T'
    return g


# Water caves: the creek. Two storeys: the water below, the banks above.

def creek():
    g0, g1 = blank(2, 2), blank(2, 2)
    creek_door(g0, g1, 0, 1); creek_door(g0, g1, 8, 1); down(g1, 0, 5, 'www')
    outline(g1, L=[1] * 8, R=[15, 15, 15, 13, 13, 15, 15, 15])
    channel(g0, g1, 1, L=[5] * 8, R=[11] * 8)
    # Under the west bank the water reaches back into the rock, a hollow with a reward.
    carve(g0, 2, L=[5, 3, 3, 5], R=[11] * 4, fill='~', pairs=WATER_ROCK)
    put(g0, 3, 3, '&&'); put(g1, 2, 2, '$$'); g1[2][0] = 'T'; g1[6][15] = 'T'
    return {0: g0, 1: g1}


def creek_bend():
    g0, g1 = blank(3, 3), blank(3, 3)
    creek_door(g0, g1, 12, 9); creek_door(g0, g1, 1, 23, down=True); down(g1, 0, 5, 'www')
    outline(g1, L=[9] * 12, R=[23] * 12)
    fill(g1, (5, 6, 7), range(1, 9), '.')
    channel(g0, g1, 3, L=[17, 15, 13, 13, 13, 13, 13, 13, 13, 13], R=[23, 23, 23, 23, 21, 19, 19, 19, 19, 19])
    # The outer bank is undercut.
    carve(g0, 8, L=[19, 19, 19, 19], R=[19, 21, 21, 19], fill='~', pairs=WATER_ROCK)
    put(g0, 9, 19, '&&'); put(g1, 9, 10, '$$'); g1[0][12] = 'T'; g1[10][23] = 'T'
    return {0: g0, 1: g1}


def creek_ford():
    g0, g1 = blank(2, 3), blank(2, 3)
    creek_door(g0, g1, 5, 0, down=True); creek_door(g0, g1, 5, 15, down=True)
    put(g1, 0, 1, 'nnnnnn'); put(g1, 12, 9, 'ssssss')
    outline(g1, L=[1] * 12, R=[7, 9, 11, 13, 15, 15, 15, 15, 15, 15, 15, 15])
    channel(g0, g1, 7, L=[1] * 4, R=[15] * 4)
    # The ford: shallows across the channel over a sill of rock, where walkers cross.
    fill(g1, (7, 8, 9), range(6, 10), ',')
    fill(g0, (7, 8, 9), range(6, 10), '#')
    put(g1, 2, 2, '$$'); g1[3][0] = 'T'; g1[12][4] = 'T'
    return {0: g0, 1: g1}


def creek_cavern():
    g0, g1 = blank(3, 4), blank(3, 4)
    creek_door(g0, g1, 0, 9); creek_door(g0, g1, 16, 9); down(g1, 0, 5, 'www'); down(g1, 23, 9, 'eee')
    outline(g1, L=[9, 7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9, 9, 9, 9], R=[23] * 16)
    channel(g0, g1, 1, L=[13, 13, 13, 13, 11, 11, 11, 11, 13, 13, 13, 13, 13, 13, 13, 13],
            R=[19, 19, 19, 19, 17, 17, 17, 17, 19, 19, 19, 19, 19, 19, 19, 19])
    # A rock arch over the river, its deck 0.6 m over the banks, two steps up to it either
    # side: a swimmer passes under it.
    fill(g1, (12, 13), range(13, 19), ':')
    fill(g1, (12, 13), range(11, 13), 'S'); fill(g1, (12, 13), range(19, 21), 'Z')
    put(g1, 4, 5, 'ii'); put(g1, 15, 20, 'jj'); put(g1, 9, 7, 'mm'); put(g1, 4, 20, 'MM')
    put(g0, 6, 13, '&&'); g1[8][0] = 'T'; g1[6][23] = 'T'
    water_rock(g0, g1)
    return {0: g0, 1: g1}


def creek_narrows():
    g0, g1 = blank(2, 3), blank(2, 3)
    creek_door(g0, g1, 12, 1); creek_door(g0, g1, 0, 9, rill=True)
    outline(g1, L=[9, 9, 9, 9, 9, 7, 5, 3, 1, 1, 1, 1], R=[15] * 12)
    channel(g0, g1, 1, L=[9, 9, 9, 9, 9, 7, 5, 5, 5, 5, 5, 5], R=[15, 15, 15, 15, 15, 13, 11, 11, 11, 11, 11, 11])
    water_rock(g0, g1)
    put(g1, 7, 3, '//')  # the west bank's tip, dry
    g1[10][0] = 'T'; g1[9][15] = 'T'
    return {0: g0, 1: g1}


def rill():
    # Water wall to wall: no bank, so it is swum.
    g0, g1 = blank(1, 2), blank(1, 2)
    creek_door(g0, g1, 0, 1, rill=True); creek_door(g0, g1, 8, 1, rill=True); down(g1, 0, 5, 'www')
    outline(g1, L=[1] * 8, R=[7] * 8, fill=' ')
    carve(g0, 1, L=[1] * 8, R=[7] * 8, fill='~', pairs=WATER_ROCK)
    g1[2][7] = 'T'
    return {0: g0, 1: g1}


def rill_sump():
    # The rill dives under the rock for 3 m, its water up to the rock, and comes up again.
    g0, g1 = blank(1, 3), blank(1, 3)
    creek_door(g0, g1, 0, 1, rill=True); creek_door(g0, g1, 12, 1, rill=True)
    outline(g1, L=[1] * 12, R=[7] * 12, fill=' ')
    carve(g0, 1, L=[1] * 12, R=[7] * 12, fill='~', pairs=WATER_ROCK)
    fill(g1, (5, 6, 7), range(1, 7), '#'); fill(g0, (5, 6, 7), range(1, 7), 'X')
    # The rock closes in at 45 degrees on one side of each of the sump's mouths, leaving 2 m.
    put(g1, 4, 1, '\\\\'); put(g1, 8, 5, '\\\\')
    water_rock(g0, g1)
    g1[2][0] = 'T'; g1[10][7] = 'T'
    return {0: g0, 1: g1}


def creek_spring():
    g0, g1 = blank(3, 3), blank(3, 3)
    creek_door(g0, g1, 12, 9); put(g1, 0, 9, 'nnnnnn'); down(g1, 0, 5, 'www')
    # The east bank runs straight up into the room, so both banks join round the pool's head.
    outline(g1, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[19, 21, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23])
    channel(g0, g1, 3, L=[13, 11, 11, 11, 11, 13, 13, 13, 13, 13], R=[17, 19, 19, 19, 19, 19, 19, 19, 19, 19])
    # The spring wells up from under the rock at the pool's head.
    carve(g0, 1, L=[13, 13, 13], R=[17, 17, 17], fill='~', pairs=WATER_ROCK)
    put(g1, 6, 5, 'ii'); put(g1, 2, 12, 'mm'); put(g1, 9, 20, 'mm'); put(g0, 1, 14, '&&')
    g1[4][0] = 'T'; g1[10][23] = 'T'
    water_rock(g0, g1)
    return {0: g0, 1: g1}


def rill_spring():
    g0, g1 = blank(2, 2), blank(2, 2)
    creek_door(g0, g1, 8, 9, rill=True); put(g1, 0, 1, 'nnnnnn'); down(g1, 0, 5, 'www')
    outline(g1, L=[1] * 8, R=[11, 13, 15, 15, 15, 15, 15, 15])
    # The rill comes in wall to wall for 3 m before the pool opens out.
    channel(g0, g1, 2, L=[9, 7, 7, 9, 9, 9, 9], R=[13, 15, 15, 15, 15, 15, 15])
    fill(g1, (5, 6, 7), [8], '#')
    water_rock(g0, g1)
    g1[2][0] = 'T'
    return {0: g0, 1: g1}


def creek_sink(sump=False):
    g0, g1 = blank(3, 3), blank(3, 3)
    creek_door(g0, g1, 0, 9); down(g1, 0, 5, 'www'); down(g1, 23, 5, 'eee')
    outline(g1, L=[1] * 10 + [3, 5], R=[23] * 10 + [21, 19])
    # The river spreads into a pool and runs on under the rock, under the walk that joins the banks.
    channel(g0, g1, 1, L=[13, 13, 13, 11, 9, 9, 11], R=[19] * 7)
    if sump:
        # Down a passage under the rock to an underwater doorway: a flooded run goes on.
        carve(g0, 7, L=[11, 9, 9, 9, 9, 9], R=[19, 17, 15, 15, 15, 15], fill='~', pairs=WATER_ROCK)
        put(g0, 12, 9, 'uuuuuu')
    else:
        # To a dead end, a hollow with a reward on its floor.
        carve(g0, 7, L=[11, 11, 13, 13], R=[19, 19, 17, 17], fill='~', pairs=WATER_ROCK)
        put(g0, 9, 14, '&&')
    put(g1, 9, 4, 'ii'); put(g1, 3, 20, 'mm'); put(g1, 10, 18, '$$')
    g1[0][5] = 'T'; g1[9][23] = 'T'; g1[8][0] = 'T'
    water_rock(g0, g1)
    return {0: g0, 1: g1}


def creek_falls():
    # Three storeys: the upper river's water in storey 1, its banks in storey 2; over a lip it
    # falls into a pool in storey 0, the lower river's banks in storey 1. A rock stair joins the
    # upper west bank to the lower; the lip is a walk across the top of the falls, and a ford
    # below joins the lower banks.
    g0, g1, g2 = blank(3, 3), blank(3, 3), blank(3, 3)
    creek_door(g1, g2, 0, 9); creek_door(g0, g1, 12, 9)
    # Upper river, storey 2: banks either side of the channel, a landing west to the stair.
    outline(g2, L=[7, 7, 7, 7, 7, 7, 9], R=[21, 23, 23, 23, 23, 23, 21])
    channel(g1, g2, 1, L=[13] * 6, R=[19] * 6)
    fill(g2, [1], range(3, 7), '.'); fill(g2, range(2, 10), range(3, 7), ' ')
    fill(g2, (6, 7), range(13, 19), ' ')  # open over the lip and the drop
    # The lip, a metre wide, holds the upper water: its top just under the surface.
    fill(g1, [6], range(13, 19), 'L')
    # Storey 1: the stair, the lower banks, the falls' sheet.
    fill(g1, range(2, 10), range(3, 7), 'S')
    fill(g1, (10, 11), range(3, 9), '.')
    outline_rows = {7: (9, 23), 8: (9, 23), 9: (9, 23), 10: (9, 23), 11: (9, 23)}
    for r, (a, b) in outline_rows.items():
        fill(g1, [r], range(a, b), '.')
    channel(g0, g1, 7, L=[13] * 6, R=[19] * 6)
    fill(g1, [7], range(13, 19), 'F')
    # The plunge pool spreads under the banks.
    carve(g0, 7, L=[11, 9, 11], R=[21, 23, 21], fill='~', pairs=WATER_ROCK)
    # The ford: shallows over a sill of rock across the lower river.
    fill(g1, (9, 10), range(13, 19), ','); fill(g0, (9, 10), range(13, 19), '#')
    put(g0, 8, 11, '&&')
    # Chamfered corners: the lower river's north-east, the landing's south-west, the upper
    # river's north-east and south corners.
    put(g1, 7, 21, '\\\\'); put(g1, 11, 3, '\\\\')
    g2[3][23] = 'T'; g1[9][23] = 'T'; g1[12][6] = 'T'
    return {0: g0, 1: g1, 2: g2}



# The frozen river, the ice caves' own: a river's channel of ice sunk 0.4 m between banks of
# snow, and the slide, ice wall to wall. Its doorways are `FFFFffffffFFFF` and `FFfffFF` (bank,
# then sunken ice) and `||||||` and `|||`; the banks open onto the ice caves by ice doorways.

def frozen_river():
    g = blank(2, 2)
    put(g, 0, 1, FROZEN_NS); put(g, 8, 1, FROZEN_NS); down(g, 0, 5, '+++')
    outline(g, L=[1] * 8, R=[15, 15, 15, 13, 13, 15, 15, 15])
    fill(g, range(1, 8), range(5, 11), '_')
    hang_over(g, 4, L=[7, 5, 5, 7], R=[9, 11, 11, 9])
    put(g, 2, 2, '$$'); g[2][0] = 'T'; g[7][15] = 'T'
    return g


def frozen_ford():
    g = blank(2, 3)
    down(g, 0, 5, FROZEN_EW); down(g, 15, 5, FROZEN_EW); put(g, 0, 1, '++++++'); put(g, 12, 9, '++++++')
    outline(g, L=[1] * 12, R=[7, 9, 11, 13, 15, 15, 15, 15, 15, 15, 15, 15])
    fill(g, (7, 8, 9), range(1, 15), '_')
    fill(g, (7, 8, 9), range(6, 10), '.')  # a causeway of snow across
    put(g, 2, 2, '$$'); g[3][0] = 'T'; g[12][4] = 'T'
    return g


def frozen_bend():
    g = blank(3, 3)
    put(g, 12, 9, FROZEN_NS); down(g, 23, 1, FROZEN_EW); down(g, 0, 5, '+++')
    outline(g, L=[9] * 12, R=[23] * 12)
    fill(g, (5, 6, 7), range(1, 9), '.')
    region(g, 3, L=[17, 15, 13, 13, 13, 13, 13, 13, 13, 13], R=[23, 23, 23, 23, 21, 19, 19, 19, 19, 19],
           fill='_', pairs=POND)
    hang_over(g, 8, L=[15, 13, 13, 15], R=[17, 19, 19, 17])
    g[0][14] = 'T'; g[10][23] = 'T'
    return g


def frozen_cavern():
    g = blank(3, 4)
    put(g, 0, 9, FROZEN_NS); put(g, 16, 9, FROZEN_NS); down(g, 0, 5, '+++'); down(g, 23, 9, '+++')
    outline(g, L=[9, 7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9, 9, 9, 9], R=[23] * 16)
    region(g, 1, L=[13, 13, 13, 13, 11, 11, 11, 11, 13, 13, 13, 13, 13, 13, 13, 13],
           R=[19, 19, 19, 19, 17, 17, 17, 17, 19, 19, 19, 19, 19, 19, 19, 19], fill='_', pairs=POND)
    fill(g, (11, 12), range(13, 19), '.')  # a bridge of snow
    hang_over(g, 2, L=[15, 13, 13, 15], R=[17, 19, 19, 17])
    put(g, 4, 5, 'ii'); put(g, 13, 20, 'jj'); put(g, 9, 7, 'mm'); put(g, 4, 20, 'MM')
    put(g, 6, 14, '&&'); put(g, 7, 3, '$$')
    g[2][23] = 'T'; g[14][23] = 'T'
    pond_rock(g)
    return g


def frozen_narrows():
    g = blank(2, 3)
    # A one-cell doorway sits in one cell, so the river narrows toward the east one: the
    # banks run out and its last cell is ice wall to wall.
    put(g, 12, 1, FROZEN_NS); put(g, 0, 9, SLIDE_NS)
    outline(g, L=[9, 9, 9, 9, 9, 7, 5, 3, 1, 1, 1, 1], R=[15] * 12)
    region(g, 1, L=[9, 9, 9, 9, 9, 7, 5, 5, 5, 5, 5, 5], R=[15, 15, 15, 15, 15, 13, 11, 11, 11, 11, 11, 11],
           fill='_', pairs=POND)
    pond_rock(g)
    put(g, 7, 3, '//')  # the west bank's tip, snow
    g[10][0] = 'T'; g[10][15] = 'T'
    return g


def frozen_slide():
    # Ice wall to wall, sunk: no bank to stop on, so it is taken at a slide.
    g = blank(1, 2)
    put(g, 0, 1, SLIDE_NS); put(g, 8, 1, SLIDE_NS); down(g, 0, 5, '+++')
    outline(g, L=[1] * 8, R=[7] * 8, fill='_')
    g[2][7] = 'T'
    return g


def frozen_slide_bend():
    g = blank(2, 2)
    put(g, 8, 9, SLIDE_NS); down(g, 0, 1, SLIDE_EW)
    outline(g, L=[1] * 8, R=[15] * 8, fill='_')
    fill(g, range(4, 8), range(1, 9), '#')
    # 45-degree rock on the bend's outer and inner corners: what slides round it meets them.
    put(g, 1, 13, '\\\\'); put(g, 4, 7, '\\\\')
    pond_rock(g)
    g[0][8] = 'T'
    return g


def frozen_spring():
    g = blank(3, 3)
    put(g, 12, 9, FROZEN_NS); put(g, 0, 9, '++++++'); down(g, 0, 5, '+++')
    # The east bank runs straight up into the room, 2 m wide, so both banks join here.
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[19, 21, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23])
    region(g, 3, L=[13, 11, 11, 11, 11, 13, 13, 13, 13, 13], R=[17, 19, 19, 19, 19, 19, 19, 19, 19, 19],
           fill='_', pairs=POND)
    # The frozen fall it comes out from under: icicles hanging low over the pool's head.
    hang_over(g, 3, L=[15, 13, 13, 15], R=[17, 19, 19, 17])
    put(g, 6, 5, 'ii'); put(g, 2, 12, 'mm'); put(g, 9, 20, 'mm')
    put(g, 8, 5, '$$')
    g[4][0] = 'T'; g[8][23] = 'T'
    pond_rock(g)
    return g


def frozen_sink():
    g = blank(3, 3)
    put(g, 0, 9, FROZEN_NS); down(g, 0, 5, '+++'); down(g, 23, 5, '+++')
    outline(g, L=[1, 1, 1, 1, 1, 1, 1, 1, 1, 1, 3, 5], R=[23, 23, 23, 23, 23, 23, 23, 23, 23, 23, 21, 19])
    region(g, 1, L=[13, 13, 13, 11, 9, 7, 7, 9, 11], R=[19, 19, 19, 21, 21, 21, 21, 21, 19], fill='_', pairs=POND)
    hang_over(g, 5, L=[11, 9, 9, 11], R=[13, 15, 15, 13])
    put(g, 7, 17, '&&'); put(g, 10, 11, '$$')
    g[2][0] = 'T'; g[2][23] = 'T'; g[12][11] = 'T'
    pond_rock(g)
    return g


def frozen_slide_spring():
    g = blank(2, 2)
    put(g, 8, 9, SLIDE_NS); put(g, 0, 1, '++++++'); down(g, 0, 5, '+++')
    outline(g, L=[1] * 8, R=[11, 13, 15, 15, 15, 15, 15, 15])
    # The slide comes in wall to wall for 3 m before the pool opens out.
    region(g, 2, L=[9, 7, 7, 9, 9, 9, 9], R=[13, 15, 15, 15, 15, 15, 15], fill='_', pairs=POND)
    fill(g, (5, 6, 7), [8], '#')
    pond_rock(g)
    put(g, 3, 2, '$$'); g[3][0] = 'T'
    return g


PLANS = {
    'cave': cave, 'lava-lake': lava_lake, 'cave-passage': cave_passage,
    'grotto': grotto, 'cavern': cavern, 'cave-bend': cave_bend, 'cave-fork': cave_fork,
    'lava-chasm': lava_chasm, 'magma-pool': magma_pool,
    'river': river, 'river-ford': river_ford, 'river-bend': river_bend, 'river-cavern': river_cavern,
    'stream': stream, 'stream-bend': stream_bend, 'river-narrows': river_narrows,
    'lava-spring': lava_spring, 'lava-sink': lava_sink, 'stream-spring': stream_spring,
    'ice-grotto': ice_grotto, 'ice-lake': ice_lake, 'ice-sheet': ice_sheet, 'ice-cavern': ice_cavern,
    'ice-passage': ice_passage, 'ice-bend': ice_bend, 'ice-gate': ice_gate, 'ice-gate-bend': ice_gate_bend,
    'ice-chute': ice_chute, 'ice-niche': ice_niche, 'frost-shrine': frost_shrine,
    'creek': creek, 'creek-bend': creek_bend, 'creek-ford': creek_ford, 'creek-cavern': creek_cavern,
    'creek-narrows': creek_narrows, 'rill': rill, 'rill-sump': rill_sump, 'creek-spring': creek_spring,
    'rill-spring': rill_spring, 'creek-sink': creek_sink, 'creek-sink-sump': lambda: creek_sink(sump=True),
    'creek-falls': creek_falls,
    'frozen-river': frozen_river, 'frozen-ford': frozen_ford, 'frozen-bend': frozen_bend,
    'frozen-cavern': frozen_cavern, 'frozen-narrows': frozen_narrows, 'frozen-slide': frozen_slide,
    'frozen-slide-bend': frozen_slide_bend, 'frozen-slide-spring': frozen_slide_spring,
    'frozen-sink': frozen_sink, 'frozen-spring': frozen_spring,
}


def main(args):
    check = '--check' in args
    names = [a for a in args if a != '--check'] or list(PLANS)
    status = 0
    for name in names:
        if name not in PLANS:
            print('%s: no such cave plan; there are %s' % (name, ', '.join(PLANS)), file=sys.stderr)
            status = 1
            continue
        plans = PLANS[name]()
        if not isinstance(plans, dict):
            plans = {0: plans}
        rows = []
        for k in sorted(plans):
            if k:
                rows += ['', 'plan %d' % k]
            rows += ["".join(r) for r in plans[k]]
        path = os.path.join(ROOT, 'data', 'blueprints', name + '.txt')
        lines = open(path).read().split('\n')
        start = lines.index('plan 0') + 1
        new = lines[:start] + rows + ['']
        if new == lines:
            continue
        if check:
            print('%s: plan differs from the blueprint' % name)
            status = 1
        else:
            open(path, 'w').write('\n'.join(new))
            print('%s: plan drawn' % name)
    return status


if __name__ == '__main__':
    sys.exit(main(sys.argv[1:]))
