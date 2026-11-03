#!/usr/bin/env python3
"""A page for choosing the sound effects' takes, swapping each into the running game.

  tools/sfx_picker.py            then open http://127.0.0.1:8765/
  tools/sfx_picker.py --port 9000

The page (tools/sfx_picker.html) lists every clip of audio/sfx.md with its generated takes
(audio/sfx/<clip>-<n>.wav), which play in the browser. Choosing takes for a clip (one, or
several variants, and a gain) rewrites its line in audio/sfx-picks.txt, runs
tools/make_sfx.py on that clip, and has the game reload it (RELOAD-SOUND, sound.lisp) and
play it 3 m in front of the player (AUDITION-SOUND), so the next time the game plays it,
it is the new take. Choose again as often as you like: nothing is lost, the takes stay.

It talks to the game this checkout's tools/hd would (HEXMAW_EVAL_PORT, else .eval-port, else
7171); without a game, the picks and the converted files still change, for the next start.
"""

import argparse
import json
import os
import re
import socket
import subprocess
import sys
import threading
import wave
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parent.parent
TABLE = ROOT / "audio/sfx.md"
PICKS = ROOT / "audio/sfx-picks.txt"
TAKES = ROOT / "audio/sfx"
PAGE = Path(__file__).resolve().parent / "sfx_picker.html"
LOCK = threading.Lock()


def game_port():
    if os.environ.get("HEXMAW_EVAL_PORT"):
        return int(os.environ["HEXMAW_EVAL_PORT"])
    try:
        return int((ROOT / ".eval-port").read_text().strip())
    except (OSError, ValueError):
        return 7171


def game_eval(form, timeout=10.0):
    """(ok, text): FORM evaluated by the game's eval server, as tools/hd does it."""
    try:
        with socket.create_connection(("127.0.0.1", game_port()), timeout=timeout) as s:
            s.sendall(form.encode() + b"\n")
            data = b""
            while chunk := s.recv(65536):
                data += chunk
    except OSError:
        return False, f"The game isn't running (nothing on port {game_port()})."
    status, _, body = data.decode(errors="replace").partition("\n")
    return status == "OK", body.strip()


def read_table():
    """The clips in audio/sfx.md's order: name, tier, place, seconds, takes asked, hook, section."""
    clips, section = [], ""
    for line in TABLE.read_text().splitlines():
        if line.startswith("## "):
            section = line[3:].strip()
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) == 6 and re.fullmatch(r"[a-z0-9-]+", cells[0]) and cells[1].isdigit():
            pos = cells[2].split()
            clips.append({"name": cells[0], "tier": int(cells[1]), "positional": pos[0] == "P",
                          "loop": "L" in pos[1:], "seconds": float(cells[3]),
                          "hook": cells[5], "section": section})
    return clips


TAKE_INFO = {}


def take_info(path):
    """Length, peak and clipped samples of a take, cached by its modification time."""
    key = (path, path.stat().st_mtime)
    if key not in TAKE_INFO:
        with wave.open(str(path)) as w:
            rate, n = w.getframerate(), w.getnframes()
            x = np.frombuffer(w.readframes(n), np.int16)
        TAKE_INFO[key] = {"seconds": round(n / rate, 2),
                          "peak": round(20 * np.log10(max(1, int(np.abs(x.astype(np.int32)).max())) / 32768), 1),
                          "clipped": int((np.abs(x.astype(np.int32)) >= 32767).sum())}
    return TAKE_INFO[key]


def takes_of(clip):
    found = []
    for path in TAKES.glob(f"{clip}*.wav"):
        m = re.fullmatch(rf"{re.escape(clip)}(?:-(\d+))?\.wav", path.name)
        if m:
            found.append({"take": int(m.group(1) or 1), "file": path.name, **take_info(path)})
    return sorted(found, key=lambda t: t["take"])


