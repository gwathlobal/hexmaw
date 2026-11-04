#!/usr/bin/env bash
# Take a fixed set of screenshots from the running game, for comparing renderers.
#
#   tools/compare_shots.sh screenshots/compare/ours
#   SHOTS="spawn bolt" tools/compare_shots.sh /tmp/out    only those shots
#
# Each shot puts the level back (reset-run), freezes the world with hit-stop, places
# the player and the imps, and saves <dir>/<shot>.png. The game is left paused.

set -euo pipefail
dir="${1:?usage: tools/compare_shots.sh OUTDIR}"
hd="$(dirname "$0")/hd"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

# player X Y Z PITCH YAW
player() {
  echo "(let ((f (feet *player*)) (r (rotation *player*)) (v (velocity *player*)))
          (setf (vx f) $1 (vy f) $2 (vz f) $3 (vx r) $4 (vy r) $5
                (vx v) 0.0 (vy v) 0.0 (vz v) 0.0))"
}

# imp INDEX X Z FACING
imp() {
  echo "(let ((c (aref *creatures* $1)))
          (setf (vx (location c)) $2 (vz (location c)) $3 (facing c) $4))"
}

# weapon :hands (the bolt, hotbar key 2) or :sword (key 1), in hand at once
weapon() {
  local key=:2
  [ "$1" = ":sword" ] && key=:1
  echo "(progn (select-weapon *player* $key) (settle-held *player*) (setf (weapon-lower *player*) 0.0))"
}

# shot NAME FORM...: set the scene up with the forms, let it draw, save the frame.
shot() {
  local name="$1"; shift
  if [[ -n "${SHOTS:-}" && " $SHOTS " != *" $name "* ]]; then return; fi
  "$hd" "(game (reset-run) (setf *game-state* :playing *hit-stop* 1000.0) $* T)" >/dev/null
  sleep 0.4
  "$hd" "(screenshot \"$dir/$name.png\")"
}

shot spawn        "$(player 0.0 0.0 5.0 0.0 0.0)" "$(weapon :hands)"
shot imp-front    "$(player 0.0 0.0 0.0 0.0 0.0)" "$(imp 0 0.0 -3.0 3.1416)" "$(weapon :hands)"
shot imp-close    "$(player 0.0 0.0 -1.6 0.1 0.0)" "$(imp 0 0.0 -3.0 3.1416)" "$(weapon :sword)"
shot imp-quarter  "$(player 2.5 0.0 -0.5 0.05 5.4978)" "$(imp 0 0.0 -3.0 3.1416)" "$(weapon :hands)"
shot imp-far      "$(player -2.0 0.0 8.0 0.0 0.436)" "$(imp 0 1.5 0.5 3.58)" "$(weapon :hands)"
shot pillar       "$(player -2.2 0.0 -2.2 0.15 5.4978)" "$(weapon :hands)"
shot bolt         "$(player 0.0 0.0 1.0 0.0 0.0)" "$(imp 0 0.0 -3.0 3.1416)" "$(weapon :hands)" \
                  "(cast-spell (find-spell 'bolt) (vec 0.0 1.3 -0.6) (vec 0 0 -1) (scene +main+))"
shot corridor     "$(player 0.0 0.0 -8.5 0.0 0.0)" "$(weapon :hands)"
shot imp-torch    "$(player 5.6 0.0 0.3 0.0 1.5708)" "$(imp 0 8.9 0.5 4.7124)" "$(weapon :hands)"
shot shrine       "$(player 0.0 0.0 -26.0 0.05 0.0)" "$(weapon :hands)"

"$hd" "(game (setf *hit-stop* 0.0 *game-state* :paused) T)" >/dev/null
