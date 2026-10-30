#!/usr/bin/env python3
"""Stack one animation sheet per view and slice the result, in one step.

tools/stack_views.py and tools/slice_frames.py in a row, without writing the stacked
sheet: it is big (about 10 MB for a monster's walk) and rebuilds exactly from the
per-view sheets, so it doesn't belong in the repository. Takes the output directory,
the one animation the views make, the per-view sheets in the turnaround's view order,
and both tools' options:

  tools/slice_views.py data/sprites/knight walk:20 art/knight/runic-walk-{front-1,front-quarter-b-1,side,back-quarter,back}.png \\
      --height 1000 --frame 1 --blank 1 --pixel 8 --anchor bottom --filter box

To look at the stacked sheet, run tools/stack_views.py with the same stacking options.
"""

import argparse
from pathlib import Path

from slice_frames import add_slice_arguments, slice_sheet
from stack_views import add_stack_arguments, stack


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", help="output directory")
    ap.add_argument("animation", metavar="NAME:FRAMES", help="the animation, with its frame count")
    ap.add_argument("inputs", nargs="+", help="one sheet per view")
    add_stack_arguments(ap)
    add_slice_arguments(ap)
    args = ap.parse_args()
    args.animations = [args.animation]
    names = ", ".join(Path(p).name for p in args.inputs)
    slice_sheet(stack(args), f"tools/slice_views.py from {names}", args)


if __name__ == "__main__":
    main()
