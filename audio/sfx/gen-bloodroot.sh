#!/usr/bin/env bash
# The bloodroot's clips (audio/sfx.md), two takes each.
cd "$(dirname "$0")/../.." || exit 1
g(){ tools/gen_sfx.py audio/sfx/$1.wav -f audio/prompts/sfx-$1.txt -d $2 -n 2 || echo "FAILED $1"; }
g bloodroot-alert 1.2; g bloodroot-pain 0.6; g bloodroot-death 1.8; g bloodroot-spit 0.6
g seed-impact 0.7; g bloom-swell 1.2; g bloom 1.2; g root-drink 0.8
g snare-tell 0.6; g snare-grab 0.6; g snare-break 0.6; g roots-burn 0.8
