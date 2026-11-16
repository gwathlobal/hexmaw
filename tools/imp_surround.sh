#!/bin/bash
# How well a pack of imps surrounds the player, with the flank leap on and off
# (tools/imp_surround.lisp). Drives the running game (tools/hd): it starts the debug level with
# only its hall imps and runs TRIALS trials of 20 s for each configuration, then prints the
# means. Leaves the debug level with *debug-hall-monsters* on.
#
#   tools/imp_surround.sh [TRIALS] [MODES]
#
# TRIALS defaults to 5; MODES to "track strafe" (:track, the player facing the nearest imp and
# backing off; :strafe, facing north and strafing). Each mode runs with the leap off and on, and
# the shield down and up: 4 configurations a mode, 20 s a trial.
set -e
cd "$(dirname "$0")/.."
trials=${1:-5}
modes=${2:-track strafe}

configs=""
for mode in $modes; do
  for shield in nil t; do
    for leaps in nil t; do
      configs="$configs (list $leaps $shield :$mode)"
    done
  done
done

tools/hd '(progn (setf *debug-hall-monsters* t *debug-level-monsters* (list (quote imp)) *revive-time* nil) (game (start-debug-level)))' > /dev/null
until [ "$(tools/hd '*game-state*')" = ":PLAYING" ]; do sleep 1; done
tools/hd '(cl:load "tools/imp_surround.lisp")' > /dev/null
tools/hd "(game (run-surround (list $configs) $trials))" > /dev/null
until [ "$(tools/hd '(surround-done-p)')" = "T" ]; do sleep 5; done
tools/hd '(princ (surround-report))'
