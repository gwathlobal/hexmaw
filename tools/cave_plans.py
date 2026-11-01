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
  an ice cave's `++++++` and `+++`.
- pickup spots: put `$$` (floor) or `&&` (reward) where the blueprint's legend says what they are.

Ice caves: their floor is snow, and a frozen pond (`_`) is sunk 0.2 m into it, a REGION with
POND's shore pairs. POND_ROCK turns rock pairs beside it into `<` and `>`, standing in it,
HANG_OVER hangs icicles that keep the pond under them, HANG_DIAMOND hangs a diamond of ice
from a corridor's ceiling, and FROST_LINE turns an ice gate from rock to ice along a 45-degree
line across the way, a drift of snow over the join. Nothing in a cave is a rectangle.

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


PLANS = {
    'cave': cave, 'lava-lake': lava_lake, 'cave-passage': cave_passage,
    'grotto': grotto, 'cavern': cavern, 'cave-bend': cave_bend, 'cave-fork': cave_fork,
    'lava-chasm': lava_chasm, 'magma-pool': magma_pool,
    'river': river, 'river-ford': river_ford, 'river-bend': river_bend, 'river-cavern': river_cavern,
    'stream': stream, 'stream-bend': stream_bend, 'river-narrows': river_narrows,
    'lava-spring': lava_spring, 'lava-sink': lava_sink, 'stream-spring': stream_spring,
    'ice-grotto': ice_grotto, 'ice-lake': ice_lake, 'ice-cavern': ice_cavern,
    'ice-passage': ice_passage, 'ice-bend': ice_bend, 'ice-gate': ice_gate, 'ice-gate-bend': ice_gate_bend,
    'ice-chute': ice_chute, 'ice-niche': ice_niche, 'frost-shrine': frost_shrine,
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
        rows = ["".join(r) for r in PLANS[name]()]
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
