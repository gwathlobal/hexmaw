#!/usr/bin/env python3
"""Generate or restyle an image with OpenAI's image models and save it into the project.

  tools/gen_image.py art/imp/walk-front.png --prompt-file art/prompts/imp-walk.txt \\
      --ref "art/imp/Pixel Demon Character Turnaround.png" --size 1536x1024

The prompt is --prompt TEXT or --prompt-file PATH (keep prompts worth repeating in files).
--ref images (repeatable) go along as references: a design reference, a turnaround sheet
or a Blender render to restyle. The output format follows the output's extension (.png,
.webp, .jpg). With -n 3 the images go to <stem>-1.png, <stem>-2.png, <stem>-3.png.
Existing files are never overwritten unless --force is given. Next to the output,
<stem>.prompt.json records the prompt, references and options, so a good result can be
reproduced or varied.

Two backends:

--backend codex (the default) runs the Codex CLI (`codex exec`, signed in with ChatGPT)
and has its built-in image tool draw the prompt, so images count against the ChatGPT
plan's Codex allowance instead of being billed. Codex runs in an empty temp folder with
its shell, plugins, browser and sub-agents off, so all it can do is generate. Size and
background are passed on as requests in the prompt (1536x1024 came back exact; without
one a square is 1254 x 1254), and --quality is ignored. One image per Codex run, about
45 s each; -n runs it n times. The image is moved out of ~/.codex/generated_images.

--backend api calls the Image API (POST /v1/images/generations, or /v1/images/edits with
--ref), billed per image. The key comes from $OPENAI_API_KEY, or else from
~/.config/openai/api_key (one line). Here --size is "auto" or WIDTHxHEIGHT: both multiples
of 16, aspect between 1:3 and 3:1, at most 3840 on an edge, and is honoured exactly.
--mask is a PNG the size of the first reference whose transparent pixels mark where the
image may change (API only).

--dry-run prints the request instead of sending it.
"""

import argparse
import base64
import io
import json
import mimetypes
import os
import shutil
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
import uuid
from pathlib import Path

from PIL import Image

API = "https://api.openai.com/v1/images"
KEY_FILE = Path.home() / ".config/openai/api_key"
CODEX_HOME = Path(os.environ.get("CODEX_HOME", Path.home() / ".codex"))
FORMATS = {".png": "png", ".webp": "webp", ".jpg": "jpeg", ".jpeg": "jpeg"}
# Python 3.10's mimetypes doesn't know .webp.
MIME = {".png": "image/png", ".webp": "image/webp", ".jpg": "image/jpeg", ".jpeg": "image/jpeg"}
# Everything Codex could do besides calling its image tool.
CODEX_OFF = ["shell_tool", "unified_exec", "multi_agent", "plugins", "apps", "browser_use",
             "browser_use_external", "computer_use", "in_app_browser", "skill_search",
             "tool_suggest", "goals", "hooks"]
CODEX_TASK = """\
Use your built-in image generation tool exactly once to generate one image. Pass it the
prompt between the PROMPT lines below word for word: do not shorten, reword or add to it.
{refs}Do not do anything else. Reply with only the path of the saved image.

PROMPT
{prompt}
PROMPT
"""


def api_key():
    key = os.environ.get("OPENAI_API_KEY", "").strip()
    if not key and KEY_FILE.exists():
        key = KEY_FILE.read_text().strip()
    if not key:
        sys.exit(f"No API key: set OPENAI_API_KEY or put the key in {KEY_FILE}")
    return key


def multipart(fields, files):
    """Encode form fields and (name, path) files as multipart/form-data."""
    boundary = uuid.uuid4().hex
    out = bytearray()
    for name, value in fields.items():
        out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"\r\n\r\n"
                f"{value}\r\n").encode()
    for name, path in files:
        ctype = MIME.get(path.suffix.lower()) or mimetypes.guess_type(path.name)[0]
        out += (f"--{boundary}\r\nContent-Disposition: form-data; name=\"{name}\"; "
                f"filename=\"{path.name}\"\r\nContent-Type: {ctype}\r\n\r\n").encode()
        out += path.read_bytes() + b"\r\n"
    out += f"--{boundary}--\r\n".encode()
    return bytes(out), f"multipart/form-data; boundary={boundary}"


def output_paths(out, n):
    if n == 1:
        return [out]
    return [out.with_name(f"{out.stem}-{i}{out.suffix}") for i in range(1, n + 1)]


