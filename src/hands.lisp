(in-package #:hexmaw)

;;; The player's hands, Hexen-style: the casting gauntlets low at the bottom of the screen,
;;; fire in their palms. One strip (data/sprites/hands/hands, tools/make_shield.py from
;;; art/hands/hands-frames.txt) holds 3 idle frames followed by an 8-frame cast, each frame a
;;; whole-screen picture of both hands, drawn at the weapons' art pixel size (SWORD-SCALE) and
;;; placed by its aim, the picture's middle, on the screen's. Each hand is its own entity drawing
;;; its half of the picture, pushed out from the middle for a wider stance; they close up for the
;;; frames where the fire joins between them. The cast is timed so its release frame shows when
;;; the player's spell leaves (*CAST-RELEASE*). Walking sways them. Their fire takes the look of
;;; the spell in them (*HAND-LOOKS*).

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
(defparameter *hands-aim* 154
  "Art pixels from the hands strip's screen corner to its aim, which goes on the screen's middle:
the pictures' middle, (1536 - 768) * 0.2 (art/hands/hands-frames.txt).")
(defparameter *hands-idle-sequence* '(0 1 2) "Strip frames the idle loop steps through.")
(defparameter *hands-spread* 28 "Art pixels each hand sits out from where its picture draws it.")
(defparameter *hands-together* '(4 5 6 7)
  "Strip frames where the fire joins between the hands (the gather, the fireball held, the
release), so the spread closes: split, the fire would tear in two.")
(defparameter *hands-spread-ease* 30.0 "How fast the hands open again after meeting.")
(defparameter *hands-cast-first* 3 "Strip index of the cast's first frame.")
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
  "Closed on the frames where the hands meet, closing across the frame before them (the cast's
first), apart otherwise."
  (cond ((member frame *hands-together*) 0.0)
        ((and position (member (1+ frame) *hands-together*))
         (- 1.0 (- position (ffloor position))))
        (T 1.0)))

(defun hands-split (atlas)
  "Art pixels from the cell's left edge to the pictures' middle, where the two hands part."
  (- (getf atlas :cell-width) (getf atlas :overhang *sword-overhang*) *hands-aim*))

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
  "Put this hand's half of the picture beside the screen's middle, the strip's aim on it at the
weapons' art pixel size, apart by the spread, sunk below the bottom edge as the sword is, lowered
while switching weapons and offset by the sway. The sway only ever dips, so the arms' cut-off
ends stay below the screen."
  (multiple-value-bind (sx sy) (sword-scale)
    (let* ((atlas (animation-atlas (sprite-animation hands)))
           (context (context +main+))
           (split (hands-split atlas))
           (left-p (eq (side hands) :left))
           (w (* sx (if left-p split (- (getf atlas :cell-width) split))))
           (h (* sy (getf atlas :cell-height)))
           (middle (round (width context) 2))
           (out (round (* *hands-spread* (spread hands) sx)))
           (bob (* *hands-bob* (bob-amount hands)))
           (phase (bob-phase hands)))
      (setf (vx (scaling hands)) (float w 0f0)
            (vy (scaling hands)) (float h 0f0))
      (place hands
             (+ (if left-p (- middle w out) (+ middle out)) (round (* bob sx (cos phase))))
             (- (+ (* *sword-drop* sy)
                   (round (* bob sy (abs (sin phase))))
                   (round (* h (weapon-drop *player*)))))
             *weapon-depth*))))

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
         (part (/ (float (hands-split atlas)) (getf atlas :cell-width)))
         (target (spread-target frame position)))
    (strip-uv uv atlas frame (getf atlas :frames))
    ;; Each hand draws its side of the cell.
    (if (eq (side hands) :left)
        (setf (vz uv) (* part (vz uv)))
        (setf (vx uv) (+ (vx uv) (* part (vz uv)))
              (vz uv) (* (- 1.0 part) (vz uv))))
    ;; Closing follows the cast's clock, so the hands are shut exactly when they meet; a frame
    ;; lasts too short for easing to get there. Opening eases.
    (if (< target (spread hands))
        (setf (spread hands) target)
        (incf (spread hands) (* (- target (spread hands)) (min 1.0 (* *hands-spread-ease* dt))))))
  (layout-hands hands))
