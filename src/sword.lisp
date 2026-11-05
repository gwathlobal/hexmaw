(in-package #:hexmaw)

;;; The sword, and switching between weapons. The player holds one weapon at a time: the
;;; sword, the spear (spear.lisp) or the casting hands with a spell, whichever the hotbar slot
;;; asked for holds (keys 1 to 9; the hotbar is the inventory's, inventory.lisp). Switching
;;; lowers the current one off the bottom of the screen and raises the next, Hexen-style; one
;;; spell to another lowers and raises the hands.
;;;
;;; The sword's slash and the spear's thrust are both swings: SWING-TIME runs whichever
;;; is in hand, and the generics below (SWING-FRAME-TIMES, SWING-REACH and the rest)
;;; give each its timing and blow, by the weapon's keyword.
;;;
;;; The sword is one HUD sprite against the bottom-right corner. Its strip
;;; (data/sprites/sword, from art/sword/restyle.png) holds a 4-frame idle loop (a glint
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

(defparameter *hotbar-keys* '(:1 :2 :3 :4 :5 :6 :7 :8 :9) "The key of each hotbar slot.")
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

;;; Weapon state lives on the player: WEAPON (and HELD-SPELL, for the hands) is the one on
;;; screen, WANTED-WEAPON (and WANTED-SPELL) the one asked for, from the hotbar slot
;;; WANTED-SLOT, WEAPON-LOWER how far it is lowered (0 up, 1 off screen).

(defun attacking-p (player)
  (or (swing-time player) (pending-spell player) (cast-position)
      (bash-time player) (< 0.0 (block-raise player))))

(defun weapon-in-hand-p (player)
  "True if what is on screen is what is asked for."
  (and (eq (weapon player) (wanted-weapon player))
       (eq (held-spell player) (wanted-spell player))))

(defun weapon-ready-p (player)
  (and (weapon-in-hand-p player)
       (= 0.0 (weapon-lower player))))

(defun sync-wanted (player)
  "Ask for what the wanted hotbar slot holds now, which a drag in the inventory may have
changed: its weapon, the hands with its rune's spell, or nothing."
  ;; A stack that left the bag (a rune unweaved) is no longer bound.
  (prune-bindings player)
  (let ((stack (nth (wanted-slot player) (hotbar player))))
    (setf (wanted-weapon player) (cond ((null stack) NIL)
                                       ((eq :rune (first stack)) :hands)
                                       (T (item-property (first stack) :weapon)))
          (wanted-spell player) (stack-spell stack))))

(defun settle-held (player)
  "Take what the wanted hotbar slot holds in hand at once, after a load, the stairs or a reset:
a spell decoded apart from its rune isn't the rune's, and would be switched for it."
  (sync-wanted player)
  (setf (weapon player) (wanted-weapon player)
        (held-spell player) (wanted-spell player)))

(defun select-slot (player index)
  "Take what hotbar slot INDEX, from 0, holds in hand; an empty one changes nothing. True if
it holds something."
  (when (nth index (hotbar player))
    (setf (wanted-slot player) index)
    (sync-wanted player)
    T))

(defun select-weapon (player key)
  "Take what the hotbar slot on KEY (:1 to :9) holds in hand. True if it holds something."
  (let ((index (position key *hotbar-keys*)))
    (and index (select-slot player index))))

(defun weapon-drop (player)
  "Fraction of its height the weapon on screen is lowered, eased."
  (let ((k (weapon-lower player)))
    (* k k)))

(defun player-attack (player)
  "Attack with the weapon in hand: cast the spell in the hands, swing the sword, thrust the
spear, or, with the shield raised, bash with it. Nothing while the shield is on its way up
or down, or with nothing in hand."
  (when (weapon-ready-p player)
    (case (weapon player)
      (:hands (when (held-spell player)
                (player-cast player (held-spell player))))
      (:sword (cond ((<= 1.0 (block-raise player)) (player-bash player))
                    ((= 0.0 (block-raise player)) (player-swing player))))
      (:spear (player-swing player)))))

(defparameter *weapon-sounds*
  '(:sword (:swing :sword-swing :draw :draw-sword)
    :spear (:swing :spear-thrust :draw :draw-spear)
    :hands (:draw :draw-magic))
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
  (looked-at-creature player reach arc))

(defun looked-at-creature (player reach arc &key test dead)
  "As SWING-TARGET: the nearest live creature within REACH and ARC. TEST, if given, must also
be true of it; DEAD lets in the dead, for E (townsfolk.lisp)."
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
          when (and (or dead (not (dead c)))
                    (or (null test) (funcall test c))
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
      (hurt target (roll (swing-damage weapon)) :from (feet player) :by player
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
             (hurt target (roll *bash-damage*) :from (feet player) :pain-bonus bonus :by player)
             (push-creature target (v- (location target) (feet player))
                            (float (* *bash-knockback* (if poised *poised-bash-knockback* 1.0)) 0f0))
             (enchant-strike player :shield target))))))

;;; Enchantments: a weapon's spell (the forge's, forge.lisp) goes with every blow of it that
;;; lands, for ENCHANT-COST mana out of the player's pool; with too little left, the blow
;;; lands plain. A miss costs nothing.

(defparameter *enchant-cost-scale* 0.5 "Mana a blow costs, against its spell's cost to cast.")

(defun enchant-cost (spell)
  (max 1 (ceiling (* *enchant-cost-scale* (spell-cost spell)))))

