(in-package #:hexmaw)

;;; The spear, held in both hands, so no shield. Against the sword it reaches further
;;; and staggers more often, but its thrust is slower and its arc narrow, so it hits
;;; only what the player is looking at. It is swung like the sword (SWING-TIME,
;;; sword.lisp), its blow landing at full extension.
;;;
;;; Its sprite is the sword's, drawn from its own strip (data/sprites/spear): a 4-frame
;;; idle loop followed by an 8-frame thrust: rest, drawing back, drawn back, the thrust,
;;; full extension, pulling back, recovery, rest.

(define-fx-animation spear "sprites/spear/spear" :fps 5 :loop T)

(defparameter *spear-idle-frames* 4 "Strip frames the idle loop steps through, from the first.")
(defparameter *spear-swing-first* 4 "Strip index of the thrust's first frame.")
(defparameter *spear-aim* 187
  "Art pixels left from the strip's screen corner to the spearhead's point at full
extension (art/spear/extend-1.png's tip, placed by art/spear/spear-frames.txt), which goes on
the screen's middle: held in both hands, the spear points where the player looks.")

(defparameter *thrust-frame-times* '(0.05 0.08 0.06 0.05 0.12 0.10 0.12 0.10)
  "Seconds each frame of the thrust shows. The thrust is over after the last.")
(defparameter *thrust-hit-frame* 4 "Thrust frame the blow lands on, counted from 0: full extension.")
(defparameter *spear-reach* 3.5 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *spear-arc* 0.3 "Radians either side of the view the thrust reaches.")
(defparameter *spear-damage* '(8 14))
(defparameter *spear-knockback* 2.5 "Speed in m/s a hit slides the creature away.")
(defparameter *spear-pain-bonus* 35
  "Percent a hit adds to the creature's PAIN-CHANCE: staggering is what it is for.")

;;; A thrust that lands on a creature charging at the player through the air (CHARGING-P,
;;; creature.lisp: a leap or pounce, a harpy's dive) is a counter: the charge runs onto the
;;; point. It hits harder, always flinches (a boss only rolls with *COUNTER-PAIN-BONUS*), shows the
;;; jolt and does its kind's reaction (IMPALE: a leaper drops out of the air with no quake). A
;;; knight's shield takes it as any thrust. The right button (the shield's action, :BLOCK) sweeps
;;; with the haft: the bash's rules (a stagger only in a wind-up, poise), but every creature in a
;;; wide arc, to clear space, and no enchantment.

(defparameter *counter-damage* '(18 26) "Damage of a thrust that meets a charge.")
(defparameter *counter-sparks* 12 "Sparks the spearhead throws as it meets a charge.")
(defparameter *counter-knockback* 5.0 "Speed in m/s a counter throws the creature back.")
(defparameter *counter-pain-bonus* 100
  "Percent a counter adds to a boss's PAIN-CHANCE: anything else always flinches.")
(defparameter *spear-jolt-time* 0.25 "Seconds the spear shows the jolt of a counter.")

(defparameter *sweep-frame-times* '(0.1 0.08 0.12 0.12)
  "Seconds each frame of the haft sweep shows: wound up to the right, the sweep, the
follow-through, back. It is over after the last.")
(defparameter *sweep-hit-frame* 1 "Sweep frame the blow lands on, counted from 0: the sweep.")
(defparameter *sweep-reach* 1.8 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *sweep-arc* 1.4 "Radians either side of the view the sweep reaches: a flanker's side too.")
(defparameter *sweep-damage* '(2 4))
(defparameter *sweep-knockback* 6.0 "Speed in m/s a sweep slides each creature away.")
(defparameter *sweep-stamina* 15.0 "Stamina a sweep costs; with less, no sweep.")

;;; Strip frames after the thrust: the jolt of a counter, then the sweep.
(defparameter *spear-jolt-frame* 12 "Strip index of the jolt of a counter.")
(defparameter *spear-sweep-first* 13 "Strip index of the sweep's first frame.")

(defmethod swing-frame-times ((weapon (eql :spear))) *thrust-frame-times*)
(defmethod swing-hit-frame ((weapon (eql :spear))) *thrust-hit-frame*)
(defmethod swing-reach ((weapon (eql :spear))) *spear-reach*)
(defmethod swing-arc ((weapon (eql :spear))) *spear-arc*)
(defmethod swing-damage ((weapon (eql :spear))) *spear-damage*)
(defmethod swing-knockback ((weapon (eql :spear))) *spear-knockback*)
(defmethod swing-pain-bonus ((weapon (eql :spear))) *spear-pain-bonus*)

(defmethod bash-frame-times ((weapon (eql :spear))) *sweep-frame-times*)
(defmethod bash-hit-frame ((weapon (eql :spear))) *sweep-hit-frame*)
(defmethod bash-strike (player (weapon (eql :spear))) (sweep-hit player))

;; A thrust's blow is a counter on a creature charging at the player.
(defmethod swing-strike (player (weapon (eql :spear)) target)
  (if (and (charging-p target) (not (shielded-p target (feet player))))
      (spear-counter player target)
      (call-next-method)))

(defun spear-counter (player target)
  "TARGET charged onto PLAYER's thrust: skewered, flinching whatever the roll, and its charge
broken (IMPALE)."
  (let ((feet (feet player)))
    (setf (spear-jolt player) *spear-jolt-time*)
    (play-sound :spear-impale (location target))
    (strike-sparks target feet *counter-sparks*)
    (impale target)
    (hurt target (roll *counter-damage*) :from feet :by player
                                          :pain-bonus *counter-pain-bonus*
                                          :force-pain (not (typep target 'boss)))
    (push-creature target (v- (location target) feet) (float *counter-knockback* 0f0))
    (enchant-strike player :spear target)))

(defun player-sweep (player)
  (when (and (weapon-ready-p player) (not (attacking-p player)) (<= *sweep-stamina* (stamina player)))
    (decf (stamina player) *sweep-stamina*)
    (break-snare player)
    (play-sound :haft-sweep)
    (setf (bash-time player) 0.0
          (bash-pending player) T)))

(defun sweep-hit (player)
  "Sweep the haft through every creature in its arc: each shoved, staggered only in the wind-up of
an attack and not poised (BASH-HIT's rules). One a shield covers glances off it, and the player
reels back once. With no one in it, it strikes the wall."
  (let ((feet (feet player))
        (glanced NIL)
        (struck NIL))
    (loop for c across *creatures*
          when (and (not (dead c)) (blow-reaches-p player c *sweep-reach* *sweep-arc*))
            do (setf struck T)
               (if (shielded-p c feet)
                   (progn
                     (play-sound :bash-glance (location c))
                     (block-hit c)
                     (setf glanced c))
                   (let* ((poised (< 0.0 (bash-poise c)))
                          (bonus (if (and (not poised) (winding-up-p c)) *bash-pain-bonus* -100)))
                     (setf (bash-poise c) *bash-poise-time*)
                     (play-sound :bash-hit (location c))
                     (hurt c (roll *sweep-damage*) :from feet :pain-bonus bonus :by player)
                     (push-creature c (v- (location c) feet)
                                    (float (* *sweep-knockback* (if poised *poised-bash-knockback* 1.0)) 0f0)))))
    (when glanced
      (shove-player player (location glanced) *bash-recoil*)
      (break-guard player *bash-recoil-guard*))
    ;; With no one in its arc, the haft strikes the wall the crosshair meets (WALL-STRIKE, sword.lisp).
    (unless struck
      (wall-strike player :haft *sweep-reach*))))

(define-shader-entity spear (sword)
  ((animation :initform (find-fx-animation 'spear))))

(defmethod held-weapon ((spear spear)) :spear)
(defmethod idle-frames ((spear spear)) *spear-idle-frames*)
(defmethod swing-first ((spear spear)) *spear-swing-first*)
(defmethod weapon-aim ((spear spear)) *spear-aim*)

(defmethod weapon-frame ((spear spear) player)
  (let ((sweep (and (bash-time player) (frame-at (bash-time player) *sweep-frame-times*))))
    (cond (sweep (+ *spear-sweep-first* sweep))
          ((< 0.0 (spear-jolt player)) *spear-jolt-frame*)
          (T (call-next-method)))))

(defun add-spear (container)
  (add-weapon-sprite 'spear container))
