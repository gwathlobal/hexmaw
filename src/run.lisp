(in-package #:hexmaw)

;;; A run: generated levels one after another, *RUN-LEVELS* of them. The run has a seed, and
;;; each level's seed comes from it and the level's depth, so a run always builds the same
;;; levels. The way down is one-way: the old level is left behind with its scene, and only
;;; what the player carries goes on (*CARRIED-SLOTS*), along with a record of each level
;;; left (LEVEL-RECORD), which is what the run's totals add up.

(defparameter *run-levels*
  '((:rooms 16 :exit "descent" :altar-chance 0.4
     :pool (("imp" 5) ("acolyte" 2) ("knight" 2) ("harpy" 1) ("necromancer" 1))
     :loot (:weapons 1 :first-weapon :spear :enchant-chance 0.0
            :runes 1 :rune-mana (10 18) :rune-effects 1 :area-chance 0.0 :authored-chance 0.0)
     :skip-scale 1.0 :elite-chance 0.0
     :sight 1.0 :hearing 1.0 :alert 1.0 :pause 1.0 :cooldown 1.0)
    (:rooms 19 :exit "descent" :altar-chance 0.4
     :pool (("imp" 3) ("acolyte" 1) ("knight" 1) ("harpy" 1) ("necromancer" 1) ("ogre" 1) ("gale-wraith" 1)
            ("riftwalker" 1))
     :loot (:weapons 1 :enchant-chance 0.5 :enchant-cost (2 3) :enchant-effects 1
            :runes 2 :rune-mana (16 28) :rune-effects 2 :area-chance 0.3 :authored-chance 0.35)
     :skip-scale 0.75 :elite-chance 0.12
     :sight 1.15 :hearing 1.3 :alert 1.3 :pause 0.85 :cooldown 0.9)
    (:rooms 22 :exit "arena" :altar-chance 0.4
     :pool (("imp" 2) ("acolyte" 1) ("knight" 2) ("harpy" 1) ("necromancer" 2) ("ogre" 2) ("gale-wraith" 2)
            ("riftwalker" 2))
     :loot (:weapons 2 :enchant-chance 0.8 :enchant-cost (3 6) :enchant-effects 2
            :runes 2 :rune-mana (24 40) :rune-effects 3 :area-chance 0.5 :authored-chance 0.5)
     :skip-scale 0.5 :elite-chance 0.2
     :sight 1.3 :hearing 1.6 :alert 1.6 :pause 0.7 :cooldown 0.8))
  "A run's levels, first to last. :ROOMS is how many rooms the generator aims for, and :EXIT
the block it puts on the doorway furthest from the start (or a list of them, tried in order):
the descent, whose exit leaves the level, or the last level's arena, whose boss ends the run
(boss.lisp). NIL: no such block. :ALTAR-CHANCE is the chance of a spellforge altar room
(forge.lisp), besides the town's.

What the player finds there, :LOOT (loot.lisp): :WEAPONS swords and spears (the first a
:FIRST-WEAPON if it names one), each enchanted with :ENCHANT-CHANCE, its blows costing :ENCHANT-COST
mana, with up to :ENCHANT-EFFECTS effects; and :RUNES ready spells costing :RUNE-MANA, with up to
:RUNE-EFFECTS effects, a projectile's bursting with :AREA-CHANCE, and with :AUTHORED-CHANCE the
level is the one of the run that has a spell the forge can't make (*LOOT-SPELLS*) instead.

How hard its monsters are. Decided as it is built (LEVEL-SETTINGS): :POOL, what a spawn_any
picks from (*SPAWN-POOL*; leave a kind out rather than give it weight 0), :SKIP-SCALE, which
scales a spawn's chance of no monster (*SPAWN-SKIP-SCALE*), and :ELITE-CHANCE, a spawn's chance
of an elite (*ELITE-CHANCE*, elite.lisp). Asked in play (DEPTH-SCALE): :SIGHT and :HEARING scale
how far a creature notices the player, :ALERT how long it hunts after, :PAUSE its pause after an
attack and :COOLDOWN its abilities' cooldowns. A key left out keeps the variable, or 1.")

