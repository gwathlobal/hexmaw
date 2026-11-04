(in-package #:hexmaw)

;;; The sword, and switching between weapons. The player holds one weapon at a time
;;; (*WEAPONS*): the sword, the casting hands or the spear (spear.lisp). Switching
;;; lowers the current one off the bottom of the screen and raises the next, Hexen-style.
;;;
;;; The sword's slash and the spear's thrust are both swings: SWING-TIME runs whichever
;;; is in hand, and the generics below (SWING-FRAME-TIMES, SWING-REACH and the rest)
;;; give each its timing and blow, by the weapon's keyword.
;;;
;;; The sword is one HUD sprite against the bottom-right corner. Its strip
;;; (data/sprites/sword, from "Sword Sheet.png") holds a 4-frame idle loop (a glint
;;; running up the blade) followed by an 8-frame slash: rest, wind-up, the cut with
;;; its swoosh arc, recovery. It sways while walking. The hit lands at the start of
;;; *SWING-HIT-FRAME*: the nearest creature inside the swing's reach and arc takes
;;; the blow.
;;;
;;; The left hand holds a shield, its own sprite against the bottom-left corner (below).
;;; Holding the right button raises it to block (SHIELD-BLOCKS-P, player.lisp); a click
;;; while it is up bashes with it: a shove and a little damage, landing on
;;; *BASH-HIT-FRAME*. It staggers only a creature winding up a blow, and each bash leaves
;;; the creature poised for a moment, so timing the interrupt matters and spamming the
;;; bash only shoves. Against the knight's shield it glances off.

(define-fx-animation sword "sprites/sword/sword" :fps 5 :loop T)

(defparameter *sword-idle-frames* 4 "Strip frames the idle loop steps through, from the first.")
(defparameter *sword-swing-first* 4 "Strip index of the slash's first frame.")

(defparameter *weapons* '(:1 :sword :2 :hands :3 :spear :4 :tempest) "Key to press for each weapon.")
(defparameter *weapon-switch-time* 0.15 "Seconds to lower a weapon, and again to raise the next.")

(defparameter *swing-frame-times* '(0.05 0.07 0.07 0.04 0.06 0.07 0.08 0.08)
  "Seconds each frame of the slash shows. The swing is over after the last.")
(defparameter *swing-hit-frame* 4 "Slash frame the blow lands on, counted from 0: the blade at full sweep.")
(defparameter *sword-reach* 2.0 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *sword-arc* 0.8 "Radians either side of the view the blade sweeps through.")
(defparameter *sword-damage* '(10 16))
(defparameter *sword-knockback* 3.0 "Speed in m/s a hit slides the creature away.")
(defparameter *sword-pain-bonus* 0 "Percent a hit adds to the creature's PAIN-CHANCE.")

(defparameter *block-raise-time* 0.12 "Seconds to raise the shield to block, and again to lower it.")
(defparameter *bash-frame-times* '(0.08 0.06 0.12 0.08)
  "Seconds each frame of the bash shows: pulled back, thrust, impact, coming back.")
(defparameter *bash-hit-frame* 1 "Bash frame the blow lands on, counted from 0: the thrust.")
(defparameter *bash-reach* 1.6 "Metres from the player to the nearest edge of a creature's body.")
(defparameter *bash-arc* 0.6 "Radians either side of the view the bash reaches.")
(defparameter *bash-damage* '(2 4))
(defparameter *bash-knockback* 6.0 "Speed in m/s a bash slides the creature away.")
(defparameter *bash-pain-bonus* 50
  "Percent a bash adds to the creature's PAIN-CHANCE when it lands in the wind-up of the
creature's attack (WINDING-UP-P): interrupting is what it is for. At any other time a
bash doesn't stagger.")
(defparameter *bash-poise-time* 1.5
  "Seconds after a bash lands in which another bash can't stagger the creature and barely
moves it.")
(defparameter *poised-bash-knockback* 0.25 "Fraction of *BASH-KNOCKBACK* a poised creature takes.")
(defparameter *bash-recoil* 4.0 "Speed in m/s a bash glancing off a shield throws the player back.")
(defparameter *bash-recoil-guard* 0.5 "Seconds a bash glancing off a shield leaves the player's shield down.")

(defparameter *sword-height* 1.04
  "Vertical art scale: the strip's cell height times the scale is about this fraction
of the window height. Snaps to whole screen pixels per art pixel. The strip is a
render framed to reach the screen's top edge (250 art pixels tall, 3 screen pixels
each at 720), so the swing is cut only by the screen.")
(defparameter *sword-stretch* 1.0
  "Width over height of an art pixel on screen. Square, unlike the hands, so the sword
keeps the proportions of its render and of the generator's restyle.")
(defparameter *sword-drop* 6 "Art pixels the sword sits below the bottom edge.")
(defparameter *sword-overhang* 6
  "Art pixels the strip reaches past the right edge. The arm runs off that edge in the
cut, so this must be more than the sway, or the cut-off end shows.")
(defparameter *sword-bob* 3.0 "Sway at walking speed, in art pixels.")
(defparameter *weapon-depth* -1.0
  "HUD depth of the sword and shield: behind the bars, the weapon slots and the pain
flash, which they reach into.")

(defgeneric swing-frame-times (weapon)
  (:documentation "Seconds each frame of WEAPON's swing shows. The swing is over after the last."))
(defgeneric swing-hit-frame (weapon)
  (:documentation "Swing frame WEAPON's blow lands on, counted from 0."))
(defgeneric swing-reach (weapon)
  (:documentation "Metres from the player to the nearest edge of a body WEAPON reaches."))
(defgeneric swing-arc (weapon)
  (:documentation "Radians either side of the view WEAPON's blow reaches."))
(defgeneric swing-damage (weapon))
(defgeneric swing-knockback (weapon)
  (:documentation "Speed in m/s WEAPON's blow slides a creature away."))
(defgeneric swing-pain-bonus (weapon)
  (:documentation "Percent WEAPON's blow adds to the creature's PAIN-CHANCE."))

(defmethod swing-frame-times ((weapon (eql :sword))) *swing-frame-times*)
(defmethod swing-hit-frame ((weapon (eql :sword))) *swing-hit-frame*)
(defmethod swing-reach ((weapon (eql :sword))) *sword-reach*)
(defmethod swing-arc ((weapon (eql :sword))) *sword-arc*)
(defmethod swing-damage ((weapon (eql :sword))) *sword-damage*)
(defmethod swing-knockback ((weapon (eql :sword))) *sword-knockback*)
(defmethod swing-pain-bonus ((weapon (eql :sword))) *sword-pain-bonus*)

;;; Weapon state lives on the player: WEAPON is the one on screen, WANTED-WEAPON the
;;; one asked for, WEAPON-LOWER how far it is lowered (0 up, 1 off screen).

(defun attacking-p (player)
  (or (swing-time player) (pending-spell player) (cast-position)
      (bash-time player) (< 0.0 (block-raise player))))

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
  "Attack with the weapon in hand: cast the bolt or the tornado, swing the sword, thrust the
spear, or, with the shield raised, bash with it. Nothing while the shield is on its way up
or down."
  (when (weapon-ready-p player)
    (ecase (weapon player)
      (:hands (let ((spell (current-spell player)))
                (when spell (player-cast player spell))))
      (:tempest (player-cast player 'tempest))
      (:sword (cond ((<= 1.0 (block-raise player)) (player-bash player))
                    ((= 0.0 (block-raise player)) (player-swing player))))
      (:spear (player-swing player)))))

(defparameter *weapon-sounds*
  '(:sword (:swing :sword-swing :draw :draw-sword)
    :spear (:swing :spear-thrust :draw :draw-spear)
    :hands (:draw :draw-magic)
    :tempest (:draw :draw-magic))
  "Each weapon's clips (sound.lisp): :SWING as a swing starts, :DRAW as it comes up.")

(defun weapon-sound (weapon event)
  (getf (getf *weapon-sounds* weapon) event))

(defun player-swing (player)
  (unless (swing-time player)
    (play-sound (weapon-sound (weapon player) :swing))
    (setf (swing-time player) 0.0
          (swing-pending player) T)))

(defun player-bash (player)
  (unless (bash-time player)
    (play-sound :shield-bash)
    (setf (bash-time player) 0.0
          (bash-pending player) T)))

(defun frame-at (time frame-times)
  "Frame of an animation timed by FRAME-TIMES at TIME seconds into it, or NIL once it
is over."
  (loop for frame from 0
        for duration in frame-times
        sum duration into end
        when (< time end) return frame))

(defun swing-frame (time weapon)
  "Frame of WEAPON's swing at TIME seconds into it, or NIL once it is over."
  (frame-at time (swing-frame-times weapon)))

(defun swing-hit-time (weapon)
  (reduce #'+ (subseq (swing-frame-times weapon) 0 (swing-hit-frame weapon))))

(defun bash-hit-time ()
  (reduce #'+ (subseq *bash-frame-times* 0 *bash-hit-frame*)))

(defun clear-path-p (from to height)
  "True if nothing solid stands between FROM and TO, HEIGHT metres above FROM."
  (let* ((dx (- (vx to) (vx from)))
         (dz (- (vz to) (vz from)))
         (steps (ceiling (sqrt (+ (* dx dx) (* dz dz))) 0.1))
         (y (+ (vy from) height)))
    (loop for i from 1 below steps
          for k = (/ i steps)
          never (solid-overlapping (+ (vx from) (* k dx)) y (+ (vz from) (* k dz)) 0.02 0.02))))

(defun swing-target (player &optional (reach *sword-reach*) (arc *sword-arc*))
  "The nearest live creature the swing reaches: its body within REACH, inside ARC
either side of where the player faces, level with the player, and not behind a wall."
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
                    (< distance (+ reach r))
                    (< (vy loc) (+ (vy feet) *player-height*))
                    (< (vy feet) (+ (vy loc) (sprite-height c)))
                    (or (< distance r)
                        ;; The body's own width widens the arc it can be hit in.
                        (< (acos (max -1.0 (min 1.0 (/ (+ (* dx fx) (* dz fz)) distance))))
                           (+ arc (atan r distance))))
                    (clear-path-p feet loc 1.0)
                    (or (null best) (< distance best-distance)))
            do (setf best c best-distance distance))
    best))

(defun swing-hit (player)
  (let* ((weapon (weapon player))
         (target (swing-target player (swing-reach weapon) (swing-arc weapon))))
    (when target
      (play-sound (if (bleeds target) :blade-hit-flesh :blade-hit-bone) (location target))
      (hurt target (roll (swing-damage weapon)) :from (feet player)
                                                :pain-bonus (swing-pain-bonus weapon))
      (push-creature target (v- (location target) (feet player))
                     (float (swing-knockback weapon) 0f0))
      (enchant-strike player weapon target))))

(defun bash-hit (player)
  "Bash the creature in front of PLAYER. Against a shield that covers it, the bash glances
off and the player reels back; otherwise it hurts and shoves, staggering only a creature
winding up an attack and not already poised from a bash."
  (let ((target (swing-target player *bash-reach* *bash-arc*)))
    (cond ((null target))
          ((shielded-p target (feet player))
           (play-sound :bash-glance (location target))
           (block-hit target)
           (shove-player player (location target) *bash-recoil*)
           (break-guard player *bash-recoil-guard*))
          (T
           (let* ((poised (< 0.0 (bash-poise target)))
                  (bonus (if (and (not poised) (winding-up-p target)) *bash-pain-bonus* -100)))
             (setf (bash-poise target) *bash-poise-time*)
             (play-sound :bash-hit (location target))
             (hurt target (roll *bash-damage*) :from (feet player) :pain-bonus bonus)
             (push-creature target (v- (location target) (feet player))
                            (float (* *bash-knockback* (if poised *poised-bash-knockback* 1.0)) 0f0))
             (enchant-strike player :shield target))))))

;;; Enchantments: a weapon's spell (the forge's, forge.lisp) goes with every blow of it that
;;; lands, for ENCHANT-COST mana out of the player's pool; with too little left, the blow
;;; lands plain. A miss costs nothing.

(defparameter *enchant-cost-scale* 0.5 "Mana a blow costs, against its spell's cost to cast.")

(defun enchant-cost (spell)
  (max 1 (ceiling (* *enchant-cost-scale* (spell-cost spell)))))

(defun enchanted-p (player weapon)
  "True if WEAPON is enchanted and PLAYER has the mana for a blow of it."
  (let ((spell (getf (enchantments player) weapon)))
    (and spell (<= (enchant-cost spell) (mana player)))))

(defun enchant-strike (player weapon target)
  "WEAPON's blow landed on TARGET: its enchantment strikes too, if PLAYER can pay."
  (let ((spell (getf (enchantments player) weapon)))
    (when (and spell (<= (enchant-cost spell) (mana player)))
      (decf (mana player) (enchant-cost spell))
      (let* ((loc (location target))
             (at (vec (vx loc) (+ (vy loc) (* 0.5 (sprite-height target))) (vz loc))))
        (apply-self-effects spell player player)
        (strike-with-spell spell target (feet player) player at)
        (play-impact spell at (container player))))))

(defun update-weapons (player dt)
  "Run the swing and the weapon switch. Called from the player's tick while not frozen."
  (when (swing-time player)
    (incf (swing-time player) dt)
    (when (and (swing-pending player) (<= (swing-hit-time (weapon player)) (swing-time player)))
      (setf (swing-pending player) NIL)
      (swing-hit player))
    (unless (swing-frame (swing-time player) (weapon player))
      (setf (swing-time player) NIL)))
  (when (bash-time player)
    (incf (bash-time player) dt)
    (when (and (bash-pending player) (<= (bash-hit-time) (bash-time player)))
      (setf (bash-pending player) NIL)
      (bash-hit player))
    (unless (frame-at (bash-time player) *bash-frame-times*)
      (setf (bash-time player) NIL)))
  ;; The shield rises while the block is held with the sword in hand and staying there,
  ;; once any swing is over; it stays up through a bash.
  (let ((step (/ dt *block-raise-time*))
        (was (block-raise player)))
    (setf (block-raise player)
          (if (or (bash-time player)
                  (and (block-held player)
                       (<= (guard-broken player) 0.0)
                       (eq (weapon player) :sword)
                       (eq (wanted-weapon player) :sword)
                       (= 0.0 (weapon-lower player))
                       (not (swing-time player))))
              (min 1.0 (+ (block-raise player) step))
              (max 0.0 (- (block-raise player) step))))
    (when (and (= was 0.0) (< 0.0 (block-raise player)) (not (bash-time player)))
      (play-sound :shield-raise)))
  (let ((step (/ dt *weapon-switch-time*)))
    (cond ((eq (weapon player) (wanted-weapon player))
           (setf (weapon-lower player) (max 0.0 (- (weapon-lower player) step))))
          ((attacking-p player))
          ((< (weapon-lower player) 1.0)
           (setf (weapon-lower player) (min 1.0 (+ (weapon-lower player) step))))
          (T
           (setf (weapon player) (wanted-weapon player))
           (play-sound (weapon-sound (weapon player) :draw))))))

;;; The sword on screen. The spear's sprite (spear.lisp) is a subclass: these generics
;;; say which weapon a sprite draws and how its strip is laid out.

(define-shader-entity sword (hud-element fx-sprite)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (animation :initform (find-fx-animation 'sword))
   (bob-phase :initform 0.0 :accessor bob-phase)
   (bob-amount :initform 0.0 :accessor bob-amount)))

(defgeneric held-weapon (sprite)
  (:documentation "The weapon (a keyword of *WEAPONS*) SPRITE is drawn for."))
(defgeneric idle-frames (sprite)
  (:documentation "Strip frames SPRITE's idle loop steps through, from the first."))
(defgeneric swing-first (sprite)
  (:documentation "Strip index of the first frame of SPRITE's swing."))
(defgeneric weapon-aim (sprite)
  (:documentation "Art pixels left from the strip's screen corner (the bottom-right one,
*SWORD-OVERHANG* in from the strip's edge) to where SPRITE's weapon points, which LAYOUT-SWORD
puts on the screen's middle; or NIL to keep the strip against the bottom-right corner."))

(defmethod held-weapon ((sword sword)) :sword)
(defmethod idle-frames ((sword sword)) *sword-idle-frames*)
(defmethod swing-first ((sword sword)) *sword-swing-first*)
(defmethod weapon-aim ((sword sword)) NIL)

(defun add-sword (container)
  (enter (make-instance 'sword) container))

(defmethod render :around ((sword sword) (program shader-program))
  (when (and *player* (eq (weapon *player*) (held-weapon sword)))
    (call-next-method)))

(defun sword-scale ()
  "Screen pixels per art pixel, across and up, for the sword and the shield: from the
sword strip's cell height, so the two always share one art pixel size."
  (let* ((atlas (animation-atlas (find-fx-animation 'sword)))
         (sy (max 1 (round (* *sword-height* (height (context +main+))) (getf atlas :cell-height)))))
    (values (max 1 (round (* sy *sword-stretch*))) sy)))

(defun layout-sword (sword)
  "Put the strip's right edge past the screen's (or its aim on the screen's middle, for a
weapon with a WEAPON-AIM), sunk below the bottom edge, lowered while switching, and offset
by the sway. As with the hands, the sway only ever dips."
  (multiple-value-bind (sx sy) (sword-scale)
    (let* ((atlas (animation-atlas (sprite-animation sword)))
           (context (context +main+))
           (w (* sx (getf atlas :cell-width)))
           (h (* sy (getf atlas :cell-height)))
           (aim (weapon-aim sword))
           (corner (if aim
                       (+ (round (width context) 2) (* aim sx))
                       (width context)))
           (bob (* *sword-bob* (bob-amount sword)))
           (phase (bob-phase sword)))
      (setf (vx (scaling sword)) (float w 0f0)
            (vy (scaling sword)) (float h 0f0))
      (place sword
             (+ (- corner w) (* *sword-overhang* sx) (round (* bob sx (cos phase))))
             (- (+ (* *sword-drop* sy)
                   (round (* bob sy (abs (sin phase))))
                   (round (* h (weapon-drop *player*)))))
             *weapon-depth*))))

;; Replaces FX-SPRITE's tick, which would face it into the world.
(define-handler (sword tick) (dt)
  (when *player*
    (unless (frozen-p)
      (incf (age sword) dt)
      (update-bob sword dt))
    (let* ((animation (sprite-animation sword))
           (atlas (animation-atlas animation))
           (time (swing-time *player*))
           (swing (and time (swing-frame time (held-weapon sword)))))
      (strip-uv (frame-uv sword) atlas
                (if swing
                    (+ (swing-first sword) swing)
                    (mod (floor (* (age sword) (animation-fps animation))) (idle-frames sword)))
                (getf atlas :frames)))
    (layout-sword sword)))

;;; The shield, in the left hand: a sprite of its own against the bottom-left corner,
;;; drawn with the sword at the sword's art pixel size. Its strip
;;; (data/sprites/sword/shield, from tools/make_shield.py) has its cell's bottom-left
;;; corner *SHIELD-MARGIN* art pixels past the screen's. It drops and sways with the
;;; sword. Frames: low and idle, then *SHIELD-RAISE-FRAMES* rising (lowering plays them
;;; back), the block held, then the bash's frames.

(define-fx-animation shield "sprites/sword/shield" :fps 1 :loop T)

(defparameter *shield-raise-frames* 2 "Strip frames between the idle one and the held block.")
(defparameter *shield-margin* 6
  "Art pixels the shield strip reaches past the screen's left and bottom edges:
make_shield.py's --margin. More than the sway, or the strip's edge shows.")

(define-shader-entity shield (sword)
  ((animation :initform (find-fx-animation 'shield))))

(defun add-shield (container)
  (enter (make-instance 'shield) container))

(defun shield-frame (player)
  "Strip frame showing PLAYER's shield: the bash's, else how far it is raised."
  (let ((bash (and (bash-time player) (frame-at (bash-time player) *bash-frame-times*)))
        (raise (block-raise player))
        (held (1+ *shield-raise-frames*)))
    (cond (bash (+ held 1 bash))
          ((<= 1.0 raise) held)
          ((< 0.0 raise) (min *shield-raise-frames* (1+ (floor (* raise *shield-raise-frames*)))))
          (T 0))))

(defun layout-shield (shield)
  (multiple-value-bind (sx sy) (sword-scale)
    (let* ((atlas (animation-atlas (sprite-animation shield)))
           (w (* sx (getf atlas :cell-width)))
           (h (* sy (getf atlas :cell-height)))
           (bob (* *sword-bob* (bob-amount shield)))
           (phase (bob-phase shield)))
      (setf (vx (scaling shield)) (float w 0f0)
            (vy (scaling shield)) (float h 0f0))
      (place shield
             (- (round (* bob sx (cos phase))) (* *shield-margin* sx))
             (- (+ (* *shield-margin* sy)
                   (round (* bob sy (abs (sin phase))))
                   ;; Lowered by the sword's height, so both leave the screen together.
                   (round (* sy (getf (animation-atlas (find-fx-animation 'sword)) :cell-height)
                             (weapon-drop *player*)))))
             *weapon-depth*))))

;; Replaces the sword's tick.
(define-handler (shield tick) (dt)
  (when *player*
    (unless (frozen-p)
      (update-bob shield dt))
    (let ((atlas (animation-atlas (sprite-animation shield))))
      (strip-uv (frame-uv shield) atlas (shield-frame *player*) (getf atlas :frames)))
    (layout-shield shield)))

;;; The weapon slots: one square per weapon in *WEAPONS*, in a row above the bars,
;;; each with the weapon's icon and its key number in the top-left
;;; corner. The weapon asked for is framed in gold and lit; the others are dimmed.
;;; Icons come from data/sprites/icons/weapons (tools/draw_weapon_icons.py).

(define-fx-animation weapon-icons "sprites/icons/weapons")

(defparameter *weapon-icons* '(:sword 0 :hands 1 :spear 2 :tempest 3) "Frame of each weapon's icon in the strip.")
(defparameter *weapon-icon-scale* 2 "Screen pixels per icon art pixel. Whole numbers only.")
(defparameter *weapon-slot-padding* 3 "Pixels between a slot's edge and its icon.")
(defparameter *weapon-slot-gap* 6 "Pixels between slots, and between the slots and the bars.")
(defparameter *weapon-slot-color* (vec4 0.06 0.05 0.06 0.8))
(defparameter *weapon-slot-active-color* (vec4 0.24 0.17 0.07 0.85))
(defparameter *weapon-slot-border* (vec4 0 0 0 1))
(defparameter *weapon-slot-active-border* (vec4 0.95 0.78 0.30 1))
(defparameter *weapon-icon-dim* 0.45 "Brightness of the icons of the weapons not asked for.")

(defparameter *enchant-dim* 0.4 "Brightness of an enchanted weapon's border while mana can't pay for a blow.")

(define-shader-entity weapon-slot (hud-element vertex-entity transformed-entity)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (active :initform NIL :accessor active)
   (enchanted :initform NIL :accessor enchanted
              :documentation "True while its weapon is enchanted: the border is ENCHANT-COLOR.")
   (enchant-color :initform (vec4 1 1 1 1) :reader enchant-color)))

(defmethod render :before ((slot weapon-slot) (program shader-program))
  (let ((active (active slot)))
    (setf (uniform program "back_color") (if active *weapon-slot-active-color* *weapon-slot-color*))
    (setf (uniform program "border_color") (cond ((enchanted slot) (enchant-color slot))
                                                 (active *weapon-slot-active-border*)
                                                 (T *weapon-slot-border*)))
    (setf (uniform program "border_width") (if (or active (enchanted slot)) 2.0 1.0))))

(defun spell-tint (spell color brightness)
  "Set vec4 COLOR to SPELL's look's colour (*SPELL-LOOKS*), brightest channel at BRIGHTNESS."
  (destructuring-bind (r g b) (fourth (assoc (effects-look (spell-effects spell)) *spell-looks*))
    (let ((k (/ brightness (max r g b))))
      (setf (vx color) (* k r) (vy color) (* k g) (vz color) (* k b) (vw color) 1.0))))

(define-class-shader (weapon-slot :vertex-shader)
  "layout (location = TRIAL_V_UV) in vec2 in_uv;
out vec2 slot_uv;

void main(){
  maybe_call_next_method();
  slot_uv = in_uv;
}")

(define-class-shader (weapon-slot :fragment-shader)
  "in vec2 slot_uv;
uniform vec4 back_color;
uniform vec4 border_color;
uniform float border_width;
out vec4 color;

void main(){
  // Distance to the nearest edge in screen pixels.
  vec2 edge = min(slot_uv, 1.0 - slot_uv) / fwidth(slot_uv);
  color = min(edge.x, edge.y) < border_width ? border_color : back_color;
}")

(define-shader-entity weapon-icon (hud-element fx-sprite)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (animation :initform (find-fx-animation 'weapon-icons))
   (frame :initarg :frame :initform 0 :accessor frame)
   (active :initform NIL :accessor active)))

;; Replaces FX-SPRITE's tick, which would face it into the world and end the strip.
(define-handler (weapon-icon tick) ()
  (let ((atlas (animation-atlas (sprite-animation weapon-icon))))
    (strip-uv (frame-uv weapon-icon) atlas (frame weapon-icon) (getf atlas :frames))))

(defmethod render :before ((icon weapon-icon) (program shader-program))
  (setf (uniform program "brightness") (if (active icon) 1.0 (float *weapon-icon-dim* 0f0))))

(define-class-shader (weapon-icon :fragment-shader)
  "uniform float brightness;
out vec4 color;

void main(){
  maybe_call_next_method();
  color.rgb *= brightness;
}")

(defclass weapon-bar (entity listener)
  ((name :initform :weapon-bar)
   (slots :initform () :accessor slots :documentation "(weapon slot icon label) per weapon.")
   (spell-label :initform (make-hud-text "" 'spell-label) :reader spell-label
                :documentation "The spell the hands cast and its cost, right of the slots.")
   (shown-spell :initform NIL :accessor shown-spell)))

(define-shader-entity spell-label (hud-text) ())

(defmethod hud-shown-p ((label spell-label))
  (and (call-next-method) *player* (eq :hands (wanted-weapon *player*))))

(defun weapon-enchantment (player weapon)
  "The spell WEAPON's blows carry: the sword's slot shows its shield's if it has none."
  (let ((enchantments (enchantments player)))
    (or (getf enchantments weapon)
        (and (eq weapon :sword) (getf enchantments :shield)))))

(defun add-weapon-bar (container)
  (let ((bar (make-instance 'weapon-bar)))
    (setf (slots bar)
          (loop for (key weapon) on *weapons* by #'cddr
                collect (list weapon
                              (make-instance 'weapon-slot)
                              (make-instance 'weapon-icon :frame (getf *weapon-icons* weapon))
                              (make-hud-text (string key)))))
    (enter bar container)
    ;; Slot, icon and number overlap: entered back to front, and placed at depths to match.
    (loop for (nil . parts) in (slots bar)
          do (dolist (part parts) (enter part container)))
    (enter (spell-label bar) container)
    bar))

(define-handler (weapon-bar tick) ()
  (let* ((atlas (animation-atlas (find-fx-animation 'weapon-icons)))
         (scale *weapon-icon-scale*)
         (icon-w (* scale (getf atlas :cell-width)))
         (icon-h (* scale (getf atlas :cell-height)))
         (pad *weapon-slot-padding*)
         (slot-w (+ icon-w pad pad))
         (slot-h (+ icon-h pad pad))
         (y (+ (hud-top) *weapon-slot-gap*))
         (wanted (and *player* (wanted-weapon *player*))))
    (loop for (weapon slot icon label) in (slots weapon-bar)
          for x from *hud-margin* by (+ slot-w *weapon-slot-gap*)
          for active = (eq weapon wanted)
          do (setf (active slot) active
                   (active icon) active
                   (vx (scaling slot)) (float slot-w 0f0)
                   (vy (scaling slot)) (float slot-h 0f0)
                   (vx (scaling icon)) (float icon-w 0f0)
                   (vy (scaling icon)) (float icon-h 0f0))
             (place slot x y -0.2)
             (place icon (+ x pad) (+ y pad) -0.1)
             (place label (+ x pad) (- (+ y slot-h) pad +glyph-height+))
             (let ((spell (and *player* (weapon-enchantment *player* weapon))))
               (setf (enchanted slot) (and spell T))
               (when spell
                 (spell-tint spell (enchant-color slot)
                             (if (<= (enchant-cost spell) (mana *player*)) 1.0 *enchant-dim*)))))
    ;; The spell the hands cast, right of the quickslot (inventory.lisp), clear of the
    ;; hands, re-uploaded only when it changes.
    (let ((spell (and *player* (current-spell *player*)))
          (label (spell-label weapon-bar)))
      (unless (eq spell (shown-spell weapon-bar))
        (setf (shown-spell weapon-bar) spell
              (text label) (if spell (format NIL "~a  ~d MP  (R)" (spell-title spell) (spell-cost spell)) "")))
      (multiple-value-bind (qx qy) (quick-position)
        (place label (+ qx (item-cell-size) *weapon-slot-gap*) (+ qy 2))))))