(defun held-weapon-stack (player)
  "The bag stack of the weapon PLAYER holds: the wanted hotbar slot's, while it is that weapon."
  (let ((stack (nth (wanted-slot player) (hotbar player))))
    (and stack (eq (weapon player) (item-property (first stack) :weapon)) stack)))

(defun weapon-spell (player weapon)
  "The enchantment WEAPON's blows carry: the shield's PLAYER's own, a sword's or spear's the one
in hand's (STACK-ENCHANTMENT, inventory.lisp), each weapon having its own."
  (if (eq weapon :shield)
      (getf (enchantments player) :shield)
      (let ((stack (held-weapon-stack player)))
        (and stack (eq weapon (item-property (first stack) :weapon)) (stack-enchantment stack)))))

(defun enchanted-p (player weapon)
  "True if WEAPON is enchanted and PLAYER has the mana for a blow of it."
  (let ((spell (weapon-spell player weapon)))
    (and spell (<= (enchant-cost spell) (mana player)))))

(defun enchant-strike (player weapon target)
  "WEAPON's blow landed on TARGET: its enchantment strikes too, if PLAYER can pay."
  (let ((spell (weapon-spell player weapon)))
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
    ;; A bash that glanced off a knight's shield knocked the guard aside (BREAK-GUARD), ending it.
    (unless (and (bash-time player) (frame-at (bash-time player) *bash-frame-times*))
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
  (sync-wanted player)
  (let ((step (/ dt *weapon-switch-time*)))
    (cond ((weapon-in-hand-p player)
           (setf (weapon-lower player) (max 0.0 (- (weapon-lower player) step))))
          ((attacking-p player))
          ;; Empty-handed, the next one comes straight up.
          ((null (weapon player))
           (setf (weapon player) (wanted-weapon player)
                 (held-spell player) (wanted-spell player)
                 (weapon-lower player) 1.0)
           (play-sound (weapon-sound (weapon player) :draw)))
          ((< (weapon-lower player) 1.0)
           (setf (weapon-lower player) (min 1.0 (+ (weapon-lower player) step))))
          (T
           (setf (weapon player) (wanted-weapon player)
                 (held-spell player) (wanted-spell player))
           (play-sound (weapon-sound (weapon player) :draw))))))

;;; The sword on screen. The spear's sprite (spear.lisp) is a subclass: these generics
;;; say which weapon a sprite draws and how its strip is laid out.

(define-shader-entity sword (rim-glow hud-element fx-sprite)
  ((vertex-array :initform (// 'hexmaw 'hud-quad))
   (animation :initform (find-fx-animation 'sword))
   (bob-phase :initform 0.0 :accessor bob-phase)
   (bob-amount :initform 0.0 :accessor bob-amount)))

(defgeneric held-weapon (sprite)
  (:documentation "The weapon (:SWORD or :SPEAR, as a weapon item's :WEAPON) SPRITE is drawn for."))
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

;;; An enchanted weapon on screen glows at its rim in its spell's colour (RIM-GLOW, boss.lisp),
;;; as its hotbar slot's border does: pulsing, and dim while mana can't pay a blow.

(defparameter *weapon-rim-strength* 0.85 "How strongly an enchanted weapon's rim shows its colour, at the pulse's top.")
(defparameter *weapon-rim-pulse* 0.25 "How far the rim's strength falls at the pulse's bottom.")
(defparameter *weapon-rim-rate* 3.0 "The rim's pulse, in radians a second.")

(defparameter *weapon-rim-width* 2 "Texels the rim reaches in: the weapons' art is fine-grained.")
(defmethod rim-width ((sprite sword)) *weapon-rim-width*)

(defgeneric rim-weapon (sprite)
  (:documentation "The weapon whose enchantment SPRITE's rim shows: the shield's own for the shield.")
  (:method ((sprite sword)) (held-weapon sprite))
  (:method ((sprite shield)) :shield))

(define-handler (sword tick :after) ()
  (let ((spell (and *player* (weapon-spell *player* (rim-weapon sword))))
        (glow (glow sword)))
    (if spell
        (progn
          (spell-tint spell glow 1.0)
          (setf (vw glow) (* (if (<= (enchant-cost spell) (mana *player*)) 1.0 *enchant-dim*)
                             (- *weapon-rim-strength*
                                (* *weapon-rim-pulse* 0.5 (+ 1.0 (sin (* *weapon-rim-rate* *light-clock*))))))))
        (setf (vw glow) 0.0))))

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

(defparameter *weapon-icons* '(:sword 0 :spear 2) "Frame of each weapon's icon in the strip.")
(defparameter *spell-icons*
  '(:fire 1 :storm 3 :frost 4 :shock 5 :drain 6 :heal 7 :ward 8 :slow 9 :knockback 10)
  "Frame in the strip of the icon of a rune by its first effect (SPELL-ICON-KEY): damage by its
element, any other by its kind, and a tornado's :STORM.")

(defun spell-icon-key (spell)
  "What SPELL's icon shows: its first effect, damage as its element (fire without one), or the
tornado for a vortex."
  (let ((first (first (spell-effects spell))))
    (cond ((eq (spell-delivery spell) :vortex) :storm)
          ((null first) :fire)
          ((eq (effect-kind first) :damage) (or (effect-element first) :fire))
          (T (effect-kind first)))))

(defun spell-icon (spell)
  (getf *spell-icons* (spell-icon-key spell) 1))
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

(defun weapon-enchantment (player stack)
  "The spell the weapon STACK's blows carry: a sword's slot shows its shield's if it has none."
  (or (stack-enchantment stack)
      (and (eq :sword (item-property (first stack) :weapon)) (getf (enchantments player) :shield))))
