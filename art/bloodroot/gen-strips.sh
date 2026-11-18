#!/usr/bin/env bash
# The bloodroot's strips, one generation at a time (art/prompts/bloodroot-*.txt), from the chosen design.
cd "$(dirname "$0")/../.." || exit 1
P=art/prompts
D=art/bloodroot/design-2.png
A=art/style/anchor.png
for anim in idle attacks death snare; do
  tools/gen_image.py art/bloodroot/$anim.png --prompt "$(cat $P/bloodroot-$anim.txt $P/bloodroot-common.txt $P/style-common.txt)" \
      --ref $D --ref $A --size 1536x1024 -n 2
done
tools/gen_image.py art/spells/blood-seed.png --prompt "$(cat $P/blood-seed.txt $P/style-common.txt)" --ref $D --ref $A --size 1536x1024 -n 2
tools/gen_image.py art/textures/bloodroot.png --prompt "$(cat $P/texture-bloodroot.txt)" --ref $D --ref $A --size 1024x1024 -n 2
tools/gen_image.py art/bloodroot/tendrils.png --prompt "$(cat $P/bloodroot-tendrils.txt $P/style-common.txt)" --ref $D --ref $A --ref art/bloodroot/snare-1.png --size 1536x1024 -n 2
tools/gen_image.py art/bloodroot/snare-grip.png --prompt "$(cat $P/bloodroot-snare-grip.txt $P/bloodroot-common.txt $P/style-common.txt)" --ref $D --ref $A --ref art/bloodroot/snare-1.png --size 1536x1024 -n 2