def save(path, data, fmt):
    """Write image bytes to path, converting them when they aren't already in fmt."""
    img = Image.open(io.BytesIO(data))
    if img.format.lower() == fmt:
        path.write_bytes(data)
    else:
        (img.convert("RGB") if fmt == "jpeg" else img).save(path, fmt)


def run_api(args, text, fmt):
    """Ask the Image API for args.n images. Returns (image bytes list, metadata)."""
    fields = {"model": args.model, "prompt": text, "n": args.n, "size": args.size,
              "quality": args.quality, "background": args.background, "output_format": fmt}
    if args.ref:
        url = f"{API}/edits"
        files = [("image[]", p) for p in args.ref] + ([("mask", args.mask)] if args.mask else [])
    else:
        url = f"{API}/generations"
        files = []
    if args.dry_run:
        print(f"POST {url}")
        print(json.dumps({**fields, "files": [f"{n}={p}" for n, p in files]}, indent=2))
        sys.exit()

    headers = {"Authorization": f"Bearer {api_key()}"}
    if files:
        body, headers["Content-Type"] = multipart(fields, files)
    else:
        body, headers["Content-Type"] = json.dumps(fields).encode(), "application/json"
    print(f"Asking {args.model} for {args.n} image(s)"
          f"{f' from {len(args.ref)} reference(s)' if args.ref else ''}...", file=sys.stderr)
    try:
        with urllib.request.urlopen(urllib.request.Request(url, body, headers),
                                    timeout=600) as resp:
            request_id = resp.headers.get("x-request-id")
            result = json.load(resp)
    except urllib.error.HTTPError as e:
        detail = e.read().decode(errors="replace")
        try:
            detail = json.loads(detail)["error"]["message"]
        except (ValueError, KeyError, TypeError):
            pass
        sys.exit(f"HTTP {e.code} ({e.headers.get('x-request-id')}): {detail}")
    for item in result["data"]:
        if item.get("revised_prompt"):
            print(f"  revised prompt: {item['revised_prompt']}", file=sys.stderr)
    meta = {**{k: v for k, v in fields.items() if k != "prompt"}, "request_id": request_id,
            "result_size": result.get("size"), "usage": result.get("usage")}
    return [base64.b64decode(item["b64_json"]) for item in result["data"]], meta


def codex_prompt(args, text):
    """The image prompt with the size and background requests Codex can't set itself."""
    extra = []
    if args.size != "auto":
        w, h = (int(v) for v in args.size.split("x"))
        extra.append(f"Image size: {w}x{h} pixels ({'landscape' if w > h else 'portrait' if h > w else 'square'}).")
    if args.background != "auto":
        extra.append(f"Background: {args.background}.")
    return "\n".join([text.rstrip()] + extra)


def run_codex_once(args, task, refs, work):
    """One codex exec run. Returns (image bytes, thread id)."""
    cmd = ["codex", "exec", "--skip-git-repo-check", "--ignore-user-config", "--ignore-rules",
           "--ephemeral", "--json", "-s", "read-only", "-C", str(work),
           "-o", str(work / "last.txt")]
    for feature in CODEX_OFF:
        cmd += ["--disable", feature]
    for ref in refs:
        cmd += ["-i", str(ref)]
    proc = subprocess.run(cmd + ["-"], input=task, capture_output=True, text=True, timeout=900)
    thread = None
    for line in proc.stdout.splitlines():
        try:
            event = json.loads(line)
        except ValueError:
            continue
        if event.get("type") == "thread.started":
            thread = event["thread_id"]
        elif event.get("type") in ("error", "turn.failed"):
            print(f"  codex: {json.dumps(event)}", file=sys.stderr)
    folder = CODEX_HOME / "generated_images" / str(thread)
    images = sorted(folder.glob("*.png"), key=lambda p: p.stat().st_mtime) if thread else []
    if proc.returncode != 0 or not images:
        last = (work / "last.txt").read_text() if (work / "last.txt").exists() else ""
        sys.exit(f"Codex made no image (exit {proc.returncode}).\n{proc.stderr[-2000:]}\n{last}")
    data = images[-1].read_bytes()
    shutil.rmtree(folder)
    return data, thread