(defparameter *settlement-level*
  '(:core "town" :rooms 6 :exit NIL :min-wing 3 :altar-chance NIL :loot (:weapons 0 :runes 1)
    :settings ((*generator-blocks* . ("crypt" "cell" "cell-mirror" "chamber" "vestry" "vestry-mirror" "shrine" "corridor"
                                      "corridor-long" "corner" "tee" "cross" "arch" "narrow" "narrowing"
                                      "stair" "tower" "tower-mirror"))
               (*max-rivers* . 0) (*max-high-networks* . 0) (*max-flooded-networks* . 0) (*max-canals* . 0)
               (*start-clearance* . 6.0)))
  "The settlement's level, which RUN-LEVELS puts into the run once (settlement.lisp): grown
from the town block (:CORE) instead of a start block, with a small wing of crypts and cells
off its gates, at least :MIN-WING rooms besides the town. Its way down is in the town, so it
has no :EXIT, and no altar room, the town having its altar. :SETTINGS are generator settings for
this level only. How hard its monsters are (:POOL and the rest) it takes from the level it comes
before (RUN-LEVELS).")

(defvar *settlement* NIL
  "The SETTLEMENT of the level in play (settlement.lisp), or NIL on any other level. CLEAR-LEVEL forgets it.")

(defparameter *settlement-override* NIL
  "When non-NIL, a plist that fixes the settlement's draws for testing: :DEPTH (in the run),
:FACTION and :CONDITION (settlement.lisp), as '(:depth 1 :faction :deepwardens :condition
:besieged). Reloading this file clears it.")

(defvar *last-wing-rooms* 0
  "How many rooms the last generated level has besides its core, the settlement's town (GENERATE-LEVEL).")

(defparameter *settlement-depths* '(2 3)
  "The depths the settlement may take in a run, one picked by the run's seed. Every level
from there on is one deeper.")

(defvar *run-depth* 1 "Which of *RUN-LEVELS* the player is on, from 1.")
(defvar *run-seed* NIL "The run's seed, or NIL until a level needs one.")
(defparameter *level-seed* NIL "Fixes the run's seed, and so its first level's, or NIL for a new one every run.")
(defvar *last-level-seed* NIL "The seed of the last generated level, to build it again.")

(defparameter *carried-slots*
  '(health mana inventory quickslot stamina winded run-time damage-taken level-records
    gold reputation max-health max-mana max-stamina blessed
    known-effects hotbar-cells wanted-slot enchantments)
  "The player's slots that go on to the next level; the rest start fresh (RESET-PLAYER).
SETUP-SCENE takes what the hotbar slot asked for in hand (SETTLE-HELD).")

(defvar *carried-state* NIL
  "CARRIED-STATE of the player leaving a level, while the next one is built, else NIL.")

(defparameter *max-level-attempts* 8
  "How many seeds a level may try for one whose exit fits and can be reached (BUILD-LEVEL).")

(defun settlement-depth (run-seed)
  "The depth of run RUN-SEED's settlement, from its own random state so the levels' seeds
stay as they were. *SETTLEMENT-OVERRIDE*'s :DEPTH fixes it (settlement.lisp)."
  (or (getf *settlement-override* :depth)
      (let ((random (sb-ext:seed-random-state (logxor run-seed #x5E771E))))
        (nth (random (length *settlement-depths*) random) *settlement-depths*))))

(defun run-levels ()
  "The run's levels, first to last: *RUN-LEVELS* with *SETTLEMENT-LEVEL* at its depth, as hard as
the level after it (or the last), whose keys it doesn't give itself."
  (let ((at (min (1- (settlement-depth (current-run-seed))) (length *run-levels*))))
    (append (subseq *run-levels* 0 at)
            (list (append *settlement-level* (nth (min at (1- (length *run-levels*))) *run-levels*)))
            (nthcdr at *run-levels*))))

(defun run-length () (length (run-levels)))

(defun run-level-property (depth key &optional default)
  (getf (nth (1- depth) (run-levels)) key default))

(defun settlement-level-p (&optional (depth *run-depth*))
  "True if level DEPTH of the run is the settlement's."
  (and (run-level-property depth :core) T))

(defun depth-scale (key)
  "How much the level being played scales a creature's KEY (see *RUN-LEVELS*): 1 but on a
generated level."
  (if (eq *level* :generated)
      (float (run-level-property *run-depth* key 1.0) 0f0)
      1f0))

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
