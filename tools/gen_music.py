#!/usr/bin/env python3
"""Generate a music track with ElevenLabs' music model (Eleven Music) and save it into the project.

  tools/gen_music.py audio/music/explore.mp3 --prompt-file audio/prompts/music-explore.txt \\
      --length 90

The prompt is --prompt TEXT or --prompt-file PATH (keep prompts worth repeating in files).
It describes the music in words: genre, mood, instruments, tempo, structure. Artists' and
works' names are refused. The format follows the output's extension, as in gen_sfx.py:
.mp3 (44.1 kHz, 128 kbit/s) or .wav (16-bit stereo PCM at --rate). With -n 2 the tracks
go to <stem>-1.mp3, <stem>-2.mp3, one request each. Existing files are never overwritten
unless --force is given, and <stem>.prompt.json records the prompt and options.

--length is 10 to 300 seconds. Tracks are instrumental unless --vocals is given.

The key is gen_sfx.py's ($ELEVENLABS_API_KEY or ~/.config/elevenlabs/api_key), with the
Music permission, on a paid plan (the free one refuses music). Music costs about 12 credits
a second (a 60 s track took about 715), against about 10 for sound effects.

--dry-run prints the request instead of sending it.
"""

import argparse
import json
import sys
import time
from pathlib import Path

from gen_sfx import FORMATS, api_key, output_paths, request, save

API = "https://api.elevenlabs.io/v1/music"


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path, help="output track (.mp3 or .wav)")
    prompt = ap.add_mutually_exclusive_group(required=True)
    prompt.add_argument("--prompt", "-p")
    prompt.add_argument("--prompt-file", "-f", type=Path)
    ap.add_argument("--length", "-l", type=float, default=60, help="seconds, 10 to 300")
    ap.add_argument("--vocals", action="store_true", help="allow vocals")
    ap.add_argument("--rate", type=int, default=44100, choices=[16000, 22050, 24000, 44100],
                    help="sample rate of a .wav")
    ap.add_argument("--model", default="music_v1")
    ap.add_argument("-n", type=int, default=1, help="number of tracks")
    ap.add_argument("--force", action="store_true", help="overwrite existing outputs")
    ap.add_argument("--dry-run", action="store_true", help="print the request, send nothing")
    args = ap.parse_args()

    if args.out.suffix.lower() not in FORMATS:
        ap.error(f"output must end in one of {', '.join(FORMATS)}")
    if not 10 <= args.length <= 300:
        ap.error("--length is 10 to 300 seconds")
    outs = output_paths(args.out, args.n)
    taken = [p for p in outs if p.exists()]
    if taken and not args.force:
        ap.error(f"{taken[0]} exists (pass --force to overwrite)")
    text = (args.prompt if args.prompt is not None else args.prompt_file.read_text()).strip()

    fmt = "mp3_44100_128" if args.out.suffix.lower() == ".mp3" else f"pcm_{args.rate}"
    url = f"{API}?output_format={fmt}"
    body = {"prompt": text, "music_length_ms": int(args.length * 1000), "model_id": args.model,
            "force_instrumental": not args.vocals}
    if args.dry_run:
        print(f"POST {url}, {args.n} time(s)")
        print(json.dumps(body, indent=2))
        sys.exit()

    key = api_key()
    start = time.monotonic()
    args.out.parent.mkdir(parents=True, exist_ok=True)
    ids, lengths = [], []
    for i, path in enumerate(outs):
        print(f"Track {i + 1}/{args.n}...", file=sys.stderr)
        data, request_id = request(url, body, key)
        lengths.append(round(save(path, data, args.rate), 1))
        ids.append(request_id)
        print(path)
    meta_path = args.out.with_name(f"{args.out.stem}.prompt.json")
    meta_path.write_text(json.dumps({
        "prompt": text, "prompt_file": str(args.prompt_file) if args.prompt_file else None,
        **{k: v for k, v in body.items() if k != "prompt"}, "output_format": fmt, "n": args.n,
        "created": int(time.time()), "request_ids": ids, "seconds": lengths}, indent=2) + "\n")
    print(f"{len(outs)} track(s) in {time.monotonic() - start:.0f} s, "
          f"settings in {meta_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
