#!/usr/bin/env bash
# Staged screenshots of the spark pool (src/sparks.lisp): sparks off a shield, the spear's counter,
# the maul's blow, the earthshake's grit, an ogre's landing, embers off a torch and lava, and each
# blow that finds no one striking the hall's west wall, the floor and the planks (WALL-STRIKE,
# sword.lisp). Runs on the debug level with its hall monsters.
#
#   tools/spark_shots.sh /some/dir             every shot
#   SHOTS="shield maul" tools/spark_shots.sh /some/dir
#   BEFORE=1 tools/spark_shots.sh /some/dir    the same with no sparks, as before the pool
#
# Each shot puts the level back (reset-run), freezes the world with hit-stop, places the player
# and a creature, throws the particles and steps the pool by hand (STEP-SPARKS, which runs while
# frozen), so a shot is the same every time but for the particles' random throws. The game is
# left paused.

set -euo pipefail
dir="${1:?usage: tools/spark_shots.sh OUTDIR}"
hd="$(dirname "$0")/hd"
mkdir -p "$dir"
dir="$(cd "$dir" && pwd)"
before="${BEFORE:+T}"; before="${before:-NIL}"

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

# put CLASS X Z FACING: the first creature of CLASS, standing there
put() {
  echo "(let ((c (find-if (lambda (c) (typep c '$1)) *creatures*)))
          (setf (vx (location c)) $2 (vz (location c)) $3 (facing c) $4))"
}

# the first creature of CLASS
it() { echo "(find-if (lambda (c) (typep c '$1)) *creatures*)"; }

# hold KEY: what hotbar key KEY holds (1 sword, 3 spear, 6 maul), in hand at once
hold() {
  echo "(progn (select-weapon *player* :$1) (settle-held *player*) (setf (weapon-lower *player*) 0.0))"
}

# run SECONDS: step the pool (and the embers' sources) that long, in 10 ms ticks
run() {
  echo "(when *spark-pool* (dotimes (i (round $1 0.01)) (send-up-embers *spark-pool* 0.01) (step-sparks *spark-pool* 0.01)))"
}

# shot NAME FORM...: stage the scene, frozen, and save it.
shot() {
  local name="$1"; shift
  if [[ -n "${SHOTS:-}" && " $SHOTS " != *" $name "* ]]; then return; fi
  "$hd" "(game (reset-run) (setf *game-state* :playing *hit-stop* 1000.0)
              (let ((*spark-pool* (if $before NIL *spark-pool*))) $*) T)" >/dev/null
  sleep 0.4
  "$hd" "(screenshot \"$dir/$name.png\")"
}

shot shield    "$(player 0.0 -1.0 0.0 0.0)" "$(put knight 0.0 -2.8 3.1416)" "$(hold 1)" \
               "(shield-sparks $(it knight))" "$(run 0.06)"
shot counter   "$(player 0.0 -1.0 0.05 0.0)" "$(put imp 0.0 -3.2 3.1416)" "$(hold 3)" \
               "(strike-sparks $(it imp) (feet *player*) *counter-sparks*)" "$(run 0.05)"
shot maul      "$(player 0.0 -1.0 0.05 0.0)" "$(put knight 0.0 -2.9 3.1416)" "$(hold 6)" \
               "(strike-sparks $(it knight) (feet *player*) (second *maul-sparks*) :speed '(3.0 9.0))" \
               "(shield-sparks $(it knight))" "$(run 0.07)"
shot shake     "$(player 0.0 2.0 0.45 0.0)" "$(hold 6)" \
               "(kick-dust (vec 0 0 0) *shake-dust-radius* *shake-dust-puffs* (scene +main+))" \
               "(floor-sparks 0.0 0.0 0.0)" "$(run 0.12)"
shot grit      "$(player 0.0 2.0 0.45 0.0)" "$(hold 6)" \
               "(kick-dust (vec 0 0 0) *shake-dust-radius* *shake-dust-puffs* (scene +main+))" "$(run 1.0)"
shot landing   "$(player 0.0 4.0 0.15 0.0)" "$(put ogre 0.0 -2.0 3.1416)" "$(hold 1)" \
               "(kick-dust (vec 0 0 -2) (* 0.6 *quake-radius*) *ogre-dust-puffs* (scene +main+))" \
               "(floor-sparks 0.0 0.0 -0.5)" "$(run 0.1)"
shot torch     "$(player 7.2 0.3 -0.15 1.5708)" "$(hold 1)" "$(run 3.0)"
shot lava      "$(player -4.0 5.0 0.35 4.7124)" "$(hold 1)" "$(run 3.0)"

"$hd" "(game (setf *hit-stop* 0.0 *game-state* :paused) T)" >/dev/null

# A blow that finds no one, striking the hall's west wall (x -10), the floor and the planks, each
# weapon shown at its hit frame. The sparks start at its tip on screen (WEAPON-TIP-DIRECTION), so
# the strike waits a frame for the sprites to lay themselves out.
# wallshot NAME X Z PITCH YAW KEY FRAME-FORM STRIKE-FORM
wallshot() {
  local name="$1"
  if [[ -n "${SHOTS:-}" && " $SHOTS " != *" $name "* ]]; then return; fi
  "$hd" "(game (reset-run) (setf *game-state* :playing *hit-stop* 1000.0) $(player $2 $3 $4 $5) $(hold $6)
              (setf (swing-time *player*) NIL (bash-time *player*) NIL (block-raise *player*) 0.0
                    (spear-jolt *player*) 0.0 (charge-time *player*) NIL)
              (place-camera *player*) $7 T)" >/dev/null
  sleep 0.3
  "$hd" "(game (let ((*spark-pool* (if $before NIL *spark-pool*))) $8 $(run 0.05)) T)" >/dev/null
  sleep 0.4
  "$hd" "(screenshot \"$dir/$name.png\")"
}

west=4.7124
wallshot wall-sword -8.4 0.0 0.05 $west 1 "(setf (swing-time *player*) (swing-hit-time :sword))" "(wall-strike *player* :sword *sword-reach*)"
wallshot wall-spear -7.2 0.0 0.05 $west 3 "(setf (swing-time *player*) (swing-hit-time :spear))" "(wall-strike *player* :spear *spear-reach*)"
wallshot wall-maul  -8.4 0.0 0.1  $west 6 "(setf (blow-charge *player*) 1.0 (swing-time *player*) (swing-hit-time :maul))" \
         "(wall-strike *player* :maul *maul-reach* :charge 1.0)"
wallshot wall-bash  -8.9 0.0 0.05 $west 1 "(setf (block-raise *player*) 1.0 (bash-time *player*) (bash-hit-time :sword))" "(wall-strike *player* :shield *bash-reach*)"
wallshot wall-sweep -8.7 0.0 0.05 $west 3 "(setf (bash-time *player*) (bash-hit-time :spear))" "(wall-strike *player* :haft *sweep-reach*)"
wallshot wall-floor 0.0 2.0 1.1 0.0 1 "(setf (swing-time *player*) (swing-hit-time :sword))" "(wall-strike *player* :sword *sword-reach*)"
wallshot wall-wood  9.0 -3.3 0.3 0.0 1 "(setf (swing-time *player*) (swing-hit-time :sword))" "(wall-strike *player* :sword *sword-reach*)"
