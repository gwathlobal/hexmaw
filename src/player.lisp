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
(defparameter *max-mana* 50.0)
(defparameter *mana-regen* 8.0 "Mana per second.")
(defparameter *cast-cooldown* 0.35 "Seconds between casts.")
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
   (eye :initform *eye-height* :accessor eye)
   (mouse-look :initform NIL :accessor mouse-look)
   (mana :initform *max-mana* :accessor mana)
   (cast-timer :initform 0.0 :accessor cast-timer)))

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
  "Cast spell NAME from just below the eye toward where the player looks, if mana and
the cooldown allow. Returns true if it was cast."
  (let* ((spell (find-spell name))
         (cost (spell-cost spell)))
    (when (and (<= (cast-timer player) 0) (<= cost (mana player)))
      (decf (mana player) cost)
      (setf (cast-timer player) *cast-cooldown*)
      (let* ((dir (look-direction player))
             (origin (v+ (location player) (v* dir 0.5) (vec 0 -0.2 0))))
        (cast-spell spell origin dir (container player)))
      T)))

(define-handler (player mouse-press) (button)
  (cond ((not (mouse-look player))
         (capture-mouse player))
        ((eq button :left)
         (player-cast player 'bolt))))

(define-handler (player key-press) (key)
  (case key
    (:escape (release-mouse player))
    (:f12 (screenshot))))

(define-handler (player mouse-move) (old-pos pos)
  (when (mouse-look player)
    (let ((rot (rotation player)))
      ;; Mouse Y grows upward here, while positive pitch looks down; hence the minus.
      (setf (vx rot) (max -1.55 (min 1.55 (- (vx rot) (* *mouse-sensitivity* (- (vy pos) (vy old-pos)))))))
      (setf (vy rot) (mod (+ (vy rot) (* *mouse-sensitivity* (- (vx pos) (vx old-pos)))) #.(float (* 2 pi) 0f0))))))

(defun overlapping-solid (feet)
  "Return the first solid the player box at FEET overlaps, or NIL."
  (solid-overlapping (vx feet) (vy feet) (vz feet)
                     (float *player-radius* 0f0) (float *player-height* 0f0)))

(defun move-axis (player axis delta)
  "Move along AXIS (0 x, 1 y, 2 z) by DELTA, stopping flush against solids."
  (let ((feet (feet player))
        (vel (velocity player)))
    (flet ((ref (v) (ecase axis (0 (vx v)) (1 (vy v)) (2 (vz v))))
           (put (v x) (ecase axis (0 (setf (vx v) x)) (1 (setf (vy v) x)) (2 (setf (vz v) x)))))
      (put feet (+ (ref feet) delta))
      (loop repeat 8
            for s = (overlapping-solid feet)
            while s
            do (let ((lo (aref s axis)) (hi (aref s (+ axis 3))))
                 (cond ((< 0 delta)
                        (put feet (- lo (if (= axis 1) (float *player-height* 0f0) (float *player-radius* 0f0)))))
                       (T
                        (put feet (+ hi (if (= axis 1) 0f0 (float *player-radius* 0f0))))
                        (when (= axis 1) (setf (grounded player) T))))
                 (put vel 0f0)
                 (when (= 0 delta) (return)))))))

(defun horizontal-distance-squared (feet x0 z0)
  (+ (expt (- (vx feet) x0) 2) (expt (- (vz feet) z0) 2)))

(defun move-horizontal (player dx dz can-step)
  "Move by DX, DZ against solids. When CAN-STEP and the move is blocked, also try it
raised by up to *STEP-HEIGHT* and dropped back down, and keep whichever got further.
On a step the eye keeps its height and eases to the new one."
  (let* ((feet (feet player)) (vel (velocity player))
         (x0 (vx feet)) (y0 (vy feet)) (z0 (vz feet))
         (vx0 (vx vel)) (vy0 (vy vel)) (vz0 (vz vel)))
    (move-axis player 0 dx)
    (move-axis player 2 dz)
    ;; MOVE-AXIS zeroes the velocity component it was blocked on.
    (when (and can-step (or (/= (vx vel) vx0) (/= (vz vel) vz0)))
      (let ((px (vx feet)) (pz (vz feet)) (pvx (vx vel)) (pvz (vz vel))
            (plain (horizontal-distance-squared feet x0 z0)))
        (setf (vx feet) x0 (vy feet) y0 (vz feet) z0 (vx vel) vx0 (vy vel) vy0 (vz vel) vz0)
        (move-axis player 1 (float *step-height* 0f0))
        (move-axis player 0 dx)
        (move-axis player 2 dz)
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

(define-handler (player tick) (dt)
  (when (frozen-p)
    (return))
  (setf (mana player) (min *max-mana* (+ (mana player) (* *mana-regen* dt)))
        (cast-timer player) (max 0.0 (- (cast-timer player) dt)))
  (let* ((dt (min dt 0.05))
         (vel (velocity player))
         (yaw (vy (rotation player)))
         (crouching (or (retained :left-control) (retained :c)))
         (ix (- (if (retained :d) 1.0 0.0) (if (retained :a) 1.0 0.0)))
         (iz (- (if (retained :w) 1.0 0.0) (if (retained :s) 1.0 0.0)))
         (wx (+ (* iz (sin yaw)) (* ix (cos yaw))))
         (wz (+ (* iz (- (cos yaw))) (* ix (sin yaw))))
         (wlen (sqrt (+ (* wx wx) (* wz wz))))
         (speed (cond (crouching *crouch-speed*)
                      ((retained :left-shift) *run-speed*)
                      (T *walk-speed*))))
    (when (< 1.0 wlen)
      (setf wx (/ wx wlen) wz (/ wz wlen)))
    ;; Accelerate horizontal velocity toward the wished velocity.
    (let* ((dvx (- (* wx speed) (vx vel)))
           (dvz (- (* wz speed) (vz vel)))
           (dlen (sqrt (+ (* dvx dvx) (* dvz dvz))))
           (max-dv (* *ground-acceleration* (if (grounded player) 1.0 *air-control*) dt)))
      (when (< max-dv dlen)
        (setf dvx (* dvx (/ max-dv dlen)) dvz (* dvz (/ max-dv dlen))))
      (incf (vx vel) dvx)
      (incf (vz vel) dvz))
    (when (and (grounded player) (retained :space) (not crouching))
      (setf (vy vel) (float *jump-speed* 0f0)))
    (decf (vy vel) (* *gravity* dt))
    ;; Steps only while walking: not mid-air, and not on the frame a jump starts.
    (let ((walking (and (grounded player) (<= (vy vel) 0))))
      (setf (grounded player) NIL)
      (move-horizontal player (* (vx vel) dt) (* (vz vel) dt) walking)
      (move-axis player 1 (* (vy vel) dt))
      (when (and walking (not (grounded player)))
        (snap-to-ground player)))
    (when (< (vy (feet player)) *kill-height*)
      (respawn player))
    ;; Ease the eye toward standing or crouching height, then place the camera.
    (let ((target (if crouching *crouch-eye-height* *eye-height*)))
      (setf (eye player) (+ (eye player) (* (- target (eye player)) (min 1.0 (* *eye-height-speed* dt))))))
    (let ((loc (location player))
          (feet (feet player)))
      (setf (vx loc) (vx feet)
            (vy loc) (+ (vy feet) (float (eye player) 0f0))
            (vz loc) (vz feet)))))

(defun respawn (player)
  (let ((feet (feet player)))
    (setf (vx feet) (vx *spawn-point*) (vy feet) (vy *spawn-point*) (vz feet) (vz *spawn-point*)))
  (setf (vx (velocity player)) 0f0 (vy (velocity player)) 0f0 (vz (velocity player)) 0f0))
