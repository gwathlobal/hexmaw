(in-package #:hexmaw)

;;; The ogre: big (2.7 m, a body 1 m out from its centre), slow, and the monster that
;;; pushes the player around. It fits the 3 m doorways and corridors but not narrow ones
;;; or tight stairs, so it is the creature that can't follow the player everywhere.
;;;
;;; From 4 to 12 m away it leaps (SPECIAL-ATTACK): PLAN-LEAP finds a cell its body fits
;;; under the player, and an arc to it that its body fits all the way, lowered under the
;;; ceiling (in a 4 m room its feet rise about 1.2 m; in a 3 m corridor there is no room
;;; to leap). It crouches for *LEAP-WINDUP*, the warning, then flies at where the player
;;; stood then. Landing, it QUAKEs: everything with its feet on the floor within
;;; *QUAKE-RADIUS*, the player and its own allies, is hurt and thrown back, less toward
;;; the rim; a player in the air is untouched. It then stands *LEAP-RECOVER*, the opening.
;;; Up close it slams its maul down: a hit throws the player back off their feet, and the
;;; impact shoves whatever stands beside it, hit or not.
;;;
;;; The flight runs in KEEP-HEIGHT, which runs every tick, so a hit (which stops a
;;; creature's thinking for its flinch) never leaves it hanging in the air.

(defparameter *ogre-height* 2.7 "Ogre height in metres.")

(defparameter *leap-min* 4.0 "Least distance, in metres across, the ogre leaps.")
(defparameter *leap-max* 12.0 "Furthest it leaps.")
(defparameter *leap-max-rise* 2.5 "Highest, in metres, it leaps up onto.")
(defparameter *leap-max-drop* 6.0 "Lowest it leaps down to.")
(defparameter *leap-apex* 2.0 "Metres its feet rise above the higher end of a leap, where the ceiling allows.")
(defparameter *leap-min-apex* 0.5 "Lowest rise over the higher end it still leaps with.")
(defparameter *leap-headroom* 0.1 "Metres it keeps between its head and the ceiling in a leap.")
(defparameter *leap-gravity* 15.0 "Acceleration, in m/s², along a leap's arc and of a fall.")
(defparameter *leap-max-speed* 16.0 "Fastest, in m/s across, it flies: a low ceiling limits how far it leaps.")
(defparameter *leap-sample* 0.25 "Metres between the points of an arc that are checked against solids.")
(defparameter *leap-windup* 0.6 "Seconds it crouches before it leaps.")
(defparameter *leap-recover* 1.2 "Seconds it stands after landing.")
(defparameter *leap-cooldown* 6.0 "Seconds from one leap to the next.")
(defparameter *leap-hit-stop* 0.12 "Hit-stop on landing.")
(defparameter *leap-debug* NIL "When true, log why each leap was refused.")

(defparameter *quake-radius* 3.5 "Metres from its centre that the landing's shockwave reaches.")
(defparameter *quake-reach-height* 0.4 "Metres above the floor feet can be and still be struck: a jump dodges it.")
(defparameter *quake-damage* '(10 18) "Damage at the centre of the shockwave, falling off to nothing at its rim.")
(defparameter *quake-shove* 9.0 "Speed in m/s the shockwave throws creatures at its centre, before their KNOCKBACK-SCALE.")
(defparameter *quake-player-shove* 9.0 "Speed in m/s it throws the player standing against it.")
(defparameter *quake-player-lift* 5.0 "Speed in m/s it throws the player standing against it up.")
(defparameter *quake-direct-hit* 1.5 "Damage factor when it lands on the player, or right against them.")
(defparameter *direct-hit-margin* 0.25 "Metres between the bodies that still count as landing on the player.")

(defparameter *slam-shove* 9.0 "Speed in m/s the slam throws the player it hits.")
(defparameter *slam-lift* 4.0 "Speed in m/s the slam throws the player up.")
(defparameter *slam-quake-radius* 1.5 "Metres from the maul's impact that the slam shoves.")
(defparameter *slam-quake-shove* 6.0 "Speed in m/s the impact shoves creatures, and the player it missed.")
(defparameter *slam-quake-lift* 2.0 "Speed in m/s the impact throws a missed player up.")
(defparameter *slam-impact* 1.5 "Metres in front of its centre that the maul lands.")

(defparameter *ogre-dust* 'ogre-dust
  "Effect animation of the dust kicked up where it lands and where the maul strikes, or NIL for none.")
(defparameter *ogre-dust-puffs* 8 "Puffs of dust round a landing.")

;; Sliced at 173 px tall, so its art pixels are the imp's size (64 per metre). The strips'
;; cells are measured against that standing height.
(define-asset (hexmaw ogre-turnaround) image
    #p"sprites/ogre/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; A heavy stride, four frames per view, 190 px cells for the rise on the passing frames.
;; The frame follows the distance walked (STRIDE), so :FPS is unused.
(define-fx-animation ogre-walk "sprites/ogre/walk" :loop T :size (* *ogre-height* 190/173))
;; Wind-up with the maul high overhead (274 px cells), swing, the maul in the floor (the
;; blow lands), recover. The frames run on ATTACK-FRAME-TIMES.
(define-fx-animation ogre-slam "sprites/ogre/slam" :size (* *ogre-height* 274/173))
;; Crouch, in the air with the maul raised, landed with it driven down: three frames per
;; view, shown by the leap's state, not a clock. The airborne frame stands on its cell's
;; ground line; the arc lifts the ogre itself.
(define-fx-animation ogre-leap "sprites/ogre/leap" :size (* *ogre-height* 207/173))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*.
(define-fx-animation ogre-hurt "sprites/ogre/hurt" :size (* *ogre-height* 180/173))
;; It falls face down beside its maul, the corpse. Front view only.
(define-fx-animation ogre-death "sprites/ogre/death" :fps 9 :size (* *ogre-height* 172/173))
;; A burst of dust and grit, standing on the floor: 66 px cells, about 1 m.
(define-fx-animation ogre-dust "sprites/ogre/dust" :fps 14 :size (/ 66 64.0))

(define-shader-entity ogre (creature)
  ((texture :initform (// 'hexmaw 'ogre-turnaround))
   (atlas :initform (read-atlas "sprites/ogre/turnaround.lisp"))
   (sprite-height :initform *ogre-height*)
   (walk-animation :initform 'ogre-walk)
   (attack-animation :initform 'ogre-slam)
   (leap-animation :initform 'ogre-leap :reader leap-animation)
   (hurt-animation :initform 'ogre-hurt)
   (death-animation :initform 'ogre-death)
   (stride :initform 0.4)
   (body-radius :initform 1.0)
   ;; Its stride: the nav grid's tall clearance ignores what it steps over
   ;; (*NAV-TALL-LIFT*), which takes in two of a stair's steps under its bulk.
   (step-height :initform *nav-tall-lift*)
   (turn-speed :initform 1.4)
   (knockback-scale :initform 0.15)
   (attack-damage :initform '(14 22))
   (attack-reach :initform 1.0)
   (attack-arc :initform 0.9)
   ;; Wind-up overhead, swing, the maul in the floor (the blow lands), recover.
   (attack-frame-times :initform '(0.7 0.15 0.2 0.5))
   (attack-pause :initform 1.0)
   ;; The maul knocks a raised shield aside; its shockwave comes up through the floor,
   ;; under it (QUAKE).
   (guard-break :initform 1.2)
   (walk-speed :initform 0.8)
   (chase-speed :initform 1.6)
   (wander-radius :initform 2.0)
   (gibs :initform '((:flesh 0 0 1 1 2 3 4 5 5 6 6 7 7)))
   (gib-scale :initform 1.8)
   (gib-overkill :initform 0.12)
   ;; Its bulk shrugs off most blows, nearly as the knight's plate does.
   (pain-chance :initform 17)
   (max-health :initform 120)
   ;; Which attack ATTACK-STEP runs: the slam, or a leap PLAN-LEAP laid out.
   (attack-kind :initform :slam :accessor attack-kind)
   (leap-from :initform (vec 0 0 0) :reader leap-from)
   (leap-to :initform (vec 0 0 0) :reader leap-to)
   (leap-apex :initform 0.0 :accessor leap-apex
              :documentation "Height its feet reach at the top of the arc.")
   (leap-duration :initform 0.0 :accessor leap-duration)
   (leap-time :initform 0.0 :accessor leap-time)
   (airborne :initform NIL :accessor airborne
             :documentation "True while it flies a leap's arc.")
   (falling :initform NIL :accessor falling
            :documentation "True while it drops, a leap cut short by a wall or a body.")
   (fall-speed :initform 0.0 :accessor fall-speed)
   (recover :initform 0.0 :accessor recover
            :documentation "Seconds it still stands after landing.")
   (leap-cooldown :initform 0.0 :accessor leap-cooldown)))

(defmethod stage :after ((ogre ogre) (area staging-area))
  (stage (animation-texture (find-fx-animation (leap-animation ogre))) area))

(defmethod attack-frame-times ((ogre ogre))
  ;; A leap's only timed part is the crouch; the flight doesn't run on the attack's clock.
  (if (eq (attack-kind ogre) :leap) (list *leap-windup* 1000.0) (call-next-method)))
(defmethod attack-animation ((ogre ogre))
  (if (eq (attack-kind ogre) :leap) (leap-animation ogre) (call-next-method)))

(defun leap-log (format &rest args)
  (when *leap-debug*
    (v:info :hexmaw "Ogre: ~?" format args)))

(defun leap-refused (format &rest args)
  (leap-log "leap refused, ~?" format args)
  NIL)

(defvar *leap-peak* 0.0 "Highest its feet got in the last leap, for *LEAP-DEBUG*.")

;;; The arc. Its feet rise from LEAP-FROM to LEAP-APEX and fall to LEAP-TO under
;;; *LEAP-GRAVITY*, moving across at a steady speed.

(defun rise-time (from-y apex)
  (sqrt (/ (* 2 (max 0.0 (- apex from-y))) *leap-gravity*)))

(defun arc-time (from-y to-y apex)
  (+ (rise-time from-y apex) (rise-time to-y apex)))

(defun arc-point (from to apex duration time out)
  "Set OUT to where the arc from FROM to TO over APEX, DURATION long, is TIME seconds in."
  (let* ((k (if (< 0 duration) (min 1.0 (/ time duration)) 1.0))
         (up (rise-time (vy from) apex))
         (d (- (min time duration) up)))
    (setf (vx out) (float (+ (vx from) (* k (- (vx to) (vx from)))) 0f0)
          (vy out) (float (- apex (* 0.5 *leap-gravity* d d)) 0f0)
          (vz out) (float (+ (vz from) (* k (- (vz to) (vz from)))) 0f0))
    out))

(defun lowest-ceiling-along (from to y)
  "The lowest ceiling over the line FROM TO above height Y, or NIL under open sky."
  (let* ((dx (- (vx to) (vx from)))
         (dz (- (vz to) (vz from)))
         (steps (max 1 (ceiling (sqrt (+ (* dx dx) (* dz dz))) 0.5)))
         (lowest NIL))
    (loop for i from 0 to steps
          for k = (/ i steps)
          for c = (ceiling-above (+ (vx from) (* k dx)) y (+ (vz from) (* k dz)))
          when (and c (or (null lowest) (< c lowest)))
            do (setf lowest c))
    lowest))

(defun arc-clear-p (ogre from to apex duration)
  "True if OGRE's body fits all along the arc. Bodies don't count: the landing throws them."
  (let* ((distance (sqrt (+ (expt (- (vx to) (vx from)) 2) (expt (- (vz to) (vz from)) 2))))
         (steps (max 2 (ceiling distance *leap-sample*)))
         (r (body-radius ogre))
         (h (sprite-height ogre))
         (p (vec 0 0 0)))
    ;; Both ends stand on a floor; the points between are in the air.
    (loop for i from 1 below steps
          do (arc-point from to apex duration (* duration (/ i steps)) p)
             (unless (fits-at-p (vx p) (vy p) (vz p) r h)
               (return (leap-refused "arc blocked at ~,2f ~,2f ~,2f" (vx p) (vy p) (vz p))))
          finally (return T))))

(defun plan-leap (ogre)
  "Lay out a leap at the player, into LEAP-FROM, LEAP-TO, LEAP-APEX and LEAP-DURATION:
true if there is a landing cell and an arc OGRE's body fits."
  (let* ((loc (ground-point ogre))
         (r (body-radius ogre))
         (h (sprite-height ogre)))
    (multiple-value-bind (i j k) (and *nav-grid* (nav-nearest-fitting (feet *player*) r h :search 4))
      (unless i
        (return-from plan-leap (leap-refused "no cell under the player fits")))
      (let* ((to (nav-point i j k))
             (distance (sqrt (+ (expt (- (vx to) (vx loc)) 2) (expt (- (vz to) (vz loc)) 2))))
             (rise (- (vy to) (vy loc))))
        (cond ((not (<= *leap-min* distance *leap-max*))
               (leap-refused "landing ~,1f m away" distance))
              ((< *leap-max-rise* rise) (leap-refused "~,1f m up" rise))
              ((< *leap-max-drop* (- rise)) (leap-refused "~,1f m down" (- rise)))
              ((not (clear-path-p (location ogre) (feet *player*) (cast-height ogre)))
               (leap-refused "no line to the player"))
              (T
               (let* ((top (max (vy loc) (vy to)))
                      (ceiling (lowest-ceiling-along loc to top))
                      (apex (if ceiling
                                (min (+ top *leap-apex*) (- ceiling h *leap-headroom*))
                                (+ top *leap-apex*)))
                      (duration (arc-time (vy loc) (vy to) apex)))
                 (cond ((< apex (+ top *leap-min-apex*))
                        (leap-refused "ceiling too low, apex ~,2f over ~,2f" apex top))
                       ((< (* *leap-max-speed* duration) distance)
                        (leap-refused "~,1f m too far for a ~,2f s arc" distance duration))
                       ((arc-clear-p ogre loc to apex duration)
                        (v<- (leap-from ogre) loc)
                        (v<- (leap-to ogre) to)
                        (setf (leap-apex ogre) (float apex 0f0)
                              (leap-duration ogre) (float duration 0f0))
                        T)))))))))

(defmethod special-attack ((ogre ogre))
  (when (and (<= (leap-cooldown ogre) 0) (not (airborne ogre)) (not (falling ogre))
             (<= *leap-min* (player-distance ogre) (+ *leap-max* 1.0))
             (plan-leap ogre))
    (setf (attack-kind ogre) :leap)
    (start-attack ogre)
    T))

;;; The attack.

(defun launch-leap (ogre)
  (let ((from (leap-from ogre))
        (to (leap-to ogre)))
    ;; It may have been shoved in the crouch: the arc leaves from where it is.
    (v<- from (location ogre))
    (setf (airborne ogre) T
          (leap-time ogre) 0.0
          (leap-cooldown ogre) *leap-cooldown*
          (leap-duration ogre) (float (arc-time (vy from) (vy to) (leap-apex ogre)) 0f0))
    (turn-to ogre (atan (- (vx to) (vx from)) (- (vz from) (vz to))) 100.0)
    (setf *leap-peak* (vy from))
    (leap-log "leaps from ~,2f ~,2f ~,2f to ~,2f ~,2f ~,2f, apex ~,2f, ~,2f s"
              (vx from) (vy from) (vz from) (vx to) (vy to) (vz to) (leap-apex ogre) (leap-duration ogre))))

(defmethod attack-step ((ogre ogre) dt)
  (if (eq (attack-kind ogre) :leap)
      (let ((to (leap-to ogre))
            (loc (location ogre)))
        (unless (airborne ogre)
          (turn-to ogre (atan (- (vx to) (vx loc)) (- (vz loc) (vz to))) dt)
          (when (<= *leap-windup* (incf (attack-time ogre) dt))
            (launch-leap ogre))))
      (call-next-method)))

(defmethod release-attack ((ogre ogre))
  (let* ((loc (location ogre))
         (yaw (facing ogre))
         (impact (vec (+ (vx loc) (* *slam-impact* (sin yaw))) (vy loc)
                      (- (vz loc) (* *slam-impact* (cos yaw)))))
         (hit (and (player-within-p ogre (attack-reach ogre))
                   (< (player-angle ogre) (attack-arc ogre))
                   (clear-path-p loc (feet *player*) 1.0))))
    (when hit
      (hurt-player *player* (roll (attack-damage ogre)) loc :shove *slam-shove* :lift *slam-lift*
                   :guard-break (guard-break ogre)))
    (quake ogre impact *slam-quake-radius* NIL *slam-quake-shove*
           (unless hit *slam-quake-shove*) *slam-quake-lift*)
    (kick-dust impact 0.0 1 (container ogre))))

;;; The shockwave.

(defun quake (ogre centre radius damage shove player-shove player-lift &key (inner 0.0))
  "Shake the floor at CENTRE out to RADIUS: everything but OGRE with its feet on that
floor takes DAMAGE (a roll, NIL for none) and is thrown away at SHOVE m/s (the player at
PLAYER-SHOVE, NIL to leave them, and up at PLAYER-LIFT). All of it is full within INNER
of CENTRE (the ogre's own body, when it lands) and falls off to nothing at RADIUS."
  (flet ((falloff (point margin)
           (let* ((dx (- (vx point) (vx centre)))
                  (dz (- (vz point) (vz centre)))
                  (d (- (sqrt (+ (* dx dx) (* dz dz))) margin)))
             (when (and (< d radius) (< (abs (- (vy point) (vy centre))) *quake-reach-height*))
               (min 1.0 (- 1.0 (/ (- d inner) (- radius inner))))))))
    (loop for c across *creatures*
          for f = (and (not (eq c ogre)) (not (dead c)) (falloff (location c) (body-radius c)))
          when f
            do (leap-log "quake hits ~a at ~,2f" (type-of c) f)
               (when damage
                 (let ((amount (round (* f (roll damage)))))
                   (when (<= 1 amount)
                     (hurt c amount :from centre))))
               (let ((away (v- (location c) centre)))
                 (when (< (+ (expt (vx away) 2) (expt (vz away) 2)) 1f-4)
                   (setf (vx away) (sin (facing ogre)) (vz away) (- (cos (facing ogre)))))
                 (push-creature c away (* f shove))))
    (let ((f (and player-shove *player* (< 0 (health *player*))
                  (falloff (feet *player*) *player-radius*))))
      (when f
        (leap-log "quake hits the player at ~,2f" f)
        (let ((from (if (< (+ (expt (- (vx (feet *player*)) (vx centre)) 2)
                              (expt (- (vz (feet *player*)) (vz centre)) 2))
                           1f-4)
                        ;; Right under it: thrown the way it faces.
                        (vec (- (vx centre) (sin (facing ogre))) (vy centre) (+ (vz centre) (cos (facing ogre))))
                        centre)))
          (if damage
              (let ((direct (< (sqrt (+ (expt (- (vx (feet *player*)) (vx centre)) 2)
                                        (expt (- (vz (feet *player*)) (vz centre)) 2)))
                               (+ (body-radius ogre) *player-radius* *direct-hit-margin*))))
                (hurt-player *player* (max 1 (round (* f (if direct *quake-direct-hit* 1.0) (roll damage))))
                             from :shove (* f player-shove) :lift (* f player-lift) :unblockable T))
              (shove-player *player* from (* f player-shove) (* f player-lift))))))))

(defun kick-dust (centre radius count container)
  "Puffs of dust round CENTRE, RADIUS out, if the ogre has a dust animation."
  (when *ogre-dust*
    (let ((turn (random (float (* 2 pi) 0f0))))
      (dotimes (k count)
        (let ((a (+ turn (* k (/ (* 2 pi) count)))))
          (spawn-standing-fx *ogre-dust* (+ (vx centre) (* radius (cos a))) (vy centre)
                             (+ (vz centre) (* radius (sin a))) container))))))

(defun land-leap (ogre)
  (setf (airborne ogre) NIL
        (falling ogre) NIL
        (fall-speed ogre) 0.0
        (attack-kind ogre) :slam)
  (unless (dead ogre)
    (let ((at (location ogre)))
      (leap-log "lands at ~,2f ~,2f ~,2f, its feet at most ~,2f up"
                (vx at) (vy at) (vz at) (- *leap-peak* (vy at)))
      (setf (recover ogre) *leap-recover*)
      (stop-walking ogre *leap-recover*)
      (quake ogre at *quake-radius* *quake-damage* *quake-shove* *quake-player-shove* *quake-player-lift*
             :inner (body-radius ogre))
      (kick-dust at (* 0.6 *quake-radius*) *ogre-dust-puffs* (container ogre))
      (hit-stop *leap-hit-stop*))))

(defvar *arc-point* (vec 0 0 0) "Where FLY-LEAP is on the arc this tick, reused.")

(defun fly-leap (ogre dt)
  "Move OGRE DT seconds along its leap's arc. A wall, ceiling or body in the way cuts
the leap short: it drops from there."
  (let* ((loc (location ogre))
         (p (arc-point (leap-from ogre) (leap-to ogre) (leap-apex ogre) (leap-duration ogre)
                       (incf (leap-time ogre) dt) *arc-point*))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc))))
         (y (if floor (max floor (vy p)) (vy p))))
    (if (fits-at-p (vx loc) y (vz loc) (body-radius ogre) (sprite-height ogre))
        (setf (vy loc) (float y 0f0)
              *leap-peak* (max *leap-peak* (vy loc)))
        (setf (falling ogre) T))
    (unless (falling ogre)
      (multiple-value-bind (x-blocked z-blocked) (move-creature ogre (- (vx p) (vx loc)) (- (vz p) (vz loc)) 0.05)
        (when (or x-blocked z-blocked)
          (leap-log "leap cut short at ~,2f ~,2f ~,2f" (vx loc) (vy loc) (vz loc))
          (setf (falling ogre) T))))
    (cond ((falling ogre)
           (setf (airborne ogre) NIL))
          ((<= (leap-duration ogre) (leap-time ogre))
           (land-leap ogre)))))

(defun drop-ogre (ogre dt)
  "Drop OGRE under gravity onto the floor under it, and land there."
  (let* ((loc (location ogre))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
    (if (and floor (< floor (vy loc)))
        (setf (vy loc) (float (max floor (- (vy loc) (* (incf (fall-speed ogre) (* *leap-gravity* dt)) dt))) 0f0))
        (land-leap ogre))))

(defmethod break-flight ((ogre ogre))
  (setf (airborne ogre) NIL
        (falling ogre) NIL
        (fall-speed ogre) 0.0
        (recover ogre) 0.0
        (attack-kind ogre) :slam))

(defmethod keep-height ((ogre ogre) dt)
  (setf (leap-cooldown ogre) (max 0.0 (- (leap-cooldown ogre) dt))
        (recover ogre) (max 0.0 (- (recover ogre) dt)))
  (cond ((or (airborne ogre) (falling ogre))
         ;; The flight moves it: hold its thinking still, hit or not.
         (unless (dead ogre)
           (stop-walking ogre (max 0.1 (idle-timer ogre))))
         (if (airborne ogre) (fly-leap ogre dt) (drop-ogre ogre dt)))
        (T
         ;; A leap broken off in its crouch (a hit) is forgotten; the next attack is a slam.
         (unless (eq (brain ogre) :attacking)
           (setf (attack-kind ogre) :slam))
         (call-next-method))))

(defmethod show-own-pose ((ogre ogre) squash)
  (cond ((dead ogre) NIL)
        ((or (airborne ogre) (falling ogre))
         (show-view-frame ogre (leap-animation ogre) 1 squash) T)
        ((< 0 (recover ogre))
         (show-view-frame ogre (leap-animation ogre) 2 squash) T)))

;; It sees down off a balcony's ledge, as far as it leaps down.
(defmethod sight-rise ((ogre ogre)) (+ *leap-max-drop* 0.5))
