#!/usr/bin/env bash
# Staged screenshots for comparing the art before and after a change ("House style" in CLAUDE.md):
# where groups of art meet on screen. Runs on the debug level with its hall monsters.
#
#   tools/art_shots.sh /some/dir            every shot, at the window's size
#   SHOTS="burst hands" tools/art_shots.sh /some/dir
#   ROWS=720 tools/art_shots.sh /some/dir   resize the window first (1280x720; ROWS=1080: 1920x1080)
#
# Each shot puts the level back (reset-run), places the player and a creature, lets the scene run
# WAIT seconds (an effect's frames), then freezes it with hit-stop and saves <dir>/<shot>.png.
# The game is left paused. It rebuilds the debug level first (reload-scene) when the hall has no
# monsters.

set -euo pipefail
dir="${1:?usage: tools/art_shots.sh OUTDIR}"
hd="$(dirname "$0")/hd"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"

case "${ROWS:-}" in
  720) "$hd" '(game (trial:resize *context* 1280 720) T)' >/dev/null ;;
  1080) "$hd" '(game (trial:resize *context* 1920 1080) T)' >/dev/null ;;
esac

if [ "$("$hd" '(if (and (eq *level* :test) *debug-hall-monsters*) 1 0)')" != 1 ]; then
  "$hd" '(progn (setf *debug-hall-monsters* t) (game (start-debug-level)) T)' >/dev/null
  sleep 6
fi

# player X Z PITCH YAW, on the hall floor
player() {
  echo "(let ((f (feet *player*)) (r (rotation *player*)) (v (velocity *player*)))
          (setf (vx f) $1 (vy f) 0.0 (vz f) $2 (vx r) $3 (vy r) $4
                (vx v) 0.0 (vy v) 0.0 (vz v) 0.0))"
}

# put CLASS X Z FACING: the first creature of CLASS, standing there, idle
put() {
  echo "(let ((c (find-if (lambda (c) (typep c '$1)) *creatures*)))
          (setf (vx (location c)) $2 (vz (location c)) $3 (facing c) $4)
          (stop-walking c 5.0))"
}

# hold KEY: what hotbar key KEY holds (debug level: 1 sword, 2 bolt, 3 spear, 4 tempest, 5 heal,
# 6 maul), in hand at once
hold() {
  echo "(progn (select-weapon *player* :$1) (settle-held *player*) (setf (weapon-lower *player*) 0.0))"
}

# shot NAME WAIT FORM...: stage the scene, let it run WAIT seconds, freeze and save it.
shot() {
  local name="$1" wait="$2"; shift 2
  if [[ -n "${SHOTS:-}" && " $SHOTS " != *" $name "* ]]; then return; fi
  "$hd" "(game (reset-run) (setf *game-state* :playing *hit-stop* 0.0) $* T)" >/dev/null
  sleep "$wait"
  "$hd" "(game (setf *hit-stop* 1000.0) T)" >/dev/null
  sleep 0.3
  "$hd" "(screenshot \"$dir/$name.png\")"
}

area_spell="(spec-spell '(art-burst :projectile (:kind :damage :magnitude (5 5) :area 2.0
                                                 :target-type :target :element :frost)))"

shot imp-wall    0.05 "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 1)"
shot imp-torch   0.05 "$(player 5.6 0.3 0.0 1.5708)" "$(put imp 8.9 0.5 4.7124)" "$(hold 2)"
shot knight      0.05 "$(player -2.0 2.0 0.0 0.0)" "$(put knight -2.0 -1.5 3.1416)" "$(hold 1)"
shot hands       0.12 "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -4.0 3.1416)" "$(hold 2)" \
                 "(player-cast *player* (held-spell *player*))"
shot spear       0.05 "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 3)"
shot maul        0.05 "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 6)"
shot bolt        0.08 "$(player 0.0 1.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 2)" \
                 "(cast-spell (find-spell 'bolt) (vec 0.0 1.3 -0.6) (vec 0 0 -1) (scene +main+))"
shot burst       0.12 "$(player 0.0 2.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 2)" \
                 "(play-impact $area_spell (vec 0.0 0.8 -2.5) (scene +main+))"
shot aura        0.4  "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -3.0 3.1416)" "$(hold 1)" \
                 "(afflict (find-if (lambda (c) (typep c 'imp)) *creatures*) :damage 1 8.0 :element :fire :caster *player*)"
shot circle      1.0  "$(player 0.0 2.0 0.25 0.0)" "$(hold 1)" \
                 "(cast-spell (find-spell 'grave-spikes) (vec 0.0 0.0 -2.5) (vec 0 0 1) (scene +main+))"
shot flash      0.04 "$(player 0.0 0.0 0.0 0.0)" "$(put imp 0.0 -2.5 3.1416)" "$(hold 1)" \
                 "(let ((c (find-if (lambda (c) (typep c 'imp)) *creatures*))) (setf (flash c) *flash-time*))"
shot lava        0.3  "$(player -7.5 9.5 0.45 0.0)" "$(hold 1)"
shot pickups     0.05 "$(player -2.5 5.0 0.3 3.1416)" "$(hold 1)"
shot boss        0.05 "$(player -2.0 29.0 -0.05 3.1416)" "$(hold 1)"
shot corridor    0.05 "$(player 0.0 -8.5 0.0 0.0)" "$(hold 2)"

"$hd" "(game (setf *hit-stop* 0.0 *game-state* :paused) T)" >/dev/null
