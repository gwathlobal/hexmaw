(in-package #:hexmaw)

;;; Creatures: billboard monsters that can be hurt. A hit flashes the sprite,
;;; squashes it in a flinch (stagger), slides it back along the blow (knockback)
;;; and freezes the action for a moment (hit-stop). At zero health it plays its
;;; death animation and stays down as a corpse (or, without one, collapses into the
;;; floor); for now it then revives at its spawn point, so there is always
;;; something to shoot at.

(defparameter *hit-stop-time* 0.06 "Seconds the world freezes when a hit lands.")
(defparameter *flash-time* 0.15)
(defparameter *flash-color* (vec4 1.0 0.95 0.8 0.85) "RGB and peak strength of the hit flash.")
(defparameter *stagger-time* 0.35)
(defparameter *stagger-squash* 0.12 "How much a flinch squashes the sprite, as a fraction of its height.")
(defparameter *knockback-friction* 14.0 "Deceleration of knockback, in m/s².")
(defparameter *death-time* 0.5 "Seconds a creature without a death animation takes to collapse.")
(defparameter *revive-time* 3.0 "Seconds a corpse lies still before it comes back; NIL to stay dead.")

(defvar *hit-stop* 0.0 "Seconds of hit-stop left. While positive, nothing in the world moves.")
(defvar *creatures* (make-array 0 :adjustable T :fill-pointer T)
  "Creatures in the level, for hit tests. The level rebuilds it.")

(defvar *game-state* :title
  "What the game is doing: :TITLE (main menu), :PLAYING or :PAUSED. Menus (menu.lisp)
change it; anything but :PLAYING freezes the world.")

(defun frozen-p ()
  (or (< 0.0 *hit-stop*)
      (not (eq *game-state* :playing))))

(defun hit-stop (&optional (time *hit-stop-time*))
  (setf *hit-stop* (max *hit-stop* (float time 0f0))))

(define-shader-entity creature (billboard)
  ((max-health :initarg :max-health :initform 30 :accessor max-health)
   (health :accessor health)
   (body-radius :initarg :body-radius :initform 0.35 :accessor body-radius
                :documentation "Half-width of the hit and collision box, in metres.")
   (knockback :initform (vec 0 0 0) :reader knockback)
   (stagger :initform 0.0 :accessor stagger)
   (flash :initform 0.0 :accessor flash)
   (dead :initform NIL :accessor dead :documentation "Seconds since death, or NIL while alive.")
   (death-animation :initarg :death-animation :initform NIL :accessor death-animation
                    :documentation "Frame animation played once on death, its last frame the
corpse; NIL to collapse into the floor instead.")
   (body-texture :reader body-texture :documentation "The atlas texture, put back on revival.")
   (home :reader home)
   (base-scaling :reader base-scaling)))

(defmethod initialize-instance :after ((creature creature) &key)
  (setf (health creature) (max-health creature))
  (setf (slot-value creature 'home) (vcopy (location creature)))
  (setf (slot-value creature 'body-texture) (texture creature))
  (setf (slot-value creature 'base-scaling) (vcopy (scaling creature))))

;; Only the current texture gets loaded with the scene; the death strip has to be too.
(defmethod stage :after ((creature creature) (area staging-area))
  (when (death-animation creature)
    (stage (animation-texture (find-fx-animation (death-animation creature))) area)))

(defun death-duration (creature)
  "Seconds from death until the corpse lies still."
  (let ((name (death-animation creature)))
    (if name
        (let ((animation (find-fx-animation name)))
          (/ (getf (animation-atlas animation) :frames) (animation-fps animation)))
        *death-time*)))

(defun spawn-creature (creature container)
  (vector-push-extend creature *creatures*)
  (enter creature container))

(defun creature-at (point margin)
  "The first live creature whose body contains POINT, grown by MARGIN metres, or NIL."
  (loop for c across *creatures*
        for loc = (location c)
        for r = (+ (body-radius c) margin)
        when (and (not (dead c))
                  (< (+ (expt (- (vx point) (vx loc)) 2) (expt (- (vz point) (vz loc)) 2)) (* r r))
                  (< (- (vy loc) margin) (vy point) (+ (vy loc) (sprite-height c) margin)))
          return c))

(defun hurt (creature amount)
  "Take AMOUNT health from CREATURE with the full hit reaction."
  (unless (dead creature)
    (decf (health creature) amount)
    (setf (flash creature) *flash-time*
          (stagger creature) *stagger-time*)
    (hit-stop)
    (when (<= (health creature) 0)
      (setf (dead creature) 0.0))))

(defun push-creature (creature direction speed)
  "Knock CREATURE along DIRECTION (only its horizontal part counts) at SPEED m/s."
  (let ((len (sqrt (+ (expt (vx direction) 2) (expt (vz direction) 2))))
        (kb (knockback creature)))
    (when (< 1f-4 len)
      (setf (vx kb) (* speed (/ (vx direction) len))
            (vz kb) (* speed (/ (vz direction) len))))))

(defun slide (creature dt)
  "Apply knockback for DT seconds, stopping at solids, then slow it by friction."
  (let ((kb (knockback creature))
        (loc (location creature))
        (r (float (body-radius creature) 0f0))
        (h (float (sprite-height creature) 0f0)))
    (flet ((blocked () (solid-overlapping (vx loc) (+ (vy loc) 0.05) (vz loc) r (- h 0.05))))
      (let ((old (vx loc)))
        (incf (vx loc) (* (vx kb) dt))
        (when (blocked) (setf (vx loc) old (vx kb) 0.0)))
      (let ((old (vz loc)))
        (incf (vz loc) (* (vz kb) dt))
        (when (blocked) (setf (vz loc) old (vz kb) 0.0))))
    (let* ((speed (sqrt (+ (expt (vx kb) 2) (expt (vz kb) 2))))
           (slower (max 0.0 (- speed (* *knockback-friction* dt)))))
      (if (< speed 1f-4)
          (setf (vx kb) 0.0 (vz kb) 0.0)
          (setf (vx kb) (* (vx kb) (/ slower speed)) (vz kb) (* (vz kb) (/ slower speed)))))))

(defun revive (creature)
  (setf (dead creature) NIL
        (health creature) (max-health creature)
        (stagger creature) 0.0
        (flash creature) 0.0
        (texture creature) (body-texture creature))
  (v<- (location creature) (home creature))
  (let ((kb (knockback creature)))
    (setf (vx kb) 0.0 (vz kb) 0.0)))

(defun update-creature-look (creature)
  "Set tint and scaling from flash, stagger and death."
  (let ((tint (tint creature))
        (base (base-scaling creature))
        (scale (scaling creature))
        (f (/ (flash creature) *flash-time*))
        (s (/ (stagger creature) *stagger-time*)))
    (setf (vx tint) (vx *flash-color*) (vy tint) (vy *flash-color*) (vz tint) (vz *flash-color*)
          (vw tint) (* f (vw *flash-color*)))
    (setf (vx scale) (* (vx base) (+ 1 (* s *stagger-squash* 0.7)))
          (vy scale) (* (vy base) (- 1 (* s *stagger-squash*)))
          (vz scale) (vz base))
    (let ((d (dead creature)))
      (cond ((null d))
            ((death-animation creature)
             ;; Play the death strip once, then hold its last frame. It replaces
             ;; the flinch, so it isn't squashed.
             (let* ((animation (find-fx-animation (death-animation creature)))
                    (atlas (animation-atlas animation))
                    (count (getf atlas :frames))
                    (h (animation-size animation)))
               (setf (texture creature) (animation-texture animation))
               (strip-uv (frame-uv creature) atlas (min (1- count) (floor (* d (animation-fps animation)))) count)
               (setf (vx scale) (* h (/ (getf atlas :cell-width) (getf atlas :cell-height)))
                     (vy scale) h)))
            (T
             ;; Collapse into the floor, darkening, then stay flat until revived.
             (let ((k (max 0.02 (- 1 (/ d *death-time*)))))
               (setf (vy scale) (* (vy base) k)
                     (vx tint) 0.1 (vy tint) 0.0 (vz tint) 0.0 (vw tint) (- 1 k))))))))

;; :AFTER so BILLBOARD's tick handler (view selection) still runs.
(define-handler (creature tick :after) (dt)
  (unless (frozen-p)
    (let ((dt (min dt 0.05)))
      (setf (flash creature) (max 0.0 (- (flash creature) dt))
            (stagger creature) (max 0.0 (- (stagger creature) dt)))
      (slide creature dt)
      (when (dead creature)
        (incf (dead creature) dt)
        (when (and *revive-time* (< (+ (death-duration creature) *revive-time*) (dead creature)))
          (revive creature)))))
  (update-creature-look creature))

;;; The imp.

(defparameter *imp-height* 1.5
  "Imp height in metres, horns to feet. The player's eye is at 1.6.")

;; Sliced so the standing imp in its first frame is as tall as a turnaround cell.
(define-fx-animation imp-death "sprites/imp/death" :fps 10 :size *imp-height*)

(define-shader-entity imp (creature)
  ((texture :initform (// 'hexmaw 'imp-turnaround))
   (atlas :initform (read-atlas "data/sprites/imp/turnaround.lisp"))
   (sprite-height :initform *imp-height*)
   (death-animation :initform 'imp-death)
   (max-health :initform 30)))
