(in-package #:hexmaw)

;;; Creatures: billboard monsters that can be hurt. A hit flashes the sprite, slides it
;;; back along the blow (momentum) and freezes the action for a moment (hit-stop). On a
;;; pain roll (its PAIN-CHANCE plus the weapon's bonus, at most *MAX-PAIN-CHANCE*) it also
;;; plays its flinch (stagger; without a hurt animation, a squash) and breaks off what it
;;; was doing, so no monster can be held in its flinch. At zero health it plays its
;;; death animation and stays down as a corpse (or, without one, collapses into the
;;; floor). On the test level it then revives at its spawn point, so there is always
;;; something to shoot at; elsewhere the dead stay dead.

(defparameter *hit-stop-time* 0.06 "Seconds the world freezes when a hit lands.")
(defparameter *flash-time* 0.15)
(defparameter *flash-color* (vec4 1.0 0.95 0.8 0.85) "RGB and peak strength of the hit flash.")
(defparameter *stagger-time* 0.35)
(defparameter *stagger-squash* 0.12 "How much a flinch squashes the sprite, as a fraction of its height.")
(defparameter *knockback-friction* 14.0 "Deceleration of knockback, in m/s², on floors other than ice.")
(defparameter *skid-arrive* 0.5 "Metres from a path's point within which a creature skidding on ice has reached it.")
(defparameter *skid-pass* 1.5
  "Metres from a path's point within which a skidding creature whose momentum leads away from
it has gone past it, and makes for the next.")
(defparameter *death-time* 0.5 "Seconds a creature without a death animation takes to collapse.")
(defparameter *revive-time* 3.0 "Seconds a corpse lies still before it comes back; NIL to stay dead.")
(defparameter *wander-pause* '(1.0 3.0) "Least and most seconds a wandering creature stands before moving on.")
(defparameter *hurt-pause* 0.2 "Seconds a creature stands after a painful hit before it plans a new walk.")
(defparameter *max-pain-chance* 75
  "Most percent chance a hit has to make a creature flinch, whatever its PAIN-CHANCE and
the weapon's bonus: some hits always pass it by, so it can't be held in its flinch.")
(defparameter *settle-speed* 3.0 "Metres per second a creature rises or sinks to the floor under it.")
(defparameter *float-sink* 0.6
  "Share of its height a creature afloat in deep water is drawn below the surface it is on.")
(defparameter *flounder-speed* 0.4 "Share of its walking speed a creature afloat makes for the shore at.")
(defparameter *creature-drown-damage* 6.0 "Health per second a creature afloat in deep water loses.")
(defparameter *stuck-time* 0.5 "Seconds a walking creature stays blocked before it gives up its path.")
(defparameter *stuck-pause* 0.3 "Seconds it stands after giving up before it plans another walk.")
(defparameter *sidestep-time* 0.4
  "Seconds a walking creature that runs into another creature's body steps round it.")
(defparameter *sidestep-across* 0.8
  "How much of a sidestep goes across the way it was walking, from 0 (straight on) to 1
(straight across): the rest goes on.")
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
(defparameter *flank-range* 5.0
  "Metres within which a creature that FLANKS walks round a raised shield instead of into it.")
(defparameter *flank-margin* 0.35
  "Radians past *BLOCK-ARC* (player.lisp) that a flanking creature makes for, and that it
still counts as in front of the shield.")
(defparameter *flank-cooldown* 2.5
  "Seconds from one flank to the next: a player who keeps turning to face it gets the blow
on the shield.")
(defparameter *flank-steps* 3 "Points on the arc a flank walks round the player.")
(defparameter *slot-range* 6.0
  "Metres from the player within which melee hunters spread round them (ATTACK-SLOT)
instead of all making for the player.")
(defparameter *slot-spacing* 0.8
  "Least radians, seen from the player, between two melee hunters' attack spots: 0.8 sets
two imps there side by side.")
(defparameter *slot-wait-radius* 2.5
  "Metres from the player that a melee hunter with no free attack spot waits at. One
nearer than a metre inside it backs out to it, so the pack's waiters never loiter at
arm's length.")
(defparameter *slot-ban-time* 2.0
  "Seconds a melee hunter keeps off an attack spot it couldn't get to: no path, a path
through the player, or stuck on the way.")

(defvar *hit-stop* 0.0 "Seconds of hit-stop left. While positive, nothing in the world moves.")
(defvar *roll-random* (make-random-state T)
  "Rolls damage, knockback and pain (ROLL, spells.lisp; PAIN-ROLL-P). RANDOM serves blood,
wandering and the like, which draw a different number of times a frame as the frame rate
varies; kept apart, and saved with a game (save.lisp), the rolls after a load come out as
they did after the save.")
(defvar *creatures* (make-array 0 :adjustable T :fill-pointer T)
  "Creatures in the level, for hit tests. The level rebuilds it.")

(defvar *player* NIL "The player in the current scene.")

(defvar *game-state* :title
  "What the game is doing: :TITLE (main menu), :LOADING (building a level), :PLAYING,
:PAUSED, :MAP (the automap, map-view.lisp), :INVENTORY (the inventory panel, inventory.lisp)
or :DEAD (the player fell on a generated level, PLAYER-DIES, then the death screen). Menus
(menu.lisp) change it; anything but :PLAYING
freezes the world.")

(defvar *level* :test
  "Which level BUILD-LEVEL (level.lisp) builds: :TEST, the greybox test level where the
creatures in development live; :GALLERY, every level block laid out (kit.lisp); or
:GENERATED (generate.lisp). Only the test level revives its dead.")

(defun frozen-p ()
  (or (< 0.0 *hit-stop*)
      (not (eq *game-state* :playing))))

(defun hit-stop (&optional (time *hit-stop-time*))
  (setf *hit-stop* (max *hit-stop* (float time 0f0))))

;;; Vortices (vortex.lisp) pull, whirl and throw the player and creatures alike, so what
;;; that takes lives on both.

(defvar *vortices* (make-array 4 :adjustable T :fill-pointer 0)
  "The vortices in the scene, which every actor asks each tick. BUILD-LEVEL empties it.")
(defvar *ignore-bodies* NIL "True while MOVE-CREATURE moves something other bodies don't stop.")

(defclass whirlable ()
  ((whirl :initform NIL :accessor whirl :documentation "The vortex holding it, or NIL.")
   (whirl-angle :initform 0.0 :accessor whirl-angle :documentation "Where it is round the vortex, in radians.")
   (whirl-radius :initform 0.0 :accessor whirl-radius :documentation "Metres out from the vortex's centre line.")
   (whirl-lift :initform 0.0 :accessor whirl-lift :documentation "Metres over the floor it is carried up to.")
   (whirl-time :initform 0.0 :accessor whirl-time :documentation "Seconds since it was caught.")
   (whirl-hold :initform 0.0 :accessor whirl-hold :documentation "Seconds until it is thrown out.")
   (whirl-stuck :initform 0.0 :accessor whirl-stuck :documentation "Seconds walls have kept it off its orbit.")
   (flung :initform NIL :accessor flung :documentation "True from being thrown out until it lands.")
   (spat-timer :initform 0.0 :accessor spat-timer :documentation "Seconds until a vortex can pull it again.")
   (pull :initform (vec 0 0 0) :reader pull :documentation "How fast, in m/s, vortices drag it this tick.")
   (pull-look :initform 0.0 :accessor pull-look :documentation "Seconds until it looks for a line to a vortex again.")
   (pull-clear :initform NIL :accessor pull-clear :documentation "True if it had a line to a vortex when it last looked.")))

(defun clear-whirl (actor)
  "ACTOR is neither held nor thrown by a vortex, and can be pulled at once."
  (setf (whirl actor) NIL
        (flung actor) NIL
        (whirl-stuck actor) 0.0
        (spat-timer actor) 0.0
        (pull-look actor) 0.0)
  (let ((pull (pull actor)))
    (setf (vx pull) 0f0 (vz pull) 0f0)))

;;; Impacts: an actor thrown or knocked into a wall, a ceiling or another body fast enough
;;; is hurt, whatever sent it, and so is the body it hits. Onto a floor that holds for one a
;;; vortex threw; the player's own falls hurt only from higher up. Walking, running and
;;; sliding on ice stay under it.

(defparameter *impact-speed* 8.0
  "Speed in m/s into a wall, ceiling or body below which an actor is unhurt, and onto a floor for one thrown.")
(defparameter *fall-impact-speed* 13.0 "Speed in m/s onto a floor below which the player's own fall is unhurt: a 4 m drop.")
(defparameter *impact-per-speed* 2.5 "Damage per m/s over the speed that hurts.")
(defparameter *impact-max* 20 "The most damage one impact does.")

(defun impact-damage (speed &optional (threshold *impact-speed*))
  (max 1 (min *impact-max* (round (* *impact-per-speed* (- speed threshold))))))

(defgeneric hit-surface (actor speed x y z &key threshold by)
  (:documentation "ACTOR hit something at SPEED m/s going along X Y Z, the way into it: hurt
it if that is over THRESHOLD (*IMPACT-SPEED*). BY is what to blame, for the death screen."))

(defun strike-body (actor speed x z reach &key by)
  "ACTOR, stopped going along X Z at SPEED, may have run into another body: if one is within
REACH metres that way, it takes the impact too, the other way."
  (let ((len (sqrt (+ (* x x) (* z z)))))
    (when (and (< *impact-speed* speed) (< 1f-4 len))
      (let* ((feet (body-feet actor))
             (k (/ (max reach 0.1) len))
             (body (nth-value 1 (body-overlapping (+ (vx feet) (* k x)) (+ (vy feet) 0.05) (+ (vz feet) (* k z))
                                                  (float (body-radius actor) 0f0)
                                                  (- (float (body-height actor) 0f0) 0.05)
                                                  actor))))
        (when body
          (hit-surface body speed (- x) 0.0 (- z) :by (or by actor)))))))

(defun hit-across (actor hit-x hit-z dt &key by)
  "ACTOR moving along the ground or through the air was stopped going at HIT-X HIT-Z m/s
this DT-second tick: a wall or body it hit fast enough hurts it, and the body too."
  (let ((speed (sqrt (+ (* hit-x hit-x) (* hit-z hit-z)))))
    (when (< *impact-speed* speed)
      (hit-surface actor speed hit-x 0.0 hit-z :by by)
      (strike-body actor speed hit-x hit-z (* speed dt) :by by))))

(define-shader-entity creature (billboard whirlable)
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
   (pain-chance :initarg :pain-chance :initform 50 :reader pain-chance
                :documentation "Percent chance a hit makes it flinch and breaks off its walk or
attack; the weapon adds its pain bonus, up to *MAX-PAIN-CHANCE*.")
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
   (bash-poise :initform 0.0 :accessor bash-poise
               :documentation "Seconds left in which a shield bash can't stagger it and barely
moves it (sword.lisp): set by every bash that lands.")
   (guard-break :initarg :guard-break :initform NIL :reader guard-break
                :documentation "Seconds a blow of its that the player's shield blocks knocks the
shield down for (BREAK-GUARD, player.lisp); NIL for none.")
   (flanks :initarg :flanks :initform NIL :reader flanks
           :documentation "True if it walks round to the side of a raised shield instead of
attacking into it (FLANK).")
   (flanking :initform NIL :accessor flanking :documentation "True while it walks a flank's path.")
   (flank-timer :initform 0.0 :accessor flank-timer :documentation "Seconds until it may flank again.")
   (slot-yaw :initform NIL :accessor slot-yaw
             :documentation "Direction round the player, as a yaw, of the attack spot it has
claimed (ATTACK-SLOT), or NIL.")
   (slot-bans :initform () :accessor slot-bans
              :documentation "Yaws of attack spots it couldn't get to, kept off for *SLOT-BAN-TIME*.")
   (slot-ban-timer :initform 0.0 :accessor slot-ban-timer
                   :documentation "Seconds until it forgets SLOT-BANS.")
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
   (sidestep :initform 0.0 :accessor sidestep
             :documentation "Seconds left of stepping round a body in its way (WALK-PATH).")
   (sidestep-side :initform 1 :accessor sidestep-side
                  :documentation "Which way it steps round: 1 to its right, -1 to its left.")
   (sidestep-flipped :initform NIL :accessor sidestep-flipped
                     :documentation "True once this sidestep has turned to the other side, its first
side being shut too.")
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
   (momentum :initform (vec 0 0 0) :reader momentum
             :documentation "Velocity it slides with: a blow's knockback, and on ice its walk too.")
   (flight :initform (vec 0 0 0) :reader flight
           :documentation "Velocity it flies with while FLUNG (vortex.lisp).")
   (footing :initform NIL :accessor footing
            :documentation "The footing (*FOOTINGS*) it stands on this tick, or NIL.")
   (stagger :initform 0.0 :accessor stagger)
   (flash :initform 0.0 :accessor flash)
   (burn-timer :initform 0.0 :accessor burn-timer
               :documentation "Seconds until the next burn can land (liquids.lisp).")
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
   (undead :initarg :undead :initform NIL :reader undead
           :documentation "True for the risen dead, whom a necromancer's spells spare.")
   (death-blood :initarg :death-blood :initform NIL :reader death-blood
                :documentation "Drops of blood its death bursts out; NIL for *DEATH-BLOOD*. At 0
its corpse doesn't bleed either.")
   (bleeding :initform 0f0 :accessor bleeding :documentation "Seconds it keeps dripping blood.")
   (gibs :initarg :gibs :initform NIL :reader gibs
         :documentation "What a blow that overkills it tears it into (gore.lisp): groups of a
gib set's name in the blood strip, then a piece number for each gib, (:HEAD N) for the
one that flies from the top. NIL never tears apart.")
   (gib-scale :initarg :gib-scale :initform 1.0 :reader gib-scale
              :documentation "Size its gibs are drawn at, so one set serves every size of creature.")
   (gib-overkill :initarg :gib-overkill :initform NIL :reader gib-overkill
                 :documentation "Fraction of its most health a killing blow must overkill it by to
tear it apart; NIL for *GIB-OVERKILL*.")
   (gibbed :initform NIL :accessor gibbed :documentation "True while it lies torn apart.")
   (summoned :initarg :summoned :initform NIL :reader summoned
             :documentation "True if it came into the level mid-game (a raised skeleton): a
reset takes it away instead of reviving it.")
   (rising :initform 0.0 :accessor rising
           :documentation "Seconds left of getting up from where it was raised; it does
nothing else meanwhile, and plays its death backwards.")
   (stirring :initform 0.0 :accessor stirring
             :documentation "Seconds left of a corpse's twitching, as something raises it.")
   (drip-timer :initform 0f0 :accessor drip-timer :documentation "Seconds until its next drip.")
   (size-scale :initarg :size-scale :initform 1.0 :reader size-scale
               :documentation "How much bigger than its strips' own size it is drawn: a boss's
empowered form (boss.lisp). Its SPRITE-HEIGHT is already scaled.")
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

(defgeneric spares-p (caster target)
  (:documentation "True if CASTER's spells pass TARGET by (a necromancer's, its undead).")
  (:method (caster target) NIL))

(defun creature-at (point margin &optional ignore)
  "The first live creature other than IGNORE, or one IGNORE spares, whose body contains
POINT, grown by MARGIN metres, or NIL."
  (loop for c across *creatures*
        for loc = (location c)
        for r = (+ (body-radius c) margin)
        when (and (not (dead c))
                  (not (eq c ignore))
                  (not (and ignore (spares-p ignore c)))
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
(defmethod body-solid-p ((creature creature)) (not (or (dead creature) (whirl creature))))

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
         (bodies (not (or *ignore-bodies* (creature-body-overlapping creature)))))
    (labels ((blocked ()
               (or (solid-overlapping (vx loc) (+ (vy loc) lift) (vz loc) r (- h lift))
                   (and bodies (creature-body-overlapping creature))))
             (try (axis delta)
               ;; Move DELTA along AXIS; blocked, undo it, or take the part that runs
               ;; along a wedge's diagonal instead. True if it got nowhere.
               (let ((ox (vx loc)) (oz (vz loc)))
                 (if (= axis 0) (incf (vx loc) delta) (incf (vz loc) delta))
                 (let ((s (blocked)))
                   (when s
                     (let ((diagonal (nth-value 1 (solid-flush s axis delta (vx loc) (vz loc) r))))
                       (setf (vx loc) ox (vz loc) oz)
                       (or (not diagonal)
                           (multiple-value-bind (sx sz) (slide-along s axis delta)
                             (incf (vx loc) sx) (incf (vz loc) sz)
                             (when (blocked) (setf (vx loc) ox (vz loc) oz) T)))))))))
      (values (unless (= 0 dx) (try 0 dx))
              (unless (= 0 dz) (try 2 dz))))))

(defgeneric always-pained-p (creature)
  (:documentation "True if a hit on CREATURE now breaks off what it's doing whatever the
pain roll says (a flyer's dive, flyer.lisp).")
  (:method ((creature creature)) NIL))

(defun pain-roll-p (creature bonus)
  "Roll whether a hit with pain bonus BONUS (percent) makes CREATURE flinch."
  (< (random 100 *roll-random*)
     (min *max-pain-chance* (+ (pain-chance creature) bonus))))

(defgeneric stays-dead-p (creature)
  (:documentation "True if CREATURE never comes back on the test level (*REVIVE-TIME*): one
summoned mid-game, or a boss (boss.lisp).")
  (:method ((creature creature)) (summoned creature)))

(defgeneric dormant-p (creature)
  (:documentation "True while CREATURE sleeps: it neither thinks nor takes harm (a boss
before its arena is sealed, boss.lisp). A hit only flashes it.")
  (:method ((creature creature)) NIL))

(defgeneric react-to-hit (creature)
  (:documentation "What CREATURE does after a hit it lived through, once HURT has done the
rest (the riftwalker blinks away, riftwalker.lisp).")
  (:method ((creature creature)) NIL))

(defun hurt (creature amount &key from (pain-bonus 0))
  "Take AMOUNT health from CREATURE, struck from point FROM (NIL: from the player), which
the blood sprays away from. It flinches and breaks off what it's doing on a pain roll,
its PAIN-CHANCE plus PAIN-BONUS percent."
  (when (and (dormant-p creature) (not (dead creature)))
    (setf (flash creature) *flash-time*)
    (return-from hurt))
  (unless (dead creature)
    (decf (health creature) amount)
    (when (bleeds creature)
      (bleed creature amount from))
    (setf (flash creature) *flash-time*
          (alert creature) *alert-time*)
    (when (or (<= (health creature) 0)
              (always-pained-p creature)
              (pain-roll-p creature pain-bonus))
      ;; Stop (a hit breaks off an attack too), and plan afresh once the flinch is over:
      ;; knockback moves it off its path.
      (setf (stagger creature) *stagger-time*)
      (stop-walking creature *hurt-pause*))
    (hit-stop)
    (when (<= (health creature) 0)
      (cond ((gib-p creature amount)
             (tear-apart creature :from from))
            ((bleeds creature)
             (bleed-out creature)))
      (setf (dead creature) 0.0))
    (unless (dead creature)
      (react-to-hit creature))))

(defmethod hit-surface ((creature creature) speed x y z &key (threshold *impact-speed*) by)
  (declare (ignore by))
  (when (< threshold speed)
    (let ((loc (location creature)))
      ;; Struck from the side away from what it hit, so the blood sprays onto it.
      (hurt creature (impact-damage speed threshold)
            :from (vec (- (vx loc) x) (- (+ (vy loc) (* 0.5 (sprite-height creature))) y) (- (vz loc) z))))))

(defun burn (creature amount)
  "Take AMOUNT health from CREATURE standing in lava or drowning: a flash and it notices, but no
flinch, blood or hit-stop, which would freeze the game every burn."
  (unless (or (dead creature) (dormant-p creature))
    (decf (health creature) amount)
    (setf (flash creature) *flash-time*
          (alert creature) *alert-time*)
    (when (<= (health creature) 0)
      (stop-walking creature)
      (setf (dead creature) 0.0))))

(defun escape-liquid (creature)
  "Set CREATURE, standing in lava or afloat in deep water, walking to the nearest dry cell.
In the middle of a stream, lava wall to wall, or of a pool that is several metres off, so
look further if need be."
  (when *nav-grid*
    (multiple-value-bind (i j k)
        (let ((*nav-hazards* :avoid)
              (loc (location creature)) (r (body-radius creature)) (h (sprite-height creature)))
          (multiple-value-bind (i j k) (nav-nearest-fitting loc r h :search 4)
            (if i
                (values i j k)
                (nav-nearest-fitting loc r h :search 12))))
      (when i
        (setf (path creature) (list (nav-point i j k))
              (brain creature) :walking
              (stuck creature) 0.0)))))

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
        (kb (momentum creature)))
    (when (< 1f-4 len)
      (setf (vx kb) (* speed (/ (vx direction) len))
            (vz kb) (* speed (/ (vz direction) len))))))

(defun slide (creature dt)
  "Move by its momentum for DT seconds, stopping at solids and bodies, then slow it by
friction: on ice by the footing's, and while it walks there it climbs steps as it walks."
  (let ((kb (momentum creature))
        (footing (footing creature))
        (walking (eq (brain creature) :walking)))
    (multiple-value-bind (x-blocked z-blocked)
        (move-creature creature (* (vx kb) dt) (* (vz kb) dt)
                       (if (and footing walking) (move-lift creature) 0.05))
      (let ((hit-x (if x-blocked (vx kb) 0.0))
            (hit-z (if z-blocked (vz kb) 0.0)))
        (when x-blocked (setf (vx kb) 0.0))
        (when z-blocked (setf (vz kb) 0.0))
        ;; Knocked into something hard; its own walk on ice doesn't count.
        (unless walking
          (hit-across creature hit-x hit-z dt))))
    (if footing
        (footing-drag kb footing dt (not walking))
        (let* ((speed (sqrt (+ (expt (vx kb) 2) (expt (vz kb) 2))))
               (slower (max 0.0 (- speed (* *knockback-friction* dt)))))
          (if (< speed 1f-4)
              (setf (vx kb) 0.0 (vz kb) 0.0)
              (setf (vx kb) (* (vx kb) (/ slower speed)) (vz kb) (* (vz kb) (/ slower speed))))))))

(defun walking-speed (creature)
  (* (if (hunting-p creature) (or (chase-speed creature) (walk-speed creature)) (walk-speed creature))
     (if (afloat-p creature) *flounder-speed* 1.0)))

;;; Deep water (liquids.lisp): its surface is a floor on the nav grid, so a walker shoved
;;; in settles onto it like any floor, and is drawn sunk to the chest. Afloat it can't
;;; fight: it flounders toward the nearest dry floor, slowed and drowning, and walks out
;;; up the step onto the ledge. Its paths otherwise keep out of water.

(defgeneric floats-p (creature)
  (:documentation "True if CREATURE ends up afloat on deep water it gets onto: a walker.
A flyer hovers over it.")
  (:method ((creature creature)) T))

(defun afloat-p (creature)
  "True if CREATURE stands on deep water's surface."
  (and (floats-p creature)
       (let* ((loc (location creature))
              (water (swim-liquid-at (vx loc) (- (vy loc) 0.05) (vz loc))))
         (and water (< (- (aref (liquid-bounds water) 4) (vy loc)) 0.1)))))

(defvar *sink-offset* (vec3) "Scratch: how far an afloat creature is drawn below its location.")

;; Afloat, drawn sunk: the water's surface, drawn after it, covers what is below. Before
;; the sprite's own transform, so the offset is in world space.
(defmethod apply-transforms :around ((creature creature))
  (when (afloat-p creature)
    (setf (vy *sink-offset*) (float (- (* *float-sink* (sprite-height creature))) 0f0))
    (translate *sink-offset*))
  (call-next-method))

(defun flounder (creature dt)
  "Make for the nearest dry floor (ESCAPE-LIQUID) for DT seconds: CREATURE is afloat."
  (unless (and (eq (brain creature) :walking) (path creature))
    (stop-walking creature 0.0)
    (escape-liquid creature))
  (when (eq (brain creature) :walking)
    (walk-path creature dt)))

(defun update-footing (creature)
  "Find the footing CREATURE stands on. Stepping onto ice mid-walk, it carries its walk's
speed onto it as momentum, so it doesn't stall at the edge."
  (let ((footing (and *nav-grid* (let ((loc (location creature)))
                                   (nav-footing-at (vx loc) (vy loc) (vz loc))))))
    (when (and footing (not (footing creature)) (not (dead creature)) (eq (brain creature) :walking))
      (let ((m (momentum creature))
            (speed (walking-speed creature))
            (yaw (facing creature)))
        (when (< (+ (expt (vx m) 2) (expt (vz m) 2)) (* speed speed))
          (setf (vx m) (float (* speed (sin yaw)) 0f0)
                (vz m) (float (* speed (- (cos yaw))) 0f0)))))
    (setf (footing creature) footing)))

(defun attacker-p (creature)
  (or (attack-damage creature) (attack-spell creature)))

(defun hunting-p (creature)
  (and (attacker-p creature) (< 0 (alert creature))))

(defun stop-walking (creature &optional (pause (if (hunting-p creature) *chase-pause* (wander-pause))))
  "Stand still, walking or attacking, for PAUSE seconds."
  (setf (brain creature) :idle
        (path creature) ()
        (flanking creature) NIL
        (sidestep creature) 0.0
        (stuck creature) 0.0
        (attack-time creature) NIL
        (idle-timer creature) pause))

(defgeneric nav-hazards (creature)
  (:documentation "How CREATURE's paths treat lava and deep water (*NAV-HAZARDS*, nav.lisp):
a walker keeps out of them, wading lava only when no other way reaches the player; a flyer
ignores lava and paths over water.")
  (:method ((creature creature)) :avoid))

(defgeneric move-lift (creature)
  (:documentation "Metres above its feet that a moving CREATURE ignores solids in: the
ledges it climbs. A flyer has nothing to climb.")
  (:method ((creature creature)) (step-height creature)))

(defgeneric keep-height (creature dt)
  (:documentation "Each tick, dead or alive, move CREATURE to the height it belongs at.
A walker settles onto the floor; a flyer (flyer.lisp) hovers, dives and falls.")
  (:method ((creature creature) dt)
    (unless (dead creature)
      (settle creature dt))))

(defgeneric break-flight (creature)
  (:documentation "A vortex caught CREATURE: forget any flight of its own (an ogre's leap, a
flyer's dive), which KEEP-HEIGHT would otherwise carry on with once it lands.")
  (:method ((creature creature)) NIL))

(defgeneric land-thrown (creature)
  (:documentation "A vortex threw CREATURE and it has just come to the floor: alive, it
staggers; a flyer lies downed.")
  (:method ((creature creature))
    (setf (stagger creature) *stagger-time*)
    (stop-walking creature *hurt-pause*)))

(defun ground-point (creature)
  "Where CREATURE plans its moves from: its feet, or for one in the air, the floor
under them. The nav grid only knows floors."
  (let* ((loc (location creature))
         (floor (and *nav-grid* (nav-floor-at (vx loc) (vy loc) (vz loc)))))
    (if (and floor (< *nav-layer-above* (- (vy loc) floor)))
        (vec (vx loc) floor (vz loc))
        loc)))

(defun skid-path (creature dt)
  "Walk DT seconds toward the next point of the path on ice: face it and push the momentum
toward it (SLIDE does the moving), so it is slow to get going and overshoots. A point is
reached near it or once gone past it. Going too slowly for *STUCK-TIME*, it gives up."
  (let* ((loc (location creature))
         (target (first (path creature)))
         (m (momentum creature))
         (dx (- (vx target) (vx loc)))
         (dz (- (vz target) (vz loc)))
         (distance (sqrt (+ (* dx dx) (* dz dz))))
         (speed (walking-speed creature)))
    (when (< 1f-4 distance)
      (turn-to creature (atan dx (- dz)) dt)
      (footing-push m (/ dx distance) (/ dz distance) speed (footing creature) dt))
    ;; The legs scrabble at the walk's pace, whatever the ice makes of it.
    (incf (walk-distance creature) (* speed dt))
    (setf (stuck creature) (if (< (+ (expt (vx m) 2) (expt (vz m) 2)) (expt (* 0.25 speed) 2))
                               (+ (stuck creature) dt)
                               0.0))
    (cond ((or (< distance *skid-arrive*)
               (and (< distance *skid-pass*) (< (+ (* dx (vx m)) (* dz (vz m))) 0)))
           (unless (setf (path creature) (rest (path creature)))
             (stop-walking creature)))
          ((< *stuck-time* (stuck creature))
           (ban-slot creature)
           (stop-walking creature *stuck-pause*)))))

(defun body-ahead (creature fx fz)
  "The creature whose body stands in CREATURE's way along FX FZ (a unit vector), or NIL.
Not the player: a creature walks into the player to attack."
  (let ((loc (location creature)))
    (multiple-value-bind (box body)
        (body-overlapping (+ (vx loc) (* 0.1 fx)) (+ (vy loc) 0.05) (+ (vz loc) (* 0.1 fz))
                          (float (body-radius creature) 0f0) (- (float (sprite-height creature) 0f0) 0.05)
                          creature)
      (declare (ignore box))
      (and body (not (eq body *player*)) body))))

(defun walk-path (creature dt)
  "Walk DT seconds toward the next point of the path, facing the way it goes. Blocked
by a body it slides along it, and stopped dead by another creature's it steps round it
for *SIDESTEP-TIME* (the other way if that side is shut too); a hunter stopped by one
standing still plans afresh instead, round it (STANDING-BODIES), unless it just did.
Blocked for *STUCK-TIME*, it gives up the path. On ice it skids instead (SKID-PATH)."
  (when (footing creature)
    (return-from walk-path (skid-path creature dt)))
  (let* ((loc (location creature))
         (target (first (path creature)))
         (dx (- (vx target) (vx loc)))
         (dz (- (vz target) (vz loc)))
         (distance (sqrt (+ (* dx dx) (* dz dz))))
         (speed (walking-speed creature))
         (step (min distance (* speed dt)))
         (x0 (vx loc))
         (z0 (vz loc))
         (fx (if (< 1f-4 distance) (/ dx distance) 0.0))
         (fz (if (< 1f-4 distance) (/ dz distance) 0.0))
         (dodging (< 0.0 (sidestep creature))))
    (when (< 1f-4 distance)
      ;; Stepping round a body: mostly across the way, a little on. Its right is (-fz, fx).
      (let* ((side (float (sidestep-side creature) 0f0))
             (across (if dodging *sidestep-across* 0.0))
             (mx (+ (* across side (- fz)) (* (- 1.0 across) fx)))
             (mz (+ (* across side fx) (* (- 1.0 across) fz)))
             (ml (sqrt (+ (* mx mx) (* mz mz)))))
        (turn-to creature (atan mx (- mz)) dt)
        (move-creature creature (* step (/ mx ml)) (* step (/ mz ml)) (move-lift creature))))
    (let* ((moved (sqrt (+ (expt (- (vx loc) x0) 2) (expt (- (vz loc) z0) 2))))
           (blocked (and (< 1f-4 distance) (< moved (* 0.25 step))))
           (dodge (and blocked (not dodging) (body-ahead creature fx fz))))
      (incf (walk-distance creature) moved)
      (when dodging
        (decf (sidestep creature) dt))
      (cond ((and dodge (hunting-p creature) (not (flanking creature))
                  (not (eq (brain dodge) :walking))
                  (< (replan-timer creature) (- *chase-replan* 0.2)))
             ;; It stopped after this path was planned: the next plan goes round it.
             (setf (replan-timer creature) 0.0))
            (dodge
             ;; Another creature in the way: step round it, on the side away from its centre.
             (let ((loc2 (location dodge)))
               (setf (sidestep-side creature)
                     (if (< 0 (+ (* (- (vx loc2) (vx loc)) (- fz)) (* (- (vz loc2) (vz loc)) fx))) -1 1)
                     (sidestep creature) *sidestep-time*
                     (sidestep-flipped creature) NIL)))
            ((and blocked dodging (not (sidestep-flipped creature)))
             ;; That way round is shut too: try the other.
             (setf (sidestep-side creature) (- (sidestep-side creature))
                   (sidestep creature) *sidestep-time*
                   (sidestep-flipped creature) T)))
      (setf (stuck creature) (if (and blocked (not dodge)) (+ (stuck creature) dt) 0.0))
      (cond ((< (+ (expt (- (vx target) (vx loc)) 2) (expt (- (vz target) (vz loc)) 2)) 1f-6)
             (unless (setf (path creature) (rest (path creature)))
               (stop-walking creature)))
            ((< *stuck-time* (stuck creature))
             (ban-slot creature)
             (stop-walking creature *stuck-pause*))))))

(defun plan-wander (creature)
  "Set off for a random spot it can reach within WANDER-RADIUS of home."
  (let* ((loc (ground-point creature))
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

(defgeneric sight-rise (creature)
  (:documentation "Metres above or below it that CREATURE notices the player: the rooms
it can do something about. The ogre, which leaps down, looks further.")
  (:method ((creature creature)) 3.0))

(defun sees-player-p (creature)
  (let* ((loc (location creature))
         (feet (feet *player*))
         (distance (sqrt (+ (expt (- (vx feet) (vx loc)) 2) (expt (- (vz feet) (vz loc)) 2)))))
    (and (< 0 (health *player*))
         (< (abs (- (vy feet) (vy loc))) (sight-rise creature))
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

(defun player-bearing (point)
  "Direction from the player to POINT, as a yaw."
  (let ((feet (feet *player*)))
    (atan (- (vx point) (vx feet)) (- (vz feet) (vz point)))))

(defun melee-hunter-p (creature)
  (and (not (dead creature)) (not (whirl creature)) (not (flung creature))
       (attack-damage creature) (not (ranged-p creature)) (hunting-p creature)))

(defun angle-between (a b)
  "Radians between yaws A and B, the short way round."
  (abs (- (mod (+ (- a b) pi) (* 2 pi)) pi)))

(defun open-spot-p (creature spot)
  "True if CREATURE fits on the floor at SPOT, within a step of its height, with no wall
between SPOT and the player. Not a walk from the player's feet: with their back to a wall
the creature doesn't fit there. Bodies don't count (ATTACK-SLOT keeps spots apart): the cell
under a spot beside another hunter's may reach into it."
  (and (let ((*nav-bodies* NIL))
         (nav-nearest-fitting spot (body-radius creature) (sprite-height creature)
                              :search 0 :reach (step-height creature)))
       (clear-path-p spot (feet *player*) 1.0)))

(defun slot-point (creature yaw &optional radius)
  "The spot at YAW round the player, RADIUS metres off (by default where CREATURE attacks
from), or NIL if it isn't open (OPEN-SPOT-P)."
  (let* ((feet (feet *player*))
         (radius (or radius (+ (body-radius creature) *player-radius*
                               (* 0.9 *attack-start-reach* (attack-reach creature)))))
         (spot (vec (+ (vx feet) (* radius (sin yaw))) (vy feet) (- (vz feet) (* radius (cos yaw))))))
    (when (open-spot-p creature spot)
      spot)))

(defun nearest-open-spot (creature radius &optional (allowed (constantly T)))
  "The open spot (SLOT-POINT, RADIUS off) round the player nearest the way CREATURE comes
from, whose yaw ALLOWED accepts, looking a quarter of *SLOT-SPACING* at a time either
side. Returns the spot and its yaw, or NIL."
  (let ((bearing (player-bearing (location creature)))
        (step (/ *slot-spacing* 4)))
    (loop for k from 0 to (floor pi step)
          do (dolist (sign (if (= k 0) '(1) '(1 -1)))
               (let ((yaw (float (+ bearing (* sign k step)) 0f0)))
                 (when (funcall allowed yaw)
                   (let ((spot (slot-point creature yaw radius)))
                     (when spot
                       (return-from nearest-open-spot (values spot yaw))))))))))

(defun ban-slot (creature)
  "Give up CREATURE's attack spot, one it couldn't get to, and keep off it a while."
  (when (slot-yaw creature)
    (push (slot-yaw creature) (slot-bans creature))
    (setf (slot-ban-timer creature) *slot-ban-time*
          (slot-yaw creature) NIL)))

(defparameter *body-avoid-range* 10.0
  "Metres from a planning creature within which standing bodies shut its paths (STANDING-BODIES).")

(defun standing-bodies (creature)
  "The bodies CREATURE's hunting paths keep clear of (*NAV-BODIES*, nav.lisp): the player
and every other live creature not walking, within *BODY-AVOID-RANGE*, standing level with
CREATURE, and not one it already touches. A walking one has moved on by the next replan."
  (let ((loc (location creature))
        (r (body-radius creature))
        (bodies ()))
    (flet ((consider (feet radius height)
             (let ((d2 (+ (expt (- (vx feet) (vx loc)) 2) (expt (- (vz feet) (vz loc)) 2))))
               (when (and (< (vy feet) (+ (vy loc) (sprite-height creature)))
                          (< (vy loc) (+ (vy feet) height))
                          (< d2 (expt *body-avoid-range* 2))
                          ;; Not one it touches: it may walk out of that.
                          (<= (expt (+ r radius) 2) d2))
                 (push (list (vx feet) (vz feet) radius (- (vy feet) 1.0) (+ (vy feet) 1.0)) bodies)))))
      (unless (whirl *player*)
        (consider (feet *player*) *player-radius* *player-height*))
      (loop for c across *creatures*
            unless (or (eq c creature) (dead c) (eq (brain c) :walking) (whirl c) (flung c))
              do (consider (location c) (body-radius c) (sprite-height c))))
    (make-nav-bodies bodies)))

(defun attack-slot (creature)
  "Where CREATURE, a melee hunter within *SLOT-RANGE* of the player, makes for to attack,
so a pack surrounds the player instead of queuing. It claims a direction round the player
(SLOT-YAW) and keeps it while it hunts: the free one nearest the way it comes from, at
least *SLOT-SPACING* from every other hunter's claim and from every one that stands there
already, at arm's length (one that got within reach on the way to its own spot). It
gives its claim up to a hunter nearer the player that claimed close to it or stands on
it, or when a wall comes between it and the player. Returns the spot; NIL and :WAIT when every spot is taken (the rest of the pack
waits its turn); NIL further off, or for anything else."
  (let ((distance (player-distance creature)))
    (if (not (and *nav-grid* (melee-hunter-p creature) (< distance *slot-range*)))
        (setf (slot-yaw creature) NIL)
        (let ((claims (loop for c across *creatures*
                            when (and (not (eq c creature)) (slot-yaw c) (melee-hunter-p c)
                                      (< (player-distance c) (+ *slot-range* 1.0)))
                              collect (cons (slot-yaw c) (player-distance c))))
              (standing (loop for c across *creatures*
                              when (and (not (eq c creature)) (not (dead c))
                                        (player-within-p c (attack-reach c)))
                                collect (player-bearing (location c))))
              (own (slot-yaw creature)))
          (flet ((free-p (yaw nearer-only)
                   (and (loop for (claim . d) in claims
                              never (and (or (not nearer-only) (< d distance))
                                         (< (angle-between yaw claim) (* 0.99 *slot-spacing*))))
                        (loop for b in standing
                              never (< (angle-between yaw b) (* 0.99 *slot-spacing*)))
                        (loop for ban in (slot-bans creature)
                              never (< (angle-between yaw ban) (* 0.5 *slot-spacing*))))))
            (or (and own (free-p own T) (slot-point creature own))
                ;; A new claim: the free spot nearest the way it comes from.
                (multiple-value-bind (spot yaw)
                    (nearest-open-spot creature NIL (lambda (yaw) (free-p yaw NIL)))
                  (setf (slot-yaw creature) yaw)
                  spot)
                (values NIL :wait)))))))

(defun chase-path (creature)
  "A path to the player, or to the creature's ATTACK-SLOT beside them: straight there when
nothing is in the way, else along the nav grid, round the player and every creature
standing still (STANDING-BODIES). A slot it can't get to is given up (BAN-SLOT) for
another; with none, it waits off."
  (let* ((*nav-bodies* (standing-bodies creature))
         (*nav-body-mask* (nav-body-mask *nav-bodies* (body-radius creature)))
         (loc (ground-point creature))
         (r (body-radius creature))
         (h (sprite-height creature))
         (step (step-height creature)))
    (labels ((path-to (goal)
               (cond ((nav-line-clear-p loc goal r h step)
                      (list (vcopy goal)))
                     ((nav-path-to loc goal r h step :max-walk *chase-max-walk*))
                     ;; No dry way: through lava, then, the short way across.
                     ((eq *nav-hazards* :avoid)
                      (let ((*nav-hazards* :wade))
                        (nav-path-to loc goal r h step :max-walk *chase-max-walk*)))))
             (wait-path ()
               ;; No spot free: stand (NIL) until one is, or come in to *SLOT-WAIT-RADIUS*
               ;; from further off, or back out to it from close in, clear of the others
               ;; waiting.
               (let* ((distance (player-distance creature))
                      (near (+ *slot-wait-radius* 1.5))
                      (waiting (loop for c across *creatures*
                                     when (and (not (eq c creature)) (melee-hunter-p c)
                                               (< (player-distance c) near))
                                       collect (player-bearing (location c))))
                      (spot (and (or (< near distance) (< distance (- *slot-wait-radius* 1.0)))
                                 (nearest-open-spot creature *slot-wait-radius*
                                                    (lambda (yaw)
                                                      (loop for b in waiting
                                                            never (< (angle-between yaw b) (* 0.6 *slot-spacing*))))))))
                 (and spot (path-to spot)))))
      (when *nav-grid*
        ;; A spot it can't get to is given up for the next nearest, a few times.
        (loop repeat 3
              do (multiple-value-bind (slot wait) (attack-slot creature)
                   (cond (slot
                          (let ((path (path-to slot)))
                            (if path
                                (return path)
                                (ban-slot creature))))
                         (wait (return (wait-path)))
                         (T (return (path-to (feet *player*))))))
              finally (return (wait-path)))))))

(defun start-attack (creature)
  ;; It attacks from where it got within reach, which needn't be the spot it claimed:
  ;; that is its spot now (ATTACK-SLOT), the one to come back to if shoved off it, unless
  ;; that would crowd another's claim off its own.
  (when (slot-yaw creature)
    (let ((bearing (float (player-bearing (location creature)) 0f0)))
      (when (loop for c across *creatures*
                  never (and (not (eq c creature)) (slot-yaw c) (melee-hunter-p c)
                             (< (angle-between bearing (slot-yaw c)) *slot-spacing*)))
        (setf (slot-yaw creature) bearing))))
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
  (let* ((loc (ground-point creature))
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

(defgeneric hunt-from-range (creature)
  (:documentation "Hunt as a caster does: back off from a player too close, attack one in
range and in sight, else close in."))

(defmethod hunt-from-range ((creature creature))
  (let ((distance (player-distance creature)))
    (cond ((and (< distance (keep-away creature)) (retreat creature)))
          ((and (< distance (attack-range creature))
                (clear-path-p (location creature) (feet *player*) (cast-height creature)))
           (start-attack creature))
          (T (chase creature)))))

(defgeneric ranged-p (creature)
  (:documentation "True if CREATURE attacks from a distance, as HUNT-FROM-RANGE has it:
a caster, or a flyer that dives from out of reach.")
  (:method ((creature creature)) (attack-spell creature)))

(defgeneric special-attack (creature)
  (:documentation "Start an attack of CREATURE's own if it has one ready and it fits, as
the ogre's leap: true if it started one. HUNT asks it first, so a chasing creature asks
every *CHASE-REPLAN*.")
  (:method ((creature creature)) NIL))

(defun flank-yaw (side)
  "Direction from the player, as a yaw, to strike past their shield from on SIDE (1 their
right, -1 their left): just outside the shield's arc."
  (+ (vy (rotation *player*)) (* side (+ *block-arc* *flank-margin*))))

(defun flank-target (creature side radius)
  "Where CREATURE stands to strike past the player's shield from SIDE, RADIUS metres off."
  (let ((feet (feet *player*))
        (yaw (flank-yaw side)))
    (vec (+ (vx feet) (* radius (sin yaw))) (vy (location creature)) (- (vz feet) (* radius (cos yaw))))))

(defun flank-side (creature)
  "The side of the player's facing CREATURE stands on: 1 their right, -1 their left."
  (let* ((loc (location creature))
         (feet (feet *player*))
         (yaw (vy (rotation *player*)))
         ;; The player's right is (cos, sin) of the yaw.
         (right (+ (* (- (vx loc) (vx feet)) (cos yaw)) (* (- (vz loc) (vz feet)) (sin yaw)))))
    (if (< right 0) -1 1)))

(defun flank-taken-p (creature point)
  "True if another creature already flanks toward a point near POINT."
  (loop for c across *creatures*
        thereis (and (not (eq c creature)) (flanking c) (path c)
                     (let ((end (car (last (path c)))))
                       (< (+ (expt (- (vx end) (vx point)) 2) (expt (- (vz end) (vz point)) 2))
                          (* 1.5 1.5))))))

(defun flank (creature)
  "Walk round the player's raised shield, if CREATURE FLANKS, may again, is near and in
front of it: along an arc to where it strikes past the shield, on the side it is on,
or the other if someone else already makes for that one. One creature flanks each side:
with both taken it doesn't. True if it set off."
  (when (and (flanks creature)
             (<= (flank-timer creature) 0)
             (< (player-distance creature) *flank-range*)
             (shield-facing-p *player* (location creature) *flank-margin*)
             *nav-grid*)
    (let* ((*nav-bodies* (standing-bodies creature))
           (*nav-body-mask* (nav-body-mask *nav-bodies* (body-radius creature)))
           (radius (+ (body-radius creature) *player-radius*
                      (* *attack-start-reach* (attack-reach creature))))
           (side (let ((side (flank-side creature)))
                   (cond ((not (flank-taken-p creature (flank-target creature side radius))) side)
                         ((not (flank-taken-p creature (flank-target creature (- side) radius))) (- side))
                         (T (return-from flank NIL)))))
           (feet (feet *player*))
           (loc (ground-point creature))
           (from (atan (- (vx loc) (vx feet)) (- (vz feet) (vz loc))))
           (to (flank-yaw side))
           ;; The short way round from where it stands to the flank.
           (turn (- (mod (+ (- to from) pi) (* 2 pi)) pi))
           (out (max radius (player-distance creature)))
           (r (body-radius creature))
           (h (sprite-height creature))
           (step (step-height creature))
           (points (loop for i from 1 to *flank-steps*
                         for yaw = (+ from (* turn (/ i *flank-steps*)))
                         for d = (if (= i *flank-steps*) radius out)
                         collect (vec (+ (vx feet) (* d (sin yaw))) (vy loc) (- (vz feet) (* d (cos yaw)))))))
      (when (loop for a = loc then b
                  for b in points
                  always (nav-line-clear-p a b r h step))
        (setf (path creature) points
              (brain creature) :walking
              (flanking creature) T
              (flank-timer creature) *flank-cooldown*)
        T))))

(defun hunt (creature)
  "Attack the player if within reach, or set off along a fresh path toward them."
  (cond ((special-attack creature))
        ((ranged-p creature) (hunt-from-range creature))
        ((flank creature))
        ((player-within-p creature (* *attack-start-reach* (attack-reach creature)))
         (start-attack creature))
        (T (chase creature))))

(defun attack-hit-time (creature)
  (loop for time in (attack-frame-times creature)
        repeat (attack-hit-frame creature)
        sum time))

(defun winding-up-p (creature)
  "True while CREATURE's attack has yet to land: the moment a shield bash interrupts it."
  (and (eq (brain creature) :attacking)
       (attack-pending creature)
       (attack-time creature)
       (< (attack-time creature) (attack-hit-time creature))))

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

(defgeneric release-attack (creature)
  (:documentation "Land CREATURE's attack, on its ATTACK-HIT-FRAME: cast its spell, or
strike the player if still in reach and in front of it.")
  (:method ((creature creature))
    (cond ((attack-spell creature)
           (release-attack-spell creature))
          ((and (player-within-p creature (attack-reach creature))
                (< (player-angle creature) (attack-arc creature))
                (clear-path-p (location creature) (feet *player*) 1.0))
           (hurt-player *player* (roll (attack-damage creature)) (location creature)
                        :guard-break (guard-break creature) :by creature)))))

(defgeneric face-attack-target (creature dt)
  (:documentation "Turn CREATURE through an attack's wind-up toward what it attacks.")
  (:method ((creature creature) dt) (face-player creature dt)))

(defun attack (creature dt)
  (let ((time (incf (attack-time creature) dt))
        (times (attack-frame-times creature)))
    ;; It turns to follow its target through the wind-up (a caster, until it casts);
    ;; after that the blow is committed.
    (when (< time (if (ranged-p creature) (attack-hit-time creature) (first times)))
      (face-attack-target creature dt))
    (when (and (attack-pending creature) (<= (attack-hit-time creature) time))
      (setf (attack-pending creature) NIL)
      (release-attack creature))
    (when (<= (reduce #'+ times) time)
      (stop-walking creature (attack-pause creature)))))

(defgeneric attack-step (creature dt)
  (:documentation "Run DT seconds of CREATURE's attack: a blow or a cast (ATTACK), or a
flyer's dive.")
  (:method ((creature creature) dt) (attack creature dt)))

(defun think (creature dt)
  "Hunt the player while alert, wander otherwise."
  (when (attacker-p creature)
    (notice-player creature dt))
  (let ((hunting (hunting-p creature)))
    (ecase (brain creature)
      (:attacking
       (attack-step creature dt))
      (:idle
       (when hunting
         (face-player creature dt))
       (when (<= (decf (idle-timer creature) dt) 0)
         (if hunting (hunt creature) (plan-wander creature))))
      (:walking
       ;; A flank is over once the shield no longer faces it: lowered, or got past.
       (when (and (flanking creature) (not (shield-facing-p *player* (location creature))))
         (setf (flanking creature) NIL
               (replan-timer creature) 0.0))
       (cond ((and hunting (not (ranged-p creature)) (not (flanking creature))
                   (player-within-p creature (* *attack-start-reach* (attack-reach creature))))
              (start-attack creature))
             (T
              ;; A flank walks its arc to the end, then hunts afresh.
              (when (and hunting (not (flanking creature)) (<= (decf (replan-timer creature) dt) 0))
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
  (clear-whirl creature)
  (setf (alert creature) 0.0
        (bleeding creature) 0f0
        (gibbed creature) NIL
        (rising creature) 0.0
        (stirring creature) 0.0)
  (stop-walking creature)
  (setf (walk-distance creature) 0.0)
  (setf (dead creature) NIL
        (health creature) (max-health creature)
        (stagger creature) 0.0
        (brace creature) 0.0
        (flash creature) 0.0
        (texture creature) (body-texture creature))
  (v<- (location creature) (home creature))
  (let ((kb (momentum creature)))
    (setf (vx kb) 0.0 (vz kb) 0.0)))

(defun creature-walking-p (creature)
  (and (eq (brain creature) :walking) (not (dead creature)) (walk-animation creature)))

(defgeneric flinch-p (creature)
  (:documentation "True if CREATURE's pose lets it show its flinch when hit: not a flyer
lying knocked down, which squashes its own pose instead.")
  (:method ((creature creature)) T))

(defun creature-hurting-p (creature)
  (and (< 0 (stagger creature)) (not (dead creature)) (hurt-animation creature) (flinch-p creature)))

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
         (h (* (size-scale creature) (animation-size animation)))
         (scale (scaling creature)))
    (setf (texture creature) (animation-texture animation))
    (strip-uv (frame-uv creature) atlas (+ (* (view-index creature) cycle) (mod frame cycle))
              count (mirrored creature))
    (setf (vx scale) (* h (/ (getf atlas :cell-width) (getf atlas :cell-height)) (+ 1 (* squash *stagger-squash* 0.7)))
          (vy scale) (* h (- 1 (* squash *stagger-squash*))))))

(defun show-front-frame (creature name frame squash)
  "Show FRAME of animation NAME whatever the view, as a death strip is shown. SQUASH is
the flinch, 0 to 1."
  (let* ((animation (find-fx-animation name))
         (atlas (animation-atlas animation))
         (h (* (size-scale creature) (animation-size animation)))
         (scale (scaling creature)))
    (setf (texture creature) (animation-texture animation))
    (strip-uv (frame-uv creature) atlas frame (getf atlas :frames))
    (setf (vx scale) (* h (/ (getf atlas :cell-width) (getf atlas :cell-height)) (+ 1 (* squash *stagger-squash* 0.7)))
          (vy scale) (* h (- 1 (* squash *stagger-squash*))))))

(defun show-rising (creature)
  "Show CREATURE getting up where it was raised: its death played backwards, or without
one, growing up out of the floor."
  (let* ((duration (death-duration creature))
         (k (max 0.0 (min 1.0 (- 1 (/ (rising creature) duration)))))
         (name (death-animation creature)))
    (if name
        (let ((count (getf (animation-atlas (find-fx-animation name)) :frames)))
          (show-front-frame creature name (- count 1 (min (1- count) (floor (* k count)))) 0.0))
        (setf (vy (scaling creature)) (* (vy (base-scaling creature)) (max 0.02 k))))))

(defgeneric show-own-pose (creature squash)
  (:documentation "Show a pose of CREATURE's own kind (a flyer's wingbeat and dive) with
SHOW-VIEW-FRAME, and return true; or NIL to show the walk or the standing pose. Comes
after the flinch, block and attack.")
  (:method ((creature creature) squash)
    (declare (ignore squash))
    NIL))

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
    (cond ((and (< 0 (rising creature)) (not (dead creature)))
           (show-rising creature))
          ((creature-hurting-p creature)
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
          ((show-own-pose creature s))
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
                    (h (* (size-scale creature) (animation-size animation))))
               (setf (texture creature) (animation-texture animation))
               (strip-uv (frame-uv creature) atlas (min (1- count) (floor (* d (animation-fps animation)))) count)
               (setf (vx scale) (* h (/ (getf atlas :cell-width) (getf atlas :cell-height)))
                     (vy scale) h)
               (stir creature)))
            ;; A death pose of its own kind (a flyer reuses its knockdown).
            ((show-own-pose creature 0.0))
            (T
             ;; Collapse into the floor, darkening, then stay flat until revived.
             (let ((k (max 0.02 (- 1 (/ d *death-time*)))))
               (setf (vy scale) (* (vy base) k)
                     (vx tint) 0.1 (vy tint) 0.0 (vz tint) 0.0 (vw tint) (- 1 k))))))))

(defun stir (creature)
  "Twitch CREATURE's corpse while it is STIRRING: something is raising it."
  (when (< 0 (stirring creature))
    (let ((scale (scaling creature))
          (k (* 0.06 (sin (* 47.0 (stirring creature))))))
      (setf (vx scale) (* (vx scale) (+ 1 k))
            (vy scale) (* (vy scale) (- 1 (* 0.5 k)))))))

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
           (remove-lamp lamp)
           (setf (death-lamp creature) NIL)))))

;; :AFTER so BILLBOARD's tick handler (view selection) still runs.
(define-handler (creature tick :after) (dt)
  (unless (frozen-p)
    (let ((dt (min dt 0.05)))
      (setf (flash creature) (max 0.0 (- (flash creature) dt))
            (stagger creature) (max 0.0 (- (stagger creature) dt))
            (brace creature) (max 0.0 (- (brace creature) dt))
            (bash-poise creature) (max 0.0 (- (bash-poise creature) dt))
            (flank-timer creature) (max 0.0 (- (flank-timer creature) dt))
            (slot-ban-timer creature) (max 0.0 (- (slot-ban-timer creature) dt))
            (stirring creature) (max 0.0 (- (stirring creature) dt)))
      (when (and (slot-bans creature) (<= (slot-ban-timer creature) 0))
        (setf (slot-bans creature) ()))
      ;; Held or thrown by a vortex, it moves and thinks no other way.
      (let ((held (whirl-step creature dt)))
        (unless held
          (update-footing creature)
          (slide creature dt))
        (drip-blood creature dt)
        (unless (or held (dead creature))
          ;; Lava burns, and deep water drowns, what is in it.
          (let* ((loc (location creature))
                 (afloat (afloat-p creature))
                 (damage (if afloat
                             *creature-drown-damage*
                             (hazard-at (vx loc) (+ (vy loc) 0.05) (vz loc)))))
            (multiple-value-bind (timer due) (burn-due (burn-timer creature) dt damage)
              (setf (burn-timer creature) timer)
              (when (< 0 due)
                (burn creature due)))
            (when (and (< 0 damage) (not afloat) (not (dead creature)) (eq (brain creature) :idle))
              (escape-liquid creature))
            (unless (dead creature)
              (cond ((< 0 (rising creature))
                     (decf (rising creature) dt))
                    ((< 0 (stagger creature)))
                    ((dormant-p creature))
                    (afloat
                     (flounder creature dt))
                    (T
                     (let ((*nav-hazards* (nav-hazards creature)))
                       (think creature dt)))))))
        (unless held
          (keep-height creature dt))
        (when (dead creature)
          (incf (dead creature) dt)
          (when (and *revive-time* (eq *level* :test) (not (stays-dead-p creature))
                     (< (+ (death-duration creature) *revive-time*) (dead creature))
                     ;; Wait for whoever stands on its spawn point to move.
                     (let ((home (home creature)))
                       (not (body-overlapping (vx home) (+ (vy home) 0.05) (vz home)
                                              (float (body-radius creature) 0f0)
                                              (- (float (sprite-height creature) 0f0) 0.05)
                                              creature))))
            (revive creature))))))
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
   (atlas :initform (read-atlas "sprites/imp/turnaround.lisp"))
   (sprite-height :initform *imp-height*)
   (death-animation :initform 'imp-death)
   (walk-animation :initform 'imp-walk)
   (attack-animation :initform 'imp-attack)
   (hurt-animation :initform 'imp-hurt)
   ;; Its own head and tail, then flesh: two arms, two legs, ribs, an organ, a big
   ;; chunk, two chunks, two scraps.
   (gibs :initform '((:imp (:head 0) 3) (:flesh 0 0 1 1 2 4 5 6 6 7 7)))
   (attack-damage :initform '(6 10))
   (chase-speed :initform 2.6)
   ;; Quick and small: it darts round a raised shield.
   (flanks :initform T)
   (pain-chance :initform 60)
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
   (atlas :initform (read-atlas "sprites/acolyte/turnaround.lisp"))
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
   (pain-chance :initform 50)
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
   (atlas :initform (read-atlas "sprites/knight/turnaround.lisp"))
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
   ;; The mace beats a raised shield aside.
   (guard-break :initform 0.8)
   (walk-speed :initform 0.9)
   (chase-speed :initform 1.4)
   (wander-radius :initform 2.0)
   ;; Flesh from inside the plate, drawn bigger for its size. No single blow overkills
   ;; 60 health by the usual fraction, so it tears apart more easily.
   (gibs :initform '((:flesh 0 0 1 1 2 3 4 5 5 6 6 7 7)))
   (gib-scale :initform 1.3)
   (gib-overkill :initform 0.15)
   ;; Plate and a steady stance: most blows don't stagger it.
   (pain-chance :initform 15)
   (max-health :initform 60)))
