#!/bin/bash
# The hands for Absorb, healing and ward spells (CLAUDE.md, the casting hands): their own magic, not
# fire. Every pose takes the rest pose as its third reference, so the gauntlets stay the same.
cd "$(dirname "$0")/../.."
P=art/prompts
REFS="--ref art/sword-shield/ref-sword-idle.png --ref art/spear/idle-2.png --ref art/hands/idle-2.png"
for pose in absorb-void absorb-idle heal-idle heal-rise heal-wrap heal-fade ward-idle ward-push ward-pane ward-fade; do
  tools/gen_image.py art/hands/$pose.png --prompt "$(cat $P/hands-common-magic.txt $P/hands-$pose.txt $P/hands-follow-magic.txt)" $REFS --size 1536x1024 -n 2
done
