(in-package #:hexmaw)

;;; Loot: the weapons and runes a generated level hands out, for the player to find. A run starts
;;; with only the sword and shield, the fire bolt and heal (*STARTING-HOTBAR*, player.lisp); the
;;; rest is found. A found weapon is a sword or a spear with the stats every sword or spear has:
;;; it differs only in its enchantment (its stack's, STACK-ENCHANTMENT), plain on the first level,
;;; more often enchanted and more strongly the deeper it lies. A found rune is a ready spell: a
;;; generated one, made as the spellforge would make it (a FORGE-DRAFT, forge.lisp), so it costs
;;; what the forge would ask, or, now and then from the second level on, one the forge can't make
;;; (*LOOT-SPELLS*: the tornado), never twice in a run.
;;;
;;; What a level holds is its :LOOT (*RUN-LEVELS*, run.lisp; LOOT-PROPERTY). Everything is drawn
;;; from random states of the level's and the run's seeds, never from what the player has, so a
;;; load builds the same items: a save names the taken pickups by place, and keeps what the bag
;;; holds.

(defparameter *loot-spells* '(tempest)
  "Spells the forge can't make that a level may hand out as a rune instead of a generated one,
each once a run at most (AUTHORED-LOOT).")

(defparameter *loot-weapons* '(:sword :spear) "The weapons a level may hand out, as items.")

(defvar *loot-override* NIL "A :LOOT that LOOT-PROPERTY answers from instead, for the debug level's.")

(defun loot-property (key &optional (depth *run-depth*) default)
  "KEY of level DEPTH's :LOOT. The settlement's level gives its own :LOOT before the one of the
level it takes the rest from (RUN-LEVELS), so a key it leaves out comes from there."
  (loop for (k v) on (if *loot-override* (list :loot *loot-override*) (nth (1- depth) (run-levels))) by #'cddr
        when (eq k :loot)
          do (let ((found (getf v key '%none)))
               (unless (eq found '%none) (return found)))
        finally (return default)))

(defun loot-count (&optional (depth *run-depth*))
  "How many items level DEPTH hands out."
  (if (eq *level* :generated)
      (+ (loot-property :weapons depth 0) (loot-property :runes depth 0))
      0))

(defun random-range (range random)
  "A whole number from RANGE, (LO HI), drawn from RANDOM."
  (destructuring-bind (lo hi) range
    (+ lo (random (1+ (- hi lo)) random))))

(defun weighted-choice (choices random)
  "One of CHOICES, (THING WEIGHT) each, by weight: one float draw, whatever the weights."
  (let ((pick (* (random 1.0 random) (reduce #'+ choices :key #'second))))
    (loop for (thing weight) in choices
          do (decf pick weight)
          when (< pick 0) return thing
          finally (return (first (car (last choices)))))))

;;; Drafts drawn at random, then sized to a cost.

(defparameter *loot-strike-kinds* '((:damage 6) (:drain 2) (:slow 1) (:knockback 1))
  "What a delivered spell's or a weapon's first effect is, by weight; a second or third is any
other of them, alike.")
(defparameter *loot-self-kinds* '((:heal 7) (:ward 3)) "What a spell cast on yourself's first effect is.")
(defparameter *loot-deliveries* '((:projectile 13) (:touch 4) (:self 3)))
(defparameter *loot-durations*
  '((:damage 0.25 (2 5)) (:heal 0.3 (3 8)) (:slow 1.0 (2 8)) (:ward 1.0 (6 20)))
  "(KIND CHANCE RANGE): the chance an effect of KIND lasts, and for how many seconds.")

(defun loot-effect (kind random)
  "A fresh EFFECT-DRAFT of KIND, its element and time drawn; its magnitude is sized later."
  (let* ((timing (assoc kind *loot-durations*))
         (duration (if (and timing (< (random 1.0 random) (second timing)))
                       (random-range (third timing) random)
                       (if (eq :status (kind-property kind :timing)) 1 0))))
    (make-instance 'effect-draft :kind kind :magnitude 1 :duration duration
                                 :element (when (eq kind :damage)
                                            (nth (random (length *forge-elements*) random) *forge-elements*)))))

(defun loot-kinds (first-choices count random)
  "COUNT effect kinds: the first from FIRST-CHOICES by weight, the rest any other of them."
  (let ((kinds (list (weighted-choice first-choices random))))
    (loop repeat (1- count)
          for left = (remove-if (lambda (k) (member k kinds)) (mapcar #'first first-choices))
          while left
          do (setf kinds (append kinds (list (nth (random (length left) random) left)))))
    kinds))

(defun size-draft (draft cost-of target random)
  "Set DRAFT's magnitudes, each its own share of its kind's most, as high as they go while
COST-OF the draft's spell stays at most TARGET. Bisected, so the effects keep their shares."
  (let ((shares (loop for e in (draft-effects draft)
                      collect (* (kind-property (draft-kind e) :magnitude) (+ 0.5 (random 0.5 random))))))
    (flet ((apply-k (k)
             (loop for e in (draft-effects draft)
                   for share in shares
                   do (setf (draft-magnitude e)
                            (max 1 (min (kind-property (draft-kind e) :magnitude) (round (* k share))))))
             (funcall cost-of (draft-spell draft))))
      (let ((lo 0.0) (hi 1.0))
        (if (<= (apply-k hi) target)
            (setf lo hi)
            (loop repeat 20
                  do (let ((mid (/ (+ lo hi) 2)))
                       (if (<= (apply-k mid) target) (setf lo mid) (setf hi mid)))))
        (apply-k lo)
        draft))))

(defun loot-rune-draft (random)
  "A draft for a generated rune of this level: its delivery, effects and dials drawn, sized to a
cost in its :RUNE-MANA."
  (let* ((delivery (weighted-choice *loot-deliveries* random))
         (count (random-range (list 1 (loot-property :rune-effects *run-depth* 1)) random))
         (kinds (loot-kinds (if (eq delivery :self) *loot-self-kinds* *loot-strike-kinds*) count random))
         (draft (make-instance 'forge-draft :sink :new :delivery delivery
                                            :effects (mapcar (lambda (k) (loot-effect k random)) kinds))))
    ;; A burst, now and then: every effect that can spread does.
    (when (and (eq delivery :projectile) (< (random 1.0 random) (loot-property :area-chance *run-depth* 0)))
      (let ((area (* 0.5 (random-range '(2 5) random))))
        (dolist (e (draft-effects draft))
          (setf (draft-area e) (min area (kind-property (draft-kind e) :area))))))
    (size-draft draft #'spell-cost (random-range (loot-property :rune-mana *run-depth* '(10 18)) random) random)))

(defun loot-enchantment (stack random)
  "A generated enchantment for the weapon STACK, sized to a cost a blow in its level's :ENCHANT-COST."
  (let* ((count (random-range (list 1 (loot-property :enchant-effects *run-depth* 1)) random))
         (draft (make-instance 'forge-draft :sink stack
                                            :effects (mapcar (lambda (k) (loot-effect k random))
                                                             (loot-kinds *loot-strike-kinds* count random)))))
    (size-draft draft #'enchant-cost (random-range (loot-property :enchant-cost *run-depth* '(2 3)) random) random)
    (draft-spell draft)))

;;; Items.

(defun make-loot-weapon (random &optional kind)
  "A weapon of this level, a stack (KIND 1 ENCHANTMENT): KIND, or a sword or spear at random,
enchanted with the level's :ENCHANT-CHANCE."
  (let* ((kind (or kind (nth (random (length *loot-weapons*) random) *loot-weapons*)))
         (stack (list kind 1 NIL))
         (roll (random 1.0 random)))
    (when (< roll (loot-property :enchant-chance *run-depth* 0))
      (setf (stack-enchantment stack) (loot-enchantment stack random)))
    stack))

(defparameter *rune-mana-slack* 2
  "How far under its level's :RUNE-MANA a generated rune may cost: one whose effects can't reach it
(a knockback alone) is drawn again, as one the forge would refuse is.")

(defun make-loot-rune (random &optional spell)
  "A rune of this level, a stack (:RUNE 1 SPELL): SPELL, or a generated one the forge would make,
as cheap or dear as the level's :RUNE-MANA. Tried again while the forge would refuse it or it
comes out too cheap."
  (list :rune 1
        (or spell
            (loop with least = (- (first (loot-property :rune-mana *run-depth* '(10 18))) *rune-mana-slack*)
                  repeat 20
                  for draft = (loot-rune-draft random)
                  unless (or (draft-fault draft *max-mana*) (< (spell-cost (draft-spell draft)) least))
                    return (draft-spell draft)
                  finally (return (find-spell 'bolt))))))

(defun authored-loot (&optional (depth *run-depth*))
  "The spells of *LOOT-SPELLS* level DEPTH hands out in place of generated runes. Each is placed
once a run at most, on the first level whose :AUTHORED-CHANCE roll comes up, from the run's seed
alone, so every level of the run agrees."
  (let ((random (sb-ext:seed-random-state (logxor (or *run-seed* 0) #xA17))))
    (loop for spell in *loot-spells*
          when (loop for d from 1 to (run-length)
                     ;; Every level rolls, so a change of one level's chance moves no other's.
                     for hit = (< (random 1.0 random) (loot-property :authored-chance d 0))
                     when hit return (= d depth))
            collect (find-spell spell))))

(defun make-level-loot (random)
  "The stacks this level hands out, weapons first: its :WEAPONS (its :FIRST-WEAPON, if it names
one, first) and :RUNES, the authored spells it has taking runes' places."
  (let ((first (loot-property :first-weapon *run-depth*))
        (authored (authored-loot)))
    (append (loop for i from 0 below (loot-property :weapons *run-depth* 0)
                  collect (make-loot-weapon random (and (= i 0) first)))
            (loop for i from 0 below (loot-property :runes *run-depth* 0)
                  collect (make-loot-rune random (pop authored))))))

;;; On the floor.

(define-fx-animation loot-sword "sprites/pickups/loot-sword" :fps 4 :loop T :size (/ 48 64.0))
(define-fx-animation loot-spear "sprites/pickups/loot-spear" :fps 4 :loop T :size (/ 80 64.0))
(define-fx-animation loot-rune-fire "sprites/pickups/loot-rune-fire" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-frost "sprites/pickups/loot-rune-frost" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-shock "sprites/pickups/loot-rune-shock" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-drain "sprites/pickups/loot-rune-drain" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-heal "sprites/pickups/loot-rune-heal" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-arcane "sprites/pickups/loot-rune-arcane" :fps 5 :loop T :size (/ 22 64.0))
(define-fx-animation loot-rune-storm "sprites/pickups/loot-rune-storm" :fps 5 :loop T :size (/ 22 64.0))

(defparameter *loot-rune-animations*
  '(:fire loot-rune-fire :frost loot-rune-frost :shock loot-rune-shock :drain loot-rune-drain
    :heal loot-rune-heal :arcane loot-rune-arcane :storm loot-rune-storm)
  "A rune's pickup by its spell's look (SPELL-LOOK), drawn by tools/draw_loot.py.")

(define-shader-entity loot-pickup (rim-glow pickup)
  ((stack :initarg :stack :reader loot-stack :documentation "What it gives: a weapon's or rune's stack."))
  (:documentation "A found weapon or rune. Taken, a copy of its stack goes into the bag, so a
reset (RESTORE-PICKUPS) hands out the same one, unchanged by the forge. An enchanted weapon's
outline glows in its enchantment's colour, pulsing, as it does in hand and in the bag."))

(define-handler (loot-pickup tick :after) ()
  ;; As the weapon in hand's rim (sword.lisp), never dimmed: on the floor its mana isn't asked.
  (let ((spell (stack-enchantment (loot-stack loot-pickup)))
        (glow (glow loot-pickup)))
    (if spell
        (progn
          (spell-tint spell glow 1.0)
          (setf (vw glow) (- *weapon-rim-strength*
                             (* *weapon-rim-pulse* 0.5 (+ 1.0 (sin (* *weapon-rim-rate* *light-clock*)))))))
        (setf (vw glow) 0.0))))

(defun loot-animation (stack)
  (if (eq :rune (first stack))
      (getf *loot-rune-animations* (spell-look (stack-spell stack)) 'loot-rune-fire)
      (ecase (item-property (first stack) :weapon)
        (:sword 'loot-sword)
        (:spear 'loot-spear))))

(defun add-loot (container stack x y z &key (phase 0.0))
  "A pickup of STACK standing on the floor at X Y Z."
  (let* ((animation (find-fx-animation (loot-animation stack)))
         (pickup (make-instance 'loot-pickup :animation animation :stack stack :ground (float y 0f0)
                                             :kind (if (eq :rune (first stack)) :loot-rune :loot-weapon)
                                             :location (vec x (+ y *pickup-hover* (* 0.5 (animation-size animation))) z))))
    (setf (age pickup) phase)
    (vector-push-extend pickup *pickups*)
    (enter pickup container)
    pickup))

(defun loot-title (stack)
  "STACK as the player reads it found: \"a spear\", \"a sword: Frost Edge\", \"a rune: Shock Bolt\"."
  (let ((spell (or (stack-spell stack) (stack-enchantment stack))))
    (format NIL "a ~(~a~)~@[: ~a~]"
            (if (eq :rune (first stack)) "rune" (item-property (first stack) :name))
            (and spell (spell-title spell)))))

(defmethod collect-pickup ((pickup loot-pickup) player)
  ;; With the bag full it stays, as any item does.
  (let ((stack (copy-list (loot-stack pickup))))
    (multiple-value-bind (cell key) (give-stack player stack)
      (when cell
        (flash-resource player :glyph)
        (show-message (format NIL "Found ~a~:[, in the bag~;, on key ~:*~d~]."
                              (loot-title stack) (and key (1+ key))))
        T))))

(defun place-loot (container)
  "Put the level's loot (MAKE-LEVEL-LOOT) on spots no pickup took, a reward spot first, in blocks
with no pickup if there are any. After the glyphs, from random states of its own."
  (multiple-value-bind (spots used) (free-pickup-spots)
    (let ((random (sb-ext:seed-random-state (logxor *last-level-seed* #x1007))))
      (dolist (stack (make-level-loot random))
        (let ((spot (pick-spot spots '(:reward :floor) used random)))
          (if spot
              (let ((p (getf spot :position)))
                (add-loot container stack (vx p) (vy p) (vz p) :phase (random 10.0 random))
                (setf spots (remove spot spots))
                (push (getf spot :block) used))
              (v:warn :hexmaw "No spot for ~a." (loot-title stack))))))))

(defun place-test-loot (container)
  "The debug level's: along the hall's south wall, east of the dust, a plain spear, an enchanted
sword and two runes, as the deepest level makes them, from a fixed seed."
  (let ((random (sb-ext:seed-random-state 7))
        (*loot-override* (getf (car (last *run-levels*)) :loot)))
    (loop for stack in (list (list :spear 1 NIL)
                             (let ((sword (list :sword 1 NIL)))
                               (setf (stack-enchantment sword) (loot-enchantment sword random))
                               sword)
                             ;; A rune thrown and a rune of touch, so the two differ.
                             (let ((*loot-deliveries* '((:projectile 1)))) (make-loot-rune random))
                             (let ((*loot-deliveries* '((:touch 1)))) (make-loot-rune random)))
          for x from 6.5 by 1.0
          do (add-loot container stack x 0 8.5))))

;;; Hoards: an ogre that can't walk to the start (STRANDED-CREATURES, kit.lisp) guards a treasure,
;;; so the corner it can't leave is worth fighting into: a found item, always enchanted or a rune,
;;; and a pile of gold, on the floor just behind where it spawned. Its wander keeps it within 2 m
;;; of that, between the player and the hoard. Placed last of all the pickups, so the others keep
;;; their places in *PICKUPS* (a save's taken ones).

(defparameter *hoard-behind* 1.5 "Metres behind a guard's spawn point its hoard lies.")
(defparameter *hoard-spread* 0.7 "Metres to the side of the item the hoard's gold lies.")
(defparameter *hoard-gold* '(60 120) "Least and most coins in a hoard, at the first depth.")

(defun hoard-guard-p (creature)
  "True if CREATURE, stranded, guards a hoard: an ogre (or an elite one) built with the level."
  (and (typep creature 'ogre) (monster-p creature)))

(defun make-hoard-loot (random)
  "A hoard's item: a weapon of *LOOT-WEAPONS* with an enchantment of this level, or a generated
rune. Never plain, which on the first level every weapon is."
  (if (< (random 1.0 random) 0.5)
      (let ((stack (list (nth (random (length *loot-weapons*) random) *loot-weapons*) 1 NIL)))
        (setf (stack-enchantment stack) (loot-enchantment stack random))
        stack)
      (make-loot-rune random)))

(defun hoard-points (guard seen)
  "Where GUARD's hoard goes, the item's point and the gold's, or NIL: behind its spawn point,
nearer, or turned toward its side where a wall is in the way (spawns often stand with their back
to one), never in front of it, and on it at last. A point must be floor the player fits on, a step
from the guard's, among the cells SEEN (NAV-REACHED) they can get to."
  (let* ((home (home guard))
         (f (facing guard))
         (bx (- (sin f))) (bz (cos f)))
    (flet ((point (along across turn)
             (let* ((dx (- (* bx (cos turn)) (* bz (sin turn))))
                    (dz (+ (* bz (cos turn)) (* bx (sin turn))))
                    (ox (+ (* along dx) (* across dz)))
                    (oz (- (* along dz) (* across dx)))
                    (p (vec (+ (vx home) ox) (+ (vy home) 0.1) (+ (vz home) oz))))
               ;; Not in front: the guard stands between the player and its hoard.
               (when (<= -0.1 (+ (* ox bx) (* oz bz)))
                 (multiple-value-bind (i j k) (nav-nearest-fitting p *player-radius* *player-height* :search 0 :reach 1.0)
                   (when i
                     (let ((y (nav-floor i j k)))
                       (when (<= (abs (- y (vy home))) *step-height*)
                         (setf (vy p) y)
                         (when (spot-reached-p (list :position p :tier :floor) seen)
                           p)))))))))
      (let* ((candidates (loop for along in (list *hoard-behind* (* 0.6 *hoard-behind*) 0.0)
                               append (loop for turn in (if (< 0 along)
                                                            (list 0.0 (/ pi 4) (- (/ pi 4)) (/ pi 2) (- (/ pi 2)))
                                                            '(0.0))
                                            append (loop for across in (list 0.0 *hoard-spread* (- *hoard-spread*))
                                                         for p = (point along across turn)
                                                         when p collect p))))
             (item (first candidates))
             (gold (find-if (lambda (p) (<= *hoard-spread* (vdistance p item))) (rest candidates))))
        (when item
          (values item (or gold item)))))))

(defun place-hoards (container guards)
  "A hoard behind each of GUARDS (HOARD-GUARD-P, stranded), from a random state of its own."
  (when guards
    (let* ((random (sb-ext:seed-random-state (logxor *last-level-seed* #x4041D)))
           (*nav-hazards* :swim)
           (seen (multiple-value-bind (i j k) (nav-nearest-fitting *spawn-point* *player-radius* *player-height*)
                   (and i (nav-reached i j k *player-radius* *player-height* *step-height*)))))
      (dolist (guard guards)
        (multiple-value-bind (item gold) (and seen (hoard-points guard seen))
          (if item
              (let ((stack (make-hoard-loot random))
                    (coins (random-range *hoard-gold* random)))
                (add-loot container stack (vx item) (vy item) (vz item) :phase (random 10.0 random))
                (add-pickup container :gold (vx gold) (vy gold) (vz gold) :phase (random 10.0 random) :count coins)
                (v:info :hexmaw "~a at ~a guards ~a and ~d gold." (type-of guard) (home guard) (loot-title stack) coins))
              (v:warn :hexmaw "No floor the player can reach behind ~a at ~a for its hoard."
                      (type-of guard) (home guard))))))))