def run_codex(args, text):
    """Have Codex's image tool draw args.n images, one run each."""
    if not shutil.which("codex"):
        sys.exit("No codex on PATH: install the Codex CLI and run `codex login`")
    if args.mask:
        sys.exit("--mask needs --backend api")
    prompt = codex_prompt(args, text)
    refs = ""
    if args.ref:
        refs = (f"Give the image tool the {len(args.ref)} attached image(s) as reference "
                "images; the prompt says how to use them.\n")
    task = CODEX_TASK.format(refs=refs, prompt=prompt)
    if args.dry_run:
        print(f"codex exec, {args.n} run(s), references: {[str(p) for p in args.ref]}")
        print(task)
        sys.exit()
    if args.quality != "auto":
        print("  --quality has no effect with the codex backend", file=sys.stderr)

    images, threads = [], []
    with tempfile.TemporaryDirectory(prefix="gen_image-") as tmp:
        work = Path(tmp)
        # Codex splits -i values on commas, so the references go in under plain names.
        refs = []
        for i, ref in enumerate(args.ref, 1):
            refs.append(work / f"ref-{i}{ref.suffix.lower()}")
            shutil.copyfile(ref, refs[-1])
        for i in range(args.n):
            print(f"Codex run {i + 1}/{args.n}"
                  f"{f' with {len(refs)} reference(s)' if refs else ''}...", file=sys.stderr)
            data, thread = run_codex_once(args, task, refs, work)
            images.append(data)
            threads.append(thread)
    return images, {"size_request": args.size, "background": args.background,
                    "codex_prompt": prompt, "codex_threads": threads}


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("out", type=Path, help="output image (.png, .webp or .jpg)")
    prompt = ap.add_mutually_exclusive_group(required=True)
    prompt.add_argument("--prompt", "-p")
    prompt.add_argument("--prompt-file", "-f", type=Path)
    ap.add_argument("--ref", "-r", type=Path, action="append", default=[],
                    help="reference image (repeatable, up to 16)")
    ap.add_argument("--backend", default="codex", choices=["codex", "api"])
    ap.add_argument("--mask", type=Path, help="PNG mask for the first reference (api only)")
    ap.add_argument("--model", default="gpt-image-2.5-sunburst", help="image model (api only)")
    ap.add_argument("--size", default="auto")
    ap.add_argument("--quality", default="auto",
                    choices=["auto", "low", "medium", "high", "xhigh", "max"])
    ap.add_argument("--background", default="auto", choices=["auto", "opaque", "transparent"])
    ap.add_argument("-n", type=int, default=1, help="number of images (1 to 10)")
    ap.add_argument("--force", action="store_true", help="overwrite existing outputs")
    ap.add_argument("--dry-run", action="store_true", help="print the request, send nothing")
    args = ap.parse_args()

    fmt = FORMATS.get(args.out.suffix.lower())
    if not fmt:
        ap.error(f"output must end in one of {', '.join(FORMATS)}")
    if args.size != "auto" and not all(v.isdigit() for v in args.size.split("x", 1)):
        ap.error("--size is auto or WIDTHxHEIGHT")
    if args.mask and not args.ref:
        ap.error("--mask needs a --ref to apply to")
    for path in args.ref + ([args.mask] if args.mask else []):
        if not path.is_file():
            ap.error(f"no such file: {path}")
    outs = output_paths(args.out, args.n)
    taken = [p for p in outs if p.exists()]
    if taken and not args.force:
        ap.error(f"{taken[0]} exists (pass --force to overwrite)")
    text = args.prompt if args.prompt is not None else args.prompt_file.read_text()

    start = time.monotonic()
    images, meta = run_api(args, text, fmt) if args.backend == "api" else run_codex(args, text)
    args.out.parent.mkdir(parents=True, exist_ok=True)
    for path, data in zip(outs, images):
        save(path, data, fmt)
        print(path)
    meta_path = args.out.with_name(f"{args.out.stem}.prompt.json")
    meta_path.write_text(json.dumps({
        "prompt": text, "prompt_file": str(args.prompt_file) if args.prompt_file else None,
        "refs": [str(p) for p in args.ref], "mask": str(args.mask) if args.mask else None,
        "backend": args.backend, "n": args.n, "created": int(time.time()), **meta,
        "sizes": [list(Image.open(p).size) for p in outs[:len(images)]]}, indent=2) + "\n")
    print(f"{len(images)} image(s) in {time.monotonic() - start:.0f} s, "
          f"settings in {meta_path}", file=sys.stderr)


if __name__ == "__main__":
    main()
