(in-package #:hexmaw)

;;; The sword, and switching between weapons. The player holds one weapon at a time
;;; (*WEAPONS*): the casting hands or the sword. Switching lowers the current one off
;;; the bottom of the screen and raises the next, Hexen-style.
;;;
;;; The sword is one HUD sprite against the bottom-right corner. Its strip
;;; (data/sprites/sword, from "Sword Sheet.png") holds a 4-frame idle loop (a glint
;;; running up the blade) followed by an 8-frame slash: rest, wind-up, the cut with
;;; its swoosh arc, recovery. It sways while walking. The hit lands at the start of
;;; *SWING-HIT-FRAME*: the nearest creature inside the swing's reach and arc takes
;;; the blow.

(define-fx-animation sword "sprites/sword/sword" :fps 5 :loop T)

(defparameter *sword-idle-frames* 4 "Strip frames the idle loop steps through, from the first.")
(defparameter *sword-swing-first* 4 "Strip index of the slash's first frame.")

(defparameter *weapons* '(:1 :sword :2 :hands) "Key to press for each weapon.")
(defparameter *weapon-switch-time* 0.15 "Seconds to lower a weapon, and again to raise the next.")

(defparameter *swing-frame-times* '(0.05 0.07 0.07 0.04 0.06 0.07 0.08 0.08)
  "Seconds each frame of the slash shows. The swing is over after the last.")(defparameter *swing-hit-frame* 4 "Slash frame the blow lands on, counted from 0: the blade at full sweep.")
(defparameter *sword-reach* 2.0 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *sword-arc* 0.8 "Radians either side of the view the blade sweeps through.")
(defparameter *sword-damage* '(10 16))
(defparameter *sword-knockback* 3.0 "Speed in m/s a hit slides the creature away.")

(defparameter *sword-height* 0.6
  "Vertical art scale: the strip's cell height times the scale is about this fraction
of the window height. Snaps to whole screen pixels per art pixel.")
(defparameter *sword-stretch* 1.25 "Width over height of an art pixel on screen, as for the hands.")
(defparameter *sword-drop* 6 "Art pixels the sword sits below the bottom edge.")
(defparameter *sword-overhang* 6
  "Art pixels the strip reaches past the right edge. The arm runs off that edge in the
cut, so this must be more than the sway, or the cut-off end shows.")
(defparameter *sword-bob* 3.0 "Sway at walking speed, in art pixels.")

;;; Weapon state lives on the player: WEAPON is the one on screen, WANTED-WEAPON the
;;; one asked for, WEAPON-LOWER how far it is lowered (0 up, 1 off screen).

(defun attacking-p (player)
  (or (swing-time player) (pending-spell player) (cast-position)))

(defun weapon-ready-p (player)
  (and (eq (weapon player) (wanted-weapon player))
       (= 0.0 (weapon-lower player))))

(defun select-weapon (player key)
  "Switch to the weapon on KEY, if any. Returns true if KEY names one."
  (let ((weapon (getf *weapons* key)))
    (when weapon
      (setf (wanted-weapon player) weapon)
      T)))

(defun weapon-drop (player)
  "Fraction of its height the weapon on screen is lowered, eased."
  (let ((k (weapon-lower player)))
    (* k k)))

(defun player-attack (player)
  "Attack with the weapon in hand: cast the bolt, or swing the sword."
  (when (weapon-ready-p player)
    (ecase (weapon player)
      (:hands (player-cast player 'bolt))
      (:sword (player-swing player)))))

(defun player-swing (player)
  (unless (swing-time player)
    (setf (swing-time player) 0.0
          (swing-pending player) T)))

(defun swing-frame (time)
  "Frame of the slash at TIME seconds into it, or NIL once it is over."
  (loop for frame from 0
        for duration in *swing-frame-times*
        sum duration into end
        when (< time end) return frame))

(defun swing-hit-time ()
  (reduce #'+ (subseq *swing-frame-times* 0 *swing-hit-frame*)))

(defun clear-path-p (from to height)
  "True if nothing solid stands between FROM and TO, HEIGHT metres above FROM."
  (let* ((dx (- (vx to) (vx from)))
         (dz (- (vz to) (vz from)))
         (steps (ceiling (sqrt (+ (* dx dx) (* dz dz))) 0.1))
         (y (+ (vy from) height)))
    (loop for i from 1 below steps
          for k = (/ i steps)
          never (solid-overlapping (+ (vx from) (* k dx)) y (+ (vz from) (* k dz)) 0.02 0.02))))

(defun swing-target (player)
  "The nearest live creature the swing reaches: its body within *SWORD-REACH*, inside
the arc around where the player faces, level with the player, and not behind a wall."
  (let* ((feet (feet player))
         (yaw (vy (rotation player)))
         (fx (sin yaw))
         (fz (- (cos yaw)))
         (best NIL)
         (best-distance 0.0))
    (loop for c across *creatures*
          for loc = (location c)
          for dx = (- (vx loc) (vx feet))
          for dz = (- (vz loc) (vz feet))
          for distance = (sqrt (+ (* dx dx) (* dz dz)))
          for r = (body-radius c)
          when (and (not (dead c))
                    (< distance (+ *sword-reach* r))
                    (< (vy loc) (+ (vy feet) *player-height*))
                    (< (vy feet) (+ (vy loc) (sprite-height c)))
                    (or (< distance r)
                        ;; The body's own width widens the arc it can be hit in.
                        (< (acos (max -1.0 (min 1.0 (/ (+ (* dx fx) (* dz fz)) distance))))
                           (+ *sword-arc* (atan r distance))))
                    (clear-path-p feet loc 1.0)
                    (or (null best) (< distance best-distance)))
            do (setf best c best-distance distance))
    best))

(defun swing-hit (player)
  (let ((target (swing-target player)))
    (when target
      (hurt target (roll *sword-damage*))
      (push-creature target (v- (location target) (feet player)) (float *sword-knockback* 0f0)))))

(defun update-weapons (player dt)
  "Run the swing and the weapon switch. Called from the player's tick while not frozen."
  (when (swing-time player)
    (incf (swing-time player) dt)
    (when (and (swing-pending player) (<= (swing-hit-time) (swing-time player)))
      (setf (swing-pending player) NIL)
      (swing-hit player))
    (unless (swing-frame (swing-time player))
      (setf (swing-time player) NIL)))
  (let ((step (/ dt *weapon-switch-time*)))
    (cond ((eq (weapon player) (wanted-weapon player))
           (setf (weapon-lower player) (max 0.0 (- (weapon-lower player) step))))
          ((attacking-p player))
          ((< (weapon-lower player) 1.0)
           (setf (weapon-lower player) (min 1.0 (+ (weapon-lower player) step))))
          (T
           (setf (weapon player) (wanted-weapon player))))))

;;; The sword on screen.

(define-shader-entity sword (hud-element fx-sprite)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (animation :initform (find-fx-animation 'sword))
   (bob-phase :initform 0.0 :accessor bob-phase)
   (bob-amount :initform 0.0 :accessor bob-amount)))

(defun add-sword (container)
  (enter (make-instance 'sword) container))

(defmethod render :around ((sword sword) (program shader-program))
  (when (and *player* (eq (weapon *player*) :sword))
    (call-next-method)))

(defun layout-sword (sword)
  "Put the strip's right edge past the screen's, sunk below the bottom edge, lowered
while switching, and offset by the sway. As with the hands, the sway only ever dips."
  (let* ((atlas (animation-atlas (sprite-animation sword)))
         (cell-w (getf atlas :cell-width))
         (cell-h (getf atlas :cell-height))
         (context (context +main+))
         (sy (max 1 (round (* *sword-height* (height context)) cell-h)))
         (sx (max 1 (round (* sy *sword-stretch*))))
         (w (* sx cell-w))
         (h (* sy cell-h))
         (bob (* *sword-bob* (bob-amount sword)))
         (phase (bob-phase sword)))
    (setf (vx (scaling sword)) (float w 0f0)
          (vy (scaling sword)) (float h 0f0))
    (place sword
           (+ (- (width context) w) (* *sword-overhang* sx) (round (* bob sx (cos phase))))
           (- (+ (* *sword-drop* sy)
                 (round (* bob sy (abs (sin phase))))
                 (round (* h (weapon-drop *player*))))))))

;; Replaces FX-SPRITE's tick, which would face it into the world.
(define-handler (sword tick) (dt)
  (when *player*
    (unless (frozen-p)
      (incf (age sword) dt)
      (update-bob sword dt))
    (let* ((animation (sprite-animation sword))
           (atlas (animation-atlas animation))
           (time (swing-time *player*))
           (swing (and time (swing-frame time))))
      (strip-uv (frame-uv sword) atlas
                (if swing
                    (+ *sword-swing-first* swing)
                    (mod (floor (* (age sword) (animation-fps animation))) *sword-idle-frames*))
                (getf atlas :frames)))
    (layout-sword sword)))
