(in-package #:hexmaw)

;;; First-person controller. The player is the camera: FEET is the position on
;;; the ground, the eye sits EYE-HEIGHT above it. Collision is box-vs-box
;;; against *SOLIDS*, resolved one axis at a time.

(defparameter *walk-speed* 4.0)
(defparameter *run-speed* 7.0)
(defparameter *crouch-speed* 2.0)
(defparameter *ground-acceleration* 40.0)
(defparameter *air-control* 0.3)
(defparameter *gravity* 20.0)
(defparameter *jump-speed* 6.5)
(defparameter *eye-height* 1.6)
(defparameter *crouch-eye-height* 0.9)
(defparameter *eye-height-speed* 6.0)
(defparameter *step-height* 0.45)
(defparameter *player-radius* 0.3)
(defparameter *player-height* 1.8)
(defparameter *mouse-sensitivity* 0.0025)
(defparameter *player-max-health* 100)
(defparameter *max-mana* 50.0)
(defparameter *max-stamina* 100.0)
(defparameter *stamina-regen* 8.0 "Stamina per second while not running.")
(defparameter *run-stamina* 15.0 "Stamina per second a run costs.")
(defparameter *jump-stamina* 15.0 "Stamina a jump costs; with less, no jump.")
(defparameter *block-stamina-scale* 2.0
  "Stamina a blow on the raised shield costs, per point of its damage before the shield.")
(defparameter *winded-recover* 25.0 "Stamina a player who ran it empty needs before running again.")
(defparameter *stamina-guard-break* 1.0
  "Seconds a blow the shield hasn't the stamina for knocks it aside (BREAK-GUARD).")
(defparameter *cast-cooldown* 0.35 "Seconds between casts.")
(defparameter *cast-release* 0.2
  "Seconds from the click until the spell leaves the hands: the cast animation's release frame.")
(defparameter *player-knockback* 3.0 "Speed in m/s a blow shoves the player away from it.")
(defparameter *block-arc* 1.0 "Radians either side of the view the raised shield covers.")
(defparameter *block-damage-scale* 0.25 "Fraction of a blocked blow's damage that gets through.")
(defparameter *block-shove-scale* 0.4 "Fraction of a blocked blow's shove that gets through.")
(defparameter *block-speed-scale* 0.6
  "Fraction of the walking speed the player keeps with the shield fully raised; no running.")
(defparameter *pain-time* 0.35 "Seconds the screen flashes red after the player is hurt.")
(defparameter *swim-speed* 3.0)
(defparameter *swim-run-speed* 4.5)
(defparameter *swim-acceleration* 10.0 "Metres per second squared toward the swim wished for.")
(defparameter *water-drag* 3.0
  "Per second, the share of speed water takes from something moving faster than a swim (a
dive in, a shove), as an exponential.")
(defparameter *swim-sink* 0.4 "Metres per second a player sinks at below the surface, swimming nowhere.")
(defparameter *swim-waist* 0.9 "Metres above the feet that must be in water to swim.")
(defparameter *float-eye* 0.15 "Metres above the surface the eye floats at.")
(defparameter *climb-out-height* 0.8 "The highest a ledge may stand over the surface for the player to climb out onto it.")
(defparameter *climb-speed* 3.0 "Metres per second a climb out rises.")
(defparameter *climb-time* 1.0 "Seconds a climb out may take before it gives up.")
(defparameter *breath-time* 20.0 "Seconds the player can stay under water.")
(defparameter *breath-refill* 5.0 "Seconds of breath regained per second in air.")
(defparameter *drown-damage* 10.0 "Health per second lost under water with no breath left.")
(defparameter *spawn-point* (vec 0 0 5))
(defparameter *kill-height* -20.0)

(defclass player (fps-camera)
  ((name :initform :player)
   (fov :initform 75.0)
   (near-plane :initform 0.05f0)
   (far-plane :initform 200.0f0)
   (feet :initform (vcopy *spawn-point*) :accessor feet)
   (velocity :initform (vec 0 0 0) :accessor velocity)
   (grounded :initform NIL :accessor grounded)
   (footing :initform NIL :accessor footing
            :documentation "The footing (*FOOTINGS*) of the floor it stood on last tick, or NIL.")
   (eye :initform *eye-height* :accessor eye)
   (mouse-look :initform NIL :accessor mouse-look)
   (health :initform *player-max-health* :accessor health)
   (pain :initform 0.0 :accessor pain :documentation "Seconds of the pain flash left.")
   (burn-timer :initform 0.0 :accessor burn-timer
               :documentation "Seconds until the next burn can land (liquids.lisp).")
   (wading :initform NIL :accessor wading
           :documentation "Kind of the liquid last stood in, NIL on dry ground: it slows a jump from it.")
   (swimming :initform NIL :accessor swimming :documentation "True while in water up to the waist.")
   (climbing :initform NIL :accessor climbing
             :documentation "Seconds left of a climb out of the water onto a ledge, or NIL.")
   (breath :initform *breath-time* :accessor breath :documentation "Seconds of breath left.")
   (drown-timer :initform 0.0 :accessor drown-timer
                :documentation "Seconds until the next drowning damage can land (BURN-DUE).")
   (mana :initform *max-mana* :accessor mana)
   (stamina :initform *max-stamina* :accessor stamina)
   (winded :initform NIL :accessor winded
           :documentation "True from running out of stamina until *WINDED-RECOVER*: no running.")
   (cast-timer :initform 0.0 :accessor cast-timer)
   (cast-time :initform NIL :accessor cast-time
              :documentation "Seconds since the last cast began, or NIL before the first.")
   (pending-spell :initform NIL :accessor pending-spell
                  :documentation "Spell being cast, launched at *CAST-RELEASE*.")
   (weapon :initform :hands :accessor weapon :documentation "Weapon on screen (sword.lisp).")
   (wanted-weapon :initform :hands :accessor wanted-weapon
                  :documentation "Weapon asked for; differs from WEAPON while switching.")
   (weapon-lower :initform 0.0 :accessor weapon-lower
                 :documentation "How far the weapon on screen is lowered: 0 up, 1 gone.")
   (swing-time :initform NIL :accessor swing-time
               :documentation "Seconds since the sword swing began, or NIL when not swinging.")
   (swing-pending :initform NIL :accessor swing-pending
                  :documentation "True until the swing's blow has landed.")
   (block-held :initform NIL :accessor block-held
               :documentation "True while the block button (the right one) is down.")
   (block-raise :initform 0.0 :accessor block-raise
                :documentation "How far the shield is raised to block: 0 down, 1 up.")
   (bash-time :initform NIL :accessor bash-time
              :documentation "Seconds since the shield bash began, or NIL when not bashing.")
   (bash-pending :initform NIL :accessor bash-pending
                 :documentation "True until the bash's blow has landed.")
   (guard-broken :initform 0.0 :accessor guard-broken
                 :documentation "Seconds left before the shield can be raised again, after a
blow knocked it aside (BREAK-GUARD).")))

(defun capture-mouse (player)
  (lock-cursor (context +main+))
  (setf (mouse-look player) T))

(defun release-mouse (player)
  (show-cursor (context +main+))
  (setf (mouse-look player) NIL))

(defun look-direction (player)
  "Unit vector the player is looking along, pitch included."
  (let ((pitch (vx (rotation player)))
        (yaw (vy (rotation player))))
    (vec (* (sin yaw) (cos pitch)) (- (sin pitch)) (- (* (cos yaw) (cos pitch))))))

(defun player-cast (player name)
  "Start casting spell NAME, if mana and the cooldown allow. The hands wind up and the
spell leaves *CAST-RELEASE* seconds later (RELEASE-SPELL). Returns true if it was cast."
  (let* ((spell (find-spell name))
         (cost (spell-cost spell)))
    (when (and (<= (cast-timer player) 0) (<= cost (mana player)))
      (decf (mana player) cost)
      (setf (cast-timer player) *cast-cooldown*
            (cast-time player) 0.0
            (pending-spell player) spell)
      T)))

(defun release-spell (player)
  "Fire the pending spell from just below the eye toward where the player looks now."
  (let* ((dir (look-direction player))
         (origin (v+ (location player) (v* dir 0.5) (vec 0 -0.2 0))))
    (cast-spell (pending-spell player) origin dir (container player) :caster player)
    (setf (pending-spell player) NIL)))

;;; Clicks in a menu belong to the menu (menu.lisp), as does Esc.

(define-handler (player mouse-press) (button)
  (when (eq *game-state* :playing)
    (cond ((not (mouse-look player))
           (capture-mouse player))
          ((eq button :left)
           (player-attack player))
          ((eq button :right)
           (setf (block-held player) T)))))

(define-handler (player mouse-release) (button)
  (when (eq button :right)
    (setf (block-held player) NIL)))

(define-handler (player key-press) (key)
  (case key
    (:f12 (screenshot))
    (T (when (eq *game-state* :playing)
         (select-weapon player key)))))

(define-handler (player mouse-scroll) (delta)
  ;; Wheel down (negative delta) for the next weapon, up for the previous one.
  (when (and (eq *game-state* :playing) (/= 0 delta))
    (cycle-weapon player (if (< delta 0) 1 -1))))

(define-handler (player mouse-move) (old-pos pos)
  (when (mouse-look player)
    (let ((rot (rotation player)))
      ;; Mouse Y grows upward here, while positive pitch looks down; hence the minus.
      (setf (vx rot) (max -1.55 (min 1.55 (- (vx rot) (* *mouse-sensitivity* (- (vy pos) (vy old-pos)))))))
      (setf (vy rot) (mod (+ (vy rot) (* *mouse-sensitivity* (- (vx pos) (vx old-pos)))) #.(float (* 2 pi) 0f0))))))

(defmethod body-feet ((player player)) (feet player))
(defmethod body-radius ((player player)) *player-radius*)
(defmethod body-height ((player player)) *player-height*)
(defmethod body-solid-p ((player player)) T)

(defvar *walk-through-bodies* NIL
  "True while the player already overlaps a body (something revived on it), so it can walk out.")

(defun overlapping-solid (feet)
  "Return the first solid or body the player box at FEET overlaps, or NIL."
  (let ((r (float *player-radius* 0f0)) (h (float *player-height* 0f0)))
    (or (solid-overlapping (vx feet) (vy feet) (vz feet) r h)
        (unless *walk-through-bodies*
          (body-overlapping (vx feet) (vy feet) (vz feet) r h *player*)))))

(defun move-axis (player axis delta)
  "Move along AXIS (0 x, 1 y, 2 z) by DELTA, stopping flush against solids. Returns the
wedge whose diagonal stopped it, if one did, and how far short of DELTA it stopped."
  (let ((feet (feet player))
        (vel (velocity player))
        (wedge NIL))
    (flet ((ref (v) (ecase axis (0 (vx v)) (1 (vy v)) (2 (vz v))))
           (put (v x) (ecase axis (0 (setf (vx v) x)) (1 (setf (vy v) x)) (2 (setf (vz v) x)))))
      (let ((target (+ (ref feet) delta)))
        (put feet target)
        (loop repeat 8
              for s = (overlapping-solid feet)
              while s
              do (cond ((/= axis 1)
                        (multiple-value-bind (at diagonal)
                            (solid-flush s axis delta (vx feet) (vz feet) (float *player-radius* 0f0))
                          (put feet at)
                          (setf wedge (and diagonal s))))
                       ((< 0 delta)
                        (put feet (- (aref s 1) (float *player-height* 0f0))))
                       (T
                        (put feet (aref s 4))
                        (setf (grounded player) T)))
                 (put vel 0f0)
                 (when (= 0 delta) (return)))
        (values wedge (- target (ref feet)))))))

(defun move-flat (player dx dz)
  "Move by DX then DZ against solids, sliding along a wedge's diagonal where it stops one."
  (flet ((go-axis (axis delta)
           (multiple-value-bind (wedge blocked) (move-axis player axis delta)
             (when wedge
               ;; Along the wall: first the other axis, which leads away from it, then this one.
               (multiple-value-bind (sx sz) (slide-along wedge axis blocked)
                 (if (= axis 0)
                     (progn (move-axis player 2 sz) (move-axis player 0 sx))
                     (progn (move-axis player 0 sx) (move-axis player 2 sz))))))))
    (go-axis 0 dx)
    (go-axis 2 dz)))

(defun horizontal-distance-squared (feet x0 z0)
  (+ (expt (- (vx feet) x0) 2) (expt (- (vz feet) z0) 2)))

(defun move-horizontal (player dx dz can-step)
  "Move by DX, DZ against solids. When CAN-STEP and the move is blocked, also try it
raised by up to *STEP-HEIGHT* and dropped back down, and keep whichever got further.
On a step the eye keeps its height and eases to the new one."
  (let* ((feet (feet player)) (vel (velocity player))
         (x0 (vx feet)) (y0 (vy feet)) (z0 (vz feet))
         (vx0 (vx vel)) (vy0 (vy vel)) (vz0 (vz vel)))
    (move-flat player dx dz)
    ;; MOVE-AXIS zeroes the velocity component it was blocked on.
    (when (and can-step (or (/= (vx vel) vx0) (/= (vz vel) vz0)))
      (let ((px (vx feet)) (pz (vz feet)) (pvx (vx vel)) (pvz (vz vel))
            (plain (horizontal-distance-squared feet x0 z0)))
        (setf (vx feet) x0 (vy feet) y0 (vz feet) z0 (vx vel) vx0 (vy vel) vy0 (vz vel) vz0)
        (move-axis player 1 (float *step-height* 0f0))
        (move-flat player dx dz)
        (move-axis player 1 (- y0 (vy feet)))
        (if (< (+ plain 1f-8) (horizontal-distance-squared feet x0 z0))
            (decf (eye player) (- (vy feet) y0))
            (setf (vx feet) px (vy feet) y0 (vz feet) pz
                  (vx vel) pvx (vy vel) vy0 (vz vel) pvz
                  (grounded player) NIL))))))

(defun snap-to-ground (player)
  "Keep a walking player on the floor when it drops away by up to *STEP-HEIGHT*
(walking down steps) instead of letting them fall off each one."
  (let* ((feet (feet player)) (vel (velocity player))
         (y0 (vy feet)) (vy0 (vy vel)))
    (move-axis player 1 (- (float *step-height* 0f0)))
    (if (grounded player)
        (incf (eye player) (- y0 (vy feet)))
        (setf (vy feet) y0 (vy vel) vy0))))

(defun place-camera (player)
  "Put the camera at the player's eye, and note whether it is under water (the fog)."
  (let ((loc (location player))
        (feet (feet player)))
    (setf (vx loc) (vx feet)
          (vy loc) (+ (vy feet) (float (eye player) 0f0))
          (vz loc) (vz feet))
    (setf *eye-underwater* (swim-liquid-at (vx loc) (vy loc) (vz loc)))))

;;; Swimming, Quake-style: in water to the waist the player swims where they look (W and S
;;; along the view, A and D level), Space up and C or Ctrl down, against the water's drag,
;;; sinking slowly when swimming nowhere and floating with the eye just over the surface.
;;; Pushing forward against a ledge at the surface climbs out onto it.

(defun swim-water (player)
  "The water PLAYER is in up to the waist, or NIL."
  (let ((feet (feet player)))
    (swim-liquid-at (vx feet) (+ (vy feet) *swim-waist*) (vz feet))))

(defun ledge-ahead-p (player surface yaw)
  "True if a ledge stands ahead of PLAYER no more than *CLIMB-OUT-HEIGHT* over the water's
SURFACE, with room to stand on it."
  (let* ((feet (feet player))
         (reach (+ *player-radius* 0.35))
         (x (+ (vx feet) (* reach (sin yaw))))
         (z (- (vz feet) (* reach (cos yaw)))))
    (and (solid-overlapping x surface z 0.05 *climb-out-height*)
         (not (solid-overlapping x (+ surface *climb-out-height*) z *player-radius* *player-height*)))))

(defun swim (player water dt ix iz up running yaw)
  "Move PLAYER through WATER for DT seconds: IX IZ the strafe and forward keys, UP the
up and down keys (1, 0 or -1)."
  (let* ((vel (velocity player))
         (feet (feet player))
         (surface (aref (liquid-bounds water) 4))
         (pitch (vx (rotation player)))
         (cp (cos pitch))
         (wx (+ (* iz (sin yaw) cp) (* ix (cos yaw))))
         (wy (+ (* iz (- (sin pitch))) up))
         (wz (+ (* iz (- (cos yaw)) cp) (* ix (sin yaw))))
         (len (sqrt (+ (* wx wx) (* wy wy) (* wz wz))))
         (speed (if running *swim-run-speed* *swim-speed*))
         (float-y (+ surface *float-eye*))
         (eye-y (+ (vy feet) *eye-height*))
         (at-surface (< (- float-y 0.3) eye-y)))
    (when (< 1.0 len)
      (setf wx (/ wx len) wy (/ wy len) wz (/ wz len)))
    ;; Faster than a swim, the water's drag slows it.
    (when (< (* speed speed) (+ (expt (vx vel) 2) (expt (vy vel) 2) (expt (vz vel) 2)))
      (let ((keep (exp (- (* *water-drag* dt)))))
        (setf (vx vel) (* (vx vel) keep) (vy vel) (* (vy vel) keep) (vz vel) (* (vz vel) keep))))
    ;; Toward the wished velocity. Swimming nowhere, it floats up to the surface when near
    ;; it, and sinks slowly when below.
    (let* ((tx (* wx speed))
           (ty (cond ((< 0 (abs wy)) (* wy speed))
                     (at-surface (max (- *swim-sink*) (min speed (* 2.0 (- float-y eye-y)))))
                     (T (- *swim-sink*))))
           (tz (* wz speed))
           (dx (- tx (vx vel))) (dy (- ty (vy vel))) (dz (- tz (vz vel)))
           (dlen (sqrt (+ (* dx dx) (* dy dy) (* dz dz))))
           (max-dv (* *swim-acceleration* dt)))
      (when (< max-dv dlen)
        (let ((f (/ max-dv dlen))) (setf dx (* dx f) dy (* dy f) dz (* dz f))))
      (incf (vx vel) dx) (incf (vy vel) dy) (incf (vz vel) dz))
    (let ((vx0 (vx vel)) (vz0 (vz vel)))
      (setf (grounded player) NIL)
      (move-horizontal player (* (vx vel) dt) (* (vz vel) dt) NIL)
      (move-axis player 1 (* (vy vel) dt))
      ;; The surface holds the eye: swimming up stops there.
      (let ((over (- (+ (vy feet) *eye-height*) float-y)))
        (when (and (< 0 over) (< 0 (vy vel)))
          (setf (vy vel) 0f0)))
      ;; Pushing forward into a ledge at the surface: climb out.
      (when (and at-surface (< 0 iz)
                 (or (/= vx0 (vx vel)) (/= vz0 (vz vel)))
                 (ledge-ahead-p player surface yaw))
        (setf (climbing player) *climb-time*)))))

(defun climb-out (player dt yaw)
  "Rise for DT seconds of a climb out, then step forward onto the ledge once clear of it."
  (let* ((feet (feet player))
         (vel (velocity player))
         (fx (sin yaw)) (fz (- (cos yaw)))
         (x0 (vx feet)) (z0 (vz feet)))
    (setf (vx vel) 0f0 (vz vel) 0f0 (vy vel) (float *climb-speed* 0f0)
          (grounded player) NIL)
    (move-axis player 1 (* *climb-speed* dt))
    (move-flat player (* fx 1.5 dt) (* fz 1.5 dt))
    (decf (climbing player) dt)
    ;; Over the ledge, or out of time: on with walking, a little forward.
    (when (or (< (* 1.0 dt) (sqrt (+ (expt (- (vx feet) x0) 2) (expt (- (vz feet) z0) 2))))
              (<= (climbing player) 0))
      (setf (climbing player) NIL
            (vx vel) (float (* fx 2.0) 0f0) (vy vel) 0f0 (vz vel) (float (* fz 2.0) 0f0)))))

(defun update-breath (player dt)
  "Use up PLAYER's breath while its eye is under water, regain it in air, and drown it
with none left."
  (let* ((feet (feet player))
         (under (swim-liquid-at (vx feet) (+ (vy feet) (eye player)) (vz feet))))
    (setf (breath player) (if under
                              (max 0.0 (- (breath player) dt))
                              (min *breath-time* (+ (breath player) (* *breath-refill* dt)))))
    (multiple-value-bind (timer damage)
        (burn-due (drown-timer player) dt (if (and under (<= (breath player) 0)) *drown-damage* 0.0))
      (setf (drown-timer player) timer)
      (when (< 0 damage)
        (hurt-player player damage feet :shove NIL)))))

(defun update-stamina (player running dt)
  "Spend PLAYER's stamina while RUNNING, regain it otherwise. Running it empty leaves the
player WINDED until *WINDED-RECOVER*, so they don't stutter between a run and a walk."
  (if running
      (when (<= (decf (stamina player) (* *run-stamina* dt)) 0.0)
        (setf (stamina player) 0.0
              (winded player) T))
      (setf (stamina player) (min *max-stamina* (+ (stamina player) (* *stamina-regen* dt)))))
  (when (and (winded player) (<= *winded-recover* (stamina player)))
    (setf (winded player) NIL)))

(define-handler (player tick) (dt)
  (when (frozen-p)
    ;; Still place the camera, so a game that starts frozen (the main menu) shows the level.
    (place-camera player)
    (return))
  (setf (cast-timer player) (max 0.0 (- (cast-timer player) dt))
        (pain player) (max 0.0 (- (pain player) dt))
        (guard-broken player) (max 0.0 (- (guard-broken player) dt)))
  (when (cast-time player)
    (incf (cast-time player) dt)
    (when (and (pending-spell player) (<= *cast-release* (cast-time player)))
      (release-spell player)))
  (update-weapons player dt)
  (let* ((dt (min dt 0.05))
         (yaw (vy (rotation player)))
         (crouching (or (retained :left-control) (retained :c)))
         (ix (- (if (retained :d) 1.0 0.0) (if (retained :a) 1.0 0.0)))
         (iz (- (if (retained :w) 1.0 0.0) (if (retained :s) 1.0 0.0)))
         (wx (+ (* iz (sin yaw)) (* ix (cos yaw))))
         (wz (+ (* iz (- (cos yaw))) (* ix (sin yaw))))
         (wlen (sqrt (+ (* wx wx) (* wz wz))))
         (liquid (let ((feet (feet player))) (liquid-at (vx feet) (+ (vy feet) 0.05) (vz feet))))
         ;; A jump from a liquid stays slowed until it lands outside one.
         (kind (if (grounded player)
                   (setf (wading player) (and liquid (liquid-kind liquid)))
                   (if liquid (liquid-kind liquid) (wading player))))
         (raise (block-raise player))
         (running (and (retained :left-shift) (< 0.0 wlen) (not crouching) (= 0.0 raise)
                       (not (winded player))))
         ;; The raised shield slows the player to a walk and below.
         (speed (* (cond (crouching *crouch-speed*)
                         (running *run-speed*)
                         (T *walk-speed*))
                   (+ 1.0 (* raise (- *block-speed-scale* 1.0)))
                   (if kind (liquid-property kind :speed) 1.0))))
    (when (< 1.0 wlen)
      (setf wx (/ wx wlen) wz (/ wz wlen)))
    (let ((water (swim-water player)))
      (setf (swimming player) (and water T))
      (cond ((climbing player)
             (climb-out player dt yaw))
            (water
             (setf (footing player) NIL)
             (swim player water dt ix iz
                   (- (if (retained :space) 1.0 0.0) (if crouching 1.0 0.0))
                   running yaw))
            (T (walk player dt wx wz wlen speed kind crouching))))
    (update-stamina player running dt)
    (when (< (vy (feet player)) *kill-height*)
      (respawn player))
    ;; Standing in lava burns; under water with no breath left, drowning.
    (let ((feet (feet player)))
      (multiple-value-bind (timer damage)
          (burn-due (burn-timer player) dt (hazard-at (vx feet) (+ (vy feet) 0.05) (vz feet)))
        (setf (burn-timer player) timer)
        (when (< 0 damage)
          (hurt-player player damage feet :shove NIL))))
    (update-breath player dt)
    ;; Ease the eye toward standing or crouching height, then place the camera.
    (let ((target (if (and crouching (not (swimming player))) *crouch-eye-height* *eye-height*)))
      (setf (eye player) (+ (eye player) (* (- target (eye player)) (min 1.0 (* *eye-height-speed* dt))))))
    (place-camera player)))

(defun walk (player dt wx wz wlen speed kind crouching)
  "Move PLAYER on foot or through the air for DT seconds, wishing along WX WZ (WLEN long)
at SPEED, out of liquid KIND if any."
  (let ((vel (velocity player)))
    (setf (footing player) (and (grounded player)
                                (let ((feet (feet player))) (floor-footing (vx feet) (vy feet) (vz feet) *player-radius*))))
    (if (footing player)
        ;; On ice the wish only pushes the momentum (footing.lisp).
        (progn (footing-drag vel (footing player) dt (= 0 wlen))
               (footing-push vel wx wz speed (footing player) dt))
        ;; Accelerate horizontal velocity toward the wished velocity. In the air that steers
        ;; but never brakes: a launch faster than a run (off ice) keeps its speed.
        (let* ((speed (if (grounded player)
                          speed
                          (max speed (sqrt (+ (expt (vx vel) 2) (expt (vz vel) 2))))))
               (dvx (- (* wx speed) (vx vel)))
               (dvz (- (* wz speed) (vz vel)))
               (dlen (sqrt (+ (* dvx dvx) (* dvz dvz))))
               (max-dv (* *ground-acceleration* (if (grounded player) 1.0 *air-control*) dt)))
          (when (< max-dv dlen)
            (setf dvx (* dvx (/ max-dv dlen)) dvz (* dvz (/ max-dv dlen))))
          (incf (vx vel) dvx)
          (incf (vz vel) dvz)))
    (when (and (grounded player) (retained :space) (not crouching)
               (<= *jump-stamina* (stamina player)))
      (decf (stamina player) *jump-stamina*)
      (setf (vy vel) (float (* *jump-speed* (if kind (liquid-property kind :jump) 1.0)) 0f0)))
    (decf (vy vel) (* *gravity* dt))
    ;; Steps only while walking: not mid-air, and not on the frame a jump starts.
    (let ((walking (and (grounded player) (<= (vy vel) 0)))
          (*walk-through-bodies* (let ((feet (feet player)))
                                   (body-overlapping (vx feet) (vy feet) (vz feet)
                                                     (float *player-radius* 0f0) (float *player-height* 0f0)
                                                     player))))
      (setf (grounded player) NIL)
      (move-horizontal player (* (vx vel) dt) (* (vz vel) dt) walking)
      (move-axis player 1 (* (vy vel) dt))
      (when (and walking (not (grounded player)))
        (snap-to-ground player)))))

(defun shove-player (player from speed &optional lift)
  "Push PLAYER away from point FROM at SPEED m/s, and with LIFT, up at that many m/s."
  (let* ((feet (feet player))
         (vel (velocity player))
         (speed (float speed 0f0))
         (dx (- (vx feet) (vx from)))
         (dz (- (vz feet) (vz from)))
         (len (sqrt (+ (* dx dx) (* dz dz)))))
    (when (< 1f-4 len)
      (incf (vx vel) (* speed (/ dx len)))
      (incf (vz vel) (* speed (/ dz len))))
    (when lift
      (setf (vy vel) (max (vy vel) (float lift 0f0))))))

(defun shield-facing-p (player from &optional (margin 0.0))
  "True if PLAYER's shield is raised at all (sword.lisp) and point FROM lies within
*BLOCK-ARC*, plus MARGIN radians, of where the player faces."
  (and (eq (weapon player) :sword)
       (< 0.0 (block-raise player))
       (let* ((feet (feet player))
              (dx (- (vx from) (vx feet)))
              (dz (- (vz from) (vz feet)))
              (len (sqrt (+ (* dx dx) (* dz dz))))
              (yaw (vy (rotation player))))
         (and (< 1f-4 len)
              (< (acos (max -1.0 (min 1.0 (/ (- (* dx (sin yaw)) (* dz (cos yaw))) len))))
                 (+ *block-arc* margin))))))

(defun shield-blocks-p (player from)
  "True if PLAYER's shield is fully raised and a blow from point FROM comes from within
*BLOCK-ARC* of where the player faces."
  (and (<= 1.0 (block-raise player))
       (shield-facing-p player from)))

(defun break-guard (player seconds)
  "Knock PLAYER's shield aside: down at once, a bash in progress cut off, and not raised
again for SECONDS."
  (setf (guard-broken player) (max (guard-broken player) (float seconds 0f0))
        (block-raise player) 0.0
        (bash-time player) NIL
        (bash-pending player) NIL))

(defun hurt-player (player amount from &key (shove T) lift guard-break unblockable)
  "Take AMOUNT health from PLAYER, struck from point FROM: a red flash, a shove away
from FROM and hit-stop. SHOVE is T for *PLAYER-KNOCKBACK*, a speed in m/s, or NIL (a
burn: only the flash). LIFT, in m/s, also throws the player up off their feet, where a
shove carries much further than on the ground. A blow the raised shield meets
(SHIELD-BLOCKS-P; never an UNBLOCKABLE one) costs *BLOCK-STAMINA-SCALE* stamina a point of
damage, does *BLOCK-DAMAGE-SCALE* of its damage, at least 1, and shoves and lifts
*BLOCK-SHOVE-SCALE* as far; with GUARD-BREAK it also knocks the shield aside for that many
seconds (BREAK-GUARD). With too little stamina the blow goes through in full, takes what
stamina is left and knocks the shield aside for at least *STAMINA-GUARD-BREAK*. At zero
health the run starts over."
  (when (< 0 (health player))
    (let ((blocked (and shove (not unblockable) (shield-blocks-p player from))))
      (when blocked
        (let ((cost (* amount *block-stamina-scale*)))
          (cond ((<= cost (stamina player))
                 (decf (stamina player) cost)
                 (setf amount (max 1 (round (* amount *block-damage-scale*))))
                 (when guard-break
                   (break-guard player guard-break)))
                (T
                 (setf (stamina player) 0.0
                       blocked NIL)
                 (break-guard player (max *stamina-guard-break* (or guard-break 0)))))))
      (decf (health player) amount)
      (setf (pain player) *pain-time*)
      (when shove
        (let ((k (if blocked *block-shove-scale* 1.0)))
          (shove-player player from (* k (if (eq shove T) *player-knockback* shove)) (and lift (* k lift))))
        (hit-stop)))
    (when (<= (health player) 0)
      ;; No death screen yet. Not now: this runs inside a creature's tick, and
      ;; RESET-RUN despawns entities.
      (queue-menu-action 'reset-run))))

(defun player-at-p (player point margin)
  "True if POINT lies in PLAYER's body, grown by MARGIN metres."
  (let ((feet (feet player))
        (r (+ *player-radius* margin)))
    (and (< (abs (- (vx point) (vx feet))) r)
         (< (abs (- (vz point) (vz feet))) r)
         (< (- (vy feet) margin) (vy point) (+ (vy feet) *player-height* margin)))))

;; A creature's spell, hitting the player: the shove follows the projectile's flight.
(defmethod apply-effect ((kind (eql :damage)) effect (target player) (source spell-projectile))
  (hurt-player target (roll (effect-magnitude effect)) (v- (location source) (projectile-velocity source))))

(defmethod apply-effect ((kind (eql :knockback)) effect (target player) (source spell-projectile))
  (let* ((flight (projectile-velocity source))
         (len (sqrt (+ (expt (vx flight) 2) (expt (vz flight) 2))))
         (speed (* (float (roll (effect-magnitude effect)) 0f0)
                   (if (shield-blocks-p target (v- (location source) flight)) *block-shove-scale* 1.0)))
         (vel (velocity target)))
    (when (< 1f-4 len)
      (incf (vx vel) (* speed (/ (vx flight) len)))
      (incf (vz vel) (* speed (/ (vz flight) len))))))

(defun respawn (player)
  (let ((feet (feet player)))
    (setf (vx feet) (vx *spawn-point*) (vy feet) (vy *spawn-point*) (vz feet) (vz *spawn-point*)))
  (setf (vx (velocity player)) 0f0 (vy (velocity player)) 0f0 (vz (velocity player)) 0f0))
