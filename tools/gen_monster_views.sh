#!/usr/bin/env bash
# Generate one animation sheet per view for a monster, the knight's way (CLAUDE.md,
# "Monster sprites"): art/prompts/<who>-<anim>-common.txt plus <who>-view-<view>.txt,
# referencing the turnaround and art/<who>/stand-<view>.png. The front-quarter adds
# <who>-view-front-quarter-strict.txt and no front sheet; the side and back views add
# <who>-follow.txt with the finished front sheet as the third reference.
#
#   tools/gen_monster_views.sh WHO ANIM TURNAROUND VIEW... [-- FRONT-SHEET]
#
# Writes art/<who>/<anim>-<view>.png (existing ones are kept).
set -u
who=$1 anim=$2 turnaround=$3; shift 3
views=(); front=""
while [ $# -gt 0 ]; do
  if [ "$1" = "--" ]; then front=$2; shift 2; else views+=("$1"); shift; fi
done
for view in "${views[@]}"; do
  out="art/$who/$anim-$view.png"
  [ -e "$out" ] && continue
  prompt="$(cat "art/prompts/$who-$anim-common.txt" "art/prompts/$who-view-$view.txt")"
  refs=(--ref "$turnaround" --ref "art/$who/stand-$view.png")
  case $view in
    front) ;;
    front-quarter) prompt="$prompt"$'\n'"$(cat "art/prompts/$who-view-front-quarter-strict.txt")" ;;
    *) prompt="$prompt"$'\n\n'"$(cat "art/prompts/$who-follow.txt")"; refs+=(--ref "$front") ;;
  esac
  tools/gen_image.py "$out" --prompt "$prompt" "${refs[@]}" --size 1536x1024
done
