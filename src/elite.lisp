(in-package #:hexmaw)

;;; Elites: a monster of a deeper level that is more than its kind. A spawn on a generated
;;; level is one with the level's *ELITE-CHANCE* (*RUN-LEVELS*' :ELITE-CHANCE), drawn from
;;; *ELITE-RANDOM* (ELITE-ROLL, from PLACE-BLOCK), so a seed always has the same ones. An elite
;;; has *ELITE-HEALTH-SCALE* times its kind's health, is drawn a little bigger, glows round its
;;; rim (RIM-GLOW, boss.lisp) in its trait's colour, never the boss's orange, and has one trait:
;;;
;;; - :HASTE, walks and attacks *ELITE-HASTE* times as fast;
;;; - :WARDED, its front turns spells back, as the knight's shield does (so not the knight);
;;; - :TOUGH, flinches half as often and takes half the knockback.
;;;
;;; Its trait comes back with the level when a save is loaded, since the seed draws it again.

(defparameter *elite-kinds*
  '(("imp" elite-imp) ("acolyte" elite-acolyte) ("knight" elite-knight) ("harpy" elite-harpy)
    ("necromancer" elite-necromancer) ("ogre" elite-ogre) ("gale-wraith" elite-wraith))
  "What can be an elite: the kind as a spawn names it, and the elite's class.")

(defparameter *elite-traits* '(:haste :warded :tough))

(defparameter *elite-trait-denied* '((:warded "knight"))
  "Each trait with the kinds that never get it.")

(defparameter *elite-override* NIL
  "For testing: :ALL makes every spawn that can be an elite one, on any level, its trait drawn;
a trait makes them all that trait. NIL for the level's chance.")

(defparameter *elite-health-scale* 1.75)
(defparameter *elite-size-scale* 1.15
  "How much bigger an elite is drawn, but never past *NAV-CLEARANCE-HEIGHT*, nor at all for a
kind already taller (the ogre), so it goes everywhere its kind goes. Its body isn't widened.")
(defparameter *elite-haste* 1.3 "How much faster :HASTE makes its walk and its attacks.")
(defparameter *elite-tough-pain* 0.5 "Its pain chance, :TOUGH, against its kind's.")
(defparameter *elite-tough-knockback* 0.5 "Its knockback, :TOUGH, against its kind's.")

(defparameter *elite-glow-colors*
  (list :haste (vec 0.3 0.9 1.0) :warded (vec 0.65 0.35 1.0) :tough (vec 0.9 0.9 0.8))
  "Each trait's rim and lamp colour: cyan, violet, bone-white, all far from the boss's orange.")
(defparameter *elite-glow-strength* 0.6 "The rim's strength, about which it pulses.")
(defparameter *elite-glow-pulse* 0.2 "How far either way it pulses.")
(defparameter *elite-glow-rate* 2.0 "Its pulse, in radians a second: slower than the boss's.")
(defparameter *elite-light-radius* 3.5)
(defparameter *elite-light-scale* 0.5 "Its lamp's brightness against the rim's.")

(defun elite-trait-allowed-p (trait kind)
  (not (member kind (rest (assoc trait *elite-trait-denied*)) :test #'string-equal)))

(defun elite-roll (kind)
  "Whether a spawn of the monster KIND is an elite: NIL, or a list of its class and trait.
Draws from *ELITE-RANDOM* the same whatever it decides, so one spawn's roll never moves another's."
  (let ((chance (random 1.0 *elite-random*))
        (pick (random 1.0 *elite-random*))
        (entry (and kind (assoc kind *elite-kinds* :test #'string-equal))))
    (when (and entry
               (or *elite-override*
                   (and (eq *level* :generated) (< chance *elite-chance*))))
      (let ((traits (if (and *elite-override* (not (eq *elite-override* :all)))
                        (list *elite-override*)
                        (remove-if-not (lambda (trait) (elite-trait-allowed-p trait kind)) *elite-traits*))))
        (when traits
          (list (second entry) (nth (min (1- (length traits)) (floor (* pick (length traits)))) traits)))))))

(define-shader-entity elite (rim-glow)
  ((trait :initarg :trait :initform :tough :reader elite-trait))
  (:documentation "A monster more than its kind, with one trait. List it first in the superclasses."))

(defmethod initialize-instance :after ((elite elite) &key)
  (let* ((h (sprite-height elite))
         (k (if (< *nav-clearance-height* h) 1.0 (min *elite-size-scale* (/ *nav-clearance-height* h)))))
    ;; The billboard and the creature have already sized it from its kind's height.
    (setf (sprite-height elite) (* k h)
          (slot-value elite 'size-scale) k)
    (nv* (scaling elite) k)
    (nv* (base-scaling elite) k)
    ;; Its body stays its kind's: a wider one would need wider cells of the nav grid.
    (setf (attack-reach elite) (* k (attack-reach elite))
          (cast-offset elite) (* k (cast-offset elite))))
  (setf (max-health elite) (round (* *elite-health-scale* (max-health elite)))
        (health elite) (max-health elite))
  (when (eq (elite-trait elite) :tough)
    (setf (slot-value elite 'pain-chance) (round (* *elite-tough-pain* (pain-chance elite)))
          (knockback-scale elite) (* *elite-tough-knockback* (knockback-scale elite)))))

(defun elite-speed (elite)
  (if (eq (elite-trait elite) :haste) *elite-haste* 1.0))

(defmethod walk-speed ((elite elite)) (* (elite-speed elite) (call-next-method)))

(defmethod chase-speed ((elite elite))
  (let ((speed (call-next-method)))
    (and speed (* (elite-speed elite) speed))))

(defmethod attack-step ((elite elite) dt)
  (call-next-method elite (* dt (elite-speed elite))))

(defmethod shield-views ((elite elite))
  (if (eq (elite-trait elite) :warded) (max 1 (or (call-next-method) 0)) (call-next-method)))

(defun update-elite-glow (elite)
  "The rim and its lamp: pulsing while it lives, going out as it dies, gone with its gibs."
  (let* ((d (dead elite))
         (k (cond ((gibbed elite) 0.0)
                  (d (max 0.0 (- 1.0 (/ d (max 0.1 (death-duration elite))))))
                  (T 1.0)))
         (strength (* k (+ *elite-glow-strength* (* *elite-glow-pulse* (sin (* *elite-glow-rate* *light-clock*)))))))
    (light-rim elite (getf *elite-glow-colors* (elite-trait elite)) strength *elite-light-radius*)
    (let ((lamp (glow-lamp elite)))
      (when lamp
        (nv* (color lamp) *elite-light-scale*)))))

(define-handler (elite tick :after) ()
  (update-elite-glow elite))

;;; One class per kind.

(define-shader-entity elite-imp (elite imp) ())
(define-shader-entity elite-acolyte (elite acolyte) ())
(define-shader-entity elite-knight (elite knight) ())
(define-shader-entity elite-harpy (elite harpy) ())
(define-shader-entity elite-necromancer (elite necromancer) ())
(define-shader-entity elite-ogre (elite ogre) ())
(define-shader-entity elite-wraith (elite gale-wraith) ())
