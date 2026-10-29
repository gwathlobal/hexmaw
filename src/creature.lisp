(in-package #:hexmaw)

;;; Creatures: billboard monsters that can be hurt. A hit flashes the sprite,
;;; plays its flinch (stagger; without a hurt animation, a squash), slides it back along the blow (knockback)
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
(defparameter *wander-pause* '(1.0 3.0) "Least and most seconds a wandering creature stands before moving on.")
(defparameter *hurt-pause* 0.4 "Seconds a creature stands after a hit before it plans a new walk.")
(defparameter *settle-speed* 3.0 "Metres per second a creature rises or sinks to the floor under it.")
(defparameter *stuck-time* 0.5 "Seconds a walking creature stays blocked before it gives up its path.")
(defparameter *stuck-pause* 0.3 "Seconds it stands after giving up before it plans another walk.")
(defparameter *sight-range* 10.0 "Metres within which a creature sees the player in front of it.")
(defparameter *hearing-range* 3.0 "Metres within which it notices the player behind it.")
(defparameter *alert-time* 6.0 "Seconds a creature hunts after it last noticed the player or was hit.")
(defparameter *look-interval* 0.25 "Seconds between a creature's looks for the player.")
(defparameter *chase-replan* 0.5 "Seconds between a hunting creature's fresh paths to the player.")
(defparameter *chase-pause* 0.1 "Seconds a hunting creature stands at the end of a path before the next.")
(defparameter *chase-max-walk* 25.0
  "Longest path, in metres, a creature takes to reach the player. A room above or below
is a long walk round by the stairs.")
(defparameter *retreat-step* 3.0 "Metres a ranged creature backs off at a time when the player is too close.")
(defparameter *cast-aim-height* 1.1 "Height above the player's feet a creature's spell is aimed at.")
(defparameter *block-time* 0.3 "Seconds a shielded creature shows its block pose after a spell hits the shield.")
(defparameter *block-hit-stop* 0.04 "Seconds of hit-stop when a spell hits a shield.")
(defparameter *attack-start-reach* 0.5
  "Fraction of its ATTACK-REACH within which a creature starts an attack. The rest
leaves the player room to back out of the blow during the wind-up.")

(defvar *hit-stop* 0.0 "Seconds of hit-stop left. While positive, nothing in the world moves.")
(defvar *creatures* (make-array 0 :adjustable T :fill-pointer T)
  "Creatures in the level, for hit tests. The level rebuilds it.")

(defvar *player* NIL "The player in the current scene.")

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
   (step-height :initarg :step-height :initform 0.45 :accessor step-height
                :documentation "Tallest ledge it walks up or down; the player's is *STEP-HEIGHT*.")
   (walk-speed :initarg :walk-speed :initform 1.4 :accessor walk-speed :documentation "Metres per second.")
   (wander-radius :initarg :wander-radius :initform 4.0 :accessor wander-radius
                  :documentation "How far from home, in metres, it wanders to random spots.")
   (chase-speed :initarg :chase-speed :initform NIL :accessor chase-speed
                :documentation "Metres per second while hunting; NIL for WALK-SPEED.")
   (turn-speed :initarg :turn-speed :initform NIL :accessor turn-speed
               :documentation "Radians per second it turns; NIL to turn at once. A slow turner
can be got behind.")
   (knockback-scale :initarg :knockback-scale :initform 1.0 :accessor knockback-scale
                    :documentation "How far blows knock it back, 1 for the usual distance.")
   (shield-views :initarg :shield-views :initform NIL :accessor shield-views
                 :documentation "The last billboard view (0 front .. 4 back) its shield covers: a
spell coming from where that view or a nearer one is seen is deflected (spells.lisp). NIL
for no shield.")
   (shield-reflects :initarg :shield-reflects :initform T :accessor shield-reflects
                    :documentation "True if its shield sends spells back the way they came; NIL to stop them.")
   (block-animation :initarg :block-animation :initform NIL :accessor block-animation
                    :documentation "Frame animation of the block pose, one sequence per view like
WALK-ANIMATION, spread over *BLOCK-TIME*; NIL to show nothing.")
   (brace :initform 0.0 :accessor brace :documentation "Seconds left of the block pose.")
   (brain :initform :idle :accessor brain
          :documentation ":IDLE (standing), :WALKING along PATH or :ATTACKING.")
   (alert :initform 0.0 :accessor alert
          :documentation "Seconds it keeps hunting the player; it wanders at 0.")
   (look-timer :initform 0.0 :accessor look-timer :documentation "Seconds until it next looks for the player.")
   (replan-timer :initform 0.0 :accessor replan-timer :documentation "Seconds until a hunt plans a fresh path.")
   (attack-damage :initarg :attack-damage :initform NIL :accessor attack-damage
                  :documentation "Least and most health a blow takes; NIL for a creature without a melee attack.")
   (attack-spell :initarg :attack-spell :initform NIL :accessor attack-spell
                 :documentation "Spell it casts at the player instead of a blow, or NIL. Its
attack releases the spell on ATTACK-HIT-FRAME.")
   (attack-range :initarg :attack-range :initform 10.0 :accessor attack-range
                 :documentation "Metres within which a caster starts casting at a player it can see.")
   (keep-away :initarg :keep-away :initform 4.0 :accessor keep-away
              :documentation "Metres a caster backs off to keep between itself and the player.")
   (cast-offset :initarg :cast-offset :initform 0.0 :accessor cast-offset
                :documentation "Metres to its right of its centre line that its spell leaves
from: where the casting hand is on the release frame.")
   (attack-reach :initarg :attack-reach :initform 0.6 :accessor attack-reach
                 :documentation "Metres from its body's edge to the player's that a blow reaches.")
   (attack-arc :initarg :attack-arc :initform 0.8 :accessor attack-arc
               :documentation "Radians either side of its facing that a blow reaches.")
   (attack-frame-times :initarg :attack-frame-times :initform '(0.4 0.1 0.25 0.3) :accessor attack-frame-times
                       :documentation "Seconds each attack animation frame shows.")
   (attack-hit-frame :initarg :attack-hit-frame :initform 2 :accessor attack-hit-frame
                     :documentation "Frame (from 0) on which the blow lands.")
   (attack-pause :initarg :attack-pause :initform 0.5 :accessor attack-pause
                 :documentation "Seconds it stands after an attack before the next move.")
   (attack-animation :initarg :attack-animation :initform NIL :accessor attack-animation
                     :documentation "Frame animation of the attack, one sequence per view like
WALK-ANIMATION; NIL to attack in the standing pose.")
   (attack-time :initform NIL :accessor attack-time :documentation "Seconds into the attack, or NIL.")
   (attack-pending :initform NIL :accessor attack-pending :documentation "True until the attack's blow has landed.")
   (idle-timer :initform (wander-pause) :accessor idle-timer :documentation "Seconds left standing.")
   (path :initform () :accessor path :documentation "Points still to walk to, nearest first.")
   (stuck :initform 0.0 :accessor stuck :documentation "Seconds its walk has been blocked.")
   (walk-distance :initform 0.0 :accessor walk-distance
                  :documentation "Metres walked so far; picks the walk animation's frame.")
   (walk-animation :initarg :walk-animation :initform NIL :accessor walk-animation
                   :documentation "Frame animation of the walk: one cycle per view, in the
billboard's view order. NIL to glide in the standing pose.")
   (stride :initarg :stride :initform 0.35 :accessor stride
           :documentation "Metres walked per walk animation frame.")
   (hurt-animation :initarg :hurt-animation :initform NIL :accessor hurt-animation
                   :documentation "Frame animation of the flinch, one sequence per view like
WALK-ANIMATION, spread over *STAGGER-TIME*; NIL to squash the standing pose instead.")
   (knockback :initform (vec 0 0 0) :reader knockback)
   (stagger :initform 0.0 :accessor stagger)
   (flash :initform 0.0 :accessor flash)
   (dead :initform NIL :accessor dead :documentation "Seconds since death, or NIL while alive.")
   (death-animation :initarg :death-animation :initform NIL :accessor death-animation
                    :documentation "Frame animation played once on death, its last frame the
corpse; NIL to collapse into the floor instead.")
   (death-glow :initarg :death-glow :initform NIL :reader death-glow
               :documentation "Colour of the light a burning death gives off, or NIL for none.")
   (death-glow-radius :initarg :death-glow-radius :initform 3.0 :reader death-glow-radius)
   (death-glow-times :initarg :death-glow-times :initform '(0.1 0.2 0.4 0.8) :reader death-glow-times
                     :documentation "Seconds into the death that the glow starts, is at full
strength, starts to fade and is out, to match the fire in the death animation.")
   (death-lamp :initform NIL :accessor death-lamp :documentation "The lamp lit while its death glows.")
   (bleeds :initarg :bleeds :initform T :reader bleeds :documentation "True if a hit sprays blood (gore.lisp).")
   (death-blood :initarg :death-blood :initform NIL :reader death-blood
                :documentation "Drops of blood its death bursts out; NIL for *DEATH-BLOOD*. At 0
its corpse doesn't bleed either.")
   (bleeding :initform 0f0 :accessor bleeding :documentation "Seconds it keeps dripping blood.")
   (gibs :initarg :gibs :initform NIL :reader gibs
         :documentation "What a blow that overkills it tears it into (gore.lisp): its gib set's
name in the blood strip, then a piece number for each gib. NIL never tears apart.")
   (gibbed :initform NIL :accessor gibbed :documentation "True while it lies torn apart.")
   (drip-timer :initform 0f0 :accessor drip-timer :documentation "Seconds until its next drip.")
   (body-texture :reader body-texture :documentation "The standing atlas texture, for when it isn't walking or dying.")
   (home :reader home)
   (base-scaling :reader base-scaling)))

(defmethod initialize-instance :after ((creature creature) &key)
  (setf (health creature) (max-health creature))
  (setf (slot-value creature 'home) (vcopy (location creature)))
  (setf (slot-value creature 'body-texture) (texture creature))
  (setf (slot-value creature 'base-scaling) (vcopy (scaling creature))))

;; Only the current texture gets loaded with the scene; the other strips have to be too.
(defmethod stage :after ((creature creature) (area staging-area))
  (dolist (name (list (death-animation creature) (walk-animation creature) (attack-animation creature)
                    (hurt-animation creature) (block-animation creature)))
    (when name
      (stage (animation-texture (find-fx-animation name)) area))))

(defun wander-pause ()
  (destructuring-bind (lo hi) *wander-pause*
    (+ lo (random (float (- hi lo) 0f0)))))

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

(defun creature-at (point margin &optional ignore)
  "The first live creature other than IGNORE whose body contains POINT, grown by MARGIN
metres, or NIL."
  (loop for c across *creatures*
        for loc = (location c)
        for r = (+ (body-radius c) margin)
        when (and (not (dead c))
                  (not (eq c ignore))
                  (< (+ (expt (- (vx point) (vx loc)) 2) (expt (- (vz point) (vz loc)) 2)) (* r r))
                  (< (- (vy loc) margin) (vy point) (+ (vy loc) (sprite-height c) margin)))
          return c))

;;; Bodies: the player and live creatures block each other, as upright boxes like the
;;; solids. Corpses don't. Bodies move, so they aren't in *SOLIDS*, and the nav grid
;;; ignores them.

(defgeneric body-feet (thing) (:documentation "The bottom centre of THING's box."))
(defgeneric body-height (thing))
(defgeneric body-solid-p (thing) (:documentation "True while THING blocks other bodies."))

(defmethod body-feet ((creature creature)) (location creature))
(defmethod body-height ((creature creature)) (sprite-height creature))
(defmethod body-solid-p ((creature creature)) (not (dead creature)))

(defvar *body-box* (make-array 6 :element-type 'single-float)
  "The box BODY-OVERLAPPING returns, reused by every call.")

(defun body-overlapping (x y z half-width height &optional ignore)
  "The first body other than IGNORE overlapped by an upright box standing at X Y Z,
HALF-WIDTH out from its centre line and HEIGHT tall, or NIL. Returns its box, like a
solid's (*BODY-BOX*, good until the next call), and the body."
  (flet ((hit (thing)
           (when (and thing (not (eq thing ignore)) (body-solid-p thing))
             (let ((feet (body-feet thing))
                   (r (float (body-radius thing) 0f0))
                   (box *body-box*))
               (setf (aref box 0) (- (vx feet) r) (aref box 1) (vy feet) (aref box 2) (- (vz feet) r)
                     (aref box 3) (+ (vx feet) r) (aref box 5) (+ (vz feet) r)
                     (aref box 4) (+ (vy feet) (float (body-height thing) 0f0)))
               (box-overlaps-p box x y z half-width height)))))
    (cond ((hit *player*) (values *body-box* *player*))
          (T (loop for c across *creatures*
                   when (hit c) return (values *body-box* c))))))

(defun creature-body-overlapping (creature)
  "The first other body CREATURE overlaps where it stands, as for BODY-OVERLAPPING."
  (let ((loc (location creature)))
    (body-overlapping (vx loc) (+ (vy loc) 0.05) (vz loc)
                      (float (body-radius creature) 0f0) (- (float (sprite-height creature) 0f0) 0.05)
                      creature)))

(defun move-creature (creature dx dz lift)
  "Move CREATURE by DX, DZ, one axis at a time, each step undone if it runs into a solid
(ignoring the LIFT metres above its feet: steps it can climb) or another body. Returns
whether the X move and whether the Z move were blocked."
  (let* ((loc (location creature))
         (r (float (body-radius creature) 0f0))
         (h (float (sprite-height creature) 0f0))
         ;; Already inside a body (revived under the player, say): let it walk out.
         (bodies (not (creature-body-overlapping creature))))
    (flet ((blocked ()
             (or (solid-overlapping (vx loc) (+ (vy loc) lift) (vz loc) r (- h lift))
                 (and bodies (creature-body-overlapping creature)))))
      (values (unless (= 0 dx)
                (let ((old (vx loc)))
                  (incf (vx loc) dx)
                  (when (blocked) (setf (vx loc) old) T)))
              (unless (= 0 dz)
                (let ((old (vz loc)))
                  (incf (vz loc) dz)
                  (when (blocked) (setf (vz loc) old) T)))))))

(defun hurt (creature amount &key from)
  "Take AMOUNT health from CREATURE with the full hit reaction, struck from point FROM
(NIL: from the player), which the blood sprays away from."
  (unless (dead creature)
    (decf (health creature) amount)
    (when (bleeds creature)
      (bleed creature amount from))
    (setf (flash creature) *flash-time*
          (stagger creature) *stagger-time*
          (alert creature) *alert-time*)
    ;; Stop (a hit breaks off an attack too), and plan afresh once the flinch is over:
    ;; knockback moves it off its path.
    (stop-walking creature *hurt-pause*)
    (hit-stop)
    (when (<= (health creature) 0)
      (cond ((gib-p creature amount)
             (setf (gibbed creature) T)
             (burst-gibs creature from))
            ((bleeds creature)
             (bleed-out creature)))
      (setf (dead creature) 0.0))))

(defun shielded-p (creature from)
  "True if CREATURE's shield covers it against a blow from point FROM: the view of it
seen from FROM is one its shield covers."
  (and (shield-views creature)
       (not (dead creature))
       (<= (billboard-view creature from) (shield-views creature))))

(defun block-hit (creature)
  "React to a spell striking CREATURE's shield: no damage, a faint flash, the block pose
and a moment's brace, unless it's in the middle of an attack."
  (setf (flash creature) (max (flash creature) (* 0.4 *flash-time*))
        (alert creature) *alert-time*)
  (unless (eq (brain creature) :attacking)
    (setf (brace creature) *block-time*)
    (stop-walking creature *block-time*))
  (hit-stop *block-hit-stop*))

(defun push-creature (creature direction speed)
  "Knock CREATURE along DIRECTION (only its horizontal part counts) at SPEED m/s, scaled
by its KNOCKBACK-SCALE."
  (let ((len (/ (sqrt (+ (expt (vx direction) 2) (expt (vz direction) 2)))
                (float (knockback-scale creature) 0f0)))
        (kb (knockback creature)))
    (when (< 1f-4 len)
      (setf (vx kb) (* speed (/ (vx direction) len))
            (vz kb) (* speed (/ (vz direction) len))))))

(defun slide (creature dt)
  "Apply knockback for DT seconds, stopping at solids and bodies, then slow it by friction."
  (let ((kb (knockback creature)))
    (multiple-value-bind (x-blocked z-blocked) (move-creature creature (* (vx kb) dt) (* (vz kb) dt) 0.05)
      (when x-blocked (setf (vx kb) 0.0))
      (when z-blocked (setf (vz kb) 0.0)))
    (let* ((speed (sqrt (+ (expt (vx kb) 2) (expt (vz kb) 2))))
           (slower (max 0.0 (- speed (* *knockback-friction* dt)))))
      (if (< speed 1f-4)
          (setf (vx kb) 0.0 (vz kb) 0.0)
          (setf (vx kb) (* (vx kb) (/ slower speed)) (vz kb) (* (vz kb) (/ slower speed)))))))

(defun attacker-p (creature)
  (or (attack-damage creature) (attack-spell creature)))

(defun hunting-p (creature)
  (and (attacker-p creature) (< 0 (alert creature))))

(defun stop-walking (creature &optional (pause (if (hunting-p creature) *chase-pause* (wander-pause))))
  "Stand still, walking or attacking, for PAUSE seconds."
  (setf (brain creature) :idle
        (path creature) ()
        (stuck creature) 0.0
        (attack-time creature) NIL
        (idle-timer creature) pause))

(defun walk-path (creature dt)
  "Walk DT seconds toward the next point of the path, facing the way it goes. Blocked
by a body it slides along it; blocked for *STUCK-TIME*, it gives up the path."
  (let* ((loc (location creature))
         (target (first (path creature)))
         (dx (- (vx target) (vx loc)))
         (dz (- (vz target) (vz loc)))
         (distance (sqrt (+ (* dx dx) (* dz dz))))
         (speed (if (hunting-p creature) (or (chase-speed creature) (walk-speed creature)) (walk-speed creature)))
         (step (min distance (* speed dt)))
         (x0 (vx loc))
         (z0 (vz loc)))
    (when (< 1f-4 distance)
      (turn-to creature (atan dx (- dz)) dt)
      (move-creature creature (* step (/ dx distance)) (* step (/ dz distance)) (step-height creature)))
    (let ((moved (sqrt (+ (expt (- (vx loc) x0) 2) (expt (- (vz loc) z0) 2)))))
      (incf (walk-distance creature) moved)
      (setf (stuck creature) (if (< moved (* 0.25 step)) (+ (stuck creature) dt) 0.0))
      (cond ((< (+ (expt (- (vx target) (vx loc)) 2) (expt (- (vz target) (vz loc)) 2)) 1f-6)
             (unless (setf (path creature) (rest (path creature)))
               (stop-walking creature)))
            ((< *stuck-time* (stuck creature))
             (stop-walking creature *stuck-pause*))))))

(defun plan-wander (creature)
  "Set off for a random spot it can reach within WANDER-RADIUS of home."
  (let* ((loc (location creature))
         (path (flet ((spot (around)
                        (nav-reachable-spot loc (body-radius creature) (sprite-height creature)
                                            (step-height creature)
                                            :around around :within (wander-radius creature))))
                 ;; Somewhere near home; if it got pushed too far for that, near itself.
                 (or (spot (home creature)) (spot loc)))))
    (if path
        (setf (path creature) path
              (brain creature) :walking)
        (setf (idle-timer creature) (wander-pause)))))

;;; Hunting: a creature that can attack notices the player in front of it within
;;; *SIGHT-RANGE* (or close behind it), and when hit. While alert it chases the player
;;; along the nav grid and attacks within reach; the blow lands on ATTACK-HIT-FRAME if
;;; the player is still in reach and in front of it. A caster (ATTACK-SPELL) instead
;;; stops to cast within ATTACK-RANGE wherever it has a clear line to the player, and
;;; backs off when the player comes within KEEP-AWAY.

(defun player-within-p (creature reach)
  "True if the player's body is within REACH metres of CREATURE's, and level with it."
  (let* ((loc (location creature))
         (feet (feet *player*))
         (dx (- (vx feet) (vx loc)))
         (dz (- (vz feet) (vz loc)))
         (r (+ (body-radius creature) *player-radius* reach)))
    (and (< (+ (* dx dx) (* dz dz)) (* r r))
         (< (vy feet) (+ (vy loc) (sprite-height creature)))
         (< (vy loc) (+ (vy feet) *player-height*)))))

(defun player-angle (creature)
  "Radians between the way CREATURE faces and the direction to the player."
  (let* ((loc (location creature))
         (feet (feet *player*))
         (dx (- (vx feet) (vx loc)))
         (dz (- (vz feet) (vz loc)))
         (distance (sqrt (+ (* dx dx) (* dz dz)))))
    (if (< distance 1f-4)
        0.0
        (acos (max -1.0 (min 1.0 (/ (+ (* dx (sin (facing creature))) (* dz (- (cos (facing creature))))) distance)))))))

(defun turn-to (creature yaw dt)
  "Turn CREATURE toward YAW, at once or, with a TURN-SPEED, by as much as DT seconds allow."
  (let ((rate (turn-speed creature)))
    (setf (facing creature)
          (float (if rate
                     ;; The short way round, kept within -pi..pi so it doesn't wind up.
                     (let* ((now (facing creature))
                            (diff (- (mod (+ (- yaw now) pi) (* 2 pi)) pi))
                            (most (* rate dt)))
                       (- (mod (+ now (max (- most) (min most diff)) pi) (* 2 pi)) pi))
                     yaw)
                 0f0))))

(defun face-player (creature &optional (dt 0.0))
  "Turn CREATURE toward the player: at once, or for a slow turner, DT seconds' worth."
  (let ((loc (location creature))
        (feet (feet *player*)))
    (turn-to creature (atan (- (vx feet) (vx loc)) (- (vz loc) (vz feet))) dt)))

(defun sees-player-p (creature)
  (let* ((loc (location creature))
         (feet (feet *player*))
         (distance (sqrt (+ (expt (- (vx feet) (vx loc)) 2) (expt (- (vz feet) (vz loc)) 2)))))
    (and (< 0 (health *player*))
         (< (abs (- (vy feet) (vy loc))) 3.0)
         (or (< distance *hearing-range*)
             (and (< distance *sight-range*)
                  (< (player-angle creature) #.(float (/ pi 2) 0f0))))
         (clear-path-p loc feet (* 0.8 (sprite-height creature))))))

(defun notice-player (creature dt)
  (setf (alert creature) (max 0.0 (- (alert creature) dt)))
  (when (<= (decf (look-timer creature) dt) 0)
    (setf (look-timer creature) *look-interval*)
    (when (sees-player-p creature)
      (when (<= (alert creature) 0)
        ;; Just noticed: cut a wander's pause short, and turn a wander's walk into a chase.
        (setf (idle-timer creature) (min (idle-timer creature) *chase-pause*)
              (replan-timer creature) 0.0))
      (setf (alert creature) *alert-time*))))

(defun chase-path (creature)
  "A path to the player: straight at them when nothing is in the way, else along the nav grid."
  (let ((loc (location creature))
        (feet (feet *player*))
        (r (body-radius creature))
        (h (sprite-height creature))
        (step (step-height creature)))
    (when *nav-grid*
      (if (nav-line-clear-p loc feet r h step)
          (list (vcopy feet))
          (nav-path-to loc feet r h step :max-walk *chase-max-walk*)))))

(defun start-attack (creature)
  (face-player creature)
  (setf (brain creature) :attacking
        (path creature) ()
        (attack-time creature) 0.0
        (attack-pending creature) T))

(defun chase (creature)
  "Set off along a fresh path toward the player."
  (let ((route (chase-path creature)))
    (setf (replan-timer creature) *chase-replan*)
    (if route
        (setf (path creature) route
              (brain creature) :walking)
        (stop-walking creature *chase-replan*))))

(defun player-distance (creature)
  (let ((loc (location creature))
        (feet (feet *player*)))
    (sqrt (+ (expt (- (vx feet) (vx loc)) 2) (expt (- (vz feet) (vz loc)) 2)))))

(defun cast-height (creature)
  "Height above its feet that CREATURE casts from."
  (* 0.7 (sprite-height creature)))

(defun retreat (creature)
  "Walk *RETREAT-STEP* metres away from the player, or as near away as the nav grid
allows a straight walk. Returns NIL if every way back is blocked."
  (let* ((loc (location creature))
         (feet (feet *player*))
         (away (atan (- (vx loc) (vx feet)) (- (vz feet) (vz loc)))))
    (when *nav-grid*
      (loop for turn in '(0.0 0.6 -0.6 1.2 -1.2)
            for yaw = (+ away turn)
            for to = (vec (+ (vx loc) (* *retreat-step* (sin yaw))) (vy loc)
                          (- (vz loc) (* *retreat-step* (cos yaw))))
            when (nav-line-clear-p loc to (body-radius creature) (sprite-height creature) (step-height creature))
              do (setf (path creature) (list to)
                       (brain creature) :walking
                       (replan-timer creature) *chase-replan*)
                 (return T)))))

(defun hunt-from-range (creature)
  "Back off from a player too close, cast at one in range and in sight, else close in."
  (let ((distance (player-distance creature)))
    (cond ((and (< distance (keep-away creature)) (retreat creature)))
          ((and (< distance (attack-range creature))
                (clear-path-p (location creature) (feet *player*) (cast-height creature)))
           (start-attack creature))
          (T (chase creature)))))

(defun hunt (creature)
  "Attack the player if within reach, or set off along a fresh path toward them."
  (cond ((attack-spell creature) (hunt-from-range creature))
        ((player-within-p creature (* *attack-start-reach* (attack-reach creature)))
         (start-attack creature))
        (T (chase creature))))

(defun attack-hit-time (creature)
  (loop for time in (attack-frame-times creature)
        repeat (attack-hit-frame creature)
        sum time))

(defun attack-frame (creature)
  "The attack animation frame showing ATTACK-TIME seconds in."
  (loop with end = 0.0
        for time in (attack-frame-times creature)
        for frame from 0
        do (incf end time)
        when (< (attack-time creature) end)
          return frame
        finally (return frame)))

(defun release-attack-spell (creature)
  "Cast CREATURE's ATTACK-SPELL from in front of it at where the player stands now."
  (let* ((loc (location creature))
         (feet (feet *player*))
         (out (+ (body-radius creature) 0.15))
         (side (cast-offset creature))
         (yaw (facing creature))
         ;; Forward is (sin, -cos) of the facing, its right (cos, sin).
         (origin (vec (+ (vx loc) (* out (sin yaw)) (* side (cos yaw)))
                      (+ (vy loc) (cast-height creature))
                      (+ (vz loc) (- (* out (cos yaw))) (* side (sin yaw)))))
         (aim (v- (vec (vx feet) (+ (vy feet) *cast-aim-height*) (vz feet)) origin)))
    (when (< 1f-4 (vlength aim))
      (cast-spell (find-spell (attack-spell creature)) origin (nvunit aim) (container creature)
                  :caster creature))))

(defun attack (creature dt)
  (let ((time (incf (attack-time creature) dt))
        (times (attack-frame-times creature)))
    ;; It turns to follow the player through the wind-up (a caster, until it casts);
    ;; after that the blow is committed.
    (when (< time (if (attack-spell creature) (attack-hit-time creature) (first times)))
      (face-player creature dt))
    (when (and (attack-pending creature) (<= (attack-hit-time creature) time))
      (setf (attack-pending creature) NIL)
      (cond ((attack-spell creature)
             (release-attack-spell creature))
            ((and (player-within-p creature (attack-reach creature))
                  (< (player-angle creature) (attack-arc creature))
                  (clear-path-p (location creature) (feet *player*) 1.0))
             (hurt-player *player* (roll (attack-damage creature)) (location creature)))))
    (when (<= (reduce #'+ times) time)
      (stop-walking creature (attack-pause creature)))))

(defun think (creature dt)
  "Hunt the player while alert, wander otherwise."
  (when (attacker-p creature)
    (notice-player creature dt))
  (let ((hunting (hunting-p creature)))
    (ecase (brain creature)
      (:attacking
       (attack creature dt))
      (:idle
       (when hunting
         (face-player creature dt))
       (when (<= (decf (idle-timer creature) dt) 0)
         (if hunting (hunt creature) (plan-wander creature))))
      (:walking
       (cond ((and hunting (not (attack-spell creature))
                   (player-within-p creature (* *attack-start-reach* (attack-reach creature))))
              (start-attack creature))
             (T
              (when (and hunting (<= (decf (replan-timer creature) dt) 0))
                (hunt creature))
              (when (eq (brain creature) :walking)
                (walk-path creature dt))))))))

(defun settle (creature dt)
  "Ease CREATURE up or down to the floor under it: steps, and knockback off a ledge.
It only sinks while its body has room below, so it never sinks into a ledge it overhangs."
  (let* ((loc (location creature))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
    (when floor
      (let* ((most (* *settle-speed* dt))
             (y (+ (vy loc) (max (- most) (min most (- floor (vy loc)))))))
        (when (or (<= (vy loc) y)
                  (fits-at-p (vx loc) y (vz loc) (body-radius creature) (sprite-height creature)))
          (setf (vy loc) y))))))

(defun revive (creature)
  (setf (alert creature) 0.0
        (bleeding creature) 0f0
        (gibbed creature) NIL)
  (stop-walking creature)
  (setf (walk-distance creature) 0.0)
  (setf (dead creature) NIL
        (health creature) (max-health creature)
        (stagger creature) 0.0
        (brace creature) 0.0
        (flash creature) 0.0
        (texture creature) (body-texture creature))
  (v<- (location creature) (home creature))
  (let ((kb (knockback creature)))
    (setf (vx kb) 0.0 (vz kb) 0.0)))

(defun creature-walking-p (creature)
  (and (eq (brain creature) :walking) (not (dead creature)) (walk-animation creature)))

(defun creature-hurting-p (creature)
  (and (< 0 (stagger creature)) (not (dead creature)) (hurt-animation creature)))

;; The block strip only has the views the shield covers: a deflected spell comes from
;; one of them. Seen from elsewhere, it braces in the standing pose.
(defun creature-blocking-p (creature)
  (and (< 0 (brace creature)) (not (dead creature)) (block-animation creature)
       (<= (view-index creature) (shield-views creature))))

(defun creature-attacking-p (creature)
  (and (eq (brain creature) :attacking) (not (dead creature)) (attack-animation creature)))

(defun show-view-frame (creature name frame squash &optional (views (length (getf (atlas creature) :views))))
  "Show FRAME of the view the billboard tick picked, from animation NAME: one sequence
per view, in the turnaround's view order, for the first VIEWS views. SQUASH is the
flinch, 0 to 1."
  (let* ((animation (find-fx-animation name))
         (atlas (animation-atlas animation))
         (count (getf atlas :frames))
         (cycle (floor count views))
         (h (animation-size animation))
         (scale (scaling creature)))
    (setf (texture creature) (animation-texture animation))
    (strip-uv (frame-uv creature) atlas (+ (* (view-index creature) cycle) (mod frame cycle))
              count (mirrored creature))
    (setf (vx scale) (* h (/ (getf atlas :cell-width) (getf atlas :cell-height)) (+ 1 (* squash *stagger-squash* 0.7)))
          (vy scale) (* h (- 1 (* squash *stagger-squash*))))))

(defun update-creature-look (creature)
  "Set texture, frame, tint and scaling from walking, attacking, flash, stagger and death."
  (let ((tint (tint creature))
        (base (base-scaling creature))
        (scale (scaling creature))
        (f (/ (flash creature) *flash-time*))
        (s (/ (stagger creature) *stagger-time*)))
    (setf (vx tint) (vx *flash-color*) (vy tint) (vy *flash-color*) (vz tint) (vz *flash-color*)
          (vw tint) (* f (vw *flash-color*)))
    (setf (texture creature) (body-texture creature))
    (setf (vx scale) (* (vx base) (+ 1 (* s *stagger-squash* 0.7)))
          (vy scale) (* (vy base) (- 1 (* s *stagger-squash*)))
          (vz scale) (vz base))
    (cond ((creature-hurting-p creature)
           ;; The frames carry the flinch, so no squash on top.
           (let ((frames (floor (getf (animation-atlas (find-fx-animation (hurt-animation creature))) :frames)
                                (length (getf (atlas creature) :views)))))
             (show-view-frame creature (hurt-animation creature)
                              (min (1- frames) (floor (* (- 1 s) frames))) 0.0)))
          ((and (creature-blocking-p creature) (not (creature-attacking-p creature)))
           (let* ((views (1+ (shield-views creature)))
                  (frames (floor (getf (animation-atlas (find-fx-animation (block-animation creature))) :frames)
                                 views)))
             (show-view-frame creature (block-animation creature)
                              (min (1- frames) (floor (* (- 1 (/ (brace creature) *block-time*)) frames))) 0.0
                              views)))
          ((creature-attacking-p creature)
           (show-view-frame creature (attack-animation creature) (attack-frame creature) s))
          ((creature-walking-p creature)
           ;; The frame follows the distance walked, so feet don't skate.
           (show-view-frame creature (walk-animation creature)
                            (floor (walk-distance creature) (stride creature)) s)))
    (let ((d (dead creature)))
      (cond ((null d))
            ((gibbed creature)
             ;; Its pieces are in the blood pool; nothing of it stays.
             (setf (vx scale) 0.0 (vy scale) 0.0))
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

;;; A burning death lights its surroundings: a lamp that comes up with the fire, fades
;;; with it and is then taken out of *LAMPS*, since a corpse never leaves the scene.

(defparameter *death-glow-flicker* 0.25)

(defun death-glow-strength (creature)
  "How bright CREATURE's death glow is now, 0 to 1."
  (let ((d (dead creature)))
    (if (or (null d) (null (death-glow creature)))
        0.0
        (destructuring-bind (start full fade out) (death-glow-times creature)
          (cond ((<= d start) 0.0)
                ((< d full) (/ (- d start) (- full start)))
                ((<= d fade) 1.0)
                ((< d out) (/ (- out d) (- out fade)))
                (T 0.0))))))

(defun update-death-glow (creature)
  (let ((k (death-glow-strength creature))
        (lamp (death-lamp creature)))
    (cond ((< 0 k)
           ;; A level rebuild empties *LAMPS* under it.
           (unless (and lamp (find lamp *lamps*))
             (setf lamp (add-lamp (location creature) (death-glow creature) (death-glow-radius creature)
                                  :flicker *death-glow-flicker*)
                   (death-lamp creature) lamp))
           (let ((at (location lamp))
                 (loc (location creature))
                 (color (color lamp))
                 (glow (death-glow creature)))
             (setf (vx at) (vx loc) (vy at) (+ (vy loc) (* 0.5 (sprite-height creature))) (vz at) (vz loc))
             (setf (vx color) (* k (vx glow)) (vy color) (* k (vy glow)) (vz color) (* k (vz glow)))))
          (lamp
           (let ((at (position lamp *lamps*)))
             (when at
               (replace *lamps* *lamps* :start1 at :start2 (1+ at))
               (decf (fill-pointer *lamps*))))
           (setf (death-lamp creature) NIL)))))

;; :AFTER so BILLBOARD's tick handler (view selection) still runs.
(define-handler (creature tick :after) (dt)
  (unless (frozen-p)
    (let ((dt (min dt 0.05)))
      (setf (flash creature) (max 0.0 (- (flash creature) dt))
            (stagger creature) (max 0.0 (- (stagger creature) dt))
            (brace creature) (max 0.0 (- (brace creature) dt)))
      (slide creature dt)
      (drip-blood creature dt)
      (unless (dead creature)
        (when (<= (stagger creature) 0)
          (think creature dt))
        (settle creature dt))
      (when (dead creature)
        (incf (dead creature) dt)
        (when (and *revive-time* (< (+ (death-duration creature) *revive-time*) (dead creature))
                   ;; Wait for whoever stands on its spawn point to move.
                   (let ((home (home creature)))
                     (not (body-overlapping (vx home) (+ (vy home) 0.05) (vz home)
                                            (float (body-radius creature) 0f0)
                                            (- (float (sprite-height creature) 0f0) 0.05)
                                            creature))))
          (revive creature)))))
  (update-creature-look creature)
  (update-death-glow creature))

;;; The imp.

(defparameter *imp-height* 1.5
  "Imp height in metres, horns to feet. The player's eye is at 1.6.")

;; Sliced so the standing imp in its first frame is as tall as a turnaround cell.
(define-fx-animation imp-death "sprites/imp/death" :fps 10 :size *imp-height*)
;; Four frames per view, every view scaled to a turnaround cell's height. The frame
;; follows the distance walked (STRIDE), so :FPS is unused.
(define-fx-animation imp-walk "sprites/imp/walk" :loop T :size *imp-height*)
;; The claw swipe: wind-up, lunge, strike, recover, four frames per view. Its cells are
;; 110 px tall to fit the raised claw, with the standing imp 96 px like the walk's.
;; The frames run on the imp's ATTACK-FRAME-TIMES, so :FPS is unused.
(define-fx-animation imp-attack "sprites/imp/attack" :size (* *imp-height* 110/96))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*. Its cells
;; are 80 px tall, the buckled jolt at the walk's scale (standing imp 96 px).
(define-fx-animation imp-hurt "sprites/imp/hurt" :size (* *imp-height* 80/96))

(define-shader-entity imp (creature)
  ((texture :initform (// 'hexmaw 'imp-turnaround))
   (atlas :initform (read-atlas "data/sprites/imp/turnaround.lisp"))
   (sprite-height :initform *imp-height*)
   (death-animation :initform 'imp-death)
   (walk-animation :initform 'imp-walk)
   (attack-animation :initform 'imp-attack)
   (hurt-animation :initform 'imp-hurt)
   ;; Head, two arms, two legs, the tail, ribs, a big chunk, two chunks, two scraps.
   (gibs :initform '(:imp 0 1 1 2 2 3 4 5 6 6 7 7))
   (attack-damage :initform '(6 10))
   (chase-speed :initform 2.6)
   (max-health :initform 30)))

;;; The acolyte: a robed caster that keeps its distance and throws cinders (spells.lisp).
;;; It has no walk: it glides in the standing pose, the robe hiding its feet.

(defparameter *acolyte-height* 1.8 "Acolyte height in metres, cowl tip to hem.")

;; Sliced at 115 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw acolyte-turnaround) image
    #p"sprites/acolyte/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; The cast: wind-up (a flame kindles in the hand), raised hand (a fireball held beside
;; the cowl), release, recover; four frames per view. Its cells are 125 px tall to fit
;; the fire, with the standing acolyte 115 px like the turnaround. The frames run on
;; ATTACK-FRAME-TIMES, so :FPS is unused.
(define-fx-animation acolyte-cast "sprites/acolyte/cast" :size (* *acolyte-height* 125/115))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*. Its cells
;; are 116 px tall, at the turnaround's scale.
(define-fx-animation acolyte-hurt "sprites/acolyte/hurt" :size (* *acolyte-height* 116/115))
;; The fire inside burns it away, leaving the empty robe as the corpse. Its cells are
;; 133 px tall to fit the flames, the jolted acolyte in frame 1 115 px.
(define-fx-animation acolyte-death "sprites/acolyte/death" :fps 10 :size (* *acolyte-height* 133/115))

(define-shader-entity acolyte (creature)
  ((texture :initform (// 'hexmaw 'acolyte-turnaround))
   (atlas :initform (read-atlas "data/sprites/acolyte/turnaround.lisp"))
   (sprite-height :initform *acolyte-height*)
   (attack-animation :initform 'acolyte-cast)
   (hurt-animation :initform 'acolyte-hurt)
   (death-animation :initform 'acolyte-death)
   ;; Up with the fire bursting out (frame 2), fading as the robe burns down (frames 5 to 8).
   (death-glow :initform (vec 1.4 0.55 0.2))
   ;; It burns from inside rather than bleeding out.
   (death-blood :initform 0)
   (attack-spell :initform 'cinder)
   (attack-range :initform 12.0)
   (keep-away :initform 4.0)
   (cast-offset :initform 0.25)
   ;; The fireball is held up longest, as the warning; it leaves on the release frame.
   (attack-frame-times :initform '(0.35 0.4 0.3 0.3))
   (attack-pause :initform 1.2)
   (walk-speed :initform 1.2)
   (chase-speed :initform 1.8)
   (wander-radius :initform 2.0)
   (max-health :initform 24)))

;;; The knight: slow, in heavy plate, behind a tower shield from its feet to its helm.
;;; The shield turns spells away from the front and front-quarter views (and reflects
;;; them back), so the player gets behind it, where it turns only slowly, or closes in
;;; with the sword, which the shield doesn't stop.

(defparameter *knight-height* 1.95 "Knight height in metres, helm to sabatons, about the shield's height.")

;; Sliced at 125 px tall, so its art pixels are the imp's size (96 px for 1.5 m).
(define-asset (hexmaw knight-turnaround) image
    #p"sprites/knight/turnaround.png"
  :min-filter :nearest :mag-filter :nearest)

;; The block: impact (the shield's face lit by the splash), then the brace, crouched
;; behind the raised shield; two frames for each of the views the shield covers (front
;; and front-quarter), over *BLOCK-TIME*. Its cells are 112 px tall, at the turnaround's
;; scale.
(define-fx-animation knight-block "sprites/knight/block" :size (* *knight-height* 112/125))
;; A slow, heavy stride, four frames per view, the shield held up in front. Its cells are
;; 132 px tall for the rise on the passing frames, the standing knight 125 px. The frame
;; follows the distance walked (STRIDE), so :FPS is unused.
(define-fx-animation knight-walk "sprites/knight/walk" :loop T :size (* *knight-height* 132/125))
;; The mace blow over the shield: wind-up, swing, strike, recover, four frames per view.
;; Its cells are 157 px tall to fit the raised mace. The frames run on
;; ATTACK-FRAME-TIMES, so :FPS is unused.
(define-fx-animation knight-attack "sprites/knight/attack" :size (* *knight-height* 157/125))
;; The flinch: jolt, then stagger, two frames per view over *STAGGER-TIME*. Its cells
;; are 124 px tall, at the turnaround's scale.
(define-fx-animation knight-hurt "sprites/knight/hurt" :size (* *knight-height* 124/125))
;; It kneels, topples onto its hands and crashes down, its eyes and runes going dark;
;; the heap of armour is the corpse. Front view only, the jolted knight in frame 1
;; 125 px tall.
(define-fx-animation knight-death "sprites/knight/death" :fps 9 :size *knight-height*)

(define-shader-entity knight (creature)
  ((texture :initform (// 'hexmaw 'knight-turnaround))
   (atlas :initform (read-atlas "data/sprites/knight/turnaround.lisp"))
   (sprite-height :initform *knight-height*)
   (walk-animation :initform 'knight-walk)
   (attack-animation :initform 'knight-attack)
   (hurt-animation :initform 'knight-hurt)
   (death-animation :initform 'knight-death)
   (stride :initform 0.3)
   (body-radius :initform 0.45)
   (shield-views :initform 1)
   (block-animation :initform 'knight-block)
   (turn-speed :initform 1.6)
   (knockback-scale :initform 0.35)
   (attack-damage :initform '(12 18))
   (attack-reach :initform 0.8)
   (attack-arc :initform 0.7)
   ;; A slow, heavy blow: a long wind-up to back out of.
   (attack-frame-times :initform '(0.6 0.15 0.25 0.45))
   (attack-pause :initform 0.9)
   (walk-speed :initform 0.9)
   (chase-speed :initform 1.4)
   (wander-radius :initform 2.0)
   (max-health :initform 60)))
