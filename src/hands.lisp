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

;;; As a weapon (weapons.lisp): what switching to them plays. Their frames follow the spell in them
;;; (below), not a template's.
(define-weapon :hands
  :title "Hands" :sounds (:draw :draw-magic))
;; The same with the fire recoloured (tools/recolor_strip.py), one for each look.
(define-fx-animation storm-hands "sprites/hands/storm" :fps 6 :loop T)
(define-fx-animation frost-hands "sprites/hands/frost" :fps 6 :loop T)
(define-fx-animation shock-hands "sprites/hands/shock" :fps 6 :loop T)
(define-fx-animation drain-hands "sprites/hands/drain" :fps 6 :loop T)
(define-fx-animation arcane-hands "sprites/hands/arcane" :fps 6 :loop T)

(defparameter *hand-looks*
  '(:fire fire-hands :storm storm-hands :frost frost-hands :shock shock-hands :drain drain-hands
    :arcane arcane-hands :heal fire-hands :ward fire-hands :absorb fire-hands)
  "The hands' strip for a spell of each look (SPELL-LOOK, spells.lisp). Healing, ward and Absorb
spells show their own magic, never fire (*HAND-MOTIFS*), so they take the strip as drawn.")

(defparameter *weapon-depth* -1.0
  "HUD depth of the hands, the sword, the shield and the spear: behind the bars, the hotbar, the
inventory and its tooltip, and the pain flash, which they reach into.")
(defparameter *hands-aim* 154
  "Art pixels from the hands strip's screen corner to its aim, which goes on the screen's middle:
the pictures' middle, (1536 - 768) * 0.2 (art/hands/hands-frames.txt).")
(defparameter *hand-motifs*
  '((:fire :idle (0 1 2) :cast 3 :cast-frames 8 :release 4)
    (:absorb :idle (11 12 13 14) :stance (15 16 17 18))
    (:heal :idle (19 20 21 22) :cast 23 :cast-frames 6 :release 2)
    (:ward :idle (29 30 31) :cast 32 :cast-frames 6 :release 2))
  "The hands' frames for each kind of spell in them (HAND-MOTIF), in the strip
(art/hands/hands-frames.txt): fire, the attack's flames; Absorb, a void in each palm and, held, a
void between the hands drinking in streaks of light; healing, ribbons of light round the forearms
that unwind and wrap them; ward, a gold hexagon over each palm that becomes a honeycomb pane. :IDLE
the loop at rest, :CAST the first of :CAST-FRAMES, :RELEASE the one the spell leaves or lands on,
counted from :CAST; :STANCE the loop while it is held.")
(defparameter *hands-idle-time* 0.2 "Seconds each idle frame of a motif other than fire shows: the ward's three
take turns bold, the void's specks orbit, light runs up the healing ribbons.")
(defparameter *hands-spread* 28 "Art pixels each hand sits out from where its picture draws it.")
(defparameter *hands-together* '(4 5 6 7 15 16 17 18 24 33 34)
  "Strip frames where the magic joins between the hands (the fire's gather, fireball held and
release; the Absorb void; the ward's honeycomb), so the spread closes: split, it would tear in two.")
(defparameter *hands-spread-ease* 30.0 "How fast the hands open again after meeting.")
(defparameter *hands-bob* 3.0 "Sway at walking speed, in art pixels.")
(defparameter *channel-hands-drop* 0.3
  "Fraction of their height the hands sink while holding a beam, together round its fire, so the
ray and what it strikes stay in sight above them.")
(defparameter *channel-hands-frames* '(5 6)
  "Strip frames the hands show while holding a beam, in turn: together, the fire between them.")
(defparameter *channel-hands-flicker* 0.1 "Seconds each of them shows.")
(defparameter *absorb-hands-flicker* 0.12 "Seconds each of the Absorb stance's frames shows.")
(defparameter *overcharge-hands-frames* '(5 6)
  "Strip frames the hands hold while overcharging a spell: the fireball held, and trembling between
the two at a full overcharge.")
(defparameter *overcharge-tremble-rate* 12.0 "Times a second a full overcharge trembles from one frame to the other.")
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
   (bob-amount :initform 0.0 :accessor bob-amount)
   (channel-ease :initform 0.0 :accessor channel-ease
                 :documentation "0 up, 1 lowered for a held beam, eased over the cast's wind-up.")))

(defun add-hands (container)
  (enter (make-instance 'hands :side :left) container)
  (enter (make-instance 'hands :side :right) container)
  ;; Their other looks are swapped in mid-game (SWAP-ANIMATION): load them now.
  (loop for (nil name) on *hand-looks* by #'cddr
        do (preload (make-instance 'hands :animation (find-fx-animation name)) container)))

(defun hand-motif (spell)
  "Which of *HAND-MOTIFS* the hands show for SPELL: :ABSORB, :HEAL or :WARD for a spell of those cast
on yourself (by its first effect), :FIRE for anything else or no spell."
  (let ((kind (and spell (eq (spell-delivery spell) :self) (spell-effects spell)
                   (effect-kind (first (spell-effects spell))))))
    (if (member kind '(:absorb :heal :ward)) kind :fire)))

(defun motif (spell key)
  (getf (rest (assoc (hand-motif spell) *hand-motifs*)) key))

(defun cast-position ()
  "How far the cast animation of the spell last cast has run, in frames from its first, or NIL when
none plays."
  (let ((cast-time (and *player* (cast-time *player*)))
        (spell (and *player* (last-cast *player*))))
    ;; A held spell (Absorb) has no cast to play.
    (when (and cast-time (motif spell :release))
      (let ((position (/ (* cast-time (motif spell :release)) *cast-release*)))
        (when (< position (motif spell :cast-frames))
          position)))))

(defun hand-idle-spell (hands)
  "The spell whose idle HANDS show: the left the slot's rune, the right its off hand's, or the left's."
  (when *player*
    (if (eq (side hands) :right)
        (or (offhand-spell *player*) (held-spell *player*))
        (held-spell *player*))))

(defun hand-look-spell (hands)
  "The spell whose look HANDS take: while a cast plays or a spell is held, that spell's, both hands
alike; else this hand's own (HAND-IDLE-SPELL)."
  (let ((player *player*))
    (when player
      (if (and (last-cast player) (or (channel player) (pending-spell player) (cast-position)))
          (last-cast player)
          (hand-idle-spell hands)))))

(defun hands-frame (hands position)
  "Strip index to show: a held beam's or Absorb's frames, an overcharge's, the cast of the spell last
cast while one plays (POSITION), else this hand's spell's idle loop."
  (flet ((loop-frames (frames time)
           (nth (mod (floor (age hands) time) (length frames)) frames)))
    (let ((channel (and *player* (channel *player*))))
      (cond ((and channel (absorb-spell-p channel))
             (loop-frames (motif channel :stance) *absorb-hands-flicker*))
            (channel
             (loop-frames *channel-hands-frames* *channel-hands-flicker*))
            ((and *player* (overcharging-p *player*))
             (if (<= 1.0 (overcharge *player*))
                 (loop-frames *overcharge-hands-frames* (/ 1.0 *overcharge-tremble-rate*))
                 (first *overcharge-hands-frames*)))
            (position
             (+ (motif (last-cast *player*) :cast) (floor position)))
            (T
             (let ((spell (hand-idle-spell hands)))
               (loop-frames (motif spell :idle)
                            (if (eq :fire (hand-motif spell))
                                (/ 1.0 (animation-fps (sprite-animation hands)))
                                *hands-idle-time*))))))))

(defun spread-target (frame position)
  "Closed on the frames where the hands meet, closing across the frame before them (the cast's
first), apart otherwise."
  (cond ((member frame *hands-together*) 0.0)
        ((and position (< frame (+ (motif NIL :cast) (motif NIL :cast-frames))) (member (1+ frame) *hands-together*))
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
           (lowered (channel-ease hands))
           (out (round (* *hands-spread* (spread hands) sx)))
           (bob (* *hands-bob* (bob-amount hands)))
           (phase (bob-phase hands)))
      (setf (vx (scaling hands)) (float w 0f0)
            (vy (scaling hands)) (float h 0f0))
      (place hands
             (+ (if left-p (- middle w out) (+ middle out)) (round (* bob sx (cos phase))))
             (- (+ (* *sword-drop* sy)
                   (round (* bob sy (abs (sin phase))))
                   (round (* h (weapon-drop *player*)))
                   (round (* h *channel-hands-drop* lowered (- 2.0 lowered)))))
             *weapon-depth*))))

(define-handler (hands tick) (dt)
  (unless (frozen-p)
    (incf (age hands) dt)
    (when *player*
      (update-bob hands dt)
      ;; A held beam takes the cast's wind-up to lower them, and as long to raise them again.
      (let ((step (/ dt *cast-release*)))
        (setf (channel-ease hands) (if (channelling-beam-p *player*)
                                       (min 1.0 (+ (channel-ease hands) step))
                                       (max 0.0 (- (channel-ease hands) step)))))))
  (let ((spell (hand-look-spell hands)))
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
