#!/usr/bin/env python3
"""Cut a seamless loop out of a generated music track and encode it for the game.

  tools/make_loop.py audio/music/combat-1.wav data/music/combat-1.ogg --min-loop 50

Looks for two moments A and B in the track (a 16-bit stereo .wav) whose harmony and sound
match: chroma and 24 log-spaced bands, compared over 3 s either side. A lies from --start
on, B at least --min-loop seconds after it and --fade seconds before the track's fade-out
(found by loudness, or --end). B is then moved by up to 0.3 s to where the waveforms line
up best. The loop is A to B, its first --fade seconds crossfaded (equal power) from what
follows B, so B runs on into A. It goes to <src>-loop.wav, then through GStreamer to Ogg
Vorbis at OUT (--quality, 0.5 by default), checked to say it holds the same number of
samples (its last page's granule position), so it still loops seamlessly.

A score is the mean per-frame chroma distance plus 0.15 times the band distance: lower is
closer. The run prints the best candidates and what the same passage scores 1 s on, for
scale; a match under that joins about as smoothly as the music runs on. --pick N takes the
Nth candidate instead of the best. --preview PATH writes the loop's last 8 s running into
its first 8 s, to listen to the join.

--loudness LUFS sets the loop's integrated loudness (BS.1770: K-weighted, gated), so tracks
of one mood sound equally loud whatever the generator made of them: the game's exploration
loops are -14, its combat loops -11. A gain that would push peaks past -0.2 dBFS is caught by
a look-ahead limiter, run round the loop as a circle so the join stays seamless. Every run
prints the loop's loudness either way.
"""

import argparse
import subprocess
import sys
import wave
from pathlib import Path

import numpy as np

N, H = 4096, 2048  # STFT window and hop


def read_wav(path):
    with wave.open(str(path)) as w:
        if w.getnchannels() != 2 or w.getsampwidth() != 2:
            sys.exit(f"{path}: need 16-bit stereo")
        rate = w.getframerate()
        data = np.frombuffer(w.readframes(w.getnframes()), np.int16)
    return data.reshape(-1, 2).astype(np.float64) / 32768, rate


def write_wav(path, x, rate):
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.clip(x, -1, 1) * 32767).astype(np.int16).tobytes())


def k_weighted(x, rate):
    """X through BS.1770's K-weighting, its high shelf and high-pass, applied as their magnitude
    response. The coefficients are the standard's for 48 kHz; at 44.1 kHz the curve shifts
    about 8%, which matters little when tracks are compared with each other."""
    f = np.fft.rfftfreq(len(x), 1 / rate)
    z = np.exp(-2j * np.pi * f / rate)

    def response(b, a):
        return np.abs((b[0] + b[1] * z + b[2] * z * z) / (a[0] + a[1] * z + a[2] * z * z))

    gain = (response([1.53512485958697, -2.69169618940638, 1.19839281085285],
                     [1.0, -1.69065929318241, 0.73248077421585])
            * response([1.0, -2.0, 1.0], [1.0, -1.99004745483398, 0.99007225036621]))
    return np.fft.irfft(np.fft.rfft(x, axis=0) * gain[:, None], len(x), axis=0)


def loudness(x, rate):
    """Integrated loudness in LUFS: 400 ms blocks every 100 ms, gated at -70 LUFS and then 10
    below the mean of what passed."""
    y = k_weighted(x, rate) ** 2
    block, hop = int(0.4 * rate), int(0.1 * rate)
    sums = np.concatenate([[0.0], np.cumsum(y.sum(1))])
    starts = np.arange(0, len(y) - block + 1, hop)
    power = (sums[starts + block] - sums[starts]) / block
    lk = -0.691 + 10 * np.log10(power + 1e-12)
    rel = -0.691 + 10 * np.log10(power[lk > -70].mean()) - 10
    return -0.691 + 10 * np.log10(power[lk > rel].mean())


