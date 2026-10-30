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
  south face and `RR===RR` on an east or west one; a stream's `SS--SS` and `S-S`.

Then `tools/blueprint NAME` builds the block, and in the game `(check-kit '("NAME"))` checks
its doorways and monsters reach each other.
"""
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ROCK = set('#<>/\\AB1234')

POOL = {'/': '(', '\\': ')'}
PIT = {'/': '[', '\\': ']'}
SHELF = {'/': '{', '\\': '}'}
HANG = {'/': 'A', '\\': 'B'}
WIDE_NS, WIDE_EW = 'RRRR======RRRR', 'RR===RR'
NARROW_NS, NARROW_EW = 'SS--SS', 'S-S'


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
    put(g, 6, 12, 'ii'); g[0][8] = 'T'; g[12][15] = 'T'
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
    put(g, 4, 9, 'vv'); put(g, 6, 16, 'ii')
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
    put(g, 6, 9, 'ii')
    return g


def cavern():
    g = blank(4, 3)
    put(g, 0, 9, 'nnnnnn'); put(g, 12, 17, 'ssssss'); down(g, 0, 5, 'www'); down(g, 31, 5, 'eee')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[23, 25, 27, 29, 31, 31, 31, 31, 29, 27, 25, 23])
    octagon_pillar(g, 3, 8)
    octagon_pillar(g, 7, 19)
    region(g, 2, L=[17, 15, 15, 17], R=[21, 23, 23, 21], fill=',', pairs=SHELF)
    region(g, 7, L=[9, 7, 7, 9], R=[11, 13, 13, 11], fill='v', pairs=HANG)
    put(g, 6, 15, 'ii'); put(g, 9, 13, 'jj')
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
    put(g, 9, 17, 'ii')
    lava_rock(g)
    return g


def magma_pool():
    g = blank(3, 3)
    put(g, 0, 9, 'nnnnnn'); down(g, 0, 5, 'www'); down(g, 23, 5, 'eee')
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[17, 19, 21, 23, 23, 23, 23, 23, 21, 19, 17, 15])
    region(g, 3, L=[9, 7, 5, 5, 5, 5, 7, 9], R=[15, 17, 19, 19, 19, 19, 17, 15], fill='~', pairs=POOL)
    region(g, 5, L=[11, 9, 9, 11], R=[13, 15, 15, 13], fill='.', pairs=POOL)
    fill(g, [1, 2, 3, 4], [11, 12], '.')
    put(g, 6, 11, 'ii')
    lava_rock(g)
    return g


def river():
    g = blank(2, 2)
    put(g, 0, 1, WIDE_NS); put(g, 8, 1, WIDE_NS); down(g, 0, 5, 'www')
    outline(g, L=[1] * 8, R=[15, 15, 15, 13, 13, 15, 15, 15])
    fill(g, range(1, 8), range(5, 11), '~')
    return g


def river_ford():
    g = blank(2, 3)
    down(g, 0, 5, WIDE_EW); down(g, 15, 5, WIDE_EW); put(g, 0, 1, 'nnnnnn'); put(g, 12, 9, 'ssssss')
    outline(g, L=[1] * 12, R=[7, 9, 11, 13, 15, 15, 15, 15, 15, 15, 15, 15])
    fill(g, (7, 8, 9), range(1, 15), '~')
    fill(g, (7, 8, 9), range(6, 10), '.')
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
    put(g, 4, 5, 'ii'); put(g, 13, 20, 'jj')
    return g


def stream():
    g = blank(1, 2)
    put(g, 0, 1, NARROW_NS); put(g, 8, 1, NARROW_NS); down(g, 0, 5, 'www')
    outline(g, L=[1] * 8, R=[7] * 8)
    fill(g, range(1, 8), (3, 4), '~')
    return g


def stream_bend():
    g = blank(2, 2)
    put(g, 8, 9, NARROW_NS); down(g, 0, 1, NARROW_EW)
    outline(g, L=[1] * 8, R=[15] * 8)
    region(g, 2, L=[1, 1], R=[13, 13], fill='~', pairs=POOL)
    region(g, 3, L=[9, 11, 11, 11, 11, 11], R=[13] * 6, fill='~', pairs=POOL)
    return g


def river_narrows():
    g = blank(2, 3)
    # A one-cell doorway sits in one cell, so the river narrows toward the east one.
    put(g, 12, 1, WIDE_NS); put(g, 0, 9, NARROW_NS)
    outline(g, L=[9, 7, 5, 3, 1, 1, 1, 1, 1, 1, 1, 1], R=[15] * 12)
    region(g, 1, L=[11, 11, 11, 9, 7, 5, 5, 5, 5, 5, 5, 5], R=[13, 13, 13, 13, 11, 11, 11, 11, 11, 11, 11, 11],
           fill='~', pairs=POOL)
    return g


def lava_spring():
    g = blank(3, 3)
    put(g, 12, 9, WIDE_NS); put(g, 0, 9, 'nnnnnn'); down(g, 0, 5, 'www')
    # The east bank runs straight up into the room, 2 m wide, so both banks join here.
    outline(g, L=[7, 5, 3, 1, 1, 1, 1, 1, 3, 5, 7, 9], R=[19, 21, 23, 23, 23, 23, 23, 23, 23, 23, 23, 23])
    region(g, 3, L=[13, 11, 11, 11, 11, 13, 13, 13, 13, 13], R=[17, 19, 19, 19, 19, 19, 19, 19, 19, 19],
           fill='~', pairs=POOL)
    put(g, 6, 5, 'ii')
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
    region(g, 2, L=[9, 7, 7, 9, 11, 11], R=[13, 15, 15, 13, 13, 13], fill='~', pairs=POOL)
    lava_rock(g)
    return g


PLANS = {
    'cave': cave, 'lava-lake': lava_lake, 'cave-passage': cave_passage,
    'grotto': grotto, 'cavern': cavern, 'cave-bend': cave_bend, 'cave-fork': cave_fork,
    'lava-chasm': lava_chasm, 'magma-pool': magma_pool,
    'river': river, 'river-ford': river_ford, 'river-bend': river_bend, 'river-cavern': river_cavern,
    'stream': stream, 'stream-bend': stream_bend, 'river-narrows': river_narrows,
    'lava-spring': lava_spring, 'lava-sink': lava_sink, 'stream-spring': stream_spring,
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
