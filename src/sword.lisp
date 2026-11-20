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

;;; The sword (weapons.lisp): a slash that lands at full sweep, its 4-frame idle loop then the
;;; slash's 8 frames in its strip, and the shield (below) as its guard.
(define-weapon :sword
  :title "Sword" :icon 0 :strip sword :frames (:idle 4 :swing 4)
  :loot T :loot-strip loot-sword :forge-noun "Edge"
  :sounds (:draw :draw-sword)
  :guard :shield
  ;; The blow lands on frame 4, the blade at full sweep: the nearest creature within 2 m of its
  ;; body's edge and 0.8 rad either side of the view.
  :swing (blow :name :sword :frame-times (0.05 0.07 0.07 0.04 0.06 0.07 0.08 0.08) :hit-frame 4
               :reach 2.0 :arc 0.8 :damage (10 16) :knockback 3.0 :pain-bonus 0
               :sound :sword-swing :verb "swing"
               :wall (:sparks 8 :grit 4 :speed (3.0 7.0) :spread 0.8
                      :sound :blade-hit-stone :wood-sound :blade-hit-wood)
               ;; The blade's tip in strip frame 8.
               :tip (:sword 140 167)))

;;; The shield, the sword's guard: it rises over 0.12 s; a click while it is up bashes, pulled
;;; back, thrust, impact, coming back, landing on the thrust. Its strip's idle frame comes first,
;;; then 2 rising (lowering plays them back), the block held, then the bash's.
(define-guard :shield
  :title "Shield" :strip shield :raise-time 0.12 :raise-frames 2 :margin 6
  :sound :shield-raise :forge-noun "Bulwark"
  :bash (bash :name :shield :frame-times (0.08 0.06 0.12 0.08) :hit-frame 1
              :reach 1.6 :arc 0.6 :damage (2 4) :knockback 6.0 :sound :shield-bash
              :wall (:sparks 3 :grit 5 :speed (2.0 5.0) :spread 0.9
                     :sound :shield-block :wood-sound :shield-block :recoil 1.5)
              ;; Its upper rim in strip frame 5.
              :tip (:shield 182 10)))

