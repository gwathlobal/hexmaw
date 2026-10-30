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

(defmethod swing-frame-times ((weapon (eql :spear))) *thrust-frame-times*)
(defmethod swing-hit-frame ((weapon (eql :spear))) *thrust-hit-frame*)
(defmethod swing-reach ((weapon (eql :spear))) *spear-reach*)
(defmethod swing-arc ((weapon (eql :spear))) *spear-arc*)
(defmethod swing-damage ((weapon (eql :spear))) *spear-damage*)
(defmethod swing-knockback ((weapon (eql :spear))) *spear-knockback*)
(defmethod swing-pain-bonus ((weapon (eql :spear))) *spear-pain-bonus*)

(define-shader-entity spear (sword)
  ((animation :initform (find-fx-animation 'spear))))

(defmethod held-weapon ((spear spear)) :spear)
(defmethod idle-frames ((spear spear)) *spear-idle-frames*)
(defmethod swing-first ((spear spear)) *spear-swing-first*)
(defmethod weapon-aim ((spear spear)) *spear-aim*)

(defun add-spear (container)
  (enter (make-instance 'spear) container))
