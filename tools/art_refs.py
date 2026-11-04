#!/usr/bin/env python3
"""Say which images under art/ are the record and which are candidates nobody chose.

    tools/art_refs.py            # KEEP and ATTIC lists, tracked and untracked, with sizes
    tools/art_refs.py --attic    # only the ATTIC paths, one a line (for moving them out)
    tools/art_refs.py --check    # before committing art: exit 1 if a tracked or staged
                                 # image is unreferenced, or a reference names no file

An image is KEEP when something names it:
- a ```bash block in CLAUDE.md, run through bash with every command stubbed out, so its
  braces, loops and variables ($K, ${a%:*}-$v) expand as they would when run;
- a path in CLAUDE.md's prose or a tool's docstring (braces and <view> expanded; a bare
  file name resolves to the art/ folder last mentioned before it);
- a frames file (art/**/*.txt: a picture name at the start of a line, in that file's folder);
- the refs of the .prompt.json of an image already kept (repeated until nothing changes),
  so the references a chosen take was made from are kept with it.

Tracked takes of a .prompt.json none of whose takes is named are UNDECIDED: the choice
isn't written down, so name the chosen one in CLAUDE.md. Files in a strips/ folder (slicer output that a later command reads) are kept. A folder
whose files are all untracked is work in progress and is left out of both lists. Everything
else is ATTIC: a take that wasn't chosen, a preview, an earlier design.

Git LFS can't delete what was pushed to it, so nothing ATTIC should ever be committed: move
it to ../hexmaw-art-attic/ (same paths) or delete it.
"""

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
IMAGE = re.compile(r'\.(png|webp|jpe?g|blend)$', re.I)
VIEWS = ['front', 'front-quarter', 'side', 'back-quarter', 'back']


def git_files(*args):
    out = subprocess.run(['git', 'ls-files', '-z', *args, '--', 'art'],
                         cwd=ROOT, capture_output=True, text=True, check=True).stdout
    return [f for f in out.split('\0') if f]


def braces(s):
    m = re.search(r'\{([^{}]*,[^{}]*)\}', s)
    if not m:
        return [s]
    return [e for alt in m.group(1).split(',')
            for e in braces(s[:m.start()] + alt + s[m.end():])]


def expand(s):
    out = []
    for e in braces(s):
        out += [e.replace('<view>', v) for v in VIEWS] if '<view>' in e else [e]
    return out