def limit(x, rate, ceiling=10 ** (-0.2 / 20), look=0.005):
    """Keep X's peaks under CEILING: the gain each sample needs, its minimum over 2 LOOK
    seconds either side, smoothed over LOOK, so it eases down before a peak and back up after.
    X is treated as a circle, so a loop's join is limited the way the rest of it is."""
    w = int(look * rate)
    need = np.minimum(1.0, ceiling / (np.abs(x).max(1) + 1e-12))
    ring = np.concatenate([need[-2 * w:], need, need[:2 * w]])
    lowest = np.lib.stride_tricks.sliding_window_view(ring, 2 * w + 1).min(1)
    smooth = np.convolve(lowest, np.ones(w + 1) / (w + 1), "same")[w:-w]
    return x * smooth[:len(x), None], int((need < 1).sum())


def features(mono, rate):
    frames = np.lib.stride_tricks.sliding_window_view(mono, N)[::H] * np.hanning(N)
    power = np.abs(np.fft.rfft(frames, axis=1)) ** 2
    freqs = np.fft.rfftfreq(N, 1 / rate)
    sel = (freqs > 55) & (freqs < 4000)
    pitch_class = (np.round(12 * np.log2(freqs[sel] / 440)) % 12).astype(int)
    chroma = np.stack([power[:, sel][:, pitch_class == k].sum(1) for k in range(12)], 1)
    chroma /= chroma.sum(1, keepdims=True) + 1e-12
    edges = np.geomspace(40, 16000, 25)
    bands = np.log10(np.stack([power[:, (freqs >= lo) & (freqs < hi)].sum(1)
                               for lo, hi in zip(edges[:-1], edges[1:])], 1) + 1e-10)
    return chroma, bands


def fade_out_start(mono, rate):
    """Where the track's closing fade begins: the last 0.5 s window within 6 dB of its median."""
    win = rate // 2
    db = np.array([10 * np.log10(np.mean(mono[i:i + win] ** 2) + 1e-12)
                   for i in range(0, len(mono) - win, win)])
    loud = np.nonzero(db > np.median(db) - 6)[0]
    return (loud[-1] + 1) * win / rate


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("src", type=Path, help="generated track, 16-bit stereo .wav")
    ap.add_argument("out", type=Path, help="the game's loop, .ogg")
    ap.add_argument("--min-loop", type=float, default=60, help="shortest loop, seconds")
    ap.add_argument("--start", type=float, default=4, help="earliest A, seconds (skips an intro)")
    ap.add_argument("--end", type=float, help="latest B plus --fade (default: the fade-out)")
    ap.add_argument("--fade", type=float, default=4, help="crossfade at the join, seconds")
    ap.add_argument("--pick", type=int, default=1, help="take the Nth best candidate")
    ap.add_argument("--quality", type=float, default=0.5, help="Vorbis quality, -0.1 to 1")
    ap.add_argument("--preview", type=Path, help="write the join, 8 s either side, here")
    ap.add_argument("--loudness", type=float, help="integrated loudness to bring the loop to, LUFS")
    args = ap.parse_args()

    audio, rate = read_wav(args.src)
    mono = audio.mean(1)
    chroma, bands = features(mono, rate)
    fps = rate / H
    half = int(3 * fps)
    end = args.end if args.end is not None else fade_out_start(mono, rate)
    last_b = int((end - args.fade - 3) * fps)
    first_a, min_gap = max(half, int(args.start * fps)), int(args.min_loop * fps)
    if first_a + min_gap > last_b:
        sys.exit(f"no room for a {args.min_loop} s loop between {args.start} s and {end:.1f} s")

    def score(i, j):
        return (np.abs(chroma[i - half:i + half] - chroma[j - half:j + half]).sum(1).mean()
                + 0.15 * np.abs(bands[i - half:i + half] - bands[j - half:j + half]).mean())

    found = sorted((score(i, j), i, j) for i in range(first_a, last_b - min_gap, 2)
                   for j in range(i + min_gap, last_b, 2))
    picked = []
    for s, i, j in found:
        if not any(abs(i - a) < 3 * fps and abs(j - b) < 3 * fps for _, a, b in picked):
            picked.append((s, i, j))
            if len(picked) == max(5, args.pick):
                break
    step = int(fps)
    same = np.median([score(i, i + step) for i in range(half, len(chroma) - half - step, 20)])
    print(f"{args.src}: {len(mono) / rate:.1f} s, fade-out from {end:.1f} s; "
          f"the same passage 1 s on scores {same:.3f}")
    for n, (s, i, j) in enumerate(picked, 1):
        print(f"  {n}. {s:.3f}  {i / fps:6.2f} s to {j / fps:6.2f} s, {(j - i) / fps:5.1f} s")
    _, i, j = picked[args.pick - 1]

    a, b, f = int(i / fps * rate), int(j / fps * rate), int(args.fade * rate)
    lag = int(0.3 * rate)
    seg = mono[a:a + f]
    ref = mono[b - lag:b + f + lag]
    norms = np.sqrt(np.convolve(ref ** 2, np.ones(f), "valid"))
    corr = np.correlate(ref, seg, "valid") / (np.linalg.norm(seg) * norms + 1e-12)
    b += int(np.argmax(corr)) - lag
    loop = audio[a:b].copy()
    t = np.linspace(0, np.pi / 2, f)[:, None]
    loop[:f] = audio[a:a + f] * np.sin(t) + audio[b:b + f] * np.cos(t)
    loop = set_level(loop, rate, args.loudness)
    wav = args.src.with_name(f"{args.src.stem}-loop.wav")
    loop, frames = encode_loop(loop, rate, wav, args.out, args.quality)
    if args.preview:
        write_join(args.preview, loop, rate)
    print(f"loop {a / rate:.2f} s to {(a + len(loop)) / rate:.2f} s ({len(loop) / rate:.2f} s) in {wav}")
    print(f"{args.out}: {args.out.stat().st_size / 1e6:.1f} MB, holds the same {frames} frames")


