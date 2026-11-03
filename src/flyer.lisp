(in-package #:hexmaw)

;;; Flyers: creatures that keep to the air. A flyer plans its moves on the nav grid like
;;; any creature, from the floor under it (GROUND-POINT), but hovers HOVER-HEIGHT above
;;; that floor, lower where the ceiling around it is (NAV-ROOM-AROUND), bobbing. Low
;;; solids pass under it.
;;;
;;; It hunts from out of reach (RANGED-P): it keeps KEEP-AWAY from the player and,
;;; within ATTACK-RANGE with a clear line, dives. The dive is the telegraph and the
;;; counterplay: it hangs, rising, for DIVE-WINDUP, then flies a straight line at the
;;; player's head as it was when the dive left, at DIVE-SPEED and DIVE-OVERSHOOT beyond,
;;; so a sidestep makes it miss. Its talons strike once if the player's body comes within
;;; ATTACK-REACH. A hit during the dive itself downs it: it drops to the floor for
;;; *DOWNED-TIME*, in reach of the sword. Dead, it falls.

(defparameter *hover-bob* 0.08 "Metres a hovering flyer bobs up and down.")
(defparameter *hover-bob-rate* 1.6 "Bobs per second.")
(defparameter *hover-headroom* 0.1 "Metres a flyer keeps between its top and the ceiling.")
(defparameter *hover-look-ahead* 1.25
  "Metres around it that a flyer keeps under the lowest ceiling of, so it ducks under a
lintel before it reaches it.")
(defparameter *flyer-sink-speed* 3.0 "Metres per second a flyer sinks to a lower hover.")
(defparameter *flyer-gravity* 12.0 "Acceleration, in m/s², of a dead or downed flyer's fall.")
(defparameter *downed-time* 1.5 "Seconds a flyer hit during its dive lies on the floor.")
(defparameter *crash-time* 0.15 "Seconds a downed flyer shows its crash on landing, before it lies sprawled.")
(defparameter *stir-time* 0.75 "Seconds before it gets up that a downed flyer lifts its head.")
(defparameter *push-time* 0.4 "Seconds before it gets up that a downed flyer pushes itself up on its wings.")
(defparameter *launch-time* 0.35 "Seconds a flyer shows its launch as it leaves the floor.")
(defparameter *dive-floor-margin* 0.15 "Least height above the floor a dive takes a flyer's feet.")

(define-shader-entity flyer (creature)
  ((hover-height :initarg :hover-height :initform 2.0 :accessor hover-height
                 :documentation "Metres above the floor its feet keep, where the ceiling allows.")
   (climb-speed :initarg :climb-speed :initform 1.5 :accessor climb-speed
                :documentation "Metres per second it climbs back to its hover.")
   (dive-speed :initarg :dive-speed :initform 9.0 :accessor dive-speed :documentation "Metres per second.")
   (dive-windup :initarg :dive-windup :initform 0.5 :accessor dive-windup
                :documentation "Seconds it hangs before a dive: the warning.")
   (dive-rise :initarg :dive-rise :initform 0.4 :accessor dive-rise
              :documentation "Metres it rises during the wind-up.")
   (dive-overshoot :initarg :dive-overshoot :initform 1.5 :accessor dive-overshoot
                   :documentation "Metres a dive carries on past where it aimed.")
   (strike-height :initarg :strike-height :initform 1.1 :accessor strike-height
                  :documentation "Height above the player's feet that a dive aims its feet at.")
   (dive-direction :initform (vec 0 0 0) :reader dive-direction :documentation "Unit vector of the dive.")
   (dive-left :initform NIL :accessor dive-left
              :documentation "Metres of dive still to fly, or NIL when not diving.")
   (downed :initform 0.0 :accessor downed :documentation "Seconds left on the floor after a hit in its dive.")
   (landed :initform NIL :accessor landed :documentation "True once a downed flyer has hit the floor.")
   (launching :initform 0.0 :accessor launching :documentation "Seconds left of its launch off the floor.")
   (landed-dead :initform NIL :accessor landed-dead
                :documentation "Seconds into its death that it hit the floor, or NIL while it falls (or lives).")
   (fall-speed :initform 0.0 :accessor fall-speed :documentation "Metres per second it falls, dead or downed.")
   (bob-phase :initform (random (float (* 2 pi) 0f0)) :accessor bob-phase
              :documentation "Where it is in its bob, 0 to 2 pi; the wingbeat follows it.")
   (flap-animation :initarg :flap-animation :initform NIL :accessor flap-animation
                   :documentation "Frame animation of the wingbeat, four frames per view like
WALK-ANIMATION (top, downstroke, bottom, upstroke), one beat per bob; NIL to hover in the
standing pose.")
   (dive-animation :initarg :dive-animation :initform NIL :accessor dive-animation
                   :documentation "Frame animation of the dive, two frames per view: the wind-up,
then the dive itself; NIL to dive in the standing pose.")
   (downed-animation :initarg :downed-animation :initform NIL :accessor downed-animation
                     :documentation "Frame animation of being knocked down, seen from the front
whatever the view, like a death: tumbling, crash, sprawled, stirring, pushing up, launching.
NIL to fall and lie in the standing pose.")))

(defmethod stage :after ((flyer flyer) (area staging-area))
  (dolist (name (list (flap-animation flyer) (dive-animation flyer) (downed-animation flyer)))
    (when name
      (stage (animation-texture (find-fx-animation name)) area))))


(defun downed-frame (flyer)
  "The frame of the downed animation FLYER shows now."
  (let ((left (downed flyer)))
    (cond ((< 0 (launching flyer)) 5)
          ((not (landed flyer)) 0)
          ((< (- *downed-time* left) *crash-time*) 1)
          ((< left *push-time*) 4)
          ((< left *stir-time*) 3)
          (T 2))))

(defun dead-frame (flyer)
  "The frame of the downed animation a dead FLYER shows: tumbling as it falls, the crash
as it lands, then sprawled, its head down, for the corpse."
  (let ((at (landed-dead flyer)))
    (cond ((null at) 0)
          ((< (- (dead flyer) at) *crash-time*) 1)
          (T 2))))

;; A hit in its dive always breaks it off, and KEEP-HEIGHT downs it.
(defmethod always-pained-p ((flyer flyer))
  (and (dive-left flyer) T))

;; Its flinch is a mid-air one; on the floor it squashes its knockdown pose instead.
(defmethod flinch-p ((flyer flyer))
  (and (<= (downed flyer) 0) (<= (launching flyer) 0)))

(defmethod show-own-pose ((flyer flyer) squash)
  (cond ((dead flyer)
         ;; It dies the way it is knocked down, and stays down.
         (when (downed-animation flyer)
           (show-front-frame flyer (downed-animation flyer) (dead-frame flyer) squash)
           T))
        ((or (< 0 (downed flyer)) (< 0 (launching flyer)))
         (when (downed-animation flyer)
           (show-front-frame flyer (downed-animation flyer) (downed-frame flyer) squash)
           T))
        ((eq (brain flyer) :attacking)
         (when (dive-animation flyer)
           (show-view-frame flyer (dive-animation flyer) (if (dive-left flyer) 1 0) squash)
           T))
        ((flap-animation flyer)
         ;; The bottom of the stroke, frame 2, where the bob is highest (a quarter turn in).
         (show-view-frame flyer (flap-animation flyer)
                          (mod (1+ (floor (+ (bob-phase flyer) #.(float (/ pi 4) 0f0)) #.(float (/ pi 2) 0f0))) 4)
                          squash)
         T)))

(defmethod ranged-p ((flyer flyer)) T)

(defmethod move-lift ((flyer flyer)) 0.05)
;; It hovers over lava and water: its paths treat lava as any floor, and pass over water.
(defmethod nav-hazards ((flyer flyer)) :ignore)
(defmethod floats-p ((flyer flyer)) NIL)

(defun lift-flyer (flyer dy)
  "Move FLYER up by DY metres (down if negative) if its body fits there. Returns T if it moved."
  (let* ((loc (location flyer))
         (y (+ (vy loc) dy)))
    (when (fits-at-p (vx loc) y (vz loc) (body-radius flyer) (sprite-height flyer))
      (setf (vy loc) (float y 0f0))
      T)))

(defun hover-y (flyer)
  "The height FLYER's feet hover at where it is, bob included, or NIL over no floor."
  (let ((loc (location flyer)))
    (multiple-value-bind (floor ceiling)
        (and *nav-grid* (nav-room-around (vx loc) (vy loc) (vz loc) *hover-look-ahead* (step-height flyer)))
      (when floor
        (max floor (min (+ floor (hover-height flyer) (* *hover-bob* (sin (bob-phase flyer))))
                        (- ceiling (sprite-height flyer) *hover-headroom*)))))))

(defun fall (flyer dt)
  "Drop FLYER under gravity onto the floor under it. Returns T once it lies there."
  (let* ((loc (location flyer))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
    (cond ((and floor (< floor (vy loc)))
           (setf (vy loc) (max floor (- (vy loc) (* (incf (fall-speed flyer) (* *flyer-gravity* dt)) dt))))
           NIL)
          (T
           (setf (fall-speed flyer) 0.0)
           T))))

(defun lie-downed (flyer dt)
  "Fall, then lie on the floor for *DOWNED-TIME*, doing nothing. Getting up, it stands
while it climbs back to its hover, so it never dives from the floor."
  ;; Hold it still: a hit while it lies there must not set it hunting.
  (stop-walking flyer (max (idle-timer flyer) 0.1))
  (when (and (setf (landed flyer) (fall flyer dt)) (<= (decf (downed flyer) dt) 0))
    (setf (downed flyer) 0.0
          (launching flyer) *launch-time*)
    (stop-walking flyer (/ (hover-height flyer) (climb-speed flyer)))))

(defmethod break-flight ((flyer flyer))
  (setf (dive-left flyer) NIL
        (downed flyer) 0.0
        (landed flyer) NIL
        (launching flyer) 0.0
        (fall-speed flyer) 0.0))

;; Thrown to the floor, it lies there as if downed in its dive.
(defmethod land-thrown ((flyer flyer))
  (setf (downed flyer) *downed-time*
        (landed flyer) NIL)
  (stop-walking flyer *downed-time*))

(defmethod keep-height ((flyer flyer) dt)
  ;; A dive broken off by a hit (HURT stops it) downs the flyer.
  (when (and (dive-left flyer) (not (eq (brain flyer) :attacking)))
    (setf (dive-left flyer) NIL)
    (unless (dead flyer)
      (setf (downed flyer) *downed-time*
            (landed flyer) NIL)))
  (setf (launching flyer) (max 0.0 (- (launching flyer) dt)))
  (unless (dead flyer)
    (setf (landed-dead flyer) NIL))
  (cond ((dead flyer)
         (setf (downed flyer) 0.0
               (launching flyer) 0.0)
         (when (and (fall flyer dt) (null (landed-dead flyer)))
           (setf (landed-dead flyer) (dead flyer))))
        ((< 0 (downed flyer))
         (lie-downed flyer dt))
        ;; The dive moves it.
        ((eq (brain flyer) :attacking))
        (T
         (setf (fall-speed flyer) 0.0)
         (setf (bob-phase flyer) (mod (+ (bob-phase flyer) (* dt 2 pi *hover-bob-rate*)) (* 2 pi)))
         (let ((y (hover-y flyer)))
           (when y
             (lift-flyer flyer (max (- (* *flyer-sink-speed* dt))
                                    (min (* (climb-speed flyer) dt) (- y (vy (location flyer)))))))))))

(defun aim-dive (flyer)
  "Point FLYER's dive at the player's head as it is now."
  (let* ((loc (location flyer))
         (feet (feet *player*))
         (dir (dive-direction flyer)))
    (setf (vx dir) (- (vx feet) (vx loc))
          (vy dir) (- (+ (vy feet) (strike-height flyer)) (vy loc))
          (vz dir) (- (vz feet) (vz loc)))
    (let ((length (vlength dir)))
      (cond ((< length 1f-3)
             (setf (vx dir) 0.0 (vy dir) -1.0 (vz dir) 0.0
                   (dive-left flyer) 0.0))
            (T
             (nv/ dir length)
             (setf (dive-left flyer) (+ length (dive-overshoot flyer))))))
    (face-player flyer)))

(defun end-dive (flyer)
  (setf (dive-left flyer) NIL)
  (stop-walking flyer (attack-pause flyer)))

(defun fly-dive (flyer dt)
  "Fly DT seconds of the dive, striking the player if they're in reach. It ends at its
length, against a wall or a body, or on the strike."
  (let* ((loc (location flyer))
         (dir (dive-direction flyer))
         (step (min (dive-left flyer) (* (dive-speed flyer) dt)))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
    (decf (dive-left flyer) step)
    (multiple-value-bind (x-blocked z-blocked)
        (move-creature flyer (* step (vx dir)) (* step (vz dir)) (move-lift flyer))
      ;; Down the line, but skimming the floor rather than going into it.
      (lift-flyer flyer (if floor
                            (max (* step (vy dir)) (- (+ floor *dive-floor-margin*) (vy loc)))
                            (* step (vy dir))))
      (cond ((player-within-p flyer (attack-reach flyer))
             (hurt-player *player* (roll (attack-damage flyer)) loc :by flyer)
             (end-dive flyer))
            ((or x-blocked z-blocked (<= (dive-left flyer) 0))
             (end-dive flyer))))))

(defmethod attack-step ((flyer flyer) dt)
  (cond ((< (incf (attack-time flyer) dt) (dive-windup flyer))
         ;; The warning: it hangs, rising, turned to follow the player.
         (face-player flyer dt)
         (lift-flyer flyer (* dt (/ (dive-rise flyer) (dive-windup flyer)))))
        (T
         (unless (dive-left flyer)
           (aim-dive flyer))
         (fly-dive flyer dt))))

;;; The harpy: a winged hag that circles under the ceiling, out of sword reach in a hall,
;;; and dives at the player's head with its talons.

(defparameter *harpy-height* 1.8 "Harpy height in metres, raised wingtips to talons.")

;; Sliced at 116 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw harpy-turnaround) image
    #p"sprites/harpy/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; The wind-up (rearing back, wings spread high, talons raised) and the dive itself (head
;; low, wings swept back, talons reaching ahead), two frames per view. Its cells are
;; 110 px tall, at the turnaround's scale.
(define-fx-animation harpy-dive "sprites/harpy/dive" :size (* *harpy-height* 110/116))
;; The wingbeat: top (the turnaround's pose), downstroke, bottom, upstroke, four frames per
;; view, one beat per bob, so :FPS is unused. Its cells are 116 px tall like the
;; turnaround's, and 174 wide for the spread wings.
(define-fx-animation harpy-flap "sprites/harpy/flap" :loop T :size *harpy-height*)
;; Knocked out of its dive: tumbling, crash, sprawled, stirring (head up), pushing up on its
;; wings, launching; front view only, timed by DOWNED-FRAME, so :FPS is unused. Its cells
;; are 100 px tall, at the turnaround's scale.
(define-fx-animation harpy-downed "sprites/harpy/downed" :size (* *harpy-height* 100/116))
;; The flinch in mid-air: jolt (snapped back, screeching, talons clenched), then stagger
;; (sagging, a wing drooping), two frames per view over *STAGGER-TIME*. Its cells are
;; 108 px tall, at the turnaround's scale.
(define-fx-animation harpy-hurt "sprites/harpy/hurt" :size (* *harpy-height* 108/116))

(define-shader-entity harpy (flyer)
  ((texture :initform (// 'hexmaw 'harpy-turnaround))
   (atlas :initform (read-atlas "sprites/harpy/turnaround.lisp"))
   (sprite-height :initform *harpy-height*)
   (dive-animation :initform 'harpy-dive)
   (flap-animation :initform 'harpy-flap)
   (downed-animation :initform 'harpy-downed)
   (hurt-animation :initform 'harpy-hurt)
   ;; It paths onto the platform and up the stairs; flying, it clears both.
   (step-height :initform 1.3)
   (attack-damage :initform '(5 9))
   (attack-reach :initform 0.3)
   (attack-range :initform 6.0)
   (keep-away :initform 2.5)
   (attack-pause :initform 0.7)
   (walk-speed :initform 1.6)
   (chase-speed :initform 3.0)
   (wander-radius :initform 5.0)
   (gibs :initform '((:flesh 0 0 1 2 4 5 6 7 7)))
   (gib-scale :initform 1.1)
   (pain-chance :initform 25)
   (max-health :initform 20)))