def bash_args(block):
    """Every argument the commands of BLOCK would get, with no command run."""
    # A command named by a path would run if it existed and fail otherwise: make each a
    # plain name, so it goes through command_not_found_handle like every other command.
    block = re.sub(r'(^|[;&|(]|\bdo\b|\bthen\b)(\s*)((?:\./)?[\w.-]+(?:/[\w.-]+)+)',
                   lambda m: m.group(1) + m.group(2) + m.group(3).replace('/', '__'),
                   block, flags=re.M)
    script = ('command_not_found_handle() { printf "%s\\0" "$@" >&3; return 0; }\n'
              + block)
    with tempfile.TemporaryDirectory() as empty, tempfile.TemporaryFile() as out:
        subprocess.run(['/bin/bash', '--norc', '--noprofile', '-c',
                        f'exec 3>&{out.fileno()}; ' + script],
                       cwd=empty, env={'PATH': '/nonexistent'}, pass_fds=(out.fileno(),),
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        out.seek(0)
        return out.read().decode('utf-8', 'replace').split('\0')


def art_paths(text):
    """Paths under art/ written in TEXT, quoted or not, with their braces expanded."""
    found = []
    for m in re.finditer(r'"(art/[^"\n]*)"|(art/[^\s`"\'(),;]+(?:\([^)\s]*\)[^\s`"\']*)?)', text):
        found += expand(m.group(1) or m.group(2))
    return found


def references():
    """Paths named by CLAUDE.md, the tools and the frames files."""
    named = set()
    doc = (ROOT / 'CLAUDE.md').read_text()
    for block in re.findall(r'```bash\n(.*?)```', doc, re.S):
        for arg in bash_args(block):
            for m in re.finditer(r'(?:^|=)(art/.+)$', arg):
                named.add(m.group(1))
    sources = [doc] + [p.read_text(errors='ignore') for p in (ROOT / 'tools').iterdir()
                       if p.is_file() and p.suffix in ('.py', '.sh', '')]
    for text in sources:
        folder = None
        for m in re.finditer(r'`([^`\n]+)`|(art/[^\s`]+)', text):
            span = m.group(1) or m.group(2)
            for p in art_paths(span):
                named.add(p)
                if IMAGE.search(p) and not p.startswith('art/prompts/'):
                    folder = os.path.dirname(p)
            if m.group(1) and '/' not in span and IMAGE.search(span) and folder:
                named.update(f'{folder}/{e}' for e in expand(span))
    for txt in (ROOT / 'art').rglob('*.txt'):
        if 'prompts' in txt.parts:
            continue
        for line in txt.read_text(errors='ignore').splitlines():
            m = re.match(r'\s*([^;\s][^\s]*\.(?:png|webp))\b', line)
            if m:
                named.add(str(txt.relative_to(ROOT).parent / m.group(1)))
    # What gen_image.py is told to write is a new take, not a reference to one.
    outputs = {m.group(1) for text in sources
               for m in re.finditer(r'gen_image\.py\s+(art/\S+)', text)}
    return {os.path.normpath(p) for p in named - outputs}


def prompt_record(image):
    """The .prompt.json gen_image.py wrote beside IMAGE: <stem>.prompt.json, stem without -N."""
    p = Path(image)
    stem = p.stem
    for s in (stem, re.sub(r'-\d+$', '', stem)):
        rec = ROOT / p.parent / f'{s}.prompt.json'
        if rec.exists():
            return rec
    return None


def classify():
    tracked = git_files()
    untracked = git_files('--others', '--exclude-standard')
    files = set(tracked) | set(untracked)
    named = references()
    # A stem (a strip named without its .png) names its files.
    for p in list(named):
        if not IMAGE.search(p):
            named.update(f for f in files if os.path.splitext(f)[0] == p)
    keep = {f for f in files if IMAGE.search(f) and (f in named or '/strips/' in f)}
    while True:
        more = set()
        for f in keep:
            rec = prompt_record(f)
            if rec:
                try:
                    refs = json.loads(rec.read_text()).get('refs') or []
                except ValueError:
                    refs = []
                more.update(os.path.normpath(r) for r in refs if r.startswith('art/'))
        named |= more
        new = (more & files) - keep
        if not new:
            break
        keep |= new
    tracked_dirs = {os.path.dirname(f) for f in tracked}
    wip = {f for f in untracked if os.path.dirname(f) not in tracked_dirs}
    images = sorted(f for f in files if IMAGE.search(f) and f not in wip)
    # A record none of whose takes is named: which one was chosen isn't written down.
    takes = {}
    for f in images:
        takes.setdefault(prompt_record(f), []).append(f)
    tracked_set = set(tracked)
    undecided = {f for rec, fs in takes.items() if rec and not any(t in keep for t in fs)
                 for f in fs if f in tracked_set}

    def missing(p):
        if not IMAGE.search(p) or p in files or (ROOT / p).exists():
            return False
        if re.search(r'[$<>*]|-N\.', p) or (ROOT / os.path.basename(p)).exists():
            return False             # a placeholder, or a file at the root
        stem = os.path.splitext(p)[0]
        return not any(f.startswith(stem + '-') for f in files)   # gen_image's -1, -2 ...
    broken = sorted(p for p in named if missing(p))
    return tracked, keep, undecided, wip, broken, images


def size(f):
    try:
        return os.path.getsize(ROOT / f)
    except OSError:
        return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__.split('\n')[0])
    ap.add_argument('--attic', action='store_true', help='print only the ATTIC paths')
    ap.add_argument('--check', action='store_true', help='fail on committed candidates')
    args = ap.parse_args()
    tracked, keep, undecided, wip, broken, images = classify()
    tracked = set(tracked)
    attic = [f for f in images if f not in keep and f not in undecided]
    if args.attic:
        for f in attic:
            print(f)
        return
    if args.check:
        bad = [f for f in attic if f in tracked]
        for f in bad:
            print(f'unreferenced, so a candidate: {f}')
        for f in sorted(undecided):
            print(f'no take of its .prompt.json is named, so which was chosen is unknown: {f}')
        for p in broken:
            print(f'named but missing: {p}')
        bad += sorted(undecided)
        if bad:
            print(f'{len(bad)} tracked image(s) nothing names: name the chosen take in CLAUDE.md '
                  'or a frames file, or move it to ../hexmaw-art-attic/', file=sys.stderr)
        sys.exit(1 if bad else 0)
    for label, group in (('KEEP', [f for f in images if f in keep]),
                         ('UNDECIDED', sorted(undecided)), ('ATTIC', attic)):
        for where in ('tracked', 'untracked'):
            part = [f for f in group if (f in tracked) == (where == 'tracked')]
            if part or label != 'UNDECIDED':
                print(f'== {label} {where}: {len(part)} files, '
                      f'{sum(map(size, part)) / 1e6:.1f} MB')
            for f in part:
                print(f'{size(f) / 1e6:6.2f}  {f}')
    if wip:
        print(f'== work in progress (left alone): {len(wip)} files, '
              f'{sum(map(size, wip)) / 1e6:.1f} MB in '
              + ', '.join(sorted({os.path.dirname(f) for f in wip})))
    for p in broken:
        print(f'named but missing: {p}')


if __name__ == '__main__':
    main()
