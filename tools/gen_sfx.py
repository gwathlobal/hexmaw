#!/usr/bin/env python3
"""Generate a sound effect with ElevenLabs' text-to-sound model and save it into the project.

  tools/gen_sfx.py audio/sfx/bolt-cast.wav --prompt-file audio/prompts/bolt-cast.txt \\
      --duration 1.2 -n 3

The prompt is --prompt TEXT or --prompt-file PATH (keep prompts worth repeating in files).
The format follows the output's extension: .wav (16-bit stereo PCM at --rate, wrapped here)
or .mp3 (44.1 kHz, 128 kbit/s). With -n 3 the clips go to <stem>-1.wav, <stem>-2.wav,
<stem>-3.wav, one request each. Existing files are never overwritten unless --force is
given. Next to the output, <stem>.prompt.json records the prompt and options, so a good
result can be reproduced or varied. --add makes more takes of a clip that has some: they are
numbered on from the last one (<stem>-4.wav, ...), recorded in <stem>-4.prompt.json, and the
earlier takes and their record stay as they are.

--duration is 0.5 to 30 seconds; without it the model picks one. --influence (0 to 1,
default 0.3) is how literally it takes the prompt: higher follows it closer, lower varies
more. --loop asks for a clip that loops seamlessly (ambience, a torch's crackle).

The key comes from $ELEVENLABS_API_KEY, or else from ~/.config/elevenlabs/api_key (one
line): ElevenLabs → Developers → API Keys, with the Sound Effects permission. Each request
is billed in credits against the account's plan: with --duration, about 10 credits a
second (three 1.2 s clips took 36).

--dry-run prints the request instead of sending it.
"""

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
import wave
from pathlib import Path

API = "https://api.elevenlabs.io/v1/sound-generation"
KEY_FILE = Path.home() / ".config/elevenlabs/api_key"
FORMATS = (".wav", ".mp3")


def api_key():
    key = os.environ.get("ELEVENLABS_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text().strip()
    if not key:
        sys.exit(f"No API key: set ELEVENLABS_API_KEY or put the key in {KEY_FILE}")
    return key


def output_paths(out, n, add=False):
    if add:
        have = [int(p.stem[len(out.stem) + 1:]) for p in out.parent.glob(f"{out.stem}-*{out.suffix}")
                if p.stem[len(out.stem) + 1:].isdigit()]
        first = max(have, default=1 if out.exists() else 0) + 1
        return [out.with_name(f"{out.stem}-{i}{out.suffix}") for i in range(first, first + n)]
    if n == 1:
        return [out]
    return [out.with_name(f"{out.stem}-{i}{out.suffix}") for i in range(1, n + 1)]


def save(path, data, rate):
    """Write the clip: raw PCM wrapped as a .wav, an .mp3 as it came."""
    if path.suffix.lower() == ".mp3":
        path.write_bytes(data)
        return len(data) / (128000 / 8)
    # The model's PCM is interleaved stereo, though the docs don't say so: read as mono, a
    # 1.2 s clip played 2.4 s at half the pitch.
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes(data)
    return len(data) / 4 / rate


def request(url, body, key):
    """POST one generation. Returns (audio bytes, request id)."""
    req = urllib.request.Request(url, json.dumps(body).encode(),
                                 {"xi-api-key": key, "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=300) as resp:
            return resp.read(), resp.headers.get("request-id")
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail)["detail"]
            detail = detail.get("message", detail) if isinstance(detail, dict) else detail
        except (ValueError, KeyError, TypeError):
            pass
        sys.exit(f"HTTP {e.code}: {detail}")


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path, help="output clip (.wav or .mp3)")
    prompt = ap.add_mutually_exclusive_group(required=True)
    prompt.add_argument("--prompt", "-p")
    prompt.add_argument("--prompt-file", "-f", type=Path)
    ap.add_argument("--duration", "-d", type=float, help="seconds, 0.5 to 30 (default: auto)")
    ap.add_argument("--influence", type=float, default=0.3, help="prompt influence, 0 to 1")
    ap.add_argument("--loop", action="store_true", help="make the clip loop seamlessly")
    ap.add_argument("--rate", type=int, default=44100, choices=[16000, 22050, 24000, 44100],
                    help="sample rate of a .wav")
    ap.add_argument("--model", default="eleven_text_to_sound_v2")
    ap.add_argument("-n", type=int, default=1, help="number of clips")
    ap.add_argument("--force", action="store_true", help="overwrite existing outputs")
    ap.add_argument("--add", action="store_true", help="number new takes after the existing ones")
    ap.add_argument("--dry-run", action="store_true", help="print the request, send nothing")
    args = ap.parse_args()

    if args.out.suffix.lower() not in FORMATS:
        ap.error(f"output must end in one of {', '.join(FORMATS)}")
    if args.duration is not None and not 0.5 <= args.duration <= 30:
        ap.error("--duration is 0.5 to 30 seconds")
    if not 0 <= args.influence <= 1:
        ap.error("--influence is 0 to 1")
    outs = output_paths(args.out, args.n, args.add)
    taken = [p for p in outs if p.exists()]
    if taken and not args.force:
        ap.error(f"{taken[0]} exists (pass --force to overwrite)")
    text = (args.prompt if args.prompt is not None else args.prompt_file.read_text()).strip()

    fmt = "mp3_44100_128" if args.out.suffix.lower() == ".mp3" else f"pcm_{args.rate}"
    url = f"{API}?output_format={fmt}"
    body = {"text": text, "model_id": args.model, "prompt_influence": args.influence,
            "loop": args.loop}
    if args.duration is not None:
        body["duration_seconds"] = args.duration
    if args.dry_run:
        print(f"POST {url}, {args.n} time(s), to {', '.join(p.name for p in outs)}")
        print(json.dumps(body, indent=2))
        sys.exit()

    key = api_key()
    start = time.monotonic()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    ids, lengths = [], []
    for i, path in enumerate(outs):
        print(f"Clip {i + 1}/{args.n}...", file=sys.stderr)
        data, request_id = request(url, body, key)
        lengths.append(round(save(path, data, args.rate), 2))
        ids.append(request_id)
        print(path)
    meta_path = (outs[0] if args.add else args.out).with_name(
        f"{(outs[0] if args.add else args.out).stem}.prompt.json")
    meta_path.write_text(json.dumps({
        "prompt": text, "prompt_file": str(args.prompt_file) if args.prompt_file else None,
        **{k: v for k, v in body.items() if k != "text"}, "output_format": fmt, "n": args.n,
        "created": int(time.time()), "request_ids": ids, "seconds": lengths}, indent=2) + "\n")
    print(f"{len(outs)} clip(s) in {time.monotonic() - start:.0f} s, "
          f"settings in {meta_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