def read_picks():
    picks = {}
    if PICKS.exists():
        for line in PICKS.read_text().splitlines():
            words = line.split("#")[0].split()
            if words:
                takes = [int(w) for w in words[1:] if w.isdigit()]
                gain = next((float(w[5:]) for w in words[1:] if w.startswith("gain=")), 0.0)
                picks[words[0]] = {"takes": takes or [1], "gain": gain}
    return picks


def write_pick(clip, takes, gain):
    """Set CLIP's line in the picks file, keeping every other line and its own comment."""
    lines = PICKS.read_text().splitlines() if PICKS.exists() else []
    entry = f"{clip} {' '.join(map(str, takes))}" + (f" gain={gain:g}" if gain else "")
    for i, line in enumerate(lines):
        words = line.split("#")[0].split()
        if words and words[0] == clip:
            comment = line[line.index("#"):] if "#" in line else ""
            lines[i] = f"{entry:<24}{comment}".rstrip() if comment else entry
            break
    else:
        lines.append(entry)
    PICKS.write_text("\n".join(lines) + "\n")


def use(clip, takes, gain, audition):
    known = {c["name"]: c for c in read_table()}
    if clip not in known:
        return 400, {"error": f"No clip {clip}."}
    have = {t["take"] for t in takes_of(clip)}
    takes = [int(t) for t in takes]
    if not takes or not set(takes) <= have:
        return 400, {"error": f"{clip} has takes {sorted(have)}, not {takes}."}
    with LOCK:
        write_pick(clip, takes, float(gain))
        made = subprocess.run([sys.executable, str(ROOT / "tools/make_sfx.py"), clip],
                              capture_output=True, text=True)
        if made.returncode:
            return 500, {"error": made.stderr.strip() or made.stdout.strip()}
        ok, text = game_eval(f"(game (and (reload-sound :{clip}) {'(audition-sound :' + clip + ')' if audition else 'T'}))")
    return 200, {"made": made.stdout.strip(), "game": text if ok else None,
                 "note": None if ok else text}


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass

    def send(self, code, body, kind="application/json"):
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
        self.send_response(code)
        self.send_header("Content-Type", kind)
        self.send_header("Content-Length", str(len(data)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(data)

    def do_GET(self):
        if self.path in ("/", "/index.html"):
            return self.send(200, PAGE.read_bytes(), "text/html; charset=utf-8")
        if self.path == "/api/clips":
            picks = read_picks()
            clips = []
            for c in read_table():
                takes = takes_of(c["name"])
                pick = picks.get(c["name"], {"takes": [1] if takes else [], "gain": 0.0, "default": True})
                clips.append({**c, "takes": takes, "pick": pick})
            return self.send(200, {"clips": clips})
        if self.path == "/api/game":
            ok, text = game_eval("(namestring (root))", timeout=2.0)
            return self.send(200, {"running": ok, "root": text if ok else None,
                                   "port": game_port(), "note": None if ok else text})
        m = re.fullmatch(r"/take/([a-z0-9-]+\.wav)", self.path)
        if m and (TAKES / m.group(1)).exists():
            return self.send(200, (TAKES / m.group(1)).read_bytes(), "audio/wav")
        self.send(404, {"error": "not found"})

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("Content-Length", 0))) or b"{}")
        if self.path == "/api/use":
            code, reply = use(body.get("clip", ""), body.get("takes", []), body.get("gain", 0),
                              body.get("audition", True))
            return self.send(code, reply)
        if self.path == "/api/audition":
            clip = body.get("clip", "")
            if not re.fullmatch(r"[a-z0-9-]+", clip):
                return self.send(400, {"error": "bad clip"})
            ok, text = game_eval(f"(game (audition-sound :{clip}))")
            return self.send(200 if ok else 503, {"game": text} if ok else {"error": text})
        self.send(404, {"error": "not found"})


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--port", type=int, default=8765)
    args = ap.parse_args()
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Handler)
    print(f"Sound picker on http://127.0.0.1:{args.port}/ (game on port {game_port()})", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
