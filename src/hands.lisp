(in-package #:hexmaw)

;;; The player's hands, Hexen-style: sprites low on the bottom edge of the screen,
;;; mostly fingers and palms. One strip (data/sprites/hands, from "Fire Hands
;;; Sheet.png") holds 4 idle frames followed by an 8-frame cast. The cast is timed so
;;; its release frame shows when the player's spell leaves (*CAST-RELEASE*).
;;;
;;; The art has both hands close together, so each hand is its own entity drawing
;;; one half of the frame, pushed out from the centre for a wider stance. They close
;;; up for the frames where they meet around the fireball. Walking sways them. Their fire
;;; takes the look of the spell in them (*HAND-LOOKS*).

(define-fx-animation fire-hands "sprites/hands/hands" :fps 6 :loop T)
;; The same with the fire recoloured (tools/recolor_strip.py), one for each look.
(define-fx-animation storm-hands "sprites/hands/storm" :fps 6 :loop T)
(define-fx-animation frost-hands "sprites/hands/frost" :fps 6 :loop T)
(define-fx-animation shock-hands "sprites/hands/shock" :fps 6 :loop T)
(define-fx-animation drain-hands "sprites/hands/drain" :fps 6 :loop T)
(define-fx-animation heal-hands "sprites/hands/heal" :fps 6 :loop T)
(define-fx-animation arcane-hands "sprites/hands/arcane" :fps 6 :loop T)

(defparameter *hand-looks*
  '(:fire fire-hands :storm storm-hands :frost frost-hands :shock shock-hands :drain drain-hands
    :heal heal-hands :arcane arcane-hands)
  "The hands' strip for a spell of each look (SPELL-LOOK, spells.lisp).")

(defparameter *weapon-depth* -1.0
  "HUD depth of the hands, the sword, the shield and the spear: behind the bars, the hotbar, the
inventory and its tooltip, and the pain flash, which they reach into.")
(defparameter *hands-height* 0.62
  "Vertical art scale: the strip's cell height times the scale is about this fraction
of the window height. Snaps to whole screen pixels per art pixel.")
(defparameter *hands-stretch* 1.25
  "Width over height of an art pixel on screen. The horizontal scale is a whole number
too, so every art pixel stays a uniform block.")
(defparameter *hands-drop* 28
  "Art pixels the hands sit below the bottom edge; Hexen shows little more than fingers.")
(defparameter *hands-spread* 18"Art pixels each hand sits out from the centre.")
(defparameter *hands-together* '(7 8)
  "Strip frames where the hands meet around the fireball, so the spread closes.")
(defparameter *hands-spread-ease* 30.0 "How fast the hands open again after meeting.")
(defparameter *hands-idle-sequence* '(4 11 10 11)
  "Strip frames the idle loop steps through. Most of the generated idle row lacks palm
fire, so for now it borrows the cast's rest poses (its first and last two frames).")
(defparameter *hands-cast-first* 4 "Strip index of the cast's first frame.")
(defparameter *hands-cast-frames* 8)
(defparameter *hands-release-frame* 4 "Cast frame the spell leaves on, counted from 0.")
(defparameter *hands-bob* 3.0 "Sway at walking speed, in art pixels.")
(defparameter *hands-bob-rate* 0.2
  "Sway cycles per metre walked: 0.8 a second walking, 1.4 running. Each cycle dips twice.")
(defparameter *hands-bob-ease* 8.0 "How fast the sway fades in and out.")

;; FX-SPRITE gives the strip, frame UVs and alpha cut-out; HUD-ELEMENT draws it in
;; pixel space. This tick replaces FX-SPRITE's, which would face it into the world.
(define-shader-entity hands (hud-element fx-sprite)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (animation :initform (find-fx-animation 'fire-hands))
   (side :initarg :side :initform :left :reader side :documentation ":left or :right half.")
   (spread :initform 1.0 :accessor spread :documentation "0 together, 1 fully apart.")
   (bob-phase :initform 0.0 :accessor bob-phase)
   (bob-amount :initform 0.0 :accessor bob-amount)))

(defun add-hands (container)
  (enter (make-instance 'hands :side :left) container)
  (enter (make-instance 'hands :side :right) container)
  ;; Their other looks are swapped in mid-game (SWAP-ANIMATION): load them now.
  (loop for (nil name) on *hand-looks* by #'cddr
        do (preload (make-instance 'hands :animation (find-fx-animation name)) container)))

(defun cast-position ()
  "How far the cast animation has run, in frames from its first, or NIL when none plays."
  (let ((cast-time (and *player* (cast-time *player*))))
    (when cast-time
      (let ((position (/ (* cast-time *hands-release-frame*) *cast-release*)))
        (when (< position *hands-cast-frames*)
          position)))))

(defun hands-frame (hands position)
  "Strip index to show: the cast while one plays (POSITION), the idle loop otherwise."
  (if position
      (+ *hands-cast-first* (floor position))
      (nth (mod (floor (* (age hands) (animation-fps (sprite-animation hands))))
                (length *hands-idle-sequence*))
           *hands-idle-sequence*)))

(defun spread-target (frame position)
  "Closed on the frames where the hands meet, closing across the frame before them
(the gather), apart otherwise."
  (cond ((member frame *hands-together*) 0.0)
        ((and position (member (1+ frame) *hands-together*))
         (- 1.0 (- position (ffloor position))))
        (T 1.0)))

(defun update-bob (weapon dt)
  "Advance WEAPON's sway (the hands or the sword) with the distance walked; it fades
out when standing or airborne."
  (let* ((vel (velocity *player*))
         (speed (sqrt (+ (* (vx vel) (vx vel)) (* (vz vel) (vz vel)))))
         (target (if (grounded *player*) (min 1.0 (/ speed *walk-speed*)) 0.0)))
    (incf (bob-amount weapon) (* (- target (bob-amount weapon)) (min 1.0 (* *hands-bob-ease* dt))))
    (setf (bob-phase weapon) (mod (+ (bob-phase weapon) (* speed dt *hands-bob-rate* #.(float (* 2 pi) 0f0)))
                                  #.(float (* 2 pi) 0f0)))))

(defmethod render :around ((hands hands) (program shader-program))
  (when (and *player* (eq (weapon *player*) :hands))
    (call-next-method)))

(defun layout-hands (hands)
  "Put this hand's half of the frame beside the screen's centre line, apart by the
spread, sunk below the bottom edge, lowered while switching weapons and offset by the
sway. The sway only ever dips, so the arms' cut-off ends stay below the screen."
  (let* ((atlas (animation-atlas (sprite-animation hands)))
         (cell-w (getf atlas :cell-width))
         (cell-h (getf atlas :cell-height))
         (context (context +main+))
         (sy (max 1 (round (* *hands-height* (height context)) cell-h)))
         (sx (max 1 (round (* sy *hands-stretch*))))
         (half-w (round (* sx cell-w 0.5)))
         (out (round (* *hands-spread* (spread hands) sx)))
         (centre (floor (width context) 2))
         (bob (* *hands-bob* (bob-amount hands)))
         (phase (bob-phase hands)))
    (setf (vx (scaling hands)) (float half-w 0f0)
          (vy (scaling hands)) (float (* sy cell-h) 0f0))
    (place hands
           (+ (if (eq (side hands) :left) (- centre half-w out) (+ centre out))
              (round (* bob sx (cos phase))))
           (- (+ (* *hands-drop* sy)
                 (round (* bob sy (abs (sin phase))))
                 (round (* sy cell-h (weapon-drop *player*)))))
           *weapon-depth*)))

(define-handler (hands tick) (dt)
  (unless (frozen-p)
    (incf (age hands) dt)
    (when *player*
      (update-bob hands dt)))
  (let ((spell (and *player* (held-spell *player*))))
    (when spell
      (swap-animation hands (find-fx-animation (getf *hand-looks* (spell-look spell) 'fire-hands)))))
  (let* ((atlas (animation-atlas (sprite-animation hands)))
         (position (cast-position))
         (frame (hands-frame hands position))
         (uv (frame-uv hands))
         (target (spread-target frame position)))
    (strip-uv uv atlas frame (getf atlas :frames))
    ;; Each hand draws its half of the cell.
    (setf (vz uv) (* 0.5 (vz uv)))
    (when (eq (side hands) :right)
      (incf (vx uv) (vz uv)))
    ;; Closing follows the cast's clock, so the hands are shut exactly when they
    ;; meet; a frame lasts too short for easing to get there. Opening eases.
    (if (< target (spread hands))
        (setf (spread hands) target)
        (incf (spread hands) (* (- target (spread hands)) (min 1.0 (* *hands-spread-ease* dt))))))
  (layout-hands hands))