def set_level(loop, rate, target):
    """LOOP brought to TARGET LUFS through the limiter, or with NIL just kept under clipping."""
    before = loudness(loop, rate)
    if target is None:
        print(f"loudness {before:.1f} LUFS")
        return loop * min(1.0, 0.99 / np.abs(loop).max())
    loop, limited = limit(loop * 10 ** ((target - before) / 20), rate)
    print(f"loudness {before:.1f} LUFS, gain {target - before:+.1f} dB to "
          f"{loudness(loop, rate):.1f}; limiter caught {limited} samples")
    return loop


def write_join(path, loop, rate, seconds=8):
    """The loop's last SECONDS running into its first, to listen to the join."""
    p = int(seconds * rate)
    write_wav(path, np.concatenate([loop[-p:], loop[:p]]), rate)


def ogg_length(path):
    """The samples an Ogg Vorbis file says it holds: the granule position of its last page,
    which a decoder trims the last packet to (stb_vorbis, the game's, does)."""
    data = Path(path).read_bytes()
    last = data.rfind(b"OggS")
    if last < 0 or not data[last + 5] & 4:
        sys.exit(f"{path}: no end-of-stream page")
    return int.from_bytes(data[last + 6:last + 14], "little")


def encode_loop(loop, rate, wav, out, quality=0.5):
    """Write LOOP to WAV and, through GStreamer, Ogg Vorbis to OUT, checking the Ogg says it
    holds the same number of frames. Returns the loop and that count.

    Decoding it back through GStreamer is no check: it turns sample positions into
    nanosecond timestamps and back, and comes out a sample or two long at some lengths."""
    out.parent.mkdir(parents=True, exist_ok=True)
    write_wav(wav, loop, rate)
    subprocess.run(["gst-launch-1.0", "-q", "filesrc", f"location={wav}", "!", "wavparse",
                    "!", "audioconvert", "!", "vorbisenc", f"quality={quality}", "!",
                    "oggmux", "!", "filesink", f"location={out}"], check=True)
    frames = ogg_length(out)
    if frames != len(loop):
        sys.exit(f"{out} holds {frames} frames, not {len(loop)}: the loop would jump")
    return loop, frames


if __name__ == "__main__":
    main()