(defparameter *hotbar-keys* '(:1 :2 :3 :4 :5 :6 :7 :8 :9) "The key of each hotbar slot.")
(defvar *weapon-sprites* ()
  "The weapon sprites on screen, by the class each was made as (sword, spear, maul, shield):
WEAPON-TIP-DIRECTION reads where they are.")

(defparameter *weapon-switch-time* 0.15 "Seconds to lower a weapon, and again to raise the next.")

;;; The rules of a staggering blow, which the bash, the spear's sweep and the maul's earthshake
;;; share.
(defparameter *bash-pain-bonus* 50
  "Percent a bash adds to the creature's PAIN-CHANCE when it lands in the wind-up of the
creature's attack (WINDING-UP-P): interrupting is what it is for. At any other time a
bash doesn't stagger.")
(defparameter *bash-poise-time* 1.5
  "Seconds after a bash lands in which another bash can't stagger the creature and barely
moves it.")
(defparameter *poised-bash-knockback* 0.25 "Fraction of a staggering blow's knockback a poised creature takes.")
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

;;; Weapon state lives on the player: WEAPON (and HELD-SPELL, for the hands) is the one on
;;; screen, WANTED-WEAPON (and WANTED-SPELL) the one asked for, from the hotbar slot
;;; WANTED-SLOT, WEAPON-LOWER how far it is lowered (0 up, 1 off screen).

(defun attacking-p (player)
  (or (swing-time player) (charge-time player) (pending-spell player) (cast-position)
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
  "Take what the wanted hotbar slot holds in hand at once after the stairs, a scene reset, or a
load of a save older than HELD-RUNE (save.lisp)."
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
spear, raise the maul to charge it (maul.lisp), or, with the shield raised, bash with it.
Nothing while the shield is on its way up or down, or with nothing in hand. Its blow, as it lands,
tears free of a bloodroot's roots closing on or holding the player (bloodroot.lisp): SWING-HIT and
BASH-STRIKE's moment in UPDATE-WEAPONS, a spell's release. What it does is the template's
WEAPON-ATTACK (weapons.lisp)."
  (when (weapon-ready-p player)
    (let ((template (find-weapon (weapon player) NIL)))
      (when template
        (weapon-attack template player)))))

;; A weapon's swing; with its guard fully raised, its guard's bash, and nothing while the guard is
;; on its way up or down.
(defmethod weapon-attack ((template weapon-template) player)
  (let ((guard (weapon-guard template))
        (raise (block-raise player)))
    (cond ((null guard) (start-blow (weapon-swing template) player))
          ((<= 1.0 raise) (start-blow (guard-bash guard) player))
          ((= 0.0 raise) (start-blow (weapon-swing template) player)))))

;; A weapon's alternate blow, if it has one.
(defmethod weapon-alternate ((template weapon-template) player)
  (let ((blow (weapon-alternate-blow template)))
    (when blow
      (start-blow blow player))))

(defun weapon-sound (weapon event)
  "WEAPON's clip (sound.lisp) for EVENT: :SWING as its swing starts (its blow's), :GUARD as its
guard rises, :DRAW as it comes up (its template's SOUNDS)."
  (let ((template (find-weapon weapon NIL)))
    (and template
         (case event
           (:swing (let ((blow (weapon-swing template))) (and blow (blow-sound blow))))
           (:guard (let ((guard (weapon-guard template))) (and guard (guard-sound guard))))
           (T (getf (weapon-sounds template) event))))))

(defun player-swing (player)
  "Start the swing of the weapon in hand, on SWING-TIME."
  (unless (swing-time player)
    (play-sound (weapon-sound (weapon player) :swing))
    (setf (swing-time player) 0.0
          (swing-pending player) T)))

;; A plain swing starts at once.
(defmethod start-blow ((blow blow) player)
  (player-swing player))

;;; The second blow: with the shield up (BLOCK-RAISE), a click bashes with it; with the spear, the
;;; right button sweeps with its haft (spear.lisp), with the maul it shakes the floor (maul.lisp).
;;; Each runs on BASH-TIME, the weapon's SECOND-BLOW (weapons.lisp).

(defun start-second-blow (player blow)
  "Start BLOW on BASH-TIME."
  (play-sound (blow-sound blow))
  (setf (bash-time player) 0.0
        (bash-pending player) T))

(defmethod start-blow ((blow bash) player)
  (unless (bash-time player)
    (start-second-blow player blow)))

(defun start-alternate (player blow)
  "Start the alternate blow BLOW, a press of the right button: not before the weapon is ready, nor
during another blow, nor without its stamina."
  (when (and (weapon-ready-p player) (not (attacking-p player)) (<= (blow-stamina blow) (stamina player)))
    (decf (stamina player) (blow-stamina blow))
    (start-second-blow player blow)))

(defmethod bash-strike (player (blow bash))
  (bash-hit player blow))

(defun frame-at (time frame-times)
  "Frame of an animation timed by FRAME-TIMES at TIME seconds into it, or NIL once it
is over."
  (loop for frame from 0
        for duration in frame-times
        sum duration into end
        when (< time end) return frame))

(defun swing-frame (time weapon)
  "Frame of WEAPON's swing at TIME seconds into it, or NIL once it is over."
  (frame-at time (blow-frame-times (swing-blow weapon))))

(defun swing-hit-time (weapon)
  (blow-hit-time (swing-blow weapon)))

(defun bash-hit-time (weapon)
  (blow-hit-time (second-blow weapon)))

(defun clear-path-p (from to height)
  "True if nothing solid stands between FROM and TO, HEIGHT metres above FROM."
  (let* ((dx (- (vx to) (vx from)))
         (dz (- (vz to) (vz from)))
         (steps (ceiling (sqrt (+ (* dx dx) (* dz dz))) 0.1))
         (y (+ (vy from) height)))
    (loop for i from 1 below steps
          for k = (/ i steps)
          never (solid-overlapping (+ (vx from) (* k dx)) y (+ (vz from) (* k dz)) 0.02 0.02))))

(defun swing-target (player reach arc)
  "The nearest live creature the swing reaches: its body within REACH, inside ARC
either side of where the player faces, level with the player, and not behind a wall."
  (looked-at-creature player reach arc))

(defun blow-reaches-p (player creature reach arc)
  "The distance across to CREATURE if a blow of PLAYER's reaches it: its body within REACH, inside
ARC either side of where the player faces, level with the player, and not behind a wall; else NIL."
  (let* ((feet (feet player))
         (yaw (vy (rotation player)))
         (loc (location creature))
         (dx (- (vx loc) (vx feet)))
         (dz (- (vz loc) (vz feet)))
         (distance (sqrt (+ (* dx dx) (* dz dz))))
         (r (body-radius creature)))
    (and (< distance (+ reach r))
         (< (vy loc) (+ (vy feet) *player-height*))
         (< (vy feet) (+ (vy loc) (sprite-height creature)))
         (or (< distance r)
             ;; The body's own width widens the arc it can be hit in.
             (< (acos (max -1.0 (min 1.0 (/ (- (* dx (sin yaw)) (* dz (cos yaw))) distance))))
                (+ arc (atan r distance))))
         (clear-path-p feet loc 1.0)
         distance)))

(defun looked-at-creature (player reach arc &key test dead)
  "As SWING-TARGET: the nearest live creature within REACH and ARC. TEST, if given, must also
be true of it; DEAD lets in the dead, for E (townsfolk.lisp)."
  (let ((best NIL)
        (best-distance 0.0))
    (loop for c across *creatures*
          for distance = (and (or dead (not (dead c)))
                              (or (null test) (funcall test c))
                              (blow-reaches-p player c reach arc))
          when (and distance (or (null best) (< distance best-distance)))
            do (setf best c best-distance distance))
    best))

(defun swing-hit (player)
  (let* ((blow (swing-blow (weapon player)))
         (target (swing-target player (blow-reach blow) (blow-arc blow))))
    (if target
        (swing-strike player blow target)
        (swing-miss player blow))))

(defmethod swing-miss (player (blow blow))
  (wall-strike player blow))

;;; A blow that finds no one strikes the wall where its weapon's tip is on screen at the hit frame
;;; (its BLOW-TIP): sparks and grit off stone (SOLID-STRIKE, greybox.lisp; WALL-SPARKS, sparks.lisp),
;;; chips off ice, splinters off wood, a puff off snow, with a sound and a little of the feel of a
;;; hit, always less than one. The line goes from the eye through that pixel, so the sparks start at
;;; the tip whatever the window's size (the weapons' art pixels are whole screen pixels, so a fixed
;;; offset from the crosshair would drift with it).

(defun weapon-tip-direction (player blow)
  "The unit vector from PLAYER's eye through where BLOW's weapon tip is on screen (its BLOW-TIP),
as three values, or NIL if its sprite isn't there."
  (destructuring-bind (&optional sprite-name (ax 0) (ay 0)) (blow-tip blow)
    (let ((sprite (and sprite-name (getf *weapon-sprites* sprite-name))))
      (when (and sprite (slot-boundp sprite 'animation))
        (let* ((atlas (animation-atlas (sprite-animation sprite)))
               (cw (float (getf atlas :cell-width) 0f0))
               (ch (float (getf atlas :cell-height) 0f0))
               (loc (location sprite))
               (size (scaling sprite))
               ;; Window pixels, from the bottom-left (the HUD's quads stand on their corner).
               (px (+ (vx loc) (* (vx size) (/ (+ ax 0.5) cw))))
               (py (+ (vy loc) (* (vy size) (/ (- ch ay 0.5) ch))))
               (context (context +main+))
               (w (float (width context) 0f0))
               (h (float (height context) 0f0))
               (tan-half (tan (* 0.5 (float (fov player) 0f0) (/ (float pi 0f0) 180))))
               (sx (* (/ (- px (* 0.5 w)) (* 0.5 w)) tan-half (/ w h)))
               (sy (* (/ (- py (* 0.5 h)) (* 0.5 h)) tan-half))
               (f (look-direction player))
               (yaw (vy (rotation player)))
               ;; Right, and up as right × forward.
               (rx (cos yaw)) (rz (sin yaw))
               (ux (- (* 0 (vz f)) (* rz (vy f))))
               (uy (- (* rz (vx f)) (* rx (vz f))))
               (uz (- (* rx (vy f)) (* 0 (vx f))))
               (dx (+ (vx f) (* sx rx) (* sy ux)))
               (dy (+ (vy f) (* sy uy)))
               (dz (+ (vz f) (* sx rz) (* sy uz)))
               (len (sqrt (+ (* dx dx) (* dy dy) (* dz dz)))))
          (values (/ dx len) (/ dy len) (/ dz len)))))))

(defun wall-strike-value (value charge)
  "VALUE as a BLOW-WALL gives it, at CHARGE (0 to 1) if it is (:CHARGE least full)."
  (if (and (consp value) (eq :charge (first value)))
      (destructuring-bind (least full) (rest value)
        (if (consp least)
            (mapcar (lambda (l f) (charge-lerp charge l f)) least full)
            (charge-lerp charge least full)))
      value))

(defun wall-strike (player blow &key (reach (blow-reach blow)) (charge 0.0))
  "BLOW (weapons.lisp) found no one: if the line from PLAYER's eye through its weapon's tip on
screen (WEAPON-TIP-DIRECTION; the crosshair without one) meets a solid within REACH metres ahead
(the blow's own), strike it there, as its BLOW-WALL says. True if it did."
  (let ((props (blow-wall blow))
        (eye (location player))
        (ahead (look-direction player)))
    (when props
      (multiple-value-bind (dx dy dz) (weapon-tip-direction player blow)
        (unless dx (setf dx (vx ahead) dy (vy ahead) dz (vz ahead)))
        ;; REACH is how far ahead, so a line off to the side reaches as deep a wall.
        (let ((range (/ reach (max 0.6 (+ (* dx (vx ahead)) (* dy (vy ahead)) (* dz (vz ahead)))))))
          (multiple-value-bind (s x y z nx ny nz)
              (wall-strike-point (vx eye) (vy eye) (vz eye) dx dy dz range)
            (when (and s (pane-of-solid s))
              ;; A window shatters (glass.lisp).
              (break-pane (pane-of-solid s) :from eye)
              (return-from wall-strike T))
            (when s
              (flet ((by-charge (key) (wall-strike-value (getf props key) charge)))
                (let ((strike (solid-strike s))
                      (at (vec x y z)))
                  (wall-sparks x y z nx ny nz dx dy dz strike
                               :sparks (round (by-charge :sparks)) :grit (round (by-charge :grit))
                               :speed (by-charge :speed) :spread (getf props :spread))
                  (play-sound (case strike
                                (:snow :footstep-snow)
                                (:wood (getf props :wood-sound))
                                (T (getf props :sound)))
                              at)
                  (let ((camera (getf props :camera))
                        (stop (getf props :hit-stop))
                        (recoil (getf props :recoil)))
                    (when camera (kick-camera (by-charge :camera) player))
                    (when stop (hit-stop (by-charge :hit-stop)))
                    (when recoil (shove-player player at recoil)))
                  T)))))))))

;; A blade's blow: hurt, shoved, and the weapon's enchantment.
(defmethod swing-strike (player (blow blow) target)
  (play-sound (if (bleeds target) :blade-hit-flesh :blade-hit-bone) (location target))
  ;; The shield doesn't stop the blade, but the blade rings off it.
  (when (shielded-p target (feet player))
    (shield-sparks target))
  (hurt target (roll (blow-damage blow)) :from (feet player) :by player
                                         :pain-bonus (blow-pain-bonus blow))
  (push-creature target (v- (location target) (feet player))
                 (float (blow-knockback blow) 0f0))
  (enchant-strike player (weapon player) target))

(defun bash-hit (player bash)
  "Bash (the blow BASH) the creature in front of PLAYER. Against a shield that covers it, the bash
glances off and the player reels back; otherwise it hurts and shoves, staggering only a creature
winding up an attack and not already poised from a bash. With no one there, it strikes the wall.
Its enchantment is its guard's, the shield's."
  (let* ((target (swing-target player (blow-reach bash) (blow-arc bash))))
    (cond ((null target) (wall-strike player bash))
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
             (hurt target (roll (blow-damage bash)) :from (feet player) :pain-bonus bonus :by player)
             (push-creature target (v- (location target) (feet player))
                            (float (* (blow-knockback bash) (if poised *poised-bash-knockback* 1.0)) 0f0))
             (enchant-strike player (weapon-guard-name (find-weapon (weapon player))) target))))))

;;; What a weapon's tooltip says of its blows (WEAPON-LINES, inventory.lisp).

(defmethod blow-lines ((blow blow))
  (list (format NIL "Damage ~a, reach ~,1f m" (range-text (blow-damage blow)) (blow-reach blow))
        (format NIL "~,2f s a ~a" (blow-duration blow) (blow-verb blow))))

(defmethod second-blow-lines ((guard guard-template))
  (list (format NIL "Right button: ~(~a~) up, click to bash" (guard-title guard))))

;;; Enchantments: a weapon's spell (the forge's, forge.lisp) goes with every blow of it that
;;; lands, for ENCHANT-COST mana out of the player's pool; with too little left, the blow
;;; lands plain. A miss costs nothing.

(defparameter *enchant-cost-scale* 0.5 "Mana a blow costs, against its spell's power (SPELL-POWER).")

(defun enchant-cost (spell)
  (max 1 (ceiling (* *enchant-cost-scale* (spell-power spell)))))

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
      ;; As the blow lands, it tears free of roots holding the player (bloodroot.lisp).
      (break-snare player)
      (swing-hit player))
    (unless (swing-frame (swing-time player) (weapon player))
      (setf (swing-time player) NIL)))
  (when (bash-time player)
    (incf (bash-time player) dt)
    (when (and (bash-pending player) (<= (bash-hit-time (weapon player)) (bash-time player)))
      (setf (bash-pending player) NIL)
      (break-snare player)
      (bash-strike player (second-blow (weapon player))))
    ;; A bash that glanced off a knight's shield knocked the guard aside (BREAK-GUARD), ending it.
    (unless (and (bash-time player) (frame-at (bash-time player) (blow-frame-times (second-blow (weapon player)))))
      (setf (bash-time player) NIL)))
  (setf (spear-jolt player) (max 0.0 (- (spear-jolt player) dt)))
  (update-blow-charge player dt)
  ;; The guard (the shield) rises while the block is held with its weapon in hand and staying
  ;; there, once any swing is over; it stays up through a bash. With no guard in hand, one still
  ;; up comes down at the shield's pace.
  (let* ((weapon (weapon player))
         (guard (let ((g (weapon-guard-of weapon))) (and g (guard-raise-time g))))
         (step (/ dt (or guard (guard-raise-time (find-guard :shield)))))
         (was (block-raise player)))
    (setf (block-raise player)
          (if (and guard
                   (or (bash-time player)
                       (and (block-held player)
                            (<= (guard-broken player) 0.0)
                            (eq (wanted-weapon player) weapon)
                            (= 0.0 (weapon-lower player))
                            (not (swing-time player)))))
              (min 1.0 (+ (block-raise player) step))
              (max 0.0 (- (block-raise player) step))))
    (when (and (= was 0.0) (< 0.0 (block-raise player)) (not (bash-time player)))
      (play-sound (weapon-sound weapon :guard))))
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
  (:documentation "The weapon (:SWORD, :SPEAR or :MAUL, as a weapon item's :WEAPON) SPRITE is drawn for."))
(defgeneric idle-frames (sprite)
  (:documentation "Strip frames SPRITE's idle loop steps through, from the first."))
(defgeneric swing-first (sprite)
  (:documentation "Strip index of the first frame of SPRITE's swing."))
(defgeneric weapon-aim (sprite)
  (:documentation "Art pixels left from the strip's screen corner (the bottom-right one,
*SWORD-OVERHANG* in from the strip's edge) to where SPRITE's weapon points, which LAYOUT-SWORD
puts on the screen's middle; or NIL to keep the strip against the bottom-right corner."))

(defmethod held-weapon ((sword sword)) :sword)
;; From its template's FRAMES and AIM (weapons.lisp).
(defmethod idle-frames ((sword sword)) (weapon-frame-index (find-weapon (held-weapon sword)) :idle))
(defmethod swing-first ((sword sword)) (weapon-frame-index (find-weapon (held-weapon sword)) :swing))
(defmethod weapon-aim ((sword sword)) (weapon-aim-pixels (find-weapon (held-weapon sword))))

(defgeneric weapon-frame (sprite player)
  (:documentation "Strip frame SPRITE shows for PLAYER now: its swing's, else its idle loop's.")
  (:method ((sword sword) player)
    (let* ((time (swing-time player))
           (swing (and time (swing-frame time (held-weapon sword)))))
      (if swing
          (+ (swing-first sword) swing)
          (mod (floor (* (age sword) (animation-fps (sprite-animation sword)))) (idle-frames sword))))))

(defun add-weapon-sprite (class container)
  (let ((sprite (make-instance class)))
    (setf (getf *weapon-sprites* (rim-weapon sprite)) sprite)
    (enter sprite container)))

(defun add-sword (container)
  (add-weapon-sprite 'sword container))

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
             ;; A strip whose pictures reach past the corner says how far (make_shield.py).
             (+ (- corner w) (* (getf atlas :overhang *sword-overhang*) sx) (round (* bob sx (cos phase))))
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
    (let ((atlas (animation-atlas (sprite-animation sword))))
      (strip-uv (frame-uv sword) atlas (weapon-frame sword *player*) (getf atlas :frames)))
    (layout-sword sword)))

;;; The shield, in the left hand: a sprite of its own against the bottom-left corner,
;;; drawn with the sword at the sword's art pixel size. Its strip
;;; (data/sprites/sword/shield, from tools/make_shield.py) has its cell's bottom-left
;;; corner its guard's MARGIN art pixels past the screen's. It drops and sways with the
;;; sword. Frames: low and idle, then its guard's RAISE-FRAMES rising (lowering plays them
;;; back), the block held, then the bash's frames.

(define-fx-animation shield "sprites/sword/shield" :fps 1 :loop T)

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
  (add-weapon-sprite 'shield container))

(defun shield-frame (player)
  "Strip frame showing PLAYER's shield: the bash's, else how far it is raised."
  (let* ((guard (find-guard :shield))
         (raise-frames (guard-raise-frames guard))
         (bash (and (bash-time player) (eq (weapon-guard-of (weapon player)) guard)
                    (frame-at (bash-time player) (blow-frame-times (guard-bash guard)))))
         (raise (block-raise player))
         (held (1+ raise-frames)))
    (cond (bash (+ held 1 bash))
          ((<= 1.0 raise) held)
          ((< 0.0 raise) (min raise-frames (1+ (floor (* raise raise-frames)))))
          (T 0))))

(defun layout-shield (shield)
  (multiple-value-bind (sx sy) (sword-scale)
    (let* ((atlas (animation-atlas (sprite-animation shield)))
           (w (* sx (getf atlas :cell-width)))
           (h (* sy (getf atlas :cell-height)))
           (margin (guard-margin (find-guard :shield)))
           (bob (* *sword-bob* (bob-amount shield)))
           (phase (bob-phase shield)))
      (setf (vx (scaling shield)) (float w 0f0)
            (vy (scaling shield)) (float h 0f0))
      (place shield
             (- (round (* bob sx (cos phase))) (* margin sx))
             (- (+ (* margin sy)
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

;; A weapon's icon is its template's ICON (weapons.lisp).
(defparameter *spell-icons*
  '(:fire 1 :storm 3 :frost 4 :shock 5 :drain 6 :heal 7 :ward 8 :slow 9 :knockback 10 :absorb 12)
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
(defparameter *weapon-slot-padding* 1 "Art pixels between a slot's edge and its icon.")
(defparameter *weapon-slot-gap* 2 "Art pixels between slots, and between the slots and the bars.")

;; The icons, slots and their spacing are in HUD art pixels (HUD-PIXEL-SCALE, hud.lisp).
(defun slot-padding () (* *weapon-slot-padding* (hud-pixel-scale)))
(defun slot-gap () (* *weapon-slot-gap* (hud-pixel-scale)))
(defparameter *weapon-slot-color* (vec4 0.06 0.05 0.06 0.8))
(defparameter *weapon-slot-active-color* (vec4 0.24 0.17 0.07 0.85))
(defparameter *weapon-slot-border* (vec4 0.07 0.05 0.04 1))
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
    ;; One HUD art pixel; the asked-for and enchanted slots show by their border's colour.
    (setf (uniform program "border_width") (float (hud-pixel-scale) 0f0))))

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
