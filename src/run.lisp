(in-package #:hexmaw)

;;; A run: generated levels one after another, *RUN-LEVELS* of them. The run has a seed, and
;;; each level's seed comes from it and the level's depth, so a run always builds the same
;;; levels. The way down is one-way: the old level is left behind with its scene, and only
;;; what the player carries goes on (*CARRIED-SLOTS*), along with a record of each level
;;; left (LEVEL-RECORD), which is what the run's totals add up.

(defparameter *run-levels*
  '((:rooms 16 :exit "descent" :altar-chance 0.4)
    (:rooms 19 :exit "descent" :altar-chance 0.4)
    (:rooms 22 :exit "arena" :altar-chance 0.4))
  "A run's levels, first to last: how many rooms the generator aims for, the block it puts on
the doorway furthest from the start (or a list of them, tried in order): the descent, whose
exit leaves the level, or the last level's arena, whose boss ends the run (boss.lisp), NIL for
no such block; and the chance of a spellforge altar room (forge.lisp), besides the town's.")

(defvar *run-depth* 1 "Which of *RUN-LEVELS* the player is on, from 1.")
(defvar *run-seed* NIL "The run's seed, or NIL until a level needs one.")
(defparameter *level-seed* NIL "Fixes the run's seed, and so its first level's, or NIL for a new one every run.")
(defvar *last-level-seed* NIL "The seed of the last generated level, to build it again.")

(defparameter *carried-slots*
  '(health mana inventory quickslot stamina winded run-time damage-taken level-records
    known-effects spellbook active-spell enchantments)
  "The player's slots that go on to the next level; the rest start fresh (RESET-PLAYER).
SETUP-SCENE carries the weapon anyway.")

(defvar *carried-state* NIL
  "CARRIED-STATE of the player leaving a level, while the next one is built, else NIL.")

(defparameter *max-level-attempts* 8
  "How many seeds a level may try for one whose exit fits and can be reached (BUILD-LEVEL).")

(defun run-length () (length *run-levels*))

(defun run-level-property (depth key)
  (getf (nth (1- depth) *run-levels*) key))

(defun current-run-seed ()
  "The seed this run's levels come from, picked when first asked for; *LEVEL-SEED* fixes it for testing."
  (cond (*level-seed* (setf *run-seed* *level-seed*))
        (*run-seed*)
        (T (setf *run-seed* (random most-positive-fixnum (make-random-state T))))))

(defun level-seed (run-seed depth &optional (attempt 0))
  "The seed of level DEPTH of the run RUN-SEED, on its ATTEMPTth try. The first try at the
first level is RUN-SEED itself."
  (let ((random (sb-ext:seed-random-state run-seed))
        (seed run-seed))
    (loop repeat (+ (* (1- depth) *max-level-attempts*) attempt)
          do (setf seed (random most-positive-fixnum random)))
    seed))

(defun carried-state (player)
  (loop for name in *carried-slots*
        collect (cons name (encode-value (saved-value player name)))))

(defun level-record ()
  "The level the player is on, as the run's totals count it."
  (let ((summary (run-summary)))
    (list :monsters (getf summary :monsters)
          :slain (getf summary :slain)
          :blocks (length *map-blocks*)
          :explored (length (revealed-block-indices))
          :seed *last-level-seed*)))

(defun run-totals (player)
  "The run so far, the level PLAYER is on included, as a plist of :MONSTERS, :SLAIN, :BLOCKS and :EXPLORED."
  (let ((records (cons (level-record) (level-records player))))
    (loop for key in '(:monsters :slain :blocks :explored)
          collect key
          collect (reduce #'+ records :key (lambda (record) (getf record key))))))
